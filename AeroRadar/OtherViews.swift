import SwiftUI
import MapKit
import Charts

// MARK: - Aeropuertos

struct AirportsView: View {
    @Environment(LocationProvider.self) private var location
    @Environment(RadarStore.self) private var radar
    let goToRadar: () -> Void
    @State private var text = ""
    @AppStorage("favAirports") private var favRaw = "SCEL,SCFA"

    private var favs: [Airport] { favRaw.split(separator: ",").compactMap { AirportDB.find(String($0)) } }

    var body: some View {
        NavigationStack {
            List {
                if text.isEmpty {
                    if !favs.isEmpty {
                        Section("Favoritos") { ForEach(favs) { row($0) } }
                    }
                    Section(location.location == nil ? "Cerca del mapa" : "Cerca de ti") {
                        ForEach(AirportDB.near(location.location?.coordinate ?? radar.center, limit: 20)) { row($0) }
                    }
                } else {
                    ForEach(AirportDB.search(text)) { row($0) }
                }
            }
            .searchable(text: $text, prompt: "Código, ciudad o nombre")
            .navigationTitle("Aeropuertos")
            .navigationDestination(for: Airport.self) { AirportDetail(airport: $0, favRaw: $favRaw, goToRadar: goToRadar) }
        }
    }

    private func row(_ ap: Airport) -> some View {
        NavigationLink(value: ap) {
            HStack(spacing: 12) {
                Text(ap.iata).font(.headline.monospaced()).frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ap.name).lineLimit(1)
                    Text("\(ap.city) · \(ap.icao) \(ap.flag)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let me = location.location?.coordinate {
                    Text("\(Int(Geo.distanceKm(me, ap.coordinate))) km").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct AirportDetail: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    let airport: Airport
    @Binding var favRaw: String
    let goToRadar: () -> Void
    @State private var metar: Metar?
    @State private var taf: String?
    @State private var traffic: [Aircraft] = []
    @State private var loading = true

    private var isFav: Bool { favRaw.split(separator: ",").contains(Substring(airport.icao)) }
    private var arrivals: [Aircraft] { traffic.filter { !$0.onGround && ($0.verticalRate ?? 0) < -200 && ($0.altitude ?? 0) < 15000 } }
    private var departures: [Aircraft] { traffic.filter { !$0.onGround && ($0.verticalRate ?? 0) > 200 && ($0.altitude ?? 0) < 15000 } }
    private var ground: [Aircraft] { traffic.filter(\.onGround) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: airport.coordinate, distance: 9000, heading: 0, pitch: 55))) {
                    ForEach(traffic) { a in
                        Annotation(a.displayName, coordinate: a.coordinate) {
                            Image(systemName: "airplane").foregroundStyle(altitudeColor(a.altitude, onGround: a.onGround))
                                .rotationEffect(.degrees((a.track ?? 90) - 90)).shadow(radius: 2)
                        }
                    }
                }
                .mapStyle(.imagery(elevation: .realistic))
                .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 6) {
                    Text(airport.name).font(.title2.bold())
                    Text("\(airport.city) \(airport.flag) · IATA \(airport.iata) · ICAO \(airport.icao) · Elev. \(airport.elevation) ft")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let m = metar { MetarCard(metar: m, taf: taf) }
                else if loading { ProgressView("Cargando meteorología…") }

                trafficSection("Llegando", arrivals, "airplane.arrival")
                trafficSection("Despegando", departures, "airplane.departure")
                trafficSection("En tierra", ground, "parkingsign.circle")

                Button {
                    radar.focus(on: airport.coordinate)
                    goToRadar()
                } label: { Label("Ver en el radar", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle(airport.iata)
        .toolbar {
            Button { toggleFav() } label: { Image(systemName: isFav ? "star.fill" : "star") }
        }
        .task {
            async let m = API.metar(airport.icao)
            async let t = API.taf(airport.icao)
            async let tr = try? API.aircraft(center: airport.coordinate, radiusNM: 25)
            metar = await m; taf = await t; traffic = (await tr) ?? []
            loading = false
        }
    }

    private func toggleFav() {
        var s = favRaw.split(separator: ",").map(String.init)
        if isFav { s.removeAll { $0 == airport.icao } } else { s.append(airport.icao) }
        favRaw = s.joined(separator: ",")
    }

    @ViewBuilder private func trafficSection(_ t: String, _ list: [Aircraft], _ icon: String) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(t) (\(list.count))", systemImage: icon).font(.headline)
                ForEach(list.prefix(12)) { a in
                    HStack {
                        Text(a.displayName).font(.subheadline.bold().monospaced())
                        Text(a.typeCode ?? "").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(prefs.altitude(a.altitude, ground: a.onGround)).font(.caption.monospacedDigit())
                        Text("\(Int(Geo.distanceKm(a.coordinate, airport.coordinate))) km").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .card()
        }
    }
}

struct MetarCard: View {
    @Environment(Prefs.self) private var prefs
    let metar: Metar
    let taf: String?
    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Meteorología").font(.headline)
                Spacer()
                if let c = metar.category {
                    Text(c).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(metar.categoryColor, in: Capsule()).foregroundStyle(.white)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                w("Temp.", metar.temp.map { "\(Int($0))°C" } ?? "—", "thermometer.medium")
                w("Rocío", metar.dewpoint.map { "\(Int($0))°C" } ?? "—", "drop")
                w("Viento", windText, "wind")
                w("Visib.", metar.visibility.map { $0 == "6+" ? "≥10 km" : "\($0) SM" } ?? "—", "eye")
                w("QNH", metar.altimeter.map { "\(Int($0)) hPa" } ?? "—", "barometer")
                w("Hora", metar.observed?.formatted(date: .omitted, time: .shortened) ?? "—", "clock")
            }
            DisclosureGroup("METAR y TAF", isExpanded: $showRaw) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(metar.raw).font(.caption.monospaced()).textSelection(.enabled)
                    if let taf { Text(taf).font(.caption.monospaced()).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
        }
        .card()
    }

    private var windText: String {
        guard let s = metar.windSpeed else { return "—" }
        if s == 0 { return "Calma" }
        return "\(metar.windDir ?? "") \(s) kt" + (metar.windGust.map { " G\($0)" } ?? "")
    }

    private func w(_ t: String, _ v: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(t, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeatherMini: View {
    let title: String
    let metar: Metar
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline.monospaced())
                Spacer()
                if let c = metar.category {
                    Text(c).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(metar.categoryColor, in: Capsule()).foregroundStyle(.white)
                }
            }
            Text(metar.temp.map { "\(Int($0))°C" } ?? "—").font(.title2.bold())
            Text("Viento \(metar.windDir ?? "") \(metar.windSpeed ?? 0) kt").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

// MARK: - Estadísticas

struct StatsView: View {
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs

    private var current: [Aircraft] { Array(radar.aircraft.values) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        kpi("\(current.count)", "en pantalla ahora", "airplane", .orange)
                        kpi("\(radar.seen.count)", "vistas en esta sesión", "eye", .blue)
                        kpi("\(current.filter { !$0.onGround }.count)", "en vuelo", "cloud", .cyan)
                        kpi("\(current.filter(\.military).count)", "militares", "shield.lefthalf.filled", .green)
                        kpi("\(current.filter(\.isEmergency).count)", "emergencias", "exclamationmark.triangle", .red)
                        kpi(radar.sessionStart.formatted(.relative(presentation: .numeric)), "inicio de sesión", "clock", .purple)
                    }

                    if let h = radar.highest {
                        record("Más alto", h, prefs.altitude(h.altitude), "arrow.up.to.line")
                    }
                    if let f = radar.fastest {
                        record("Más rápido", f, prefs.speed(f.groundSpeed), "hare")
                    }

                    chartCard("Modelos más vistos", radar.typeCounts)
                    chartCard("Aerolíneas más vistas (ICAO)", radar.airlineCounts)

                    if !current.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Distribución de altitudes").font(.headline)
                            let bins = Dictionary(grouping: current.filter { !$0.onGround && $0.altitude != nil }) { (($0.altitude ?? 0) / 5000) * 5 }
                            Chart(bins.keys.sorted(), id: \.self) { k in
                                BarMark(x: .value("Altitud", "\(k)k"), y: .value("Aeronaves", bins[k]?.count ?? 0))
                                    .foregroundStyle(altitudeColor(k * 1000))
                            }
                            .frame(height: 180)
                        }.card()
                    }
                }
                .padding()
                .frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .navigationTitle("Estadísticas")
        }
    }

    private func kpi(_ v: String, _ t: String, _ icon: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(c)
            Text(v).font(.title.bold()).lineLimit(1).minimumScaleFactor(0.5)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func record(_ t: String, _ a: Aircraft, _ v: String, _ icon: String) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.orange).frame(width: 36)
            VStack(alignment: .leading) {
                Text(t).font(.caption).foregroundStyle(.secondary)
                Text("\(a.displayName) · \(a.typeCode ?? "")").font(.headline)
            }
            Spacer()
            Text(v).font(.title3.bold().monospacedDigit())
        }.card()
    }

    @ViewBuilder private func chartCard(_ title: String, _ counts: [String: Int]) -> some View {
        if !counts.isEmpty {
            let top = counts.sorted { $0.value > $1.value }.prefix(10)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Chart(Array(top), id: \.key) { e in
                    BarMark(x: .value("Cantidad", e.value), y: .value("", e.key))
                        .foregroundStyle(.orange.gradient)
                        .annotation(position: .trailing) { Text("\(e.value)").font(.caption2) }
                }
                .frame(height: CGFloat(top.count) * 26 + 20)
            }.card()
        }
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @Environment(Prefs.self) private var prefs
    @Environment(RadarStore.self) private var radar

    var body: some View {
        @Bindable var prefs = prefs
        @Bindable var radar = radar
        NavigationStack {
            Form {
                Section("Mapa") {
                    Picker("Estilo", selection: $prefs.mapLook) { ForEach(MapLook.allCases) { Text($0.label).tag($0) } }
                    Toggle("Etiquetas de vuelo", isOn: $prefs.showLabels)
                    Toggle("Aeropuertos", isOn: $prefs.showAirports)
                    Toggle("Estelas de todos los aviones", isOn: $prefs.showTrails)
                    Toggle("Línea día / noche", isOn: $prefs.showTerminator)
                    Toggle("Movimiento fluido (estima)", isOn: $prefs.smoothMotion)
                    Stepper("Máximo de aeronaves: \(prefs.maxAircraft)", value: $prefs.maxAircraft, in: 100...1500, step: 100)
                }
                Section("Datos") {
                    Picker("Unidades", selection: $prefs.units) { ForEach(UnitSystem.allCases) { Text($0.label).tag($0) } }
                    Stepper("Actualizar cada \(Int(prefs.refresh)) s", value: $prefs.refresh, in: 3...30, step: 1)
                }
                Section("Alertas") {
                    Toggle("Avisar emergencias (7500/7600/7700)", isOn: $prefs.emergencyAlerts)
                        .onChange(of: prefs.emergencyAlerts) { _, v in if v { Notifier.requestAuth() } }
                    NavigationLink("Lista de vigilancia (\(radar.watchlist.count))") { WatchlistView() }
                }
                OpenSkySection()
                Section("Fuentes de datos (gratuitas)") {
                    Link("adsb.lol — posiciones ADS-B en vivo (ODbL)", destination: URL(string: "https://adsb.lol")!)
                    Link("adsb.fi — red ADS-B de respaldo", destination: URL(string: "https://adsb.fi")!)
                    Link("OpenSky Network — receptores propios (mejor cobertura en Sudamérica)", destination: URL(string: "https://opensky-network.org")!)
                    Link("Wikipedia — fotos y descripción de modelos", destination: URL(string: "https://es.wikipedia.org")!)
                    Link("adsbdb.com — rutas y fichas de aeronaves", destination: URL(string: "https://www.adsbdb.com")!)
                    Link("aviationweather.gov — METAR y TAF", destination: URL(string: "https://aviationweather.gov")!)
                    Link("OurAirports — base de aeropuertos", destination: URL(string: "https://ourairports.com")!)
                }
                Section {
                    LabeledContent("Versión", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("AeroRadar no usa servidores propios ni recopila datos. La cobertura depende de receptores voluntarios de la red ADS-B: puede haber zonas sin señal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ajustes")
        }
    }
}

struct WatchlistView: View {
    @Environment(RadarStore.self) private var radar
    @State private var newItem = ""

    var body: some View {
        @Bindable var radar = radar
        Form {
            Section {
                HStack {
                    TextField("Matrícula, vuelo o hex (ej. CC-BGA)", text: $newItem)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Agregar", action: add).disabled(newItem.count < 2)
                }
            } footer: { Text("Recibirás una notificación cuando alguno de estos aviones aparezca en la red. Se revisa cada minuto mientras la app está abierta.") }
            Section("Vigilando") {
                ForEach(radar.watchlist) { w in
                    HStack {
                        Label(w.query, systemImage: "star.fill")
                        Spacer()
                        if radar.watchHits.values.contains(where: { [$0.registration, $0.callsign, $0.hex.uppercased()].compactMap { $0?.uppercased() }.contains(w.query.uppercased()) }) {
                            Text("En el aire").font(.caption.bold()).foregroundStyle(.green)
                        }
                    }
                }
                .onDelete { radar.watchlist.remove(atOffsets: $0) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vigilancia")
    }

    private func add() {
        let q = newItem.trimmingCharacters(in: .whitespaces).uppercased()
        guard q.count >= 2, !radar.watchlist.contains(where: { $0.query == q }) else { return }
        Notifier.requestAuth()
        radar.watchlist.append(WatchItem(query: q))
        newItem = ""
    }
}


// MARK: - OpenSky (cupo y cuenta gratuita)

struct OpenSkySection: View {
    @Environment(RadarStore.self) private var radar
    @State private var os = OpenSkyClient.shared
    @State private var id = ""
    @State private var secret = ""
    @State private var editing = false

    var body: some View {
        Section {
            LabeledContent("Aviones ADS-B comunitario", value: "\(radar.adsbCount)")
            LabeledContent("Aviones extra de OpenSky", value: "\(radar.openSkyExtra)")
            LabeledContent("Cupo OpenSky hoy", value: "\(os.usedToday) de \(os.dailyBudget) créditos")
            if let e = os.lastError { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption) }
            if os.hasAccount && !editing {
                LabeledContent("Cuenta", value: os.clientID)
                Button("Quitar cuenta", role: .destructive) { os.clearCredentials() }
            } else if editing {
                TextField("Client ID", text: $id)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Client secret", text: $secret)
                HStack {
                    Button("Cancelar") { editing = false; id = ""; secret = "" }
                    Spacer()
                    Button("Guardar") { os.setCredentials(id: id, secret: secret); editing = false; id = ""; secret = "" }
                        .disabled(id.isEmpty || secret.isEmpty)
                }
            } else {
                Button("Conectar cuenta gratuita de OpenSky") { editing = true }
            }
        } header: {
            Text("OpenSky Network")
        } footer: {
            Text("Sin cuenta: 400 créditos al día (la app los reparte para que duren). Con una cuenta gratuita: 4.000 créditos y además la trayectoria de los aviones que solo ve OpenSky. Para obtenerla: crea una cuenta en opensky-network.org → Account → API Client → descarga credentials.json y copia aquí el client ID y el secret. Se guardan en el llavero del dispositivo.")
        }
    }
}
