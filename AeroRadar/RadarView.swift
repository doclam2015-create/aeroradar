import SwiftUI
import MapKit

struct RadarView: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    @Environment(LocationProvider.self) private var location
    @Environment(\.horizontalSizeClass) private var hsize

    @State private var showSearch = false
    @State private var showFilters = false
    @State private var showOverhead = false
    @State private var showDetail = false

    var body: some View {
        @Bindable var radar = radar
        ZStack(alignment: .top) {
            map
            VStack(spacing: 8) {
                topBar
                if let e = radar.errorText { pill(e, icon: "wifi.exclamationmark", color: .red) }
                emergencyBanner
                Spacer()
                if let a = radar.selected, !radar.cockpit, !showDetail || hsize != .compact {
                    if hsize == .compact {
                        CompactCard(aircraft: a) { showDetail = true }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if radar.cockpit, let a = radar.selected { cockpitHUD(a) }
                legend
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .animation(.spring(duration: 0.35), value: radar.selectedHex)
        .inspector(isPresented: Binding(get: { showDetail && radar.selected != nil }, set: { showDetail = $0 })) {
            if let a = radar.selected {
                AircraftDetailView(aircraft: a, close: { showDetail = false; radar.select(nil) })
                    .presentationDetents([.medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .inspectorColumnWidth(min: 340, ideal: 380, max: 460)
            }
        }
        .sheet(isPresented: $showSearch) { SearchView { a, region in
            showSearch = false
            if let region {
                radar.follow = false; radar.cockpit = false
                radar.cameraRequest = CameraRequest(region: region)
            }
            if let a { radar.select(a); showDetail = true; fly(to: a.coordinate, distance: 300_000) }
        } }
        .sheet(isPresented: $showFilters) { FiltersView() }
        .sheet(isPresented: $showOverhead) { OverheadView { a in
            showOverhead = false; radar.select(a); showDetail = true
        } }
        .onChange(of: radar.selectedHex) { _, h in if h != nil && hsize != .compact { showDetail = true } }
        .onChange(of: radar.cockpit) { _, on in
            if on {
                if hsize == .compact { showDetail = false }
            } else if let a = radar.selected {
                fly(to: a.coordinate, distance: 250_000)
            }
        }
        .preferredColorScheme(prefs.forceDark ? .dark : nil)
    }

    // MARK: Mapa

    private var map: some View {
        RadarMapView(radar: radar, prefs: prefs)
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) { hoverOverlay }
    }

    /// Tarjeta flotante al pasar el puntero (Mac / iPad con trackpad)
    @ViewBuilder private var hoverOverlay: some View {
        if let h = radar.hovered, h.hex != radar.selectedHex {
            GeometryReader { g in
                let p = radar.hoverPoint
                let x = min(max(p.x - 182, 8), g.size.width - 372)
                let y = p.y > 470 ? p.y - 460 : p.y + 30
                HoverCard(aircraft: h)
                    .offset(x: x, y: y)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private func fly(to c: CLLocationCoordinate2D, distance: Double) {
        radar.cameraRequest = CameraRequest(center: c, distance: distance)
    }

    // MARK: Barras

    private var topBar: some View {
        @Bindable var radar = radar
        return HStack(spacing: 6) {
            Button { showSearch = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(hsize == .compact ? "Buscar" : "Vuelo, matrícula o aeropuerto").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).frame(height: 40)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f")

            Menu {
                Picker("Modo", selection: $radar.mode) {
                    ForEach(RadarMode.allCases) { m in Label(m.label, systemImage: m.icon).tag(m) }
                }
            } label: {
                circleIcon(radar.mode.icon, active: radar.mode != .area)
            }
            .menuStyle(.button).buttonStyle(.plain)

            Button { showFilters = true } label: {
                circleIcon("line.3.horizontal.decrease", active: radar.filters.isActive)
            }.buttonStyle(.plain)

            Button { showOverhead = true } label: { circleIcon("binoculars.fill", active: false) }
                .buttonStyle(.plain)
                .help("¿Qué vuela sobre mí?")

            Menu {
                Toggle("Etiquetas", isOn: Bindable(prefs).showLabels)
                Toggle("Aeropuertos", isOn: Bindable(prefs).showAirports)
                Toggle("Estelas", isOn: Bindable(prefs).showTrails)
                Toggle("Día y noche", isOn: Bindable(prefs).showTerminator)
                Picker("Mapa", selection: Bindable(prefs).mapLook) {
                    ForEach(MapLook.allCases) { Text($0.label).tag($0) }
                }
            } label: { circleIcon("square.3.layers.3d", active: false) }
            .menuStyle(.button).buttonStyle(.plain)
        }
        .padding(.top, 6)
        .overlay(alignment: .bottomLeading) {
            statusPill.offset(y: 34)
        }
        .padding(.bottom, 30)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(radar.errorText == nil ? .green : .red).frame(width: 7, height: 7)
                .opacity(radar.isLoading ? 0.3 : 1)
            Text(radar.visible.count == 1 ? "1 aeronave" : "\(radar.visible.count) aeronaves")
            if radar.mode != .area { Text("· \(radar.mode.label)") }
            if radar.filters.isActive { Text("· filtrado") }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder private var emergencyBanner: some View {
        let em = radar.aircraft.values.filter(\.isEmergency)
        if let a = em.first {
            Button { radar.select(a); showDetail = true; fly(to: a.coordinate, distance: 300_000) } label: {
                pill("\(a.displayName): \(a.emergencyLabel ?? "Emergencia")\(em.count > 1 ? " (+\(em.count - 1))" : "")",
                     icon: "exclamationmark.triangle.fill", color: .red)
            }.buttonStyle(.plain)
        }
    }

    private func cockpitHUD(_ a: Aircraft) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "cube.transparent").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 0) {
                Text("Vista 3D · \(a.displayName)").font(.headline)
                Text("\(prefs.altitude(a.altitude, ground: a.onGround)) · \(prefs.speed(a.groundSpeed)) · \(Int(a.track ?? 0))° \(Geo.compass(a.track ?? 0))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Salir") { radar.cockpit = false; radar.follow = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 520)
    }

    private var legend: some View {
        HStack(spacing: 0) {
            ForEach([0, 5000, 10000, 20000, 30000, 40000], id: \.self) { ft in
                Text(ft == 0 ? "0" : "\(ft / 1000)k")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .frame(width: 30, height: 14)
                    .background(altitudeColor(ft))
                    .foregroundStyle(.black.opacity(0.75))
            }
        }
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .trailing)
        .opacity(0.9)
    }

    private func circleIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 40, height: 40)
            .foregroundStyle(active ? .white : .primary)
            .background(active ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.regularMaterial), in: Circle())
    }

    private func pill(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color.gradient, in: Capsule())
            .foregroundStyle(.white)
    }
}

// MARK: - Tarjeta compacta (iPhone)

struct CompactCard: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    let aircraft: Aircraft
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aircraft.displayName).font(.title3.bold())
                        Text(radar.selectedRoute?.airlineName ?? aircraft.owner ?? aircraft.typeDesc ?? "—")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let r = radar.selectedRoute {
                        Text("\(r.origin.code) → \(r.destination.code)").font(.headline.monospaced())
                    }
                    Button { radar.select(nil) } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
                HStack {
                    stat("Altitud", prefs.altitude(aircraft.altitude, ground: aircraft.onGround))
                    stat("Velocidad", prefs.speed(aircraft.groundSpeed))
                    stat("Tipo", aircraft.typeCode ?? "—")
                    stat("Matrícula", aircraft.registration ?? "—")
                }
                Label("Toca para ver detalles", systemImage: "chevron.up").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }
}
