import SwiftUI
import Charts
import MapKit

struct AircraftDetailView: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    @Environment(MyFlightsStore.self) private var myFlights
    @Environment(\.openURL) private var openURL
    let aircraft: Aircraft
    let close: () -> Void
    @State private var addedToMyFlights = false
    @State private var modelImage: URL?

    private var a: Aircraft { aircraft }
    private var route: FlightRoute? { radar.selectedRoute }
    private var info: AircraftInfo? { radar.selectedInfo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let label = a.emergencyLabel {
                    Label(label, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(10)
                        .background(.red.gradient, in: RoundedRectangle(cornerRadius: 12))
                }
                if let route { routeCard(route) }
                actions
                liveGrid
                profileChart
                aircraftCard
                ModelSection(aircraft: a)
                Text("Datos: adsb.lol (ADS-B comunitario), adsbdb.com, aviationweather.gov. Actualizado \(radar.lastUpdate?.formatted(date: .omitted, time: .standard) ?? "—").")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .sensoryFeedback(.selection, trigger: a.hex)
        .task(id: a.hex) {
            modelImage = nil
            modelImage = await ModelInfoLoader.load(for: aircraft).1?.image
        }
    }

    // MARK: Encabezado con foto

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = info?.photoURL ?? modelImage {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { photoPlaceholder.overlay(ProgressView()) }
                } else {
                    photoPlaceholder
                }
            }
            .frame(height: 190).frame(maxWidth: .infinity).clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.displayName).font(.largeTitle.bold())
                    Text(route?.airlineName ?? a.owner ?? info?.owner ?? "Operador desconocido")
                        .font(.subheadline).lineLimit(1)
                }
                Spacer()
                Text(a.flightPhase)
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white).padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.headline).padding(9).background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).padding(10)
        }
    }

    private var photoPlaceholder: some View {
        LinearGradient(colors: [.indigo, .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "airplane").font(.system(size: 60)).foregroundStyle(.white.opacity(0.25)).rotationEffect(.degrees(-20)))
    }

    // MARK: Ruta

    private func routeCard(_ r: FlightRoute) -> some View {
        let total = r.distanceKm
        let done = Geo.distanceKm(r.origin.coordinate, a.coordinate)
        let left = Geo.distanceKm(a.coordinate, r.destination.coordinate)
        let progress = min(max(done / max(done + left, 1), 0), 1)
        let etaHours = (a.groundSpeed ?? 0) > 80 ? left / ((a.groundSpeed ?? 1) * 1.852) : nil
        return VStack(spacing: 12) {
            HStack(alignment: .top) {
                airportColumn(r.origin, align: .leading)
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "airplane").foregroundStyle(.orange)
                    Text(prefs.distance(total)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                airportColumn(r.destination, align: .trailing)
            }
            ProgressView(value: progress).tint(.orange)
            HStack {
                Text("\(prefs.distance(done)) recorridos").font(.caption)
                Spacer()
                if let etaHours {
                    Text("Llega \(Date().addingTimeInterval(etaHours * 3600 + 480).formatted(date: .omitted, time: .shortened)) · faltan \(prefs.distance(left))")
                        .font(.caption.bold())
                } else {
                    Text("Faltan \(prefs.distance(left))").font(.caption)
                }
            }.foregroundStyle(.secondary)
        }
        .card()
    }

    private func airportColumn(_ ap: RouteAirport, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(ap.code).font(.system(size: 30, weight: .bold, design: .rounded))
            Text(ap.city ?? ap.name).font(.caption).lineLimit(1)
            Text(Geo.flag(ap.country ?? "")).font(.caption)
        }
    }

    // MARK: Acciones

    private var actions: some View {
        @Bindable var radar = radar
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                actionButton(radar.follow && !radar.cockpit ? "Siguiendo" : "Seguir", "scope", active: radar.follow && !radar.cockpit) {
                    radar.cockpit = false; radar.follow.toggle()
                }
                actionButton("Vista 3D", "cube.transparent", active: radar.cockpit) {
                    radar.cockpit.toggle(); radar.follow = radar.cockpit
                }
                actionButton(radar.isWatched(a) ? "Vigilado" : "Vigilar", radar.isWatched(a) ? "star.fill" : "star", active: radar.isWatched(a)) {
                    radar.toggleWatch(a)
                }
                if let r = route, !addedToMyFlights {
                    actionButton("Mis vuelos", "plus.circle", active: false) {
                        myFlights.add(MyFlight(number: r.callsignIATA ?? r.callsign, callsignICAO: r.callsignICAO ?? a.callsign, date: .now,
                                               origin: r.origin, destination: r.destination, airline: r.airlineName))
                        addedToMyFlights = true
                    }
                }
                ShareLink(item: URL(string: "https://globe.adsb.lol/?icao=\(a.hex)")!,
                          subject: Text(a.displayName),
                          message: Text(shareText)) {
                    actionLabel("Compartir", "square.and.arrow.up", active: false)
                }.buttonStyle(.plain)
                actionButton("Web", "safari", active: false) {
                    openURL(URL(string: "https://globe.adsb.lol/?icao=\(a.hex)")!)
                }
            }
        }
    }

    private var shareText: String {
        var s = "✈️ \(a.displayName)"
        if let r = route { s += " \(r.origin.code)→\(r.destination.code)" }
        s += " · \(prefs.altitude(a.altitude, ground: a.onGround)) · \(prefs.speed(a.groundSpeed))"
        return s
    }

    private func actionButton(_ t: String, _ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(t, icon, active: active) }.buttonStyle(.plain)
    }
    private func actionLabel(_ t: String, _ icon: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            Text(t).font(.caption2.weight(.medium))
        }
        .frame(width: 72, height: 58)
        .foregroundStyle(active ? .white : .primary)
        .background(active ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Datos en vivo

    private var liveGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Altitud", prefs.altitude(a.altitude, ground: a.onGround), "arrow.up.and.down", altitudeColor(a.altitude, onGround: a.onGround))
            tile("Vel. suelo", prefs.speed(a.groundSpeed), "speedometer", .cyan)
            tile("Vertical", prefs.vrate(a.verticalRate), "arrow.up.forward", (a.verticalRate ?? 0) >= 0 ? .green : .orange)
            tile("Rumbo", a.track.map { "\(Int($0))° \(Geo.compass($0))" } ?? "—", "location.north.line", .blue)
            tile("Squawk", a.squawk ?? "—", "number", a.isEmergency ? .red : .gray)
            tile("Alt. GPS", prefs.altitude(a.geomAltitude), "globe", .teal)
            if let m = a.mach { tile("Mach", String(format: "%.3f", m), "wind", .purple) }
            if let t = a.tas { tile("TAS", prefs.speed(Double(t)), "gauge.with.dots.needle.67percent", .indigo) }
            if let i = a.ias { tile("IAS", prefs.speed(Double(i)), "gauge.medium", .indigo) }
            if let o = a.oat, (a.groundSpeed ?? 0) > 150 { tile("Temp. ext.", "\(o) °C", "thermometer.snowflake", .mint) }
            if let wd = a.windDir, let ws = a.windSpeed { tile("Viento", "\(wd)° / \(prefs.speed(Double(ws)))", "wind", .mint) }
            if let n = a.navAltitude { tile("Alt. selec.", prefs.altitude(n), "dial.medium", .brown) }
        }
    }

    private func tile(_ t: String, _ v: String, _ icon: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(t, systemImage: icon).font(.caption2).foregroundStyle(c).labelStyle(.titleAndIcon)
            Text(v).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Perfil de vuelo

    @ViewBuilder private var profileChart: some View {
        let pts = radar.fullTrail(for: a.hex).filter { $0.alt != nil }
        if pts.count > 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Perfil de vuelo").font(.headline)
                Chart(pts, id: \.time) { p in
                    AreaMark(x: .value("Hora", p.time), y: .value("Altitud", p.alt ?? 0))
                        .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.5), .orange.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Hora", p.time), y: .value("Altitud", p.alt ?? 0))
                        .foregroundStyle(.orange)
                }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let i = v.as(Int.self) { Text("\(i / 1000)k") } } } }
                .frame(height: 140)
                if pts.contains(where: { $0.gs != nil }) {
                    Chart(pts.filter { $0.gs != nil }, id: \.time) { p in
                        LineMark(x: .value("Hora", p.time), y: .value("Velocidad", p.gs ?? 0)).foregroundStyle(.cyan)
                    }
                    .chartYAxisLabel("kt")
                    .frame(height: 90)
                }
            }
            .card()
        }
    }

    // MARK: Aeronave

    private var aircraftCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aeronave").font(.headline)
            row("Modelo", TypeDB.spec(for: a.typeCode)?.name ?? info.flatMap { i in [i.manufacturer, i.type].compactMap { $0 }.joined(separator: " ").nilIfEmpty } ?? a.typeDesc ?? a.typeCode)
            row("Código tipo", a.typeCode)
            row("Matrícula", a.registration ?? info?.registration)
            row("Operador", a.owner ?? info?.owner)
            row("País de registro", info?.country)
            row("Año", a.year)
            row("Hex ICAO", a.hex.uppercased())
            row("Fuente", sourceLabel)
            if a.military { row("Clasificación", "Militar") }
        }
        .card()
    }

    private var sourceLabel: String {
        switch a.source ?? "" {
        case let s where s.hasPrefix("adsb"): return "ADS-B"
        case "mlat": return "MLAT (multilateración)"
        case let s where s.hasPrefix("tisb"): return "TIS-B"
        case "adsr_icao": return "ADS-R"
        case "mode_s": return "Modo S"
        case "opensky": return "OpenSky Network"
        default: return a.source ?? "—"
        }
    }

    @ViewBuilder private func row(_ k: String, _ v: String?) -> some View {
        if let v, !v.isEmpty {
            HStack {
                Text(k).foregroundStyle(.secondary)
                Spacer()
                Text(v).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            .font(.subheadline)
            Divider()
        }
    }
}

extension View {
    func card() -> some View {
        padding(14).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    }
}
