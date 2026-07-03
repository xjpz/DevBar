//
//  DevBarWidgetBundle.swift
//  DevBarWidget
//

import WidgetKit
import SwiftUI

@main
struct DevBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        TransparentDesktopWidget()
        LiquidGlassDesktopWidget()
        DarkDesktopWidget()
        #if os(iOS)
        DevBarLockScreenHelloWidget()
        DevBarLockScreenQuotaWidget()
        AgentWatcherLiveActivityWidget()
        DevBarLiveMessageLiveActivityWidget()
        TerminalLiveActivityWidget()
        if #available(iOSApplicationExtension 17.0, *) {
            DevBarQuotaLiveActivityWidget()
        }
        #endif
    }
}
