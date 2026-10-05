//
//  TVScrubArrowInput.swift
//  Lume
//
//  tvOS ←/→ press tracker for timeline scrubbing. Owns short-step vs hold-rate
//  preview so SwiftUI `onMoveCommand` / CEC relays cannot double-apply nudges.
//

#if os(tvOS)

    import Foundation
    import QuartzCore
    import SwiftUI
    import UIKit

    /// Arms while compact live OSD is up or classic scrub is active. Left/right
    /// UIPress began/ended drive `TVScrubArrowSession`; MoveCommand / CEC pulses
    /// use `TVCECScrubRepeatTracker` so key-repeat can ramp like a Siri hold.
    @MainActor
    final class TVScrubArrowInput {
        static let shared = TVScrubArrowInput()

        /// When true, the window observer claims left/right presses for scrub.
        private(set) var isEnabled = false
        /// True between Siri-style UIPress began and ended/cancelled — MoveCommand
        /// left/right must no-op while this is set to avoid double steps.
        private(set) var isPressActive = false
        /// True while a CEC/MoveCommand hold ramp is driving the scrub session.
        private(set) var isCECHoldActive = false

        var onShortStep: ((TVScrubArrowDirection) -> Void)?
        /// Hold crossed the threshold — caller must cancel auto-commit.
        var onHoldStarted: ((TVScrubArrowDirection) -> Void)?
        /// Continuous preview delta in *video* seconds (signed).
        var onHoldDelta: ((TimeInterval) -> Void)?
        /// Hold finished or watchdog fired — caller should seek immediately.
        var onHoldEnded: (() -> Void)?

        private var session = TVScrubArrowSession()
        private var cecTracker = TVCECScrubRepeatTracker()
        private var tickTask: Task<Void, Never>?
        private var cecSilenceTask: Task<Void, Never>?
        private var isObserving = false
        fileprivate weak var activeRecognizer: UIGestureRecognizer?

        private init() {}

        /// True while either a physical UIPress or a CEC hold owns ←/→.
        var isArrowSessionActive: Bool { isPressActive || isCECHoldActive }

        func setEnabled(_ enabled: Bool) {
            guard isEnabled != enabled else { return }
            isEnabled = enabled
            if !enabled {
                forceStop(scheduleCommit: false)
            }
        }

        func forceStop(scheduleCommit: Bool) {
            stopTickLoop()
            cancelCECSilenceTimer()
            cecTracker.cancel()
            isCECHoldActive = false
            let decision = session.cancel()
            isPressActive = false
            if let recognizer = activeRecognizer,
               recognizer.state == .began || recognizer.state == .changed
            {
                recognizer.state = .cancelled
            }
            activeRecognizer = nil
            if scheduleCommit, case .holdEnded = decision {
                onHoldEnded?()
            }
        }

        /// MoveCommand or CEC UIPress pulse while no Siri UIPress is down.
        /// Returns `true` when the caller must not apply its own short step.
        @discardableResult
        func handleNonPressCommand(_ direction: TVScrubArrowDirection) -> Bool {
            guard isEnabled else { return false }
            if isPressActive { return true }

            let now = CACurrentMediaTime()
            switch cecTracker.notePulse(direction, at: now) {
            case .ignore:
                return true
            case let .shortStep(dir):
                onShortStep?(dir)
                restartCECSilenceTimer()
                return true
            case let .startHold(dir):
                beginCECHold(direction: dir, at: now)
                restartCECSilenceTimer()
                return true
            case let .continueHold:
                restartCECSilenceTimer()
                return true
            }
        }

        fileprivate func observePresses(in window: UIWindow) {
            guard !isObserving else { return }
            isObserving = true
            let observer = ScrubArrowPressObserver()
            observer.allowedPressTypes = [
                UIPress.PressType.leftArrow, .rightArrow
            ].map { NSNumber(value: $0.rawValue) }
            window.addGestureRecognizer(observer)
        }

        fileprivate func handlePressBegan(
            _ direction: TVScrubArrowDirection,
            recognizer: UIGestureRecognizer
        ) {
            guard isEnabled else { return }
            // Abandon any CEC pulse stream — Siri UIPress owns the session now.
            abandonCECTrackingWithoutCommit()
            let now = CACurrentMediaTime()
            switch session.begin(direction, at: now) {
            case .ignore:
                return
            case .replaced:
                // Opposite arrow restarts acceleration from the hold start rate;
                // do not commit the previous hold — preview keeps moving.
                stopTickLoop()
                isPressActive = true
                activeRecognizer = recognizer
                startTickLoop()
            case .armed:
                isPressActive = true
                activeRecognizer = recognizer
                startTickLoop()
            }
        }

        fileprivate func handlePressEnded() {
            guard isEnabled || isPressActive else { return }
            let now = CACurrentMediaTime()
            stopTickLoop()
            let decision = session.end(at: now)
            isPressActive = false
            activeRecognizer = nil
            switch decision {
            case let .shortStep(direction):
                onShortStep?(direction)
                // Seed dedupe so a trailing MoveCommand twin does not step again.
                cecTracker.noteExternalPulse(direction, at: now)
            case let .holdEnded(direction):
                onHoldEnded?()
                cecTracker.noteExternalPulse(direction, at: now)
            case .ignore:
                break
            }
        }

        /// CEC-synthesised arrow press: do not claim began/ended (ended is often
        /// missing). Feed the same pulse driver as MoveCommand instead.
        fileprivate func handleCECPulse(_ direction: TVScrubArrowDirection) {
            _ = handleNonPressCommand(direction)
        }

        private func beginCECHold(direction: TVScrubArrowDirection, at now: TimeInterval) {
            stopTickLoop()
            // Drop any prior armed session without seeking, then start already
            // past the hold threshold so the first tick emits holdStarted.
            _ = session.cancel()
            _ = session.begin(direction, at: now - TVScrubArrowSession.holdThreshold)
            isCECHoldActive = true
            isPressActive = false
            activeRecognizer = nil
            // Emit holdStarted before the tick loop so auto-commit is cancelled
            // before the first rate delta.
            processTick(at: now)
            startTickLoop()
        }

        private func abandonCECTrackingWithoutCommit() {
            cancelCECSilenceTimer()
            cecTracker.cancel()
            if isCECHoldActive {
                stopTickLoop()
                _ = session.cancel()
                isCECHoldActive = false
            }
        }

        private func restartCECSilenceTimer() {
            cancelCECSilenceTimer()
            let gap = TVCECScrubRepeatTracker.releaseGap
            cecSilenceTask = Task { @MainActor in
                let ns = UInt64(gap * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                self.handleCECSilence()
            }
        }

        private func cancelCECSilenceTimer() {
            cecSilenceTask?.cancel()
            cecSilenceTask = nil
        }

        private func handleCECSilence() {
            let decision = cecTracker.noteSilence(at: CACurrentMediaTime())
            switch decision {
            case .ignore:
                break
            case .holdEnded:
                stopTickLoop()
                _ = session.end(at: CACurrentMediaTime())
                isCECHoldActive = false
                onHoldEnded?()
            }
        }

        private func startTickLoop() {
            stopTickLoop()
            tickTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 16_666_667) // ~60 Hz
                    guard !Task.isCancelled else { return }
                    self.processTick(at: CACurrentMediaTime())
                }
            }
        }

        private func stopTickLoop() {
            tickTask?.cancel()
            tickTask = nil
        }

        private func processTick(at now: TimeInterval) {
            switch session.tick(at: now) {
            case let .holdStarted(direction):
                onHoldStarted?(direction)
            case let .holdTick(_, videoDelta):
                onHoldDelta?(videoDelta)
            case .forceEnd:
                stopTickLoop()
                cancelCECSilenceTimer()
                cecTracker.cancel()
                isCECHoldActive = false
                isPressActive = false
                if let recognizer = activeRecognizer,
                   recognizer.state == .began || recognizer.state == .changed
                {
                    recognizer.state = .cancelled
                }
                activeRecognizer = nil
                onHoldEnded?()
            case .ignore:
                break
            }
        }
    }

    /// Window-level observer that claims left/right while scrub arrows are armed
    /// so `pressesEnded` is delivered (unlike the surf observer, which fails
    /// immediately on began). CEC synthesised presses are *not* claimed — they
    /// lack a reliable ended and are fed to the pulse/repeat driver instead.
    private final class ScrubArrowPressObserver: UIGestureRecognizer {
        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            super.pressesBegan(presses, with: event)
            guard TVScrubArrowInput.shared.isEnabled else {
                state = .failed
                return
            }
            for press in presses {
                guard let direction = Self.direction(for: press.type) else { continue }
                if Self.looksLikeCEC(press) {
                    TVScrubArrowInput.shared.handleCECPulse(direction)
                    state = .failed
                    return
                }
                TVScrubArrowInput.shared.handlePressBegan(direction, recognizer: self)
                state = .began
                return
            }
            state = .failed
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            super.pressesEnded(presses, with: event)
            if presses.contains(where: { $0.type == .leftArrow || $0.type == .rightArrow }) {
                TVScrubArrowInput.shared.handlePressEnded()
            }
            state = .ended
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            super.pressesCancelled(presses, with: event)
            if presses.contains(where: { $0.type == .leftArrow || $0.type == .rightArrow }) {
                TVScrubArrowInput.shared.handlePressEnded()
            }
            state = .cancelled
        }

        private static func direction(for type: UIPress.PressType) -> TVScrubArrowDirection? {
            switch type {
            case .leftArrow: .left
            case .rightArrow: .right
            default: nil
            }
        }

        /// Same heuristic as the surf observer: CEC presses often report ~0 force.
        private static func looksLikeCEC(_ press: UIPress) -> Bool {
            press.force < 0.01
        }
    }

    /// Zero-size probe that attaches the scrub arrow observer once per window.
    struct TVScrubArrowInputProbe: UIViewRepresentable {
        func makeUIView(context _: Context) -> ProbeView { ProbeView() }
        func updateUIView(_: ProbeView, context _: Context) {}

        final class ProbeView: UIView {
            override func didMoveToWindow() {
                super.didMoveToWindow()
                guard let window else { return }
                TVScrubArrowInput.shared.observePresses(in: window)
            }
        }
    }

#endif
