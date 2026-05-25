import SwiftUI
import SwiftData
import UIKit

struct IOSToolsView: View {
    @Environment(\.themeTokens) private var theme

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink {
                    IOSAPIClientView()
                } label: {
                    IOSToolCard(
                        title: "API 调试",
                        subtitle: "API Client",
                        systemImage: "globe",
                        iconColor: .cyan,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSFormatterView()
                } label: {
                    IOSToolCard(
                        title: "格式化",
                        subtitle: "Formatter",
                        systemImage: "curlybraces",
                        iconColor: .yellow,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSBase64View()
                } label: {
                    IOSToolCard(
                        title: "Base64",
                        subtitle: "编码 / 解码",
                        systemImage: "lock.square",
                        iconColor: .indigo,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSTimestampView()
                } label: {
                    IOSToolCard(
                        title: "时间戳",
                        subtitle: "Timestamp",
                        systemImage: "clock",
                        iconColor: .mint,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSMarkdownView()
                } label: {
                    IOSToolCard(
                        title: "Markdown",
                        subtitle: "编辑 / 预览",
                        systemImage: "doc.richtext",
                        iconColor: .orange,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSQRCodeView()
                } label: {
                    IOSToolCard(
                        title: "二维码",
                        subtitle: "QR Code",
                        systemImage: "qrcode",
                        iconColor: .blue,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSMacRelayView()
                } label: {
                    IOSToolCard(
                        title: "Mac 中继",
                        subtitle: "Relay",
                        systemImage: "macbook.and.iphone",
                        iconColor: .green,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                if #available(iOS 18.0, *) {
                    NavigationLink {
                        IOSTranslationView()
                    } label: {
                        IOSToolCard(
                            title: "翻译",
                            subtitle: "Translate",
                            systemImage: "character.book.closed",
                            iconColor: .teal,
                            theme: theme
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    IOSOCRView()
                } label: {
                    IOSToolCard(
                        title: "文字识别",
                        subtitle: "OCR",
                        systemImage: "doc.text.viewfinder",
                        iconColor: .purple,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSSpeechToTextView()
                } label: {
                    IOSToolCard(
                        title: "语音转文字",
                        subtitle: "Speech to Text",
                        systemImage: "mic.fill",
                        iconColor: .pink,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    IOSMemoListView()
                } label: {
                    IOSToolCard(
                        title: "备忘录",
                        subtitle: "Memo",
                        systemImage: "note.text",
                        iconColor: .brown,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .iosGeekScreenBackground(theme)
        .navigationTitle("ios_tab_tools")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
        .accessibilityIdentifier("ios.tools.screen")
    }
}

struct IOSToolCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    let theme: IOSThemeTokens

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconColor.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .iosGlassContainer(theme, cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }
}

extension View {
    func iosToolNavigationChrome(_ theme: IOSThemeTokens) -> some View {
        self
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct IOSAPIRecordsListView: View {
    let records: [IOSAPIRecord]
    let openRecord: (IOSAPIRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme

    var body: some View {
        Group {
            if records.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No API Records yet",
                        systemImage: "tray",
                        description: Text("Saved Fetch/XHR requests will appear here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 48, leading: 20, bottom: 48, trailing: 20))
                }
            } else {
                ForEach(records) { record in
                    Button {
                        openRecord(record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .foregroundStyle(theme.textPrimary)
                            Text(record.url)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(record.method)
                                Text(record.requestType)
                                if let provider = record.provider {
                                    Text(provider)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.brandPrimary)
                        }
                    }
                    .swipeActions {
                        Button {
                            record.isFavorite.toggle()
                            record.lastOpenedAt = .now
                        } label: {
                            Label(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)

                        Button(role: .destructive) {
                            modelContext.delete(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
