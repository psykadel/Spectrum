@preconcurrency import CoreWLAN
import Foundation

@MainActor
final class CoreWLANScanner: NSObject, WiFiScanProviding {
    var eventHandler: (@MainActor (WiFiScannerEvent) -> Void)?

    private let client: CWWiFiClient
    private let scanQueue = DispatchQueue(label: "Spectrum.CoreWLANScanner", qos: .userInitiated)
    private var pollTask: Task<Void, Never>?
    private var selectedInterfaceNameStorage: String?
    private var isFocused = true
    private var scanInFlight = false

    init(client: CWWiFiClient = .shared()) {
        self.client = client
        super.init()
    }

    var selectedInterfaceName: String? {
        selectedInterfaceNameStorage ?? currentInterface()?.interfaceName
    }

    func start() {
        client.delegate = self
        registerEvents()
        emitInterfaceState()
        restartPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        client.delegate = nil
    }

    func resetSession() {
        pollTask?.cancel()
        pollTask = nil
        scanInFlight = false
        emitInterfaceState()
    }

    func setFocused(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
        restartPolling()
    }

    func selectInterface(named name: String?) {
        selectedInterfaceNameStorage = name
        emitInterfaceState()
        Task {
            await requestImmediateScan()
        }
    }

    func requestImmediateScan() async {
        await performActiveScan()
    }

    private func currentInterface() -> CWInterface? {
        if let selectedInterfaceNameStorage, !selectedInterfaceNameStorage.isEmpty {
            return client.interface(withName: selectedInterfaceNameStorage)
        }
        return client.interface()
    }

    private func registerEvents() {
        do {
            try client.startMonitoringEvent(with: .powerDidChange)
            try client.startMonitoringEvent(with: .linkDidChange)
            try client.startMonitoringEvent(with: .scanCacheUpdated)
        } catch {
            Task { @MainActor [weak self] in
                self?.eventHandler?(.scanFailed(error.localizedDescription))
            }
        }
    }

    private func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await performActiveScan()
                let seconds = isFocused ? 2.0 : 5.0
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    private func emitInterfaceState() {
        let snapshot = interfaceSnapshot()
        Task { @MainActor [weak self] in
            self?.eventHandler?(.interfaceStateChanged(snapshot))
        }
    }

    private func interfaceSnapshot() -> WiFiInterfaceSnapshot {
        let names = client.interfaceNames() ?? []
        let interface = currentInterface()
        return WiFiInterfaceSnapshot(
            availableInterfaceNames: names.sorted(),
            selectedInterfaceName: interface?.interfaceName,
            isPoweredOn: interface?.powerOn() ?? false
        )
    }

    private func performActiveScan() async {
        guard !scanInFlight else { return }
        scanInFlight = true
        defer { scanInFlight = false }

        let interfaceState = interfaceSnapshot()
        guard interfaceState.isPoweredOn, let interface = currentInterface() else {
            await MainActor.run { [weak self] in
                self?.eventHandler?(.interfaceStateChanged(interfaceState))
            }
            return
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<WiFiScanSnapshot, Error>, Never>) in
            let snapshot = interfaceState
            scanQueue.async { [weak self] in
                guard self != nil else {
                    continuation.resume(returning: .success(.init(interface: snapshot, observations: [], scannedAt: Date())))
                    return
                }

                do {
                    let networks = try interface.scanForNetworks(withName: nil, includeHidden: true)
                    let observations = networks.compactMap(Self.makeObservation(from:))
                    continuation.resume(
                        returning: .success(
                            WiFiScanSnapshot(
                                interface: snapshot,
                                observations: observations.sorted { $0.rssi > $1.rssi },
                                scannedAt: Date()
                            )
                        )
                    )
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            switch result {
            case let .success(snapshot):
                eventHandler?(.scanUpdated(snapshot))
            case let .failure(error):
                eventHandler?(.scanFailed(error.localizedDescription))
            }
        }
    }

    private func emitCachedScan(for interfaceName: String) {
        guard let interface = client.interface(withName: interfaceName) else {
            emitInterfaceState()
            return
        }

        let cached = interface.cachedScanResults() ?? []
        let snapshot = WiFiScanSnapshot(
            interface: interfaceSnapshot(),
            observations: cached.compactMap(Self.makeObservation(from:)),
            scannedAt: Date()
        )
        Task { @MainActor [weak self] in
            self?.eventHandler?(.scanUpdated(snapshot))
        }
    }

    nonisolated private static func makeObservation(from network: CWNetwork) -> WiFiScanObservation? {
        guard
            let bssid = network.bssid?.uppercased(),
            let channel = network.wlanChannel
        else {
            return nil
        }

        let band: SpectrumBand
        switch channel.channelBand.rawValue {
        case 1:
            band = .band2_4
        case 2:
            band = .band5
        case 3:
            band = .band6
        default:
            return nil
        }

        let widthMHz: Int
        switch channel.channelWidth.rawValue {
        case 1:
            widthMHz = 20
        case 2:
            widthMHz = 40
        case 3:
            widthMHz = 80
        case 4:
            widthMHz = 160
        default:
            widthMHz = 20
        }

        return WiFiScanObservation(
            bssid: bssid,
            ssid: network.ssid,
            channel: channel.channelNumber,
            band: band,
            channelWidthMHz: widthMHz,
            rssi: network.rssiValue,
            noise: network.noiseMeasurement
        )
    }
}

extension CoreWLANScanner: @preconcurrency CWEventDelegate {
    func powerStateDidChangeForWiFiInterface(withName _: String) {
        emitInterfaceState()
    }

    func linkDidChangeForWiFiInterface(withName _: String) {
        emitInterfaceState()
    }

    func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
        emitCachedScan(for: interfaceName)
    }
}
