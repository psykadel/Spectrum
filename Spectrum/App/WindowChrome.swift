import AppKit
import SwiftUI

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
        let minimumSize = NSSize(width: 876, height: 540)
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
