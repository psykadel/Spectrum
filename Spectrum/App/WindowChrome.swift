import AppKit
import SwiftUI

enum SpectrumWindowMetrics {
    static let minimumContentSize = NSSize(width: 1180, height: 540)
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            configureWindow(from: nsView)
        }
    }

    private func configureWindow(from view: NSView) {
        guard let window = view.window else { return }
        let minimumSize = SpectrumWindowMetrics.minimumContentSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.styleMask.insert(.fullSizeContentView)
        window.contentMinSize = minimumSize
        window.minSize = minimumSize
        window.identifier = NSUserInterfaceItemIdentifier("Spectrum.MainWindow")
        window.toolbarStyle = .unifiedCompact

        if window.frame.size.width < minimumSize.width || window.frame.size.height < minimumSize.height {
            let nextSize = NSSize(
                width: max(window.frame.size.width, minimumSize.width),
                height: max(window.frame.size.height, minimumSize.height)
            )
            window.setContentSize(nextSize)
        }
    }
}
