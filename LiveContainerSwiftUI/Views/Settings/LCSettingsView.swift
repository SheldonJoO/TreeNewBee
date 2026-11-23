//
//  LCSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UserNotifications

enum JITEnablerType : Int, CaseIterable, Identifiable {
    var id: Int { rawValue }
    case SideJITServer = 0
    case StikJIT = 1
    case JITStreamerEBLegacy = 2
    case StikJITLC = 3
    case SideStore = 4
    case StosDebug = 5
    case StosDebugLC = 6
    
    var displayName: String {
        switch self {
        case .StikJIT: "StikDebug"
        case .StikJITLC: "StikDebug (Another TreeNewBee/Multitask)"
        case .StosDebug: "StosDebug"
        case .StosDebugLC: "StosDebug (Another TreeNewBee/Multitask)"
        case .SideStore: "openSSS"
        case .JITStreamerEBLegacy: "JitStreamer-EB (Relaunch)"
        case .SideJITServer: "SideJITServer/JITStreamer 2.0"
        }
    }
}

struct LCSettingsView: View {
    @State var errorShow = false
    @State var errorInfo = ""
    @State var successShow = false
    @State var successInfo = ""

    @State private var certificateDataFound = false
    
    @StateObject private var certificateImportAlert = YesNoHelper()
    @StateObject private var certificateImportFromBuiltInSideStoreAlert = YesNoHelper()
    @StateObject private var certificateRemoveAlert = YesNoHelper()
    @StateObject private var certificateImportFileAlert = AlertHelper<URL>()
    @StateObject private var certificateImportPasswordAlert = InputHelper()
    
    @AppStorage("LCFrameShortcutIcons") var frameShortIcon = false
    @AppStorage("LCSwitchAppWithoutAsking") var silentSwitchApp = false
    @AppStorage("LCOpenWebPageWithoutAsking") var silentOpenWebPage = false
    @AppStorage("LCDontSignApp", store: LCUtils.appGroupUserDefault) var dontSignApp = false
    @AppStorage("LCStrictHiding", store: LCUtils.appGroupUserDefault) var strictHiding = false
    @AppStorage("dynamicColors", store: LCUtils.appGroupUserDefault) var dynamicColors = true
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) var darkModeIcon = false
    
    @AppStorage("LCSideJITServerAddress", store: LCUtils.appGroupUserDefault) var sideJITServerAddress : String = ""
    @AppStorage("LCDeviceUDID", store: LCUtils.appGroupUserDefault) var deviceUDID: String = ""
    @AppStorage("LCJITEnablerType", store: LCUtils.appGroupUserDefault) var JITEnabler: JITEnablerType = .SideJITServer
    
    @State var store : Store = .Unknown
    
    @AppStorage("LCLoadTweaksToSelf") var injectToLCItelf = false
    @AppStorage("LCIgnoreJITOnLaunch") var ignoreJITOnLaunch = false
    @AppStorage("LCSelected32BitEmulator", store: LCUtils.appGroupUserDefault) var selected32BitEmulator : String = ""
    @AppStorage("LCKeepSelectedWhenQuit") var keepSelectedWhenQuit = false
    @AppStorage("LCWaitForDebugger") var waitForDebugger = false
    @AppStorage("LCSharePrivateDataWithLiveProcess") var sharePrivateDataWithLiveProcess = false
    @AppStorage("BKNoWatchdogs") var disableLiveProcessWatchdog = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    @State private var isViewAppeared = false
    @State private var showHelp = false
    
    let storeName = LCUtils.getStoreName()
    
    init() {
        _certificateDataFound = State(initialValue: LCSharedUtils.certificatePassword() != nil)
        _store = State(initialValue: LCUtils.store())
    }
    
    var body: some View {

        NavigationView {

            Form {

                managementSection

                helpSection

                diagnosticsSection

                aboutSection

                versionSection

            }

            .navigationBarTitle("lc.tabView.settings".loc)
            .alert("lc.common.error".loc, isPresented: $errorShow){
            } message: {
                Text(errorInfo)
            }
            .alert("lc.common.success".loc, isPresented: $successShow){
            } message: {
                Text(successInfo)
            }
            .sheet(isPresented: $showHelp) {

                LCHelpView(isPresent: $showHelp)

            }

        }

        .navigationViewStyle(StackNavigationViewStyle())

        .onAppear {

            if !isViewAppeared {

                guard sharedModel.selectedTab == .settings, let link = sharedModel.deepLink else { return }

                sharedModel.deepLink = nil

                handleURL(url: link)

                isViewAppeared = true

            }

        }

        .onChange(of: sharedModel.deepLink) { link in

            guard sharedModel.selectedTab == .settings, let link else { return }

            sharedModel.deepLink = nil

            handleURL(url: link)

        }

    }


    // TreeApps: 统一管理分组 —— 7 个二级菜单入口
    private var managementSection: some View {
                Section {
                    NavigationLink {
                        LCCertificateManagementView()
                    } label: {
                        TreeSettingsRow(icon: "key.horizontal", title: "证书管理", value: "签名 · JIT-less", color: TreeAppsTheme.accent)
                    }

                    NavigationLink {
                        LCGeneralSettingsView()
                    } label: {
                        TreeSettingsRow(icon: "gearshape.2", title: "通用管理", value: "主题 · 行为 · JIT", color: TreeAppsTheme.accent)
                    }

                    if (store != .Unknown && store != .ADP) || LCUtils.isAppGroupAltStoreLike() {
                        NavigationLink {
                            LCMultiLCManagementView()
                        } label: {
                            TreeSettingsRow(icon: "square.stack.3d.up", title: sharedModel.multiLCStatus == 2 ? "这是第二个 🌲树应用" : "多开管理", value: "", color: TreeAppsTheme.accent)
                        }
                        .disabled(sharedModel.multiLCStatus == 2)
                    }

                    NavigationLink {
                        LCSourcesView()
                    } label: {
                        TreeSettingsRow(icon: "link.badge.plus", title: "源管理", value: "App 源", color: TreeAppsTheme.accent)
                    }

                    NavigationLink {
                        LCTweaksView()
                    } label: {
                        TreeSettingsRow(icon: "wrench.and.screwdriver", title: "模块管理", value: "Tweaks", color: TreeAppsTheme.accent)
                    }

                    if sharedModel.multiLCStatus != 2 {
                        NavigationLink {
                            LCStorageManagementView()
                        } label: {
                            TreeSettingsRow(icon: "internaldrive", title: "存储管理", value: "", color: TreeAppsTheme.accent)
                        }
                    }

                    NavigationLink {
                        LCDataManagementView()
                    } label: {
                        TreeSettingsRow(icon: "folder", title: "数据管理", value: "", color: TreeAppsTheme.accent)
                    }

                    NavigationLink {
                        LCTreeWidgetSettingsView()
                    } label: {
                        TreeSettingsRow(icon: "rectangle.on.rectangle.angled", title: "小组件 App", value: "手动选择", color: TreeAppsTheme.accent)
                    }
                } header: {
                    Text("管理").font(TreeAppsTheme.sectionTitleFont)
                }
    }



    // 帮助与支持
    private var helpSection: some View {
                Section {
                    Button {
                        showHelp = true
                    } label: {
                        TreeSettingsRow(icon: "book", title: "使用指南", value: "", color: TreeAppsTheme.accent)
                    }
                    Link(destination: URL(string: "https://github.com/SheldonJoO/openSSS")!) {
                        TreeSettingsRow(icon: "chevron.left.forwardslash.chevron.right", title: "加入社群 · GitHub", value: "", color: TreeAppsTheme.accent)
                    }
                    Link(destination: URL(string: "https://x.com/SheldonJo_O")!) {
                        TreeSettingsRow(icon: "bubble.left.and.bubble.right", title: "支持 🌲树应用", value: "@SheldonJo_O", color: .pink)
                    }
                } header: {
                    Text("帮助与支持").font(TreeAppsTheme.sectionTitleFont)
                }
    }



    // 诊断
    private var diagnosticsSection: some View {
                Section {
                    NavigationLink {
                        LCJITLessDiagnoseView()
                    } label: {
                        TreeSettingsRow(icon: "doc.text.magnifyingglass", title: "免 JIT 模式诊断", value: "", color: TreeAppsTheme.accent)
                    }
                    Button {
                        clearNotifications()
                    } label: {
                        TreeSettingsRow(icon: "bell.badge", title: "清理通知", value: "", color: TreeAppsTheme.accent)
                    }
                } header: {
                    Text("诊断").font(TreeAppsTheme.sectionTitleFont)
                }
    }



    // 关于
    private var aboutSection: some View {
                Section {
                    NavigationLink {
                        LCTreeAppsAboutView()
                    } label: {
                        TreeSettingsRow(icon: "info.circle", title: "关于 🌲树应用", value: "致谢与社媒", color: TreeAppsTheme.accent)
                    }
                } header: {
                    Text("关于").font(TreeAppsTheme.sectionTitleFont)
                }

                // ============ 版本 / 开发者 ============
    }



    // 版本 / 开发者
    private var versionSection: some View {
        Group {
            VStack {
                Text(LCUtils.getVersionInfo())
                    .foregroundStyle(.gray)
                    .onTapGesture(count: 5) {
                        sharedModel.developerMode = true
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(UIColor.systemGroupedBackground))
            .listRowInsets(EdgeInsets())

            if sharedModel.developerMode {
                Section {
                        Toggle(isOn: $injectToLCItelf) { Text("lc.settings.injectLCItself".loc) }
                        Toggle(isOn: $ignoreJITOnLaunch) { Text("Ignore JIT on Launching App") }
                        Toggle(isOn: $keepSelectedWhenQuit) { Text("Keep Selected App when Quit") }
                        Toggle(isOn: $waitForDebugger) { Text("Wait For Debugger") }
                        Toggle(isOn: $sharePrivateDataWithLiveProcess) { Text("Allow Private Data access from LiveProcess") }
                        Toggle(isOn: $disableLiveProcessWatchdog) { Text("Disable LiveProcess watchdog termination") }
                        Button { export() } label: { Text("Export Cert") }
                        Button { exportDyld() } label: { Text("Export Dyld") }
                        Button { Task { await nukeSideStore() } } label: { Text("Nuke openSSS") }
                        Button { exportMainBundle() } label: { Text("Export Main Bundle") }
                        Button { resetSymbolOffsets() } label: { Text("Reset Symbol Offsets") }
                        Button { presentFLEXOverlay() } label: { Text("Show FLEX Overlay") }
                            .disabled(NSClassFromString("FLEXManager") == nil)
                    } header: {
                        Text("Developer Settings")
                    } footer: {
                        Text("lc.settings.injectLCItselfDesc".loc)
                    }
                }
        }
    }

    func openGitHub() {
        UIApplication.shared.open(URL(string: "https://github.com/LiveContainer/LiveContainer")!)
    }
    
    func openGitHub2() {
        UIApplication.shared.open(URL(string: "https://github.com/hugeBlack")!)
    }
    
    func openTwitter() {
        UIApplication.shared.open(URL(string: "https://twitter.com/khanhduytran0")!)
    }

    func clearNotifications() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
        if #available(iOS 16.0, *) {
            notificationCenter.setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    func export() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 1. Copy embedded.mobileprovision from the main bundle to Documents
        if let embeddedURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") {
            let destinationURL = documentsURL.appendingPathComponent("embedded.mobileprovision")
            do {
                try fileManager.copyItem(at: embeddedURL, to: destinationURL)
                print("Successfully copied embedded.mobileprovision to Documents.")
            } catch {
                print("Error copying embedded.mobileprovision: \(error)")
            }
        } else {
            print("embedded.mobileprovision not found in the main bundle.")
        }
        
        // 2. Read "certData" from UserDefaults and save to cert.p12 in Documents
        if let certData = LCUtils.certificateData() {
            let certFileURL = documentsURL.appendingPathComponent("cert.p12")
            do {
                try certData.write(to: certFileURL)
                print("Successfully wrote certData to cert.p12 in Documents.")
            } catch {
                print("Error writing certData to cert.p12: \(error)")
            }
        } else {
            print("certData not found in UserDefaults.")
        }
        
        // 3. Read "certPassword" from UserDefaults and save to pass.txt in Documents
        if let certPassword = LCSharedUtils.certificatePassword() {
            let passwordFileURL = documentsURL.appendingPathComponent("pass.txt")
            do {
                try certPassword.write(to: passwordFileURL, atomically: true, encoding: .utf8)
                print("Successfully wrote certPassword to pass.txt in Documents.")
            } catch {
                print("Error writing certPassword to pass.txt: \(error)")
            }
        } else {
            print("certPassword not found in UserDefaults.")
        }
    }
    
    func exportMainBundle() {
        let url = Bundle.main.bundleURL
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
            try fileManager.copyItem(at: url, to: destinationURL)
            print("Successfully copied main bundle to Documents.")
        } catch {
            print("Error copying main bundle \(error)")
        }
    }
    
    func resetSymbolOffsets() {
        LCUtils.appGroupUserDefault.removeObject(forKey: "symbolOffsetCache")
    }
    
    func presentFLEXOverlay() {
        let manager = (NSClassFromString("FLEXManager") as? NSObject.Type)?.perform(NSSelectorFromString("sharedManager"))
            .takeUnretainedValue() as? NSObject
        manager?.perform(NSSelectorFromString("showExplorer"))
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
        let certificateData : Data
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
        
        let storeScheme : String
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
    
    func nukeSideStore() async {
        guard let doRemove = await certificateRemoveAlert.open(), doRemove else {
            return
        }
        do {
            let fm = FileManager.default
            let sidestoreAppGroupURL = LCPath.lcGroupDocPath.deletingLastPathComponent()
            try fm.removeItem(at: sidestoreAppGroupURL.appendingPathComponent("Database"))
            try fm.removeItem(at: sidestoreAppGroupURL.appendingPathComponent("Apps"))
        } catch {
            print("wtf \(error)")
        }
    }
    
    func exportDyld() {
        let url = URL(fileURLWithPath: "/usr/lib/dyld")
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
            try fileManager.copyItem(at: url, to: destinationURL)
            print("Successfully copied dyld to Documents.")
        } catch {
            print("Error copying dyld \(error)")
        }
    }
    
    func handleURL(url: URL) {
        if url.host == "certificate" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
                guard let encodedCert = queryItems["cert"]?.removingPercentEncoding,
                      let password = queryItems["password"],
                      let certData = Data(base64Encoded: encodedCert)
                else { return }
                
                onSideStoreCertificateCallback(certificateData: certData, password: password)
                NotificationCenter.default.post(name: .treeAppsCertificateDidUpdate, object: nil)
                
            }
        }
    }
}
