//
//  LCCertificateImportView.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  证书导入 —— 把外部 .p12 + 密码写进 openSSS 使用的 Keychain,
//  让内置 openSSS 立刻把它当作 activeSigningCertificate 用于签名 / 刷新 / 安装。
//
//  与 LCCertificateExportView 是一对:
//    导出 = Keychain -> .p12 文件
//    导入 = .p12 文件 -> Keychain
//
//  两个关键约束:
//  1) openSSS 的 Keychain 实例是
//        KeychainAccess.Keychain(service: Bundle.Info.appbundleIdentifier)
//            .accessibility(.afterFirstUnlock).synchronizable(true)
//     所以写入必须带 kSecAttrAccessibleAfterFirstUnlock + kSecAttrSynchronizable=true,
//     否则 KeychainAccess 带 synchronizable 条件的查询读不到。
//  2) appbundleIdentifier 被 LiveContainer hook 成 com.kdt.livecontainer,
//     但 static let 惰性常量在部分构建下 swizzle 不生效, 实际可能仍是 com.openssai.app。
//     所以两个 service 都写, 谁生效用谁。
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LCCertificateImportView: View {
    @State private var p12Data: Data?
    @State private var p12Filename: String = ""
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var teamID: String?
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @State private var importedServices: [String] = []

    private let candidateServices = ["com.kdt.livecontainer", "com.openssai.app"]

    var body: some View {
        // TreeApps: 由证书管理页 push 进入，沿用父级导航栈，不再自带 NavigationView
        Form {
            fileSection
            passwordSection
            if teamID != nil {
                verifiedSection
            }
            importSection
            if let resultMessage {
                Section {
                    Label(resultMessage, systemImage: resultIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundColor(resultIsError ? .red : TreeAppsTheme.teal)
                        .font(.footnote)
                }
            }
            Section {
                Text("导入后请完全退出 🌲树应用 再重新打开，内置 openSSS 会在启动时重新加载证书。导出的 .p12 与密码必须成对，密码错误会导致签名失败。证书与私钥仅写入本机 Keychain，不会上传。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text("说明")
            }
        }
        .navigationTitle("导入签名证书")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFile(result)
        }
        .treeAppsTheme()
    }

    // MARK: - Sections

    private var fileSection: some View {
        Section {
            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: p12Data == nil ? "doc.badge.plus" : "doc.fill.badge.checkmark")
                        .foregroundColor(p12Data == nil ? .secondary : TreeAppsTheme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p12Data == nil ? "选择 .p12 证书文件" : p12Filename)
                        if let p12Data {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(p12Data.count), countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("证书文件")
        }
    }

    private var passwordSection: some View {
        Section {
            HStack {
                if showPassword {
                    TextField("证书密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("证书密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: password) { _ in revalidateIfNeeded() }
            if p12Data != nil && password.isEmpty {
                Text("openSSS 导出的 .p12 通常密码就是证书序列号；若从其他渠道导出，请填导出时设定的密码。留空表示无密码 p12。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("密码")
        }
    }

    private var verifiedSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(TreeAppsTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("密码验证通过")
                    if let teamID {
                        Text("Team ID: \(teamID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("校验结果")
        }
    }

    private var importSection: some View {
        Section {
            Button {
                importCertificate()
            } label: {
                HStack {
                    Label("写入 openSSS Keychain", systemImage: "square.and.arrow.down")
                    Spacer()
                    if isImporting {
                        ProgressView()
                    }
                }
            }
            .disabled(p12Data == nil || isImporting)
        } footer: {
            Text("写入 \(candidateServices.count) 个 Keychain service，确保 openSSS 无论被 hook 成哪个 Bundle ID 都能读到。")
        }
    }

    // MARK: - Logic

    private func handleFile(_ result: Result<[URL], Error>) {
        resultMessage = nil
        teamID = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                p12Data = data
                p12Filename = url.lastPathComponent
                // 用 p12 当前密码尝试解析，验证密码是否正确
                if !password.isEmpty {
                    teamID = LCUtils.getCertTeamId(withKeyData: data, password: password)
                }
            } catch {
                setResult("读取文件失败: \(error.localizedDescription)", isError: true)
            }
        case .failure(let error):
            setResult("选择文件失败: \(error.localizedDescription)", isError: true)
        }
    }

    /// 密码变化时重新校验（只在已有文件时）
    private func revalidateIfNeeded() {
        guard let data = p12Data, !password.isEmpty else {
            teamID = nil
            return
        }
        teamID = LCUtils.getCertTeamId(withKeyData: data, password: password)
    }

    private func importCertificate() {
        guard let data = p12Data else { return }
        isImporting = true
        resultMessage = nil

        // 若填了密码，先校验，避免写入一个 openSSS 解不开的证书
        if !password.isEmpty {
            let tid = LCUtils.getCertTeamId(withKeyData: data, password: password)
            guard tid != nil else {
                setResult("密码错误或证书无效，未写入。请核对 .p12 与密码。", isError: true)
                isImporting = false
                return
            }
            teamID = tid
        }

        var succeeded: [String] = []
        for service in candidateServices {
            let certOK = writeKeychain(
                service: service,
                account: "signingCertificate",
                data: data
            )
            let passOK = writeKeychain(
                service: service,
                account: "signingCertificatePassword",
                data: Data(password.utf8)
            )
            if certOK && passOK { succeeded.append(service) }
        }

        isImporting = false
        if succeeded.isEmpty {
            setResult("写入失败：Keychain 拒绝了本次写入。", isError: true)
        } else {
            importedServices = succeeded
            setResult("已写入 \(succeeded.count)/\(candidateServices.count) 个 service：\(succeeded.joined(separator: ", "))。请重启 🌲树应用 生效。", isError: false)
        }
    }

    /// 写入单个 Keychain item。
    /// 先按 SynchronizableAny 删除同名项，再以 openSSS 期望的属性新增，
    /// 避免遗留 item 的属性（synchronizable=false / accessible 不同）导致读取失败。
    private func writeKeychain(service: String, account: String, data: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var deleteQuery = base
        deleteQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = base
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecAttrSynchronizable as String] = true

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[TreeNewBee] keychain write failed service=\(service) account=\(account) status=\(status)")
        }
        return status == errSecSuccess
    }

    private func setResult(_ message: String, isError: Bool) {
        resultMessage = message
        resultIsError = isError
    }
}
