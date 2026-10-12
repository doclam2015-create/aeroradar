import Foundation
import SwiftUI
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Preferencias

enum UnitSystem: String, CaseIterable, Identifiable {
    case both, aviation, metric, imperial
    var id: String { rawValue }
    var label: String {
        ["both": "Aeronáutico + métrico", "aviation": "Aeronáutico (ft, kt)", "metric": "Métrico (m, km/h)", "imperial": "Imperial (ft, mph)"][rawValue]!
    }
}

enum MapLook: String, CaseIterable, Identifiable {
    case dark, standard, hybrid, satellite
    var id: String { rawValue }
    var label: String { ["dark": "Radar oscuro", "standard": "Estándar", "hybrid": "Híbrido", "satellite": "Satélite"][rawValue]! }
}

@MainActor @Observable
final class Prefs {
    private let d = UserDefaults.standard
    var units: UnitSystem { didSet { d.set(units.rawValue, forKey: "units") } }
    var mapLook: MapLook { didSet { d.set(mapLook.rawValue, forKey: "mapLook") } }
    var refresh: Double { didSet { d.set(refresh, forKey: "refresh") } }
    var showLabels: Bool { didSet { d.set(showLabels, forKey: "showLabels") } }
    var showAirports: Bool { didSet { d.set(showAirports, forKey: "showAirports") } }
    var showTerminator: Bool { didSet { d.set(showTerminator, forKey: "showTerminator") } }
    var showTrails: Bool { didSet { d.set(showTrails, forKey: "showTrails") } }
    var smoothMotion: Bool { didSet { d.set(smoothMotion, forKey: "smoothMotion") } }
    var emergencyAlerts: Bool { didSet { d.set(emergencyAlerts, forKey: "emergencyAlerts") } }
    var maxAircraft: Int { didSet { d.set(maxAircraft, forKey: "maxAircraft") } }
    var useAirplanesLive: Bool { didSet { d.set(useAirplanesLive, forKey: "useAirplanesLive") } }

    init() {
        d.register(defaults: ["units": "both", "mapLook": "dark", "refresh": 6.0, "showLabels": true, "showAirports": true,
                              "showTerminator": false, "showTrails": true, "smoothMotion": true, "emergencyAlerts": true, "maxAircraft": 500, "useAirplanesLive": true])
        units = UnitSystem(rawValue: d.string(forKey: "units") ?? "") ?? .both
        mapLook = MapLook(rawValue: d.string(forKey: "mapLook") ?? "") ?? .dark
        refresh = d.double(forKey: "refresh")
        showLabels = d.bool(forKey: "showLabels")
        showAirports = d.bool(forKey: "showAirports")
        showTerminator = d.bool(forKey: "showTerminator")
        showTrails = d.bool(forKey: "showTrails")
        smoothMotion = d.bool(forKey: "smoothMotion")
        emergencyAlerts = d.bool(forKey: "emergencyAlerts")
        maxAircraft = d.integer(forKey: "maxAircraft")
        useAirplanesLive = d.bool(forKey: "useAirplanesLive")
    }

    var mapStyle: MapStyle {
        switch mapLook {
        case .dark: return .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .standard: return .standard(elevation: .realistic, pointsOfInterest: .including([.airport]))
        case .hybrid: return .hybrid(elevation: .realistic, pointsOfInterest: .including([.airport]))
        case .satellite: return .imagery(elevation: .realistic)
        }
    }
    var forceDark: Bool { mapLook == .dark }

    // Formato
    func altitude(_ ft: Int?, ground: Bool = false) -> String {
        if ground { return "En tierra" }
        guard let ft else { return "—" }
        let m = "\(Int(Double(ft) * 0.3048).formatted()) m"
        switch units {
        case .metric: return m
        case .both: return "\(ft.formatted()) ft · \(m)"
        default: return "\(ft.formatted()) ft"
        }
    }
    func speed(_ kt: Double?) -> String {
        guard let kt else { return "—" }
        switch units {
        case .aviation: return "\(Int(kt)) kt"
        case .both: return "\(Int(kt)) kt · \(Int(kt * 1.852)) km/h"
        case .metric: return "\(Int(kt * 1.852)) km/h"
        case .imperial: return "\(Int(kt * 1.15078)) mph"
        }
    }
    func vrate(_ fpm: Int?) -> String {
        guard let fpm else { return "—" }
        let arrow = fpm > 100 ? "↑" : fpm < -100 ? "↓" : "→"
        let ms = String(format: "%.1f m/s", abs(Double(fpm) * 0.00508)).replacingOccurrences(of: ".", with: ",")
        switch units {
        case .metric: return "\(arrow) \(ms)"
        case .both: return "\(arrow) \(abs(fpm).formatted()) ft/min · \(ms)"
        default: return "\(arrow) \(abs(fpm).formatted()) ft/min"
        }
    }
    func distance(_ km: Double) -> String {
        switch units {
        case .aviation: return "\(Int(km / 1.852).formatted()) NM"
        case .both: return "\(Int(km).formatted()) km · \(Int(km / 1.852).formatted()) NM"
        case .metric: return "\(Int(km).formatted()) km"
        case .imperial: return "\(Int(km * 0.621371).formatted()) mi"
        }
    }
}

// MARK: - Ubicación

@MainActor @Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    var heading: Double?
    private let m = CLLocationManager()
    override init() { super.init(); m.delegate = self }
    func request() {
        m.requestWhenInUseAuthorization()
        m.startUpdatingLocation()
        #if os(iOS)
        if CLLocationManager.headingAvailable() { m.startUpdatingHeading() }
        #endif
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        let l = locs.last
        Task { @MainActor in self.location = l }
    }
    #if os(iOS)
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in self.heading = v }
    }
    #endif
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.m.authorizationStatus != .denied { self.m.startUpdatingLocation() } }
    }
}

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    static func send(_ title: String, _ body: String, id: String = UUID().uuidString) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }
}

// MARK: - Filtros y modos

struct RadarFilters: Equatable {
    var minAlt: Double = 0
    var maxAlt: Double = 50000
    var hideGround = false
    var onlyEmergencies = false
    var onlyMilitary = false
    var minSpeed: Double = 0
    var airline = ""
    var type = ""
    var isActive: Bool { self != RadarFilters() }

    func matches(_ a: Aircraft) -> Bool {
        if hideGround && a.onGround { return false }
        if onlyEmergencies && !a.isEmergency { return false }
        if onlyMilitary && !a.military { return false }
        let alt = Double(a.altitude ?? 0)
        if !a.onGround && (alt < minAlt || alt > maxAlt) { return false }
        if minSpeed > 0 && (a.groundSpeed ?? 0) < minSpeed { return false }
        if !airline.isEmpty {
            let q = airline.uppercased()
            if !(a.callsign?.uppercased().hasPrefix(q) ?? false) && !(a.owner?.uppercased().contains(q) ?? false) { return false }
        }
        if !type.isEmpty {
            let q = type.uppercased()
            if !(a.typeCode?.uppercased().hasPrefix(q) ?? false) && !(a.typeDesc?.uppercased().contains(q) ?? false) { return false }
        }
        return true
    }
}

enum RadarMode: String, CaseIterable, Identifiable {
    case area, military, emergencies, watchlist
    var id: String { rawValue }
    var label: String { ["area": "Zona", "military": "Militares", "emergencies": "Emergencias", "watchlist": "Vigilados"][rawValue]! }
    var icon: String { ["area": "scope", "military": "shield.lefthalf.filled", "emergencies": "exclamationmark.triangle.fill", "watchlist": "star.fill"][rawValue]! }
}

struct WatchItem: Codable, Hashable, Identifiable {
    var query: String
    var note: String = ""
    var id: String { query }
}

// MARK: - Radar

@MainActor @Observable
final class RadarStore {
    let prefs: Prefs
    var aircraft: [String: Aircraft] = [:]
    var trails: [String: [TrailPoint]] = [:]
    var mode: RadarMode = .area { didSet { aircraft = [:]; trails = [:]; Task { await refresh() } } }
    var filters = RadarFilters() { didSet { recomputeVisible() } }
    /// Aviones a dibujar (calculado una vez por actualización, no en cada fotograma)
    private(set) var visible: [Aircraft] = []
    /// Aumenta cada vez que cambian los datos: el mapa solo se sincroniza cuando cambia
    private(set) var dataVersion = 0
    var cameraRequest: CameraRequest?
    var hoverPoint: CGPoint = .zero
    private var pendingRefresh = false
    var center = CLLocationCoordinate2D(latitude: -33.45, longitude: -70.67)
    var span = MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
    var mapHeading: Double = 0
    var lastUpdate: Date?
    var isLoading = false
    var errorText: String?
    var tick = Date()

    var selectedHex: String? { didSet { if selectedHex != oldValue { loadSelection() } } }
    var selectedRoute: FlightRoute?
    var selectedInfo: AircraftInfo?
    var selectedTrace: [TrailPoint] = []
    var follow = false
    var cockpit = false
    var hoverHex: String?
    private var hoverClear: Task<Void, Never>?

    func hover(_ hex: String, _ inside: Bool) {
        hoverClear?.cancel()
        if inside { hoverHex = hex; return }
        hoverClear = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, self?.hoverHex == hex else { return }
            self?.hoverHex = nil
        }
    }
    var hovered: Aircraft? { hoverHex.flatMap { aircraft[$0] } }

    // Estadísticas de la sesión
    var seen: Set<String> = []
    var typeCounts: [String: Int] = [:]
    var airlineCounts: [String: Int] = [:]
    var highest: Aircraft?
    var fastest: Aircraft?
    var sessionStart = Date()
    private var alertedEmergencies: Set<String> = []

    var watchlist: [WatchItem] = [] { didSet { saveWatchlist() } }
    var watchHits: [String: Aircraft] = [:]
    private var alertedWatch: Set<String> = []
    private var lastWatchCheck = Date.distantPast

    private var loop: Task<Void, Never>?

    init(prefs: Prefs) {
        self.prefs = prefs
        if let d = UserDefaults.standard.data(forKey: "watchlist"), let w = try? JSONDecoder().decode([WatchItem].self, from: d) {
            watchlist = w
        }
        if let lat = UserDefaults.standard.object(forKey: "lastLat") as? Double, let lon = UserDefaults.standard.object(forKey: "lastLon") as? Double {
            center = .init(latitude: lat, longitude: lon)
            let s = UserDefaults.standard.double(forKey: "lastSpan")
            if s > 0 { span = .init(latitudeDelta: s, longitudeDelta: s) }
        }
    }

    var selected: Aircraft? { selectedHex.flatMap { aircraft[$0] ?? watchHits[$0] } }

    func recomputeVisible() {
        visible = computeVisible()
        dataVersion += 1
    }

    private func computeVisible() -> [Aircraft] {
        let list = aircraft.values.filter { filters.matches($0) }
        guard list.count > prefs.maxAircraft else { return list }
        if span.latitudeDelta > 20 {
            // Vista continental o mundial: muestra una selección repartida en todo el mapa
            // Reparto geográfico: cuadrícula de 12×12 y se toma un avión de cada celda por turno
            let la0 = center.latitude - span.latitudeDelta / 2, lo0 = center.longitude - span.longitudeDelta / 2
            var cells: [Int: [Aircraft]] = [:]
            for a in list {
                let r = min(11, max(0, Int((a.lat - la0) / span.latitudeDelta * 12)))
                let c = min(11, max(0, Int((a.lon - lo0) / span.longitudeDelta * 12)))
                cells[r * 12 + c, default: []].append(a)
            }
            var queues = cells.values.map { $0.sorted { $0.hex < $1.hex } }
            var out: [Aircraft] = []
            var i = 0
            while out.count < prefs.maxAircraft && !queues.isEmpty {
                queues = queues.filter { i < $0.count }
                for q in queues where out.count < prefs.maxAircraft { out.append(q[i]) }
                i += 1
            }
            if let s = selected, !out.contains(where: { $0.hex == s.hex }) { out.append(s) }
            return out
        }
        return Array(list.sorted { Geo.distanceKm($0.coordinate, center) < Geo.distanceKm($1.coordinate, center) }.prefix(prefs.maxAircraft))
    }

    var radiusNM: Double {
        let km = Geo.distanceKm(center, .init(latitude: center.latitude + span.latitudeDelta / 2,
                                              longitude: center.longitude + span.longitudeDelta / 2))
        return km / 1.852
    }

    func position(of a: Aircraft) -> CLLocationCoordinate2D {
        prefs.smoothMotion ? a.estimatedPosition(at: tick) : a.coordinate
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                var s = self?.prefs.refresh ?? 6
                if let d = self?.span.latitudeDelta, d > 30 { s = max(s, 20) }   // mundo/continente: menos datos
                try? await Task.sleep(for: .seconds(s))
            }
        }
    }

    func updateRegion(_ r: MKCoordinateRegion, heading: Double) {
        let moved = Geo.distanceKm(r.center, center) > radiusNM * 1.852 * 0.25 || abs(r.span.latitudeDelta - span.latitudeDelta) / span.latitudeDelta > 0.3
        center = r.center; span = r.span; mapHeading = heading
        UserDefaults.standard.set(r.center.latitude, forKey: "lastLat")
        UserDefaults.standard.set(r.center.longitude, forKey: "lastLon")
        UserDefaults.standard.set(r.span.latitudeDelta, forKey: "lastSpan")
        if moved && mode == .area { Task { await refresh() } }
        else if span.latitudeDelta > 20 || visible.count >= prefs.maxAircraft { recomputeVisible() }
    }

    func refresh() async {
        guard !isLoading else { pendingRefresh = true; return }
        isLoading = true
        defer {
            isLoading = false
            // El usuario movió el mapa mientras se cargaba: pedir de inmediato la zona nueva
            if pendingRefresh { pendingRefresh = false; Task { await refresh() } }
        }
        do {
            var list: [Aircraft]
            switch mode {
            case .area: list = try await areaAircraft()
            case .military: list = try await API.military()
            case .emergencies: list = try await API.emergencies()
            case .watchlist: list = await watchSearch()
            }
            // Mantener la aeronave seleccionada aunque salga del área
            if let h = selectedHex, !list.contains(where: { $0.hex == h }), let one = try? await API.byHex(h).first {
                list.append(one)
            }
            merge(list)
            lastUpdate = .now
            errorText = nil
        } catch {
            errorText = "Sin conexión con la red ADS-B"
        }
        if mode != .watchlist && !watchlist.isEmpty && Date().timeIntervalSince(lastWatchCheck) > 60 {
            lastWatchCheck = .now
            _ = await watchSearch()
        }
        if prefs.emergencyAlerts { checkEmergencies() }
    }

    // MARK: Fuentes por zona

    private var openSkyCache: [Aircraft] = []
    /// Aviones aportados por cada fuente en la última actualización
    private(set) var adsbCount = 0
    private(set) var openSkyExtra = 0
    private(set) var airplanesLiveExtra = 0
    private var airplanesLiveCache: [Aircraft] = []
    private var airplanesLiveAt = Date.distantPast
    private var openSkyBox: (s: Double, n: Double, w: Double, e: Double)?

    private var box: (s: Double, n: Double, w: Double, e: Double) {
        let la = span.latitudeDelta / 2 * 1.1, lo = span.longitudeDelta / 2 * 1.1
        return (center.latitude - la, center.latitude + la, center.longitude - lo, center.longitude + lo)
    }

    private func areaAircraft() async throws -> [Aircraft] {
        let b = box
        var list: [Aircraft] = []
        var adsbFailed = false
        // airplanes.live en paralelo (cada ≥10 s y sin vistas mundiales)
        let useAL = prefs.useAirplanesLive && span.latitudeDelta < 70 && Date().timeIntervalSince(airplanesLiveAt) >= 10
        if useAL { airplanesLiveAt = .now }
        async let alTask: [Aircraft]? = useAL ? try? API.airplanesLive(south: b.s, north: b.n, west: b.w, east: b.e) : nil
        do {
            list = try await API.aircraft(south: b.s, north: b.n, west: b.w, east: b.e)
        } catch {
            do { list = try await API.aircraft(center: center, radiusNM: radiusNM * 1.15) }
            catch { adsbFailed = true }   // seguimos: las otras fuentes pueden cubrir la zona
        }
        if let al = await alTask { airplanesLiveCache = al }
        if !prefs.useAirplanesLive { airplanesLiveCache = [] }
        airplanesLiveCache.removeAll { Date().timeIntervalSince($0.fetchedAt) > 60 }
        let adsbHex = Set(list.map(\.hex))
        let alExtra = airplanesLiveCache.filter { !adsbHex.contains($0.hex) && $0.lat > b.s && $0.lat < b.n && $0.lon > b.w && $0.lon < b.e }
        airplanesLiveExtra = alExtra.count
        list += alExtra
        adsbCount = list.count - alExtra.count
        // OpenSky suma receptores propios: en Sudamérica ve más del doble que las redes comunitarias.
        let os = OpenSkyClient.shared
        let cost = OpenSkyClient.cost(areaSqDeg: (b.n - b.s) * (b.e - b.w))
        let c = openSkyBox
        let newArea = c == nil || !(center.latitude > c!.s && center.latitude < c!.n && center.longitude > c!.w && center.longitude < c!.e)
            || (b.n - b.s) > (c!.n - c!.s) * 1.8
        if span.latitudeDelta < 70, os.canQuery(cost: cost, newArea: newArea) {
            if let fresh = try? await os.states(south: b.s, north: b.n, west: b.w, east: b.e) {
                openSkyCache = fresh
                openSkyBox = b
            }
        }
        // Posiciones de OpenSky de más de 3 minutos ya no son confiables
        openSkyCache.removeAll { Date().timeIntervalSince($0.fetchedAt) > 180 }
        let known = Set(list.map(\.hex))
        let extra = openSkyCache.filter { !known.contains($0.hex) && $0.lat > b.s && $0.lat < b.n && $0.lon > b.w && $0.lon < b.e }
        openSkyExtra = extra.count
        list += extra
        if adsbFailed && list.isEmpty { throw URLError(.cannotConnectToHost) }
        return list
    }

    private func merge(_ list: [Aircraft]) {
        let now = Date()
        var next: [String: Aircraft] = [:]
        for a in list {
            next[a.hex] = a
            if (prefs.showTrails && span.latitudeDelta < 8) || a.hex == selectedHex {
                var t = trails[a.hex] ?? []
                if t.last.map({ $0.lat != a.lat || $0.lon != a.lon }) ?? true {
                    t.append(TrailPoint(lat: a.lat, lon: a.lon, alt: a.altitude, gs: a.groundSpeed, time: now))
                    if t.count > 200 { t.removeFirst(t.count - 200) }
                }
                trails[a.hex] = t
            }
            if seen.insert(a.hex).inserted {
                if let t = a.typeCode { typeCounts[t, default: 0] += 1 }
                if let al = a.airlineICAO { airlineCounts[al, default: 0] += 1 }
            }
            if !a.onGround, let alt = a.altitude, alt > (highest?.altitude ?? 0) { highest = a }
            if let gs = a.groundSpeed, gs > (fastest?.groundSpeed ?? 0), !a.onGround { fastest = a }
        }
        trails = trails.filter { next[$0.key] != nil }
        aircraft = next
        tick = now
        recomputeVisible()
    }

    private func checkEmergencies() {
        for a in aircraft.values where a.isEmergency && !alertedEmergencies.contains(a.hex) {
            alertedEmergencies.insert(a.hex)
            Notifier.send("⚠️ \(a.displayName): \(a.emergencyLabel ?? "Emergencia")",
                          "\(a.typeDesc ?? a.typeCode ?? "Aeronave") a \(prefs.altitude(a.altitude, ground: a.onGround)), \(prefs.speed(a.groundSpeed))",
                          id: "emerg-\(a.hex)")
        }
    }

    // MARK: Vigilancia

    func watchSearch() async -> [Aircraft] {
        var found: [Aircraft] = []
        for w in watchlist {
            let r = await API.search(w.query)
            found += r
            if let a = r.first, !alertedWatch.contains(w.query) {
                alertedWatch.insert(w.query)
                Notifier.send("★ \(w.query) está en el aire", "\(a.displayName) · \(prefs.altitude(a.altitude, ground: a.onGround)) · \(a.typeDesc ?? a.typeCode ?? "")",
                              id: "watch-\(w.query)")
            } else if r.isEmpty {
                alertedWatch.remove(w.query)
            }
        }
        watchHits = Dictionary(found.map { ($0.hex, $0) }, uniquingKeysWith: { a, _ in a })
        return found
    }

    func isWatched(_ a: Aircraft) -> Bool {
        watchlist.contains { [a.callsign, a.registration, a.hex.uppercased()].compactMap { $0?.uppercased() }.contains($0.query.uppercased()) }
    }
    func toggleWatch(_ a: Aircraft) {
        let keys = [a.registration, a.callsign, a.hex.uppercased()].compactMap { $0?.uppercased() }
        if isWatched(a) { watchlist.removeAll { keys.contains($0.query.uppercased()) } }
        else { Notifier.requestAuth(); watchlist.append(WatchItem(query: a.registration ?? a.callsign ?? a.hex.uppercased())) }
    }
    private func saveWatchlist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(watchlist), forKey: "watchlist")
    }

    // MARK: Selección

    func select(_ a: Aircraft?) {
        if let a, aircraft[a.hex] == nil { aircraft[a.hex] = a; recomputeVisible() }
        selectedHex = a?.hex
        if a == nil { follow = false; cockpit = false }
    }

    private func loadSelection() {
        selectedRoute = nil; selectedInfo = nil; selectedTrace = []
        guard let h = selectedHex else { return }
        let cs = selected?.callsign
        Task {
            async let info = API.info(hex: h)
            async let trace = API.trace(hex: h)
            let route: FlightRoute? = if let cs { await API.route(callsign: cs) } else { nil }
            let (i, t) = await (info, trace)
            guard selectedHex == h else { return }
            selectedInfo = i
            selectedRoute = Self.plausible(route, for: aircraft[h])
            selectedTrace = t
            if t.isEmpty {
                let os = await OpenSkyClient.shared.track(hex: h)
                if selectedHex == h { selectedTrace = os }
            }
        }
    }

    /// Descarta rutas obviamente erróneas (el avión está lejísimos del trayecto).
    static func plausible(_ r: FlightRoute?, for a: Aircraft?) -> FlightRoute? {
        guard let r, let a else { return r }
        let total = r.distanceKm
        let via = Geo.distanceKm(r.origin.coordinate, a.coordinate) + Geo.distanceKm(a.coordinate, r.destination.coordinate)
        return via > total * 1.6 + 400 ? nil : r
    }

    func fullTrail(for hex: String) -> [TrailPoint] {
        let live = trails[hex] ?? []
        guard hex == selectedHex, let lastTrace = selectedTrace.last?.time else { return live }
        return selectedTrace + live.filter { $0.time > lastTrace }
    }

    func focus(on c: CLLocationCoordinate2D, span d: Double = 1.2) {
        cameraRequest = CameraRequest(region: MKCoordinateRegion(center: c, span: .init(latitudeDelta: d, longitudeDelta: d)))
    }
}
