import AppKit
import SwiftData
import SwiftUI

@main
struct SpectrumApp: App {
    private let modelContainer: ModelContainer
    @State private var store: SpectrumStore

    init() {
        let schema = Schema([NetworkAnnotation.self])
        let configuration = ModelConfiguration(schema: schema)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        modelContainer = container

        let scanner = CoreWLANScanner()
        let locationStore = LocationAuthorizationStore()
        let repository = AnnotationRepository(context: container.mainContext)

        _store = State(initialValue: SpectrumStore(
            scanner: scanner,
            locationStore: locationStore,
            annotationRepository: repository
        ))

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL)
        {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    var body: some Scene {
        Window("Spectrum", id: "main") {
            SpectrumRootView()
                .frame(minWidth: 876, minHeight: 540)
                .environment(store)
                .modelContainer(modelContainer)
                .preferredColorScheme(.dark)
                .background(WindowChromeConfigurator())
                .task {
                    store.start()
                }
                .onDisappear {
                    store.stop()
                }
        }
        .defaultSize(width: 1500, height: 940)
        .windowStyle(.hiddenTitleBar)
        .commands {
            SpectrumCommands(store: store)
        }
    }
}
