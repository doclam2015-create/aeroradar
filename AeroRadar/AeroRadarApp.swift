import SwiftUI

@main
struct AeroRadarApp: App {
    @State private var prefs: Prefs
    @State private var radar: RadarStore
    @State private var myFlights = MyFlightsStore()
    @State private var location = LocationProvider()

    init() {
        let p = Prefs()
        _prefs = State(initialValue: p)
        _radar = State(initialValue: RadarStore(prefs: p))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prefs)
                .environment(radar)
                .environment(myFlights)
                .environment(location)
                .tint(.orange)
                .task {
                    let r = radar
                    myFlights.localLookup = { cs in r.aircraft.values.first { $0.callsign?.uppercased() == cs.uppercased() } }
                    radar.start()
                    myFlights.start()
                    location.request()
                }
        }
        #if os(macOS)
        .defaultSize(width: 1300, height: 850)
        .commands {
            CommandMenu("Radar") {
                Button("Actualizar ahora") { Task { await radar.refresh() } }.keyboardShortcut("r")
                Button("Dejar de seguir") { radar.follow = false; radar.cockpit = false }.keyboardShortcut(.escape, modifiers: [])
            }
        }
        #endif
    }
}

enum AppTab: Hashable { case radar, myFlights, airports, stats, settings }

struct RootView: View {
    @State private var tab: AppTab = .radar
    @Environment(RadarStore.self) private var radar

    var body: some View {
        TabView(selection: $tab) {
            Tab("Radar", systemImage: "dot.radiowaves.left.and.right", value: .radar) { RadarView() }
            Tab("Mis vuelos", systemImage: "airplane.departure", value: .myFlights) { MyFlightsView(goToRadar: { tab = .radar }) }
            Tab("Aeropuertos", systemImage: "building.2", value: .airports) { AirportsView(goToRadar: { tab = .radar }) }
            Tab("Estadísticas", systemImage: "chart.bar.xaxis", value: .stats) { StatsView() }
            Tab("Ajustes", systemImage: "gearshape", value: .settings) { SettingsView() }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
