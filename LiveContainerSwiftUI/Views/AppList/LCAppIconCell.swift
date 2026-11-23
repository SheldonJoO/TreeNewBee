//
//  LCAppIconCell.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  iOS 主屏幕式 app 图标格子：圆角图标 + 名称。
//  点击启动 app，长按弹菜单（启动 / 多任务启动 / 复制启动 URL / 移除）。
//  图标、启动、卸载逻辑均复用项目已有的 LCAppInfo / LCAppModel / LCAppBannerDelegate，
//  不引入任何新的 bundle id / URL scheme / hook 符号。
//

import SwiftUI
import UIKit

struct LCAppIconCell: View {
    @ObservedObject var app: LCAppModel
    var delegate: LCAppBannerDelegate

    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showUninstallConfirm = false
    @State private var showDeleteDataConfirm = false

    /// 待卸载的 app（点击菜单"移除"时暂存）
    @State private var pendingApp: LCAppModel?

    init(app: LCAppModel, delegate: LCAppBannerDelegate) {
        self.app = app
        self.delegate = delegate
    }

    private var appIcon: UIImage? {
        app.appInfo.iconIsDarkIcon(darkModeIcon)
    }

    var body: some View {
        Button {
            launch()
        } label: {
            VStack(spacing: 6) {
                iconView
                Text(app.displayName)
                    .font(.footnote)
                    .foregroundStyle(TreeAppsTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            // 启动
            Button {
                launch()
            } label: {
                Label("lc.appBanner.run".loc, systemImage: "play.fill")
            }

            // 多任务启动（iOS 16+）
            if #available(iOS 16.0, *) {
                Button {
                    launch(multitask: !app.shouldLaunchInMultitaskMode)
                } label: {
                    Label(
                        app.shouldLaunchInMultitaskMode ? "lc.appBanner.run".loc : "lc.appBanner.multitask".loc,
                        systemImage: app.shouldLaunchInMultitaskMode ? "play.fill" : "macwindow.badge.plus"
                    )
                }
            }

            Divider()

            // 复制启动 URL
            Button {
                copyLaunchUrl()
            } label: {
                Label("lc.appBanner.copyLaunchUrl".loc, systemImage: "link")
            }

            // 设置
            Button {
                delegate.openNavigationView(view: AnyView(LCAppSettingsView(model: app)))
            } label: {
                Label("lc.tabView.settings".loc, systemImage: "gear")
            }

            Divider()

            // 移除 app
            Button(role: .destructive) {
                pendingApp = app
                showUninstallConfirm = true
            } label: {
                Label("lc.appBanner.uninstall".loc, systemImage: "trash")
            }
        }
        .alert("lc.common.error".loc, isPresented: $showError) {
            Button("lc.common.ok".loc, role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("lc.appBanner.confirmUninstallTitle".loc, isPresented: $showUninstallConfirm) {
            Button("lc.common.cancel".loc, role: .cancel) {
                pendingApp = nil
            }
            Button("lc.appBanner.uninstall".loc, role: .destructive) {
                if pendingApp?.appInfo.containers.isEmpty == false {
                    showDeleteDataConfirm = true
                } else {
                    performUninstall(deleteData: false)
                }
            }
        } message: {
            Text("lc.appBanner.confirmUninstallMsg %@".localizeWithFormat(pendingApp?.displayName ?? app.displayName))
        }
        .alert("lc.appBanner.deleteDataTitle".loc, isPresented: $showDeleteDataConfirm) {
            Button("lc.common.no".loc, role: .cancel) {
                performUninstall(deleteData: false)
            }
            Button("lc.common.delete".loc, role: .destructive) {
                performUninstall(deleteData: true)
            }
        } message: {
            Text("lc.appBanner.deleteDataMsg %@".localizeWithFormat(pendingApp?.displayName ?? app.displayName))
        }
    }

    // MARK: - Icon

    private var iconView: some View {
        Group {
            if let appIcon {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: TreeAppsTheme.iconCornerRadius)
                    .fill(TreeAppsTheme.card)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TreeAppsTheme.iconCornerRadius))
        .frame(width: 60, height: 60)
        // 保留状态提示：多开(shared) / JIT / 锁定 角标
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                if app.uiIsShared {
                    statusBadge(symbol: "arrowshape.turn.up.left.fill", color: .orange)
                }
                if app.uiIsJITNeeded || app.uiIs32bit {
                    statusBadge(symbol: "bolt.fill", color: .purple)
                }
                if app.uiIsLocked || app.uiIsHidden {
                    statusBadge(symbol: "lock.fill", color: .orange)
                }
            }
            .offset(x: 6, y: -6)
        }
    }

    private func statusBadge(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(color, in: Circle())
    }

    // MARK: - Actions

    /// 复刻 LCAppBannerViewController.runButtonTapped / runApp 的启动前置逻辑
    private func launch(multitask: Bool? = nil) {
        // 若该容器已在多任务窗口中运行，直接把窗口切到前台
        if #available(iOS 16.0, *),
           let currentDataFolder = app.uiSelectedContainer?.folderName,
           MultitaskManager.isUsing(container: currentDataFolder) {
            var found = false
            if #available(iOS 16.1, *) {
                found = MultitaskWindowManager.openExistingAppWindow(dataUUID: currentDataFolder)
            }
            if !found {
                found = MultitaskDockManager.shared.bringMultitaskViewToFront(uuid: currentDataFolder)
            }
            if found {
                return
            }
        }

        Task {
            // 隐藏/锁定的 app 启动前需鉴权
            if app.appInfo.isLocked && !DataManager.shared.model.isHiddenAppUnlocked {
                do {
                    if !(try await LCUtils.authenticateUser()) {
                        return
                    }
                } catch {
                    presentError(error.localizedDescription)
                    return
                }
            }

            do {
                try await app.runApp(multitask: multitask)
            } catch {
                presentError(error.localizedDescription)
            }
        }
    }

    /// 复刻 LCAppBannerViewController.copyLaunchUrl
    private func copyLaunchUrl() {
        guard let relativeBundlePath = app.appInfo.relativeBundlePath else {
            return
        }
        if let folderName = app.uiSelectedContainer?.folderName {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(relativeBundlePath)&container-folder-name=\(folderName)"
        } else {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(relativeBundlePath)"
        }
    }

    /// 复刻 LCAppBannerViewController.uninstall 的文件删除与清理逻辑
    private func performUninstall(deleteData: Bool) {
        guard let target = pendingApp else {
            pendingApp = nil
            return
        }
        let appInfo = target.appInfo
        let containers = appInfo.containers

        do {
            guard let bundlePath = appInfo.bundlePath() else {
                throw CocoaError(.fileNoSuchFile)
            }
            let fileManager = FileManager.default
            try fileManager.removeItem(atPath: bundlePath)
            delegate.removeApp(app: target)

            if deleteData {
                for container in containers {
                    let dataUUID = container.folderName
                    try? fileManager.removeItem(at: LCPath.dataPath.appendingPathComponent(dataUUID))
                    LCUtils.removeAppKeychain(dataUUID: dataUUID)
                    DataManager.shared.model.appDataFolderNames.removeAll { $0 == dataUUID }
                }
            }
        } catch {
            presentError(error.localizedDescription)
        }
        pendingApp = nil
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

/// 锁定隐藏 app 在网格模式下的占位格子
struct LCAppSkeletonIconCell: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: TreeAppsTheme.iconCornerRadius)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 60)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 56, height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}
