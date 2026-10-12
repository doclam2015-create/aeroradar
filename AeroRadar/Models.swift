import Foundation
import CoreLocation
import SwiftUI

// MARK: - Aeronave (formato readsb / adsb.lol v2)

struct Aircraft: Identifiable, Hashable, Decodable {
    let hex: String
    var id: String { hex }
    var callsign: String?
    var registration: String?
    var typeCode: String?
    var typeDesc: String?
    var owner: String?
    var year: String?
    var altitude: Int?
    var onGround: Bool
    var geomAltitude: Int?
    var groundSpeed: Double?
    var track: Double?
    var verticalRate: Int?
    var squawk: String?
    var category: String?
    var lat: Double
    var lon: Double
    var emergency: String?
    var military: Bool
    var seenPos: Double
    var mach: Double?
    var tas: Int?
    var ias: Int?
    var oat: Int?
    var windDir: Int?
    var windSpeed: Int?
    var navAltitude: Int?
    var source: String?
    var fetchedAt: Date = .now

    enum K: String, CodingKey {
        case hex, flight, r, t, desc, ownOp, year, alt_baro, alt_geom, gs, track, true_heading, baro_rate, geom_rate
        case squawk, category, lat, lon, emergency, dbFlags, seen_pos, mach, tas, ias, oat, wd, ws, nav_altitude_mcp, type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        hex = try c.decode(String.self, forKey: .hex).lowercased()
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        callsign = (try? c.decode(String.self, forKey: .flight))?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        registration = (try? c.decode(String.self, forKey: .r))?.nilIfEmpty
        typeCode = (try? c.decode(String.self, forKey: .t))?.nilIfEmpty
        typeDesc = (try? c.decode(String.self, forKey: .desc))?.nilIfEmpty
        owner = (try? c.decode(String.self, forKey: .ownOp))?.nilIfEmpty
        year = (try? c.decode(String.self, forKey: .year))?.nilIfEmpty
        if let alt = try? c.decode(Int.self, forKey: .alt_baro) {
            altitude = alt; onGround = false
        } else if let s = try? c.decode(String.self, forKey: .alt_baro), s == "ground" {
            altitude = 0; onGround = true
        } else {
            altitude = nil; onGround = false
        }
        geomAltitude = try? c.decode(Int.self, forKey: .alt_geom)
        groundSpeed = try? c.decode(Double.self, forKey: .gs)
        track = (try? c.decode(Double.self, forKey: .track)) ?? (try? c.decode(Double.self, forKey: .true_heading))
        verticalRate = (try? c.decode(Int.self, forKey: .baro_rate)) ?? (try? c.decode(Int.self, forKey: .geom_rate))
        squawk = try? c.decode(String.self, forKey: .squawk)
        category = try? c.decode(String.self, forKey: .category)
        emergency = try? c.decode(String.self, forKey: .emergency)
        military = ((try? c.decode(Int.self, forKey: .dbFlags)) ?? 0) & 1 == 1
        seenPos = (try? c.decode(Double.self, forKey: .seen_pos)) ?? 0
        mach = try? c.decode(Double.self, forKey: .mach)
        tas = try? c.decode(Int.self, forKey: .tas)
        ias = try? c.decode(Int.self, forKey: .ias)
        oat = try? c.decode(Int.self, forKey: .oat)
        windDir = try? c.decode(Int.self, forKey: .wd)
        windSpeed = try? c.decode(Int.self, forKey: .ws)
        navAltitude = try? c.decode(Int.self, forKey: .nav_altitude_mcp)
        source = try? c.decode(String.self, forKey: .type)
    }

    /// Vector de estado de OpenSky: [icao24, callsign, país, tPos, tUlt, lon, lat, altBaro(m), enTierra, vel(m/s), rumbo, vVert(m/s), …, altGeo, squawk]
    init?(openSky s: [Any]) {
        guard s.count > 14, let h = s[0] as? String, let lon = s[5] as? Double, let lat = s[6] as? Double else { return nil }
        hex = h.lowercased()
        self.lat = lat; self.lon = lon
        callsign = (s[1] as? String)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        onGround = s[8] as? Bool ?? false
        altitude = onGround ? 0 : (s[7] as? Double).map { Int($0 / 0.3048) }
        geomAltitude = (s[13] as? Double).map { Int($0 / 0.3048) }
        groundSpeed = (s[9] as? Double).map { $0 * 1.943844 }
        track = s[10] as? Double
        verticalRate = (s[11] as? Double).map { Int($0 * 196.85) }
        squawk = s[14] as? String
        military = false
        let last = (s[3] as? Double) ?? (s[4] as? Double) ?? Date().timeIntervalSince1970
        seenPos = max(0, Date().timeIntervalSince1970 - last)
        source = "opensky"
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var displayName: String { callsign ?? registration ?? hex.uppercased() }
    var airlineICAO: String? {
        guard let cs = callsign, cs.count >= 4 else { return nil }
        let p = cs.prefix(3)
        guard p.allSatisfy(\.isLetter), cs.dropFirst(3).first?.isNumber == true else { return nil }
        return String(p)
    }
    var isEmergency: Bool {
        if let s = squawk, ["7500", "7600", "7700"].contains(s) { return true }
        if let e = emergency, e != "none" { return true }
        return false
    }
    var emergencyLabel: String? {
        switch squawk {
        case "7500": return "Interferencia ilícita (7500)"
        case "7600": return "Falla de radio (7600)"
        case "7700": return "Emergencia general (7700)"
        default:
            guard let e = emergency, e != "none" else { return nil }
            return "Emergencia: \(e)"
        }
    }
    var isHelicopter: Bool { category == "A7" || (typeDesc?.uppercased().contains("HELICOPTER") ?? false) }
    var sizeClass: CGFloat {
        switch category {
        case "A1", "B1", "B4": return 15
        case "A2": return 18
        case "A3": return 22
        case "A4", "A5": return 26
        case "A7": return 17
        default: return 20
        }
    }
    var flightPhase: String {
        if onGround { return "En tierra" }
        guard let vr = verticalRate else { return "En vuelo" }
        if vr > 300 { return "Ascendiendo" }
        if vr < -300 { return "Descendiendo" }
        return "Crucero"
    }

    /// Posición estimada por navegación a estima (para movimiento fluido entre actualizaciones).
    func estimatedPosition(at date: Date) -> CLLocationCoordinate2D {
        guard !onGround, let gs = groundSpeed, gs > 30, let trk = track else { return coordinate }
        let dt = min(date.timeIntervalSince(fetchedAt) + seenPos, 180)
        guard dt > 0 else { return coordinate }
        let distKm = gs * 1.852 * dt / 3600
        return Geo.destination(from: coordinate, bearing: trk, km: distKm)
    }
}

struct ACResponse: Decodable {
    let ac: [Aircraft]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var arr = try c.nestedUnkeyedContainer(forKey: c.contains(.ac) ? .ac : .aircraft)
        var out: [Aircraft] = []
        while !arr.isAtEnd {
            if let a = try? arr.decode(Aircraft.self) { out.append(a) } else { _ = try? arr.decode(Skip.self) }
        }
        ac = out
    }
    enum CodingKeys: String, CodingKey { case ac, aircraft }
    private struct Skip: Decodable {}
}

// MARK: - Ruta y ficha

struct RouteAirport: Codable, Hashable {
    var icao: String
    var iata: String?
    var name: String
    var city: String?
    var country: String?
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var code: String { iata ?? icao }
}

struct FlightRoute: Codable, Hashable {
    var callsign: String
    var callsignICAO: String?
    var callsignIATA: String?
    var airlineName: String?
    var airlineICAO: String?
    var airlineIATA: String?
    var origin: RouteAirport
    var destination: RouteAirport
    var distanceKm: Double { Geo.distanceKm(origin.coordinate, destination.coordinate) }
}

struct AircraftInfo: Hashable {
    var type: String?
    var manufacturer: String?
    var registration: String?
    var owner: String?
    var country: String?
    var photoURL: URL?
    var thumbURL: URL?
}

struct TrailPoint: Hashable {
    var lat: Double
    var lon: Double
    var alt: Int?
    var gs: Double?
    var time: Date
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct Metar: Hashable {
    var raw: String
    var temp: Double?
    var dewpoint: Double?
    var windDir: String?
    var windSpeed: Int?
    var windGust: Int?
    var visibility: String?
    var altimeter: Double?
    var category: String?
    var observed: Date?
    var name: String?

    var categoryColor: Color {
        switch category {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }
}

// MARK: - Aeropuerto local

struct Airport: Identifiable, Hashable {
    let icao: String
    let iata: String
    let name: String
    let city: String
    let country: String
    let lat: Double
    let lon: Double
    let elevation: Int
    let large: Bool
    var id: String { icao }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var flag: String { Geo.flag(country) }
    var asRouteAirport: RouteAirport { .init(icao: icao, iata: iata, name: name, city: city, country: country, lat: lat, lon: lon) }
}

// MARK: - Utilidades

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum Geo {
    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    static func destination(from c: CLLocationCoordinate2D, bearing: Double, km: Double) -> CLLocationCoordinate2D {
        let R = 6371.0, δ = km / R, θ = bearing * .pi / 180
        let φ1 = c.latitude * .pi / 180, λ1 = c.longitude * .pi / 180
        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
        return .init(latitude: φ2 * 180 / .pi, longitude: (λ2 * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
    /// Puntos sobre el círculo máximo entre dos coordenadas.
    static func greatCircle(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, steps: Int = 64) -> [CLLocationCoordinate2D] {
        let φ1 = a.latitude * .pi / 180, λ1 = a.longitude * .pi / 180
        let φ2 = b.latitude * .pi / 180, λ2 = b.longitude * .pi / 180
        let d = 2 * asin(sqrt(pow(sin((φ2 - φ1) / 2), 2) + cos(φ1) * cos(φ2) * pow(sin((λ2 - λ1) / 2), 2)))
        guard d > 0.0001 else { return [a, b] }
        return (0...steps).map { i in
            let f = Double(i) / Double(steps)
            let A = sin((1 - f) * d) / sin(d), B = sin(f * d) / sin(d)
            let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
            let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
            let z = A * sin(φ1) + B * sin(φ2)
            return .init(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi, longitude: atan2(y, x) * 180 / .pi)
        }
    }
    static func compass(_ deg: Double) -> String {
        let d = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        return d[Int((deg + 22.5) / 45) % 8]
    }
    static func flag(_ iso: String) -> String {
        guard iso.count == 2 else { return "🏳️" }
        return iso.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }
}

/// Línea día/noche (terminador solar) como dos polígonos de la zona nocturna.
enum Terminator {
    static func nightPolygons(at date: Date) -> [[CLLocationCoordinate2D]] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let comps = cal.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60 + Double(comps.second ?? 0) / 3600
        let decl = -23.44 * cos(2 * .pi / 365 * (day + 10)) * .pi / 180
        let sunLon = -(hours - 12) * 15
        let pole: Double = decl > 0 ? -85 : 85
        func lat(_ lon: Double) -> Double {
            let t = atan(-cos((lon - sunLon) * .pi / 180) / tan(decl == 0 ? 0.0001 : decl)) * 180 / .pi
            return max(-85, min(85, t))
        }
        return [(-180.0, 0.0), (0.0, 180.0)].map { range in
            var pts = stride(from: range.0, through: range.1, by: 2).map { CLLocationCoordinate2D(latitude: lat($0), longitude: $0) }
            pts.append(.init(latitude: pole, longitude: range.1))
            pts.append(.init(latitude: pole, longitude: range.0))
            return pts
        }
    }
}

func altitudeColor(_ ft: Int?, onGround: Bool = false) -> Color {
    if onGround { return .gray }
    guard let ft else { return .white }
    let f = min(max(Double(ft), 0), 42000) / 42000
    return Color(hue: 0.08 + f * 0.74, saturation: 0.85, brightness: 0.98)
}

extension View {
    /// Tamaño mínimo de hojas solo en Mac (en iPhone/iPad ocupan el ancho disponible).
    @ViewBuilder func macSheetSize(_ w: CGFloat, _ h: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: w, minHeight: h)
        #else
        self
        #endif
    }
}
