//
//  DevBarWidgetBundle.swift
//  DevBarWidget
//

import WidgetKit
import SwiftUI

@main
struct DevBarWidgetBundle: WidgetBundle {
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
