// WeChatLoginSheet.swift
// DevBar

import SwiftUI

struct WeChatLoginSheet: View {
    @ObservedObject var authService: WeChatAuthService
    let onComplete: () -> Void

    @State private var qrImage: NSImage?
    @State private var lastQRImageData: Data?

    var body: some View {
        VStack(spacing: 20) {
            Text("wechat_login_title")
                .font(.headline)

            Group {
                switch authService.loginState {
                case .idle, .loading:
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(width: 200, height: 200)

                case .qrReady(let imageData):
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 200)
                    } else {
                        Text("wechat_qr_decode_error")
                            .frame(width: 200, height: 200)
                    }

                case .waiting:
                    qrOverlayView {
                        ProgressView()
                        Text("wechat_waiting_scan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .scanned:
                    qrOverlayView {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text("wechat_scanned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .confirmed:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("wechat_login_success")
                            .font(.headline)
                    }
                    .frame(width: 200, height: 200)

                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("wechat_retry") {
                            authService.startLogin()
                        }
                    }
                    .frame(width: 200, height: 200)
                }
            }

            Text("wechat_login_hint")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if case .confirmed = authService.loginState {
                    Button("wechat_done") {
                        authService.loadAccounts()
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") {
                        authService.cancelLogin()
                        onComplete()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            authService.startLogin()
        }
        .onChange(of: authService.loginState) { _, newState in
            if case .qrReady(let data) = newState {
                lastQRImageData = data
                qrImage = NSImage(data: data)
            }
            if case .confirmed = newState {
                // Auto-dismiss after short delay
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    authService.loadAccounts()
                    onComplete()
                }
            }
        }
    }

    @ViewBuilder
    private func qrOverlayView<Overlay: View>(@ViewBuilder overlay: () -> Overlay) -> some View {
        if let image = qrImage ?? lastQRImageData.flatMap(NSImage.init(data:)) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            VStack(spacing: 8) {
                                overlay()
                            }
                        )
                )
        } else {
            Text("wechat_qr_decode_error")
                .frame(width: 200, height: 200)
        }
    }
}
