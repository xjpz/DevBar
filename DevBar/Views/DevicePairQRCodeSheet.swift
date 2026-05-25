import CoreImage.CIFilterBuiltins
import DevBarCore
import SwiftUI

struct DevicePairQRCodeSheet: View {
    let payload: DeviceRelayPairQRCodePayload

    @Environment(\.dismiss) private var dismiss

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接 iPhone")
                .font(.title2.weight(.semibold))

            Text("用 iPhone DevBar 扫描二维码完成配对。二维码不包含设备密钥，过期后请重新生成。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                qrCodeView

                VStack(alignment: .leading, spacing: 10) {
                    Label("Relay：\(payload.relay.host ?? payload.relay.absoluteString)", systemImage: "network")
                    Label("配对码：\(payload.pairCode)", systemImage: "qrcode")
                    Label("Mac：\(payload.macDeviceId)", systemImage: "desktopcomputer")
                    Label(expirationText, systemImage: "clock")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var qrCodeView: some View {
        Group {
            if let text = try? DeviceRelayPairQRCodeCodec.encode(payload),
               let image = makeQRCodeImage(from: text) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .overlay {
                        Text("二维码生成失败")
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }

    private var expirationText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(payload.expiresAt) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "过期时间：\(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func makeQRCodeImage(from value: String) -> CGImage? {
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return context.createCGImage(transformed, from: transformed.extent)
    }
}
