//
//  TreeToolbox.swift
//  TreeNewBee —— 内置 openSSS 工具箱
//
//  悬浮「工具箱」按钮 + 两个功能：
//  1) 手机信息（与爱思助手截图一致的字段）
//  2) 屏蔽 iOS 更新（内置爱思版 / 尝鲜派版 tvOS 26 Beta 描述文件）
//
//  描述文件通过本机 HTTP 服务交给 Safari 下载，用户在「设置 → 通用 →
//  VPN 与设备管理」里完成安装。Apple 不允许 App 直接安装描述文件。
//

import Foundation
import UIKit
import Network
import Darwin

@objc(TreeToolbox)
public class TreeToolbox: NSObject {

    private static var installed = false
    private static var sceneObserver: NSObjectProtocol?
    private static var appObserver: NSObjectProtocol?

    @objc public static func install() {
        guard !installed else { return }
        installed = true
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            sceneObserver = center.addObserver(forName: UIScene.didActivateNotification,
                                               object: nil, queue: .main) { note in
                if let scene = note.object as? UIWindowScene { ensureWindow(in: scene) }
            }
            appObserver = center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                             object: nil, queue: .main) { _ in
                for scene in UIApplication.shared.connectedScenes {
                    if let scene = scene as? UIWindowScene { ensureWindow(in: scene) }
                }
            }
            for scene in UIApplication.shared.connectedScenes {
                if let scene = scene as? UIWindowScene { ensureWindow(in: scene) }
            }
        }
    }

    private static let windowKey = UnsafeRawPointer(bitPattern: 0x54524e4254585452)! // "TRNBTXTR"

    private static func ensureWindow(in scene: UIWindowScene) {
        if objc_getAssociatedObject(scene, windowKey) as? TreeToolboxWindow != nil { return }

        let window = TreeToolboxWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.normal + 1.5
        window.backgroundColor = .clear
        let host = UIViewController()
        host.view.backgroundColor = .clear

        let size: CGFloat = 42
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: scene.screen.bounds.width - size - 14,
                              y: scene.screen.bounds.height - size - 96,
                              width: size, height: size)
        button.layer.cornerRadius = size / 2
        button.backgroundColor = UIColor.black.withAlphaComponent(0.66)
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 6
        let icon = UIImage(systemName: "wrench.and.screwdriver") ?? UIImage(systemName: "gearshape")
        button.setImage(icon, for: .normal)
        button.tintColor = .white
        button.imageEdgeInsets = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)
        button.accessibilityLabel = "工具箱"
        let target = TreeToolboxTarget()
        target.window = window
        objc_setAssociatedObject(window, UnsafeRawPointer(bitPattern: 0x54524e4254585447)!, target,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        button.addTarget(target, action: #selector(TreeToolboxTarget.tapped), for: .touchUpInside)
        button.addGestureRecognizer(UIPanGestureRecognizer(target: target, action: #selector(TreeToolboxTarget.pan(_:))))
        host.view.addSubview(button)

        window.rootViewController = host
        window.isHidden = false
        // window 必须强持有，否则出了作用域立即释放，按钮消失
        objc_setAssociatedObject(scene, windowKey, window, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class TreeToolboxWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 保险：一旦本 window 上有 modal，放行全部触摸，否则 sheet 里的
        // 「完成」和表格行会被下面的按钮过滤逻辑吞掉，表现为「卡死」。
        if let root = rootViewController, root.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }
        let hit = super.hitTest(point, with: event)
        guard let hit else { return nil }
        var view: UIView? = hit
        while let v = view, v != self {
            if v is UIButton { return hit }
            view = v.superview
        }
        return nil
    }
}

// present 期间暂时隐藏悬浮按钮 window，避免它盖在 sheet 上吞触摸；
// sheet 关闭时恢复。双保险，确保工具箱页面能正常点。
private final class TreeToolboxNavController: UINavigationController {
    var onDismiss: (() -> Void)?
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            onDismiss?()
        }
    }
}

private final class TreeToolboxTarget: NSObject {
    weak var window: TreeToolboxWindow?

    @objc func tapped() {
        let vc = TreeToolboxViewController(style: .insetGrouped)
        let nav = TreeToolboxNavController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        nav.view.tintColor = .systemTeal
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }

        // 关键：present 前先隐藏悬浮按钮 window，杜绝层级遮挡/触摸拦截
        let overlay = window
        nav.onDismiss = { overlay?.isHidden = false }
        overlay?.isHidden = true

        // 明确找 openSSS 主 window（排除悬浮工具箱 window），从它的 root 找 top
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        guard let scene else { overlay?.isHidden = false; return }
        let presenter = scene.windows
            .first { $0 is TreeToolboxWindow == false && $0.rootViewController != nil }
            ?? scene.keyWindow
        guard let root = presenter?.rootViewController else { overlay?.isHidden = false; return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(nav, animated: true) {
            // present 完成后再隐藏一次，确保动画期间浮层不会挡住 sheet
            overlay?.isHidden = true
        }
    }

    @objc func pan(_ gesture: UIPanGestureRecognizer) {
        guard let button = gesture.view, let superview = button.superview else { return }
        let delta = gesture.translation(in: superview)
        var center = button.center
        center.x += delta.x
        center.y += delta.y
        let half = button.bounds.width / 2
        center.x = max(half + 4, min(superview.bounds.width - half - 4, center.x))
        center.y = max(half + 4, min(superview.bounds.height - half - 4, center.y))
        button.center = center
        gesture.setTranslation(.zero, in: superview)
    }
}

// MARK: - 手机信息

private struct DeviceInfo {
    let name: String
    let value: String
    let opensURL: URL?

    init(_ name: String, _ value: String, _ url: URL? = nil) {
        self.name = name
        self.value = value
        self.opensURL = url
    }
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    return String(cString: buffer)
}

private func sysctlInt64(_ name: String) -> Int64? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    sysctlbyname(name, &value, &size, nil, 0)
    return value
}

private func wifiIPv4() -> String? {
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0 else { return nil }
    defer { freeifaddrs(addresses) }
    var cursor = addresses
    while let current = cursor {
        let ifa = current.pointee
        if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
           let name = String(validatingUTF8: ifa.ifa_name), name == "en0" {
            var addr = sockaddr_in()
            memcpy(&addr, sa, MemoryLayout<sockaddr_in>.size)
            let bytes = withUnsafeBytes(of: addr.sin_addr) { $0.bindMemory(to: UInt8.self) }
            return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
        }
        cursor = ifa.ifa_next
    }
    return nil
}

private func marketingName(_ machine: String) -> String {
    let table: [String: String] = [
        "iPhone18,4": "iPhone Air", "iPhone18,3": "iPhone 17 Pro Max", "iPhone18,2": "iPhone 17 Pro",
        "iPhone18,1": "iPhone 17", "iPhone17,4": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Plus", "iPhone17,1": "iPhone 16", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone16,1": "iPhone 15 Pro", "iPhone15,5": "iPhone 15 Plus", "iPhone15,4": "iPhone 15",
        "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,2": "iPhone 14 Pro", "iPhone14,8": "iPhone 14 Plus",
        "iPhone14,7": "iPhone 14", "iPhone14,6": "iPhone SE (第 3 代)", "iPhone13,4": "iPhone 13 Pro Max",
        "iPhone13,3": "iPhone 13 Pro", "iPhone13,2": "iPhone 13", "iPhone12,8": "iPhone SE (第 2 代)"
    ]
    return table[machine] ?? UIDevice.current.localizedModel
}

private func cpuName(_ machine: String) -> String {
    if let brand = sysctlString("machdep.cpu.brand_string"), !brand.isEmpty { return brand }
    let table: [String: String] = [
        "iPhone18,4": "A19 Pro", "iPhone18,3": "A19 Pro", "iPhone18,2": "A19 Pro",
        "iPhone18,1": "A19", "iPhone17,4": "A18 Pro", "iPhone17,3": "A18 Pro",
        "iPhone17,2": "A18", "iPhone17,1": "A18", "iPhone16,2": "A17 Pro", "iPhone16,1": "A17 Pro"
    ]
    return table[machine] ?? "Apple 芯片"
}

private func deviceSections() -> [[DeviceInfo]] {
    let device = UIDevice.current
    let machine = sysctlString("hw.machine") ?? device.model
    let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
    let total = (attrs?[.systemSize] as? NSNumber)?.doubleValue ?? 0
    let free = (attrs?[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
    let gb = 1024.0 * 1024.0 * 1024.0
    let cores = ProcessInfo.processInfo.processorCount
    let chineseNumerals = ["", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"]
    let coreText = cores <= 10 ? chineseNumerals[cores] + "核" : "\(cores)核"
    let hz = sysctlInt64("hw.cpufrequency") ?? 0
    let freq = hz > 0 ? String(format: "%.2fGHz", Double(hz) / 1_000_000_000.0) : "—"
    let bounds = UIScreen.main.nativeBounds.size
    let osBuild = sysctlString("kern.osversion") ?? ""

    // 销售地区：优先 MobileGestalt，失败退回系统区域
    var region = Locale.current.regionCode ?? "—"
    if let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY) {
        typealias MGCopy = @convention(c) (CFString?) -> CFString?
        if let sym = dlsym(handle, "MGCopyAnswer"), let copy = unsafeBitCast(sym, to: MGCopy?.self),
           let code = copy("RegionCode" as CFString) as String?, !code.isEmpty {
            region = code
        }
        dlclose(handle)
    }
    let regionName = Locale.current.localizedString(forRegionCode: region)
    let regionText = regionName.map { "\(region) (\($0))" } ?? region

    let info1 = [
        DeviceInfo("手机名称", device.name),
        DeviceInfo("系统版本", "\(device.systemVersion)" + (osBuild.isEmpty ? "" : " (\(osBuild))")),
        DeviceInfo("总容量", String(format: "%.2f GB", total / gb)),
        DeviceInfo("可用容量", String(format: "%.2f GB", free / gb))
    ]
    let info2 = [
        DeviceInfo("手机型号", marketingName(machine)),
        DeviceInfo("销售地区", regionText),
        DeviceInfo("处理器", "\(cpuName(machine)) (\(coreText))"),
        DeviceInfo("处理器频率", freq),
        DeviceInfo("屏幕分辨率", "\(Int(bounds.width)) x \(Int(bounds.height))"),
        DeviceInfo("IP 地址", wifiIPv4() ?? "未连接 Wi-Fi")
    ]
    let info3 = [
        DeviceInfo("保修期", "去苹果官网查询", URL(string: "https://checkcoverage.apple.com/"))
    ]
    return [info1, info2, info3]
}

// MARK: - 描述文件安装

private final class TreeProfileInstaller {
    static let shared = TreeProfileInstaller()
    private var listener: NWListener?
    private var payload = Data()
    private var filename = "profile.mobileconfig"
    private var expire: DispatchWorkItem?

    func install(name: String) -> Bool {
        guard let url = Bundle(for: TreeToolbox.self).url(forResource: name, withExtension: "mobileconfig")
                ?? Bundle.main.url(forResource: name, withExtension: "mobileconfig"),
              let data = try? Data(contentsOf: url) else { return false }
        payload = data
        filename = "\(name).mobileconfig"
        listener?.cancel()
        expire?.cancel()

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        guard let newListener = try? NWListener(using: params) else { return false }
        listener = newListener
        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                    let header = """
                    HTTP/1.1 200 OK\r
                    Content-Type: application/x-apple-aspen-config\r
                    Content-Disposition: attachment; filename="\(self.filename)"\r
                    Content-Length: \(self.payload.count)\r
                    Connection: close\r
                    \r
                    """
                    var response = Data(header.utf8)
                    response.append(self.payload)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
        newListener.start(queue: DispatchQueue.global(qos: .userInitiated))
        guard let port = newListener.port?.rawValue else { return false }

        let work = DispatchWorkItem { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
        }
        expire = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: work)

        guard let download = URL(string: "http://127.0.0.1:\(port)/\(filename)") else { return false }
        guard UIApplication.shared.canOpenURL(download) else { return false }
        UIApplication.shared.open(download, options: [:]) { _ in }
        return true
    }
}

// MARK: - 工具箱页面

private final class TreeToolboxViewController: UITableViewController {

    private enum Row: Equatable {
        case device(section: Int, row: Int)
        case profile(String, String)
        case beta
    }

    private let device = deviceSections()
    private let profiles: [(String, String, String)] = [
        ("iOS26-aisi", "屏蔽 iOS 更新（爱思版）", "爱思助手提供 · 关闭自动下载更新"),
        ("iOS26-xianchangpai", "屏蔽 iOS 更新（尝鲜派版）", "尝鲜派提供 · 关闭自动下载更新")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "工具箱"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self, action: #selector(close))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["手机信息", "屏蔽 iOS 更新", "说明"][section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? device.reduce(0) { $0 + $1.count } : section == 1 ? profiles.count + 1 : 1
    }

    private func info(at indexPath: IndexPath) -> DeviceInfo? {
        var section = 0
        var row = indexPath.row
        for group in device {
            if row < group.count { return group[row] }
            row -= group.count
            section += 1
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0, let info = info(at: indexPath) {
            config.text = info.name
            config.secondaryText = info.value
            config.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = info.opensURL == nil ? .none : .disclosureIndicator
        } else if indexPath.section == 1 {
            if indexPath.row < profiles.count {
                let p = profiles[indexPath.row]
                config.text = p.1
                config.secondaryText = p.2
                config.image = UIImage(systemName: "shield.slash")
                cell.accessoryType = .disclosureIndicator
            } else {
                config.text = "体验 iOS 26（Apple Beta）"
                config.secondaryText = "前往 beta.apple.com 注册"
                config.image = UIImage(systemName: "sparkles")
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            config.text = "下载后请前往 设置 → 通用 → VPN 与设备管理 安装，重启后生效。"
            config.secondaryText = "两个链接实际是同一份 Apple 签名的 tvOS 26 Beta 描述文件"
            config.textProperties.font = .systemFont(ofSize: 13)
            config.secondaryTextProperties.font = .systemFont(ofSize: 12)
            config.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = .none
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0, let info = info(at: indexPath), let url = info.opensURL {
            UIApplication.shared.open(url)
        } else if indexPath.section == 1 {
            if indexPath.row < profiles.count {
                let name = profiles[indexPath.row].0
                let ok = TreeProfileInstaller.shared.install(name: name)
                let alert = UIAlertController(
                    title: ok ? "已打开 Safari" : "描述文件缺失",
                    message: ok ? "描述文件已下载。请打开「设置 → 通用 → VPN 与设备管理」完成安装，然后重启设备。" :
                        "请确认合体包内包含 \(name).mobileconfig。",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                present(alert, animated: true)
            } else if let url = URL(string: "https://beta.apple.com/") {
                UIApplication.shared.open(url)
            }
        }
    }
}
