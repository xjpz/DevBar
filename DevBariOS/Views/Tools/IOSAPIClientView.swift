import SwiftUI
import SwiftData

struct IOSAPIClientView: View {
    @Query(sort: \IOSAPIRecord.lastOpenedAt, order: .reverse) private var savedRecords: [IOSAPIRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.themeTokens) private var theme
    @State private var selectedMethod = "GET"
    @State private var urlString = ""
    @State private var selectedTab: APIClientSection = .request
    @State private var headers: [KeyValueRow] = [
        .init(key: "Accept", value: "application/vnd.github+json"),
        .init(key: "User-Agent", value: "DevBar/1.0 (iOS)"),
    ]
    @State private var queryItems: [KeyValueRow] = []
    @State private var bodyText = ""
    @State private var responseText = ""
    @State private var responseStatus = ""
    @State private var responseDuration = ""
    @State private var isSending = false
    @State private var isShowingHistory = false

    init(record: IOSAPIRecord? = nil) {
        guard let record else { return }

        _selectedMethod = State(initialValue: record.method.uppercased())
        _urlString = State(initialValue: record.url)
        _headers = State(initialValue: Self.headerRows(from: record.headers))
        _bodyText = State(initialValue: record.body)
        _selectedTab = State(initialValue: record.body.isEmpty ? .request : .body)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { method in
                            Button(method) {
                                selectedMethod = method
                            }
                        }
                    } label: {
                        Text(selectedMethod)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                            .iosGlassContainer(theme, cornerRadius: 14)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    TextField("Request URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .iosGlassContainer(theme, cornerRadius: 14)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                }

                HStack(spacing: 20) {
                    ForEach(APIClientSection.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            VStack(spacing: 8) {
                                Text(tab.title)
                                    .font(.headline.weight(selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? theme.brandPrimary : theme.textSecondary)
                                Capsule()
                                    .fill(selectedTab == tab ? theme.brandPrimary : Color.clear)
                                    .frame(height: 3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                sectionContent

                Button {
                    Task { await sendRequest() }
                } label: {
                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("ios_tools_send_request")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(theme.brandPrimary)
                .disabled(isSending || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                HStack {
                    Text(responseStatus.isEmpty ? "Ready" : responseStatus)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.brandPrimary)
                    Spacer()
                    Text(responseDuration)
                        .foregroundStyle(theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Response")
                            .font(.headline)
                        Spacer()
                        Text("JSON")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.surfaceSecondary, in: Capsule())
                    }

                    ScrollView(.horizontal) {
                        Text(responseText.isEmpty ? "{\n  // Response will appear here\n}" : responseText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(minHeight: 260, alignment: .top)
                    .iosGlassContainer(theme, cornerRadius: 18)
                }
            }
            .padding(16)
        }
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(apiClientNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios_tools_history") {
                        isShowingHistory = true
                    }

                    Button("ios_tools_clear_response") {
                        responseText = ""
                        responseStatus = ""
                        responseDuration = ""
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .iosToolToolbarIcon(theme)
                }
            }
        }
        .navigationDestination(isPresented: $isShowingHistory) {
            IOSToolsAPIRecordsView(records: savedRecords)
        }
    }

    private var apiClientNavigationTitle: String {
        String(localized: "ios_tools_api_debug")
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedTab {
        case .request:
            toolSection(String(localized: "ios_tools_request")) {
                Text("Method: \(selectedMethod)")
                Text("URL: \(urlString)")
                    .lineLimit(2)
                Text("Headers: \(enabledRows(headers).count)")
                Text("Query: \(enabledRows(queryItems).count)")
            }
        case .headers:
            editableRowsSection(title: "Headers", rows: $headers, addLabel: String(localized: "ios_tools_add_header"))
        case .query:
            editableRowsSection(title: "Query", rows: $queryItems, addLabel: String(localized: "ios_tools_add_query"))
        case .body:
            toolSection("Body") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .iosGlassContainer(theme, cornerRadius: 16)
            }
        }
    }

    private func editableRowsSection(title: String, rows: Binding<[KeyValueRow]>, addLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            ForEach(rows) { $row in
                HStack(spacing: 10) {
                    TextField("Key", text: $row.key)
                    TextField("Value", text: $row.value)
                }
                .padding(12)
                .iosGlassContainer(theme, cornerRadius: 14)
            }

            Button {
                rows.wrappedValue.append(KeyValueRow())
            } label: {
                Label(addLabel, systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func toolSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            content()
                .foregroundStyle(theme.textPrimary)
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 18)
    }

    private func enabledRows(_ rows: [KeyValueRow]) -> [KeyValueRow] {
        rows.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func sendRequest() async {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let start = Date()

        do {
            var components = URLComponents(string: urlString)
            let query = enabledRows(queryItems)
            if !query.isEmpty {
                components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            }

            guard let url = components?.url else {
                responseStatus = "Invalid URL"
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = selectedMethod

            for header in enabledRows(headers) {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }

            if ["POST", "PUT", "PATCH", "DELETE"].contains(selectedMethod),
               !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.httpBody = bodyText.data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }

            persistRequestRecord(request: request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(start)

            if let http = response as? HTTPURLResponse {
                responseStatus = "\(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode).uppercased())"
            } else {
                responseStatus = "Completed"
            }
            responseDuration = "\(Int(duration * 1000))ms"
            responseText = prettyPrintedResponse(from: data)
        } catch {
            responseStatus = "Request Failed"
            responseDuration = ""
            responseText = error.localizedDescription
        }
    }

    private func prettyPrintedResponse(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
           let string = String(data: formatted, encoding: .utf8) {
            return string
        }

        return String(decoding: data, as: UTF8.self)
    }

    private static func headerRows(from headers: String) -> [KeyValueRow] {
        guard
            let data = headers.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        return object
            .sorted { $0.key < $1.key }
            .map { KeyValueRow(key: $0.key, value: "\($0.value)") }
    }

    private func persistRequestRecord(request: URLRequest) {
        guard let url = request.url else { return }

        let record = IOSAPIRecord(
            title: Self.recordTitle(for: url),
            url: url.absoluteString,
            method: selectedMethod,
            requestType: "API Client",
            headers: Self.serializedHeaders(from: request),
            body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            provider: Self.inferredProvider(from: url),
            tags: ["API Client", selectedMethod]
        )
        modelContext.insert(record)
    }

    private static func serializedHeaders(from request: URLRequest) -> String {
        let headers = request.allHTTPHeaderFields ?? [:]
        guard
            !headers.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: headers, options: [.prettyPrinted]),
            let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return string
    }

    private static func recordTitle(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.isEmpty ? "/" : url.path
        return "\(host)\(path)"
    }

    private static func inferredProvider(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host.contains("openai") {
            return "OpenAI"
        }
        if host.contains("bigmodel") || host.contains("zhipu") || host.contains("glm") {
            return "GLM"
        }
        return nil
    }
}

struct IOSToolsAPIRecordsView: View {
    let records: [IOSAPIRecord]

    @Environment(\.themeTokens) private var theme
    @State private var selectedRecord: IOSAPIRecord?

    var body: some View {
        List {
            IOSAPIRecordsListView(records: records) { record in
                selectedRecord = record
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.backgroundSecondary)
        .navigationTitle("API Records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .navigationDestination(item: $selectedRecord) { record in
            IOSAPIClientView(record: record)
        }
    }
}

enum APIClientSection: String, CaseIterable, Identifiable {
    case request
    case headers
    case query
    case body

    var id: String { rawValue }

    var title: String {
        switch self {
        case .request: return String(localized: "ios_tools_request")
        case .headers: return "Headers"
        case .query: return "Query"
        case .body: return "Body"
        }
    }
}

struct KeyValueRow: Identifiable {
    let id = UUID()
    var key = ""
    var value = ""
}
