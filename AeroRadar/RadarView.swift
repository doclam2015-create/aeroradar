import SwiftUI
import MapKit

struct RadarView: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    @Environment(LocationProvider.self) private var location
    @Environment(\.horizontalSizeClass) private var hsize

    @State private var position: MapCameraPosition = .automatic
    @State private var cameraDistance: Double = 600_000
    @State private var showSearch = false
    @State private var showFilters = false
    @State private var showOverhead = false
    @State private var showDetail = false
    @State private var didSetInitial = false

    var body: some View {
        @Bindable var radar = radar
        ZStack(alignment: .top) {
            map
            VStack(spacing: 8) {
                topBar
                if let e = radar.errorText { pill(e, icon: "wifi.exclamationmark", color: .red) }
                emergencyBanner
                Spacer()
                if let a = radar.selected, !showDetail || hsize != .compact {
                    if hsize == .compact {
                        CompactCard(aircraft: a) { showDetail = true }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
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
        .sheet(isPresented: $showSearch) { SearchView { a, coord in
            showSearch = false
            if let coord { fly(to: coord, distance: 400_000) }
            if let a { radar.select(a); showDetail = true; fly(to: a.coordinate, distance: 300_000) }
        } }
        .sheet(isPresented: $showFilters) { FiltersView() }
        .sheet(isPresented: $showOverhead) { OverheadView { a in
            showOverhead = false; radar.select(a); showDetail = true
        } }
        .onChange(of: radar.selectedHex) { _, h in if h != nil && hsize != .compact { showDetail = true } }
        .onChange(of: radar.tick) { _, _ in followIfNeeded() }
        .onAppear {
            guard !didSetInitial else { return }
            didSetInitial = true
            position = .region(MKCoordinateRegion(center: radar.center, span: radar.span))
        }
        .preferredColorScheme(prefs.forceDark ? .dark : nil)
    }

    // MARK: Mapa

    private var map: some View {
        Map(position: $position) {
            if prefs.showTerminator {
                ForEach(Array(Terminator.nightPolygons(at: radar.tick).enumerated()), id: \.offset) { _, poly in
                    MapPolygon(coordinates: poly).foregroundStyle(.black.opacity(0.28))
                }
            }
            if prefs.showAirports && radar.span.latitudeDelta < 14 {
                ForEach(AirportDB.inRegion(center: radar.center, latDelta: radar.span.latitudeDelta,
                                           lonDelta: radar.span.longitudeDelta, largeOnly: radar.span.latitudeDelta > 4)) { ap in
                    Annotation(ap.iata, coordinate: ap.coordinate, anchor: .center) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: ap.large ? 13 : 10))
                            .foregroundStyle(.white, .indigo.opacity(0.85))
                    }
                    .annotationTitles(radar.span.latitudeDelta < 6 ? .automatic : .hidden)
                }
            }
            if prefs.showTrails && radar.span.latitudeDelta < 5 {
                ForEach(radar.visible.filter { $0.hex != radar.selectedHex }) { a in
                    if let t = radar.trails[a.hex], t.count > 1 {
                        MapPolyline(coordinates: t.map(\.coordinate) + [radar.position(of: a)])
                            .stroke(altitudeColor(a.altitude, onGround: a.onGround).opacity(0.45), lineWidth: 1.5)
                    }
                }
            }
            if let a = radar.selected {
                let trail = radar.fullTrail(for: a.hex)
                if trail.count > 1 {
                    MapPolyline(coordinates: trail.map(\.coordinate) + [radar.position(of: a)])
                        .stroke(Gradient(colors: trail.map { altitudeColor($0.alt, onGround: $0.alt == 0) }),
                                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
                if let r = radar.selectedRoute {
                    MapPolyline(coordinates: Geo.greatCircle(radar.position(of: a), r.destination.coordinate))
                        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    Annotation(r.origin.code, coordinate: r.origin.coordinate) { routeDot(.green) }
                    Annotation(r.destination.code, coordinate: r.destination.coordinate) { routeDot(.orange) }
                }
            }
            ForEach(radar.visible) { a in
                Annotation(a.displayName, coordinate: radar.position(of: a), anchor: .center) {
                    PlaneMarker(aircraft: a, selected: a.hex == radar.selectedHex, mapHeading: radar.mapHeading,
                                showLabel: a.hex == radar.selectedHex || (prefs.showLabels && (radar.span.latitudeDelta < 0.8 || (radar.span.latitudeDelta < 3 && radar.visible.count < 60))),
                                watched: radar.isWatched(a))
                        .onTapGesture { radar.select(a) ; if hsize == .compact { showDetail = false } }
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(prefs.mapStyle)
        .safeAreaPadding(.top, 64)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
            MapUserLocationButton()
            #if os(macOS)
            MapZoomStepper()
            #endif
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            cameraDistance = ctx.camera.distance
            radar.updateRegion(ctx.region, heading: ctx.camera.heading)
        }
    }

    private func routeDot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 3)
    }

    private func fly(to c: CLLocationCoordinate2D, distance: Double) {
        withAnimation(.easeInOut(duration: 1.2)) {
            position = .camera(MapCamera(centerCoordinate: c, distance: distance))
        }
    }

    private func followIfNeeded() {
        guard radar.follow, let a = radar.selected else { return }
        let c = radar.position(of: a)
        if radar.cockpit {
            position = .camera(MapCamera(centerCoordinate: Geo.destination(from: c, bearing: a.track ?? 0, km: 3),
                                         distance: 9000, heading: a.track ?? 0, pitch: 72))
        } else {
            position = .camera(MapCamera(centerCoordinate: c, distance: min(cameraDistance, 1_500_000)))
        }
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
            Text("\(radar.visible.count) aeronaves")
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

// MARK: - Marcador de avión

struct PlaneMarker: View {
    let aircraft: Aircraft
    let selected: Bool
    let mapHeading: Double
    let showLabel: Bool
    let watched: Bool
    @State private var pulse = false

    var body: some View {
        let color = aircraft.isEmergency ? Color.red : altitudeColor(aircraft.altitude, onGround: aircraft.onGround)
        ZStack {
            if selected || aircraft.isEmergency {
                Circle()
                    .stroke(aircraft.isEmergency ? .red : .white, lineWidth: 2)
                    .frame(width: aircraft.sizeClass * 2.1, height: aircraft.sizeClass * 2.1)
                    .scaleEffect(pulse ? 1.25 : 0.9)
                    .opacity(pulse ? 0.2 : 0.9)
                    .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true } }
            }
            Image(systemName: aircraft.isHelicopter ? "fanblades.fill" : "airplane")
                .font(.system(size: aircraft.sizeClass * (selected ? 1.3 : 1), weight: .bold))
                .foregroundStyle(selected ? .white : color)
                .shadow(color: .black.opacity(0.65), radius: 1.5, x: 0, y: 1)
                .rotationEffect(.degrees((aircraft.track ?? 0) - mapHeading - (aircraft.isHelicopter ? 0 : 90)))
            if watched {
                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow).offset(x: 12, y: -12)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showLabel {
                Text(aircraft.displayName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(selected ? Color.orange : .black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .offset(y: 14)
            }
        }
        .accessibilityLabel("\(aircraft.displayName), \(aircraft.typeDesc ?? "")")
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
