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
}
