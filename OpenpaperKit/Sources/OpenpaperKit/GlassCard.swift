import SwiftUI
#if os(macOS)
import AppKit
import GlassBridge

struct NativeGlassContainer<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content
    func makeNSView(context: Context) -> CardGlassContainerView {
        let container = CardGlassContainerView(), host = NSHostingView(rootView: content())
        container.spacing = 0
        container.contentView = host
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor), host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor), host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
    func updateNSView(_ container: CardGlassContainerView, context: Context) {
        (container.contentView as? NSHostingView<Content>)?.rootView = content()
        container.material.scheduleAdjustment()
    }
    static func dismantleNSView(_ container: CardGlassContainerView, coordinator: ()) { container.material.stopObserving() }
}

struct ClearCardGlass: NSViewRepresentable {
    var reducedTransparency: Bool
    var decoration: AnyView = AnyView(EmptyView())
    func makeNSView(context: Context) -> CardGlassView {
        let view = CardGlassView(); view.contentView = NSHostingView(rootView: decoration); return view
    }
    func updateNSView(_ view: CardGlassView, context: Context) {
        (view.contentView as? NSHostingView<AnyView>)?.rootView = decoration
        view.reducedTransparency = reducedTransparency; view.scheduleAdjustment()
    }
    static func dismantleNSView(_ view: CardGlassView, coordinator: ()) { view.stopObserving() }
}

@MainActor final class CardGlassView: NSGlassEffectView {
    var reducedTransparency = false
    private lazy var material = GlassMaterialAdjustment(view: self)
    private var group: CardGlassContainerView? {
        var parent = superview
        while let view = parent { if let group = view as? CardGlassContainerView { return group }; parent = view.superview }
        return nil
    }
    var adjustedFilterCount: Int { group?.material.adjustedFilterCount ?? material.adjustedFilterCount }
    var observerCount: Int { material.observerCount }
    init() {
        super.init(frame: .zero)
        style = .clear; cornerRadius = 24; effectIsInteractive = true
        contentView = NSView(); setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); scheduleAdjustment() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); scheduleAdjustment() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); material.attach(); scheduleAdjustment() }
    func scheduleAdjustment() {
        if let group { material.stopObserving(); group.material.scheduleAdjustment() }
        else { material.reducedTransparency = reducedTransparency; material.scheduleAdjustment() }
    }
    func adjustMaterial() {
        if let group { group.material.adjustMaterial() }
        else { material.reducedTransparency = reducedTransparency; material.adjustMaterial() }
    }
    func stopObserving() { material.stopObserving(); group?.material.scheduleAdjustment() }
}

@MainActor final class CardGlassContainerView: NSGlassEffectContainerView {
    lazy var material = GlassMaterialAdjustment(view: self)
    override func layout() { super.layout(); material.scheduleAdjustment() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); material.scheduleAdjustment() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); material.attach() }
    var permitsAdjustment: Bool {
        func glass(_ view: NSView) -> [NSGlassEffectView] { (view as? NSGlassEffectView).map { [$0] } ?? view.subviews.flatMap(glass) }
        let effects = contentView.map(glass) ?? []
        return !effects.isEmpty && effects.allSatisfy { ($0 as? CardGlassView).map { $0.style == .clear && !$0.reducedTransparency } == true }
    }
}

@MainActor final class GlassMaterialAdjustment {
    private weak var view: NSView?
    var reducedTransparency = false
    private var observations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var originals: [ObjectIdentifier: (NSObject, [String: Any])] = [:]
    private var pending: Task<Void, Never>?
    private var adjusting = false
    private var stopped = true
    private var windowObservations: [NSObjectProtocol] = []
    private(set) var adjustedFilterCount = 0
    var observerCount: Int { observations.values.reduce(0) { $0 + $1.count } }
    init(view: NSView) { self.view = view }
    func attach() {
        stopObserving()
        guard let window = view?.window else { return }
        stopped = false
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            windowObservations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleAdjustment() }
            })
        }
        scheduleAdjustment()
    }
    func scheduleAdjustment() {
        guard !stopped, view?.window != nil, !adjusting, pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pending = nil; adjustMaterial()
        }
    }
    func adjustMaterial() {
        guard !adjusting else { return }; adjusting = true
        defer { adjusting = false }
        guard let view else { return }
        let group = view as? CardGlassContainerView
        if reducedTransparency || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || group?.permitsAdjustment == false { restore(); return }
        var layers: [CALayer] = []
        // A native container owns the shared card material; hosted content and its public glass stay untouched.
        var excluded: Set<ObjectIdentifier> = []
        func exclude(_ view: NSView) { if let layer = view.layer { excluded.insert(ObjectIdentifier(layer)) }; view.subviews.forEach(exclude) }
        let hostedContent = group?.contentView ?? (view as? NSGlassEffectView)?.contentView
        if let content = hostedContent { exclude(content) }
        func appendLayer(_ layer: CALayer) {
            guard !excluded.contains(ObjectIdentifier(layer)) else { return }
            layers.append(layer); (layer.sublayers ?? []).forEach(appendLayer)
        }
        func visit(_ candidate: NSView) {
            guard candidate !== hostedContent else { return }
            if let layer = candidate.layer { appendLayer(layer) }; candidate.subviews.forEach(visit)
        }
        visit(view)
        var seen: Set<ObjectIdentifier> = []
        var liveFilters: Set<ObjectIdentifier> = []
        adjustedFilterCount = 0
        for layer in layers {
            let identifier = ObjectIdentifier(layer)
            guard seen.insert(identifier).inserted else { continue }
            if observations[identifier] == nil {
                observations[identifier] = [
                    layer.observe(\.filters) { [weak self] _, _ in Task { @MainActor in self?.scheduleAdjustment() } },
                    layer.observe(\.sublayers) { [weak self] _, _ in Task { @MainActor in self?.scheduleAdjustment() } }
                ]
            }
            for case let filter as NSObject in layer.filters ?? [] {
                let id = ObjectIdentifier(filter); liveFilters.insert(id)
                // Private filter keys are runtime-verified; every other material parameter stays untouched.
                guard let values = OPReadBlurValues(filter) else {
                    if let saved = originals.removeValue(forKey: id) { _ = OPWriteBlurValues(saved.0, saved.1) }
                    continue
                }
                if originals[id] == nil { originals[id] = (filter, values) }
                let zeros = values.mapValues { _ in NSNumber(value: 0) }
                if values.values.allSatisfy({ ($0 as? NSNumber)?.doubleValue == 0 }) || OPWriteBlurValues(filter, zeros) { adjustedFilterCount += 1 }
                else { if let saved = originals.removeValue(forKey: id) { _ = OPWriteBlurValues(saved.0, saved.1) } }
            }
        }
        for id in observations.keys where !seen.contains(id) { observations.removeValue(forKey: id)?.forEach { $0.invalidate() } }
        originals = originals.filter { liveFilters.contains($0.key) }
    }
    private func restore() {
        for (_, (filter, values)) in originals { _ = OPWriteBlurValues(filter, values) }
        originals.removeAll(); adjustedFilterCount = 0
    }
    func stopObserving() {
        stopped = true
        pending?.cancel(); pending = nil
        windowObservations.forEach(NotificationCenter.default.removeObserver); windowObservations.removeAll()
        observations.values.flatMap { $0 }.forEach { $0.invalidate() }; observations.removeAll()
        restore()
    }
}
#endif

struct CardGlass: View {
    var decoration: AnyView = AnyView(EmptyView())
    @Environment(\.accessibilityReduceTransparency) private var reduced
    var body: some View {
        #if os(macOS)
        ClearCardGlass(reducedTransparency: reduced, decoration: decoration)
        #else
        if !reduced {
            Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous).inset(by: 4).stroke(style: StrokeStyle(lineWidth: 8)))
        }
        decoration
        #endif
    }
}

struct GlassIconButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).labelStyle(.iconOnly).font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }
            .buttonStyle(.glass).buttonBorderShape(.circle).help(title).accessibilityLabel(title)
    }
}

struct GlassPill: View {
    var title: String
    var selected = false
    var tint: Color? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { if selected { Image(systemName: "checkmark") }; Text(title) }
                .font(.subheadline).padding(.horizontal, 4).frame(minHeight: 32)
        }
        .buttonStyle(.glass(.regular.tint(tint ?? .clear))).buttonBorderShape(.capsule)
        .accessibilityAddTraits(selected ? .isSelected : []).help(title)
    }
}
