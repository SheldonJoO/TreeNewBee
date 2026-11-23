//
//  TreeWidgetSnapshot.swift
//  TreeNewBee —— 给桌面 / 锁屏小组件提供「TreeNewBee 里安装的 App」列表
//
//  数据源只扫描 TreeNewBee 自己安装 Guest App 的两个目录：
//    · LCPath.bundlePath          = Documents/Applications
//    · LCPath.lcGroupBundlePath   = App Group/LiveContainer/Applications
//  openSSS 侧载到桌面的 App 不在这里，绝不会被写进小组件。
//
//  ⚠️ 侧载环境下 appex 的 App Group 实测完全不可用（可用容器 0 个），
//  所以主通道改成 Keychain：宿主把列表+图标写进 Keychain，widget 直接读。
//  App Group 文件作为辅助留着，不影响主链路。
//

import Foundation
import UIKit
import WidgetKit
import Security

struct TreeWidgetAppEntry: Codable {
    let name: String
    let bundleName: String
    let container: String
    let icon: String
    var iconData: String? = nil   // Keychain 通道直接带图标 base64
}

struct TreeWidgetSnapshot: Codable {
    let version: Int
    let apps: [TreeWidgetAppEntry]
}

/// 扫盘得到的 TreeNewBee 已安装 App（不依赖 UI 层的 SharedModel）
struct TreeWidgetScannedApp {
    let bundleName: String
    let name: String
    let container: String
    let icon: UIImage?
    let isShared: Bool
}

enum TreeWidgetSnapshotWriter {
    public static let manualKey = "LCTreeWidgetManualApps"
    // Keychain 位置。不显式写 kSecAttrAccessGroup：两边各自用 entitlement 里
    // 第一个 keychain-access-group（侧载会把 AAAAA11111 重写成真实 team）。
    static let keychainService = "com.kdt.livecontainer.treeWidget"
    static let keychainAccount = "snapshot.v2"
    private static var lastKeychainStatus: OSStatus = -1

    static var manualSelection: [String] {
        get {
            let groupValue = LCUtils.appGroupUserDefault.stringArray(forKey: manualKey) ?? []
            if !groupValue.isEmpty { return groupValue }
            return UserDefaults.standard.stringArray(forKey: manualKey) ?? []
        }
        set {
            LCUtils.appGroupUserDefault.set(newValue, forKey: manualKey)
            UserDefaults.standard.set(newValue, forKey: manualKey)
        }
    }

    /// 直接扫盘：TreeNewBee 里安装的每一个 .app 都在这里。
    static func scanInstalledApps() -> [TreeWidgetScannedApp] {
        let fm = FileManager.default
        let roots: [(url: URL, shared: Bool)] = [
            (LCPath.bundlePath, false),
            (LCPath.lcGroupBundlePath, true)
        ]
        var seen = Set<String>()
        var result: [TreeWidgetScannedApp] = []
        for root in roots {
            let names = (try? fm.contentsOfDirectory(atPath: root.url.path)) ?? []
            for dirName in names where dirName.lowercased().hasSuffix(".app") {
                guard !seen.contains(dirName) else { continue }
                seen.insert(dirName)
                let path = root.url.appendingPathComponent(dirName).path
                guard let info = LCAppInfo(bundlePath: path) else { continue }
                info.relativeBundlePath = dirName
                info.isShared = root.shared
                let name = info.displayName() ?? (dirName as NSString).deletingPathExtension
                result.append(TreeWidgetScannedApp(bundleName: dirName,
                                                    name: name,
                                                    container: "",
                                                    icon: info.iconIsDarkIcon(false),
                                                    isShared: root.shared))
            }
        }
        return result
    }

    private static var allRoots: [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        func add(_ groupURL: URL?) {
            guard let groupURL else { return }
            let r = groupURL.appendingPathComponent("LiveContainer/TreeWidget", isDirectory: true)
            if !roots.contains(r) { roots.append(r) }
        }
        add(LCSharedUtils.appGroupPath())
        if let team = LCSharedUtils.teamIdentifier(), !team.isEmpty {
            for base in ["group.com.SideStore.SideStore", "group.com.rileytestut.AltStore"] {
                add(fm.containerURL(forSecurityApplicationGroupIdentifier: "\(base).\(team)"))
            }
        }
        add(fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.SideStore.SideStore"))
        add(fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.rileytestut.AltStore"))
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).last {
            add(docs.appendingPathComponent("TreeWidget", isDirectory: true))
        }
        return roots
    }

    /// 图标压到 72x72 PNG，避免 Keychain item 过大
    private static func iconBase64(_ image: UIImage?) -> String? {
        guard let image else { return nil }
        let size = CGSize(width: 72, height: 72)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.pngData()?.base64EncodedString()
    }

    @discardableResult
    static func refresh(apps: [LCAppModel], hiddenApps: [LCAppModel] = []) -> Int {
        var candidates = scanInstalledApps()
        // UI 列表只用来补容器信息，不作为数据源
        for model in apps + hiddenApps {
            guard let bundle = model.appInfo.relativeBundlePath, !bundle.isEmpty else { continue }
            if candidates.contains(where: { $0.bundleName == bundle }) { continue }
            let name = model.appInfo.displayName() ?? (bundle as NSString).deletingPathExtension
            candidates.append(TreeWidgetScannedApp(bundleName: bundle,
                                                    name: name,
                                                    container: model.uiSelectedContainer?.name ?? "",
                                                    icon: model.appInfo.iconIsDarkIcon(false),
                                                    isShared: model.appInfo.isShared))
        }

        let manual = Set(manualSelection)
        let automaticMode = manual.isEmpty
        var entries: [TreeWidgetAppEntry] = []
        var seen = Set<String>()

        for app in candidates {
            guard !seen.contains(app.bundleName) else { continue }
            if !automaticMode && !manual.contains(app.bundleName) { continue }
            seen.insert(app.bundleName)
            let key = app.bundleName.filter { $0.isLetter || $0.isNumber }
            entries.append(TreeWidgetAppEntry(name: app.name,
                                               bundleName: app.bundleName,
                                               container: app.container,
                                               icon: "\(key).png",
                                               iconData: iconBase64(app.icon)))
        }

        // 内置 openSSS 只有手动勾选才出现，不再混进「已安装 App」
        if !automaticMode && manual.contains("builtinSideStore") && UserDefaults.sideStoreExist() {
            let builtin = BuiltInSideStoreAppInfo.shared
            let builtinName = builtin.displayName() as String?
            entries.append(TreeWidgetAppEntry(name: builtinName ?? "openSSS",
                                               bundleName: "builtinSideStore",
                                               container: "builtinSideStore",
                                               icon: "builtinSideStore.png",
                                               iconData: iconBase64(builtin.iconIsDarkIcon(false))))
        }

        let snapshot = TreeWidgetSnapshot(version: 1, apps: entries)
        guard let data = try? JSONEncoder().encode(snapshot) else { return 0 }

        // 主通道：Keychain（侧载 appex 的 App Group 不可用，只有这个靠得住）
        lastKeychainStatus = Self.writeKeychain(data)
        // 辅助通道：App Group 文件（有些签名环境可用，留着不亏）
        let selectionData = (try? JSONEncoder().encode(manualSelection)) ?? Data()
        for root in allRoots {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? data.write(to: root.appendingPathComponent("apps.json"), options: .atomic)
            try? selectionData.write(to: root.appendingPathComponent("selection.json"), options: .atomic)
        }
        // 关键：立刻刷新 WidgetKit timeline
        WidgetCenter.shared.reloadAllTimelines()
        return entries.count
    }

    @discardableResult
    static func writeKeychain(_ data: Data) -> OSStatus {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        var attrs: [String: Any] = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(attrs as CFDictionary, nil)
        if add == errSecDuplicateItem {
            return SecItemUpdate(base as CFDictionary,
                                 [kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary)
        }
        return add
    }

    static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// 设置页自检
    static func diagnostic() -> String {
        let fm = FileManager.default
        let scanned = scanInstalledApps()
        var lines: [String] = []
        lines.append("检测到 TreeNewBee 已安装 App：\(scanned.count) 个")
        for app in scanned.prefix(20) {
            lines.append("  · \(app.name)  [\(app.bundleName)]\(app.isShared ? " 共享" : "")")
        }
        if scanned.count > 20 { lines.append("  … 其余 \(scanned.count - 20) 个省略") }
        let kcRead = readKeychain()
        lines.append("Keychain 写入状态：\(lastKeychainStatus)（0 = 成功）")
        lines.append("Keychain 回读：\(kcRead == nil ? "失败" : "\(kcRead!.count) 字节")")
        lines.append("手动选择：\(manualSelection.isEmpty ? "自动显示全部" : manualSelection.joined(separator: ", "))")
        for root in allRoots {
            let ok = fm.fileExists(atPath: root.appendingPathComponent("apps.json").path)
            lines.append("\(ok ? "✓" : "✗") \(root.path)")
        }
        return lines.joined(separator: "\n")
    }
}
