import SwiftUI

enum IOSHomeAssistantWallpaper: String, CaseIterable, Identifiable {
    case blueMist
    case warmSunset
    case midnightBlue
    case tealAurora

    static let storageKey = "ios.homeAssistant.wallpaper"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blueMist: "几何蓝灰"
        case .warmSunset: "晨曦渐变"
        case .midnightBlue: "蓝紫渐变"
        case .tealAurora: "暮色渐变"
        }
    }

    var assetName: String {
        switch self {
        case .blueMist: "HomeAssistantBackground"
        case .warmSunset: "HomeAssistantWarmSunset"
        case .midnightBlue: "HomeAssistantMidnightBlue"
        case .tealAurora: "HomeAssistantTealAurora"
        }
    }

    func overlayOpacity(for colorScheme: ColorScheme) -> Double {
        switch (self, colorScheme) {
        case (.blueMist, .light): 0.08
        case (.blueMist, .dark): 0.22
        case (.warmSunset, .light): 0.12
        case (.warmSunset, .dark): 0.28
        case (.midnightBlue, .light): 0.02
        case (.midnightBlue, .dark): 0.08
        case (.tealAurora, .light): 0.08
        case (.tealAurora, .dark): 0.18
        @unknown default: 0.12
        }
    }
}

struct IOSHomeAssistantWallpaperPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @AppStorage(IOSHomeAssistantWallpaper.storageKey) private var selectedRawValue =
        IOSHomeAssistantWallpaper.blueMist.rawValue

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    private var selectedWallpaper: IOSHomeAssistantWallpaper {
        IOSHomeAssistantWallpaper(rawValue: selectedRawValue) ?? .blueMist
    }

    var body: some View {
        ZStack {
            IOSHomeAssistantPageBackground(theme: theme, wallpaper: selectedWallpaper)
                .ignoresSafeArea()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(IOSHomeAssistantWallpaper.allCases) { wallpaper in
                        wallpaperButton(wallpaper)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("家庭墙纸")
        .navigationBarTitleDisplayMode(.inline)
        .homeAssistantTransparentNavigationBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
    }

    private func wallpaperButton(_ wallpaper: IOSHomeAssistantWallpaper) -> some View {
        let isSelected = selectedWallpaper == wallpaper

        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedRawValue = wallpaper.rawValue
            }
        } label: {
            Image(wallpaper.assetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 238)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.66)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(wallpaper.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2.weight(.semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.28), lineWidth: isSelected ? 3 : 1)
                }
                .shadow(color: .black.opacity(isSelected ? 0.24 : 0.12), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(wallpaper.title)
        .accessibilityValue(isSelected ? "已选择" : "")
        .accessibilityHint("双击设为家庭墙纸")
    }
}
