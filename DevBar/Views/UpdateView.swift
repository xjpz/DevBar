// UpdateView.swift
// DevBar

import SwiftUI

struct UpdateView: View {
    @ObservedObject var viewModel: UpdateViewModel

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .idle, .checking:
                checkingView
            case .available(let release):
                availableView(release)
            case .downloading(let progress):
                downloadingView(progress: progress)
            case .downloaded:
                downloadedView
            case .installing:
                installingView
            case .upToDate:
                upToDateView
            case .error(let message):
                errorView(message)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var checkingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在检查更新...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func availableView(_ release: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                Text("发现新版本")
                    .font(.headline)
            }

            Text(release.name ?? release.tagName)
                .font(.title2)
                .fontWeight(.bold)

            if let body = release.body, !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(6)
            }

            HStack(spacing: 8) {
                Button("跳过此版本") {
                    viewModel.skipThisVersion()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if let urlStr = release.htmlUrl, let url = URL(string: urlStr) {
                    Link("查看详情", destination: url)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Button("立即更新") {
                    viewModel.downloadUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 12) {
            Text("正在下载更新...")
                .font(.headline)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button("取消") {
                viewModel.cancelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var downloadedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("下载完成")
                .font(.headline)

            Text("需要重启应用以完成安装")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("稍后") {
                    viewModel.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("立即重启") {
                    viewModel.installAndRelaunch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var installingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在安装...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var upToDateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("当前已是最新版本")
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("关闭") {
                    viewModel.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("重试") {
                    viewModel.checkForUpdates(silent: false)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
