import Combine
import Foundation
import NaturalLanguage
import Translation
import WebKit

enum PageTranslationState: Equatable {
    case idle
    case translating
    case translated
    case failed(String)
}

/// Translates web page content using Apple Translation framework (offline).
/// Extracts text via JS, translates on native side, injects back.
@available(iOS 18.0, *)
final class PageTranslator: ObservableObject {

    @Published private(set) var state: PageTranslationState = .idle
    @Published var progress: String = ""

    /// Config for the translation session, observed by the bridge view.
    @Published var translationConfig: TranslationSession.Configuration?

    private var _pendingWebView: WKWebView?
    private var _pendingTexts: [String]?
    private var _pendingUniqueTexts: [String]?
    private var translationCache: [String: String] = [:]

    var isTranslated: Bool {
        if case .translated = state { return true }
        return false
    }

    var isTranslating: Bool {
        if case .translating = state { return true }
        return false
    }

    // MARK: - Public API

    func prepareForTranslation(webView: WKWebView?) {
        _pendingWebView = webView
    }

    func triggerTranslation() {
        guard let webView = _pendingWebView else {
            state = .failed("No web view available")
            return
        }
        state = .translating
        progress = ""

        Task { @MainActor in
            let lang = await detectPageLanguage(webView: webView)
            if isChineseLanguage(lang) {
                state = .idle
                return
            }

            guard let texts = await extractTexts(webView: webView), !texts.isEmpty else {
                state = .failed("No translatable text found")
                return
            }

            let uniqueTexts = Self.uniqueTexts(from: texts)
            _pendingTexts = texts
            _pendingUniqueTexts = uniqueTexts
            progress = "Translating \(uniqueTexts.count)/\(texts.count) items..."

            // Set config AFTER texts are ready — this triggers .translationTask
            let config = TranslationSession.Configuration(
                source: lang,
                target: Locale.Language(identifier: "zh-Hans")
            )
            translationConfig = config
        }
    }

    /// Called by the bridge view when a TranslationSession is available.
    func translate(with session: TranslationSession) async {
        guard let texts = _pendingTexts, !texts.isEmpty else { return }
        let uniqueTexts = _pendingUniqueTexts ?? Self.uniqueTexts(from: texts)

        let uniqueResults = await translateUniqueTexts(uniqueTexts, with: session)
        let lookup = Dictionary(
            uniqueKeysWithValues: zip(uniqueTexts, uniqueResults)
        )
        let results = texts.map { lookup[$0] ?? $0 }

        _pendingTexts = nil
        _pendingUniqueTexts = nil
        await applyResults(texts: texts, results: results)
    }

    @MainActor
    private func applyResults(texts: [String], results: [String]) async {
        guard let webView = _pendingWebView else {
            state = .failed("Web view lost")
            return
        }
        progress = "Applying..."
        do {
            let count = try await applyTranslations(webView: webView, originals: texts, translations: results)
            progress = ""
            state = count > 0 ? .translated : .failed("No text replaced")
        } catch {
            progress = ""
            state = .failed(error.localizedDescription)
        }
    }

    func restore(webView: WKWebView) async {
        state = .idle
        progress = ""
        _ = try? await webView.evaluateJavaScriptAsync(Self.restoreScript)
    }

    func resetState() {
        state = .idle
        progress = ""
        _pendingWebView = nil
        _pendingTexts = nil
    }

    // MARK: - JS Scripts

    private static let extractTextsScript = """
    (function() {
        var sel = 'h1,h2,h3,h4,h5,h6,p,span,a,li,td,th,label,button,dd,dt,blockquote,figcaption,caption,summary';
        var els = document.querySelectorAll(sel);
        var texts = [];
        var idx = 0;
        els.forEach(function(el) {
            if (el.children.length === 0 && el.textContent.trim().length > 1) {
                el.setAttribute('data-dtr-idx', String(idx));
                el.setAttribute('data-dtr-original', el.textContent.trim());
                texts.push(el.textContent.trim());
                idx++;
            }
        });
        return texts;
    })();
    """

    private static let applyTranslationsScript = """
    (function(translations) {
        var count = 0;
        var nodes = {};
        document.querySelectorAll('[data-dtr-idx]').forEach(function(el) {
            nodes[el.getAttribute('data-dtr-idx')] = el;
        });
        translations.forEach(function(pair) {
            var el = nodes[pair[0]];
            if (el && pair[1]) {
                el.textContent = pair[1];
                count++;
            }
        });
        return count;
    })(TRANSLATIONS)
    """

    private static let restoreScript = """
    (function() {
        document.querySelectorAll('[data-dtr-original]').forEach(function(el) {
            el.textContent = el.getAttribute('data-dtr-original');
            el.removeAttribute('data-dtr-original');
            el.removeAttribute('data-dtr-idx');
        });
    })();
    """

    // MARK: - Helpers

    @MainActor
    private func extractTexts(webView: WKWebView) async -> [String]? {
        try? await webView.evaluateJavaScriptAsync(Self.extractTextsScript) as? [String]
    }

    private func translateUniqueTexts(_ texts: [String], with session: TranslationSession) async -> [String] {
        var results = Array<String?>(repeating: nil, count: texts.count)
        var requests: [TranslationSession.Request] = []

        for (index, text) in texts.enumerated() {
            if let cached = translationCache[text] {
                results[index] = cached
            } else {
                requests.append(.init(sourceText: text, clientIdentifier: String(index)))
            }
        }

        if requests.isEmpty {
            return results.enumerated().map { _, value in value ?? "" }
        }

        await MainActor.run {
            progress = "0/\(texts.count)"
        }

        var completed = texts.count - requests.count
        do {
            for try await response in session.translate(batch: requests) {
                guard
                    let identifier = response.clientIdentifier,
                    let index = Int(identifier),
                    index < texts.count
                else {
                    continue
                }
                results[index] = response.targetText
                translationCache[texts[index]] = response.targetText
                completed += 1

                if completed == texts.count || completed % 10 == 0 {
                    let current = completed
                    await MainActor.run {
                        progress = "\(current)/\(texts.count)"
                    }
                }
            }
        } catch {
            await translateMissingTexts(texts, results: &results, with: session, completed: completed)
        }

        return results.enumerated().map { index, value in
            value ?? texts[index]
        }
    }

    private func translateMissingTexts(
        _ texts: [String],
        results: inout [String?],
        with session: TranslationSession,
        completed: Int
    ) async {
        var completed = completed
        for (index, text) in texts.enumerated() where results[index] == nil {
            do {
                let response = try await session.translate(text)
                results[index] = response.targetText
                translationCache[text] = response.targetText
            } catch {
                results[index] = text
            }

            completed += 1
            if completed == texts.count || completed % 10 == 0 {
                let current = completed
                await MainActor.run {
                    progress = "\(current)/\(texts.count)"
                }
            }
        }
    }

    @MainActor
    private func applyTranslations(
        webView: WKWebView,
        originals: [String],
        translations: [String]
    ) async throws -> Int {
        var pairs: [[String]] = []
        for i in 0..<originals.count {
            let t = translations[i]
            if !t.isEmpty && t != originals[i] {
                pairs.append([String(i), t])
            }
        }
        guard !pairs.isEmpty else { return 0 }

        let jsonData = try JSONSerialization.data(withJSONObject: pairs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        let script = Self.applyTranslationsScript
            .replacingOccurrences(of: "TRANSLATIONS", with: jsonString)

        let result = try await webView.evaluateJavaScriptAsync(script)
        return result as? Int ?? 0
    }

    private func detectPageLanguage(webView: WKWebView) async -> Locale.Language {
        let sample = (try? await webView.evaluateJavaScriptAsync(
            "document.body.innerText.substring(0,2000)"
        )) as? String ?? ""

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)

        guard let langCode = recognizer.dominantLanguage?.rawValue else {
            return Locale.Language(identifier: "en")
        }
        return Locale.Language(identifier: langCode)
    }

    private func isChineseLanguage(_ lang: Locale.Language) -> Bool {
        let code = lang.languageCode?.identifier ?? ""
        return code == "zh" || code == "zh-Hans" || code == "zh-Hant"
    }

    private static func uniqueTexts(from texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.filter { seen.insert($0).inserted }
    }
}

// MARK: - WKWebView Helpers

extension WKWebView {
    func evaluateJavaScriptAsync(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
