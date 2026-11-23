//
//  TreeOpenSSSTabView.swift
//  TreeNewBee —— 最左侧 openSSS Tab
//
//  点进这个 Tab 就一键启动内置 openSSS。启动是 in-process 的，
//  切到 guest 后宿主界面会退到后台，所以这里只是个过场页 + 失败兜底按钮。
//

import SwiftUI

struct TreeOpenSSSTabView: View {
    @State private var launched = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TreeAppsTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                if let icon = BuiltInSideStoreAppInfo.shared.iconIsDarkIcon(false) {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                }

                Text("openSSS")
                    .font(.title2.weight(.semibold))

                Text("正在打开 openSSS…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    launch()
                } label: {
                    Label("打开 openSSS", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

                Text("若没有自动跳转，点上面的按钮再试一次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("openSSS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { launch() }
        .onChange(of: scenePhase) { phase in
            // 从 openSSS 切回来时允许再次启动
            if phase == .active { launched = false }
        }
    }

    private func launch() {
        guard !launched else { return }
        launched = true
        LCUtils.openSideStore()
        // 留一点余地：若启动失败，几秒后解锁按钮允许重试
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            launched = false
        }
    }
}
