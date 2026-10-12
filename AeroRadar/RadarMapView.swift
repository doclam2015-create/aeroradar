import SwiftUI
import MapKit

#if os(iOS)
typealias PColor = UIColor
typealias PViewRepresentable = UIViewRepresentable
#else
typealias PColor = NSColor
typealias PViewRepresentable = NSViewRepresentable
#endif

/// Pedido de movimiento de cámara desde la interfaz (buscar, seguir, 3D…).
struct CameraRequest: Equatable {
    let id = UUID()
    var region: MKCoordinateRegion?
    var center: CLLocationCoordinate2D?
    var distance: Double = 300_000
    var heading: Double = 0
    var pitch: Double = 0
    static func == (a: CameraRequest, b: CameraRequest) -> Bool { a.id == b.id }
}

// MARK: - Anotaciones

final class PlaneAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var aircraft: Aircraft
    init(_ a: Aircraft) { aircraft = a; coordinate = a.coordinate }
    var title: String? { nil }
}

final class AirportAnnotation: NSObject, MKAnnotation {
    let airport: Airport
    init(_ a: Airport) { airport = a }
    var coordinate: CLLocationCoordinate2D { airport.coordinate }
    var title: String? { nil }
}

final class RouteEndAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let code: String
    let isOrigin: Bool
    init(_ c: CLLocationCoordinate2D, code: String, origin: Bool) { coordinate = c; self.code = code; isOrigin = origin }
    var title: String? { nil }
}

// MARK: - Imágenes de aviones (caché)

enum PlaneImages {
    private static var cache: [String: CGImage] = [:]

    /// Símbolo coloreado con sombra, renderizado una vez por combinación (color cuantizado + tamaño).
    static func image(symbol: String, color: PColor, colorKey: Int, size: CGFloat) -> CGImage? {
        let key = "\(symbol)-\(colorKey)-\(Int(size))"
        if let c = cache[key] { return c }
        let scale: CGFloat = 3
        #if os(iOS)
        let cfg = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
        guard let sym = UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = scale
        let pad: CGFloat = 4
        let img = UIGraphicsImageRenderer(size: CGSize(width: sym.size.width + pad * 2, height: sym.size.height + pad * 2), format: fmt).image { ctx in
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: UIColor.black.withAlphaComponent(0.7).cgColor)
            sym.draw(at: CGPoint(x: pad, y: pad))
        }
        let out = img.cgImage
        #else
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .bold).applying(.init(paletteColors: [color]))
        guard let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return nil }
        let pad: CGFloat = 4
        let w = sym.size.width + pad * 2, h = sym.size.height + pad * 2
        let out: CGImage? = {
            guard let ctx = CGContext(data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.scaleBy(x: scale, y: scale)
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.5, color: NSColor.black.withAlphaComponent(0.7).cgColor)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            sym.draw(in: CGRect(x: pad, y: pad, width: sym.size.width, height: sym.size.height))
            NSGraphicsContext.restoreGraphicsState()
            return ctx.makeImage()
        }()
        #endif
        if let out { cache[key] = out }
        return out
    }

    static func color(for a: Aircraft) -> (PColor, Int) {
        if a.isEmergency { return (.systemRed, -1) }
        if a.onGround { return (.systemGray, -2) }
        guard let ft = a.altitude else { return (.white, -3) }
        let bucket = Int(min(max(Double(ft), 0), 42000) / 42000 * 23)
        let f = Double(bucket) / 23
        return (PColor(hue: 0.08 + f * 0.74, saturation: 0.85, brightness: 0.98, alpha: 1), bucket)
    }
}

// MARK: - Vista de avión (capas, sin SwiftUI: rápida con cientos de aviones)

final class PlaneView: MKAnnotationView {
    static let reuseID = "plane"
    private let plane = CALayer()
    private let ring = CAShapeLayer()
    private let label = CATextLayer()
    private let star = CATextLayer()
    var onHover: ((Bool) -> Void)?
    private var lastKey = ""

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
        #if os(macOS)
        wantsLayer = true
        #endif
        let screenScale: CGFloat = 3
        plane.contentsGravity = .resizeAspect
        plane.contentsScale = screenScale
        ring.fillColor = nil
        ring.lineWidth = 2
        ring.isHidden = true
        label.fontSize = 10
        label.font = CTFontCreateWithName("SFProRounded-Bold" as CFString, 10, nil)
        label.alignmentMode = .center
        label.contentsScale = screenScale
        label.cornerRadius = 4
        label.foregroundColor = CGColor(gray: 1, alpha: 1)
        label.isHidden = true
        star.string = "★"
        star.fontSize = 9
        star.foregroundColor = CGColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        star.contentsScale = screenScale
        star.frame = CGRect(x: 30, y: 2, width: 10, height: 10)
        star.isHidden = true
        hostLayer.addSublayer(ring)
        hostLayer.addSublayer(plane)
        hostLayer.addSublayer(label)
        hostLayer.addSublayer(star)
        #if os(iOS)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        #endif
    }
    required init?(coder: NSCoder) { fatalError() }

    private var hostLayer: CALayer {
        #if os(iOS)
        return layer
        #else
        return layer!
        #endif
    }

    func configure(_ a: Aircraft, selected: Bool, mapHeading: Double, scale: CGFloat, showLabel: Bool, watched: Bool) {
        let (color, ck) = PlaneImages.color(for: a)
        let base = a.sizeClass * (selected ? 1.35 : scale)
        let symbol = a.isHelicopter ? "fanblades.fill" : "airplane"
        let key = "\(symbol)\(ck)\(Int(base))\(selected)"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if key != lastKey, let img = PlaneImages.image(symbol: symbol, color: selected ? .white : color, colorKey: selected ? 99 : ck, size: base) {
            lastKey = key
            plane.contents = img
            let w = CGFloat(img.width) / 3, h = CGFloat(img.height) / 3
            plane.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        }
        plane.position = CGPoint(x: 20, y: 20)
        var deg = (a.track ?? 0) - mapHeading - (a.isHelicopter ? 0 : 90)
        #if os(macOS)
        deg = -deg
        #endif
        plane.setAffineTransform(CGAffineTransform(rotationAngle: deg * .pi / 180))

        let showRing = selected || a.isEmergency
        ring.isHidden = !showRing
        if showRing {
            let r = base * 1.05
            ring.path = CGPath(ellipseIn: CGRect(x: 20 - r, y: 20 - r, width: r * 2, height: r * 2), transform: nil)
            ring.strokeColor = a.isEmergency ? CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1) : CGColor(gray: 1, alpha: 0.9)
            if ring.animation(forKey: "pulse") == nil {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 1; anim.toValue = 0.2; anim.duration = 0.9
                anim.autoreverses = true; anim.repeatCount = .infinity
                ring.add(anim, forKey: "pulse")
            }
        } else {
            ring.removeAllAnimations()
        }

        label.isHidden = !showLabel
        if showLabel {
            let text = a.displayName
            label.string = text
            label.backgroundColor = selected ? CGColor(red: 1, green: 0.58, blue: 0, alpha: 1) : CGColor(gray: 0, alpha: 0.6)
            let w = CGFloat(text.count) * 6.4 + 10
            #if os(iOS)
            label.frame = CGRect(x: 20 - w / 2, y: 20 + base / 2 + 4, width: w, height: 14)
            #else
            label.frame = CGRect(x: 20 - w / 2, y: 20 - base / 2 - 18, width: w, height: 14)
            #endif
        }
        star.isHidden = !watched
        zPriority = selected ? .max : (a.isEmergency ? .defaultSelected : .defaultUnselected)
        CATransaction.commit()
    }

    #if os(iOS)
    @objc private func hovered(_ g: UIHoverGestureRecognizer) {
        switch g.state {
        case .began: onHover?(true)
        case .ended, .cancelled: onHover?(false)
        default: break
        }
    }
    #else
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds.insetBy(dx: 6, dy: 6), options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    #endif

    override func prepareForReuse() {
        super.prepareForReuse()
        onHover = nil
        ring.removeAllAnimations()
    }
}

final class AirportView: MKAnnotationView {
    static let reuseID = "airport"
    private let dot = CALayer()
    private let text = CATextLayer()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        canShowCallout = false
        displayPriority = .defaultLow
        #if os(macOS)
        wantsLayer = true
        #endif
        let host: CALayer = {
            #if os(iOS)
            return layer
            #else
            return layer!
            #endif
        }()
        dot.frame = CGRect(x: 3, y: 3, width: 10, height: 10)
        dot.cornerRadius = 5
        dot.backgroundColor = CGColor(red: 0.35, green: 0.35, blue: 0.85, alpha: 0.9)
        dot.borderColor = CGColor(gray: 1, alpha: 1)
        dot.borderWidth = 1.5
        text.fontSize = 9
        text.foregroundColor = CGColor(gray: 1, alpha: 0.85)
        text.contentsScale = 3
        text.alignmentMode = .center
        host.addSublayer(dot)
        host.addSublayer(text)
        zPriority = .min
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ a: Airport, showCode: Bool) {
        text.isHidden = !showCode
        text.string = a.iata
        #if os(iOS)
        text.frame = CGRect(x: -12, y: 16, width: 40, height: 12)
        #else
        text.frame = CGRect(x: -12, y: -12, width: 40, height: 12)
        #endif
    }
}

final class RouteEndView: MKAnnotationView {
    static let reuseID = "routeEnd"
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        displayPriority = .required
        #if os(macOS)
        wantsLayer = true
        #endif
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(origin: Bool) {
        #if os(iOS)
        let l = layer
        #else
        let l = layer!
        #endif
        l.cornerRadius = 7
        l.backgroundColor = origin ? CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1) : CGColor(red: 1, green: 0.58, blue: 0, alpha: 1)
        l.borderColor = CGColor(gray: 1, alpha: 1)
        l.borderWidth = 2
    }
}

// MARK: - Representable

struct RadarMapView: PViewRepresentable {
    let radar: RadarStore
    let prefs: Prefs

    func makeCoordinator() -> RadarMapCoordinator { RadarMapCoordinator(radar: radar, prefs: prefs) }

    #if os(iOS)
    func makeUIView(context: Context) -> MKMapView { context.coordinator.makeMap() }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.sync() }
    #else
    func makeNSView(context: Context) -> MKMapView { context.coordinator.makeMap() }
    func updateNSView(_ map: MKMapView, context: Context) { context.coordinator.sync() }
    #endif
}

@MainActor
final class RadarMapCoordinator: NSObject, MKMapViewDelegate {
    let radar: RadarStore
    let prefs: Prefs
    weak var map: MKMapView?

    private var planes: [String: PlaneAnnotation] = [:]
    private var airports: [String: AirportAnnotation] = [:]
    private var routeEnds: [RouteEndAnnotation] = []
    private var selectedTrail: MKPolyline?
    private var selectedTrailColors: [PColor] = []
    private var routeLine: MKPolyline?
    private var otherTrails: MKMultiPolyline?
    private var night: [MKPolygon] = []

    private var lastVersion = -1
    private var lastSelected: String?
    private var lastLook = ""
    private var lastCamera: UUID?
    private var lastRouteKey = ""
    private var lastTrailCount = -1
    private var lastWasCockpit = false
    private var lastFollow = false
    /// Mientras la cámara vuela a un destino no se re-emiten movimientos (si no, la animación nunca termina)
    private var flyingUntil = Date.distantPast
    private var interacting = false
    private var programmatic = false
    private var timer: Timer?
    private var nightUpdated = Date.distantPast

    init(radar: RadarStore, prefs: Prefs) { self.radar = radar; self.prefs = prefs }

    func makeMap() -> MKMapView {
        let m = MKMapView()
        m.delegate = self
        m.showsUserLocation = true
        m.showsCompass = true
        m.showsScale = true
        m.isPitchEnabled = true
        m.isRotateEnabled = true
        #if os(iOS)
        // Brújula y ubicación bajo la barra superior (los controles nativos quedarían tapados)
        m.showsCompass = false
        let track = MKUserTrackingButton(mapView: m)
        let compass = MKCompassButton(mapView: m)
        compass.compassVisibility = .adaptive
        for v in [track, compass] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; m.addSubview(v) }
        track.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.85)
        track.layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            track.trailingAnchor.constraint(equalTo: m.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            track.topAnchor.constraint(equalTo: m.safeAreaLayoutGuide.topAnchor, constant: 64),
            compass.centerXAnchor.constraint(equalTo: track.centerXAnchor),
            compass.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 10),
        ])
        #else
        m.showsZoomControls = true
        m.showsPitchControl = true
        #endif
        m.register(PlaneView.self, forAnnotationViewWithReuseIdentifier: PlaneView.reuseID)
        m.register(AirportView.self, forAnnotationViewWithReuseIdentifier: AirportView.reuseID)
        m.register(RouteEndView.self, forAnnotationViewWithReuseIdentifier: RouteEndView.reuseID)
        m.setRegion(MKCoordinateRegion(center: radar.center, span: radar.span), animated: false)
        map = m
        applyLook()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        return m
    }

    deinit { timer?.invalidate() }

    // MARK: Sincronización (solo trabaja si algo cambió)

    func sync() {
        guard let map else { return }
        applyLook()
        if let req = radar.cameraRequest, req.id != lastCamera {
            lastCamera = req.id
            apply(req, on: map)
        }
        if radar.cockpit != lastWasCockpit || radar.follow != lastFollow {
            let starting = (radar.cockpit && !lastWasCockpit) || (radar.follow && !lastFollow)
            lastWasCockpit = radar.cockpit
            lastFollow = radar.follow
            if starting { followCamera(animated: true, initial: true) }
        }
        let selChanged = radar.selectedHex != lastSelected
        if radar.dataVersion != lastVersion || selChanged {
            lastVersion = radar.dataVersion
            syncPlanes(on: map)
        }
        if selChanged {
            let old = lastSelected
            lastSelected = radar.selectedHex
            if let o = old, let ann = planes[o] { refreshView(ann) }
            if let h = radar.selectedHex, let ann = planes[h] {
                refreshView(ann)
                if !map.selectedAnnotations.contains(where: { $0 === ann }) { map.selectAnnotation(ann, animated: false) }
            } else {
                map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: false) }
            }
        }
        syncSelectionOverlays(on: map)
        syncTrails(on: map)
        syncNight(on: map)
    }

    private func applyLook() {
        guard let map else { return }
        let look = radar.cockpit ? "cockpit" : prefs.mapLook.rawValue
        guard look != lastLook else { return }
        lastLook = look
        let cfg: MKMapConfiguration
        switch look {
        case "cockpit", "hybrid":
            let h = MKHybridMapConfiguration(elevationStyle: .realistic)
            h.pointOfInterestFilter = .excludingAll
            cfg = h
        case "satellite": cfg = MKImageryMapConfiguration(elevationStyle: .realistic)
        case "standard":
            let s = MKStandardMapConfiguration(elevationStyle: .realistic)
            s.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
            cfg = s
        default:
            let s = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
            s.pointOfInterestFilter = .excludingAll
            cfg = s
        }
        map.preferredConfiguration = cfg
        #if os(iOS)
        map.overrideUserInterfaceStyle = prefs.forceDark ? .dark : .unspecified
        #else
        map.appearance = prefs.forceDark ? NSAppearance(named: .darkAqua) : nil
        #endif
    }

    private var iconScale: CGFloat {
        let d = radar.span.latitudeDelta
        return d > 40 ? 0.45 : d > 15 ? 0.55 : d > 6 ? 0.65 : d > 2 ? 0.8 : 1
    }
    private var labelsOn: Bool {
        prefs.showLabels && (radar.span.latitudeDelta < 0.8 || (radar.span.latitudeDelta < 3 && radar.visible.count < 60))
    }

    private func syncPlanes(on map: MKMapView) {
        let vis = radar.visible
        var keep = Set<String>()
        var toAdd: [PlaneAnnotation] = []
        let now = Date()
        let rect = map.visibleMapRect.insetBy(dx: -map.visibleMapRect.width * 0.2, dy: -map.visibleMapRect.height * 0.2)
        for a in vis {
            keep.insert(a.hex)
            if let ann = planes[a.hex] {
                ann.aircraft = a
                let c = prefs.smoothMotion ? a.estimatedPosition(at: now) : a.coordinate
                if rect.contains(MKMapPoint(c)) && !interacting {
                    move(ann, to: c, duration: 0.6)
                } else {
                    ann.coordinate = c
                }
                refreshView(ann)
            } else {
                let ann = PlaneAnnotation(a)
                planes[a.hex] = ann
                toAdd.append(ann)
            }
        }
        let gone = planes.filter { !keep.contains($0.key) }
        if !gone.isEmpty {
            map.removeAnnotations(Array(gone.values))
            gone.keys.forEach { planes[$0] = nil }
        }
        if !toAdd.isEmpty { map.addAnnotations(toAdd) }
    }

    private func refreshView(_ ann: PlaneAnnotation) {
        guard let v = map?.view(for: ann) as? PlaneView else { return }
        let a = ann.aircraft
        v.configure(a, selected: a.hex == radar.selectedHex, mapHeading: map?.camera.heading ?? 0, scale: iconScale,
                    showLabel: a.hex == radar.selectedHex || labelsOn, watched: radar.isWatched(a))
    }

    private func move(_ ann: PlaneAnnotation, to c: CLLocationCoordinate2D, duration: Double) {
        #if os(iOS)
        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            ann.coordinate = c
        }
        #else
        ann.coordinate = c
        #endif
    }

    // MARK: Movimiento fluido y seguimiento (cada segundo, fuera de SwiftUI)

    private func tick() {
        guard let map, !interacting else { return }
        if radar.follow { followCamera(animated: true) }
        guard prefs.smoothMotion, radar.span.latitudeDelta < 15 || radar.follow else { return }
        let now = Date()
        let rect = map.visibleMapRect
        for ann in planes.values {
            let c = ann.aircraft.estimatedPosition(at: now)
            guard rect.contains(MKMapPoint(c)) else { ann.coordinate = c; continue }
            move(ann, to: c, duration: 1)
        }
    }

    private func followCamera(animated: Bool, initial: Bool = false) {
        guard let map, radar.follow, let a = radar.selected else { return }
        guard initial || Date() >= flyingUntil else { return }
        if initial { flyingUntil = Date().addingTimeInterval(3) }
        let c = planes[a.hex]?.coordinate ?? a.coordinate
        let cam: MKMapCamera
        if radar.cockpit {
            let altM = Double(a.altitude ?? 3000) * 0.3048
            cam = MKMapCamera(lookingAtCenter: c, fromDistance: min(max(altM * 2.2, 3000), 40_000), pitch: 70, heading: a.track ?? 0)
        } else {
            cam = MKMapCamera(lookingAtCenter: c, fromDistance: min(map.camera.centerCoordinateDistance, 1_500_000),
                              pitch: map.camera.pitch, heading: map.camera.heading)
        }
        programmatic = true
        map.setCamera(cam, animated: animated)
    }

    private func apply(_ req: CameraRequest, on map: MKMapView) {
        programmatic = true
        flyingUntil = Date().addingTimeInterval(2)
        if let r = req.region {
            map.setRegion(map.regionThatFits(r), animated: true)
        } else if let c = req.center {
            map.setCamera(MKMapCamera(lookingAtCenter: c, fromDistance: req.distance, pitch: req.pitch, heading: req.heading), animated: true)
        }
    }

    // MARK: Capas (trayectorias, ruta, noche)

    private func syncSelectionOverlays(on map: MKMapView) {
        guard let a = radar.selected else {
            if let t = selectedTrail { map.removeOverlay(t); selectedTrail = nil; lastTrailCount = -1 }
            if let r = routeLine { map.removeOverlay(r); routeLine = nil }
            if !routeEnds.isEmpty { map.removeAnnotations(routeEnds); routeEnds = [] }
            lastRouteKey = ""
            return
        }
        let trail = radar.fullTrail(for: a.hex)
        if trail.count != lastTrailCount || lastSelected != a.hex {
            lastTrailCount = trail.count
            if let t = selectedTrail { map.removeOverlay(t) }
            selectedTrail = nil
            if trail.count > 1 {
                var coords = trail.map(\.coordinate) + [a.coordinate]
                let t = MKPolyline(coordinates: &coords, count: coords.count)
                selectedTrailColors = trail.map { p in
                    let (c, _) = PlaneImages.color(for: { var x = a; x.altitude = p.alt; x.onGround = p.alt == 0; return x }())
                    return c
                } + [PlaneImages.color(for: a).0]
                selectedTrail = t
                map.addOverlay(t, level: .aboveRoads)
            }
        }
        let routeKey = "\(a.hex)-\(radar.selectedRoute?.destination.icao ?? "")-\(Int(a.lat * 20))-\(Int(a.lon * 20))"
        if routeKey != lastRouteKey {
            lastRouteKey = routeKey
            if let r = routeLine { map.removeOverlay(r) }
            routeLine = nil
            map.removeAnnotations(routeEnds); routeEnds = []
            if let r = radar.selectedRoute {
                var coords = Geo.greatCircle(a.coordinate, r.destination.coordinate)
                let line = MKPolyline(coordinates: &coords, count: coords.count)
                routeLine = line
                map.addOverlay(line, level: .aboveRoads)
                routeEnds = [RouteEndAnnotation(r.origin.coordinate, code: r.origin.code, origin: true),
                             RouteEndAnnotation(r.destination.coordinate, code: r.destination.code, origin: false)]
                map.addAnnotations(routeEnds)
            }
        }
    }

    private var lastTrailsVersion = -1
    private func syncTrails(on map: MKMapView) {
        let show = prefs.showTrails && radar.span.latitudeDelta < 5
        guard radar.dataVersion != lastTrailsVersion || (!show && otherTrails != nil) else { return }
        lastTrailsVersion = radar.dataVersion
        if let o = otherTrails { map.removeOverlay(o); otherTrails = nil }
        guard show else { return }
        let lines: [MKPolyline] = radar.visible.compactMap { a in
            guard a.hex != radar.selectedHex, let t = radar.trails[a.hex], t.count > 1 else { return nil }
            var coords = t.map(\.coordinate) + [a.coordinate]
            return MKPolyline(coordinates: &coords, count: coords.count)
        }
        guard !lines.isEmpty else { return }
        let multi = MKMultiPolyline(lines)
        otherTrails = multi
        map.addOverlay(multi, level: .aboveRoads)
    }

    private func syncNight(on map: MKMapView) {
        if !prefs.showTerminator {
            if !night.isEmpty { map.removeOverlays(night); night = [] }
            return
        }
        guard night.isEmpty || Date().timeIntervalSince(nightUpdated) > 120 else { return }
        nightUpdated = .now
        map.removeOverlays(night)
        night = Terminator.nightPolygons(at: .now).map { pts in
            var p = pts
            return MKPolygon(coordinates: &p, count: p.count)
        }
        map.addOverlays(night, level: .aboveRoads)
    }

    private func syncAirports(on map: MKMapView) {
        let span = map.region.span.latitudeDelta
        var wanted: [Airport] = []
        if prefs.showAirports && span < 14 {
            wanted = AirportDB.inRegion(center: map.region.center, latDelta: span, lonDelta: map.region.span.longitudeDelta, largeOnly: span > 4)
        }
        let keys = Set(wanted.map(\.icao))
        let gone = airports.filter { !keys.contains($0.key) }
        if !gone.isEmpty { map.removeAnnotations(Array(gone.values)); gone.keys.forEach { airports[$0] = nil } }
        let new = wanted.filter { airports[$0.icao] == nil }.map { a -> AirportAnnotation in
            let ann = AirportAnnotation(a); airports[a.icao] = ann; return ann
        }
        if !new.isEmpty { map.addAnnotations(new) }
        for ann in airports.values { (map.view(for: ann) as? AirportView)?.configure(ann.airport, showCode: span < 6) }
    }

    // MARK: Delegado

    nonisolated func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        MainActor.assumeIsolated {
            if let p = annotation as? PlaneAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: PlaneView.reuseID, for: p) as! PlaneView
                let hex = p.aircraft.hex
                v.onHover = { [weak self] inside in self?.hover(hex, inside) }
                let a = p.aircraft
                v.configure(a, selected: a.hex == radar.selectedHex, mapHeading: mapView.camera.heading, scale: iconScale,
                            showLabel: a.hex == radar.selectedHex || labelsOn, watched: radar.isWatched(a))
                return v
            }
            if let ap = annotation as? AirportAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: AirportView.reuseID, for: ap) as! AirportView
                v.configure(ap.airport, showCode: mapView.region.span.latitudeDelta < 6)
                return v
            }
            if let r = annotation as? RouteEndAnnotation {
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: RouteEndView.reuseID, for: r) as! RouteEndView
                v.configure(origin: r.isOrigin)
                return v
            }
            return nil
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        MainActor.assumeIsolated {
            if let m = overlay as? MKMultiPolyline {
                let r = MKMultiPolylineRenderer(multiPolyline: m)
                r.strokeColor = PColor.white.withAlphaComponent(0.35)
                r.lineWidth = 1.3
                return r
            }
            if let p = overlay as? MKPolyline, p === selectedTrail {
                let r = MKGradientPolylineRenderer(polyline: p)
                let n = max(selectedTrailColors.count - 1, 1)
                r.setColors(selectedTrailColors, locations: selectedTrailColors.indices.map { CGFloat($0) / CGFloat(n) })
                r.lineWidth = 3.5
                r.lineCap = .round
                return r
            }
            if let p = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: p)
                r.strokeColor = PColor.white.withAlphaComponent(0.6)
                r.lineWidth = 2
                r.lineDashPattern = [6, 6]
                return r
            }
            if let g = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: g)
                r.fillColor = PColor.black.withAlphaComponent(0.28)
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        MainActor.assumeIsolated {
            guard let p = view.annotation as? PlaneAnnotation else {
                if !(view.annotation is MKUserLocation) { mapView.deselectAnnotation(view.annotation, animated: false) }
                return
            }
            if radar.selectedHex != p.aircraft.hex { radar.select(p.aircraft) }
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        MainActor.assumeIsolated {
            guard let p = view.annotation as? PlaneAnnotation, radar.selectedHex == p.aircraft.hex, planes[p.aircraft.hex] != nil else { return }
            // Toque en el mapa vacío: cierra la selección (como Flightradar24)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.map?.selectedAnnotations.isEmpty ?? true, self.radar.selectedHex == p.aircraft.hex else { return }
                self.radar.select(nil)
            }
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        MainActor.assumeIsolated {
            if !programmatic { interacting = true }
            radar.hoverHex = nil
        }
    }

    nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        MainActor.assumeIsolated {
            interacting = false
            programmatic = false
            radar.updateRegion(mapView.region, heading: mapView.camera.heading)
            syncAirports(on: mapView)
            // Rotación, tamaño y etiquetas dependen del zoom y rumbo: solo se tocan las vistas en pantalla
            for ann in planes.values where mapView.view(for: ann) != nil { refreshView(ann) }
        }
    }

    private func hover(_ hex: String, _ inside: Bool) {
        if inside, let map, let ann = planes[hex] {
            var p = map.convert(ann.coordinate, toPointTo: map)
            #if os(macOS)
            if !map.isFlipped { p.y = map.bounds.height - p.y }
            #endif
            radar.hoverPoint = p
        }
        radar.hover(hex, inside)
    }
}
