import Foundation
import Observation
import Security

protocol KeychainValueStoring {
    func string(for account: String) throws -> String?
    func setString(_ value: String?, for account: String) throws
}

enum KeychainValueStoreError: LocalizedError {
    case invalidData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The saved API key could not be read."
        case let .unexpectedStatus(status):
            return "Keychain request failed (\(status))."
        }
    }
}

struct KeychainValueStore: KeychainValueStoring {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "io.spectrum.app") {
        self.service = service
    }

    func string(for account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8)
            else {
                throw KeychainValueStoreError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainValueStoreError.unexpectedStatus(status)
        }
    }

    func setString(_ value: String?, for account: String) throws {
        let query = baseQuery(for: account)

        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainValueStoreError.unexpectedStatus(status)
            }
            return
        }

        let data = Data(value.utf8)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainValueStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainValueStoreError.unexpectedStatus(status)
        }

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainValueStoreError.unexpectedStatus(updateStatus)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

final class InMemoryKeychainValueStore: KeychainValueStoring {
    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func string(for account: String) throws -> String? {
        values[account]
    }

    func setString(_ value: String?, for account: String) throws {
        values[account] = value
    }
}

struct OpenAIConfiguration: Equatable {
    let apiKey: String
    let model: String
    let maxOutputTokens: Int
}

@MainActor
@Observable
final class OpenAISettingsStore {
    private enum DefaultsKey {
        static let model = "Spectrum.openAI.model"
        static let maxOutputTokens = "Spectrum.openAI.maxOutputTokens"
    }

    static let exampleMiniModel = "gpt-5.4-mini"
    static let defaultMaxOutputTokens = 25_000

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: any KeychainValueStoring
    @ObservationIgnored private let apiKeyAccount: String

    var apiKey: String {
        didSet {
            persistAPIKey()
        }
    }

    var model: String {
        didSet {
            persistModel()
        }
    }

    var maxOutputTokensText: String {
        didSet {
            persistMaxOutputTokens()
        }
    }

    private(set) var persistenceErrorMessage: String?

    init(
        defaults: UserDefaults = .standard,
        keychain: any KeychainValueStoring = KeychainValueStore(),
        apiKeyAccount: String = "openai.api-key"
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.apiKeyAccount = apiKeyAccount

        let storedModel = defaults.string(forKey: DefaultsKey.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedMaxTokens = defaults.string(forKey: DefaultsKey.maxOutputTokens)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        model = storedModel ?? ""
        maxOutputTokensText = storedMaxTokens?.isEmpty == false
            ? storedMaxTokens!
            : String(Self.defaultMaxOutputTokens)
        apiKey = (try? keychain.string(for: apiKeyAccount)) ?? ""
    }

    var configuration: OpenAIConfiguration? {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMaxTokens = maxOutputTokensText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty,
              !trimmedModel.isEmpty,
              let maxOutputTokens = Int(trimmedMaxTokens),
              maxOutputTokens > 0
        else {
            return nil
        }

        return OpenAIConfiguration(
            apiKey: trimmedAPIKey,
            model: trimmedModel,
            maxOutputTokens: maxOutputTokens
        )
    }

    var isConfigured: Bool {
        configuration != nil
    }

    private func persistModel() {
        defaults.set(
            model.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.model
        )
    }

    private func persistMaxOutputTokens() {
        defaults.set(
            maxOutputTokensText.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.maxOutputTokens
        )
    }

    private func persistAPIKey() {
        do {
            let trimmedValue = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try keychain.setString(trimmedValue.isEmpty ? nil : trimmedValue, for: apiKeyAccount)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }
}
