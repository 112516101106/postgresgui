//
//  AutocompleteSuggestionListView.swift
//  PostgresGUI
//
//  SwiftUI presentation for SQL autocomplete suggestions.
//

import SwiftUI
import Combine

@MainActor
final class AutocompleteSuggestionListState: ObservableObject {
    @Published private(set) var suggestions: [SuggestionItem] = []
    @Published private(set) var selectedIndex = 0

    var selectedSuggestion: SuggestionItem? {
        guard suggestions.indices.contains(selectedIndex) else {
            return nil
        }

        return suggestions[selectedIndex]
    }

    func apply(_ newSuggestions: [SuggestionItem]) {
        let previouslySelectedID = selectedSuggestion?.id
        suggestions = newSuggestions

        guard !newSuggestions.isEmpty else {
            selectedIndex = 0
            return
        }

        if let previouslySelectedID,
           let matchingIndex = newSuggestions.firstIndex(where: { $0.id == previouslySelectedID }) {
            selectedIndex = matchingIndex
            return
        }

        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        guard !suggestions.isEmpty else {
            selectedIndex = 0
            return
        }

        let candidateIndex = selectedIndex + delta
        selectedIndex = min(max(candidateIndex, 0), suggestions.count - 1)
    }

    func selectSuggestion(withID suggestionID: SuggestionItem.ID) {
        guard let matchingIndex = suggestions.firstIndex(where: { $0.id == suggestionID }) else {
            return
        }

        selectedIndex = matchingIndex
    }
}

private enum AutocompleteSuggestionLayout {
    static let rowHeight: CGFloat = 30
    static let subtitleSize: CGFloat = 11
}

struct AutocompleteSuggestionListView: View {
    @ObservedObject var state: AutocompleteSuggestionListState
    let onSelect: (SuggestionItem) -> Void

    var body: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(state.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestionRow(
                            suggestion,
                            isSelected: index == state.selectedIndex
                        )
                        .id(suggestion.id)
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: state.selectedSuggestion?.id) { _, selectedID in
                guard let selectedID else {
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    scrollViewProxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: SuggestionItem, isSelected: Bool) -> some View {
        Button {
            state.selectSuggestion(withID: suggestion.id)
            onSelect(suggestion)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: suggestion.iconType.systemImageName)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.title)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: AutocompleteSuggestionLayout.subtitleSize))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: AutocompleteSuggestionLayout.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
