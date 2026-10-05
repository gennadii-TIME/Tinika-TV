//
//  TVCECScrubRepeatTracker.swift
//  Lume
//
//  Maps HDMI-CEC ←/→ key-repeat pulses (MoveCommand / discrete UIPress) onto
//  the same short-step → hold-ramp model as a continuous Siri Remote press.
//  Pure value logic so unit tests run on iOS Simulator.
//

import Foundation

/// Tracks a CEC-style ←/→ pulse stream that lacks a reliable press-ended.
///
/// Physical sequence on many Samsung HDMI-CEC remotes:
/// 1. First left/right pulse → one short step (same as a Siri swipe)
/// 2. Further pulses in the same direction within `promoteGap` → promote to hold
/// 3. Silence longer than `releaseGap` while holding → hold ended (seek)
///
/// Siri Remote click-hold never enters this tracker: that path owns a real
/// UIPress began/ended session and ignores MoveCommand while the press is down.
nonisolated struct TVCECScrubRepeatTracker: Equatable, Sendable {
    /// Max gap between the first pulse and the next before we treat the stream
    /// as a held key and start the 10→60 ramp.
    nonisolated static let promoteGap: TimeInterval = 0.55
    /// Silence after the last hold pulse that means the key was released.
    nonisolated static let releaseGap: TimeInterval = 0.45
    /// Collapse MoveCommand + CEC UIPress twins for one physical click.
    nonisolated static let pulseDedupeWindow: TimeInterval = 0.12

    private enum Phase: Equatable, Sendable {
        case idle
        case armed(direction: TVScrubArrowDirection, at: TimeInterval)
        case holding(direction: TVScrubArrowDirection)
    }

    private var phase: Phase = .idle
    private var lastPulseAt: TimeInterval?
    private var lastPulseDirection: TVScrubArrowDirection?

    nonisolated var isHolding: Bool {
        if case .holding = phase { return true }
        return false
    }

    nonisolated var isTracking: Bool {
        phase != .idle
    }

    nonisolated var activeDirection: TVScrubArrowDirection? {
        switch phase {
        case .idle: nil
        case let .armed(direction, _): direction
        case let .holding(direction): direction
        }
    }

    nonisolated enum PulseDecision: Equatable, Sendable {
        case ignore
        /// First pulse of a stream — caller applies one short step.
        case shortStep(TVScrubArrowDirection)
        /// Second+ pulse: start continuous hold (cancel short-step auto-commit).
        case startHold(TVScrubArrowDirection)
        /// Further pulses while already holding — keep the silence timer alive.
        case continueHold(TVScrubArrowDirection)
    }

    nonisolated enum SilenceDecision: Equatable, Sendable {
        case ignore
        case holdEnded(TVScrubArrowDirection)
    }

    /// One left/right pulse from MoveCommand or a CEC-synthesised UIPress.
    nonisolated mutating func notePulse(
        _ direction: TVScrubArrowDirection,
        at now: TimeInterval
    ) -> PulseDecision {
        if let lastAt = lastPulseAt,
           let lastDir = lastPulseDirection,
           lastDir == direction,
           now - lastAt < Self.pulseDedupeWindow
        {
            return .ignore
        }
        lastPulseAt = now
        lastPulseDirection = direction

        switch phase {
        case .idle:
            phase = .armed(direction: direction, at: now)
            return .shortStep(direction)

        case let .armed(current, started):
            if current != direction {
                phase = .armed(direction: direction, at: now)
                return .shortStep(direction)
            }
            if now - started <= Self.promoteGap {
                phase = .holding(direction: direction)
                return .startHold(direction)
            }
            // Gap was too long for a hold promote — treat as a fresh tap.
            phase = .armed(direction: direction, at: now)
            return .shortStep(direction)

        case let .holding(current):
            if current != direction {
                phase = .holding(direction: direction)
                return .startHold(direction)
            }
            return .continueHold(direction)
        }
    }

    /// No pulse arrived for `releaseGap` while holding.
    nonisolated mutating func noteSilence(at _: TimeInterval) -> SilenceDecision {
        switch phase {
        case let .holding(direction):
            phase = .idle
            lastPulseAt = nil
            lastPulseDirection = nil
            return .holdEnded(direction)
        case .armed:
            // Short step already applied; drop the watch without another seek.
            phase = .idle
            lastPulseAt = nil
            lastPulseDirection = nil
            return .ignore
        case .idle:
            return .ignore
        }
    }

    /// Collapse a trailing MoveCommand twin after a UIPress already applied the
    /// short step / hold end — keeps phase idle but records the pulse time.
    nonisolated mutating func noteExternalPulse(
        _ direction: TVScrubArrowDirection,
        at now: TimeInterval
    ) {
        lastPulseAt = now
        lastPulseDirection = direction
    }

    /// UIPress began / surf / disable — abandon without emitting holdEnded.
    nonisolated mutating func cancel() {
        phase = .idle
        lastPulseAt = nil
        lastPulseDirection = nil
    }
}
