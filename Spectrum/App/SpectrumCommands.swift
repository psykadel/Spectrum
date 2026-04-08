import SwiftUI

struct SpectrumCommands: Commands {
    let store: SpectrumStore

    var body: some Commands {
        CommandMenu("Spectrum") {
            Button("Clear Signals") {
                store.clearSignals()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Toggle("Show Inspector", isOn: Binding(
                get: { store.isInspectorVisible },
                set: { store.isInspectorVisible = $0 }
            ))
            .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Bands") {
            Toggle("2.4 GHz", isOn: bandBinding(.band2_4))
                .keyboardShortcut("1", modifiers: [.command, .option])
            Toggle("5 GHz", isOn: bandBinding(.band5))
                .keyboardShortcut("2", modifiers: [.command, .option])
            Toggle("6 GHz", isOn: bandBinding(.band6))
                .keyboardShortcut("3", modifiers: [.command, .option])
        }
    }

    private func bandBinding(_ band: SpectrumBand) -> Binding<Bool> {
        Binding(
            get: { store.bandVisibility.contains(band) },
            set: { store.setBandEnabled(band, enabled: $0) }
        )
    }
}
