import SwiftUI
import AppKit

struct ScrollViewAlwaysVisibleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AlwaysVisibleScrollViewConfigurator())
    }
}

private struct AlwaysVisibleScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                scrollView.autohidesScrollers = false
                scrollView.scrollerStyle = .legacy
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func alwaysShowScrollbars() -> some View {
        self.modifier(ScrollViewAlwaysVisibleModifier())
    }
}
