import SwiftUI

/// Carga la ficha del modelo (especificaciones locales + foto y resumen de Wikipedia).
struct ModelInfoLoader {
    static func load(for a: Aircraft) async -> (TypeSpec?, API.WikiSummary?) {
        let spec = TypeDB.spec(for: a.typeCode)
        if let spec { return (spec, await API.wiki(title: spec.wiki)) }
        if let d = a.typeDesc { return (nil, await API.wiki(search: d)) }
        return (nil, nil)
    }
}

// MARK: - Sección "Modelo" (detalle)

struct ModelSection: View {
    let aircraft: Aircraft
    @State private var spec: TypeSpec?
    @State private var wiki: API.WikiSummary?
    @State private var loaded = false
    @State private var expanded = false

    var body: some View {
        Group {
            if spec != nil || wiki != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Modelo").font(.headline)
                    if let url = wiki?.image {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                            .frame(height: 170).frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(spec?.name ?? wiki?.title ?? aircraft.typeDesc ?? "").font(.title3.bold())
                    if let spec { SpecGrid(spec: spec) }
                    if let w = wiki, !w.extract.isEmpty {
                        Text(w.extract).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(expanded ? nil : 4)
                            .onTapGesture { withAnimation { expanded.toggle() } }
                        if let p = w.page { Link("Leer más en Wikipedia", destination: p).font(.caption) }
                    }
                    if spec != nil { Text("Valores de referencia aproximados del fabricante.").font(.caption2).foregroundStyle(.tertiary) }
                }
                .card()
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: aircraft.typeCode ?? aircraft.hex) {
            loaded = false
            (spec, wiki) = await ModelInfoLoader.load(for: aircraft)
            loaded = true
        }
    }
}

struct SpecGrid: View {
    let spec: TypeSpec
    var compact = false

    var body: some View {
        let items: [(String, String, String)] = [
            ("Motores", spec.engines, "fanblades"),
            ("Pasajeros", spec.seats, "person.3"),
            ("Alcance", spec.rangeKm.contains("km") || !spec.rangeKm.first!.isNumber ? spec.rangeKm : "\(spec.rangeKm) km", "point.topleft.down.to.point.bottomright.curvepath"),
            ("Crucero", spec.cruise, "speedometer"),
            ("Largo", spec.length, "arrow.left.and.right"),
            ("Envergadura", spec.span, "airplane"),
            ("Peso máx. despegue", spec.mtow, "scalemass"),
            ("Primer vuelo", spec.firstFlight, "calendar"),
        ]
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: compact ? 6 : 10) {
            ForEach(items, id: \.0) { t, v, icon in
                VStack(alignment: .leading, spacing: 1) {
                    Label(t, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
                    Text(v).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Tarjeta al pasar el puntero (Mac / iPad con trackpad)

struct HoverCard: View {
    @Environment(Prefs.self) private var prefs
    let aircraft: Aircraft
    @State private var route: FlightRoute?
    @State private var info: AircraftInfo?
    @State private var spec: TypeSpec?
    @State private var wiki: API.WikiSummary?

    private var a: Aircraft { aircraft }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Foto real del avión o, si no hay, del modelo
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = info?.photoURL ?? wiki?.image {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { placeholder }
                    } else { placeholder }
                }
                .frame(width: 340, height: 150).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.displayName).font(.title2.bold())
                    Text(route?.airlineName ?? a.owner ?? info?.owner ?? "").font(.caption).lineLimit(1)
                }
                .foregroundStyle(.white).padding(10)
            }
            .frame(width: 340, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let r = route {
                HStack {
                    VStack(alignment: .leading) { Text(r.origin.code).font(.title3.bold()); Text(r.origin.city ?? "").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    Image(systemName: "airplane").foregroundStyle(.orange)
                    Spacer()
                    VStack(alignment: .trailing) { Text(r.destination.code).font(.title3.bold()); Text(r.destination.city ?? "").font(.caption2).foregroundStyle(.secondary) }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { kv("Altitud", prefs.altitude(a.altitude, ground: a.onGround)); kv("Velocidad", prefs.speed(a.groundSpeed)) }
                GridRow { kv("Vertical", prefs.vrate(a.verticalRate)); kv("Rumbo", a.track.map { "\(Int($0))° \(Geo.compass($0))" } ?? "—") }
                GridRow { kv("Matrícula", a.registration ?? info?.registration ?? "—"); kv("Squawk", a.squawk ?? "—") }
                GridRow { kv("Tipo", a.typeCode ?? "—"); kv("Hex", a.hex.uppercased()) }
            }

            if spec != nil || wiki != nil {
                Divider()
                Text(spec?.name ?? wiki?.title ?? a.typeDesc ?? "").font(.headline)
                if let spec { SpecGrid(spec: spec, compact: true) }
                else if let w = wiki { Text(w.extract).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
            }
            Text("Clic para ver la ficha completa").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 364)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .task(id: a.hex) {
            let ac = a, cs = a.callsign
            async let r: FlightRoute? = { if let cs { return await API.route(callsign: cs) }; return nil }()
            async let i = API.info(hex: ac.hex)
            async let m = ModelInfoLoader.load(for: ac)
            route = RadarStore.plausible(await r, for: ac)
            info = await i
            (spec, wiki) = await m
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [.indigo, .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "airplane").font(.system(size: 44)).foregroundStyle(.white.opacity(0.3)))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.callout.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(width: 160, alignment: .leading)
    }
}

// MARK: - Lugares para la búsqueda

struct NamedRegion: Identifiable {
    let name: String
    let lat: Double, lon: Double, latSpan: Double, lonSpan: Double
    var id: String { name }

    static let all: [NamedRegion] = [
        .init(name: "Todo el mundo", lat: 20, lon: 0, latSpan: 140, lonSpan: 360),
        .init(name: "Sudamérica", lat: -22, lon: -62, latSpan: 60, lonSpan: 55),
        .init(name: "Norteamérica", lat: 42, lon: -100, latSpan: 50, lonSpan: 75),
        .init(name: "Centroamérica y el Caribe", lat: 16, lon: -80, latSpan: 22, lonSpan: 40),
        .init(name: "Europa", lat: 50, lon: 12, latSpan: 32, lonSpan: 50),
        .init(name: "África", lat: 3, lon: 20, latSpan: 75, lonSpan: 75),
        .init(name: "Medio Oriente", lat: 28, lon: 47, latSpan: 25, lonSpan: 35),
        .init(name: "Asia", lat: 32, lon: 95, latSpan: 60, lonSpan: 90),
        .init(name: "Oceanía", lat: -25, lon: 140, latSpan: 45, lonSpan: 60),
        .init(name: "Antártica", lat: -75, lon: 0, latSpan: 30, lonSpan: 360),
    ]

    static func matching(_ q: String) -> [NamedRegion] {
        let t = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard t.count >= 2 else { return [] }
        let aliases = ["mundo": "Todo el mundo", "world": "Todo el mundo", "sudamerica": "Sudamérica", "america del sur": "Sudamérica",
                       "norteamerica": "Norteamérica", "america del norte": "Norteamérica", "caribe": "Centroamérica y el Caribe",
                       "centroamerica": "Centroamérica y el Caribe", "oriente": "Medio Oriente", "oceania": "Oceanía", "antartica": "Antártica",
                       "antartida": "Antártica", "africa": "África", "europa": "Europa", "asia": "Asia"]
        let names = Set(aliases.filter { $0.key.contains(t) || t.contains($0.key) }.map(\.value))
        return all.filter { names.contains($0.name) || $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(t) }
    }
}
