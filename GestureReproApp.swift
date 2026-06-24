import SwiftUI
import AppKit

// Minimal macOS repro: a SwiftUI DragGesture, held on the trackpad, is permanently
// cancelled by a two-finger magnify. The drag's .onEnded is never delivered, and the
// still-pressed finger's continued motion is never re-detected — yet the underlying
// AppKit NSEvent stream keeps delivering .leftMouseDragged the whole time.
//
// REPRO
//   1. Press-hold and drag the circle (trackpad click-drag). Both onChanged counters climb.
//   2. WITHOUT lifting, two-finger pinch.
//   3. Keep dragging the original finger.
//
// PROOF
//   The "drag and magnify" checklist never gets a ✅ on "Drag onChanged — RESUMED" or
//   "Drag onEnded" — those lines stay ◻️. Meanwhile the "NSEvent leftMouseDragged"
//   counter keeps climbing the whole time. => the OS still delivers the drag; SwiftUI dropped it.
//
// macOS 26.3.1 (25D771280a) · Xcode 26.4.1 (17E202) · Swift 6.3.1 · Apple Silicon

@main
struct GestureReproApp: App {
    var body: some Scene {
        WindowGroup("Drag killed by pinch") {
            ContentView().frame(minWidth: 880, minHeight: 640)
        }
    }
}

/// A line in an expected-event flow chart. `key` is set in `seen` once that event fires.
private struct FlowLine: Identifiable {
    let id = UUID()
    let key: String
    let text: String
}

/// Which input source actually moves the ball. SwiftUI gestures and the NSEvent
/// monitor both stay live for logging in either mode — only the movement is switched.
private enum BallControl: String, CaseIterable, Identifiable {
    case swiftUI = "SwiftUI"
    case appKit = "AppKit"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var offset: CGSize = .zero
    @State private var accumulated: CGSize = .zero
    @State private var scale: CGFloat = 1
    /// Scale at the start of the current SwiftUI magnify, so size is retained between pinches.
    @State private var magnifyBaseScale: CGFloat = 1

    /// Which input source moves the ball. Does NOT affect logs/counters/charts.
    @State private var control: BallControl = .swiftUI
    /// AppKit drag anchor (window coords + offset at press), used when control == .appKit.
    @State private var nsAnchorLocation: CGPoint = .zero
    @State private var nsAnchorOffset: CGSize = .zero

    // Monotonic counters — cleared only by Reset.
    @State private var dragChanges = 0
    @State private var magnifyChanges = 0
    @State private var nsDragged = 0
    @State private var nsMagnify = 0

    @State private var dragInProgress = false
    @State private var magnifyInProgress = false

    /// Event keys detected this run, per scenario. Drive the ✅ / ◻️ in the flow charts.
    /// drag = plain drag · magOnly = pinch with no press · mag = drag-and-magnify press.
    @State private var seenDrag: Set<String> = []
    @State private var seenMagOnly: Set<String> = []
    @State private var seenMag: Set<String> = []

    /// A chart only records ✅ once it's been "started". Before that all lines show ▫️;
    /// after, unfired lines show ⬜️.
    @State private var armedDrag = false
    @State private var armedMagOnly = false
    @State private var armedMag = false

    /// Per-magnify-gesture tracking, for the "SwiftUI missed a magnify" counter.
    @State private var magnifyActive = false
    @State private var swiftUISawThisMagnify = false
    @State private var swiftUIMissedMagnify = 0

    @State private var log: [String] = []
    @State private var monitor: Any?

    private let dragFlow: [FlowLine] = [
        .init(key: "down",       text: "NSEvent leftMouseDown"),
        .init(key: "dragStart",  text: "Drag onChanged — STARTED"),
        .init(key: "up",         text: "NSEvent leftMouseUp"),
        .init(key: "dragEnd",    text: "Drag onEnded — terminal"),
    ]

    private let magnifyFlow: [FlowLine] = [
        .init(key: "nsMagBegan",   text: "NSEvent magnify began"),
        .init(key: "magnifyStart", text: "Magnify onChanged — STARTED"),
        .init(key: "magnifyEnd",   text: "Magnify onEnded — terminal"),
        .init(key: "nsMagEnded",   text: "NSEvent magnify ended"),
    ]

    private let dragMagnifyFlow: [FlowLine] = [
        .init(key: "down",         text: "NSEvent leftMouseDown"),
        .init(key: "dragStart",    text: "Drag onChanged — STARTED"),
        .init(key: "nsMagBegan",   text: "NSEvent magnify began"),
        .init(key: "magnifyStart", text: "Magnify onChanged — STARTED"),
        .init(key: "magnifyEnd",   text: "Magnify onEnded — terminal"),
        .init(key: "nsMagEnded",   text: "NSEvent magnify ended"),
        .init(key: "up",           text: "NSEvent leftMouseUp"),
        .init(key: "dragEnd",      text: "Drag onEnded — terminal"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text("Hold-drag the circle, then two-finger pinch without lifting, then keep dragging.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Picker("control ball with", selection: $control) {
                    ForEach(BallControl.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .fixedSize()
            }
            .padding([.top, .horizontal], 12)

            counters

            Circle()
                .fill(control == .swiftUI ? Color.accentColor : Color.orange)
                .frame(width: 130, height: 130)
                .scaleEffect(scale)
                .offset(offset)
                .shadow(radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(drag)
                .simultaneousGesture(magnify)
                .background(Color(nsColor: .underPageBackgroundColor))
                .frame(maxHeight: .infinity)

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    flowChart("drag", lines: dragFlow, seen: seenDrag, armed: armedDrag,
                              start: { seenDrag.removeAll(); armedDrag.toggle() })
                    flowChart("magnify", lines: magnifyFlow, seen: seenMagOnly, armed: armedMagOnly,
                              start: { seenMagOnly.removeAll(); armedMagOnly.toggle() })
                }
                flowChart("drag and magnify", lines: dragMagnifyFlow, seen: seenMag, armed: armedMag,
                          start: { seenMag.removeAll(); armedMag.toggle() }) {
                    Text("⬜️ lines should turn ✅ but never do")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.top, 20)
                }
                logsSection
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
        .onChange(of: control) { _, _ in resetState(); stopAllCharts() }
    }

    private var counters: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("SwiftUI").bold(); Text("Drag onChanged: \(Text("\(dragChanges)").bold())")
                HStack(spacing: 10) {
                    Text("Magnify onChanged: \(Text("\(magnifyChanges)").bold())")
                    Text("· SwiftUI missed an NSEvent magnify: \(Text("\(swiftUIMissedMagnify)").bold())×")
                        .foregroundStyle(swiftUIMissedMagnify > 0 ? .orange : .secondary)
                }
            }
            GridRow {
                Text("AppKit").bold(); Text("NSEvent leftMouseDragged: \(Text("\(nsDragged)").bold())")
                Text("NSEvent magnify: \(Text("\(nsMagnify)").bold())")
            }
        }
        .font(.system(.callout, design: .monospaced))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    // MARK: Section builders (three equal columns)

    /// Title with an SF Symbol after each "drag" (hand.draw) and "magnify" (hand.pinch),
    /// the symbols sized ~150% of the headline text.
    @ViewBuilder
    private func titleView(_ title: String) -> some View {
        let draw = Image(systemName: "hand.draw").font(.system(size: 20))
        let pinch = Image(systemName: "hand.pinch").font(.system(size: 20))
        HStack(spacing: 5) {
            switch title {
            case "drag":             Text("drag"); draw
            case "magnify":          Text("magnify"); pinch
            case "drag and magnify": Text("drag"); draw; Text("and magnify"); pinch
            default:                 Text(title)
            }
        }
    }

    private func flowChart<Footer: View>(_ title: String, lines: [FlowLine], seen: Set<String>,
                                         armed: Bool, start: @escaping () -> Void,
                                         @ViewBuilder footer: () -> Footer = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                titleView(title).font(.headline)
                Spacer()
                Button(armed ? "Stop" : "Start", action: start).controlSize(.small)
            }
            Divider()
            ForEach(lines) { line in
                let done = armed && seen.contains(line.key)
                HStack(alignment: .top, spacing: 6) {
                    Text(!armed ? "▫️" : (done ? "✅" : "⬜️"))
                    Text(line.text).foregroundStyle(done ? .primary : .secondary)
                }
            }
            footer()
            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("logs").font(.headline)
                Spacer()
                Button("Reset", action: resetState).controlSize(.small)
            }
            Divider()
            scrollLog
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var scrollLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { i, line in
                        Text(line).id(i)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxHeight: .infinity)
            .onChange(of: log.count) { _, c in proxy.scrollTo(c - 1, anchor: .bottom) }
        }
    }

    /// State reset (the Reset button): counters, ball position/size, logs, transient
    /// interaction state. Does NOT touch the flow-chart checkmarks.
    private func resetState() {
        log.removeAll()
        dragChanges = 0; magnifyChanges = 0; nsDragged = 0; nsMagnify = 0; swiftUIMissedMagnify = 0
        dragInProgress = false; magnifyInProgress = false
        magnifyActive = false; swiftUISawThisMagnify = false
        offset = .zero; accumulated = .zero
        magnifyBaseScale = 1
        withAnimation { scale = 1 }
    }

    /// Stop every chart and clear its checkmarks.
    private func stopAllCharts() {
        armedDrag = false; armedMagOnly = false; armedMag = false
        seenDrag.removeAll(); seenMagOnly.removeAll(); seenMag.removeAll()
    }

    private func note(_ s: String) {
        log.append(s)
        if log.count > 300 { log.removeFirst(log.count - 300) }
        print("[Repro] \(s)")
    }

    // MARK: SwiftUI gestures

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !dragInProgress {
                    dragInProgress = true
                    seenDrag.insert("dragStart"); seenMag.insert("dragStart")
                    note("Drag onChanged — STARTED")
                }
                dragChanges += 1
                if control == .swiftUI {
                    offset = CGSize(width: accumulated.width + v.translation.width,
                                    height: accumulated.height + v.translation.height)
                }
            }
            .onEnded { _ in
                seenDrag.insert("dragEnd"); seenMag.insert("dragEnd")
                note("Drag onEnded — terminal")
                if control == .swiftUI { accumulated = offset }
                dragInProgress = false
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if !magnifyInProgress {
                    magnifyInProgress = true
                    magnifyBaseScale = scale  // retain size: build on current scale
                    note("Magnify onChanged — STARTED")
                }
                beginMagnifyIfNeeded()
                swiftUISawThisMagnify = true
                markMagnify("magnifyStart")
                magnifyChanges += 1
                if control == .swiftUI { scale = max(0.4, min(3, magnifyBaseScale * v.magnification)) }
            }
            .onEnded { _ in
                markMagnify("magnifyEnd")
                note("Magnify onEnded — terminal")
                magnifyInProgress = false
            }
    }

    // MARK: Magnify tracking

    /// Called on the first event of a magnify gesture (NSEvent began or SwiftUI onChanged),
    /// for the "SwiftUI missed a magnify" counter.
    private func beginMagnifyIfNeeded() {
        guard !magnifyActive else { return }
        magnifyActive = true
        swiftUISawThisMagnify = false
    }

    /// NSEvent magnify .ended is the authoritative end. If SwiftUI never saw this magnify,
    /// that's the bug we're counting.
    private func endMagnify() {
        guard magnifyActive else { return }
        if !swiftUISawThisMagnify { swiftUIMissedMagnify += 1 }
        magnifyActive = false
    }

    /// Magnify lines appear in both magnify charts; mark whenever the event is detected.
    private func markMagnify(_ key: String) {
        seenMagOnly.insert(key); seenMag.insert(key)
    }

    // MARK: Passive NSEvent monitor — logs only, drives nothing.

    private func installMonitor() {
        removeMonitor()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .magnify]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            switch event.type {
            case .leftMouseDown:
                seenDrag.insert("down"); seenMag.insert("down")
                note("NSEvent leftMouseDown")
                nsAnchorLocation = event.locationInWindow
                nsAnchorOffset = offset
            case .leftMouseUp:
                seenDrag.insert("up"); seenMag.insert("up")
                note("NSEvent leftMouseUp")
            case .leftMouseDragged:
                nsDragged += 1
                if control == .appKit {
                    // window coords: y is up; SwiftUI offset y is down -> negate dy.
                    let loc = event.locationInWindow
                    offset = CGSize(width: nsAnchorOffset.width + (loc.x - nsAnchorLocation.x),
                                    height: nsAnchorOffset.height - (loc.y - nsAnchorLocation.y))
                }
            case .magnify:
                nsMagnify += 1
                if event.phase == .began {
                    beginMagnifyIfNeeded()
                    markMagnify("nsMagBegan")
                    note("NSEvent magnify began")
                } else if event.phase == .ended {
                    markMagnify("nsMagEnded")
                    note("NSEvent magnify ended")
                    endMagnify()
                }
                if control == .appKit {
                    // event.magnification is an incremental delta; accumulate and retain.
                    scale = max(0.4, min(3, scale + event.magnification))
                }
            default: break
            }
            return event  // pass through so SwiftUI still sees it
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
