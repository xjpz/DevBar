// QuotaRowItem.swift
// DevBar

import Foundation

struct QuotaRowItem: Identifiable {
    var id: String { name }

    let name: String
    let percentage: Int
    let resetTime: String?
    let unitDescription: String?
}
