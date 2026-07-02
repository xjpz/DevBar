import SwiftUI
import UIKit

// MARK: - QR Code

struct IOSQRCodeView: View {
    @Environment(\.themeTokens) private var theme
    @State private var inputText = "https://example.com"
    @State private var foregroundColor: Color = .black
    @State private var backgroundColor: Color = .white
    @State private var correctionLevel: QRCorrectionLevel = .high
    @State private var copyFeedback = false
    @State private var statusToast: IOSStatusToastKind?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                inputSection
                previewSection
                actionButtons
            }
            .padding(16)
        }
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_tools_qr_code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .overlay {
            if let statusToast {
                IOSStatusToast(toastTitle(for: statusToast), kind: statusToast, theme: theme)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.22), value: statusToast)
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ios_tools_qr_content")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60)
                .scrollContentBackground(.hidden)
                .padding(10)
                .iosGlassContainer(theme, cornerRadius: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )

            HStack(spacing: 12) {
                colorPicker(label: String(localized: "ios_tools_qr_fg_color"), color: $foregroundColor)
                colorPicker(label: String(localized: "ios_tools_qr_bg_color"), color: $backgroundColor)
            }

            correctionPicker
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 18)
    }

    private func colorPicker(label: String, color: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.wrappedValue)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.borderSubtle, lineWidth: 1)
                    )
                ColorPicker("", selection: color, supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var correctionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ios_tools_qr_correction")
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Picker("ios_tools_qr_correction", selection: $correctionLevel) {
                ForEach(QRCorrectionLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(spacing: 0) {
            if let qrImage = generateQRImage() {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(20)
                    .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.borderSubtle, lineWidth: 1)
                    )
                    .overlay {
                        if copyFeedback {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(theme.brandPrimary.opacity(0.2))
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundStyle(theme.brandPrimary)
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: copyFeedback)
            } else {
                ContentUnavailableView("Enter text to generate", systemImage: "qrcode")
                    .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                copyToClipboard()
            } label: {
                Label("ios_tools_qr_copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(theme.brandPrimary)
            .disabled(generateQRImage() == nil)

            Button {
                saveToPhotos()
            } label: {
                Label("ios_tools_qr_save", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(theme.brandPrimary)
            .disabled(generateQRImage() == nil)
        }
    }

    // MARK: - QR Generation

    private func generateQRImage() -> UIImage? {
        let data = inputText.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
        guard let data, !data.isEmpty else { return nil }

        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")

        guard let output = qrFilter.outputImage else { return nil }
        let scaled = output.transformed(by: .init(scaleX: 10, y: 10))

        guard let colorFilter = CIFilter(name: "CIFalseColor") else { return nil }
        colorFilter.setValue(scaled, forKey: "inputImage")
        colorFilter.setValue(CIColor(color: UIColor(foregroundColor)), forKey: "inputColor0")
        colorFilter.setValue(CIColor(color: UIColor(backgroundColor)), forKey: "inputColor1")

        guard let colored = colorFilter.outputImage else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(colored, from: colored.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Actions

    private func copyToClipboard() {
        guard let image = generateQRImage() else { return }
        UIPasteboard.general.image = image
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            copyFeedback = false
        }
    }

    private func saveToPhotos() {
        guard let image = generateQRImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showToast(.success)
    }

    private func showToast(_ toast: IOSStatusToastKind) {
        withAnimation {
            self.statusToast = toast
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation {
                if self.statusToast == toast {
                    self.statusToast = nil
                }
            }
        }
    }

    private func toastTitle(for toast: IOSStatusToastKind) -> String {
        switch toast {
        case .success:
            return "Saved"
        case .failure:
            return "Failed"
        }
    }
}

enum QRCorrectionLevel: String, CaseIterable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .quartile: return "Quartile"
        case .high: return "High"
        }
    }
}
