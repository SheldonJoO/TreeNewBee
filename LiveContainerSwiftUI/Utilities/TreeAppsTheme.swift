//
//  TreeAppsTheme.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  树应用统一视觉层 —— 设计 token 完整照搬 openSSS 的 ShellTheme，
//  强调色默认取 openSSS 默认主题 "openSSS Teal" #19D3B5
//  (来源: openSSS SideStore/Core/Theme/ThemeManager.swift:22)。
//
//  颜色全部是 dynamic（跟随系统浅色/深色），与 openSSS 的
//  ShellTheme.background/card/primaryText 等一一对应。
//
//  外观模式（跟随系统 / 浅色 / 深色）与强调色由「设置 → 通用设置 → 主题管理」
//  写入 App Group UserDefaults，这里只负责读取并施加到视图层。
//

import SwiftUI
import UIKit

// MARK: - 外观模式

enum TreeAppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    static var current: TreeAppearanceMode {
        TreeAppearanceMode(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCAppearanceMode"))
            ?? .system
    }
}

// MARK: - Hex 颜色工具

extension UIColor {
    convenience init?(hex: String?) {
        guard let hex, !hex.isEmpty else { return nil }
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let r = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
        let g = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
        let b = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
        let a = hasAlpha ? CGFloat(number & 0xFF) / 255.0 : 1.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return "" }
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

extension Color {
    init?(hex: String?) {
        guard let uiColor = UIColor(hex: hex) else { return nil }
        self.init(uiColor: uiColor)
    }

    var hexString: String { UIColor(self).hexString }
}

// MARK: - 主题 token

enum TreeAppsTheme {
    /// openSSS 默认强调色 #19D3B5，同时是「恢复默认」的回退色
    static let defaultAccentHex = "#19D3B5"

    static let teal = Color(uiColor: UIColor { _ in
        UIColor(hex: defaultAccentHex)!
    })

    /// 当前强调色（用户自定义，存于 App Group UserDefaults）
    static var accent: Color {
        Color(hex: LCUtils.appGroupUserDefault.string(forKey: "LCCustomAccentHex")) ?? teal
    }

    static var accentUIColor: UIColor {
        UIColor(hex: LCUtils.appGroupUserDefault.string(forKey: "LCCustomAccentHex"))
            ?? UIColor(hex: defaultAccentHex)!
    }

    static var accentBackground: Color { accent.opacity(0.16) }

    /// 当前色方案，nil = 跟随系统
    static var preferredColorScheme: ColorScheme? { TreeAppearanceMode.current.colorScheme }

    // MARK: - Surfaces（对照 ShellTheme）
    static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor(red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF7 / 255.0, alpha: 1)
            : UIColor(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0F / 255.0, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? .white
            : UIColor(red: 0x1A / 255.0, green: 0x1B / 255.0, blue: 0x21 / 255.0, alpha: 1)
    })
    static let cardHighlighted = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor(red: 0xE9 / 255.0, green: 0xE9 / 255.0, blue: 0xEE / 255.0, alpha: 1)
            : UIColor(red: 0x26 / 255.0, green: 0x28 / 255.0, blue: 0x36 / 255.0, alpha: 1)
    })
    static let pillBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor(red: 0xE5 / 255.0, green: 0xE5 / 255.0, blue: 0xEA / 255.0, alpha: 1)
            : UIColor(red: 0x2A / 255.0, green: 0x2D / 255.0, blue: 0x3A / 255.0, alpha: 1)
    })
    static let pillSelectedBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? .white
            : UIColor(red: 0x14 / 255.0, green: 0x15 / 255.0, blue: 0x1C / 255.0, alpha: 1)
    })

    // MARK: - Text
    static let primaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 1)
            : .white
    })
    static let secondaryText = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0, alpha: 1)
            : UIColor(red: 0x9C / 255.0, green: 0xA3 / 255.0, blue: 0xAF / 255.0, alpha: 1)
    })
    static let separator = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor.black.withAlphaComponent(0.08)
            : UIColor.white.withAlphaComponent(0.08)
    })

    // MARK: - Semantic
    static let success = Color.green
    static let danger = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .light
            ? UIColor(red: 0xC0 / 255.0, green: 0x39 / 255.0, blue: 0x2B / 255.0, alpha: 1)
            : UIColor(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0, alpha: 1)
    }) // ShellTheme.expiredRed

    // MARK: - Metrics（对照 ShellTheme）
    static let cardCornerRadius: CGFloat = 16
    static let horizontalMargin: CGFloat = 16
    static let iconCornerRadius: CGFloat = 14

    // MARK: - Fonts（对照 ShellTheme）
    static let largeTitleFont = Font.system(size: 34, weight: .bold)
    static let headingFont = Font.system(size: 22, weight: .bold)
    static let sectionTitleFont = Font.system(size: 15, weight: .bold)
    static let rowTitleFont = Font.system(size: 17, weight: .semibold)
    static let rowValueFont = Font.system(size: 16, weight: .regular)

    /// 把统一主题注入整个窗口（按钮、NavigationLink 箭头、TabView 选中态、
    /// 系统弹窗 tint、深浅色模式）。主题变更后需要主动调用一次。
    static func applyToKeyWindow() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
            window.tintColor = accentUIColor
            window.overrideUserInterfaceStyle = TreeAppearanceMode.current.uiStyle
        }
    }
}

extension View {
    /// 在视图树根节点调用一次，统一 TreeApps 的强调色。
    func treeAppsTheme() -> some View {
        self
            .tint(TreeAppsTheme.accent)
            .accentColor(TreeAppsTheme.accent)
    }

    /// openSSS 风格卡片背景。
    func treeAppsCard(highlighted: Bool = false) -> some View {
        self.background(
            (highlighted ? TreeAppsTheme.cardHighlighted : TreeAppsTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: TreeAppsTheme.cardCornerRadius))
        )
    }
}

/// openSSS「我的」页风格设置行：左侧彩色图标 + 标题 + 右侧值。
/// 用于设置页分类列表，视觉对齐 Shell 的 SettingRowCell。
struct TreeSettingsRow: View {
    let icon: String
    let title: String
    var value: String = ""
    var color: Color = TreeAppsTheme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26)
            Text(title)
                .font(TreeAppsTheme.rowTitleFont)
                .foregroundStyle(TreeAppsTheme.primaryText)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(TreeAppsTheme.rowValueFont)
                    .foregroundStyle(TreeAppsTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
