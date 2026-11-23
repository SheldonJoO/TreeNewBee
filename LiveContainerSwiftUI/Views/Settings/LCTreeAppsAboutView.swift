//
//  LCTreeAppsAboutView.swift
//  LiveContainerSwiftUI (TreeApps)
//
//  TreeApps 关于 / 致谢页 —— 视觉沿用 openSSS Shell 风格。
//  致敬所有让这个项目成为可能的开源作者与项目。
//

import SwiftUI

private struct CreditLink: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let url: String
    let symbol: String
}

struct LCTreeAppsAboutView: View {
    private let ourLinks: [CreditLink] = [
        CreditLink(title: "openSSS · GitHub",
                   subtitle: "SheldonJoO/openSSS",
                   url: "https://github.com/SheldonJoO/openSSS",
                   symbol: "chevron.left.forwardslash.chevron.right"),
        CreditLink(title: "X · @SheldonJo_O",
                   subtitle: "Sheldon",
                   url: "https://x.com/SheldonJo_O",
                   symbol: "bubble.left.and.bubble.right"),
        CreditLink(title: "个人站点 · dntmove.asia",
                   subtitle: "https://dntmove.asia",
                   url: "https://dntmove.asia",
                   symbol: "globe"),
    ]

    private let upstreamLinks: [CreditLink] = [
        CreditLink(title: "LiveContainer",
                   subtitle: "khanhduytran0 · 宿主容器 / guest 机制",
                   url: "https://github.com/LiveContainer/LiveContainer",
                   symbol: "shippingbox"),
        CreditLink(title: "openSSS / SideStore",
                   subtitle: "内置的侧载与签名核心",
                   url: "https://github.com/SheldonJoO/openSSS",
                   symbol: "signature"),
        CreditLink(title: "AltStore",
                   subtitle: "Riley Testut · 侧载奠基",
                   url: "https://github.com/rileytestut/AltStore",
                   symbol: "app.badge"),
        CreditLink(title: "SideJITServer / StikDebug",
                   subtitle: "JIT 注入方案",
                   url: "https://github.com/Phone-JBCreator/SideJITServer",
                   symbol: "bolt"),
        CreditLink(title: "dylibify",
                   subtitle: "Mach-O 转 dylib 工具",
                   url: "https://github.com/LiveContainer/dylibify",
                   symbol: "wrench.and.screwdriver"),
    ]

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        List {
            // Header: Logo + 名称 + 版本（对照 openSSS AboutViewController）
            Section {
                VStack(spacing: 8) {
                    if let logo = UIImage(named: "TreeAppsLogo") {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: TreeAppsTheme.iconCornerRadius))
                    }
                    Text("TreeNewBee")
                        .font(TreeAppsTheme.headingFont)
                        .foregroundStyle(TreeAppsTheme.primaryText)
                    Text("版本 \(versionText)")
                        .font(.system(size: 14))
                        .foregroundStyle(TreeAppsTheme.secondaryText)
                    Text("树应用 = LiveContainer × openSSS 合体单 IPA")
                        .font(.system(size: 13))
                        .foregroundStyle(TreeAppsTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                ForEach(ourLinks) { link in linkRow(link) }
            } header: {
                Text("我们的项目与社媒").font(TreeAppsTheme.sectionTitleFont)
            } footer: {
                Text("🌲树应用 由 東't-Move 维护，欢迎 Star 与反馈。")
            }

            Section {
                ForEach(upstreamLinks) { link in linkRow(link) }
            } header: {
                Text("致敬上游开源项目").font(TreeAppsTheme.sectionTitleFont)
            } footer: {
                Text("🌲树应用 站在这些项目的肩膀上。没有他们就没有这一切——致所有开源作者。")
            }

            Section {
                Link(destination: URL(string: "https://github.com/SheldonJoO/openSSS")!) {
                    Label("开源组件与许可证", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://github.com/LiveContainer/LiveContainer/blob/main/LICENSE")!) {
                    Label("LiveContainer 许可证", systemImage: "scale.3d")
                }
            } header: {
                Text("许可").font(TreeAppsTheme.sectionTitleFont)
            }
        }
        .navigationTitle("关于 🌲树应用")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func linkRow(_ link: CreditLink) -> some View {
        Link(destination: URL(string: link.url)!) {
            HStack(spacing: 12) {
                Image(systemName: link.symbol)
                    .foregroundStyle(TreeAppsTheme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                        .font(TreeAppsTheme.rowTitleFont)
                        .foregroundStyle(TreeAppsTheme.primaryText)
                    Text(link.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(TreeAppsTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TreeAppsTheme.secondaryText)
            }
            .padding(.vertical, 4)
        }
    }
}
