import SwiftUI

struct SpectrumAnalyzerView: View {
    @Environment(SpectrumStore.self) private var store

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            VStack(spacing: 14) {
                ForEach(store.activeBands) { band in
                    BandLaneView(
                        band: band,
                        signals: store.renderedSignals(for: band, at: timeline.date)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: store.activeBands)
        }
    }
}

private struct BandLaneView: View {
    @Environment(SpectrumStore.self) private var store

    let band: SpectrumBand
    let signals: [RenderedSignalEnvelope]

    private var activeChannels: Set<Int> {
        Set(signals.map(\.channel))
    }

    private var labeledChannels: [Int] {
        Array(activeChannels).sorted()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.035),
                                Color.white.opacity(0.018),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }

                Canvas { context, size in
                    drawGrid(into: &context, size: size)
                    drawSignals(into: &context, size: size, date: Date())
                }

                laneHeader
                    .padding(.top, 18)
                    .padding(.leading, 20)

                channelLabels(size: geometry.size)
                signalLabels(size: geometry.size)
            }
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        store.selectSignal(hitTest(in: geometry.size, location: value.location))
                    }
            )
        }
    }

    private var laneHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(band.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
        }
    }

    private func drawGrid(into context: inout GraphicsContext, size: CGSize) {
        let insetRect = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 20)
        let baseline = insetRect.maxY
        let lineColor = Color.white.opacity(0.06)

        for step in 0 ... 4 {
            let y = insetRect.minY + CGFloat(step) * insetRect.height / 4
            var path = Path()
            path.move(to: CGPoint(x: insetRect.minX, y: y))
            path.addLine(to: CGPoint(x: insetRect.maxX, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: step == 4 ? 1.4 : 1)
        }

        let guideCount = 12
        for step in 0 ... guideCount {
            let x = insetRect.minX + CGFloat(step) * insetRect.width / CGFloat(guideCount)
            var path = Path()
            path.move(to: CGPoint(x: x, y: insetRect.minY))
            path.addLine(to: CGPoint(x: x, y: baseline))
            context.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }

        for channel in labeledChannels {
            let isActive = activeChannels.contains(channel)
            let x = insetRect.minX + SpectrumMath.normalizedCenter(channel: channel, band: band) * insetRect.width
            var guidePath = Path()
            guidePath.move(to: CGPoint(x: x, y: insetRect.minY + 22))
            guidePath.addLine(to: CGPoint(x: x, y: baseline - 14))
            context.stroke(
                guidePath,
                with: .color(Color.white.opacity(isActive ? 0.14 : 0.08)),
                style: StrokeStyle(lineWidth: isActive ? 1.2 : 1, dash: isActive ? [3, 6] : [4, 8])
            )
        }
    }

    private func drawSignals(into context: inout GraphicsContext, size: CGSize, date: Date) {
        let insetRect = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 20)
        let baseline = insetRect.maxY

        for signal in signals {
            let centerX = insetRect.minX + signal.centerFraction * insetRect.width
            let totalWidth = max(insetRect.width * signal.widthFraction, 18)
            let amplitude = max(insetRect.height * signal.amplitude * 0.92, 18)
            let phase = date.timeIntervalSinceReferenceDate * (0.6 + signal.shimmer * 1.4)
            let fillPath = signalPath(
                centerX: centerX,
                width: totalWidth,
                baseline: baseline,
                amplitude: amplitude,
                phase: phase,
                shimmer: signal.shimmer
            )
            let ridgePath = ridgeOnlyPath(
                centerX: centerX,
                width: totalWidth,
                baseline: baseline,
                amplitude: amplitude,
                phase: phase,
                shimmer: signal.shimmer
            )

            let colors = palette(for: signal)
            let startPoint = CGPoint(x: centerX, y: baseline - amplitude)
            let endPoint = CGPoint(x: centerX, y: baseline)

            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [
                        colors.core.opacity(signal.bodyOpacity),
                        colors.secondary.opacity(signal.bodyOpacity * 0.82),
                        colors.secondary.opacity(signal.bodyOpacity * 0.22),
                    ]),
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )

            if signal.isOwned {
                context.stroke(
                    ridgePath,
                    with: .color(Color.white.opacity(min(1, signal.bodyOpacity + 0.3))),
                    lineWidth: signal.strokeWidth * 2.2
                )
            }

            context.stroke(
                ridgePath,
                with: .color(colors.core.opacity(min(1, signal.bodyOpacity + 0.28))),
                lineWidth: signal.strokeWidth
            )

            context.stroke(
                ridgePath,
                with: .color(colors.secondary.opacity(signal.haloOpacity)),
                lineWidth: signal.strokeWidth * (signal.isOwned ? 5.2 : 4.2)
            )
        }
    }

    private func signalLabels(size: CGSize) -> some View {
        let insetRect = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 20)
        let visibleLabels = signals.filter { $0.isOwned || $0.bssid == store.selectedBSSID }

        return ForEach(Array(visibleLabels.prefix(12))) { signal in
            let centerX = insetRect.minX + signal.centerFraction * insetRect.width
            let amplitude = max(insetRect.height * signal.amplitude * 0.92, 18)
            let labelY = max(insetRect.minY + 18, insetRect.maxY - amplitude - 16)

            SignalChipView(signal: signal)
                .position(
                    x: min(max(centerX, 96), insetRect.maxX - 96),
                    y: max(labelY, insetRect.minY + 58)
                )
                .onTapGesture {
                    store.selectSignal(signal.bssid)
                }
        }
    }

    private func channelLabels(size: CGSize) -> some View {
        let insetRect = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 20)

        return ForEach(labeledChannels, id: \.self) { channel in
            let xPosition = insetRect.minX + SpectrumMath.normalizedCenter(channel: channel, band: band) * insetRect.width

            ChannelGuideLabel(
                channel: channel,
                isActive: activeChannels.contains(channel)
            )
                .position(
                    x: min(max(xPosition, insetRect.minX + 18), insetRect.maxX - 18),
                    y: insetRect.maxY - 52
                )
                .allowsHitTesting(false)
        }
    }

    private func hitTest(in size: CGSize, location: CGPoint) -> String? {
        let insetRect = CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 20)
        let baseline = insetRect.maxY

        return signals.min { lhs, rhs in
            distance(from: location, to: lhs, rect: insetRect, baseline: baseline)
                < distance(from: location, to: rhs, rect: insetRect, baseline: baseline)
        }
        .flatMap { signal in
            let hitDistance = distance(from: location, to: signal, rect: insetRect, baseline: baseline)
            return hitDistance < 86 ? signal.bssid : nil
        }
    }

    private func distance(
        from point: CGPoint,
        to signal: RenderedSignalEnvelope,
        rect: CGRect,
        baseline: CGFloat
    ) -> CGFloat {
        let centerX = rect.minX + signal.centerFraction * rect.width
        let amplitude = max(rect.height * signal.amplitude * 0.92, 18)
        let peakY = baseline - amplitude
        let deltaX = point.x - centerX
        let deltaY = point.y - peakY
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }

    private func signalPath(
        centerX: CGFloat,
        width: CGFloat,
        baseline: CGFloat,
        amplitude: CGFloat,
        phase: Double,
        shimmer: Double
    ) -> Path {
        var path = Path()
        let startX = centerX - width / 2
        let endX = centerX + width / 2
        path.move(to: CGPoint(x: startX, y: baseline))

        let steps = 28
        for index in 0 ... steps {
            let t = CGFloat(index) / CGFloat(steps)
            let gaussian = exp(-pow((Double(t) - 0.5) / 0.24, 2))
            let wave = 1 + sin((Double(t) * 6 + phase) * .pi * 2) * shimmer * 0.12
            let y = baseline - amplitude * CGFloat(gaussian * wave)
            let x = startX + width * t
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: endX, y: baseline))
        path.closeSubpath()
        return path
    }

    private func ridgeOnlyPath(
        centerX: CGFloat,
        width: CGFloat,
        baseline: CGFloat,
        amplitude: CGFloat,
        phase: Double,
        shimmer: Double
    ) -> Path {
        var path = Path()
        let startX = centerX - width / 2
        let steps = 28

        for index in 0 ... steps {
            let t = CGFloat(index) / CGFloat(steps)
            let gaussian = exp(-pow((Double(t) - 0.5) / 0.24, 2))
            let wave = 1 + sin((Double(t) * 6 + phase) * .pi * 2) * shimmer * 0.12
            let y = baseline - amplitude * CGFloat(gaussian * wave)
            let x = startX + width * t
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private func palette(for signal: RenderedSignalEnvelope) -> (core: Color, secondary: Color) {
        if signal.isOwned {
            return (
                Color(red: 1.0, green: 0.82, blue: 0.14),
                Color(red: 1.0, green: 0.52, blue: 0.12)
            )
        }

        let hue = signal.accentSeed
        return (
            Color(hue: hue, saturation: 0.86, brightness: 1),
            Color(hue: min(hue + 0.08, 1), saturation: 0.74, brightness: 0.82)
        )
    }
}

private struct ChannelGuideLabel: View {
    let channel: Int
    let isActive: Bool

    var body: some View {
        let label = "Ch \(channel)"

        return Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(isActive ? Color.white : Color(red: 0.68, green: 0.7, blue: 0.76))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isActive
                            ? Color(red: 0.08, green: 0.11, blue: 0.18)
                            : Color(red: 0.07, green: 0.08, blue: 0.11)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isActive
                            ? Color(red: 0.34, green: 0.7, blue: 1)
                            : Color(red: 0.27, green: 0.29, blue: 0.35),
                        lineWidth: 1
                    )
            )
            .rotationEffect(.degrees(-90))
    }
}

private struct SignalChipView: View {
    let signal: RenderedSignalEnvelope

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(chipColor)
                .overlay(
                    Circle()
                        .stroke(signal.isOwned ? Color.white.opacity(0.92) : Color.clear, lineWidth: 1.4)
                )
                .frame(width: signal.isOwned ? 12 : 9, height: signal.isOwned ? 12 : 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(signal.displayName)
                    .font(.system(size: 13, weight: signal.isOwned ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                Text("−\(abs(signal.rssi)) dBm · Ch \(signal.channel)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        signal.isOwned
                            ? Color(red: 0.99, green: 0.92, blue: 0.68)
                            : Color(red: 0.78, green: 0.82, blue: 0.9)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(signal.isOwned ? ownedChipBackground : defaultChipBackground)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(signal.isOwned ? chipColor : Color(red: 0.36, green: 0.43, blue: 0.56), lineWidth: signal.isOwned ? 1.8 : 1.2)
        )
        .shadow(color: signal.isOwned ? chipColor.opacity(0.35) : Color.clear, radius: 18, x: 0, y: 8)
    }

    private var chipColor: Color {
        if signal.isOwned {
            return Color(red: 1.0, green: 0.82, blue: 0.14)
        }
        return Color(hue: signal.accentSeed, saturation: 0.86, brightness: 0.95)
    }

    private var defaultChipBackground: Color {
        Color(red: 0.08, green: 0.1, blue: 0.15)
    }

    private var ownedChipBackground: Color {
        Color(red: 0.2, green: 0.16, blue: 0.05)
    }
}
