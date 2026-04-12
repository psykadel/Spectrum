import XCTest
@testable import Spectrum

final class ChannelAdvisorTests: XCTestCase {
    func testTwoPointFourPrefersCanonicalChannelWhenOverlapWinIsMarginal() async {
        let advisor = ChannelAdvisor()

        let advice = await ingestSeries(
            advisor: advisor,
            observations: [
                .init(bssid: "24:00:00:00:00:01", ssid: "Edge-1", channel: 1, band: .band2_4, channelWidthMHz: 20, rssi: -75, noise: -95),
                .init(bssid: "24:00:00:00:00:02", ssid: "Edge-2", channel: 2, band: .band2_4, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "24:00:00:00:00:03", ssid: "Edge-3", channel: 3, band: .band2_4, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "24:00:00:00:00:08", ssid: "Busy-8", channel: 8, band: .band2_4, channelWidthMHz: 20, rssi: -53, noise: -95)
            ]
        )

        XCTAssertEqual(advice[.band2_4], .recommended(primaryChannel: 1, channelWidthMHz: 20))
    }

    func testTwoPointFourAllowsOverlappingChannelWhenItIsClearlyBetter() async {
        let advisor = ChannelAdvisor()

        let advice = await ingestSeries(
            advisor: advisor,
            observations: [
                .init(bssid: "24:00:00:00:00:11", ssid: "Edge-1", channel: 1, band: .band2_4, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "24:00:00:00:00:12", ssid: "Edge-2", channel: 2, band: .band2_4, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "24:00:00:00:00:13", ssid: "Edge-3", channel: 3, band: .band2_4, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "24:00:00:00:00:19", ssid: "Busy-9", channel: 9, band: .band2_4, channelWidthMHz: 20, rssi: -67, noise: -95)
            ]
        )

        XCTAssertEqual(advice[.band2_4], .recommended(primaryChannel: 5, channelWidthMHz: 20))
    }

    func testFiveGigahertzPrefersNonDFSWhenDFSIsOnlySlightlyCleaner() async {
        let advisor = ChannelAdvisor()

        let advice = await ingestSeries(
            advisor: advisor,
            observations: [
                .init(bssid: "50:00:00:00:00:36", ssid: "UNII-1", channel: 36, band: .band5, channelWidthMHz: 80, rssi: -72, noise: -95),
                .init(bssid: "50:00:00:00:00:52", ssid: "DFS-52", channel: 52, band: .band5, channelWidthMHz: 80, rssi: -73, noise: -95),
                .init(bssid: "50:00:00:00:00:100", ssid: "DFS-100", channel: 100, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:00:116", ssid: "DFS-116", channel: 116, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:00:132", ssid: "DFS-132", channel: 132, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:00:149", ssid: "UNII-3", channel: 149, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:00:165", ssid: "Edge-165", channel: 165, band: .band5, channelWidthMHz: 20, rssi: -50, noise: -95)
            ]
        )

        XCTAssertEqual(advice[.band5], .recommended(primaryChannel: 36, channelWidthMHz: 80))
    }

    func testFiveGigahertzChoosesDFSWhenNonDFSIsClearlyWorse() async {
        let advisor = ChannelAdvisor()

        let advice = await ingestSeries(
            advisor: advisor,
            observations: [
                .init(bssid: "50:00:00:00:01:36", ssid: "UNII-1", channel: 36, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:01:52", ssid: "DFS-52", channel: 52, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:01:116", ssid: "DFS-116", channel: 116, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:01:132", ssid: "DFS-132", channel: 132, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                .init(bssid: "50:00:00:00:01:149", ssid: "UNII-3", channel: 149, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95)
            ]
        )

        XCTAssertEqual(advice[.band5], .recommended(primaryChannel: 100, channelWidthMHz: 80))
    }

    func testFiveGigahertzNarrowsWidthOnlyWhenThresholdIsMet() async {
        let advisor = ChannelAdvisor()

        let blanketAdvice = await ingestSeries(
            advisor: advisor,
            observations: [
                .init(bssid: "50:00:00:00:10:36", ssid: "C36", channel: 36, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:40", ssid: "C40", channel: 40, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:44", ssid: "C44", channel: 44, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:48", ssid: "C48", channel: 48, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:52", ssid: "C52", channel: 52, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:56", ssid: "C56", channel: 56, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:60", ssid: "C60", channel: 60, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:64", ssid: "C64", channel: 64, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:100", ssid: "C100", channel: 100, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:104", ssid: "C104", channel: 104, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:108", ssid: "C108", channel: 108, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:112", ssid: "C112", channel: 112, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:116", ssid: "C116", channel: 116, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:120", ssid: "C120", channel: 120, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:124", ssid: "C124", channel: 124, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:128", ssid: "C128", channel: 128, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:132", ssid: "C132", channel: 132, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:136", ssid: "C136", channel: 136, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:140", ssid: "C140", channel: 140, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:144", ssid: "C144", channel: 144, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:149", ssid: "C149", channel: 149, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:153", ssid: "C153", channel: 153, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:157", ssid: "C157", channel: 157, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:161", ssid: "C161", channel: 161, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95),
                .init(bssid: "50:00:00:00:10:165", ssid: "C165", channel: 165, band: .band5, channelWidthMHz: 20, rssi: -80, noise: -95)
            ]
        )

        XCTAssertEqual(blanketAdvice[.band5], .recommended(primaryChannel: 36, channelWidthMHz: 80))

        let advisor2 = ChannelAdvisor()
        let narrowedAdvice = await ingestSeries(
            advisor: advisor2,
            observations: [
                .init(bssid: "50:00:00:00:20:48", ssid: "Edge-48", channel: 48, band: .band5, channelWidthMHz: 20, rssi: -55, noise: -95),
                .init(bssid: "50:00:00:00:20:64", ssid: "Edge-64", channel: 64, band: .band5, channelWidthMHz: 20, rssi: -55, noise: -95),
                .init(bssid: "50:00:00:00:20:112", ssid: "Edge-112", channel: 112, band: .band5, channelWidthMHz: 20, rssi: -55, noise: -95),
                .init(bssid: "50:00:00:00:20:128", ssid: "Edge-128", channel: 128, band: .band5, channelWidthMHz: 20, rssi: -55, noise: -95),
                .init(bssid: "50:00:00:00:20:144", ssid: "Edge-144", channel: 144, band: .band5, channelWidthMHz: 20, rssi: -55, noise: -95),
                .init(bssid: "50:00:00:00:20:161", ssid: "Edge-161", channel: 161, band: .band5, channelWidthMHz: 20, rssi: -55, noise: -95)
            ]
        )

        XCTAssertEqual(narrowedAdvice[.band5], .recommended(primaryChannel: 36, channelWidthMHz: 40))
    }

    func testSixGigahertzUsesPSCBasedEightyMegahertzRecommendations() async {
        let advisor = ChannelAdvisor()
        let advice = await ingestSeries(advisor: advisor, observations: [])

        XCTAssertEqual(advice[.band6], .recommended(primaryChannel: 5, channelWidthMHz: 80))
    }

    func testEMASmoothingResistsSingleTransientBeforeFlipping() async {
        let advisor = ChannelAdvisor()

        for step in 0 ..< 3 {
            _ = await advisor.ingest(
                snapshot(
                    observations: [
                        .init(bssid: "50:00:00:00:30:52", ssid: "Busy-52", channel: 52, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:100", ssid: "Busy-100", channel: 100, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:116", ssid: "Busy-116", channel: 116, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:132", ssid: "Busy-132", channel: 132, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:149", ssid: "Busy-149", channel: 149, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:165", ssid: "Busy-165", channel: 165, band: .band5, channelWidthMHz: 20, rssi: -50, noise: -95)
                    ],
                    at: TimeInterval(step * 10)
                )
            )
        }

        var advice = await advisor.ingest(
            snapshot(
                observations: [
                    .init(bssid: "50:00:00:00:30:36", ssid: "Busy-36", channel: 36, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                    .init(bssid: "50:00:00:00:30:52", ssid: "Busy-52", channel: 52, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                    .init(bssid: "50:00:00:00:30:100", ssid: "Busy-100", channel: 100, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                    .init(bssid: "50:00:00:00:30:116", ssid: "Busy-116", channel: 116, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                    .init(bssid: "50:00:00:00:30:132", ssid: "Busy-132", channel: 132, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                    .init(bssid: "50:00:00:00:30:165", ssid: "Busy-165", channel: 165, band: .band5, channelWidthMHz: 20, rssi: -50, noise: -95)
                ],
                at: 30
            )
        )

        XCTAssertEqual(advice[.band5], .recommended(primaryChannel: 36, channelWidthMHz: 80))

        for step in 4 ..< 8 {
            advice = await advisor.ingest(
                snapshot(
                    observations: [
                        .init(bssid: "50:00:00:00:30:36", ssid: "Busy-36", channel: 36, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:52", ssid: "Busy-52", channel: 52, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:100", ssid: "Busy-100", channel: 100, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:116", ssid: "Busy-116", channel: 116, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:132", ssid: "Busy-132", channel: 132, band: .band5, channelWidthMHz: 80, rssi: -50, noise: -95),
                        .init(bssid: "50:00:00:00:30:165", ssid: "Busy-165", channel: 165, band: .band5, channelWidthMHz: 20, rssi: -50, noise: -95)
                    ],
                    at: TimeInterval(step * 10)
                )
            )
        }

        XCTAssertEqual(advice[.band5], .recommended(primaryChannel: 149, channelWidthMHz: 80))
    }

    private func ingestSeries(
        advisor: ChannelAdvisor,
        observations: [WiFiScanObservation],
        count: Int = 3,
        spacing: TimeInterval = 10
    ) async -> [SpectrumBand: BandChannelAdvice] {
        var latestAdvice: [SpectrumBand: BandChannelAdvice] = [:]

        for step in 0 ..< count {
            latestAdvice = await advisor.ingest(snapshot(observations: observations, at: TimeInterval(step) * spacing))
        }

        return latestAdvice
    }

    private func snapshot(observations: [WiFiScanObservation], at seconds: TimeInterval) -> WiFiScanSnapshot {
        WiFiScanSnapshot(
            interface: .init(availableInterfaceNames: ["en0"], selectedInterfaceName: "en0", isPoweredOn: true),
            observations: observations,
            scannedAt: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }
}
