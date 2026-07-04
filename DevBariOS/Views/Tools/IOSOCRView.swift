import SwiftUI
import UIKit
import Vision
import PhotosUI

// MARK: - OCR

struct IOSOCRView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.iosToolEntryContext) private var toolEntryContext
    @State private var selectedImage: UIImage?
    @State private var recognizedText = ""
    @State private var isRecognizing = false
    @State private var copyFeedback = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                actionButtons
                imagePreview
                if isRecognizing {
                    ProgressView("ios_tools_ocr_recognizing")
                        .padding(.vertical, 8)
                }
                resultSection
            }
            .padding(16)
        }
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("OCR")
        .iosToolTitleDisplayMode(toolEntryContext)
        .toolbar(toolEntryContext.tabBarVisibility, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: toolEntryContext.showsBackButton)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios_tools_ocr_clear") {
                        selectedImage = nil
                        recognizedText = ""
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .iosToolToolbarIcon(theme)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            IOSCameraPicker { image in
                selectedImage = image
                recognizeText(from: image)
            }
        }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    recognizeText(from: image)
                }
                selectedItem = nil
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("ios_tools_ocr_camera", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(theme.brandPrimary)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("ios_tools_ocr_library", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(theme.brandPrimary)
        }
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        Group {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.textSecondary)
                    Text("ios_tools_ocr_placeholder")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .iosGlassContainer(theme, cornerRadius: 18)
            }
        }
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ios_tools_ocr_result")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
            }

            if recognizedText.isEmpty && !isRecognizing {
                Text("ios_tools_ocr_empty")
                    .foregroundStyle(theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .iosGlassContainer(theme, cornerRadius: 18)
            } else {
                ScrollView {
                    Text(recognizedText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(minHeight: 120, alignment: .top)
                .iosGlassContainer(theme, cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )

                if !recognizedText.isEmpty {
                    IOSToolCopyButton(isCopied: copyFeedback) {
                        copyResult()
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: copyFeedback)
    }

    // MARK: - OCR

    private func recognizeText(from image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        isRecognizing = true
        recognizedText = ""

        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    isRecognizing = false
                }
                return
            }

            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            DispatchQueue.main.async {
                recognizedText = lines.joined(separator: "\n")
                isRecognizing = false
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func copyResult() {
        UIPasteboard.general.string = recognizedText
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copyFeedback = false
        }
    }
}

struct IOSCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
