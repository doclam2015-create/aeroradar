import Foundation
import SwiftUI
import CoreLocation

enum FlightPhase: String, Codable {
    case scheduled, taxiing, airborne, landed, unknown
    var label: String {
        switch self {
        case .scheduled: return "Programado"
        case .taxiing: return "En rodaje"
        case .airborne: return "En vuelo"
        case .landed: return "Aterrizó"
        case .unknown: return "Sin señal"
        }
    }
    var color: Color {
        switch self {
        case .scheduled: return .blue
        case .taxiing: return .orange
        case .airborne: return .green
        case .landed: return .purple
        case .unknown: return .gray
        }
    }
}

struct MyFlight: Identifiable, Codable, Hashable {
    var id = UUID()
    var number: String
    var callsignICAO: String?
    var date: Date
    var departure: Date?
    var arrival: Date?
    var origin: RouteAirport?
    var destination: RouteAirport?
    var airline: String?
    var seat = ""
    var cabin = "Económica"
    var confirmation = ""
    var terminal = ""
    var gate = ""
    var notes = ""
    var phase: FlightPhase = .scheduled
    var takeoffAt: Date?
    var landedAt: Date?
    var lastHex: String?
    var lastPosition: [Double]?
    var lastAltitude: Int?
    var lastSpeed: Double?
    var registration: String?
    var aircraftType: String?
    var updatedAt: Date?

    var distanceKm: Double {
        guard let o = origin, let d = destination else { return 0 }
        return Geo.distanceKm(o.coordinate, d.coordinate)
    }
    var lastCoordinate: CLLocationCoordinate2D? {
        guard let p = lastPosition, p.count == 2 else { return nil }
        return .init(latitude: p[0], longitude: p[1])
    }
    var progress: Double {
        switch phase {
        case .landed: return 1
        case .airborne:
            guard let c = lastCoordinate, let o = origin, let d = destination, distanceKm > 0 else { return 0.5 }
            let done = Geo.distanceKm(o.coordinate, c), left = Geo.distanceKm(c, d.coordinate)
            return min(max(done / (done + left), 0), 1)
        default: return 0
        }
    }
    var remainingKm: Double? {
        guard phase == .airborne, let c = lastCoordinate, let d = destination else { return nil }
        return Geo.distanceKm(c, d.coordinate)
    }
    /// Llegada estimada a partir de la velocidad actual (+8 min de aproximación).
    var estimatedArrival: Date? {
        guard let km = remainingKm, let gs = lastSpeed, gs > 80 else { return arrival }
        return Date().addingTimeInterval(km / (gs * 1.852) * 3600 + 480)
    }
    var isPast: Bool { phase == .landed || (Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: .now.addingTimeInterval(-86400))) }
    var isActiveWindow: Bool { abs(date.timeIntervalSinceNow) < 36 * 3600 && phase != .landed }
    var durationHours: Double {
        if let t = takeoffAt, let l = landedAt { return l.timeIntervalSince(t) / 3600 }
        if let d = departure, let a = arrival, a > d { return a.timeIntervalSince(d) / 3600 }
        return distanceKm / 780 + 0.5
    }
}

@MainActor @Observable
final class MyFlightsStore {
    var flights: [MyFlight] = [] { didSet { save() } }
    var isRefreshing = false
    /// Búsqueda en los aviones que ya muestra el radar (incluye OpenSky, que no permite buscar por indicativo)
    var localLookup: ((String) -> Aircraft?)?
    private var loop: Task<Void, Never>?
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AeroRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mis-vuelos.json")
    }()

    init() {
        if let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode([MyFlight].self, from: d) { flights = f }
    }
    private func save() { try? JSONEncoder().encode(flights).write(to: url, options: .atomic) }

    var upcoming: [MyFlight] { flights.filter { !$0.isPast }.sorted { $0.date < $1.date } }
    var past: [MyFlight] { flights.filter(\.isPast).sorted { $0.date > $1.date } }

    func lookup(_ number: String) async -> FlightRoute? {
        await API.route(callsign: number.replacingOccurrences(of: " ", with: "").uppercased())
    }

    func add(_ f: MyFlight) {
        Notifier.requestAuth()
        flights.append(f)
        Task { await refresh() }
    }
    func update(_ f: MyFlight) { if let i = flights.firstIndex(where: { $0.id == f.id }) { flights[i] = f } }
    func delete(_ f: MyFlight) { flights.removeAll { $0.id == f.id } }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        for f in flights where f.isActiveWindow {
            await track(f.id)
        }
    }

    private func track(_ id: UUID) async {
        guard var f = flights.first(where: { $0.id == id }) else { return }
        let cs = f.callsignICAO ?? f.number
        var found = (try? await API.byCallsign(cs)) ?? []
        if found.isEmpty, let local = localLookup?(cs) { found = [local] }
        // Si hay varias con el mismo indicativo, la más cercana a la ruta
        let a = found.min { x, y in
            guard let o = f.origin else { return false }
            return Geo.distanceKm(x.coordinate, o.coordinate) < Geo.distanceKm(y.coordinate, o.coordinate)
        }
        let old = f.phase
        if let a {
            f.lastHex = a.hex
            f.lastPosition = [a.lat, a.lon]
            f.lastAltitude = a.altitude
            f.lastSpeed = a.groundSpeed
            f.registration = a.registration ?? f.registration
            f.aircraftType = a.typeDesc ?? a.typeCode ?? f.aircraftType
            if a.onGround {
                if let d = f.destination, Geo.distanceKm(a.coordinate, d.coordinate) < 15, old == .airborne || f.takeoffAt != nil {
                    f.phase = .landed; f.landedAt = f.landedAt ?? .now
                } else if (a.groundSpeed ?? 0) > 5 {
                    f.phase = .taxiing
                }
            } else {
                f.phase = .airborne
                if f.takeoffAt == nil {
                    // Hora real de despegue según el historial del vuelo
                    let trace = await API.trace(hex: a.hex)
                    f.takeoffAt = trace.first(where: { ($0.alt ?? 0) > 0 })?.time ?? .now
                }
            }
        } else if old == .airborne, let c = f.lastCoordinate, let d = f.destination,
                  Geo.distanceKm(c, d.coordinate) < 40, (f.lastAltitude ?? 99999) < 6000 {
            // Perdimos señal en la aproximación final: lo damos por aterrizado
            f.phase = .landed; f.landedAt = .now
        }
        f.updatedAt = .now
        if f.phase != old {
            let route = "\(f.origin?.code ?? "?") → \(f.destination?.code ?? "?")"
            switch f.phase {
            case .taxiing: Notifier.send("\(f.number) en rodaje", "\(route): el avión se está moviendo en pista.")
            case .airborne: Notifier.send("🛫 \(f.number) despegó", "\(route). Llegada estimada \(f.estimatedArrival?.formatted(date: .omitted, time: .shortened) ?? "—").")
            case .landed: Notifier.send("🛬 \(f.number) aterrizó", "\(route) · \(f.destination?.city ?? f.destination?.name ?? "").")
            default: break
            }
        }
        update(f)
    }

    // MARK: Pasaporte

    var flown: [MyFlight] { flights.filter { $0.phase == .landed || $0.date < .now } }
    var totalKm: Double { flown.reduce(0) { $0 + $1.distanceKm } }
    var totalHours: Double { flown.reduce(0) { $0 + $1.durationHours } }
    var airports: Set<String> { Set(flown.flatMap { [$0.origin?.code, $0.destination?.code].compactMap { $0 } }) }
    var countries: Set<String> { Set(flown.flatMap { [$0.origin?.country, $0.destination?.country].compactMap { $0 } }) }
    var airlines: [String: Int] { flown.reduce(into: [:]) { $0[$1.airline ?? "Otra", default: 0] += 1 } }
    var longest: MyFlight? { flown.max { $0.distanceKm < $1.distanceKm } }
}
