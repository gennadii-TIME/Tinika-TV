//
//  TVTimedMuteCornerIndicator.swift
//  Lume
//
//  Persistent top-trailing HUD while TimedMuteController is active. Stays up
//  with the OSD hidden; informational only — no focus, no press handling.
//

#if os(tvOS)

    import SwiftUI

    /// Compact mute countdown pinned to the top-trailing corner of the player.
    struct TVTimedMuteCornerIndicator: View {
        @ObservedObject var timedMute: TimedMuteController

        var body: some View {
            if timedMute.isMuted, let seconds = timedMute.remainingSeconds, seconds >= 0 {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 22, weight: .semibold))
                    Text(Self.countdownLabel(seconds))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 36)
                .padding(.trailing, 40)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Muted"))
                .accessibilityValue(Text(Self.countdownLabel(seconds)))
                .transition(.opacity)
            }
        }

        /// `0:59` / `1:00` — minutes unpadded, seconds always two digits.
        static func countdownLabel(_ totalSeconds: Int) -> String {
            let clamped = max(0, totalSeconds)
            return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
        }
    }

#endif
