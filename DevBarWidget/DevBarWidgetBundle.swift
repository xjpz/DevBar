//
//  DevBarWidgetBundle.swift
//  DevBarWidget
//

import WidgetKit
import SwiftUI

@main
struct DevBarWidgetBundle: WidgetBundle {
    init() {
        // 设置透明背景（仅 iOS）
        #if os(iOS)
        WidgetTransparentBackground.setup()
        #endif
    }

    var body: some Widget {
        DevBarWidget()
        MacThemeWidget()
        AgentWatcherWidget()
        DevBarLockScreenQuotaWidget()
        #if os(iOS)
        AgentWatcherLiveActivityWidget()
        if #available(iOSApplicationExtension 17.0, *) {
            DevBarQuotaLiveActivityWidget()
        }
        #endif
    }
}
