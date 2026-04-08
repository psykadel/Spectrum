import SwiftUI

struct OpenAISettingsView: View {
    @Environment(OpenAISettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settingsStore = settingsStore

        Form {
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
}

#Preview {
    OpenAISettingsView()
        .environment(OpenAISettingsStore(keychain: InMemoryKeychainValueStore()))
        .frame(width: 520, height: 260)
}
