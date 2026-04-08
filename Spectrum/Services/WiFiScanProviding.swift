import Foundation

enum WiFiScannerEvent: Equatable {
    case interfaceStateChanged(WiFiInterfaceSnapshot)
    case scanUpdated(WiFiScanSnapshot)
    case scanFailed(String)
}

@MainActor
protocol WiFiScanProviding: AnyObject {
    var eventHandler: (@MainActor (WiFiScannerEvent) -> Void)? { get set }
    var selectedInterfaceName: String? { get }

    func start()
    func stop()
    func resetSession()
    func setFocused(_ focused: Bool)
    func selectInterface(named name: String?)
    func requestImmediateScan() async
}

@MainActor
final class MockWiFiScanner: WiFiScanProviding {
    var eventHandler: (@MainActor (WiFiScannerEvent) -> Void)?
    private(set) var selectedInterfaceName: String?
    private var latestState: WiFiInterfaceSnapshot
    private var latestSnapshot: WiFiScanSnapshot?

    init(
        interface: WiFiInterfaceSnapshot = .init(
            availableInterfaceNames: ["en0"],
            selectedInterfaceName: "en0",
            isPoweredOn: true
        ),
        snapshot: WiFiScanSnapshot? = nil
    ) {
        latestState = interface
        latestSnapshot = snapshot
        selectedInterfaceName = interface.selectedInterfaceName
    }

    func start() {
        eventHandler?(.interfaceStateChanged(latestState))
        if let latestSnapshot {
            eventHandler?(.scanUpdated(latestSnapshot))
        }
    }

    func stop() {}

    func resetSession() {
        latestSnapshot = nil
    }

    func setFocused(_: Bool) {}

    func selectInterface(named name: String?) {
        selectedInterfaceName = name
        latestState.selectedInterfaceName = name
        eventHandler?(.interfaceStateChanged(latestState))
    }

    func requestImmediateScan() async {
        if let latestSnapshot {
            eventHandler?(.scanUpdated(latestSnapshot))
        }
    }

    func pushState(_ state: WiFiInterfaceSnapshot) {
        latestState = state
        selectedInterfaceName = state.selectedInterfaceName
        eventHandler?(.interfaceStateChanged(state))
    }

    func pushSnapshot(_ snapshot: WiFiScanSnapshot) {
        latestSnapshot = snapshot
        latestState = snapshot.interface
        selectedInterfaceName = snapshot.interface.selectedInterfaceName
        eventHandler?(.scanUpdated(snapshot))
    }
}
