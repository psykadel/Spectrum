import AppKit
import SwiftData
import SwiftUI

@main
struct SpectrumApp: App {
    private let modelContainer: ModelContainer
    @State private var store: SpectrumStore
    @State private var openAISettingsStore: OpenAISettingsStore

    init() {
        let schema = Schema([NetworkAnnotation.self])
        let configuration = ModelConfiguration(schema: schema)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        modelContainer = container

        let scanner = CoreWLANScanner()
        let locationStore = LocationAuthorizationStore()
        let repository = AnnotationRepository(context: container.mainContext)
        let openAISettingsStore = OpenAISettingsStore()
        let deviceLabelingService = OpenAIResponsesDeviceLabelingService()

        _store = State(initialValue: SpectrumStore(
            scanner: scanner,
            locationStore: locationStore,
            annotationRepository: repository,
            openAISettingsStore: openAISettingsStore,
            deviceLabelingService: deviceLabelingService
        ))
        _openAISettingsStore = State(initialValue: openAISettingsStore)

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
                .environment(openAISettingsStore)
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

        Settings {
            OpenAISettingsView()
                .environment(openAISettingsStore)
                .frame(minWidth: 520, minHeight: 260)
                .preferredColorScheme(.dark)
        }
    }
}
