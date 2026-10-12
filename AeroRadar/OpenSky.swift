import Foundation
import Security

/// OpenSky Network: red con receptores propios que en Sudamérica ve bastante más que las redes comunitarias.
/// Cupo diario: 400 créditos sin cuenta, 4000 con cuenta gratuita (cliente API OAuth2).
/// Costo por consulta según el área del recuadro (grados²): ≤25 → 1, ≤100 → 2, ≤400 → 3, más → 4.
@MainActor @Observable
final class OpenSkyClient {
    static let shared = OpenSkyClient()

    private let d = UserDefaults.standard
    private var token: String?
    private var tokenExpiry = Date.distantPast
    private var lastCall = Date.distantPast
    private(set) var blockedUntil = Date.distantPast
    private(set) var remaining: Int?
    private(set) var lastCount = 0
    private(set) var lastError: String?

    var clientID: String { Keychain.get("opensky.id") ?? "" }
    var hasAccount: Bool { !clientID.isEmpty && Keychain.get("opensky.secret") != nil }
    var dailyBudget: Int { hasAccount ? 4000 : 400 }

    func setCredentials(id: String, secret: String) {
        Keychain.set(id.trimmingCharacters(in: .whitespaces), for: "opensky.id")
        Keychain.set(secret.trimmingCharacters(in: .whitespaces), for: "opensky.secret")
        token = nil; tokenExpiry = .distantPast; blockedUntil = .distantPast; lastError = nil
    }
    func clearCredentials() {
        Keychain.delete("opensky.id"); Keychain.delete("opensky.secret")
        token = nil; lastError = nil
    }

    static func cost(areaSqDeg a: Double) -> Int { a <= 25 ? 1 : a <= 100 ? 2 : a <= 400 ? 3 : 4 }

    // Créditos usados hoy (día UTC), para repartir el cupo
    private var today: String {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let x = c.dateComponents([.year, .month, .day], from: .now)
        return "\(x.year!)-\(x.month!)-\(x.day!)"
    }
    var usedToday: Int { d.string(forKey: "osDay") == today ? d.integer(forKey: "osUsed") : 0 }
    private func spend(_ n: Int) {
        if d.string(forKey: "osDay") != today { d.set(today, forKey: "osDay"); d.set(0, forKey: "osUsed") }
        d.set(usedToday + n, forKey: "osUsed")
    }

    /// Reparte el cupo en ~10 horas de uso al día.
    func minInterval(cost: Int) -> TimeInterval {
        let perSecond = Double(dailyBudget) / 36_000
        return max(hasAccount ? 10 : 30, Double(cost) / perSecond)
    }

    /// `newArea`: el usuario se movió a una zona que la última consulta no cubre → se consulta de inmediato
    func canQuery(cost: Int, newArea: Bool = false) -> Bool {
        let wait = newArea ? 15 : minInterval(cost: cost)
        guard Date() >= blockedUntil, Date().timeIntervalSince(lastCall) >= wait else { return false }
        if let r = remaining, r < cost { return false }
        return usedToday + cost <= dailyBudget
    }

    func states(south: Double, north: Double, west: Double, east: Double) async throws -> [Aircraft] {
        let cost = Self.cost(areaSqDeg: (north - south) * (east - west))
        lastCall = .now
        let url = String(format: "https://opensky-network.org/api/states/all?lamin=%.3f&lomin=%.3f&lamax=%.3f&lomax=%.3f",
                         max(-90, south), max(-180, west), min(90, north), min(180, east))
        let (data, _) = try await request(url)
        spend(cost)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let list = ((root["states"] as? [[Any]]) ?? []).compactMap(Aircraft.init(openSky:))
        lastCount = list.count
        return list
    }

    /// Trayectoria del vuelo actual (solo con cuenta).
    func track(hex: String) async -> [TrailPoint] {
        guard hasAccount, Date() >= blockedUntil,
              let (data, _) = try? await request("https://opensky-network.org/api/tracks/all?icao24=\(hex.lowercased())&time=0"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = root["path"] as? [[Any]] else { return [] }
        spend(1)
        return path.compactMap { p in
            guard p.count >= 6, let t = (p[0] as? Double) ?? (p[0] as? Int).map(Double.init),
                  let lat = p[1] as? Double, let lon = p[2] as? Double else { return nil }
            let ground = p[5] as? Bool ?? false
            let alt = ground ? 0 : (p[3] as? Double).map { Int($0 / 0.3048) }
            return TrailPoint(lat: lat, lon: lon, alt: alt, gs: nil, time: Date(timeIntervalSince1970: t))
        }
    }

    // MARK: Red

    private func request(_ s: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: s) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        if hasAccount, let t = await bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await API.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let r = http.value(forHTTPHeaderField: "X-Rate-Limit-Remaining"), let n = Int(r) { remaining = n }
        switch http.statusCode {
        case 200..<300:
            lastError = nil
            return (data, http)
        case 429:
            let wait = Double(http.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds") ?? "") ?? 3600
            blockedUntil = Date().addingTimeInterval(min(wait, 6 * 3600))
            lastError = "Cupo diario agotado; se reanuda \(blockedUntil.formatted(date: .omitted, time: .shortened))"
        case 401, 403:
            token = nil
            lastError = hasAccount ? "Credenciales de OpenSky rechazadas" : "Acceso denegado"
            blockedUntil = Date().addingTimeInterval(300)
        default:
            blockedUntil = Date().addingTimeInterval(60)
        }
        throw URLError(.badServerResponse)
    }

    private func bearer() async -> String? {
        if let token, Date() < tokenExpiry { return token }
        guard let secret = Keychain.get("opensky.secret"), !clientID.isEmpty,
              let url = URL(string: "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let enc: (String) -> String = { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }
        req.httpBody = "grant_type=client_credentials&client_id=\(enc(clientID))&client_secret=\(enc(secret))".data(using: .utf8)
        guard let (data, resp) = try? await API.session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["access_token"] as? String else {
            lastError = "No se pudo iniciar sesión en OpenSky (revisa el ID y el secreto)"
            return nil
        }
        token = t
        tokenExpiry = Date().addingTimeInterval(Double(j["expires_in"] as? Int ?? 1800) - 60)
        return t
    }
}

/// Llavero del sistema para guardar las credenciales de OpenSky.
enum Keychain {
    private static let service = "cl.doclam.aeroradar"
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ value: String, for key: String) {
        delete(key)
        guard !value.isEmpty else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
