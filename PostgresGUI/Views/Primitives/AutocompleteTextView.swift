//
//  AutocompleteTextView.swift
//  PostgresGUI
//
//  NSTextView subclass that keeps keyboard routing local to the SQL editor.
//

import AppKit

enum AutocompleteSelectionDirection {
    case up
    case down
}

@MainActor
protocol AutocompleteTextViewDelegate: AnyObject {
    var isAutocompleteVisible: Bool { get }

    func autocompleteTextView(
        _ textView: AutocompleteTextView,
        moveSelection direction: AutocompleteSelectionDirection
    ) -> Bool

    func autocompleteTextViewInsertSelectedSuggestion(_ textView: AutocompleteTextView) -> Bool
    func autocompleteTextViewDismissSuggestions(_ textView: AutocompleteTextView) -> Bool
}

final class AutocompleteTextView: NSTextView {
    weak var autocompleteDelegate: (any AutocompleteTextViewDelegate)?

    override func keyDown(with event: NSEvent) {
        guard shouldRouteAutocompleteCommand(for: event) else {
            super.keyDown(with: event)
            return
        }

        switch Int(event.keyCode) {
        case 125:
            if autocompleteDelegate?.autocompleteTextView(self, moveSelection: .down) == true {
                return
            }
        case 126:
            if autocompleteDelegate?.autocompleteTextView(self, moveSelection: .up) == true {
                return
            }
        case 36, 48, 76:
            if autocompleteDelegate?.autocompleteTextViewInsertSelectedSuggestion(self) == true {
                return
            }
        case 53:
            if autocompleteDelegate?.autocompleteTextViewDismissSuggestions(self) == true {
                return
            }
        default:
            break
        }

        super.keyDown(with: event)
    }

    func calculateCaretRect() -> NSRect? {
        guard let layoutManager, let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)

        let selectedRange = selectedRange()
        guard selectedRange.length == 0 else {
            return nil
        }

        let textLength = (string as NSString).length
        let clampedLocation = min(max(selectedRange.location, 0), textLength)
        let paddingX = textContainerInset.width + textContainer.lineFragmentPadding
        let paddingY = textContainerInset.height
        let lineHeight = max(font?.boundingRectForFont.height ?? 0, 16)

        guard layoutManager.numberOfGlyphs > 0 else {
            return NSRect(x: paddingX, y: paddingY, width: 1, height: lineHeight)
        }

        if clampedLocation >= textLength {
            let previousGlyphIndex = max(layoutManager.numberOfGlyphs - 1, 0)
            let glyphRange = NSRange(location: previousGlyphIndex, length: 1)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: previousGlyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )

            return NSRect(
                x: glyphRect.maxX + textContainerInset.width,
                y: lineRect.minY + paddingY,
                width: 1,
                height: max(lineRect.height, lineHeight)
            )
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedLocation)
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )

        return NSRect(
            x: glyphRect.minX + textContainerInset.width,
            y: lineRect.minY + paddingY,
            width: 1,
            height: max(lineRect.height, lineHeight)
        )
    }

    private func shouldRouteAutocompleteCommand(for event: NSEvent) -> Bool {
        guard autocompleteDelegate?.isAutocompleteVisible == true else {
            return false
        }

        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return event.modifierFlags.intersection(blockedModifiers).isEmpty
    }
}
