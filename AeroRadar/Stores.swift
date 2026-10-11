import Foundation
import SwiftUI
import MapKit
import CoreLocation
import UserNotifications

// MARK: - Preferencias

enum UnitSystem: String, CaseIterable, Identifiable {
    case aviation, metric, imperial
    var id: String { rawValue }
    var label: String { ["aviation": "Aeronáutico (ft, kt)", "metric": "Métrico (m, km/h)", "imperial": "Imperial (ft, mph)"][rawValue]! }
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

    init() {
        d.register(defaults: ["units": "aviation", "mapLook": "dark", "refresh": 6.0, "showLabels": true, "showAirports": true,
                              "showTerminator": false, "showTrails": true, "smoothMotion": true, "emergencyAlerts": true, "maxAircraft": 500])
        units = UnitSystem(rawValue: d.string(forKey: "units") ?? "") ?? .aviation
        mapLook = MapLook(rawValue: d.string(forKey: "mapLook") ?? "") ?? .dark
        refresh = d.double(forKey: "refresh")
        showLabels = d.bool(forKey: "showLabels")
        showAirports = d.bool(forKey: "showAirports")
        showTerminator = d.bool(forKey: "showTerminator")
        showTrails = d.bool(forKey: "showTrails")
        smoothMotion = d.bool(forKey: "smoothMotion")
        emergencyAlerts = d.bool(forKey: "emergencyAlerts")
        maxAircraft = d.integer(forKey: "maxAircraft")
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
        return units == .metric ? "\(Int(Double(ft) * 0.3048).formatted()) m" : "\(ft.formatted()) ft"
    }
    func speed(_ kt: Double?) -> String {
        guard let kt else { return "—" }
        switch units {
        case .aviation: return "\(Int(kt)) kt"
        case .metric: return "\(Int(kt * 1.852)) km/h"
        case .imperial: return "\(Int(kt * 1.15078)) mph"
        }
    }
    func vrate(_ fpm: Int?) -> String {
        guard let fpm else { return "—" }
        let arrow = fpm > 100 ? "↑" : fpm < -100 ? "↓" : "→"
        return units == .metric ? "\(arrow) \(abs(Int(Double(fpm) * 0.00508 * 10)) / 10) m/s" : "\(arrow) \(abs(fpm).formatted()) ft/min"
    }
    func distance(_ km: Double) -> String {
        switch units {
        case .aviation: return "\(Int(km / 1.852).formatted()) NM"
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
    var filters = RadarFilters()
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
    private var ticker: Task<Void, Never>?

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

    var visible: [Aircraft] {
        let list = aircraft.values.filter { filters.matches($0) }
        guard list.count > prefs.maxAircraft else { return list }
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
                let s = self?.prefs.refresh ?? 6
                try? await Task.sleep(for: .seconds(s))
            }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.prefs.smoothMotion else { continue }
                withAnimation(.linear(duration: 1)) { self.tick = .now }
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
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            var list: [Aircraft]
            switch mode {
            case .area: list = try await API.aircraft(center: center, radiusNM: radiusNM * 1.15)
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

    private func merge(_ list: [Aircraft]) {
        let now = Date()
        var next: [String: Aircraft] = [:]
        for var a in list {
            a.fetchedAt = now
            next[a.hex] = a
            if prefs.showTrails || a.hex == selectedHex {
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
        if let a, aircraft[a.hex] == nil { aircraft[a.hex] = a }
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
            selectedInfo = i; selectedTrace = t
            selectedRoute = Self.plausible(route, for: aircraft[h])
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

    func focus(on c: CLLocationCoordinate2D) { center = c }
}
