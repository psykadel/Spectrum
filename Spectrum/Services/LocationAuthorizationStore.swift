import CoreLocation
import Foundation

@MainActor
protocol LocationAuthorizationProviding: AnyObject {
    var eventHandler: (@MainActor (LocationAccessState) -> Void)? { get set }
    var currentState: LocationAccessState { get }

    func requestAuthorization()
    func refresh()
}

@MainActor
final class LocationAuthorizationStore: NSObject, LocationAuthorizationProviding {
    var eventHandler: (@MainActor (LocationAccessState) -> Void)?
    private let locationManager = CLLocationManager()
    private(set) var currentState: LocationAccessState = .unknown

    override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    func requestAuthorization() {
        guard CLLocationManager.locationServicesEnabled() else {
            updateState()
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }

    func refresh() {
        updateState()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateState()
    }

    private func updateState() {
        let servicesEnabled = CLLocationManager.locationServicesEnabled()
        let nextState = Self.makeState(
            authorizationStatus: locationManager.authorizationStatus,
            servicesEnabled: servicesEnabled
        )
        currentState = nextState
        eventHandler?(nextState)
    }

    private static func makeState(
        authorizationStatus: CLAuthorizationStatus,
        servicesEnabled: Bool
    ) -> LocationAccessState {
        guard servicesEnabled else { return .servicesDisabled }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return LocationAccessState.authorized
        case .notDetermined:
            return LocationAccessState.notDetermined
        case .denied:
            return LocationAccessState.denied
        case .restricted:
            return LocationAccessState.restricted
        @unknown default:
            return LocationAccessState.unknown
        }
    }
}

extension LocationAuthorizationStore: @preconcurrency CLLocationManagerDelegate {}

@MainActor
final class MockLocationAuthorizationStore: LocationAuthorizationProviding {
    var eventHandler: (@MainActor (LocationAccessState) -> Void)?
    private(set) var currentState: LocationAccessState
    private(set) var requestAuthorizationCallCount = 0

    init(initialState: LocationAccessState) {
        currentState = initialState
    }

    func requestAuthorization() {
        requestAuthorizationCallCount += 1
        setState(.authorized)
    }

    func refresh() {
        eventHandler?(currentState)
    }

    func setState(_ state: LocationAccessState) {
        currentState = state
        eventHandler?(state)
    }
}
