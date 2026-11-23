//
//  TreeLaunchOverlay.swift
//  TreeNewBee —— 小组件 / 深链启动 App 时的品牌过渡层
//
//  从桌面小组件点一个 App，系统必须先唤醒宿主、渲染 App 列表、切 Tab、
//  再切到 guest；openSSS 还会额外闪自己的启动页和「已安装应用」页。
//  以前靠"把 openSSS 从小组件里删掉"回避，这一版改成正面解决：
//  深链到达的第一时间就盖一层统一的品牌启动页，guest 起来后淡出，
//  用户只看到「小组件 → 🌲过渡页 → 目标 App」，中间页面全被遮住。
//

import UIKit

enum TreeLaunchOverlay {
    private static var window: UIWindow?
    private static var safetyWork: DispatchWorkItem?

    /// 只处理小组件来的深链（source=widget），其它深链 / App 内部跳转不受影响。
    static func showIfNeeded(for url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host?.lowercased() == "livecontainer-launch",
              comps.queryItems?.contains(where: { $0.name == "source" && $0.value == "widget" }) == true,
              let bundle = comps.queryItems?.first(where: { $0.name == "bundle-name" })?.value,
              !bundle.isEmpty else { return }
        let name = bundle == "builtinSideStore" ? "openSSS" : (bundle as NSString).deletingPathExtension
        show(name: name)
    }

    /// 显示过渡页。已有遮罩时不重复创建（openSideStore 与深链可能各调一次）。
    static func show(name: String) {
        // 深链到达时通常已在主线程：同步创建，别让 SwiftUI 先渲染一帧 App 列表。
        let build = {
            guard window == nil, let scene = activeScene() else { return }

            let w = UIWindow(windowScene: scene)
            // 比状态栏、悬浮返回按钮、工具箱按钮、版本小字（alert 级）都高
            w.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 100)
            w.backgroundColor = .clear
            let vc = TreeLaunchOverlayController(name: name)
            vc.onCancel = { hide(after: 0) }
            w.rootViewController = vc
            w.alpha = 1   // 不淡入：第一帧就完全盖住底层，杜绝「闪一下」
            w.isHidden = false
            window = w

            // 兜底：无论 guest 有没有起来，5 秒后一定收起，绝不把用户卡住
            safetyWork?.cancel()
            let work = DispatchWorkItem { hide(after: 0) }
            safetyWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
        if Thread.isMainThread {
            build()
        } else {
            DispatchQueue.main.async { build() }
        }
    }

    /// guest 启动完成后调用；留一点余量等它把界面铺好再淡出。
    static func hide(after delay: TimeInterval = 0.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            safetyWork?.cancel()
            safetyWork = nil
            guard let w = window else { return }
            window = nil
            UIView.animate(withDuration: 0.30, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                w.alpha = 0
                w.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
            } completion: { _ in
                w.isHidden = true
                w.rootViewController = nil
            }
        }
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

private final class TreeLaunchOverlayController: UIViewController {
    private let appName: String
    var onCancel: (() -> Void)?
    private var glow: CAGradientLayer?

    init(name: String) {
        self.appName = name
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let accent = UIColor(red: 0x19 / 255.0, green: 0xD3 / 255.0, blue: 0xB5 / 255.0, alpha: 1)
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF7 / 255.0, alpha: 1)
                : UIColor(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0F / 255.0, alpha: 1)
        }

        let gradient = CAGradientLayer()
        gradient.colors = [accent.withAlphaComponent(0.22).cgColor, UIColor.clear.cgColor]
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        view.layer.insertSublayer(gradient, at: 0)
        glow = gradient

        // 品牌图标
        let logo = UIImageView(image: UIImage(systemName: "tree.fill"))
        logo.tintColor = accent
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 44),
            logo.heightAnchor.constraint(equalToConstant: 44)
        ])

        let holder = UIView()
        holder.backgroundColor = accent.withAlphaComponent(0.16)
        holder.layer.cornerRadius = 22
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(logo)
        NSLayoutConstraint.activate([
            holder.widthAnchor.constraint(equalToConstant: 88),
            holder.heightAnchor.constraint(equalToConstant: 88),
            logo.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: holder.centerYAnchor)
        ])

        let brand = UILabel()
        brand.text = "🌲树应用"
        brand.font = .systemFont(ofSize: 15, weight: .semibold)
        brand.textColor = .secondaryLabel
        brand.textAlignment = .center

        let title = UILabel()
        title.text = "正在打开 \(appName)"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 2

        let subtitle = UILabel()
        subtitle.text = "请稍候，正在切换应用"
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .tertiaryLabel
        subtitle.textAlignment = .center

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = accent
        spinner.startAnimating()

        let stack = UIStackView(arrangedSubviews: [holder, brand, title, subtitle, spinner])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -28),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 15)
        cancel.tintColor = .secondaryLabel
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        glow?.frame = CGRect(x: 0, y: 0,
                             width: view.bounds.width,
                             height: view.bounds.height * 0.75)
    }

    @objc private func cancelTapped() { onCancel?() }
}
