import CoreImage.CIFilterBuiltins
import DevBarCore
import SwiftUI

struct TransferQRCodeSheet: View {
    let payload: TransferPayload
    let url: URL

    @Environment(\.dismiss) private var dismiss

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入到 iPhone")
                .font(.title2.weight(.semibold))

            Text("二维码包含账号凭证，只建议在你自己的可信设备之间迁移。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 20) {
                qrCodeView

                VStack(alignment: .leading, spacing: 10) {
                    Label(payload.deviceName ?? "This Mac", systemImage: "desktopcomputer")
                    Label(expirationText, systemImage: "clock")
                    Label(providerSummaryText, systemImage: "person.crop.circle.badge.checkmark")
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }

            Text("如果二维码过期，请关闭后重新生成。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var qrCodeView: some View {
        Group {
            if let image = makeQRCodeImage(from: url.absoluteString) {
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
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "过期时间：\(formatter.localizedString(for: payload.expiresAt, relativeTo: Date()))"
    }

    private var providerSummaryText: String {
        let names = payload.importedProviders.map(\.localizedName).joined(separator: " / ")
        return "包含 Provider：\(names)"
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
