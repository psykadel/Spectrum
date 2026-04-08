import XCTest
@testable import Spectrum

@MainActor
final class SpectrumStoreTests: XCTestCase {
    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testMergingScanRetainsMissingNetworkAsGhost() async {
        let scanner = MockWiFiScanner()
        let location = MockLocationAuthorizationStore(initialState: .authorized)
        let repository = InMemoryAnnotationRepository()
        let anchorDate = Date(timeIntervalSinceReferenceDate: 1000)
        var ticks = 0
        let store = SpectrumStore(
            scanner: scanner,
            locationStore: location,
            annotationRepository: repository,
            defaults: UserDefaults(suiteName: #function)!,
            now: {
                defer { ticks += 1 }
                return anchorDate.addingTimeInterval(TimeInterval(ticks * 10))
            }
        )

        let first = WiFiScanSnapshot(
            interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
            observations: [
                WiFiScanObservation(
                    bssid: "AA:BB:CC:DD:EE:FF",
                    ssid: "Studio",
                    channel: 36,
                    band: .band5,
                    channelWidthMHz: 80,
                    rssi: -48,
                    noise: -93
                )
            ],
            scannedAt: anchorDate
        )

        store.applyScanSnapshot(first)
        let second = WiFiScanSnapshot(
            interface: first.interface,
            observations: [],
            scannedAt: anchorDate.addingTimeInterval(10)
        )
        store.applyScanSnapshot(second)

        let envelope = store.renderedSignal(for: "AA:BB:CC:DD:EE:FF", at: anchorDate.addingTimeInterval(15))
        XCTAssertNotNil(envelope)
        XCTAssertEqual(envelope?.isGhost, true)
    }

    func testAnnotationsDriveFriendlyNamesAndOwnedStyling() async throws {
        let scanner = MockWiFiScanner()
        let location = MockLocationAuthorizationStore(initialState: .authorized)
        let repository = InMemoryAnnotationRepository(records: [
            NetworkAnnotationRecord(
                bssid: "11:22:33:44:55:66",
                friendlyName: "Backhaul",
                isOwned: true,
                accentSeed: 0.34
            )
        ])
        let store = SpectrumStore(
            scanner: scanner,
            locationStore: location,
            annotationRepository: repository,
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.start()
        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    WiFiScanObservation(
                        bssid: "11:22:33:44:55:66",
                        ssid: "Mesh",
                        channel: 1,
                        band: .band2_4,
                        channelWidthMHz: 20,
                        rssi: -55,
                        noise: -95
                    )
                ],
                scannedAt: Date()
            )
        )

        let envelope = try XCTUnwrap(store.renderedSignal(for: "11:22:33:44:55:66", at: Date()))
        XCTAssertEqual(envelope.displayName, "Backhaul")
        XCTAssertTrue(envelope.isOwned)
        XCTAssertGreaterThan(envelope.strokeWidth, 3)
    }

    func testPermissionOverlayWinsBeforeWifiState() {
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .notDetermined),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        XCTAssertEqual(store.overlayState, .permissionRequired)
    }

    func testInspectorSignalsFilterToActiveBandsAndSortByStrength() {
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.setBandEnabled(.band2_4, enabled: true)
        store.setBandEnabled(.band5, enabled: false)
        store.setBandEnabled(.band6, enabled: false)

        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:AA:AA:AA:AA:01", ssid: "Band24-weak", channel: 6, band: .band2_4, channelWidthMHz: 20, rssi: -72, noise: -95),
                    .init(bssid: "AA:AA:AA:AA:AA:02", ssid: "Band24-strong", channel: 6, band: .band2_4, channelWidthMHz: 20, rssi: -48, noise: -95),
                    .init(bssid: "BB:BB:BB:BB:BB:01", ssid: "Band5-hidden", channel: 36, band: .band5, channelWidthMHz: 80, rssi: -35, noise: -93)
                ],
                scannedAt: Date()
            )
        )

        XCTAssertEqual(store.inspectorSignals.map(\.bssid), ["AA:AA:AA:AA:AA:02", "AA:AA:AA:AA:AA:01"])
        XCTAssertEqual(store.inspectorGroups.map(\.title), ["Channel 6 · 2.4 GHz"])
    }

    func testSelectingSignalCopiesBSSIDToPasteboard() {
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.selectSignal("AA:BB:CC:DD:EE:FF")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "AA:BB:CC:DD:EE:FF")
    }

    func testBandAmplitudeUsesStrongestVisibleSignalAsPeak() throws {
        let now = Date()
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: { now }
        )

        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:AA:AA:AA:AA:01", ssid: "Peak", channel: 1, band: .band2_4, channelWidthMHz: 20, rssi: -48, noise: -95),
                    .init(bssid: "AA:AA:AA:AA:AA:02", ssid: "Lower", channel: 6, band: .band2_4, channelWidthMHz: 20, rssi: -60, noise: -95)
                ],
                scannedAt: now
            )
        )

        let envelopes = store.renderedSignals(for: .band2_4, at: now)
        let peak = try XCTUnwrap(envelopes.first(where: { $0.bssid == "AA:AA:AA:AA:AA:01" }))
        let lower = try XCTUnwrap(envelopes.first(where: { $0.bssid == "AA:AA:AA:AA:AA:02" }))

        XCTAssertGreaterThan(peak.amplitude, lower.amplitude)
        XCTAssertEqual(peak.amplitude, 0.92, accuracy: 0.03)
    }

    func testNotDeterminedLocationActionRequestsAuthorization() {
        let scanner = MockWiFiScanner()
        let location = MockLocationAuthorizationStore(initialState: .notDetermined)
        let store = SpectrumStore(
            scanner: scanner,
            locationStore: location,
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.start()
        store.performLocationAccessAction()

        XCTAssertEqual(location.requestAuthorizationCallCount, 1)
        XCTAssertEqual(store.locationAccessState, .authorized)
    }

    func testServicesDisabledLocationActionOpensSettings() {
        let scanner = MockWiFiScanner()
        let location = MockLocationAuthorizationStore(initialState: .servicesDisabled)
        var openedURLs: [URL] = []
        let store = SpectrumStore(
            scanner: scanner,
            locationStore: location,
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init,
            openURL: {
                openedURLs.append($0)
                return true
            }
        )

        store.performLocationAccessAction()

        XCTAssertEqual(location.requestAuthorizationCallCount, 0)
        XCTAssertEqual(
            openedURLs.first?.absoluteString,
            "settings-navigation://com.apple.settings.PrivacySecurity.extension/Privacy_LocationServices"
        )
    }

    func testClearSignalsResetsStoreAndScannerSession() async {
        let scanner = MockWiFiScanner()
        let store = SpectrumStore(
            scanner: scanner,
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.start()
        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:AA:AA:AA:AA:01", ssid: "Peak", channel: 1, band: .band2_4, channelWidthMHz: 20, rssi: -48, noise: -95)
                ],
                scannedAt: Date()
            )
        )

        store.clearSignals()

        XCTAssertTrue(store.inspectorSignals.isEmpty)
        XCTAssertNil(store.selectedBSSID)
        XCTAssertEqual(store.scanGeneration, 1)
        await scanner.requestImmediateScan()
        XCTAssertTrue(store.inspectorSignals.isEmpty)
    }

    func testLocationSettingsFallsBackWhenFirstURLFails() {
        let scanner = MockWiFiScanner()
        let location = MockLocationAuthorizationStore(initialState: .servicesDisabled)
        var openedURLs: [URL] = []
        let store = SpectrumStore(
            scanner: scanner,
            locationStore: location,
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init,
            openURL: { url in
                openedURLs.append(url)
                return openedURLs.count > 1
            }
        )

        store.performLocationAccessAction()

        XCTAssertEqual(
            openedURLs.map(\.absoluteString),
            [
                "settings-navigation://com.apple.settings.PrivacySecurity.extension/Privacy_LocationServices",
                "settings-navigation://com.apple.settings.PrivacySecurity.extension/LOCATION_SERVICES"
            ]
        )
    }

    func testGenerateAILabelSavesPlainAILabelWhenNoExistingName() async throws {
        let repository = InMemoryAnnotationRepository()
        let settingsStore = makeSettingsStore()
        let labelingService = MockDeviceLabelingService(result: .success("Apple iPhone"))
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: repository,
            openAISettingsStore: settingsStore,
            deviceLabelingService: labelingService,
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:FF", ssid: nil, channel: 149, band: .band5, channelWidthMHz: 80, rssi: -51, noise: -93)
                ],
                scannedAt: Date()
            )
        )

        await store.generateAILabel(for: "AA:BB:CC:DD:EE:FF")

        XCTAssertEqual(store.annotationList.first?.friendlyName, "Apple iPhone")
    }

    func testGenerateAILabelPreservesSSIDInParentheses() async throws {
        let repository = InMemoryAnnotationRepository()
        let settingsStore = makeSettingsStore()
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: repository,
            openAISettingsStore: settingsStore,
            deviceLabelingService: MockDeviceLabelingService(result: .success("Apple iPhone")),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:01", ssid: "Johnny_2G", channel: 6, band: .band2_4, channelWidthMHz: 20, rssi: -60, noise: -95)
                ],
                scannedAt: Date()
            )
        )

        await store.generateAILabel(for: "AA:BB:CC:DD:EE:01")

        XCTAssertEqual(store.annotationList.first?.friendlyName, "Apple iPhone (Johnny_2G)")
    }

    func testGenerateAILabelPreservesSavedFriendlyNameInParentheses() async throws {
        let repository = InMemoryAnnotationRepository(records: [
            NetworkAnnotationRecord(
                bssid: "AA:BB:CC:DD:EE:02",
                friendlyName: "Office Printer",
                isOwned: false,
                accentSeed: 0.2
            )
        ])
        let settingsStore = makeSettingsStore()
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: repository,
            openAISettingsStore: settingsStore,
            deviceLabelingService: MockDeviceLabelingService(result: .success("HP Printer")),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.start()
        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:02", ssid: "PrinterWiFi", channel: 44, band: .band5, channelWidthMHz: 40, rssi: -57, noise: -95)
                ],
                scannedAt: Date()
            )
        )

        await store.generateAILabel(for: "AA:BB:CC:DD:EE:02")

        XCTAssertEqual(store.annotationList.first?.friendlyName, "HP Printer (Office Printer)")
    }

    func testGenerateAILabelAvoidsDuplicateParentheticalWhenExistingLabelMatchesAIResult() async throws {
        let repository = InMemoryAnnotationRepository(records: [
            NetworkAnnotationRecord(
                bssid: "AA:BB:CC:DD:EE:03",
                friendlyName: "Apple iPhone",
                isOwned: false,
                accentSeed: 0.4
            )
        ])
        let settingsStore = makeSettingsStore()
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: repository,
            openAISettingsStore: settingsStore,
            deviceLabelingService: MockDeviceLabelingService(result: .success("Apple iPhone")),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.start()
        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:03", ssid: nil, channel: 149, band: .band5, channelWidthMHz: 80, rssi: -49, noise: -93)
                ],
                scannedAt: Date()
            )
        )

        await store.generateAILabel(for: "AA:BB:CC:DD:EE:03")

        XCTAssertEqual(store.annotationList.first?.friendlyName, "Apple iPhone")
    }

    func testGenerateAILabelReportsConfigurationAndServiceErrors() async throws {
        let repository = InMemoryAnnotationRepository()
        let emptySettings = OpenAISettingsStore(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            keychain: InMemoryKeychainValueStore()
        )
        emptySettings.model = ""
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: repository,
            openAISettingsStore: emptySettings,
            deviceLabelingService: MockDeviceLabelingService(result: .failure(DeviceLabelingServiceError.requestFailed("ignored"))),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        store.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:04", ssid: "Camera", channel: 11, band: .band2_4, channelWidthMHz: 20, rssi: -63, noise: -95)
                ],
                scannedAt: Date()
            )
        )

        await store.generateAILabel(for: "AA:BB:CC:DD:EE:04")
        XCTAssertEqual(
            store.selectedAILabelingMessage,
            "Add your OpenAI API key and reasoning model in Settings to generate AI labels."
        )

        let configuredStore = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: repository,
            openAISettingsStore: makeSettingsStore(),
            deviceLabelingService: MockDeviceLabelingService(result: .failure(DeviceLabelingServiceError.requestFailed("OpenAI request failed."))),
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            now: Date.init
        )

        configuredStore.applyScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:05", ssid: "Tablet", channel: 157, band: .band5, channelWidthMHz: 80, rssi: -55, noise: -95)
                ],
                scannedAt: Date()
            )
        )
        configuredStore.selectSignal("AA:BB:CC:DD:EE:05")

        await configuredStore.generateAILabel(for: "AA:BB:CC:DD:EE:05")

        XCTAssertEqual(configuredStore.selectedAILabelingMessage, "OpenAI request failed.")
    }

    private func makeSettingsStore() -> OpenAISettingsStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let keychain = InMemoryKeychainValueStore(values: ["openai.api-key": "sk-test"])
        let store = OpenAISettingsStore(defaults: defaults, keychain: keychain)
        store.model = OpenAISettingsStore.exampleMiniModel
        return store
    }
}

private final class MockDeviceLabelingService: DeviceLabelingService {
    private let result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func generateLabel(
        for macAddress: String,
        model: String,
        apiKey: String,
        maxOutputTokens: Int
    ) async throws -> String {
        _ = (macAddress, model, apiKey, maxOutputTokens)
        return try result.get()
    }
}
