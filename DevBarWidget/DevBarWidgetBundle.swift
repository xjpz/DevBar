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
        DevBarLockScreenQuotaWidget()
        #if os(iOS)
        if #available(iOSApplicationExtension 17.0, *) {
            DevBarQuotaLiveActivityWidget()
        }
        #endif
    }
}
