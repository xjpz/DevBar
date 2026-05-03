//
//  AppIntent.swift
//  DevBarWidget
//

import AppIntents

enum WidgetProviderSelection: String, AppEnum {
    case glm
    case openai
    case mimo

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Provider")
    }

    static var caseDisplayRepresentations: [WidgetProviderSelection: DisplayRepresentation] {
        [
            .glm: DisplayRepresentation(title: "GLM"),
            .openai: DisplayRepresentation(title: "OpenAI"),
            .mimo: DisplayRepresentation(title: "MiMo")
        ]
    }

    var displayName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        case .mimo: return "MiMo"
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "DevBar Quota" }
    static var description: IntentDescription { "Choose the Provider shown by this widget." }

    @Parameter(title: "Provider", default: .glm)
    var provider: WidgetProviderSelection
}
