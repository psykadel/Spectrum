import SwiftUI

struct SpectrumRootView: View {
    @Environment(SpectrumStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .top) {
                SpectralBackdropView()

                SpectrumAnalyzerView()
                    .padding(.horizontal, 28)
                    .padding(.top, 126)
                    .padding(.bottom, 24)

                ControlRailView()
                    .padding(.top, 18)
                    .padding(.horizontal, 18)

                if let overlayState = store.overlayState {
                    OverlayCardView(state: overlayState)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 28)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                EmptyView()
            }

            if store.isInspectorVisible {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                InspectorView()
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: store.isInspectorVisible)
        .background(Color.black)
        .onAppear {
            store.setSceneFocused(scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, newValue in
            store.setSceneFocused(newValue == .active)
        }
        .ignoresSafeArea()
    }
}

private struct SpectralBackdropView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.08),
                    Color(red: 0.03, green: 0.05, blue: 0.11),
                    Color(red: 0.01, green: 0.02, blue: 0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.08, green: 0.16, blue: 0.26).opacity(0.55),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 60,
                endRadius: 540
            )

            RadialGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.18).opacity(0.45),
                    Color.clear,
                ],
                center: .bottomTrailing,
                startRadius: 60,
                endRadius: 620
            )
        }
        .overlay {
            GeometryReader { geometry in
                Canvas { context, size in
                    let spacing: CGFloat = 72
                    let lineColor = Color.white.opacity(0.035)
                    for x in stride(from: 0, through: size.width, by: spacing) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(lineColor), lineWidth: 1)
                    }

                    for y in stride(from: 0, through: size.height, by: spacing) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(lineColor), lineWidth: 1)
                    }

                    let border = Path(CGRect(origin: .zero, size: geometry.size))
                    context.stroke(border, with: .color(.white.opacity(0.05)), lineWidth: 1)
                }
            }
        }
    }
}
