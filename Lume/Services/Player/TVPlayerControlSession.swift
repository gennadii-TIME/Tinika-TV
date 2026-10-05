//
//  TVPlayerControlSession.swift
//  Lume
//
//  Exclusive control-flow phases for the tvOS live / timeshift player.
//  Exactly one phase is active; all rewind / OSD / return-to-live actions
//  must transition through this session so handlers cannot race.
//

import Combine
import Foundation
import OSLog
import SwiftUI

/// Mutually exclusive player-control phases. Playback kind (live URL vs
/// timeshift URL) is reflected by `.live` / `.timeshift`; interaction is
/// `.controls` / `.scrubPreview` / `.seeking` / `.returningToLive`.
enum TVPlayerControlPhase: String, Equatable, Sendable {
    case live
    case controls
    case scrubPreview
    case seeking
    case timeshift
    case returningToLive
}

/// Serialises OSD / scrub / seek / return-to-live for one player session.
@MainActor
final class TVPlayerControlSession: ObservableObject {
    @Published private(set) var phase: TVPlayerControlPhase = .live
    /// Wall-clock preview while `phase == .scrubPreview`. Never triggers a
    /// media reload on its own.
    @Published private(set) var previewAbsoluteTime: Date?
    /// How many times this session asked the host to swap `PlayableMedia`.
    @Published private(set) var mediaReloadCount = 0
    /// Preview nudges since the last `beginScrub` (diagnostics / tests).
    @Published private(set) var previewMoveCount = 0
    /// Bumped when idle ←/→ debounce expires — overlay commits exactly once.
    @Published private(set) var autoCommitToken = 0

    private(set) var wasPlayingBeforeScrub = false
    private(set) var scrubTarget: TimeInterval = 0
    /// Last trusted on-screen absolute time. Seeded from the committed scrub
    /// target in `finishSeek`, then advanced by trusted engine playheads while
    /// idle. Used so a stale post-rebuild `clock.current` cannot yank the next
    /// scrub session to the live edge.
    private(set) var playheadAnchorAbsolute: Date?
    /// Wall-clock moment when `playheadAnchorAbsolute` was last trusted/seeded —
    /// advances the fallback while the engine playhead is still untrusted.
    private var playheadAnchorWallDate: Date?
    /// Fires after ~600 ms without further ←/→ to auto-confirm the preview.
    private var scrubAutoCommitTask: Task<Void, Never>?

    /// Idle gap before auto-confirm (within the 500–700 ms window).
    static let autoCommitDelayNanoseconds: UInt64 = 600_000_000

    /// Bumped on every new seek / cancel so stale async work cannot swap media.
    private var seekGeneration = 0
    private var seekTask: Task<Void, Never>?
    /// Select / auto-commit gate — at most one commit owns the pipeline.
    private var commitInFlight = false
    /// Timeshift clip may auto-return to live at most once until `resetForNewStream`.
    private var autoReturnConsumed = false

    var isScrubbing: Bool { phase == .scrubPreview }
    var isSeekInFlight: Bool { phase == .seeking || phase == .returningToLive }
    var isCommitInFlight: Bool { commitInFlight }
    /// Menu should cancel the current action instead of hiding OSD / closing.
    var capturesMenu: Bool {
        switch phase {
        case .scrubPreview, .seeking, .returningToLive: true
        case .live, .controls, .timeshift: false
        }
    }

    /// Channel surf is legal on a clean picture **or** with compact OSD up.
    /// Blocked while lists/menus own focus (host `hasOpenPanel`), while a scrub
    /// preview/commit is still armed (host cancels first), and during seek /
    /// return-to-live until `cancelSeek` / settle.
    func allowsChannelSurf(controlsVisible: Bool, mediaIsLive: Bool) -> Bool {
        guard mediaIsLive else { return false }
        _ = controlsVisible
        switch phase {
        case .live, .timeshift, .controls:
            return true
        case .scrubPreview, .seeking, .returningToLive:
            return false
        }
    }

    /// Cancel scrub preview and/or in-flight seek so ↑/↓ can surf while the
    /// compact OSD stays visible. Does not reload media.
    @discardableResult
    func prepareChannelSurfWhileOSDVisible(mediaIsCatchup: Bool) -> Bool {
        if phase == .scrubPreview {
            _ = cancelScrub()
        }
        if phase == .seeking || phase == .returningToLive {
            _ = cancelSeek(mediaIsCatchup: mediaIsCatchup)
        }
        // Land on `.controls` when OSD is meant to stay up.
        if phase == .live || phase == .timeshift {
            _ = transition(to: .controls, reason: "surf-keep-osd")
        }
        return allowsChannelSurf(controlsVisible: true, mediaIsLive: true)
    }

    func allowsTogglePlay() -> Bool {
        // Compact OSD Select toggles play even while a scrub preview is armed;
        // never during an in-flight commit / seek / return-to-live (avoids a
        // Pause race with media reload).
        guard !commitInFlight else { return false }
        switch phase {
        case .seeking, .returningToLive: return false
        case .scrubPreview, .live, .controls, .timeshift: return true
        }
    }

    /// After the viewer toggles play during scrub preview, keep auto-commit's
    /// post-seek resume desire in sync so Pause is not undone by the seek.
    func notePlaybackDesireDuringPreview(isPlaying: Bool) {
        guard phase == .scrubPreview else { return }
        wasPlayingBeforeScrub = isPlaying
    }

    // MARK: - Phase sync from host / media

    /// Call when OSD opens. Idempotent.
    func noteControlsOpened(mediaIsCatchup: Bool) {
        switch phase {
        case .live, .timeshift:
            transition(to: .controls, reason: "osd-open")
        case .controls, .scrubPreview, .seeking, .returningToLive:
            break
        }
        // Catchup with OSD open still reports controls while idle.
        _ = mediaIsCatchup
    }

    /// Call when OSD hides. Lands on `.live` or `.timeshift` from the URL kind.
    func noteControlsClosed(mediaIsCatchup: Bool) {
        guard phase == .controls || phase == .scrubPreview else {
            // Seeking keeps OSD pinned; ignore a spurious hide.
            if phase == .seeking || phase == .returningToLive { return }
            syncPlaybackPhase(mediaIsCatchup: mediaIsCatchup)
            return
        }
        cancelScrubChrome()
        // Leave `.controls` / scrub explicitly — `syncPlaybackPhase` intentionally
        // keeps `.controls` while OSD is still considered open.
        transition(to: mediaIsCatchup ? .timeshift : .live, reason: "osd-close")
    }

    /// Align phase with the media currently playing (after a swap settles).
    func syncPlaybackPhase(mediaIsCatchup: Bool) {
        switch phase {
        case .seeking, .returningToLive, .scrubPreview:
            // Wait for the in-flight action to finish.
            return
        case .controls:
            return
        case .live, .timeshift:
            let next: TVPlayerControlPhase = mediaIsCatchup ? .timeshift : .live
            if phase != next {
                transition(to: next, reason: "media-sync")
            }
        }
    }

    /// After a successful media swap that completed seeking / returning.
    func noteMediaReloadSettled(mediaIsCatchup: Bool, keepControls: Bool) {
        previewAbsoluteTime = nil
        if keepControls {
            transition(to: .controls, reason: "seek-settled-controls")
        } else {
            transition(to: mediaIsCatchup ? .timeshift : .live, reason: "seek-settled")
        }
    }

    // MARK: - Scrub preview

    /// Absolute time currently being watched — idle knob + new scrub anchor.
    func viewedAbsoluteDate(
        media: PlayableMedia,
        playerTime: TimeInterval,
        now: Date = Date()
    ) -> Date {
        let fallback: Date? = {
            guard let anchor = playheadAnchorAbsolute else { return nil }
            guard let wall = playheadAnchorWallDate else { return anchor }
            // While the engine still reports a stale playhead after a URL
            // rebuild, advance the committed seek target by wall-clock so a
            // 20 s watch does not restart scrub at the original seek point.
            let elapsed = max(0, now.timeIntervalSince(wall))
            return min(anchor.addingTimeInterval(elapsed), now)
        }()

        let trusted = isEnginePlayheadTrusted(
            media: media,
            playerTime: playerTime,
            now: now
        )
        let date: Date
        if trusted, let start = media.archiveWindowStart {
            let t = playerTime.isFinite ? max(0, playerTime) : 0
            date = start.addingTimeInterval(t)
        } else if trusted {
            date = LiveTimeshift.absolutePlaybackDate(media: media, playerTime: playerTime, now: now)
        } else {
            // Do *not* call LiveTimeshift.viewedAbsoluteDate here — its trust
            // check is only the archive window, so an in-window leftover
            // (~3500 s after an hour-back seek) would be accepted again.
            date = fallback ?? media.archiveWindowStart
                ?? LiveTimeshift.absolutePlaybackDate(media: media, playerTime: 0, now: now)
        }

        // Freeze the anchor while scrubbing / seeking so the preview origin and
        // the committed seek target are not overwritten by a live clock tick.
        if trusted, !isScrubbing, !isSeekInFlight {
            playheadAnchorAbsolute = date
            playheadAnchorWallDate = now
        }
        return date
    }

    /// Engine playhead is usable only when it sits inside the archive window
    /// *and* stays coherent with wall-clock progress from the last trusted
    /// anchor. A post-rebuild sample of ~3500 s inside a 1-hour window is
    /// "in range" but still jumps the knob toward the live edge.
    private func isEnginePlayheadTrusted(
        media: PlayableMedia,
        playerTime: TimeInterval,
        now: Date
    ) -> Bool {
        guard LiveTimeshift.isPlayerTimeTrusted(media: media, playerTime: playerTime, now: now)
        else { return false }
        guard let start = media.archiveWindowStart,
              let anchor = playheadAnchorAbsolute,
              let wall = playheadAnchorWallDate
        else {
            // No anchor yet (first open): only accept a near-start playhead so a
            // leftover live sample cannot become the first "trusted" point.
            guard media.archiveWindowStart != nil else { return true }
            return playerTime.isFinite && playerTime >= 0 && playerTime <= 30
        }
        let expected = max(0, anchor.timeIntervalSince(start)) + max(0, now.timeIntervalSince(wall))
        // Jumped far ahead of real-time progress (typical stale/live leftover).
        if playerTime > expected + 30 { return false }
        // Stuck far behind while wall-clock moved — keep wall-advanced fallback.
        if expected > 5, playerTime + 15 < expected { return false }
        return true
    }

    @discardableResult
    func beginScrub(
        absolute: Date,
        windowStart: Date?,
        playerTime: TimeInterval,
        isPlaying: Bool
    ) -> Bool {
        guard phase == .controls || phase == .live || phase == .timeshift else {
            // Already scrubbing: keep the existing preview so a second ←/→
            // continues from the nudged target rather than snapping back.
            if phase == .scrubPreview { return true }
            return false
        }
        LiveTimeshiftDiagnostics.resetScrubCounters()
        previewMoveCount = 0
        wasPlayingBeforeScrub = isPlaying
        previewAbsoluteTime = absolute
        playheadAnchorAbsolute = absolute
        playheadAnchorWallDate = Date()
        if let windowStart {
            scrubTarget = absolute.timeIntervalSince(windowStart)
        } else {
            scrubTarget = playerTime.isFinite ? playerTime : 0
        }
        return transition(to: .scrubPreview, reason: "begin-scrub")
    }

    func applyPreviewDelta(
        _ delta: TimeInterval,
        clamp: (Date) -> Date,
        windowStart: Date?
    ) {
        guard phase == .scrubPreview, !commitInFlight else { return }
        let current = previewAbsoluteTime ?? Date()
        let next = clamp(current.addingTimeInterval(delta))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            previewAbsoluteTime = next
            if let windowStart {
                scrubTarget = next.timeIntervalSince(windowStart)
            }
        }
        previewMoveCount += 1
        LiveTimeshiftDiagnostics.noteScrubPreviewMove(
            previewUTC: Int(next.timeIntervalSince1970)
        )
    }

    /// Fixed short-press scrub step (10 s). Continuous hold is driven by
    /// `TVScrubArrowInput` with a 10→60 ramp; each short step reschedules the
    /// idle auto-commit debounce.
    func noteScrubStep(
        direction _: RemoteDirectionGate.Direction,
        absoluteTimeline _: Bool
    ) -> TimeInterval {
        guard phase == .scrubPreview, !commitInFlight else { return 0 }
        scheduleAutoCommit()
        return TVScrubArrowSession.shortStepSeconds
    }

    /// Hold released — cancel any pending idle debounce. The overlay commits
    /// the preview immediately (no 600 ms wait).
    func noteHoldEnded() {
        guard phase == .scrubPreview else { return }
        cancelAutoCommit()
    }

    /// Suppress auto-commit for the duration of an arrow hold.
    func noteHoldStarted() {
        cancelAutoCommit()
    }

    /// Call after a relative preview nudge that did not go through `noteScrubStep`
    /// (e.g. fixed −15 / +15) so idle still auto-confirms.
    func notePreviewNudged() {
        guard phase == .scrubPreview else { return }
        scheduleAutoCommit()
    }

    /// Cancel pending auto-confirm (Select commit, Menu cancel, new seek).
    func cancelAutoCommit() {
        scrubAutoCommitTask?.cancel()
        scrubAutoCommitTask = nil
    }

    private func scheduleAutoCommit() {
        guard phase == .scrubPreview else { return }
        scrubAutoCommitTask?.cancel()
        scrubAutoCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoCommitDelayNanoseconds)
            guard !Task.isCancelled, phase == .scrubPreview else { return }
            autoCommitToken += 1
        }
    }

    func setVODScrubTarget(_ target: TimeInterval) {
        guard phase == .scrubPreview else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrubTarget = target }
    }

    /// Menu during scrub — discard preview, stay on OSD.
    @discardableResult
    func cancelScrub() -> Bool {
        guard phase == .scrubPreview else { return false }
        cancelScrubChrome()
        commitInFlight = false
        return transition(to: .controls, reason: "cancel-scrub")
    }

    // MARK: - ScrubCommitPipeline

    enum CommitSource: String, Sendable {
        case select
        case autoCommit
    }

    /// Single entry for Select and auto-commit. Returns `false` when a commit
    /// is already in flight or preview is not active.
    @discardableResult
    func tryBeginCommit(source: CommitSource) -> Bool {
        guard phase == .scrubPreview else { return false }
        guard !commitInFlight else { return false }
        commitInFlight = true
        cancelAutoCommit()
        Logger.player.info(
            "control-session tryBeginCommit source=\(source.rawValue, privacy: .public)"
        )
        return true
    }

    /// Arm / consume the one-shot end-of-clip return-to-live for a timeshift session.
    @discardableResult
    func tryConsumeAutoReturnToLive() -> Bool {
        guard !autoReturnConsumed else { return false }
        autoReturnConsumed = true
        return true
    }

    // MARK: - Seek / return-to-live

    /// Starts a single seek generation. Cancels any previous in-flight seek and
    /// waits for it to unwind so at most one `perform` body runs at a time.
    func runSeek(
        reason: String,
        asReturnToLive: Bool = false,
        perform: @escaping @MainActor (_ generation: Int) async -> Void
    ) async {
        seekGeneration += 1
        let generation = seekGeneration
        let previous = seekTask
        previous?.cancel()
        // Keep `previewAbsoluteTime` / `scrubTarget` pinned through the seek so
        // the OSD knob stays on the chosen point until `finishSeek` / `failSeek`.
        cancelAutoCommit()
        let next: TVPlayerControlPhase = asReturnToLive ? .returningToLive : .seeking
        transition(to: next, reason: reason)
        // Unwind the cancelled seek before starting the next — otherwise two
        // `perform` bodies can overlap briefly after `Task.cancel()`.
        await previous?.value
        guard seekGeneration == generation else {
            commitInFlight = false
            return
        }
        let task = Task { @MainActor in
            await perform(generation)
        }
        seekTask = task
        await task.value
        if seekGeneration == generation {
            commitInFlight = false
        }
    }

    /// Legacy fire-and-forget entry used by Menu cancel / tests.
    func beginSeek(
        reason: String,
        asReturnToLive: Bool = false,
        perform: @escaping @MainActor (_ generation: Int) async -> Void
    ) {
        Task { @MainActor in
            await runSeek(reason: reason, asReturnToLive: asReturnToLive, perform: perform)
        }
    }

    func isSeekGenerationCurrent(_ generation: Int) -> Bool {
        generation == seekGeneration
    }

    /// Host is about to call `onSelectMedia` — count exactly one reload.
    func noteMediaReload(reason: String) {
        mediaReloadCount += 1
        LiveTimeshiftDiagnostics.noteURLRebuild(
            reason: reason,
            startUTC: Int(Date().timeIntervalSince1970)
        )
        Logger.player.info(
            "control-session media-reload #\(self.mediaReloadCount, privacy: .public) phase=\(self.phase.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    /// Pin the OSD knob to `absolute` for an in-flight seek that did not come
    /// from scrub preview (Start Over / programme jump). `finishSeek` seeds the
    /// idle playhead anchor from this value.
    func pinSeekPreview(_ absolute: Date) {
        previewAbsoluteTime = absolute
    }

    func finishSeek(mediaIsCatchup: Bool, keepControls: Bool) {
        // Seed the idle playhead from the committed preview *before* clearing
        // it — the engine clock is often still stale for a moment after the
        // timeshift URL swap, and the next ←/→ must start from this point.
        if let preview = previewAbsoluteTime {
            playheadAnchorAbsolute = preview
            playheadAnchorWallDate = Date()
        }
        previewAbsoluteTime = nil
        commitInFlight = false
        if keepControls {
            transition(to: .controls, reason: "finish-seek-controls")
        } else {
            transition(to: mediaIsCatchup ? .timeshift : .live, reason: "finish-seek")
        }
    }

    func failSeek(mediaIsCatchup: Bool, keepControls: Bool) {
        previewAbsoluteTime = nil
        commitInFlight = false
        if keepControls {
            transition(to: .controls, reason: "fail-seek-controls")
        } else {
            transition(to: mediaIsCatchup ? .timeshift : .live, reason: "fail-seek")
        }
    }

    func finishReturnToLive(keepControls: Bool) {
        previewAbsoluteTime = nil
        playheadAnchorAbsolute = nil
        playheadAnchorWallDate = nil
        commitInFlight = false
        transition(to: keepControls ? .controls : .live, reason: "finish-return-live")
    }

    /// Menu during seeking — abandon in-flight work, keep current media.
    @discardableResult
    func cancelSeek(mediaIsCatchup: Bool) -> Bool {
        guard phase == .seeking || phase == .returningToLive else { return false }
        seekGeneration += 1
        seekTask?.cancel()
        seekTask = nil
        previewAbsoluteTime = nil
        commitInFlight = false
        return transition(
            to: mediaIsCatchup ? .timeshift : .controls,
            reason: "cancel-seek"
        )
    }

    func resetForNewStream(mediaIsCatchup: Bool) {
        seekGeneration += 1
        seekTask?.cancel()
        seekTask = nil
        cancelScrubChrome()
        previewAbsoluteTime = nil
        // Catchup/timeshift swaps seed the anchor from archive start once the
        // overlay sees the new media; live clears it.
        if !mediaIsCatchup {
            playheadAnchorAbsolute = nil
            playheadAnchorWallDate = nil
        }
        commitInFlight = false
        autoReturnConsumed = false
        transition(to: mediaIsCatchup ? .timeshift : .live, reason: "new-stream")
    }

    // MARK: - Transitions

    @discardableResult
    func transition(to next: TVPlayerControlPhase, reason: String) -> Bool {
        guard phase != next else { return true }
        guard Self.isAllowed(from: phase, to: next) else {
            Logger.player.error(
                "control-session blocked \(self.phase.rawValue, privacy: .public) → \(next.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
            )
            return false
        }
        Logger.player.info(
            "control-session \(self.phase.rawValue, privacy: .public) → \(next.rawValue, privacy: .public) reason=\(reason, privacy: .public)"
        )
        phase = next
        return true
    }

    /// Legal edges for the exclusive phase graph.
    nonisolated static func isAllowed(from: TVPlayerControlPhase, to: TVPlayerControlPhase) -> Bool {
        switch (from, to) {
        case (.live, .controls), (.live, .scrubPreview), (.live, .seeking),
             (.live, .timeshift), (.live, .returningToLive):
            return true
        case (.controls, .live), (.controls, .scrubPreview), (.controls, .seeking),
             (.controls, .timeshift), (.controls, .returningToLive):
            return true
        case (.scrubPreview, .controls), (.scrubPreview, .seeking),
             (.scrubPreview, .live), (.scrubPreview, .timeshift):
            return true
        case (.seeking, .controls), (.seeking, .timeshift), (.seeking, .live),
             (.seeking, .returningToLive):
            return true
        case (.timeshift, .controls), (.timeshift, .scrubPreview), (.timeshift, .seeking),
             (.timeshift, .returningToLive), (.timeshift, .live):
            return true
        case (.returningToLive, .live), (.returningToLive, .controls),
             (.returningToLive, .timeshift):
            return true
        default:
            return from == to
        }
    }

    private func cancelScrubChrome() {
        scrubAutoCommitTask?.cancel()
        scrubAutoCommitTask = nil
        previewAbsoluteTime = nil
    }
}
