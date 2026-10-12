import SwiftUI
import CoreLocation
import MapKit

// MARK: - Búsqueda

struct SearchView: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    let pick: (Aircraft?, MKCoordinateRegion?) -> Void
    @State private var places: [MKMapItem] = []
    @State private var text = ""
    @State private var remote: [Aircraft] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    private var local: [Aircraft] {
        let q = text.uppercased()
        guard q.count >= 2 else { return [] }
        return radar.aircraft.values.filter {
            [$0.callsign, $0.registration, $0.hex.uppercased(), $0.typeCode].compactMap { $0?.uppercased() }.contains { $0.contains(q) }
        }.prefix(30).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if text.count < 2 {
                    Section {
                        Label("Busca un vuelo (LA800), matrícula (CC-BGA), aeropuerto (SCL) o lugar: país, ciudad, continente o «todo el mundo».", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !radar.watchlist.isEmpty {
                        Section("Vigilados") {
                            ForEach(radar.watchlist) { w in
                                Button { text = w.query; Task { await searchRemote() } } label: { Label(w.query, systemImage: "star.fill") }
                            }
                        }
                    }
                }
                let regions = NamedRegion.matching(text)
                if !regions.isEmpty || !places.isEmpty {
                    Section("Lugares") {
                        ForEach(regions) { r in
                            Button { pick(nil, MKCoordinateRegion(center: .init(latitude: r.lat, longitude: r.lon),
                                                                  span: .init(latitudeDelta: r.latSpan, longitudeDelta: r.lonSpan))) } label: {
                                Label(r.name, systemImage: r.name == "Todo el mundo" ? "globe" : "globe.americas.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        ForEach(places, id: \.self) { item in
                            Button { pick(nil, region(for: item)) } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(item.name ?? "")
                                        Text(subtitle(item)).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: "mappin.circle.fill").foregroundStyle(.red) }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !local.isEmpty {
                    Section("En el mapa") { ForEach(local) { aircraftRow($0) } }
                }
                let rem = remote.filter { r in !local.contains { $0.hex == r.hex } }
                if !rem.isEmpty {
                    Section("En el mundo") { ForEach(rem) { aircraftRow($0) } }
                }
                if text.count >= 2 && !searching && remote.isEmpty && local.isEmpty {
                    Section {
                        Button { Task { await searchRemote() } } label: { Label("Buscar \"\(text.uppercased())\" en todo el mundo", systemImage: "globe") }
                    }
                }
                if searching { HStack { ProgressView(); Text("Buscando en la red ADS-B…") } }
                let aps = AirportDB.search(text)
                if !aps.isEmpty {
                    Section("Aeropuertos") {
                        ForEach(aps.prefix(15)) { ap in
                            Button { pick(nil, MKCoordinateRegion(center: ap.coordinate, span: .init(latitudeDelta: 0.8, longitudeDelta: 0.8))) } label: {
                                HStack {
                                    Text(ap.iata).font(.headline.monospaced()).frame(width: 48, alignment: .leading)
                                    VStack(alignment: .leading) {
                                        Text(ap.name).lineLimit(1)
                                        Text("\(ap.city) \(ap.flag)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $text, prompt: "Vuelo, matrícula, aeropuerto o lugar")
            .searchFocused($focused)
            .onAppear { focused = true }
            .onSubmit(of: .search) { Task { await searchRemote() } }
            .task(id: text) {
                remote = []
                places = []
                if text.count >= 2 {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    let req = MKLocalSearch.Request()
                    req.naturalLanguageQuery = text
                    req.resultTypes = .address
                    req.region = MKCoordinateRegion(center: .init(latitude: 0, longitude: 0), span: .init(latitudeDelta: 170, longitudeDelta: 360))
                    var items = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []
                    if items.isEmpty {
                        let marks = (try? await CLGeocoder().geocodeAddressString(text)) ?? []
                        items = marks.map { MKMapItem(placemark: MKPlacemark(placemark: $0)) }
                        for (i, m) in marks.enumerated() { items[i].name = m.name ?? m.locality ?? m.country }
                    }
                    guard !Task.isCancelled else { return }
                    places = Array(items.prefix(6))
                }
                guard text.count >= 3 else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await searchRemote()
            }
            .navigationTitle("Buscar")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .macSheetSize(420, 520)
    }

    private func region(for item: MKMapItem) -> MKCoordinateRegion {
        let c = item.placemark.coordinate
        let radius = (item.placemark.region as? CLCircularRegion)?.radius ?? 20_000
        let deg = min(max(radius * 2.4 / 111_000, 0.4), 120)
        return MKCoordinateRegion(center: c, span: .init(latitudeDelta: deg, longitudeDelta: deg))
    }

    private func subtitle(_ item: MKMapItem) -> String {
        let p = item.placemark
        return [p.locality, p.administrativeArea, p.country].compactMap { $0 }.filter { $0 != item.name }.joined(separator: ", ")
    }

    private func searchRemote() async {
        let q = text
        searching = true
        let r = await API.search(q)
        if q == text { remote = r }
        searching = false
    }

    private func aircraftRow(_ a: Aircraft) -> some View {
        Button { pick(a, nil) } label: {
            HStack {
                Image(systemName: "airplane").rotationEffect(.degrees((a.track ?? 90) - 90))
                    .foregroundStyle(altitudeColor(a.altitude, onGround: a.onGround)).frame(width: 28)
                VStack(alignment: .leading) {
                    Text(a.displayName).font(.headline)
                    Text([a.typeCode, a.registration, a.owner].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(prefs.altitude(a.altitude, ground: a.onGround)).font(.caption.monospacedDigit())
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Filtros

struct FiltersView: View {
    @Environment(RadarStore.self) private var radar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var radar = radar
        NavigationStack {
            Form {
                Section("Altitud (ft)") {
                    HStack { Text("Mínima"); Spacer(); Text("\(Int(radar.filters.minAlt).formatted())").monospacedDigit() }
                    Slider(value: $radar.filters.minAlt, in: 0...45000, step: 1000)
                    HStack { Text("Máxima"); Spacer(); Text("\(Int(radar.filters.maxAlt).formatted())").monospacedDigit() }
                    Slider(value: $radar.filters.maxAlt, in: 0...50000, step: 1000)
                }
                Section("Velocidad mínima") {
                    HStack { Slider(value: $radar.filters.minSpeed, in: 0...600, step: 10); Text("\(Int(radar.filters.minSpeed)) kt").monospacedDigit().frame(width: 60) }
                }
                Section("Mostrar") {
                    Toggle("Ocultar aeronaves en tierra", isOn: $radar.filters.hideGround)
                    Toggle("Solo emergencias", isOn: $radar.filters.onlyEmergencies)
                    Toggle("Solo militares", isOn: $radar.filters.onlyMilitary)
                }
                Section("Aerolínea y modelo") {
                    TextField("Aerolínea (ICAO: LAN, SKU, JAT…)", text: $radar.filters.airline)
                    TextField("Modelo (A320, B78, E19…)", text: $radar.filters.type)
                }
                Section {
                    Button("Restablecer filtros", role: .destructive) { radar.filters = RadarFilters() }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filtros")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .macSheetSize(400, 560)
    }
}

// MARK: - ¿Qué vuela sobre mí?

struct OverheadView: View {
    @Environment(LocationProvider.self) private var location
    @Environment(Prefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    let pick: (Aircraft) -> Void
    @State private var list: [Aircraft] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if location.location == nil {
                    ContentUnavailableView("Ubicación no disponible", systemImage: "location.slash",
                                           description: Text("Permite el acceso a tu ubicación para ver los aviones que tienes encima."))
                } else if list.isEmpty && !loading {
                    ContentUnavailableView("Cielo despejado", systemImage: "cloud.sun", description: Text("No hay aeronaves en 50 NM a la redonda."))
                } else {
                    List(list) { a in
                        Button { pick(a) } label: { row(a) }.buttonStyle(.plain)
                    }
                }
            }
            .overlay { if loading && list.isEmpty { ProgressView() } }
            .navigationTitle("Sobre mí")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: .seconds(8))
                }
            }
        }
        .macSheetSize(420, 520)
    }

    private func load() async {
        guard let me = location.location?.coordinate else { return }
        loading = true
        let r = (try? await API.aircraft(center: me, radiusNM: 50)) ?? []
        list = r.filter { !$0.onGround }.sorted { Geo.distanceKm($0.coordinate, me) < Geo.distanceKm($1.coordinate, me) }
        loading = false
    }

    private func row(_ a: Aircraft) -> some View {
        let me = location.location?.coordinate ?? a.coordinate
        let km = Geo.distanceKm(me, a.coordinate)
        let brg = Geo.bearing(me, a.coordinate)
        let altKm = Double(a.altitude ?? 0) * 0.0003048
        let elev = atan2(altKm, max(km, 0.01)) * 180 / .pi
        let rel = brg - (location.heading ?? 0)
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 44, height: 44)
                Image(systemName: "location.north.fill").foregroundStyle(.orange).rotationEffect(.degrees(rel))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(a.displayName).font(.headline)
                Text([a.typeDesc ?? a.typeCode, a.owner].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("Mira al \(Geo.compass(brg)) · \(Int(elev))° sobre el horizonte").font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(prefs.distance(km)).font(.subheadline.bold().monospacedDigit())
                Text(prefs.altitude(a.altitude)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
