//
//  InterfaceLanguageListView.swift
//  Lume
//
//  Checkmark list of the 10 supported interface languages. Native language
//  names (English, Deutsch, Русский, …). Select applies and dismisses; cancel /
//  back leaves the stored language unchanged.
//

import SwiftUI

#if os(tvOS)

    /// tvOS drill-in pane for Interface → Language.
    struct TVInterfaceLanguageList: View {
        @Binding var selectionRaw: String
        var onClose: () -> Void

        @FocusState private var focusedLanguage: AppInterfaceLanguage?

        private var current: AppInterfaceLanguage {
            AppInterfaceLanguage.resolve(selectionRaw)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 28) {
                Text("Language")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                VStack(alignment: .leading, spacing: 8) {
                    TVSettingsSectionLabel("Language")

                    VStack(spacing: 2) {
                        ForEach(AppInterfaceLanguage.allCases) { language in
                            Button {
                                selectionRaw = language.rawValue
                                AppInterfaceLanguage.set(language)
                                onClose()
                            } label: {
                                HStack(spacing: 16) {
                                    Text(verbatim: language.nativeDisplayName)
                                    Spacer(minLength: 0)
                                    if current == language {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 24, weight: .semibold))
                                    }
                                }
                            }
                            .buttonStyle(TVSettingsRowButtonStyle())
                            .focused($focusedLanguage, equals: language)
                        }
                    }

                    Text("Default is English. The whole app uses the language you choose, including after restart.")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .defaultFocus($focusedLanguage, current)
            .onExitCommand(perform: onClose)
        }
    }

#endif

#if !os(tvOS)

    /// iOS / macOS NavigationLink destination: radio list of interface languages.
    struct InterfaceLanguageListView: View {
        @Binding var selectionRaw: String
        @Environment(\.dismiss) private var dismiss

        private var current: AppInterfaceLanguage {
            AppInterfaceLanguage.resolve(selectionRaw)
        }

        var body: some View {
            List {
                Section {
                    ForEach(AppInterfaceLanguage.allCases) { language in
                        Button {
                            selectionRaw = language.rawValue
                            AppInterfaceLanguage.set(language)
                            dismiss()
                        } label: {
                            HStack {
                                Text(verbatim: language.nativeDisplayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if current == language {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Default is English. The whole app uses the language you choose, including after restart.")
                }
            }
            .platformNavigationTitle("Language")
            #if os(macOS)
                .formStyle(.grouped)
            #endif
        }
    }

#endif
