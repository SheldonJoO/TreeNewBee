//
//  TreeLanguageManager.swift
//  LiveContainerSwiftUI (TreeNewBee)
//
//  应用内语言切换：
//  - 宿主：写 UserDefaults.standard["AppleLanguages"]，重建 SwiftUI 树即时生效。
//  - openSSS：把语言写进内置 app 的 LCAppInfo.plist（LCSelectedLanguage），
//    guest 启动时由 NSUserDefaults hook 注入，实现 openSSS 界面跟随。
//

import Foundation
import SwiftUI

enum TreeLanguage: String, CaseIterable, Identifiable {
    case system = ""            // 跟随系统
    case zhHans = "zh-Hans"     // 简体中文
    case zhHant = "zh-Hant"     // 繁體中文
    case ja = "ja"              // 日本語
    case ko = "ko"              // 한국어
    case th = "th"              // ไทย
    case ms = "ms"              // Bahasa Melayu
    case id = "id"              // Bahasa Indonesia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .th: return "ไทย"
        case .ms: return "Bahasa Melayu"
        case .id: return "Bahasa Indonesia"
        }
    }

    var localizedName: String {
        switch self {
        case .system: return "System"
        case .zhHans: return "Chinese (Simplified)"
        case .zhHant: return "Chinese (Traditional)"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .th: return "Thai"
        case .ms: return "Malay"
        case .id: return "Indonesian"
        }
    }
}

final class TreeLanguageManager {
    static let shared = TreeLanguageManager()

    /// App Group key，保证多开实例语言一致
    private static let key = "LCTreeLanguage"
    /// 语言切换通知
    static let didChangeNotification = Notification.Name("TreeNewBeeLanguageDidChange")

    private let defaults = LCUtils.appGroupUserDefault

    var current: TreeLanguage {
        get {
            let raw = defaults.string(forKey: Self.key) ?? ""
            return TreeLanguage(rawValue: raw) ?? .system
        }
    }

    /// root view 的 id，语言变化时重建整棵 SwiftUI 树
    var rootID: String { "lang-\(current.rawValue)-appearance" }

    /// 启动时调用：把已保存语言应用到宿主
    func applyAtLaunch() {
        applyHostLanguage(current)
    }

    func setLanguage(_ language: TreeLanguage) {
        defaults.set(language.rawValue, forKey: Self.key)
        applyHostLanguage(language)
        applyGuestLanguage(language)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - 宿主语言

    private func applyHostLanguage(_ language: TreeLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - openSSS guest 语言

    private func applyGuestLanguage(_ language: TreeLanguage) {
        // 写进内置 openSSS 的 LCAppInfo.plist，guest 启动时 hook 读取该值注入 AppleLanguages
        let appInfo = BuiltInSideStoreAppInfo.shared
        appInfo.selectedLanguage = language == .system ? "" : language.rawValue
    }
}
