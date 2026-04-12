import Foundation

protocol ChannelAdvising {
    func ingest(_ snapshot: WiFiScanSnapshot) async -> [SpectrumBand: BandChannelAdvice]
    func reset() async
}

actor ChannelAdvisor: ChannelAdvising {
    private struct CandidateID: Hashable {
        let band: SpectrumBand
        let primaryChannel: Int
        let channelWidthMHz: Int
    }

    private struct Candidate {
        let id: CandidateID
        let priorityClass: Int
        let classPenalty: Double
        let isDFS: Bool
        let occupiedSpanMHz: ClosedRange<Double>

        var band: SpectrumBand { id.band }
        var primaryChannel: Int { id.primaryChannel }
        var channelWidthMHz: Int { id.channelWidthMHz }
    }

    private struct CandidateScore {
        let candidate: Candidate
        let emaCost: Double

        var effectiveCost: Double {
            emaCost * candidate.classPenalty
        }
    }

    private struct BandState {
        var sampleCount = 0
        var lastSnapshotAt: Date?
        var emaCosts: [CandidateID: Double] = [:]
    }

    private static let halfLife: TimeInterval = 45
    private static let dfsPenalty = 1.18
    private static let adjacentOverlapPenalty = 1.35
    private static var candidateCache: [SpectrumBand: [Candidate]] {
        Dictionary(uniqueKeysWithValues: SpectrumBand.allCases.map { ($0, Self.makeCandidates(for: $0)) })
    }

    private var bandStates: [SpectrumBand: BandState] = Dictionary(
        uniqueKeysWithValues: SpectrumBand.allCases.map { ($0, BandState()) }
    )

    func ingest(_ snapshot: WiFiScanSnapshot) async -> [SpectrumBand: BandChannelAdvice] {
        var adviceByBand: [SpectrumBand: BandChannelAdvice] = [:]

        for band in SpectrumBand.allCases {
            let candidates = Self.candidateCache[band] ?? []
            let observations = snapshot.observations.filter { $0.band == band }
            var state = bandStates[band] ?? BandState()
            let retainedWeight = Self.retainedWeight(since: state.lastSnapshotAt, now: snapshot.scannedAt)

            state.sampleCount += 1
            state.lastSnapshotAt = snapshot.scannedAt

            var scoredCandidates: [CandidateScore] = []
            scoredCandidates.reserveCapacity(candidates.count)

            for candidate in candidates {
                let instantCost = Self.instantaneousCost(for: candidate, observations: observations)
                let emaCost: Double
                if let prior = state.emaCosts[candidate.id] {
                    emaCost = prior * retainedWeight + instantCost * (1 - retainedWeight)
                } else {
                    emaCost = instantCost
                }

                state.emaCosts[candidate.id] = emaCost
                scoredCandidates.append(CandidateScore(candidate: candidate, emaCost: emaCost))
            }

            bandStates[band] = state
            adviceByBand[band] = Self.recommendation(
                for: band,
                scoredCandidates: scoredCandidates,
                sampleCount: state.sampleCount
            )
        }

        return adviceByBand
    }

    func reset() async {
        bandStates = Dictionary(uniqueKeysWithValues: SpectrumBand.allCases.map { ($0, BandState()) })
    }

    private static func recommendation(
        for band: SpectrumBand,
        scoredCandidates: [CandidateScore],
        sampleCount: Int
    ) -> BandChannelAdvice {
        guard sampleCount >= 3 else {
            return .scanning
        }

        switch band {
        case .band2_4:
            return recommendTwoPointFour(scoredCandidates)
        case .band5:
            return recommendFiveGigahertz(scoredCandidates)
        case .band6:
            return recommendSixGigahertz(scoredCandidates)
        }
    }

    private static func recommendTwoPointFour(_ scoredCandidates: [CandidateScore]) -> BandChannelAdvice {
        let preferred = scoredCandidates.filter { [1, 6, 11].contains($0.candidate.primaryChannel) }
        guard
            let bestPreferred = lowestCostCandidate(from: preferred),
            let bestOverall = lowestCostCandidate(from: scoredCandidates)
        else {
            return .scanning
        }

        let winner: CandidateScore
        if [1, 6, 11].contains(bestOverall.candidate.primaryChannel) {
            winner = bestPreferred
        } else if bestPreferred.emaCost > 0, bestOverall.emaCost <= bestPreferred.emaCost * 0.8 {
            winner = bestOverall
        } else {
            winner = bestPreferred
        }

        return .recommended(
            primaryChannel: winner.candidate.primaryChannel,
            channelWidthMHz: winner.candidate.channelWidthMHz
        )
    }

    private static func recommendFiveGigahertz(_ scoredCandidates: [CandidateScore]) -> BandChannelAdvice {
        let widthOrder = [80, 40, 20]
        var bestByWidth: [Int: CandidateScore] = [:]

        for width in widthOrder {
            let candidates = scoredCandidates.filter { $0.candidate.channelWidthMHz == width }
            guard !candidates.isEmpty else { continue }

            let nonDFS = bestCandidate(from: candidates.filter { !$0.candidate.isDFS })
            let dfs = bestCandidate(from: candidates.filter { $0.candidate.isDFS })

            let widthWinner: CandidateScore?
            switch (nonDFS, dfs) {
            case let (nonDFS?, dfs?):
                if nonDFS.effectiveCost > 0, dfs.effectiveCost <= nonDFS.effectiveCost * 0.85 {
                    widthWinner = dfs
                } else {
                    widthWinner = nonDFS
                }
            case let (nonDFS?, nil):
                widthWinner = nonDFS
            case let (nil, dfs?):
                widthWinner = dfs
            case (nil, nil):
                widthWinner = nil
            }

            if let widthWinner {
                bestByWidth[width] = widthWinner
            }
        }

        guard var winner = bestByWidth[80] ?? bestByWidth[40] ?? bestByWidth[20] else {
            return .scanning
        }

        for width in [40, 20] {
            guard
                width < winner.candidate.channelWidthMHz,
                let narrower = bestByWidth[width]
            else {
                continue
            }

            if winner.effectiveCost > 0, narrower.effectiveCost <= winner.effectiveCost * 0.85 {
                winner = narrower
            }
        }

        return .recommended(
            primaryChannel: winner.candidate.primaryChannel,
            channelWidthMHz: winner.candidate.channelWidthMHz
        )
    }

    private static func recommendSixGigahertz(_ scoredCandidates: [CandidateScore]) -> BandChannelAdvice {
        guard let winner = bestCandidate(from: scoredCandidates) else {
            return .scanning
        }

        return .recommended(
            primaryChannel: winner.candidate.primaryChannel,
            channelWidthMHz: winner.candidate.channelWidthMHz
        )
    }

    private static func bestCandidate(from candidates: [CandidateScore]) -> CandidateScore? {
        candidates.min {
            if $0.candidate.priorityClass != $1.candidate.priorityClass {
                return $0.candidate.priorityClass < $1.candidate.priorityClass
            }
            if $0.effectiveCost != $1.effectiveCost {
                return $0.effectiveCost < $1.effectiveCost
            }
            return $0.candidate.primaryChannel < $1.candidate.primaryChannel
        }
    }

    private static func lowestCostCandidate(from candidates: [CandidateScore]) -> CandidateScore? {
        candidates.min {
            if $0.effectiveCost != $1.effectiveCost {
                return $0.effectiveCost < $1.effectiveCost
            }
            return $0.candidate.primaryChannel < $1.candidate.primaryChannel
        }
    }

    private static func retainedWeight(since prior: Date?, now: Date) -> Double {
        guard let prior else { return 0 }
        let elapsed = max(now.timeIntervalSince(prior), 0)
        guard elapsed > 0 else { return 0 }
        return pow(0.5, elapsed / halfLife)
    }

    private static func instantaneousCost(for candidate: Candidate, observations: [WiFiScanObservation]) -> Double {
        observations.reduce(0) { partial, observation in
            let observationSpan = occupiedSpan(for: observation)
            let overlap = overlapFraction(candidate.occupiedSpanMHz, observationSpan)
            guard overlap > 0 else { return partial }

            let baseCost = overlap * signalWeight(forRSSI: observation.rssi)
            let adjustedCost: Double

            if candidate.band == .band2_4, observation.channel != candidate.primaryChannel {
                adjustedCost = baseCost * adjacentOverlapPenalty
            } else {
                adjustedCost = baseCost
            }

            return partial + adjustedCost
        }
    }

    private static func overlapFraction(_ lhs: ClosedRange<Double>, _ rhs: ClosedRange<Double>) -> Double {
        let overlap = min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound)
        guard overlap > 0 else { return 0 }
        let candidateWidth = lhs.upperBound - lhs.lowerBound
        guard candidateWidth > 0 else { return 0 }
        return overlap / candidateWidth
    }

    private static func signalWeight(forRSSI rssi: Int) -> Double {
        let normalized = min(max(Double(rssi + 92) / 55, 0), 1)
        return pow(normalized, 2)
    }

    private static func occupiedSpan(for observation: WiFiScanObservation) -> ClosedRange<Double> {
        occupiedSpan(
            primaryChannel: observation.channel,
            band: observation.band,
            channelWidthMHz: observation.channelWidthMHz,
            fallbackToCenteredWidth: true
        )
    }

    private static func occupiedSpan(
        primaryChannel: Int,
        band: SpectrumBand,
        channelWidthMHz: Int,
        fallbackToCenteredWidth: Bool
    ) -> ClosedRange<Double> {
        if channelWidthMHz <= 20 {
            let center = SpectrumMath.centerFrequencyMHz(channel: primaryChannel, band: band)
            let occupiedWidth = SpectrumMath.occupiedChannelWidthMHz(channelWidthMHz: channelWidthMHz, band: band)
            return (center - occupiedWidth / 2) ... (center + occupiedWidth / 2)
        }

        if let standardSpan = standardOccupiedSpan(
            primaryChannel: primaryChannel,
            band: band,
            channelWidthMHz: channelWidthMHz
        ) {
            return standardSpan
        }

        if fallbackToCenteredWidth {
            let center = SpectrumMath.centerFrequencyMHz(channel: primaryChannel, band: band)
            let occupiedWidth = SpectrumMath.occupiedChannelWidthMHz(channelWidthMHz: channelWidthMHz, band: band)
            return (center - occupiedWidth / 2) ... (center + occupiedWidth / 2)
        }

        let center = SpectrumMath.centerFrequencyMHz(channel: primaryChannel, band: band)
        return center ... center
    }

    private static func standardOccupiedSpan(
        primaryChannel: Int,
        band: SpectrumBand,
        channelWidthMHz: Int
    ) -> ClosedRange<Double>? {
        guard channelWidthMHz > 20 else { return nil }

        let blocks = channelBlocks(for: band, channelWidthMHz: channelWidthMHz)
        guard let block = blocks.first(where: { $0.contains(primaryChannel) }) else {
            return nil
        }

        let lowEdge = SpectrumMath.centerFrequencyMHz(channel: block[0], band: band) - 10
        let highEdge = SpectrumMath.centerFrequencyMHz(channel: block[block.count - 1], band: band) + 10
        return lowEdge ... highEdge
    }

    private static func makeCandidates(for band: SpectrumBand) -> [Candidate] {
        switch band {
        case .band2_4:
            return (1 ... 11).compactMap { primaryChannel in
                makeCandidate(
                    band: band,
                    primaryChannel: primaryChannel,
                    channelWidthMHz: 20,
                    priorityClass: [1, 6, 11].contains(primaryChannel) ? 0 : 1,
                    classPenalty: 1,
                    isDFS: false
                )
            }
        case .band5:
            let widths = [20, 40, 80]
            let channels = validTwentyMegahertzChannels(for: band)
            return widths.flatMap { width in
                channels.compactMap { primaryChannel in
                    guard width == 20 || primaryChannel != 165 else {
                        return nil
                    }
                    guard isValidPrimaryChannel(primaryChannel, band: band, channelWidthMHz: width) else {
                        return nil
                    }
                    let isDFS = (52 ... 144).contains(primaryChannel)
                    return makeCandidate(
                        band: band,
                        primaryChannel: primaryChannel,
                        channelWidthMHz: width,
                        priorityClass: isDFS ? 1 : 0,
                        classPenalty: isDFS ? dfsPenalty : 1,
                        isDFS: isDFS
                    )
                }
            }
        case .band6:
            return sixGigahertzPSCChannels.compactMap { primaryChannel in
                guard isValidPrimaryChannel(primaryChannel, band: band, channelWidthMHz: 80) else {
                    return nil
                }
                return makeCandidate(
                    band: band,
                    primaryChannel: primaryChannel,
                    channelWidthMHz: 80,
                    priorityClass: 0,
                    classPenalty: 1,
                    isDFS: false
                )
            }
        }
    }

    private static func makeCandidate(
        band: SpectrumBand,
        primaryChannel: Int,
        channelWidthMHz: Int,
        priorityClass: Int,
        classPenalty: Double,
        isDFS: Bool
    ) -> Candidate? {
        let occupiedSpan = occupiedSpan(
            primaryChannel: primaryChannel,
            band: band,
            channelWidthMHz: channelWidthMHz,
            fallbackToCenteredWidth: false
        )
        guard
            occupiedSpan.lowerBound >= band.frequencyRangeMHz.lowerBound,
            occupiedSpan.upperBound <= band.frequencyRangeMHz.upperBound
        else {
            return nil
        }

        return Candidate(
            id: CandidateID(band: band, primaryChannel: primaryChannel, channelWidthMHz: channelWidthMHz),
            priorityClass: priorityClass,
            classPenalty: classPenalty,
            isDFS: isDFS,
            occupiedSpanMHz: occupiedSpan
        )
    }

    private static func isValidPrimaryChannel(_ primaryChannel: Int, band: SpectrumBand, channelWidthMHz: Int) -> Bool {
        switch channelWidthMHz {
        case 20:
            return validTwentyMegahertzChannels(for: band).contains(primaryChannel)
        default:
            return channelBlocks(for: band, channelWidthMHz: channelWidthMHz).contains { $0.contains(primaryChannel) }
        }
    }

    private static func validTwentyMegahertzChannels(for band: SpectrumBand) -> [Int] {
        switch band {
        case .band2_4:
            Array(1 ... 11)
        case .band5:
            [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165]
        case .band6:
            Array(stride(from: 1, through: 233, by: 4))
        }
    }

    private static func channelBlocks(for band: SpectrumBand, channelWidthMHz: Int) -> [[Int]] {
        switch (band, channelWidthMHz) {
        case (.band5, 40):
            return [36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157].map { makeBlock(startingAt: $0, count: 2) }
        case (.band5, 80):
            return [36, 52, 100, 116, 132, 149].map { makeBlock(startingAt: $0, count: 4) }
        case (.band5, 160):
            return [36, 100].map { makeBlock(startingAt: $0, count: 8) }
        case (.band6, 40):
            return Array(stride(from: 1, through: 225, by: 8)).map { makeBlock(startingAt: $0, count: 2) }
        case (.band6, 80):
            return Array(stride(from: 1, through: 209, by: 16)).map { makeBlock(startingAt: $0, count: 4) }
        case (.band6, 160):
            return Array(stride(from: 1, through: 193, by: 32)).map { makeBlock(startingAt: $0, count: 8) }
        default:
            return []
        }
    }

    private static func makeBlock(startingAt start: Int, count: Int) -> [Int] {
        (0 ..< count).map { start + ($0 * 4) }
    }

    private static let sixGigahertzPSCChannels = [5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229]
}
