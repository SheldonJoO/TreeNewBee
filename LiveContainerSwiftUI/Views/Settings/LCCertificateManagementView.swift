//
//  LCCertificateManagementView.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  证书管理二级页：JIT-less 证书导入/移除/刷新 + 签名证书导入/导出。
//  从 LCSettingsView 拆出，统一收进「管理 → 证书管理」。
//

import SwiftUI
import UserNotifications

extension Notification.Name {
    static let treeAppsCertificateDidUpdate = Notification.Name("TreeNewBeeCertificateDidUpdate")
}

struct LCCertificateManagementView: View {
    @State var errorShow = false
    @State var errorInfo = ""

    @State private var certificateDataFound = false

    @StateObject private var certificateImportAlert = YesNoHelper()
    @StateObject private var certificateImportFromBuiltInSideStoreAlert = YesNoHelper()
    @StateObject private var certificateRemoveAlert = YesNoHelper()
    @StateObject private var certificateImportFileAlert = AlertHelper<URL>()
    @StateObject private var certificateImportPasswordAlert = InputHelper()

    @State var store: Store = .Unknown
    @EnvironmentObject private var sharedModel: SharedModel

    let storeName = LCUtils.getStoreName()

    init() {
        _certificateDataFound = State(initialValue: LCSharedUtils.certificatePassword() != nil)
        _store = State(initialValue: LCUtils.store())
    }

    var body: some View {
        Form {
            if sharedModel.multiLCStatus != 2 {
                Section {
                    if !certificateDataFound {
                        Button {
                            Task { await importCertificate() }
                        } label: {
                            TreeSettingsRow(icon: "key", title: "导入 JIT-less 证书", value: "", color: TreeAppsTheme.accent)
                        }
                    } else {
                        Button {
                            Task { await removeCertificate() }
                        } label: {
                            TreeSettingsRow(icon: "key.fill", title: "移除 JIT-less 证书", value: "", color: TreeAppsTheme.accent)
                        }
                    }
                    if store == .AltStore || store == .SideStore {
                        Button {
                            Task { await importCertificateFromSideStore() }
                        } label: {
                            TreeSettingsRow(icon: "arrow.triangle.2.circlepath", title: certificateDataFound ? "刷新 \(storeName) 证书" : "从 \(storeName) 导入证书", value: "", color: TreeAppsTheme.accent)
                        }
                    }
                } header: {
                    Text("JIT-less 签名证书").font(TreeAppsTheme.sectionTitleFont)
                } footer: {
                    Text("用于免 JIT 启动。证书与密码写入 App Group 共享存储。").font(.footnote)
                }

                Section {
                    NavigationLink {
                        LCCertificateImportView()
                    } label: {
                        TreeSettingsRow(icon: "square.and.arrow.down", title: "导入签名证书", value: "openSSS p12", color: TreeAppsTheme.accent)
                    }
                    NavigationLink {
                        LCCertificateExportView()
                    } label: {
                        TreeSettingsRow(icon: "square.and.arrow.up", title: "导出签名证书", value: "p12 + 密码", color: TreeAppsTheme.accent)
                    }
                } header: {
                    Text("签名证书").font(TreeAppsTheme.sectionTitleFont)
                } footer: {
                    Text("在电脑侧载工具里导出的 .p12 与密码，可导入给内置 openSSS 使用；也可反向导出给电脑。").font(.footnote)
                }

                Section {
                    NavigationLink {
                        LCJITLessDiagnoseView()
                    } label: {
                        TreeSettingsRow(icon: "doc.text.magnifyingglass", title: "证书状态诊断", value: "", color: TreeAppsTheme.accent)
                    }
                } header: {
                    Text("诊断").font(TreeAppsTheme.sectionTitleFont)
                }
            } else {
                Section {
                    Text("当前是第二个 🌲树应用，证书由主实例管理")
                        .font(TreeAppsTheme.rowValueFont)
                        .foregroundStyle(TreeAppsTheme.secondaryText)
                }
            }
        }
        .navigationTitle("证书管理")
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow) {
        } message: {
            Text(errorInfo)
        }
        .alert("lc.settings.importCertificate".loc, isPresented: $certificateImportAlert.show) {
            Button {
                certificateImportAlert.close(result: true)
            } label: {
                Text("lc.common.ok".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                certificateImportAlert.close(result: false)
            }
        } message: {
            Text("lc.settings.importCertificateDesc".loc)
        }
        .alert("lc.settings.removeCertificate".loc, isPresented: $certificateRemoveAlert.show) {
            Button(role: .destructive) {
                certificateRemoveAlert.close(result: true)
            } label: {
                Text("lc.common.ok".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                certificateRemoveAlert.close(result: false)
            }
        } message: {
            Text("lc.settings.removeCertificateDesc".loc)
        }
        .alert("lc.settings.importCertFromBuiltinSideStore".loc, isPresented: $certificateImportFromBuiltInSideStoreAlert.show) {
            Button {
                certificateImportFromBuiltInSideStoreAlert.close(result: true)
            } label: {
                Text("lc.common.ok".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                certificateImportFromBuiltInSideStoreAlert.close(result: false)
            }
        } message: {
            Text("lc.settings.importCertFromBuiltinSideStoreDesc".loc)
        }
        .betterFileImporter(isPresented: $certificateImportFileAlert.show, types: [.p12], multiple: false, callback: { fileUrls in
            certificateImportFileAlert.close(result: fileUrls[0])
        }, onDismiss: {
            certificateImportFileAlert.close(result: nil)
        })
        .textFieldAlert(
            isPresented: $certificateImportPasswordAlert.show,
            title: "lc.settings.importCertificateInputPassword".loc,
            text: $certificateImportPasswordAlert.initVal,
            placeholder: "",
            action: { newText in
                certificateImportPasswordAlert.close(result: newText)
            },
            actionCancel: { _ in
                certificateImportPasswordAlert.close(result: nil)
                certificateImportPasswordAlert.show = false
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .treeAppsCertificateDidUpdate)) { _ in
            certificateDataFound = LCSharedUtils.certificatePassword() != nil
        }
    }

    func importCertificate() async {
        guard let doImport = await certificateImportAlert.open(), doImport else {
            return
        }
        guard let certificateURL = await certificateImportFileAlert.open() else {
            return
        }
        guard let certificatePassword = await certificateImportPasswordAlert.open() else {
            return
        }
        let certificateData: Data
        do {
            certificateData = try Data(contentsOf: certificateURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }

        guard let _ = LCUtils.getCertTeamId(withKeyData: certificateData, password: certificatePassword) else {
            errorInfo = "lc.settings.invalidCertError".loc
            errorShow = true
            return
        }

        LCUtils.appGroupUserDefault.set(certificateData, forKey: "LCCertificateData")
        LCUtils.appGroupUserDefault.set(certificatePassword, forKey: "LCCertificatePassword")
        LCUtils.appGroupUserDefault.set(NSDate.now, forKey: "LCCertificateUpdateDate")
        certificateDataFound = true

        UserDefaults.standard.set(LCSharedUtils.appGroupID(), forKey: "LCAppGroupID")
    }

    func importCertificateFromSideStore() async {
        if UserDefaults.sideStoreExist() {
            if let ans = await certificateImportFromBuiltInSideStoreAlert.open(), ans {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: "signingCertificate",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecAttrService as String: "com.kdt.livecontainer",
                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
                ]

                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)

                guard status == errSecSuccess else {
                    if status == errSecItemNotFound {
                        errorInfo = "lc.settings.importCertFromBuiltinSideStore.certNotFounndErr".loc
                        errorShow = true
                    } else {
                        errorInfo = "Keychain read error: \(status)"
                        errorShow = true
                    }
                    return
                }

                guard let data = item as? Data else {
                    errorInfo = "Failed to decode certificate data"
                    errorShow = true
                    return
                }

                let passwordQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: "signingCertificatePassword",
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecAttrService as String: "com.kdt.livecontainer",
                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
                ]

                var passwordItem: CFTypeRef?
                let passwordStatus = SecItemCopyMatching(passwordQuery as CFDictionary, &passwordItem)
                var password = ""
                if passwordStatus == errSecSuccess,
                   let passwordData = passwordItem as? Data,
                   let pwd = String(data: passwordData, encoding: .utf8) {
                    password = pwd
                }

                onSideStoreCertificateCallback(certificateData: data, password: password)
                return
            }
        }

        let storeScheme: String
        if store == .AltStore {
            storeScheme = "altstore-classic"
        } else {
            storeScheme = "sidestore"
        }

        guard let url = URL(string: "\(storeScheme.lowercased())://certificate?callback_template=livecontainer%3A%2F%2Fcertificate%3Fcert%3D%24%28BASE64_CERT%29%26password%3D%24%28PASSWORD%29") else {
            errorInfo = "Failed to initialize certificate import URL."
            errorShow = true
            return
        }
        await UIApplication.shared.open(url)
    }

    func onSideStoreCertificateCallback(certificateData: Data, password: String) {
        LCUtils.appGroupUserDefault.set(certificateData, forKey: "LCCertificateData")
        LCUtils.appGroupUserDefault.set(password, forKey: "LCCertificatePassword")
        LCUtils.appGroupUserDefault.set(NSDate.now, forKey: "LCCertificateUpdateDate")
        certificateDataFound = true
    }

    func removeCertificate() async {
        guard let doRemove = await certificateRemoveAlert.open(), doRemove else {
            return
        }

        LCUtils.appGroupUserDefault.set(nil, forKey: "LCCertificateData")
        LCUtils.appGroupUserDefault.set(nil, forKey: "LCCertificatePassword")
        LCUtils.appGroupUserDefault.set(nil, forKey: "LCCertificateUpdateDate")
        certificateDataFound = false

        UserDefaults.standard.set(nil, forKey: "LCAppGroupID")
    }
}
