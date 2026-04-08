import XCTest
@testable import Spectrum

@MainActor
final class OpenAISettingsStoreTests: XCTestCase {
    func testModelDefaultsToEmptyString() {
        let store = OpenAISettingsStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: InMemoryKeychainValueStore()
        )

        XCTAssertEqual(store.model, "")
        XCTAssertEqual(store.maxOutputTokensText, "25000")
    }

    func testModelPersistsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = OpenAISettingsStore(defaults: defaults, keychain: InMemoryKeychainValueStore())

        store.model = "gpt-5.4-mini"

        let reloaded = OpenAISettingsStore(defaults: defaults, keychain: InMemoryKeychainValueStore())
        XCTAssertEqual(reloaded.model, "gpt-5.4-mini")
    }

    func testAPIKeyPersistsThroughKeychainStore() throws {
        let keychain = InMemoryKeychainValueStore()
        let store = OpenAISettingsStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: keychain
        )

        store.apiKey = "sk-secret"

        XCTAssertEqual(try keychain.string(for: "openai.api-key"), "sk-secret")
    }

    func testMaxTokensPersistThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = OpenAISettingsStore(defaults: defaults, keychain: InMemoryKeychainValueStore())

        store.maxOutputTokensText = "12345"

        let reloaded = OpenAISettingsStore(defaults: defaults, keychain: InMemoryKeychainValueStore())
        XCTAssertEqual(reloaded.maxOutputTokensText, "12345")
    }
}
