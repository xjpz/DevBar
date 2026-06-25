import SwiftUI
import Speech
import AVFoundation
import Combine

// MARK: - Speech to Text

final class IOSSpeechManager: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var partialText = ""
    @Published var errorMessage: String?

    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var wantsRecording = false

    func startRecording() {
        wantsRecording = true
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async { self?.errorMessage = String(localized: "ios_tools_speech_denied") }
                return
            }

            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async { self?.errorMessage = String(localized: "ios_tools_speech_mic_denied") }
                    return
                }

                DispatchQueue.main.async {
                    guard self?.wantsRecording == true else { return }
                    do {
                        try self?.setupAudioEngine()
                        self?.isRecording = true
                        self?.errorMessage = nil
                    } catch {
                        self?.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    func stopRecording(commit: Bool = true) {
        wantsRecording = false
        guard isRecording else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)

        if commit, !partialText.isEmpty {
            recognizedText += (recognizedText.isEmpty ? "" : "\n") + partialText
        }
        partialText = ""

        isRecording = false
        recognitionTask = nil
        recognitionRequest = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func clear() {
        recognizedText = ""
        partialText = ""
        errorMessage = nil
    }

    private func setupAudioEngine() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.recognizedText += (self.recognizedText.isEmpty ? "" : "\n") + self.partialText
                        self.partialText = ""
                    }
                }
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}

struct IOSSpeechToTextView: View {
    @Environment(\.themeTokens) private var theme
    @StateObject private var manager = IOSSpeechManager()
    @State private var copyFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Button {
                if manager.isRecording {
                    manager.stopRecording()
                } else {
                    manager.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(manager.isRecording ? theme.danger.opacity(0.15) : theme.brandPrimary.opacity(0.12))
                        .frame(width: 120, height: 120)

                    if manager.isRecording {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.danger)
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(theme.brandPrimary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: manager.isRecording)
            }

            Text(manager.isRecording ? "ios_tools_speech_listening" : "ios_tools_speech_tap_start")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)

            Spacer()

            if manager.isRecording && !manager.partialText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(manager.partialText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .iosGlassContainer(theme, cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )
            }

            if manager.isRecording || !manager.recognizedText.isEmpty || manager.errorMessage != nil {
                resultSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: manager.isRecording)
        .animation(.easeOut(duration: 0.25), value: manager.recognizedText.isEmpty)
        .padding(16)
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_tools_speech")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios_tools_speech_clear") {
                        manager.clear()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .onDisappear {
            manager.stopRecording()
        }
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ios_tools_speech_result")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if !manager.recognizedText.isEmpty {
                    Button {
                        UIPasteboard.general.string = manager.recognizedText
                        copyFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copyFeedback = false
                        }
                    } label: {
                        Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(copyFeedback ? theme.success : theme.brandPrimary)
                    }
                    .disabled(copyFeedback)
                }
            }

            if let errorMessage = manager.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.warning)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if manager.recognizedText.isEmpty {
                Text("ios_tools_speech_placeholder")
                    .foregroundStyle(theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .iosGlassContainer(theme, cornerRadius: 18)
            } else {
                ScrollView {
                    Text(manager.recognizedText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: 200, alignment: .top)
                .iosGlassContainer(theme, cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )
            }
        }
        .animation(.easeOut(duration: 0.25), value: copyFeedback)
    }
}
