//
//  LCTreeWidgetSettingsView.swift
//  TreeNewBee —— 小组件 App 手动配置
//
//  列表直接来自 TreeWidgetSnapshotWriter.allCandidates()：
//  扫 TreeNewBee 安装 Guest App 的目录，再加一条「内置 openSSS」。
//  openSSS 侧载到桌面的 App 不属于这里。
//

import SwiftUI
import WidgetKit

struct LCTreeWidgetSettingsView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @State private var selected: Set<String> = []
    @State private var saved = false
    @State private var statusText = ""
    @State private var diagnosticText = ""
    @State private var scanned: [TreeWidgetScannedApp] = []

    private var appEntries: [(key: String, name: String)] {
        // 内置 openSSS 排在首位，可像普通 App 一样勾选 / 取消。
        // 点它时的中间闪屏由 TreeLaunchOverlay 品牌过渡页遮住。
        return scanned.map {
            ($0.bundleName, "\($0.name)\($0.isShared ? " · 共享" : "")")
        }
    }

    private func refreshDiagnostic() {
        scanned = TreeWidgetSnapshotWriter.allCandidates()
        diagnosticText = TreeWidgetSnapshotWriter.diagnostic()
    }

    private func save() {
        TreeWidgetSnapshotWriter.manualSelection = selected.sorted()
        let count = TreeWidgetSnapshotWriter.refresh(apps: sharedModel.apps,
                                                      hiddenApps: sharedModel.hiddenApps)
        WidgetCenter.shared.reloadAllTimelines()
        statusText = "已写入 \(count) 个 App，小组件已刷新"
        saved = true
        refreshDiagnostic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { saved = false }
    }

    var body: some View {
        Form {
            Section {
                Text("这里列出 TreeNewBee 里安装的 App（Documents/Applications 与共享容器/LiveContainer/Applications），以及首条「内置 openSSS」。\n勾选后点保存，桌面与锁屏小组件会立刻刷新。一个都不勾则自动显示全部（含 openSSS）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(appEntries, id: \.key) { entry in
                    Toggle(isOn: Binding(
                        get: { selected.contains(entry.key) },
                        set: { on in
                            if on { selected.insert(entry.key) } else { selected.remove(entry.key) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline)
                            Text(entry.key).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("可显示的小组件条目（\(scanned.count)）")
            } footer: {
                Text(scanned.isEmpty ? "⚠️ 没扫描到任何 .app。请确认 App 是装在 TreeNewBee 里，而不是用 openSSS 侧载到桌面的。" : "首条 openSSS 是合体包内置项；数据源为 TreeNewBee 扫盘，不含 openSSS 侧载到桌面的 App。")
                    .font(.caption2)
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        Text(saved ? "已保存" : "保存并刷新小组件")
                    }
                }
                if !statusText.isEmpty {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Button("清除选择（恢复自动显示全部）") {
                    selected = []
                    TreeWidgetSnapshotWriter.manualSelection = []
                    let count = TreeWidgetSnapshotWriter.refresh(apps: sharedModel.apps,
                                                                  hiddenApps: sharedModel.hiddenApps)
                    WidgetCenter.shared.reloadAllTimelines()
                    statusText = "已恢复自动模式，写入 \(count) 个 App"
                    refreshDiagnostic()
                }
            } header: {
                Text("操作")
            }

            Section {
                Text(diagnosticText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("重新自检") { refreshDiagnostic() }
            } header: {
                Text("写入自检")
            } footer: {
                Text("✓ 表示该容器已写入 apps.json。若全为 ✗，说明 App Group 容器不可写，把这段自检内容发给开发者。")
                    .font(.caption2)
            }
        }
        .navigationTitle("小组件 App")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selected = Set(TreeWidgetSnapshotWriter.manualSelection)
            refreshDiagnostic()
        }
    }
}
