import SwiftUI

struct ControlRailView: View {
    @Environment(SpectrumStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.mint, .cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Spectrum")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))

                    Text(store.statusLine)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                ForEach(SpectrumBand.allCases) { band in
                    BandChipButton(
                        title: band.title,
                        isOn: store.bandVisibility.contains(band),
                        action: { store.toggleBand(band) }
                    )
                }
            }

            if store.interfaceSnapshot.availableInterfaceNames.count > 1 {
                Menu {
                    ForEach(store.interfaceSnapshot.availableInterfaceNames, id: \.self) { name in
                        Button(name) {
                            store.selectInterface(name)
                        }
                    }
                } label: {
                    Label(store.interfaceSnapshot.selectedInterfaceName ?? "Interface", systemImage: "dot.radiowaves.left.and.right")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.large)
            }

            Button("Clear") {
                store.clearSignals()
            }
            .buttonStyle(.glass)

            Button(store.isInspectorVisible ? "Hide Inspector" : "Inspector") {
                store.isInspectorVisible.toggle()
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 22, x: 0, y: 12)
    }
}

private struct BandChipButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? .white : .white.opacity(0.7))
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

struct OverlayCardView: View {
    @Environment(SpectrumStore.self) private var store

    let state: SpectrumOverlayState

    var body: some View {
        let copy = store.overlayCopy(for: state)

        VStack(alignment: .leading, spacing: 14) {
            Label(copy.title, systemImage: state == .permissionDenied ? "hand.raised.fill" : "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))

            Text(copy.body)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)

            if let action = copy.action {
                Button(action) {
                    switch state {
                    case .permissionRequired:
                        store.performLocationAccessAction()
                    case .permissionDenied:
                        store.performLocationAccessAction()
                    case .wifiOff, .noInterface:
                        break
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(26)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 26, x: 0, y: 14)
    }
}

struct InspectorView: View {
    @Environment(SpectrumStore.self) private var store
    @State private var draftName = ""
    @State private var ownedState = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Inspector")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))

            Text("Tracked radios stay visible until you clear the session. Owned radios stay brighter and easier to follow.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            if let selected = store.inspectorSignals.first(where: { $0.bssid == store.selectedBSSID }) ?? store.inspectorSignals.first {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selected.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))

                    TextField("Friendly name", text: $draftName)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Owned by me", isOn: $ownedState)
                        .toggleStyle(.checkbox)

                    HStack(spacing: 10) {
                        Button("Save Label") {
                            store.saveAnnotation(
                                bssid: selected.bssid,
                                friendlyName: draftName,
                                isOwned: ownedState
                            )
                        }
                        .buttonStyle(.glassProminent)

                        Button("Ask AI for Label") {
                            store.selectSignal(selected.bssid)
                            Task {
                                await store.generateAILabel(for: selected.bssid)
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(!store.canGenerateAILabels || store.isGeneratingAILabel(for: selected.bssid))

                        if store.isGeneratingAILabel(for: selected.bssid) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.9))
                        }
                    }

                    if let message = store.selectedAILabelingMessage {
                        Text(message)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(store.canGenerateAILabels ? .orange.opacity(0.9) : .white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let details = store.selectedAILabelingDebugDetails {
                        Text(details)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .onAppear {
                    syncEditor(with: selected)
                }
                .onChange(of: selected.bssid) { _, _ in
                    syncEditor(with: selected)
                }
                .onChange(of: selected.displayName) { _, _ in
                    syncEditor(with: selected)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(store.inspectorGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .textCase(.uppercase)

                            ForEach(group.signals) { signal in
                                Button {
                                    store.selectSignal(signal.bssid)
                                    syncEditor(with: signal)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Circle()
                                                .fill(signal.isOwned ? Color(red: 1.0, green: 0.82, blue: 0.14) : Color(hue: signal.accentSeed, saturation: 0.86, brightness: 1))
                                                .overlay(
                                                    Circle()
                                                        .stroke(signal.isOwned ? Color.white.opacity(0.94) : Color.clear, lineWidth: 1.3)
                                                )
                                                .frame(width: signal.isOwned ? 11 : 8, height: signal.isOwned ? 11 : 8)
                                            Text(signal.displayName)
                                                .font(.system(size: 14, weight: signal.isOwned ? .bold : .semibold, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.94))
                                            Spacer()
                                            Text("\(signal.rssi) dBm")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.56))
                                        }

                                        Text("\(signal.band.title) · \(signal.bssid)")
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.52))
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(22)
        .background(Color.black.opacity(0.28))
    }

    private func syncEditor(with signal: RenderedSignalEnvelope) {
        draftName = signal.displayName == signal.bssid ? "" : signal.displayName
        ownedState = signal.isOwned
    }
}
