//
//  DevBarWidgetBundle.swift
//  DevBarWidget
//

import WidgetKit
import SwiftUI

@main
struct DevBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        GLMWidget()
        OpenAIWidget()
    }
}
