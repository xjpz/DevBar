// GitHubRelease.swift
// DevBar

import Foundation

struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String?
    let assets: [GitHubAsset]
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
        case publishedAt = "published_at"
    }
}

struct GitHubAsset: Codable, Sendable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}
