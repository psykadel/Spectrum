import Foundation
import SwiftUI

enum SpectrumBand: Int, CaseIterable, Codable, Hashable, Identifiable {
    case band2_4
    case band5
    case band6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .band2_4:
            "2.4 GHz"
        case .band5:
            "5 GHz"
        case .band6:
            "6 GHz"
        }
    }

    var shortTitle: String {
        switch self {
        case .band2_4:
            "2.4"
        case .band5:
            "5"
        case .band6:
            "6"
        }
    }

    var frequencyRangeMHz: ClosedRange<Double> {
        switch self {
        case .band2_4:
            2400 ... 2500
        case .band5:
            5000 ... 5900
        case .band6:
            5925 ... 7125
        }
    }

    var visualCenterRangeMHz: ClosedRange<Double> {
        switch self {
        case .band2_4:
            2402 ... 2472
        case .band5:
            5170 ... 5835
        case .band6:
            5935 ... 7115
        }
    }

    var majorChannels: [Int] {
        switch self {
        case .band2_4:
            [1, 6, 11]
        case .band5:
            [36, 52, 100, 149, 165]
        case .band6:
            [1, 33, 65, 97, 129, 161, 193, 225]
        }
    }
}

struct BandVisibility: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let band2_4 = BandVisibility(rawValue: 1 << 0)
    static let band5 = BandVisibility(rawValue: 1 << 1)
    static let band6 = BandVisibility(rawValue: 1 << 2)

    static let `default`: BandVisibility = [.band2_4, .band5]
    static let all: BandVisibility = [.band2_4, .band5, .band6]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    func contains(_ band: SpectrumBand) -> Bool {
        contains(Self.option(for: band))
    }

    mutating func set(_ band: SpectrumBand, enabled: Bool) {
        if enabled {
            insert(Self.option(for: band))
        } else {
            remove(Self.option(for: band))
        }
    }

    mutating func toggle(_ band: SpectrumBand) {
        if contains(band) {
            remove(Self.option(for: band))
        } else {
            insert(Self.option(for: band))
        }
    }

    var orderedBands: [SpectrumBand] {
        SpectrumBand.allCases.filter { contains($0) }
    }

    private static func option(for band: SpectrumBand) -> BandVisibility {
        switch band {
        case .band2_4:
            .band2_4
        case .band5:
            .band5
        case .band6:
            .band6
        }
    }
}

enum LocationAccessState: Equatable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case restricted
    case servicesDisabled
}

enum SpectrumOverlayState: Equatable {
    case permissionRequired
    case permissionDenied
    case wifiOff
    case noInterface
}

struct WiFiInterfaceSnapshot: Equatable {
    var availableInterfaceNames: [String]
    var selectedInterfaceName: String?
    var isPoweredOn: Bool

    static let empty = WiFiInterfaceSnapshot(
        availableInterfaceNames: [],
        selectedInterfaceName: nil,
        isPoweredOn: false
    )
}

struct WiFiScanObservation: Equatable, Identifiable {
    let bssid: String
    let ssid: String?
    let channel: Int
    let band: SpectrumBand
    let channelWidthMHz: Int
    let rssi: Int
    let noise: Int

    var id: String { bssid }
}

struct WiFiScanSnapshot: Equatable {
    let interface: WiFiInterfaceSnapshot
    let observations: [WiFiScanObservation]
    let scannedAt: Date
}

enum BandChannelAdvice: Equatable, Hashable {
    case scanning
    case recommended(primaryChannel: Int, channelWidthMHz: Int)

    func badgeText(for band: SpectrumBand) -> String {
        switch self {
        case .scanning:
            "Scanning…"
        case let .recommended(primaryChannel, channelWidthMHz):
            switch band {
            case .band2_4:
                "Clearest: \(primaryChannel)"
            case .band5, .band6:
                "Clearest: \(primaryChannel) • \(channelWidthMHz) MHz"
            }
        }
    }
}

struct ObservedAccessPoint: Identifiable, Equatable {
    let bssid: String
    var ssid: String?
    var channel: Int
    var band: SpectrumBand
    var channelWidthMHz: Int
    var rssi: Int
    var noise: Int
    var firstSeenAt: Date
    var lastSeenAt: Date
    var instabilityScore: Double
    var missedScanCount: Int
    var lastRSSIDelta: Double

    var id: String { bssid }

    init(sample: WiFiScanObservation, at date: Date) {
        bssid = sample.bssid
        ssid = sample.ssid
        channel = sample.channel
        band = sample.band
        channelWidthMHz = sample.channelWidthMHz
        rssi = sample.rssi
        noise = sample.noise
        firstSeenAt = date
        lastSeenAt = date
        instabilityScore = 0
        missedScanCount = 0
        lastRSSIDelta = 0
    }

    mutating func absorb(_ sample: WiFiScanObservation, at date: Date) {
        let delta = abs(Double(sample.rssi - rssi))
        lastRSSIDelta = delta
        instabilityScore = min(1, max(instabilityScore * 0.45, delta / 24) + Double(missedScanCount) * 0.08)
        ssid = sample.ssid ?? ssid
        channel = sample.channel
        band = sample.band
        channelWidthMHz = sample.channelWidthMHz
        rssi = sample.rssi
        noise = sample.noise
        lastSeenAt = date
        missedScanCount = 0
    }

    mutating func registerMiss(at _: Date) {
        missedScanCount += 1
        instabilityScore = min(1, instabilityScore * 0.75 + Double(missedScanCount) * 0.12)
    }
}

struct NetworkAnnotationRecord: Equatable, Hashable, Identifiable {
    let bssid: String
    var friendlyName: String
    var isOwned: Bool
    var accentSeed: Double

    var id: String { bssid }

    var trimmedFriendlyName: String {
        friendlyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RenderedSignalEnvelope: Identifiable, Equatable {
    let bssid: String
    let displayName: String
    let subtitle: String
    let band: SpectrumBand
    let ssid: String?
    let channel: Int
    let channelWidthMHz: Int
    let rssi: Int
    let noise: Int
    let centerFraction: CGFloat
    let widthFraction: CGFloat
    let amplitude: CGFloat
    let bodyOpacity: Double
    let haloOpacity: Double
    let labelOpacity: Double
    let shimmer: Double
    let strokeWidth: CGFloat
    let isOwned: Bool
    let isGhost: Bool
    let accentSeed: Double
    let lastSeenAt: Date

    var id: String { bssid }
}

struct InspectorChannelGroup: Identifiable, Equatable {
    let band: SpectrumBand
    let channel: Int
    let signals: [RenderedSignalEnvelope]

    var id: String { "\(band.rawValue)-\(channel)" }

    var title: String {
        "Channel \(channel) · \(band.title)"
    }
}

enum SpectrumMath {
    static func orderedBands(for visibility: BandVisibility) -> [SpectrumBand] {
        visibility.orderedBands
    }

    static func centerFrequencyMHz(channel: Int, band: SpectrumBand) -> Double {
        switch band {
        case .band2_4:
            channel == 14 ? 2484 : 2407 + Double(channel * 5)
        case .band5:
            5000 + Double(channel * 5)
        case .band6:
            5950 + Double(channel * 5)
        }
    }

    static func normalizedCenter(channel: Int, band: SpectrumBand) -> CGFloat {
        let frequency = centerFrequencyMHz(channel: channel, band: band)
        let range = band.visualCenterRangeMHz
        let progress = (frequency - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(min(max(progress, 0), 1))
    }

    static func normalizedWidth(channelWidthMHz: Int, band: SpectrumBand) -> CGFloat {
        let width = occupiedChannelWidthMHz(channelWidthMHz: channelWidthMHz, band: band)
        let range = band.visualCenterRangeMHz
        let progress = width / (range.upperBound - range.lowerBound)
        return CGFloat(progress)
    }

    static func occupiedChannelWidthMHz(channelWidthMHz: Int, band: SpectrumBand) -> Double {
        let width = Double(max(channelWidthMHz, 20))

        switch band {
        case .band2_4:
            switch Int(width) {
            case 20:
                return 22
            case 40:
                return 44
            default:
                return width
            }
        case .band5, .band6:
            return width
        }
    }

    static func normalizedStrength(rssi: Int) -> CGFloat {
        let clamped = min(max(rssi, -95), -35)
        let progress = Double(clamped + 95) / 60
        return CGFloat(0.22 + progress * 0.7)
    }

    static func ghostDecayOpacity(elapsed: TimeInterval, decayDuration: TimeInterval = 20, floor: Double = 0.22) -> Double {
        guard elapsed > 0 else { return 1 }
        let progress = min(elapsed / decayDuration, 1)
        return 1 - progress * (1 - floor)
    }

    static func ghostAmplitude(liveAmplitude: CGFloat, elapsed: TimeInterval, decayDuration: TimeInterval = 20, floor: CGFloat = 0.24) -> CGFloat {
        let progress = CGFloat(min(max(elapsed / decayDuration, 0), 1))
        let target = max(floor, liveAmplitude * 0.35)
        return liveAmplitude + (target - liveAmplitude) * progress
    }
}
