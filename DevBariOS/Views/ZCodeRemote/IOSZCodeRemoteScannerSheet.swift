import SwiftUI
import UIKit
import DevBarCore

/// 扫码 / 粘贴链接接入 zcode 远控，确认后回调。
/// host 与桌面主机名只在确认页出现一次，确认后不再展示。
struct IOSZCodeRemoteScannerSheet: View {
    var startsWithPaste = false
    let onConfirmed: (ZCodeRemoteLink) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme

    @State private var pendingLink: ZCodeRemoteLink?
    @State private var scanAttemptID = 0
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let pendingLink {
                    confirmPage(pendingLink)
                        .transition(.opacity)
                } else {
                    IOSQRScannerView(onCodeScanned: handleRawValue)
                        .id(scanAttemptID)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("ios_zcode_remote_scanner_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("ios_common_cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .bottom) {
                if pendingLink == nil {
                    pasteButton
                        .padding(.bottom, 48)
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    IOSStatusToast(toastMessage, kind: .failure, theme: theme)
                        .padding(.bottom, 120)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onAppear {
                if startsWithPaste {
                    handlePaste()
                }
            }
        }
    }

    private var pasteButton: some View {
        Button {
            handlePaste()
        } label: {
            Label("ios_zcode_remote_paste_button", systemImage: "doc.on.clipboard")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func confirmPage(_ link: ZCodeRemoteLink) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 48)

            VStack(spacing: 10) {
                Text("ios_zcode_remote_confirm_title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("ios_zcode_remote_confirm_host_format \(link.url.host ?? ZCodeRemoteLink.allowedHost)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                if let desktopName = link.desktopName {
                    Text("ios_zcode_remote_confirm_name_format \(desktopName)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Label("ios_zcode_remote_confirm_security", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.yellow.opacity(0.9))
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                onConfirmed(link)
                dismiss()
            } label: {
                Text("ios_zcode_remote_confirm_button")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handlePaste() {
        guard let rawValue = UIPasteboard.general.string, !rawValue.isEmpty else {
            showToast(String(localized: "ios_zcode_remote_paste_empty"))
            return
        }
        handleRawValue(rawValue)
    }

    private func handleRawValue(_ rawValue: String) {
        guard let link = ZCodeRemoteLink(rawValue: rawValue) else {
            showToast(String(localized: "ios_zcode_remote_invalid_link"))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                // 重建扫码视图以复位相机与一次性扫码闩锁
                scanAttemptID += 1
            }
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            pendingLink = link
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard toastMessage == message else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                toastMessage = nil
            }
        }
    }
}
