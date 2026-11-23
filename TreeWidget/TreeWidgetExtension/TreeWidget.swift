//
//  TreeWidget.swift
//  TreeNewBee 桌面 / 锁屏小组件
//
//  显示的是「TreeNewBee 里安装的 App」以及可选的内置 openSSS。宿主把列表写进
//  共享容器 LiveContainer/TreeWidget/apps.json；若快照读不到，小组件会直接扫描
//  同一容器下 LiveContainer/Applications 里的 .app 作为兜底。
//  点击用 livecontainer://livecontainer-launch 深链回 TreeNewBee 启动对应 App；
//  source=widget 让宿主第一时间盖上品牌启动页，遮住中间的页面切换。
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit
import Security
import Darwin

/// widget 进程内记录「这次是从哪个容器读到数据的」，图标跟着走。
private enum WidgetStore {
    static var activeRoot: URL?
    static var lastKeychainStatus: OSStatus = -1
    static var lastKeychainBytes: Int = 0
}

private struct TreeApp: Decodable, Identifiable {
    let name: String
    let bundleName: String
    let container: String
    let icon: String
    var iconData: String? = nil   // Keychain 快照里直接带图标 base64

    var id: String { bundleName + "|" + container }

    var launchURL: URL? {
        var components = URLComponents(string: "livecontainer://livecontainer-launch")
        // source=widget：宿主据此在最早期盖一层品牌启动页，避免闪出 App 列表
        var items = [URLQueryItem(name: "bundle-name", value: bundleName),
                     URLQueryItem(name: "source", value: "widget")]
        if !container.isEmpty {
            items.append(URLQueryItem(name: "container-folder-name", value: container))
        }
        components?.queryItems = items
        return components?.url
    }

    var image: UIImage? {
        // Keychain 快照自带图标，不依赖任何容器
        if let s = iconData, let d = Data(base64Encoded: s), let img = UIImage(data: d) {
            return img
        }
        // 兜底扫盘路径没有图标文件，内置 openSSS 用系统图标占位
        if bundleName == "builtinSideStore" {
            return UIImage(systemName: "app.badge.checkmark.fill")
        }
        guard !icon.isEmpty, let root = WidgetStore.activeRoot else { return nil }
        return UIImage(contentsOfFile: root.appendingPathComponent("Icons")
            .appendingPathComponent(icon).path)
    }

    // MARK: - Keychain 主通道
    // 侧载 appex 的 App Group 实测 0 个可用容器；Keychain 是唯一可靠共享通道。
    // 不指定 kSecAttrAccessGroup：用 entitlement 里第一个 keychain group
    // （widget 与宿主都声明 AAAAA11111.com.kdt.livecontainer.shared，
    //  侧载时一起被重写为真实 team，两边自然匹配）。
    private static let kcService = "com.kdt.livecontainer.treeWidget"
    private static let kcAccount = "snapshot.v2"

    static func readKeychainSnapshot() -> (data: Data?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: kcAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let st = SecItemCopyMatching(query as CFDictionary, &item)
        return (item as? Data, st)
    }

    /// 读取「运行时真实生效」的签名 entitlement。
    /// 侧载工具会重写 application-groups / application-identifier，不能用编译期
    /// 写死的裸 group ID。iOS 上 SecCode* 不可用（macOS only），这里走
    /// SecTaskCopyValueForEntitlement —— 宿主 LCSharedUtils 也是这么读的。
    private static func runtimeEntitlementGroups() -> [String] {
        entitlementValue("com.apple.security.application-groups") as? [String] ?? []
    }

    private static func runtimeAppIdentifier() -> String? {
        entitlementValue("application-identifier") as? String
    }

    static var groupIDs: [String] {
        var ids: [String] = runtimeEntitlementGroups()
        // application-identifier 形如 <TEAMID>.com.kdt.livecontainer.TreeWidget
        var team = ""
        if let appID = runtimeAppIdentifier() {
            team = appID.split(separator: ".").first.map(String.init) ?? ""
        }
        if team.isEmpty { team = readTeamIdentifier() ?? "" }
        if !team.isEmpty && team != "AAAAA11111" {
            ids += [
                "group.com.SideStore.SideStore.\(team)",
                "group.com.rileytestut.AltStore.\(team)"
            ]
        }
        ids += ["group.com.SideStore.SideStore", "group.com.rileytestut.AltStore"]
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// 所有「能取到」的 App Group 容器根路径
    static var containerRoots: [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        for gid in groupIDs {
            if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: gid),
               !roots.contains(url) {
                roots.append(url)
            }
        }
        return roots
    }

    /// 快照目录候选（容器根 /LiveContainer/TreeWidget）
    static var snapshotRoots: [URL] {
        containerRoots.map { $0.appendingPathComponent("LiveContainer/TreeWidget", isDirectory: true) }
    }

    /// 兜底：直接扫共享容器里 TreeNewBee 安装的 .app 目录
    static func scanInstalledApps() -> [TreeApp] {
        let fm = FileManager.default
        var selection = Set<String>()
        for root in snapshotRoots {
            if let data = try? Data(contentsOf: root.appendingPathComponent("selection.json")),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                selection = Set(arr)
                break
            }
        }
        var seen = Set<String>()
        var result: [TreeApp] = []
        for containerRoot in containerRoots {
            for sub in ["LiveContainer/Applications", "Applications"] {
                let dir = containerRoot.appendingPathComponent(sub, isDirectory: true)
                let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                for dirName in names where dirName.lowercased().hasSuffix(".app") {
                    guard !seen.contains(dirName) else { continue }
                    seen.insert(dirName)
                    if !selection.isEmpty && !selection.contains(dirName) { continue }
                    let plist = dir.appendingPathComponent(dirName).appendingPathComponent("Info.plist")
                    let d = NSDictionary(contentsOfFile: plist.path) as? [String: Any] ?? [:]
                    let name = (d["CFBundleDisplayName"] as? String)
                        ?? (d["CFBundleName"] as? String)
                        ?? (dirName as NSString).deletingPathExtension
                    result.append(TreeApp(name: name, bundleName: dirName,
                                          container: "", icon: "", iconData: nil))
                }
            }
        }
        // 兜底路径也补上内置 openSSS，保证任何通道下都能把它加进小组件
        if !result.contains(where: { $0.bundleName == "builtinSideStore" }),
           selection.isEmpty || selection.contains("builtinSideStore") {
            result.insert(TreeApp(name: "openSSS", bundleName: "builtinSideStore",
                                  container: "", icon: "builtinSideStore", iconData: nil), at: 0)
        }
        return result
    }

    static var diagnosticText: String {
        let fm = FileManager.default
        let roots = snapshotRoots
        let groups = groupIDs
        let scanned = scanInstalledApps()
        let kc = TreeApp.readKeychainSnapshot()
        var lines: [String] = []
        lines.append("Keychain: 状态 \(kc.status) / \(kc.data?.count ?? 0) 字节")
        lines.append("Group 候选 \(groups.count) 个 / 可用容器 \(containerRoots.count) 个")
        let effective = runtimeEntitlementGroups()
        if effective.isEmpty {
            lines.append("⚠️ 运行时 entitlement 读取失败")
        } else {
            lines.append("生效 group: \(effective.joined(separator: ", "))")
        }
        if containerRoots.isEmpty { lines.append("⚠️ 取不到任何 App Group 容器") }
        for root in roots.prefix(4) {
            lines.append("\(fm.fileExists(atPath: root.appendingPathComponent("apps.json").path) ? "✓" : "✗") \(root.lastPathComponent)")
        }
        lines.append("容器里扫到 .app: \(scanned.count) 个")
        return lines.joined(separator: "\n")
    }

    private static func readTeamIdentifier() -> String? {
        entitlementValue("com.apple.developer.team-identifier") as? String
    }

    /// 私有 API 读取运行时 entitlement，返回 Swift 原生值（[String] 或 String）。
    private static func entitlementValue(_ key: String) -> Any? {
        typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        typealias CopyFn = @convention(c) (UnsafeMutableRawPointer?, CFString,
                                            UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?
        guard let createFn = privateSymbol("SecTaskCreateFromSelf") as? CreateFn,
              let copyFn = privateSymbol("SecTaskCopyValueForEntitlement") as? CopyFn,
              let task = createFn(nil) else { return nil }
        defer { privateCFRelease(task) }
        var error: Unmanaged<CFError>?
        guard let value = copyFn(task, key as CFString, &error) else { return nil }
        let obj: AnyObject = Unmanaged<CFTypeRef>.fromOpaque(value.toOpaque()).takeUnretainedValue() as AnyObject
        if let arr = obj as? NSArray, let strings = arr as? [String] { return strings }
        if let str = obj as? String { return str }
        return nil
    }

    private static func privateSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return p }
        // Security.framework 可能尚未把符号暴露在全局表，显式 dlopen 再找一次
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else {
            return nil
        }
        return dlsym(handle, name)
    }

    private static func privateCFRelease(_ cf: UnsafeMutableRawPointer) {
        typealias ReleaseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
        if let fn = privateSymbol("CFRelease") as? ReleaseFn { fn(cf) }
    }
}

private struct Snapshot: Decodable {
    let version: Int
    let apps: [TreeApp]
}

private struct TreeEntry: TimelineEntry {
    let date: Date
    let apps: [TreeApp]
}

private struct TreeProvider: TimelineProvider {
    // 内置 openSSS 是合法条目，不再过滤。它启动时中间的闪屏与"已安装应用"页
    // 由宿主 TreeLaunchOverlay 品牌启动页统一遮住，而不是靠删掉这一项回避。
    private func sanitize(_ apps: [TreeApp]) -> [TreeApp] {
        var seen = Set<String>()
        return Array(apps.filter { seen.insert($0.id).inserted }.prefix(12))
    }

    private func load() -> [TreeApp] {
        WidgetStore.activeRoot = nil
        // 1) Keychain 主通道（侧载 appex 的 App Group 不可用，这个才靠得住）
        let kc = TreeApp.readKeychainSnapshot()
        WidgetStore.lastKeychainStatus = kc.status
        WidgetStore.lastKeychainBytes = kc.data?.count ?? 0
        if let data = kc.data,
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           !snapshot.apps.isEmpty {
            return sanitize(snapshot.apps)
        }
        // 2) App Group 快照（辅助通道，逐个容器找第一个有数据的）
        for root in TreeApp.snapshotRoots {
            guard let data = try? Data(contentsOf: root.appendingPathComponent("apps.json")),
                  let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
                  !snapshot.apps.isEmpty else { continue }
            WidgetStore.activeRoot = root
            return sanitize(snapshot.apps)
        }
        // 3) 都读不到：直接扫 TreeNewBee 装在容器里的 .app
        return sanitize(TreeApp.scanInstalledApps())
    }

    func placeholder(in context: Context) -> TreeEntry {
        TreeEntry(date: Date(), apps: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TreeEntry) -> Void) {
        completion(TreeEntry(date: Date(), apps: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TreeEntry>) -> Void) {
        let entry = TreeEntry(date: Date(), apps: load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

private struct AppTile: View {
    let app: TreeApp
    let showName: Bool

    var body: some View {
        Group {
            if let url = app.launchURL {
                Link(destination: url) { tileContent }
            } else {
                tileContent
            }
        }
    }

    private var tileContent: some View {
        VStack(spacing: 4) {
            if let image = app.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.tint)
            }
            if showName {
                Text(app.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// iOS 17+ 强制要求小组件声明 containerBackground，否则系统显示
// "Please adopt containerBackground API" 占位错误（锁屏 accessory 尤其明显）。
private struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        } else {
            content
        }
    }
}

private struct TreeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TreeEntry

    var body: some View {
        Group {
            if entry.apps.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tree.fill").font(.title3).foregroundStyle(.green)
                    Text("没读到 TreeNewBee 里装的 App").font(.caption2).multilineTextAlignment(.center)
                    if family != .accessoryCircular && family != .accessoryInline {
                        Text(TreeApp.diagnosticText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                switch family {
                case .systemSmall:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                        ForEach(Array(entry.apps.prefix(4))) { AppTile(app: $0, showName: true) }
                    }
                case .systemMedium:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(Array(entry.apps.prefix(8))) { AppTile(app: $0, showName: true) }
                    }
                case .systemLarge:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(entry.apps) { AppTile(app: $0, showName: true) }
                    }
                case .accessoryCircular:
                    if let app = entry.apps.first, let url = app.launchURL {
                        Link(destination: url) {
                            ZStack {
                                AccessoryWidgetBackground()
                                if let image = app.image {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(8)
                                } else {
                                    Image(systemName: "app.fill")
                                }
                            }
                        }
                    }
                case .accessoryRectangular:
                    HStack(spacing: 8) {
                        ForEach(Array(entry.apps.prefix(3))) { app in
                            AppTile(app: app, showName: false)
                        }
                    }
                case .accessoryInline:
                    if let app = entry.apps.first {
                        Link(destination: app.launchURL ?? URL(string: "livecontainer://")!) {
                            Label(app.name, systemImage: "tree.fill")
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
        .modifier(WidgetBackgroundModifier())
    }
}

@main
struct TreeLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.kdt.livecontainer.treeLaunchWidget",
                            provider: TreeProvider()) { entry in
            TreeWidgetView(entry: entry)
        }
        .configurationDisplayName("🌲树应用")
        .description("一键打开 TreeNewBee 中已安装的应用")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
