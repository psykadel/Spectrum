import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SpectrumStore {
    private enum DefaultsKey {
        static let bandVisibility = "Spectrum.bandVisibility"
    }

    private static let defaultAnimationIntensity = 0.58

    private let scanner: any WiFiScanProviding
    private let locationStore: any LocationAuthorizationProviding
    private let annotationRepository: any NetworkAnnotationRepositoryProtocol
    private let openAISettingsStore: OpenAISettingsStore
    private let deviceLabelingService: any DeviceLabelingService
    private let defaults: UserDefaults
    private let now: () -> Date
    private let openURL: (URL) -> Bool

    private(set) var interfaceSnapshot: WiFiInterfaceSnapshot = .empty
    private(set) var locationAccessState: LocationAccessState
    private(set) var scannerMessage: String?
    private(set) var observedAccessPoints: [String: ObservedAccessPoint] = [:]
    private(set) var annotationRecords: [NetworkAnnotationRecord] = []
    private(set) var hasStarted = false
    private(set) var sceneIsFocused = true
    private(set) var scanGeneration = 0
    private(set) var activeAILabelRequests: Set<String> = []
    private(set) var aiLabelingErrors: [String: String] = [:]
    private(set) var aiLabelingDebugDetails: [String: String] = [:]

    var bandVisibility: BandVisibility
    var isInspectorVisible = false
    var selectedBSSID: String?

    init(
        scanner: any WiFiScanProviding,
        locationStore: any LocationAuthorizationProviding,
        annotationRepository: any NetworkAnnotationRepositoryProtocol,
        openAISettingsStore: OpenAISettingsStore,
        deviceLabelingService: any DeviceLabelingService,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.scanner = scanner
        self.locationStore = locationStore
        self.annotationRepository = annotationRepository
        self.openAISettingsStore = openAISettingsStore
        self.deviceLabelingService = deviceLabelingService
        self.defaults = defaults
        self.now = now
        self.openURL = openURL
        locationAccessState = locationStore.currentState

        let storedBands = defaults.object(forKey: DefaultsKey.bandVisibility) as? Int ?? BandVisibility.default.rawValue
        bandVisibility = BandVisibility(rawValue: storedBands).isEmpty ? .default : BandVisibility(rawValue: storedBands)
    }

    convenience init(
        scanner: any WiFiScanProviding,
        locationStore: any LocationAuthorizationProviding,
        annotationRepository: any NetworkAnnotationRepositoryProtocol,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.init(
            scanner: scanner,
            locationStore: locationStore,
            annotationRepository: annotationRepository,
            openAISettingsStore: OpenAISettingsStore(),
            deviceLabelingService: OpenAIResponsesDeviceLabelingService(),
            defaults: defaults,
            now: now,
            openURL: openURL
        )
    }

    var activeBands: [SpectrumBand] {
        let ordered = SpectrumMath.orderedBands(for: bandVisibility)
        return ordered.isEmpty ? [.band2_4] : ordered
    }

    var overlayState: SpectrumOverlayState? {
        switch locationAccessState {
        case .notDetermined, .unknown, .servicesDisabled:
            return .permissionRequired
        case .denied, .restricted:
            return .permissionDenied
        case .authorized:
            break
        }

        if interfaceSnapshot.availableInterfaceNames.isEmpty {
            return .noInterface
        }

        if !interfaceSnapshot.isPoweredOn {
            return .wifiOff
        }

        return nil
    }

    var statusLine: String {
        if let overlayState {
            switch overlayState {
            case .permissionRequired:
                return "Location access is required for network names and radio identifiers."
            case .permissionDenied:
                return "Location access is denied."
            case .wifiOff:
                return "Wi-Fi is turned off."
            case .noInterface:
                return "No Wi-Fi interface is available."
            }
        }

        let interfaceLabel = interfaceSnapshot.selectedInterfaceName ?? "Wi-Fi"
        let totalSignals = observedAccessPoints.count
        if let scannerMessage, !scannerMessage.isEmpty {
            return "\(interfaceLabel) · \(scannerMessage)"
        }
        return "\(interfaceLabel) · \(totalSignals) tracked signals"
    }

    var displayedSignal: RenderedSignalEnvelope? {
        let date = now()
        guard let focalBSSID = selectedBSSID else { return nil }
        return renderedSignal(for: focalBSSID, at: date)
    }

    var inspectorSignals: [RenderedSignalEnvelope] {
        let activeBandSet = Set(activeBands)
        return allRenderedSignals(at: now())
            .filter { activeBandSet.contains($0.band) }
            .sorted {
                if $0.band != $1.band { return $0.band.rawValue < $1.band.rawValue }
                if $0.channel != $1.channel { return $0.channel < $1.channel }
                if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
                if $0.isOwned != $1.isOwned { return $0.isOwned && !$1.isOwned }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var inspectorGroups: [InspectorChannelGroup] {
        let grouped = Dictionary(grouping: inspectorSignals) { signal in
            "\(signal.band.rawValue)-\(signal.channel)"
        }

        return grouped.values
            .map { signals in
                let sortedSignals = signals.sorted {
                    if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
                    if $0.isOwned != $1.isOwned { return $0.isOwned && !$1.isOwned }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                let first = sortedSignals[0]
                return InspectorChannelGroup(
                    band: first.band,
                    channel: first.channel,
                    signals: sortedSignals
                )
            }
            .sorted {
                if $0.band != $1.band { return $0.band.rawValue < $1.band.rawValue }
                return $0.channel < $1.channel
            }
    }

    var annotationList: [NetworkAnnotationRecord] {
        annotationRecords.sorted {
            let lhs = $0.trimmedFriendlyName.isEmpty ? $0.bssid : $0.trimmedFriendlyName
            let rhs = $1.trimmedFriendlyName.isEmpty ? $1.bssid : $1.trimmedFriendlyName
            return (lhs, $0.bssid) < (rhs, $1.bssid)
        }
    }

    var canGenerateAILabels: Bool {
        openAISettingsStore.isConfigured
    }

    var selectedAILabelingMessage: String? {
        if !openAISettingsStore.isConfigured {
            return "Add your OpenAI API key and reasoning model in Settings to generate AI labels."
        }

        guard let selectedBSSID else { return nil }
        return aiLabelingErrors[selectedBSSID]
    }

    var selectedAILabelingDebugDetails: String? {
        guard let selectedBSSID else { return nil }
        return aiLabelingDebugDetails[selectedBSSID]
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        scanner.eventHandler = { [weak self] event in
            self?.handleScannerEvent(event)
        }

        locationStore.eventHandler = { [weak self] state in
            self?.locationAccessState = state
        }

        do {
            annotationRecords = try annotationRepository.loadAll()
        } catch {
            scannerMessage = error.localizedDescription
        }

        locationStore.refresh()
        scanner.start()
    }

    func stop() {
        scanner.stop()
        hasStarted = false
    }

    func setSceneFocused(_ focused: Bool) {
        guard sceneIsFocused != focused else { return }
        sceneIsFocused = focused
        scanner.setFocused(focused)
    }

    func toggleBand(_ band: SpectrumBand) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            if bandVisibility.contains(band), activeBands.count == 1 {
                return
            }
            bandVisibility.toggle(band)
            if bandVisibility.isEmpty {
                bandVisibility = [.band2_4]
            }
        }
        persistPreferences()
    }

    func setBandEnabled(_ band: SpectrumBand, enabled: Bool) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            bandVisibility.set(band, enabled: enabled)
            if bandVisibility.isEmpty {
                bandVisibility = [.band2_4]
            }
        }
        persistPreferences()
    }

    func performLocationAccessAction() {
        switch locationAccessState {
        case .notDetermined:
            locationStore.requestAuthorization()
        case .denied, .restricted, .servicesDisabled, .unknown:
            openLocationSettings()
        case .authorized:
            break
        }
    }

    func openLocationSettings() {
        let candidates = [
            "settings-navigation://com.apple.settings.PrivacySecurity.extension/Privacy_LocationServices",
            "settings-navigation://com.apple.settings.PrivacySecurity.extension/LOCATION_SERVICES",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if openURL(url) {
                return
            }
        }
    }

    func selectInterface(_ name: String?) {
        scanner.selectInterface(named: name)
    }

    func rescanNow() {
        Task {
            await scanner.requestImmediateScan()
        }
    }

    func clearSignals() {
        withAnimation(.easeInOut(duration: 0.24)) {
            observedAccessPoints.removeAll()
            selectedBSSID = nil
            scannerMessage = nil
        }
        scanGeneration += 1
        scanner.resetSession()
        scanner.stop()
        if hasStarted {
            scanner.start()
            scanner.setFocused(sceneIsFocused)
        }
    }

    func selectSignal(_ bssid: String?) {
        selectedBSSID = bssid
        if let bssid {
            aiLabelingErrors[bssid] = nil
            aiLabelingDebugDetails[bssid] = nil
        }
        guard let bssid else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bssid, forType: .string)
    }

    func isGeneratingAILabel(for bssid: String) -> Bool {
        activeAILabelRequests.contains(bssid)
    }

    func generateAILabel(for bssid: String) async {
        guard !activeAILabelRequests.contains(bssid) else { return }

        guard let signal = renderedSignal(for: bssid, at: now()) else {
            aiLabelingErrors[bssid] = "This device is no longer available."
            return
        }

        guard let configuration = openAISettingsStore.configuration else {
            aiLabelingErrors[bssid] = DeviceLabelingServiceError.missingConfiguration.localizedDescription
            return
        }

        activeAILabelRequests.insert(bssid)
        aiLabelingErrors[bssid] = nil
        aiLabelingDebugDetails[bssid] = nil

        do {
            let baseLabel = try await deviceLabelingService.generateLabel(
                for: bssid,
                model: configuration.model,
                apiKey: configuration.apiKey,
                maxOutputTokens: configuration.maxOutputTokens
            )
            let mergedLabel = mergedAILabel(
                aiLabel: baseLabel,
                currentDisplayName: signal.displayName,
                bssid: bssid
            )
            saveAnnotation(
                bssid: bssid,
                friendlyName: mergedLabel,
                isOwned: signal.isOwned
            )
        } catch {
            aiLabelingErrors[bssid] = error.localizedDescription
            aiLabelingDebugDetails[bssid] = debugDetails(from: error)
        }

        activeAILabelRequests.remove(bssid)
    }

    func renderedSignals(for band: SpectrumBand, at date: Date) -> [RenderedSignalEnvelope] {
        let rawSignals = allRenderedSignals(at: date).filter { $0.band == band }
        guard let strongestSignal = rawSignals.max(by: { $0.rssi < $1.rssi }) else {
            return rawSignals
        }

        let dynamicPeak = strongestSignal.rssi
        return rawSignals.map { signal in
            let normalizedAmplitude = normalizedAmplitude(
                rssi: signal.rssi,
                peakRSSI: dynamicPeak,
                isGhost: signal.isGhost,
                lastSeenAt: signal.lastSeenAt,
                date: date
            )
            return RenderedSignalEnvelope(
                bssid: signal.bssid,
                displayName: signal.displayName,
                subtitle: signal.subtitle,
                band: signal.band,
                ssid: signal.ssid,
                channel: signal.channel,
                channelWidthMHz: signal.channelWidthMHz,
                rssi: signal.rssi,
                noise: signal.noise,
                centerFraction: signal.centerFraction,
                widthFraction: signal.widthFraction,
                amplitude: normalizedAmplitude,
                bodyOpacity: signal.bodyOpacity,
                haloOpacity: signal.haloOpacity,
                labelOpacity: signal.labelOpacity,
                shimmer: signal.shimmer,
                strokeWidth: signal.strokeWidth,
                isOwned: signal.isOwned,
                isGhost: signal.isGhost,
                accentSeed: signal.accentSeed,
                lastSeenAt: signal.lastSeenAt
            )
        }
    }

    func renderedSignal(for bssid: String, at date: Date) -> RenderedSignalEnvelope? {
        guard let point = observedAccessPoints[bssid] else { return nil }
        return makeEnvelope(from: point, at: date)
    }

    func saveAnnotation(
        bssid: String,
        friendlyName: String,
        isOwned: Bool
    ) {
        let seed = annotation(for: bssid)?.accentSeed ?? accentSeed(for: bssid)
        let record = NetworkAnnotationRecord(
            bssid: bssid,
            friendlyName: friendlyName,
            isOwned: isOwned,
            accentSeed: seed
        )

        do {
            try annotationRepository.save(record)
            annotationRecords = try annotationRepository.loadAll()
        } catch {
            scannerMessage = error.localizedDescription
        }
    }

    func handleScannerEvent(_ event: WiFiScannerEvent) {
        switch event {
        case let .interfaceStateChanged(snapshot):
            interfaceSnapshot = snapshot
        case let .scanUpdated(snapshot):
            scannerMessage = nil
            applyScanSnapshot(snapshot)
        case let .scanFailed(message):
            scannerMessage = message
        }
    }

    func applyScanSnapshot(_ snapshot: WiFiScanSnapshot) {
        interfaceSnapshot = snapshot.interface
        var seenBSSIDs = Set<String>()

        for sample in snapshot.observations {
            seenBSSIDs.insert(sample.bssid)
            if var existing = observedAccessPoints[sample.bssid] {
                existing.absorb(sample, at: snapshot.scannedAt)
                observedAccessPoints[sample.bssid] = existing
            } else {
                observedAccessPoints[sample.bssid] = ObservedAccessPoint(sample: sample, at: snapshot.scannedAt)
            }
        }

        for key in observedAccessPoints.keys where !seenBSSIDs.contains(key) {
            observedAccessPoints[key]?.registerMiss(at: snapshot.scannedAt)
        }
    }

    func overlayCopy(for state: SpectrumOverlayState) -> (title: String, body: String, action: String?) {
        switch state {
        case .permissionRequired:
            switch locationAccessState {
            case .servicesDisabled:
                return (
                    "Location Services Are Off",
                    "Spectrum needs macOS Location Services enabled before the system can reveal nearby Wi-Fi names and BSSIDs. Open Settings to turn Location Services back on.",
                    nil
                )
            case .unknown:
                return (
                    "Location Access Needed",
                    "Spectrum needs macOS location access before nearby Wi-Fi radios can be labeled consistently. Open Settings to review the permission state.",
                    nil
                )
            case .notDetermined, .authorized, .denied, .restricted:
                return (
                    "Location Access Needed",
                    "macOS hides nearby Wi-Fi names and BSSIDs until Spectrum has location permission. Grant access to unlock live labeling and identity tracking.",
                    nil
                )
            }
        case .permissionDenied:
            return (
                "Location Access Denied",
                "Spectrum can still render the canvas shell, but network identity and consistent labeling depend on Location Services. Open Settings to restore access.",
                "Open Location Settings"
            )
        case .wifiOff:
            return (
                "Wi-Fi Is Off",
                "Turn Wi-Fi back on to resume scans and refresh the live spectrum."
                ,
                nil
            )
        case .noInterface:
            return (
                "No Wi-Fi Interface",
                "Spectrum couldn't find an available Wi-Fi radio on this Mac right now.",
                nil
            )
        }
    }

    private func allRenderedSignals(at date: Date) -> [RenderedSignalEnvelope] {
        observedAccessPoints.values
            .compactMap { makeEnvelope(from: $0, at: date) }
            .sorted {
                if $0.isOwned != $1.isOwned { return $0.isOwned && !$1.isOwned }
                if $0.isGhost != $1.isGhost { return !$0.isGhost && $1.isGhost }
                return $0.rssi > $1.rssi
            }
    }

    private func makeEnvelope(from point: ObservedAccessPoint, at date: Date) -> RenderedSignalEnvelope? {
        let annotation = annotation(for: point.bssid)
        let age = max(date.timeIntervalSince(point.lastSeenAt), 0)
        let isGhost = age > 4
        let liveAmplitude = SpectrumMath.normalizedStrength(rssi: point.rssi)
        let amplitude = isGhost
            ? SpectrumMath.ghostAmplitude(liveAmplitude: liveAmplitude, elapsed: age - 4)
            : liveAmplitude
        let ghostOpacity = SpectrumMath.ghostDecayOpacity(elapsed: max(age - 4, 0))
        let isOwned = annotation?.isOwned == true
        let emphasis = isOwned ? 1.45 : 1
        let displayName = resolvedName(for: point, annotation: annotation)
        let subtitle = subtitle(for: point, annotation: annotation)
        let channelWidth = max(point.channelWidthMHz, 20)
        let bodyOpacity = isOwned
            ? (isGhost ? ghostOpacity * 0.58 : min(0.98, 0.62 + Double(liveAmplitude) * 0.28))
            : (isGhost ? ghostOpacity * 0.42 : min(0.92, 0.46 + Double(liveAmplitude) * 0.36))
        let haloOpacity = (isGhost ? ghostOpacity * 0.16 : 0.22 + Double(liveAmplitude) * 0.22) * emphasis
        let labelOpacity = isOwned
            ? max(0.92, bodyOpacity)
            : (isGhost ? max(0.18, ghostOpacity * 0.45) : min(1, bodyOpacity + 0.08))
        let shimmer = isGhost ? 0 : min(1, point.instabilityScore * (0.35 + Self.defaultAnimationIntensity * 0.65))
        let accentSeed = annotation?.accentSeed ?? accentSeed(for: point.bssid)

        return RenderedSignalEnvelope(
            bssid: point.bssid,
            displayName: displayName,
            subtitle: subtitle,
            band: point.band,
            ssid: point.ssid,
            channel: point.channel,
            channelWidthMHz: channelWidth,
            rssi: point.rssi,
            noise: point.noise,
            centerFraction: SpectrumMath.normalizedCenter(channel: point.channel, band: point.band),
            widthFraction: SpectrumMath.normalizedWidth(channelWidthMHz: channelWidth, band: point.band),
            amplitude: amplitude,
            bodyOpacity: bodyOpacity,
            haloOpacity: haloOpacity,
            labelOpacity: labelOpacity,
            shimmer: shimmer,
            strokeWidth: CGFloat((isOwned ? 3.3 : 1.45) * (isGhost ? 0.92 : 1)),
            isOwned: isOwned,
            isGhost: isGhost,
            accentSeed: accentSeed,
            lastSeenAt: point.lastSeenAt
        )
    }

    private func normalizedAmplitude(
        rssi: Int,
        peakRSSI: Int,
        isGhost: Bool,
        lastSeenAt: Date,
        date: Date
    ) -> CGFloat {
        let floorRSSI = min(-95, peakRSSI - 45)
        let clamped = min(max(rssi, floorRSSI), peakRSSI)
        let range = max(Double(peakRSSI - floorRSSI), 1)
        let normalized = Double(clamped - floorRSSI) / range
        let liveAmplitude = CGFloat(0.22 + normalized * 0.7)

        guard isGhost else { return liveAmplitude }

        let age = max(date.timeIntervalSince(lastSeenAt), 0)
        return SpectrumMath.ghostAmplitude(liveAmplitude: liveAmplitude, elapsed: max(age - 4, 0))
    }

    private func resolvedName(for point: ObservedAccessPoint, annotation: NetworkAnnotationRecord?) -> String {
        if let annotation, !annotation.trimmedFriendlyName.isEmpty {
            return annotation.trimmedFriendlyName
        }
        if let ssid = point.ssid, !ssid.isEmpty {
            return ssid
        }
        return point.bssid
    }

    private func subtitle(for point: ObservedAccessPoint, annotation _: NetworkAnnotationRecord?) -> String {
        let channelLabel = "Ch \(point.channel) · \(point.band.title)"
        if let ssid = point.ssid, !ssid.isEmpty {
            return "\(channelLabel) · \(ssid)"
        }
        return channelLabel
    }

    private func annotation(for bssid: String) -> NetworkAnnotationRecord? {
        annotationRecords.first(where: { $0.bssid == bssid })
    }

    private func accentSeed(for bssid: String) -> Double {
        let scalar = bssid.unicodeScalars.reduce(into: UInt64(0)) { partial, scalar in
            partial = partial &* 31 &+ UInt64(scalar.value)
        }
        return Double(scalar % 1000) / 1000
    }

    private func mergedAILabel(
        aiLabel: String,
        currentDisplayName: String,
        bssid: String
    ) -> String {
        guard currentDisplayName != bssid else { return aiLabel }

        if currentDisplayName.localizedCaseInsensitiveCompare(aiLabel) == .orderedSame {
            return aiLabel
        }

        let mergedPrefix = aiLabel.lowercased() + " ("
        let loweredDisplayName = currentDisplayName.lowercased()
        if loweredDisplayName.hasPrefix(mergedPrefix), currentDisplayName.hasSuffix(")") {
            return currentDisplayName
        }

        return "\(aiLabel) (\(currentDisplayName))"
    }

    private func debugDetails(from error: Error) -> String? {
        if let serviceError = error as? DeviceLabelingServiceError {
            return serviceError.debugDetails
        }
        return nil
    }

    private func persistPreferences() {
        defaults.set(bandVisibility.rawValue, forKey: DefaultsKey.bandVisibility)
    }
}
