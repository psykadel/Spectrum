import SwiftUI

struct SpectrumSettingsView: View {
    @Environment(SpectrumStore.self) private var store
    @Environment(OpenAISettingsStore.self) private var settingsStore
    @State private var zigbeeDraft = ""
    @State private var zigbeeFeedback: String?
    @State private var zigbeeFeedbackColor: Color = .secondary

    var body: some View {
        @Bindable var settingsStore = settingsStore

        Form {
            Section("2.4 GHz Overlays") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manual Zigbee Channels")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                    TextField("11, 15, 20", text: $zigbeeDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addManualZigbeeChannels()
                        }

                    HStack(spacing: 10) {
                        Button("Add Channels") {
                            addManualZigbeeChannels()
                        }
                        .disabled(zigbeeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !store.manualZigbeeChannels.isEmpty {
                            Button("Clear All") {
                                store.clearManualZigbeeChannels()
                                zigbeeFeedback = nil
                            }
                        }
                    }

                    Text("Add channels 11 through 26 with commas or spaces. Spectrum will draw them as Zigbee overlap markers on the 2.4 GHz lane.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    if let zigbeeFeedback {
                        Text(zigbeeFeedback)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(zigbeeFeedbackColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)

                if store.manualZigbeeChannels.isEmpty {
                    Text("No manual Zigbee channels added yet.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.manualZigbeeChannels) { manualChannel in
                            HStack(spacing: 12) {
                                ZigbeeSettingsBadge(channel: manualChannel.channel)
                                Text(manualChannel.displayName)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Spacer()
                                Button("Remove") {
                                    store.removeManualZigbeeChannel(manualChannel.channel)
                                    zigbeeFeedback = nil
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("OpenAI") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    SecureField("sk-...", text: $settingsStore.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    TextField("e.g. \(OpenAISettingsStore.exampleMiniModel)", text: $settingsStore.model)
                        .textFieldStyle(.roundedBorder)

                    Text("Use a reasoning model here. e.g. \(OpenAISettingsStore.exampleMiniModel)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Max Tokens")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    TextField("e.g. \(OpenAISettingsStore.defaultMaxOutputTokens)", text: $settingsStore.maxOutputTokensText)
                        .textFieldStyle(.roundedBorder)
                    Text("Upper limit for the Responses API output budget.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                if let errorMessage = settingsStore.persistenceErrorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("Settings")
    }

    private func addManualZigbeeChannels() {
        let result = SpectrumMath.parseZigbeeChannels(from: zigbeeDraft)
        let trimmedDraft = zigbeeDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDraft.isEmpty else {
            zigbeeFeedback = "Enter one or more Zigbee channels first."
            zigbeeFeedbackColor = .orange.opacity(0.92)
            return
        }

        if !result.channels.isEmpty {
            store.addManualZigbeeChannels(result.channels)
            zigbeeDraft = ""
        }

        if !result.invalidTokens.isEmpty {
            zigbeeFeedback = "Ignored invalid entries: \(result.invalidTokens.joined(separator: ", ")). Use channels 11 through 26."
            zigbeeFeedbackColor = .orange.opacity(0.92)
            return
        }

        if result.channels.isEmpty {
            zigbeeFeedback = "Use Zigbee channels 11 through 26."
            zigbeeFeedbackColor = .orange.opacity(0.92)
            return
        }

        let noun = result.channels.count == 1 ? "channel" : "channels"
        zigbeeFeedback = "Added \(result.channels.count) Zigbee \(noun)."
        zigbeeFeedbackColor = .green.opacity(0.92)
    }
}

private struct ZigbeeSettingsBadge: View {
    let channel: Int

    var body: some View {
        Text("Z\(channel)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.84, green: 1.0, blue: 0.98))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.05, green: 0.14, blue: 0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color(red: 0.4, green: 0.94, blue: 0.9), style: StrokeStyle(lineWidth: 1.1, dash: [3, 2]))
            )
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "SpectrumSettingsPreview")!
    let store = SpectrumStore(
        scanner: MockWiFiScanner(),
        locationStore: MockLocationAuthorizationStore(initialState: .authorized),
        annotationRepository: InMemoryAnnotationRepository(),
        defaults: defaults,
        now: Date.init
    )
    store.addManualZigbeeChannels([15, 20, 25])

    return SpectrumSettingsView()
        .environment(store)
        .environment(OpenAISettingsStore(
            defaults: defaults,
            keychain: InMemoryKeychainValueStore()
        ))
        .frame(width: 560, height: 420)
}
