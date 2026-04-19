import XCTest
@testable import Spectrum

final class SpectrumMathTests: XCTestCase {
    func testOrderedBandsMatchVisibility() {
        let visibility: BandVisibility = [.band2_4, .band6]
        XCTAssertEqual(SpectrumMath.orderedBands(for: visibility), [.band2_4, .band6])
    }

    func testChannelWidthMappingGrowsEnvelopeWidth() {
        let width20 = SpectrumMath.normalizedWidth(channelWidthMHz: 20, band: .band5)
        let width80 = SpectrumMath.normalizedWidth(channelWidthMHz: 80, band: .band5)
        XCTAssertGreaterThan(width80, width20)
    }

    func testTwoPointFourChannelSixUsesRealFrequencyPlacement() {
        let center = SpectrumMath.normalizedCenter(channel: 6, band: .band2_4)
        XCTAssertEqual(center, 35.0 / 78.0, accuracy: 0.0001)
    }

    func testBandsExposeMajorChannelsForGuideLabels() {
        XCTAssertEqual(SpectrumBand.band2_4.majorChannels, [1, 6, 11])
        XCTAssertEqual(SpectrumBand.band5.majorChannels, [36, 52, 100, 149, 165])
        XCTAssertEqual(SpectrumBand.band6.majorChannels, [1, 33, 65, 97, 129, 161, 193, 225])
    }

    func testTwoPointFourWidthUsesRealOccupiedBandwidth() {
        let width = SpectrumMath.normalizedWidth(channelWidthMHz: 20, band: .band2_4)
        XCTAssertEqual(width, 22.0 / 78.0, accuracy: 0.0001)
    }

    func testTwoPointFourTwentyMegahertzAppearsWiderThanFiveGigahertz() {
        let width24 = SpectrumMath.normalizedWidth(channelWidthMHz: 20, band: .band2_4)
        let width5 = SpectrumMath.normalizedWidth(channelWidthMHz: 20, band: .band5)
        XCTAssertGreaterThan(width24, width5)
    }

    func testGhostOpacityClampsToFloor() {
        let opacity = SpectrumMath.ghostDecayOpacity(elapsed: 120)
        XCTAssertEqual(opacity, 0.22, accuracy: 0.0001)
    }

    func testGhostAmplitudeClampsAboveVisibleFloor() {
        let amplitude = SpectrumMath.ghostAmplitude(liveAmplitude: 0.3, elapsed: 120)
        XCTAssertGreaterThanOrEqual(amplitude, 0.24)
    }

    func testZigbeeChannelsParseAndDeduplicate() {
        let result = SpectrumMath.parseZigbeeChannels(from: "11, 15 15 20 foo 27")

        XCTAssertEqual(result.channels, [11, 15, 20])
        XCTAssertEqual(result.invalidTokens, ["foo", "27"])
    }

    func testZigbeeChannelTwentySixStaysWithinTwoPointFourLane() throws {
        let frequency = try XCTUnwrap(SpectrumMath.zigbeeCenterFrequencyMHz(channel: 26))
        let position = SpectrumMath.normalizedCenter(frequencyMHz: frequency, band: .band2_4)

        XCTAssertEqual(position, 1, accuracy: 0.0001)
    }

    func testZigbeeRenderedWidthUsesActualTwoMegahertzOccupancy() {
        let width = SpectrumMath.normalizedWidth(occupiedWidthMHz: 2, band: .band2_4)

        XCTAssertEqual(width, 2.0 / 78.0, accuracy: 0.0001)
    }
}
