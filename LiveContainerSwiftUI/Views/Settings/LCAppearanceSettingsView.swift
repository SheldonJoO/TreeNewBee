//
//  LCAppearanceSettingsView.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  主题管理：外观模式（跟随系统 / 浅色 / 深色）+ 强调色（预置色板 / 自定义）。
//  所有配置写入 App Group UserDefaults，多开实例与宿主保持一致。
//

import SwiftUI

struct LCAppearanceSettingsView: View {
    @AppStorage("LCAppearanceMode", store: LCUtils.appGroupUserDefault)
    private var appearanceMode = 0

    @AppStorage("LCCustomAccentHex", store: LCUtils.appGroupUserDefault)
    private var accentHex = TreeAppsTheme.defaultAccentHex

    private let presets: [(name: String, hex: String)] = [
        ("openSSS Teal", "#19D3B5"),
        ("Sky Blue", "#409EFF"),
        ("Indigo", "#5E6AD2"),
        ("Violet", "#9B59B6"),
        ("Rose", "#FF5E84"),
        ("Amber", "#FF9500"),
        ("Mint", "#34C759"),
        ("Slate", "#8E8E93")
    ]

    var body: some View {
        Form {
            // 外观模式
            Section {
                Picker("外观模式", selection: $appearanceMode) {
                    ForEach(TreeAppearanceMode.allCases) { mode in
                        HStack(spacing: 8) {
                            Image(systemName: mode.icon)
                            Text(mode.title)
                        }
                        .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("外观模式")
            } footer: {
                Text("跟随系统会随 iOS 的深浅色自动切换；选择浅色或深色则强制固定。")
            }

            // 强调色
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 12)], spacing: 14) {
                    ForEach(presets, id: \.hex) { preset in
                        Button {
                            accentHex = preset.hex
                            TreeAppsTheme.applyToKeyWindow()
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex) ?? TreeAppsTheme.teal)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            accentHex.caseInsensitiveCompare(preset.hex) == .orderedSame
                                                ? (Color(hex: preset.hex) ?? TreeAppsTheme.teal)
                                                : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
                .padding(.vertical, 4)

                ColorPicker("自定义强调色", selection: Binding(
                    get: { Color(hex: accentHex) ?? TreeAppsTheme.teal },
                    set: { newColor in
                        accentHex = newColor.hexString
                        TreeAppsTheme.applyToKeyWindow()
                    }
                ))
            } header: {
                Text("强调色")
            } footer: {
                Text("当前 \(accentHex.uppercased())。强调色作用于按钮、图标、选中态与系统控件。")
            }

            // 恢复默认
            Section {
                Button {
                    accentHex = TreeAppsTheme.defaultAccentHex
                    appearanceMode = TreeAppearanceMode.system.rawValue
                    TreeAppsTheme.applyToKeyWindow()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("恢复默认（openSSS Teal · 跟随系统）")
                    }
                    .foregroundStyle(TreeAppsTheme.accent)
                }
            }
        }
        .navigationTitle("主题管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}
