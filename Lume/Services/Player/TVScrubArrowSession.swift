//
//  TVScrubArrowSession.swift
//  Lume
//
//  Pure ←/→ press session for tvOS timeline scrubbing: short tap = one step,
//  hold past a threshold = continuous preview with a smooth rate ramp. No seek.
//

import Foundation

/// Direction of a timeline scrub arrow (subset of move commands).
nonisolated enum TVScrubArrowDirection: Equatable, Sendable {
    case left
    case right

    nonisolated var sign: Double {
        switch self {
        case .left: -1
        case .right: 1
        }
    }
}

/// Resolves short vs held ←/→ for scrub preview.
///
/// Timeline (seconds are wall/clock video seconds unless noted):
/// 1. Arrow down → arm
/// 2a. Up before `holdThreshold` → one `shortStepSeconds` nudge
/// 2b. Held past threshold → `holdStarted`, then `holdTick` with rate that
///     starts at `holdRateStart` and ramps to `holdRateMax` over
///     `holdRampDuration`, then stays flat until up → `holdEnded`
nonisolated struct TVScrubArrowSession: Equatable, Sendable {
    nonisolated static let holdThreshold: TimeInterval = 0.25
    /// Fixed short-press step (absolute and VOD).
    nonisolated static let shortStepSeconds: TimeInterval = 10
    /// Hold preview rate at the moment hold starts (video s per real s).
    nonisolated static let holdRateStart: TimeInterval = 10
    /// Hold preview rate after the ramp completes.
    nonisolated static let holdRateMax: TimeInterval = 60
    /// Real-time seconds to ramp from `holdRateStart` to `holdRateMax`.
    nonisolated static let holdRampDuration: TimeInterval = 3
    /// If `ended` never arrives, force-stop after this much hold time.
    nonisolated static let missingReleaseWatchdog: TimeInterval = 45

    /// Backward-compatible alias for the hold start rate.
    nonisolated static var holdRateVideoSecondsPerRealSecond: TimeInterval { holdRateStart }

    private(set) var direction: TVScrubArrowDirection?
    private(set) var pressStartedAt: TimeInterval?
    private(set) var holdStartedAt: TimeInterval?
    private(set) var isHolding = false
    private(set) var lastTickAt: TimeInterval?

    nonisolated var isPressActive: Bool { direction != nil }

    nonisolated enum BeginDecision: Equatable, Sendable {
        case armed
        case ignore
        /// Opposite arrow while one is down — end previous first (caller stops hold).
        case replaced(previous: TVScrubArrowDirection)
    }

    nonisolated enum EndDecision: Equatable, Sendable {
        case shortStep(TVScrubArrowDirection)
        case holdEnded(TVScrubArrowDirection)
        case ignore
    }

    nonisolated enum TickDecision: Equatable, Sendable {
        case holdStarted(TVScrubArrowDirection)
        /// `videoDelta` is signed media seconds for this tick (rate already applied).
        case holdTick(TVScrubArrowDirection, videoDelta: TimeInterval)
        case forceEnd(TVScrubArrowDirection)
        case ignore
    }

    /// Smooth hold rate: 10 → 60 over `holdRampDuration`, then flat at 60.
    nonisolated static func holdRate(holdElapsed: TimeInterval) -> TimeInterval {
        guard holdElapsed > 0 else { return holdRateStart }
        guard holdElapsed < holdRampDuration else { return holdRateMax }
        let progress = holdElapsed / holdRampDuration
        return holdRateStart + (holdRateMax - holdRateStart) * progress
    }

    nonisolated mutating func begin(_ direction: TVScrubArrowDirection, at now: TimeInterval) -> BeginDecision {
        if let current = self.direction {
            if current == direction { return .ignore }
            let previous = current
            resetPressBookkeeping()
            self.direction = direction
            pressStartedAt = now
            return .replaced(previous: previous)
        }
        self.direction = direction
        pressStartedAt = now
        holdStartedAt = nil
        isHolding = false
        lastTickAt = nil
        return .armed
    }

    nonisolated mutating func end(at now: TimeInterval) -> EndDecision {
        guard let direction, let started = pressStartedAt else { return .ignore }
        let held = isHolding
        let elapsed = now - started
        resetPressBookkeeping()
        if held { return .holdEnded(direction) }
        if elapsed < Self.holdThreshold { return .shortStep(direction) }
        // Released after threshold but before the first tick observed hold —
        // treat as a single short step so the press still does something.
        return .shortStep(direction)
    }

    nonisolated mutating func cancel() -> EndDecision {
        guard let direction else { return .ignore }
        let held = isHolding
        resetPressBookkeeping()
        return held ? .holdEnded(direction) : .ignore
    }

    /// Drive from a display-link / timer while a press may be active.
    nonisolated mutating func tick(at now: TimeInterval) -> TickDecision {
        guard let direction, let started = pressStartedAt else { return .ignore }
        let elapsed = now - started
        if elapsed >= Self.missingReleaseWatchdog {
            resetPressBookkeeping()
            return .forceEnd(direction)
        }
        if !isHolding {
            guard elapsed >= Self.holdThreshold else { return .ignore }
            isHolding = true
            holdStartedAt = now
            lastTickAt = now
            return .holdStarted(direction)
        }
        let last = lastTickAt ?? now
        let dt = max(0, now - last)
        lastTickAt = now
        guard dt > 0 else { return .ignore }
        let holdElapsed = now - (holdStartedAt ?? now)
        let rate = Self.holdRate(holdElapsed: holdElapsed)
        let videoDelta = direction.sign * dt * rate
        return .holdTick(direction, videoDelta: videoDelta)
    }

    private nonisolated mutating func resetPressBookkeeping() {
        direction = nil
        pressStartedAt = nil
        holdStartedAt = nil
        isHolding = false
        lastTickAt = nil
    }
}
