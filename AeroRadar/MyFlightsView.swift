import SwiftUI
import MapKit
import Charts

struct MyFlightsView: View {
    @Environment(MyFlightsStore.self) private var store
    @Environment(RadarStore.self) private var radar
    let goToRadar: () -> Void
    @State private var showAdd = false
    @State private var section = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $section) {
                        Text("Próximos").tag(0); Text("Historial").tag(1); Text("Pasaporte").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    switch section {
                    case 0:
                        if store.upcoming.isEmpty { empty } else {
                            ForEach(store.upcoming) { f in NavigationLink(value: f.id) { FlightCard(flight: f) }.buttonStyle(.plain) }
                        }
                    case 1:
                        if store.past.isEmpty {
                            ContentUnavailableView("Sin historial", systemImage: "clock", description: Text("Aquí quedarán tus vuelos realizados."))
                        } else {
                            ForEach(store.past) { f in NavigationLink(value: f.id) { FlightCard(flight: f) }.buttonStyle(.plain) }
                        }
                    default:
                        PassportView()
                    }
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Mis vuelos")
            .navigationDestination(for: UUID.self) { id in
                if let f = store.flights.first(where: { $0.id == id }) { MyFlightDetail(flight: f, goToRadar: goToRadar) }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Label("Agregar vuelo", systemImage: "plus") }
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showAdd) { AddFlightView() }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "airplane.departure").font(.system(size: 54)).foregroundStyle(.orange.gradient)
            Text("Sigue tus vuelos").font(.title2.bold())
            Text("Agrega un número de vuelo y AeroRadar lo seguirá en vivo: te avisará cuando despegue y aterrice, te mostrará el avión en el mapa y la hora estimada de llegada.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { showAdd = true } label: { Label("Agregar vuelo", systemImage: "plus").padding(.horizontal) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Tarjeta estilo pase de abordar

struct FlightCard: View {
    @Environment(Prefs.self) private var prefs
    let flight: MyFlight

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(flight.number).font(.headline.monospaced())
                Text(flight.airline ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(flight.phase.label)
                    .font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(flight.phase.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(flight.phase.color)
            }
            HStack(alignment: .center) {
                end(flight.origin, time: flight.takeoffAt ?? flight.departure, align: .leading)
                Spacer()
                VStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.secondary.opacity(0.25)).frame(height: 3)
                            Capsule().fill(flight.phase.color).frame(width: g.size.width * flight.progress, height: 3)
                            Image(systemName: "airplane").foregroundStyle(flight.phase.color)
                                .offset(x: max(0, g.size.width * flight.progress - 10), y: 0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)
                    Text(flight.distanceKm > 0 ? prefs.distance(flight.distanceKm) : "").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 220)
                Spacer()
                end(flight.destination, time: flight.landedAt ?? flight.estimatedArrival, align: .trailing)
            }
            HStack {
                Label(countdown, systemImage: "calendar").font(.caption)
                Spacer()
                if !flight.gate.isEmpty { Label("Puerta \(flight.gate)", systemImage: "door.left.hand.open").font(.caption) }
                if !flight.seat.isEmpty { Label(flight.seat, systemImage: "carseat.right").font(.caption) }
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [flight.phase.color.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08)))
    }

    private var countdown: String {
        if flight.phase == .airborne, let eta = flight.estimatedArrival {
            return "Llega \(eta.formatted(.relative(presentation: .named)))"
        }
        if flight.phase == .landed { return flight.date.formatted(date: .abbreviated, time: .omitted) }
        let ref = flight.departure ?? flight.date
        return ref.formatted(date: .abbreviated, time: flight.departure == nil ? .omitted : .shortened) + " · " + ref.formatted(.relative(presentation: .named))
    }

    private func end(_ ap: RouteAirport?, time: Date?, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(ap?.code ?? "???").font(.system(size: 34, weight: .heavy, design: .rounded))
            Text(ap?.city ?? ap?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(time?.formatted(date: .omitted, time: .shortened) ?? "--:--").font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(minWidth: 80, alignment: align == .leading ? .leading : .trailing)
    }
}

// MARK: - Agregar vuelo

struct AddFlightView: View {
    @Environment(MyFlightsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var editing: MyFlight?
    @State private var f = MyFlight(number: "", date: .now)
    @State private var route: FlightRoute?
    @State private var looking = false
    @State private var notFound = false
    @State private var hasDep = false
    @State private var hasArr = false
    @State private var originCode = ""
    @State private var destCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Número de vuelo (ej. LA800, JA301)", text: $f.number)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .autocorrectionDisabled()
                            .onSubmit { Task { await lookup() } }
                        if looking { ProgressView() } else {
                            Button("Buscar") { Task { await lookup() } }.disabled(f.number.count < 3)
                        }
                    }
                    DatePicker("Fecha", selection: $f.date, displayedComponents: .date)
                } footer: {
                    if notFound { Text("No encontré la ruta de ese vuelo. Puedes ingresar los aeropuertos a mano.").foregroundStyle(.orange) }
                }
                if let r = route ?? (f.origin != nil ? FlightRoute(callsign: f.number, origin: f.origin!, destination: f.destination ?? f.origin!) : nil) {
                    Section("Ruta") {
                        HStack {
                            Text(r.origin.code).font(.title.bold())
                            Image(systemName: "arrow.right")
                            Text(r.destination.code).font(.title.bold())
                            Spacer()
                            Text(r.airlineName ?? f.airline ?? "").foregroundStyle(.secondary)
                        }
                        Text("\(r.origin.name) → \(r.destination.name)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Aeropuertos (si no se detectan)") {
                    TextField("Origen (IATA/ICAO, ej. SCL)", text: $originCode)
                    TextField("Destino (IATA/ICAO, ej. ANF)", text: $destCode)
                }
                Section("Horarios programados (opcional)") {
                    Toggle("Salida", isOn: $hasDep)
                    if hasDep { DatePicker("Hora de salida", selection: Binding(get: { f.departure ?? f.date }, set: { f.departure = $0 })) }
                    Toggle("Llegada", isOn: $hasArr)
                    if hasArr { DatePicker("Hora de llegada", selection: Binding(get: { f.arrival ?? f.date }, set: { f.arrival = $0 })) }
                }
                Section("Tu viaje") {
                    TextField("Asiento", text: $f.seat)
                    Picker("Cabina", selection: $f.cabin) {
                        ForEach(["Económica", "Premium Economy", "Business", "Primera"], id: \.self) { Text($0) }
                    }
                    TextField("Código de reserva", text: $f.confirmation)
                    TextField("Terminal", text: $f.terminal)
                    TextField("Puerta", text: $f.gate)
                    TextField("Notas", text: $f.notes, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Nuevo vuelo" : "Editar vuelo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(f.number.isEmpty) }
            }
            .onAppear {
                if let e = editing {
                    f = e; hasDep = e.departure != nil; hasArr = e.arrival != nil
                    originCode = e.origin?.code ?? ""; destCode = e.destination?.code ?? ""
                }
            }
        }
        .macSheetSize(460, 640)
    }

    private func lookup() async {
        looking = true; notFound = false
        route = await store.lookup(f.number)
        looking = false
        if let r = route {
            originCode = r.origin.code; destCode = r.destination.code
        } else { notFound = true }
    }

    private func save() {
        f.number = f.number.uppercased().replacingOccurrences(of: " ", with: "")
        if let r = route {
            f.origin = r.origin; f.destination = r.destination
            f.airline = r.airlineName; f.callsignICAO = r.callsignICAO
        }
        if let o = AirportDB.find(originCode), o.iata != f.origin?.iata { f.origin = o.asRouteAirport }
        if let d = AirportDB.find(destCode), d.iata != f.destination?.iata { f.destination = d.asRouteAirport }
        if !hasDep { f.departure = nil }
        if !hasArr { f.arrival = nil }
        if editing == nil { store.add(f) } else { store.update(f) }
        dismiss()
    }
}

// MARK: - Detalle de mi vuelo

struct MyFlightDetail: View {
    @Environment(MyFlightsStore.self) private var store
    @Environment(RadarStore.self) private var radar
    @Environment(Prefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    let flight: MyFlight
    let goToRadar: () -> Void
    @State private var edit = false
    @State private var metarO: Metar?
    @State private var metarD: Metar?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                routeMap.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 20))
                FlightCard(flight: flight)
                timeline.card()
                if metarO != nil || metarD != nil {
                    HStack(alignment: .top, spacing: 12) {
                        if let m = metarO { WeatherMini(title: flight.origin?.code ?? "", metar: m) }
                        if let m = metarD { WeatherMini(title: flight.destination?.code ?? "", metar: m) }
                    }
                }
                details.card()
                if let hex = flight.lastHex, flight.phase == .airborne || flight.phase == .taxiing {
                    Button {
                        Task {
                            if let a = try? await API.byHex(hex).first { radar.select(a); radar.follow = true; goToRadar() }
                        }
                    } label: { Label("Ver en el radar en vivo", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Button(role: .destructive) { store.delete(flight); dismiss() } label: { Label("Eliminar vuelo", systemImage: "trash") }
            }
            .padding()
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle(flight.number)
        .toolbar { Button("Editar") { edit = true } }
        .sheet(isPresented: $edit) { AddFlightView(editing: flight) }
        .task {
            if let o = flight.origin { metarO = await API.metar(o.icao) }
            if let d = flight.destination { metarD = await API.metar(d.icao) }
        }
    }

    private var routeMap: some View {
        Map(initialPosition: .automatic) {
            if let o = flight.origin, let d = flight.destination {
                MapPolyline(coordinates: Geo.greatCircle(o.coordinate, d.coordinate))
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                Marker(o.code, systemImage: "airplane.departure", coordinate: o.coordinate).tint(.green)
                Marker(d.code, systemImage: "airplane.arrival", coordinate: d.coordinate).tint(.orange)
            }
            if let c = flight.lastCoordinate, flight.phase == .airborne {
                Annotation(flight.number, coordinate: c) {
                    Image(systemName: "airplane").font(.title2.bold()).foregroundStyle(.white)
                        .rotationEffect(.degrees(Geo.bearing(c, flight.destination?.coordinate ?? c) - 90))
                        .shadow(radius: 3)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
        .allowsHitTesting(true)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            step("Programado", flight.departure.map { "Salida \($0.formatted(date: .omitted, time: .shortened))" } ?? flight.date.formatted(date: .long, time: .omitted), done: true)
            step("Despegue", flight.takeoffAt?.formatted(date: .omitted, time: .shortened) ?? "Pendiente", done: flight.takeoffAt != nil)
            step("En ruta", flight.phase == .airborne ? "\(prefs.altitude(flight.lastAltitude)) · \(prefs.speed(flight.lastSpeed))" + (flight.remainingKm.map { " · faltan \(prefs.distance($0))" } ?? "") : "—",
                 done: flight.phase == .airborne || flight.phase == .landed)
            step("Aterrizaje", flight.landedAt?.formatted(date: .omitted, time: .shortened) ?? flight.estimatedArrival.map { "Estimado \($0.formatted(date: .omitted, time: .shortened))" } ?? "Pendiente",
                 done: flight.phase == .landed, last: true)
        }
    }

    private func step(_ t: String, _ sub: String, done: Bool, last: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(done ? Color.orange : .secondary.opacity(0.3)).frame(width: 14, height: 14)
                if !last { Rectangle().fill(done ? Color.orange : .secondary.opacity(0.3)).frame(width: 2, height: 34) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.subheadline.bold())
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detalles").font(.headline)
            kv("Aerolínea", flight.airline)
            kv("Aeronave", flight.aircraftType)
            kv("Matrícula", flight.registration)
            kv("Cabina", flight.cabin)
            kv("Asiento", flight.seat)
            kv("Reserva", flight.confirmation)
            kv("Terminal", flight.terminal)
            kv("Puerta", flight.gate)
            kv("Distancia", flight.distanceKm > 0 ? prefs.distance(flight.distanceKm) : nil)
            kv("Notas", flight.notes)
            if let u = flight.updatedAt { Text("Última señal \(u.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func kv(_ k: String, _ v: String?) -> some View {
        if let v, !v.isEmpty {
            HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).textSelection(.enabled) }.font(.subheadline)
        }
    }
}

// MARK: - Pasaporte de viajero

struct PassportView: View {
    @Environment(MyFlightsStore.self) private var store
    @Environment(Prefs.self) private var prefs

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                big("\(store.flown.count)", "vuelos", "airplane")
                big(prefs.distance(store.totalKm), "recorridos", "point.topleft.down.to.point.bottomright.curvepath")
                big(String(format: "%.0f h", store.totalHours), "en el aire", "clock")
                big("\(store.airports.count)", "aeropuertos", "building.2")
                big("\(store.countries.count)", "países", "globe.americas")
                big(String(format: "%.2f×", store.totalKm / 40075), "vueltas al mundo", "arrow.trianglehead.2.clockwise.rotate.90")
            }
            if !store.flown.isEmpty {
                Map(initialPosition: .automatic) {
                    ForEach(store.flown) { f in
                        if let o = f.origin, let d = f.destination {
                            MapPolyline(coordinates: Geo.greatCircle(o.coordinate, d.coordinate)).stroke(.orange.opacity(0.8), lineWidth: 2)
                        }
                    }
                }
                .mapStyle(.standard(emphasis: .muted))
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 20))
                if !store.airlines.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Aerolíneas").font(.headline)
                        Chart(store.airlines.sorted { $0.value > $1.value }.prefix(8), id: \.key) { e in
                            BarMark(x: .value("Vuelos", e.value), y: .value("Aerolínea", e.key)).foregroundStyle(.orange.gradient)
                        }
                        .frame(height: CGFloat(min(store.airlines.count, 8)) * 32 + 20)
                    }.card()
                }
                if let l = store.longest {
                    Label("Vuelo más largo: \(l.number) \(l.origin?.code ?? "")→\(l.destination?.code ?? "") · \(prefs.distance(l.distanceKm))", systemImage: "trophy.fill")
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).card()
                }
            } else {
                Text("Tus estadísticas aparecerán cuando registres vuelos.").foregroundStyle(.secondary).padding()
            }
        }
    }

    private func big(_ v: String, _ t: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(v).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
