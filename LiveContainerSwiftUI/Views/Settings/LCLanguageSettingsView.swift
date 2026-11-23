//
//  LCLanguageSettingsView.swift
//  LiveContainerSwiftUI (TreeNewBee)
//
//  语言切换二级页：宿主 TreeNewBee + 内置 openSSS 同时生效。
//

import SwiftUI

struct LCLanguageSettingsView: View {
    @State private var selected: TreeLanguage = TreeLanguageManager.shared.current
    @State private var showRestartTip = false

    private let languages = TreeLanguage.allCases

    var body: some View {
        Form {
            Section {
                Picker(selection: $selected) {
                    ForEach(languages) { lang in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.title)
                            Text(lang.localizedName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(lang)
                    }
                } label: {
                    Label("界面语言", systemImage: "globe")
                }
                .pickerStyle(.inline)
                .onChange(of: selected) { newLang in
                    TreeLanguageManager.shared.setLanguage(newLang)
                }
            } header: {
                Text("语言")
            } footer: {
                Text("切换后界面立即更新；内置 openSSS 会在下次打开时使用新语言。选择「跟随系统」则与系统语言一致。")
            }

            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(TreeAppsTheme.accent)
                    Text("当前语言：\(TreeLanguageManager.shared.current.title)")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("语言")
        .navigationBarTitleDisplayMode(.inline)
        .treeAppsTheme()
    }
}
