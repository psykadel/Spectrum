import XCTest
import SQLite3
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

    func testManualZigbeeChannelsPersistAsRenderedOverlapMarkers() {
        let defaults = UserDefaults(suiteName: #function)!
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: defaults,
            now: Date.init
        )

        store.addManualZigbeeChannels([25, 15, 15, 11])

        XCTAssertEqual(store.manualZigbeeChannels.map(\.channel), [11, 15, 25])
        XCTAssertEqual(store.renderedZigbeeChannels.map(\.channel), [11, 15, 25])

        let reloaded = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: defaults,
            now: Date.init
        )

        XCTAssertEqual(reloaded.manualZigbeeChannels.map(\.channel), [11, 15, 25])
    }

    func testRemovingManualZigbeeChannelUpdatesPersistedState() {
        let defaults = UserDefaults(suiteName: #function)!
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: defaults,
            now: Date.init
        )

        store.addManualZigbeeChannels([11, 20, 25])
        store.removeManualZigbeeChannel(20)

        XCTAssertEqual(store.manualZigbeeChannels.map(\.channel), [11, 25])

        let reloaded = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: defaults,
            now: Date.init
        )

        XCTAssertEqual(reloaded.manualZigbeeChannels.map(\.channel), [11, 25])
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

    func testBandAdviceTransitionsFromScanningToRecommendation() async {
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        let snapshot0 = WiFiScanSnapshot(
            interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
            observations: [
                .init(bssid: "AA:BB:CC:DD:EE:52", ssid: "Busy-52", channel: 52, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "AA:BB:CC:DD:EE:100", ssid: "Busy-100", channel: 100, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "AA:BB:CC:DD:EE:116", ssid: "Busy-116", channel: 116, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "AA:BB:CC:DD:EE:132", ssid: "Busy-132", channel: 132, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "AA:BB:CC:DD:EE:149", ssid: "Busy-149", channel: 149, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95)
            ],
            scannedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let snapshot1 = WiFiScanSnapshot(
            interface: snapshot0.interface,
            observations: snapshot0.observations,
            scannedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let snapshot2 = WiFiScanSnapshot(
            interface: snapshot0.interface,
            observations: snapshot0.observations,
            scannedAt: Date(timeIntervalSinceReferenceDate: 20)
        )

        await store.ingestScanSnapshot(snapshot0)
        XCTAssertEqual(store.advice(for: .band5), .scanning)

        await store.ingestScanSnapshot(snapshot1)
        XCTAssertEqual(store.advice(for: .band5), .scanning)

        await store.ingestScanSnapshot(snapshot2)
        XCTAssertEqual(store.advice(for: .band5), .recommended(primaryChannel: 36, channelWidthMHz: 80))
    }

    func testClearSignalsResetsChannelAdvisorState() async {
        let advisor = MockChannelAdvisor(advice: [
            .band5: .recommended(primaryChannel: 149, channelWidthMHz: 80)
        ])
        let store = SpectrumStore(
            scanner: MockWiFiScanner(),
            locationStore: MockLocationAuthorizationStore(initialState: .authorized),
            annotationRepository: InMemoryAnnotationRepository(),
            channelAdvisor: advisor,
            defaults: UserDefaults(suiteName: #function)!,
            now: Date.init
        )

        await store.ingestScanSnapshot(
            WiFiScanSnapshot(
                interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
                observations: [
                    .init(bssid: "AA:BB:CC:DD:EE:49", ssid: "Busy-149", channel: 149, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95)
                ],
                scannedAt: Date()
            )
        )
        XCTAssertEqual(store.advice(for: .band5), .recommended(primaryChannel: 149, channelWidthMHz: 80))

        store.clearSignals()

        for _ in 0 ..< 10 {
            if await advisor.currentResetCallCount() == 1 {
                break
            }
            await Task.yield()
        }

        let resetCallCount = await advisor.currentResetCallCount()
        XCTAssertEqual(resetCallCount, 1)
        XCTAssertEqual(store.advice(for: .band5), .scanning)
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

    func testAnnotationStoreLocationUsesBundleScopedStoreURL() throws {
        let rootDirectory = makeTemporaryDirectory()
        let storeURL = try AnnotationStoreLocation.prepareStoreURL(
            fileManager: .default,
            bundleIdentifier: "io.spectrum.custom",
            appSupportDirectory: rootDirectory
        )

        XCTAssertEqual(
            storeURL,
            rootDirectory
                .appendingPathComponent("io.spectrum.custom", isDirectory: true)
                .appendingPathComponent("NetworkAnnotations.store", isDirectory: false)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootDirectory
                    .appendingPathComponent("io.spectrum.custom", isDirectory: true)
                    .path()
            )
        )
    }

    func testAnnotationStoreLocationMigratesLegacyDefaultStore() throws {
        let rootDirectory = makeTemporaryDirectory()
        let legacyStoreURL = rootDirectory.appendingPathComponent("default.store", isDirectory: false)
        try createLegacyAnnotationStore(at: legacyStoreURL)

        let storeURL = try AnnotationStoreLocation.prepareStoreURL(
            fileManager: .default,
            bundleIdentifier: "io.spectrum.custom",
            appSupportDirectory: rootDirectory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path()))
        XCTAssertEqual(readTableNames(from: storeURL), ["ZNETWORKANNOTATION"])
        XCTAssertEqual(readTableNames(from: legacyStoreURL), ["ZNETWORKANNOTATION"])
    }

    private func makeSettingsStore() -> OpenAISettingsStore {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let keychain = InMemoryKeychainValueStore(values: ["openai.api-key": "sk-test"])
        let store = OpenAISettingsStore(defaults: defaults, keychain: keychain)
        store.model = OpenAISettingsStore.exampleMiniModel
        return store
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func createLegacyAnnotationStore(at url: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                url.path(),
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
                nil
            ),
            SQLITE_OK
        )
        guard let database else {
            XCTFail("Failed to create legacy test store")
            return
        }
        defer { sqlite3_close(database) }

        XCTAssertEqual(
            sqlite3_exec(
                database,
                "CREATE TABLE ZNETWORKANNOTATION (Z_PK INTEGER PRIMARY KEY, ZBSSID TEXT);",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
    }

    private func readTableNames(from url: URL) -> [String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path(), &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'Z%';",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }

        var tableNames: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                tableNames.append(String(cString: name))
            }
        }
        return tableNames.sorted()
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

private actor MockChannelAdvisor: ChannelAdvising {
    private(set) var resetCallCount = 0
    private var advice: [SpectrumBand: BandChannelAdvice]

    init(advice: [SpectrumBand: BandChannelAdvice]) {
        self.advice = advice
    }

    func ingest(_ snapshot: WiFiScanSnapshot) async -> [SpectrumBand: BandChannelAdvice] {
        _ = snapshot
        return advice
    }

    func reset() async {
        resetCallCount += 1
        advice = [:]
    }

    func currentResetCallCount() -> Int {
        resetCallCount
    }
}
