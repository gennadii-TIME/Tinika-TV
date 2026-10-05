//
//  TVCompactOSDNavRelay.swift
//  Lume
//
//  Optional bridge for compact-OSD ←/→ while chrome is visible. Live ↑/↓ no
//  longer enter here — window UIPress/CEC twins share `handleChannelSurfInput`
//  with MoveCommand so a surf cannot flip into NavRelay and re-arm the hide
//  timer after the OSD was (incorrectly) raised.
//

#if os(tvOS)

    import SwiftUI

    @MainActor
    final class TVCompactOSDNavRelay {
        static let shared = TVCompactOSDNavRelay()

        /// Overlay registers while compact OSD chrome is on screen.
        var onArrow: ((MoveCommandDirection) -> Void)?

        private init() {}

        func handleArrow(_ direction: MoveCommandDirection) {
            onArrow?(direction)
        }
    }

#endif
