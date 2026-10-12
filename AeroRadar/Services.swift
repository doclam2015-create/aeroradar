import Foundation
import CoreLocation

/// Fuentes de datos gratuitas y sin clave:
/// - adsb.lol y adsb.fi: posiciones ADS-B/MLAT en vivo (redes comunitarias)
/// - adsbdb.com: rutas por indicativo y ficha de aeronave con foto
/// - aviationweather.gov: METAR/TAF oficiales (NOAA)
enum API {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["User-Agent": "AeroRadar/1.0 (app personal de seguimiento de vuelos)"]
        c.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)
        return URLSession(configuration: c)
    }()

    private static func get(_ s: String, headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw URLError(.badServerResponse) }
        return data
    }

    /// adsb.lol primero; si limita (429) o falla, adsb.fi (mismo formato readsb).
    private static func aircraftList(_ path: String, fallbackPath: String? = nil) async throws -> [Aircraft] {
        do {
            let data = try await get("https://api.adsb.lol/v2/" + path)
            return try JSONDecoder().decode(ACResponse.self, from: data).ac
        } catch {
            let data = try await get("https://opendata.adsb.fi/api/v2/" + (fallbackPath ?? path))
            return try JSONDecoder().decode(ACResponse.self, from: data).ac
        }
    }

    static func aircraft(center: CLLocationCoordinate2D, radiusNM: Double) async throws -> [Aircraft] {
        let r = Int(min(max(radiusNM, 5), 250))
        return try await aircraftList(String(format: "point/%.4f/%.4f/%d", center.latitude, center.longitude, r),
                                      fallbackPath: String(format: "lat/%.4f/lon/%.4f/dist/%d", center.latitude, center.longitude, r))
    }
    /// Todas las aeronaves dentro de un recuadro de cualquier tamaño (hasta el mundo entero).
    static func aircraft(south: Double, north: Double, west: Double, east: Double) async throws -> [Aircraft] {
        let s = max(-90, south), n = min(90, north)
        var w = west, e = east
        if e - w >= 359 || w < -180 || e > 180 { w = -180; e = 180 }
        let url = String(format: "https://globe.adsb.lol/re-api/?box=%.3f,%.3f,%.3f,%.3f&jv2", s, n, w, e)
        let data = try await get(url, headers: ["Referer": "https://globe.adsb.lol/"])
        return try JSONDecoder().decode(ACResponse.self, from: data).ac
    }

    /// airplanes.live: red comunitaria con buena cobertura en Sudamérica. Su API oficial rechaza nuestras consultas,
    /// así que se usa el endpoint de su mapa web (autorizado por el usuario, uso personal y moderado).
    static func airplanesLive(south: Double, north: Double, west: Double, east: Double) async throws -> [Aircraft] {
        let url = String(format: "https://globe.airplanes.live/re-api/?box=%.3f,%.3f,%.3f,%.3f",
                         max(-90, south), min(90, north), max(-180, west), min(180, east))
        let data = try await get(url, headers: ["Referer": "https://globe.airplanes.live/"])
        return try JSONDecoder().decode(ACResponse.self, from: data).ac
    }

    /// OpenSky Network (acceso anónimo, cupo diario limitado): complementa zonas con poca cobertura.
    static func openSky(south: Double, north: Double, west: Double, east: Double) async throws -> [Aircraft] {
        let url = String(format: "https://opensky-network.org/api/states/all?lamin=%.3f&lomin=%.3f&lamax=%.3f&lomax=%.3f",
                         max(-90, south), max(-180, west), min(90, north), min(180, east))
        let data = try await get(url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = root["states"] as? [[Any]] else { return [] }
        return states.compactMap(Aircraft.init(openSky:))
    }

    static func military() async throws -> [Aircraft] { try await aircraftList("mil") }
    static func squawk(_ code: String) async throws -> [Aircraft] { try await aircraftList("sqk/\(code)") }
    static func emergencies() async throws -> [Aircraft] {
        async let a = squawk("7700"); async let b = squawk("7600"); async let c = squawk("7500")
        return try await a + b + c
    }
    static func byCallsign(_ cs: String) async throws -> [Aircraft] {
        try await aircraftList("callsign/\(cs.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cs)")
    }
    static func byRegistration(_ r: String) async throws -> [Aircraft] {
        try await aircraftList("reg/\(r.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? r)")
    }
    static func byHex(_ h: String) async throws -> [Aircraft] { try await aircraftList("hex/\(h.lowercased())") }

    /// Busca por indicativo, matrícula o código hex.
    static func search(_ q: String) async -> [Aircraft] {
        let t = q.trimmingCharacters(in: .whitespaces).uppercased()
        guard t.count >= 2 else { return [] }
        var results: [Aircraft] = []
        if let r = try? await byCallsign(t) { results += r }
        if results.isEmpty, let r = try? await byRegistration(t) { results += r }
        if results.isEmpty, t.count == 6, t.allSatisfy(\.isHexDigit), let r = try? await byHex(t) { results += r }
        if results.isEmpty, let route = await route(callsign: t), let icao = route.callsignICAO, icao != t,
           let r = try? await byCallsign(icao) { results += r }
        return results
    }

    // MARK: Rutas y fichas (con caché)

    private static let cache = Cache()
    actor Cache {
        var routes: [String: FlightRoute?] = [:]
        var infos: [String: AircraftInfo?] = [:]
        func route(_ k: String) -> FlightRoute?? { routes[k] }
        func setRoute(_ k: String, _ v: FlightRoute?) { routes[k] = v }
        func info(_ k: String) -> AircraftInfo?? { infos[k] }
        func setInfo(_ k: String, _ v: AircraftInfo?) { infos[k] = v }
    }

    static func route(callsign: String) async -> FlightRoute? {
        let key = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        if let hit = await cache.route(key) { return hit }
        var result: FlightRoute?
        if let data = try? await get("https://api.adsbdb.com/v0/callsign/\(key)"),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resp = root["response"] as? [String: Any],
           let fr = resp["flightroute"] as? [String: Any],
           let o = parseAirport(fr["origin"]), let d = parseAirport(fr["destination"]) {
            let al = fr["airline"] as? [String: Any]
            result = FlightRoute(callsign: key,
                                 callsignICAO: fr["callsign_icao"] as? String,
                                 callsignIATA: fr["callsign_iata"] as? String,
                                 airlineName: al?["name"] as? String,
                                 airlineICAO: al?["icao"] as? String,
                                 airlineIATA: al?["iata"] as? String,
                                 origin: o, destination: d)
        }
        await cache.setRoute(key, result)
        return result
    }

    private static func parseAirport(_ any: Any?) -> RouteAirport? {
        guard let a = any as? [String: Any], let icao = a["icao_code"] as? String,
              let lat = a["latitude"] as? Double, let lon = a["longitude"] as? Double else { return nil }
        return RouteAirport(icao: icao, iata: a["iata_code"] as? String, name: a["name"] as? String ?? icao,
                            city: a["municipality"] as? String, country: a["country_iso_name"] as? String, lat: lat, lon: lon)
    }

    static func info(hex: String) async -> AircraftInfo? {
        let key = hex.lowercased()
        if let hit = await cache.info(key) { return hit }
        var result: AircraftInfo?
        if let data = try? await get("https://api.adsbdb.com/v0/aircraft/\(key)"),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resp = root["response"] as? [String: Any],
           let a = resp["aircraft"] as? [String: Any] {
            result = AircraftInfo(type: a["type"] as? String,
                                  manufacturer: a["manufacturer"] as? String,
                                  registration: a["registration"] as? String,
                                  owner: a["registered_owner"] as? String,
                                  country: a["registered_owner_country_name"] as? String,
                                  photoURL: (a["url_photo"] as? String).flatMap(URL.init(string:)),
                                  thumbURL: (a["url_photo_thumbnail"] as? String).flatMap(URL.init(string:)))
        }
        await cache.setInfo(key, result)
        return result
    }

    /// Historial completo del vuelo de hoy (globe.adsb.lol).
    static func trace(hex: String) async -> [TrailPoint] {
        let h = hex.lowercased()
        guard let raw = try? await get("https://globe.adsb.lol/data/traces/\(h.suffix(2))/trace_full_\(h).json",
                                       headers: ["Referer": "https://globe.adsb.lol/"]) else { return [] }
        let data = raw.starts(with: [0x1f, 0x8b]) ? (gunzip(raw) ?? raw) : raw
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = root["timestamp"] as? Double,
              let trace = root["trace"] as? [[Any]] else { return [] }
        var pts: [TrailPoint] = []
        for p in trace where p.count > 4 {
            guard let dt = p[0] as? Double, let lat = p[1] as? Double, let lon = p[2] as? Double else { continue }
            let alt = (p[3] as? Double).map { Int($0) } ?? ((p[3] as? String) == "ground" ? 0 : nil)
            pts.append(TrailPoint(lat: lat, lon: lon, alt: alt, gs: p[4] as? Double, time: Date(timeIntervalSince1970: ts + dt)))
        }
        // Solo el vuelo actual: desde la última vez en tierra o desde un hueco de señal largo (>20 min)
        if let i = pts.indices.reversed().first(where: {
            $0 > 0 && $0 < pts.count - 1 && (pts[$0].alt == 0 || pts[$0].time.timeIntervalSince(pts[$0 - 1].time) > 1200)
        }) {
            pts = Array(pts[i...])
        }
        return pts
    }

    private static func gunzip(_ d: Data) -> Data? {
        guard d.count > 18 else { return nil }
        let flags = d[d.startIndex + 3]
        var i = 10
        if flags & 4 != 0 { i += 2 + Int(d[d.startIndex + 10]) + Int(d[d.startIndex + 11]) << 8 }
        if flags & 8 != 0 { while i < d.count, d[d.startIndex + i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < d.count, d[d.startIndex + i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        return try? (d.subdata(in: (d.startIndex + i)..<(d.endIndex - 8)) as NSData).decompressed(using: .zlib) as Data
    }

    // MARK: Wikipedia (foto y descripción del modelo)

    struct WikiSummary: Hashable {
        var title: String
        var extract: String
        var image: URL?
        var page: URL?
    }
    private static let wikiCache = WikiCache()
    actor WikiCache {
        var items: [String: WikiSummary?] = [:]
        func get(_ k: String) -> WikiSummary?? { items[k] }
        func set(_ k: String, _ v: WikiSummary?) { items[k] = v }
    }

    static func wiki(title: String) async -> WikiSummary? {
        if let hit = await wikiCache.get(title) { return hit }
        var result: WikiSummary?
        for lang in ["es", "en"] where result == nil {
            let t = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            if let data = try? await get("https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(t)"),
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (j["type"] as? String) == "standard" {
                let img = ((j["originalimage"] as? [String: Any])?["source"] as? String) ?? ((j["thumbnail"] as? [String: Any])?["source"] as? String)
                let page = ((j["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
                result = WikiSummary(title: j["title"] as? String ?? title, extract: j["extract"] as? String ?? "",
                                     image: img.flatMap(URL.init(string:)), page: page.flatMap(URL.init(string:)))
            }
        }
        await wikiCache.set(title, result)
        return result
    }

    /// Busca el artículo de un modelo sin ficha propia a partir de la descripción ("BOEING 737-800").
    static func wiki(search desc: String) async -> WikiSummary? {
        let q = desc.capitalized.replacingOccurrences(of: "-", with: " ")
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let data = try? await get("https://es.wikipedia.org/w/api.php?action=opensearch&limit=1&format=json&search=\(enc)"),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let titles = arr.count > 1 ? arr[1] as? [String] : nil, let t = titles.first,
              let maker = q.split(separator: " ").first, t.localizedCaseInsensitiveContains(maker) else { return nil }
        return await wiki(title: t)
    }

    // MARK: Meteorología

    static func metar(_ icao: String) async -> Metar? {
        guard let data = try? await get("https://aviationweather.gov/api/data/metar?ids=\(icao)&format=json"),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let m = arr.first,
              let raw = m["rawOb"] as? String else { return nil }
        func num(_ k: String) -> Double? { (m[k] as? Double) ?? (m[k] as? Int).map(Double.init) }
        let wdir: String? = (m["wdir"] as? Int).map { String(format: "%03d°", $0) } ?? (m["wdir"] as? String)
        let vis: String? = (m["visib"] as? String) ?? num("visib").map { String(format: "%.0f", $0) }
        return Metar(raw: raw, temp: num("temp"), dewpoint: num("dewp"), windDir: wdir,
                     windSpeed: m["wspd"] as? Int, windGust: m["wgst"] as? Int, visibility: vis,
                     altimeter: num("altim"), category: m["fltCat"] as? String ?? flightCategory(raw),
                     observed: num("obsTime").map { Date(timeIntervalSince1970: $0) }, name: m["name"] as? String)
    }

    static func taf(_ icao: String) async -> String? {
        guard let data = try? await get("https://aviationweather.gov/api/data/taf?ids=\(icao)&format=raw") else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    /// Categoría de vuelo a partir del METAR crudo cuando la API no la entrega.
    static func flightCategory(_ raw: String) -> String? {
        var ceiling = 99999, visM = 9999
        for tok in raw.split(separator: " ") {
            let s = String(tok)
            if s.hasPrefix("BKN") || s.hasPrefix("OVC") || s.hasPrefix("VV"), let h = Int(s.dropFirst(s.hasPrefix("VV") ? 2 : 3).prefix(3)) {
                ceiling = min(ceiling, h * 100)
            }
            if s.count == 4, let v = Int(s) { visM = v }
            if s == "CAVOK" { return "VFR" }
        }
        if ceiling < 500 || visM < 1600 { return "LIFR" }
        if ceiling < 1000 || visM < 5000 { return "IFR" }
        if ceiling <= 3000 || visM <= 8000 { return "MVFR" }
        return "VFR"
    }
}

// MARK: - Base local de aeropuertos (OurAirports, dominio público)

enum AirportDB {
    static let all: [Airport] = {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return rows.compactMap { r in
            guard r.count >= 9, let icao = r[0] as? String, let iata = r[1] as? String, let name = r[2] as? String,
                  let lat = (r[5] as? Double) ?? (r[5] as? Int).map(Double.init),
                  let lon = (r[6] as? Double) ?? (r[6] as? Int).map(Double.init) else { return nil }
            return Airport(icao: icao, iata: iata, name: name, city: r[3] as? String ?? "", country: r[4] as? String ?? "",
                           lat: lat, lon: lon, elevation: r[7] as? Int ?? 0, large: (r[8] as? Int) == 1)
        }
    }()
    private static let byCode: [String: Airport] = {
        var d: [String: Airport] = [:]
        for a in all { d[a.icao] = a; d[a.iata] = a }
        return d
    }()

    static func find(_ code: String) -> Airport? { byCode[code.uppercased()] }

    static func search(_ q: String) -> [Airport] {
        let t = q.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard !t.isEmpty else { return [] }
        let up = t.uppercased()
        return all.filter {
            $0.iata == up || $0.icao == up ||
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(t) ||
            $0.city.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(t)
        }
        .sorted { ($0.iata == up || $0.icao == up ? 0 : $0.large ? 1 : 2) < ($1.iata == up || $1.icao == up ? 0 : $1.large ? 1 : 2) }
        .prefix(60).map { $0 }
    }

    static func near(_ c: CLLocationCoordinate2D, limit: Int = 30) -> [Airport] {
        all.map { ($0, Geo.distanceKm($0.coordinate, c)) }.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    static func inRegion(center: CLLocationCoordinate2D, latDelta: Double, lonDelta: Double, largeOnly: Bool) -> [Airport] {
        let la = latDelta / 2 * 1.1, lo = lonDelta / 2 * 1.1
        return all.filter {
            (!largeOnly || $0.large) && abs($0.lat - center.latitude) < la && abs($0.lon - center.longitude) < lo
        }
    }
}
