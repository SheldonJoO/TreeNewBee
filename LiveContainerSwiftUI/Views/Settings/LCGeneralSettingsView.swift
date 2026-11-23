//
//  LCGeneralSettingsView.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  TreeApps「管理」分类下的通用设置聚合页 —— 收纳界面、行为、
//  JIT 方式、32 位模拟器等细项开关。视觉沿用 openSSS Shell 风格。
//

import Foundation
import SwiftUI

struct LCGeneralSettingsView: View {
    @AppStorage("LCFrameShortcutIcons") var frameShortIcon = false
    @AppStorage("LCSwitchAppWithoutAsking") var silentSwitchApp = false
    @AppStorage("LCOpenWebPageWithoutAsking") var silentOpenWebPage = false
    @AppStorage("LCDontSignApp", store: LCUtils.appGroupUserDefault) var dontSignApp = false
    @AppStorage("LCStrictHiding", store: LCUtils.appGroupUserDefault) var strictHiding = false
    @AppStorage("dynamicColors", store: LCUtils.appGroupUserDefault) var dynamicColors = true
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false

    @AppStorage("LCSideJITServerAddress", store: LCUtils.appGroupUserDefault) var sideJITServerAddress: String = ""
    @AppStorage("LCDeviceUDID", store: LCUtils.appGroupUserDefault) var deviceUDID: String = ""
    @AppStorage("LCJITEnablerType", store: LCUtils.appGroupUserDefault) var JITEnabler: JITEnablerType = .SideJITServer

    @AppStorage("LCSelected32BitEmulator", store: LCUtils.appGroupUserDefault) var selected32BitEmulator: String = ""

    @EnvironmentObject private var sharedModel: SharedModel

    var body: some View {
        Form {
            // 外观
            Section {
                NavigationLink {
                    LCLanguageSettingsView()
                } label: {
                    TreeSettingsRow(icon: "globe", title: "语言",
                                    value: TreeLanguageManager.shared.current.title, color: TreeAppsTheme.accent)
                }
                NavigationLink {
                    LCAppearanceSettingsView()
                } label: {
                    TreeSettingsRow(icon: "paintbrush.fill", title: "主题管理",
                                    value: "模式 · 强调色", color: TreeAppsTheme.accent)
                }
                Toggle(isOn: $dynamicColors) {
                    Text("lc.settings.dynamicColors".loc)
                }
                if #available(iOS 18.0, *) {
                    Toggle(isOn: $darkModeIcon) {
                        Text("lc.settings.darkModeIcon".loc)
                    }
                }
                Toggle(isOn: $frameShortIcon) {
                    Text("lc.settings.FrameIcon".loc)
                }
            } header: {
                Text("外观与主题")
            } footer: {
                Text("lc.settings.dynamicColors.desc".loc)
            }

            // App 行为
            Section {
                Toggle(isOn: $silentSwitchApp) {
                    Text("lc.settings.silentSwitchApp".loc)
                }
                Toggle(isOn: $silentOpenWebPage) {
                    Text("lc.settings.silentOpenWebPage".loc)
                }
                Toggle(isOn: $dontSignApp) {
                    Text("lc.settings.dontSign".loc)
                }
                if sharedModel.isHiddenAppUnlocked {
                    Toggle(isOn: $strictHiding) {
                        Text("lc.settings.strictHiding".loc)
                    }
                }
            } header: {
                Text("App 行为")
            } footer: {
                Text("lc.settings.silentSwitchAppDesc".loc)
            }

            // 多任务（TreeApps: 从设置主页并入通用管理）
            if #available(iOS 16.1, *) {
                Section {
                    NavigationLink {
                        LCMultitaskSettingView()
                    } label: {
                        TreeSettingsRow(icon: "macwindow.on.rectangle", title: "多任务", value: "虚拟窗口 / 独立窗口", color: TreeAppsTheme.accent)
                    }
                } header: {
                    Text("多任务")
                }
            }

            // JIT 方式
            Section {
                if JITEnabler == .SideJITServer || JITEnabler == .JITStreamerEBLegacy {
                    HStack {
                        Text("lc.settings.JitAddress".loc)
                        Spacer()
                        TextField(JITEnabler == .SideJITServer ? "http://x.x.x.x:8080" : "http://[fd00::]:9172", text: $sideJITServerAddress)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if JITEnabler == .SideJITServer {
                    HStack {
                        Text("lc.settings.JitUDID".loc)
                        Spacer()
                        TextField("", text: $deviceUDID)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Picker(selection: $JITEnabler) {
                    ForEach(JITEnablerType.allCases) { enablerType in
                        Text(enablerType.displayName).tag(enablerType)
                    }
                } label: {
                    Text("lc.settings.jitEnabler".loc)
                }
            } header: {
                Text("JIT 方式")
            } footer: {
                Text("lc.settings.JitDesc".loc)
            }

            // 32 位模拟器
            Section {
                Picker(selection: $selected32BitEmulator) {
                    ForEach(sharedModel.arm32EmuApps, id: \.self) { app in
                        Text("lc.common.none".loc).tag("")
                        Text(app.appInfo.displayName()).tag(app.appInfo.relativeBundlePath!)
                    }
                } label: {
                    Text("lc.settings.selected32BitEmulator".loc)
                }
            } header: {
                Text("32 位模拟器")
            }
        }
        .navigationTitle("通用设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
