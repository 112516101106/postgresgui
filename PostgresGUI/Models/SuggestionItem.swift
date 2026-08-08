//
//  SuggestionItem.swift
//  PostgresGUI
//
//  UI-facing autocomplete suggestion models.
//

import Foundation

enum SuggestionIconType: String, Sendable, Hashable, Codable {
    case schema
    case table
    case view
    case materializedView
    case foreignTable
    case column
    case keyword

    nonisolated init(relationKind: RelationKind) {
        switch relationKind {
        case .table:
            self = .table
        case .view:
            self = .view
        case .materializedView:
            self = .materializedView
        case .foreignTable:
            self = .foreignTable
        }
    }

    nonisolated var systemImageName: String {
        switch self {
        case .schema:
            return "square.stack.3d.up"
        case .table:
            return "tablecells"
        case .view:
            return "eye"
        case .materializedView:
            return "square.text.square"
        case .foreignTable:
            return "globe"
        case .column:
            return "rectangle.split.3x1"
        case .keyword:
            return "command"
        }
    }
}

struct SuggestionItem: Identifiable, Sendable, Hashable, Codable {
    let title: String
    let subtitle: String?
    let replacementText: String
    let iconType: SuggestionIconType

    nonisolated init(
        title: String,
        subtitle: String? = nil,
        replacementText: String? = nil,
        iconType: SuggestionIconType
    ) {
        self.title = title
        self.subtitle = subtitle
        self.replacementText = replacementText ?? title
        self.iconType = iconType
    }

    nonisolated var id: String {
        let subtitleKey = subtitle?.lowercased() ?? ""
        return "\(iconType.rawValue)|\(replacementText.lowercased())|\(subtitleKey)"
    }
}
