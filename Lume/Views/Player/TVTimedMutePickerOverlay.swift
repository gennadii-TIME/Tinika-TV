//
//  TVTimedMutePickerOverlay.swift
//  Lume
//
//  tvOS timed-mute picker raised by long-press Select while the OSD is
//  hidden. Focus stays inside the menu; Menu/Back dismisses without applying.
//
//  The hidden-OSD catcher is a UIKit focus host (same pattern as EPGFocusStrip):
//  SwiftUI `.focusable()` on top of a UIViewRepresentable steals Select presses
//  so `pressesBegan` never arms the session and long-press appears dead.
//

#if os(tvOS)

    import SwiftUI
    import UIKit

    /// Full-screen picker for `TimedMuteController` presets (1…5 min) plus Unmute
    /// when a timer is already running.
    struct TVTimedMutePickerOverlay: View {
        @ObservedObject var timedMute: TimedMuteController
        let applyMute: (Bool) -> Void
        let onDismiss: () -> Void
        /// When false, rows stay visible but do not take focus — used until the
        /// opening Select is released so key-repeat cannot auto-commit "1 min".
        var allowsFocus: Bool = true

        private enum Choice: Hashable {
            case unmute
            case minutes(Int)
        }

        @FocusState private var focus: Choice?

        var body: some View {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)

                VStack(spacing: 22) {
                    Text("Timed Mute")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)

                    if timedMute.isMuted {
                        pickerButton(
                            title: String(localized: "Unmute"),
                            systemImage: "speaker.wave.2.fill",
                            choice: .unmute
                        ) {
                            timedMute.unmute(apply: applyMute)
                            onDismiss()
                        }
                    }

                    ForEach(TimedMuteController.presetMinutes, id: \.self) { minutes in
                        pickerButton(
                            title: nil,
                            minutes: minutes,
                            systemImage: "speaker.slash.fill",
                            choice: .minutes(minutes)
                        ) {
                            timedMute.mute(forMinutes: minutes, apply: applyMute)
                            onDismiss()
                        }
                    }
                }
                .padding(.horizontal, 72)
                .padding(.vertical, 48)
                .background {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        }
                }
            }
            .onChange(of: allowsFocus) { _, allowed in
                if allowed {
                    focus = timedMute.isMuted ? .unmute : .minutes(1)
                } else {
                    focus = nil
                }
            }
            .onAppear {
                if allowsFocus {
                    focus = timedMute.isMuted ? .unmute : .minutes(1)
                }
            }
            .onExitCommand {
                onDismiss()
            }
        }

        @ViewBuilder
        private func pickerButton(
            title: String?,
            minutes: Int? = nil,
            systemImage: String,
            choice: Choice,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Label {
                    if let title {
                        Text(title)
                    } else if let minutes {
                        Text(String(format: String(localized: "%lld min"), minutes))
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
                .font(.system(size: 28, weight: .medium))
                .frame(maxWidth: 520, alignment: .leading)
            }
            .buttonStyle(TVGlassButtonStyle())
            .focused($focus, equals: choice)
            .disabled(!allowsFocus)
        }
    }

    /// Hidden-OSD tap catcher: short Select summons controls; long Select opens
    /// the timed-mute picker once. UIKit owns focus (not SwiftUI `.focusable`)
    /// so Select presses reach the recognisers. Directional clicks/swipes use
    /// edge sentinels + arrow presses — a bare full-bleed view has no focus
    /// neighbours, so `shouldUpdateFocus` alone never fired (←/→ died).
    struct TVPlayerHiddenOSDCatcher: View {
        var isEnabled: Bool
        var allowsLiveTVChrome: Bool
        var isLive: Bool
        /// When true, directional presses must not open browser / EPG / surf.
        var blocksDirectionalRemote: Bool
        var focus: FocusState<Bool>.Binding
        var onShowControls: () -> Void
        var onLongSelect: () -> Void
        /// Select released after a long-press that opened the mute menu.
        var onLongSelectReleased: () -> Void
        var onOpenChannelBrowser: () -> Void
        var onOpenProgramGuide: () -> Void
        var onChannelSurf: (MoveCommandDirection) -> Void

        var body: some View {
            TVSelectPressCatcherRepresentable(
                isEnabled: isEnabled,
                isFocused: focus,
                blocksDirectionalRemote: blocksDirectionalRemote,
                allowsLiveTVChrome: allowsLiveTVChrome,
                isLive: isLive,
                onShowControls: onShowControls,
                onLongSelect: onLongSelect,
                onLongSelectReleased: onLongSelectReleased,
                onOpenChannelBrowser: onOpenChannelBrowser,
                onOpenProgramGuide: onOpenProgramGuide,
                onChannelSurf: onChannelSurf
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Arms the window arrow-press observer used when swipes are off.
            .background(TVRemoteDirectionProbeHost())
        }
    }

    /// Exposes the private probe from `TVRemoteDirectionInput` via the public
    /// `tvRemoteMoveCommand` helper without consuming moves (UIKit owns them).
    private struct TVRemoteDirectionProbeHost: View {
        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .tvRemoteMoveCommand { _ in }
        }
    }

    // MARK: - UIKit Select / long-Select / arrows

    struct TVSelectPressCatcherRepresentable: UIViewRepresentable {
        var isEnabled: Bool
        var isFocused: FocusState<Bool>.Binding
        var blocksDirectionalRemote: Bool
        var allowsLiveTVChrome: Bool
        var isLive: Bool
        var onShowControls: () -> Void
        var onLongSelect: () -> Void
        var onLongSelectReleased: () -> Void
        var onOpenChannelBrowser: () -> Void
        var onOpenProgramGuide: () -> Void
        var onChannelSurf: (MoveCommandDirection) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> TVSelectPressCatcherUIView {
            let view = TVSelectPressCatcherUIView()
            view.coordinator = context.coordinator
            context.coordinator.view = view
            return view
        }

        func updateUIView(_ uiView: TVSelectPressCatcherUIView, context: Context) {
            let coordinator = context.coordinator
            coordinator.isFocused = isFocused
            coordinator.onShowControls = onShowControls
            coordinator.onLongSelect = onLongSelect
            coordinator.onLongSelectReleased = onLongSelectReleased
            coordinator.onOpenChannelBrowser = onOpenChannelBrowser
            coordinator.onOpenProgramGuide = onOpenProgramGuide
            coordinator.onChannelSurf = onChannelSurf
            coordinator.blocksDirectionalRemote = blocksDirectionalRemote
            coordinator.allowsLiveTVChrome = allowsLiveTVChrome
            coordinator.isLive = isLive
            uiView.isCatcherEnabled = isEnabled
            // SwiftUI asked us to take focus (OSD hid / menu closed).
            if isEnabled, isFocused.wrappedValue, !uiView.isFocused {
                DispatchQueue.main.async {
                    uiView.setNeedsFocusUpdate()
                    uiView.updateFocusIfNeeded()
                }
            }
        }

        final class Coordinator {
            var session = TVSelectPressSession()
            weak var view: TVSelectPressCatcherUIView?
            var isFocused: FocusState<Bool>.Binding?
            var onShowControls: (() -> Void)?
            var onLongSelect: (() -> Void)?
            var onLongSelectReleased: (() -> Void)?
            var onOpenChannelBrowser: (() -> Void)?
            var onOpenProgramGuide: (() -> Void)?
            var onChannelSurf: ((MoveCommandDirection) -> Void)?
            var blocksDirectionalRemote = false
            var allowsLiveTVChrome = false
            var isLive = false
            /// Dedupes arrow `pressesBegan` against the matching focus-move veto.
            private var lastMoveAt: TimeInterval = 0
            private var lastMoveDirection: MoveCommandDirection?

            func handleTap() {
                switch session.shortSelect() {
                case .showControls:
                    onShowControls?()
                case .ignore:
                    break
                }
            }

            func handleLongBegan() {
                switch session.recogniseLongPress() {
                case .openMuteMenu:
                    onLongSelect?()
                case .ignore:
                    break
                }
            }

            func handlePressBegan() {
                session.beginSelect()
            }

            func handlePressEnded() {
                switch session.endSelect() {
                case .focusMuteMenu:
                    onLongSelectReleased?()
                case .ignore:
                    break
                }
            }

            /// Arrow click delivered to the focused catcher (`pressesBegan`).
            func handleArrowPress(_ direction: MoveCommandDirection) {
                guard !blocksDirectionalRemote else { return }
                noteMove(direction)
                dispatchMove(direction)
            }

            /// Focus-engine move (touchpad swipe / sentinel proposal).
            func handleFocusMove(_ direction: MoveCommandDirection) {
                guard !blocksDirectionalRemote else { return }
                if let last = lastMoveDirection,
                   last == direction,
                   CACurrentMediaTime() - lastMoveAt < 0.2
                {
                    return
                }
                let perform: () -> Void = { [weak self] in
                    self?.noteMove(direction)
                    self?.dispatchMove(direction)
                }
                if PlayerSettings.tvRemoteSwipesEnabled {
                    perform()
                } else {
                    TVRemoteDirectionInput.shared.handleMove(direction, perform: perform)
                }
            }

            private func noteMove(_ direction: MoveCommandDirection) {
                lastMoveAt = CACurrentMediaTime()
                lastMoveDirection = direction
            }

            private func dispatchMove(_ direction: MoveCommandDirection) {
                if allowsLiveTVChrome, direction == .left {
                    onOpenChannelBrowser?()
                } else if allowsLiveTVChrome, direction == .right {
                    onOpenProgramGuide?()
                } else if isLive, direction == .up || direction == .down {
                    onChannelSurf?(direction)
                } else {
                    onShowControls?()
                }
            }

            func noteFocusChange(_ focused: Bool) {
                Task { @MainActor in
                    isFocused?.wrappedValue = focused
                }
            }
        }
    }

    /// Focusable full-bleed press target with edge sentinels so every arrow
    /// direction has a focus candidate (EPGFocusStrip pattern). Without them
    /// `shouldUpdateFocus` never runs on a solitary full-screen host.
    final class TVSelectPressCatcherUIView: UIView {
        weak var coordinator: TVSelectPressCatcherRepresentable.Coordinator?
        var isCatcherEnabled = true {
            didSet {
                isUserInteractionEnabled = isCatcherEnabled
                if oldValue != isCatcherEnabled {
                    setNeedsFocusUpdate()
                }
            }
        }

        private var longPressFired = false
        private var moveConsumed = false
        private var sentinels: [MoveCommandDirection: SentinelView] = [:]

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Near-invisible but non-zero: fully transparent views are dropped
            // from the focus engine's directional candidacy.
            backgroundColor = UIColor.white.withAlphaComponent(0.01)
            isUserInteractionEnabled = true

            for direction: MoveCommandDirection in [.up, .down, .left, .right] {
                let sentinel = SentinelView()
                sentinel.owner = self
                sentinels[direction] = sentinel
                addSubview(sentinel)
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            addGestureRecognizer(tap)

            let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLong(_:)))
            long.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            // Same threshold as EPGFocusStrip — 0.55 felt dead on device with
            // competing SwiftUI focus hosts.
            long.minimumPressDuration = 0.4
            addGestureRecognizer(long)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var canBecomeFocused: Bool {
            isCatcherEnabled
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let inset: CGFloat = 4
            sentinels[.up]?.frame = CGRect(x: inset, y: 0, width: bounds.width - 2 * inset, height: inset)
            sentinels[.down]?.frame = CGRect(
                x: inset, y: bounds.height - inset, width: bounds.width - 2 * inset, height: inset
            )
            sentinels[.left]?.frame = CGRect(x: 0, y: inset, width: inset, height: bounds.height - 2 * inset)
            sentinels[.right]?.frame = CGRect(
                x: bounds.width - inset, y: inset, width: inset, height: bounds.height - 2 * inset
            )
        }

        override func didUpdateFocus(
            in context: UIFocusUpdateContext,
            with coordinator: UIFocusAnimationCoordinator
        ) {
            super.didUpdateFocus(in: context, with: coordinator)
            if context.nextFocusedView === self {
                self.coordinator?.noteFocusChange(true)
            } else if context.previouslyFocusedView === self {
                self.coordinator?.noteFocusChange(false)
            }
        }

        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            guard isCatcherEnabled, isFocused, context.previouslyFocusedView === self else {
                return true
            }
            if moveConsumed { return false }
            guard let direction = Self.direction(from: context.focusHeading) else {
                return true
            }
            moveConsumed = true
            Task { @MainActor in
                self.moveConsumed = false
                self.coordinator?.handleFocusMove(direction)
            }
            // Keep focus on the catcher; overlays / surf are raised in-place.
            return false
        }

        private static func direction(from heading: UIFocusHeading) -> MoveCommandDirection? {
            switch heading {
            case .up: .up
            case .down: .down
            case .left: .left
            case .right: .right
            default: nil
            }
        }

        private static func direction(fromPressType type: UIPress.PressType) -> MoveCommandDirection? {
            switch type {
            case .upArrow: .up
            case .downArrow: .down
            case .leftArrow: .left
            case .rightArrow: .right
            default: nil
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if presses.contains(where: { $0.type == .select }) {
                coordinator?.handlePressBegan()
                super.pressesBegan(presses, with: event)
                return
            }
            // Arrow clicks: handle as actions (browser / EPG / surf). Consuming
            // avoids a focus walk; swipes still arrive via shouldUpdateFocus.
            for press in presses {
                if let direction = Self.direction(fromPressType: press.type) {
                    coordinator?.handleArrowPress(direction)
                    return
                }
            }
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if presses.contains(where: { $0.type == .select }) {
                coordinator?.handlePressEnded()
            }
            super.pressesEnded(presses, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if presses.contains(where: { $0.type == .select }) {
                coordinator?.handlePressEnded()
            }
            super.pressesCancelled(presses, with: event)
        }

        @objc private func handleTap() {
            // EPG pattern: long-press also delivers a trailing Select tap.
            if longPressFired {
                longPressFired = false
                return
            }
            coordinator?.handleTap()
        }

        @objc private func handleLong(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            longPressFired = true
            coordinator?.handleLongBegan()
        }

        /// Proposal target the catcher vetoes onto — never actually focused.
        /// Only a candidate while the catcher itself holds focus.
        final class SentinelView: UIView {
            weak var owner: TVSelectPressCatcherUIView?

            override init(frame: CGRect) {
                super.init(frame: frame)
                backgroundColor = UIColor.white.withAlphaComponent(0.01)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var canBecomeFocused: Bool {
                owner?.isCatcherEnabled == true && owner?.isFocused == true
            }
        }
    }

#endif
