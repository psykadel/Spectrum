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

    func testGhostOpacityClampsToFloor() {
        let opacity = SpectrumMath.ghostDecayOpacity(elapsed: 120)
        XCTAssertEqual(opacity, 0.22, accuracy: 0.0001)
    }

    func testGhostAmplitudeClampsAboveVisibleFloor() {
        let amplitude = SpectrumMath.ghostAmplitude(liveAmplitude: 0.3, elapsed: 120)
        XCTAssertGreaterThanOrEqual(amplitude, 0.24)
    }
}
