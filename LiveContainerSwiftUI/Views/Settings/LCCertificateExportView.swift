//
//  LCCertificateExportView.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  证书导出功能 —— 从 openSSS 使用的 Keychain 中读取签名证书，
//  导出为 .p12 文件并给出密码。UI 与 openSSS 证书详情页风格统一。
//
//  为什么需要双 service 探测：
//  openSSS 通过 @objc dynamic static let appbundleIdentifier 写 Keychain，
//  合体后该值被 LiveContainer hook 为 com.kdt.livecontainer，
//  但 static let 惰性常量的 swizzle 在部分构建下不生效，
//  实际 service 仍可能是 com.openssai.app。
//  因此两个 service 都尝试，谁读到用谁，避免"证书明明在却读不到"。
//

import SwiftUI
import UIKit

struct LCCertificateExportView: View {
    @State private var p12Data: Data?
    @State private var password: String = ""
    @State private var sourceService: String = ""
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var copiedPassword = false
    @State private var showExported = false

    // openSSS 与合体后可能的两种 Keychain service
    private let candidateServices = ["com.kdt.livecontainer", "com.openssai.app"]

    var body: some View {
        // TreeApps: 由证书管理页 push 进入，沿用父级导航栈，不再自带 NavigationView
        Form {
            statusSection
            if let p12Data {
                exportSection(p12Data: p12Data)
            }
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundColor(.red)
                        .font(.footnote)
                } header: {
                    Text("导出失败")
                }
            }
            Section {
                Text("导出的 .p12 文件包含签名证书和私钥，请妥善保管。导入到其他设备时需要同时提供下方密码。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("说明")
            }
        }
        .navigationTitle("导出签名证书")
        .navigationBarTitleDisplayMode(.inline)
        .treeAppsTheme()
        .task { loadCertificate() }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("正在读取证书…").foregroundColor(.secondary)
                }
            } else if p12Data != nil {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(TreeAppsTheme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已找到签名证书")
                        Text("Keychain service: \(sourceService)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.seal")
                        .foregroundColor(.red)
                    Text("未找到可导出的证书")
                }
            }
        } header: {
            Text("证书状态")
        }
    }

    private func exportSection(p12Data: Data) -> some View {
        Section {
            // 分享 .p12 文件
            Button {
                exportP12(p12Data)
            } label: {
                Label("导出 .p12 文件", systemImage: "square.and.arrow.up")
            }

            // 复制密码
            Button {
                UIPasteboard.general.string = password
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copiedPassword = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedPassword = false }
            } label: {
                HStack {
                    Label("复制证书密码", systemImage: "key")
                    Spacer()
                    if copiedPassword {
                        Image(systemName: "checkmark")
                            .foregroundColor(TreeAppsTheme.teal)
                    } else if !password.isEmpty {
                        Text(password)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 复制 Base64（给 LiveContainer 类 App 的 URL 导入用）
            Button {
                UIPasteboard.general.string = p12Data.base64EncodedString()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("复制 Base64 编码", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("导出")
        } footer: {
            Text("文件大小 \(ByteCountFormatter.string(fromByteCount: Int64(p12Data.count), countStyle: .file))")
        }
    }

    // MARK: - Logic

    /// 依次尝试候选 service，读取 p12 数据与密码。
    private func loadCertificate() {
        isLoading = true
        loadError = nil

        var foundData: Data?
        var foundService = ""
        var foundPassword = ""

        for service in candidateServices {
            if let data = readKeychainData(account: "signingCertificate", service: service) {
                foundData = data
                foundService = service
                // 密码跟随同一个 service 读，读不到则为空串（openSSS 无密码 p12 常见）
                foundPassword = readKeychainString(account: "signingCertificatePassword", service: service) ?? ""
                break
            }
        }

        DispatchQueue.main.async {
            self.isLoading = false
            self.sourceService = foundService
            if let foundData {
                self.p12Data = foundData
                self.password = foundPassword
            } else {
                self.loadError = "在 Keychain 中未找到签名证书。请先在 openSSS 中导入证书，再回到此处导出。"
            }
        }
    }

    private func readKeychainData(account: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func readKeychainString(account: String, service: String) -> String? {
        guard let data = readKeychainData(account: account, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 写临时 .p12 文件并调用系统分享面板。
    private func exportP12(_ data: Data) {
        let filename = "openSSS-signing-certificate.p12"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL, options: .atomic)
            guard let rootVC = topViewController() else { return }
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = rootVC.view.bounds
            }
            rootVC.present(activityVC, animated: true)
        } catch {
            loadError = "写入临时文件失败: \(error.localizedDescription)"
        }
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              var vc = window.rootViewController else { return nil }
        while let presented = vc.presentedViewController { vc = presented }
        return vc
    }
}
