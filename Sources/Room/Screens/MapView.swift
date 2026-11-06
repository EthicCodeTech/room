import SwiftUI
import AppKit
import RoomCore

struct MapView: View {
    @Bindable var model: AppModel
    @State private var hovered: String?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private var node: DiskNode? { model.mapNode }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            toolbar
            if let p = model.mapProgress { progress(p).transition(.rise) }
            DSCard(padding: 0) { content.frame(maxWidth: .infinity, maxHeight: .infinity) }
                .frame(minHeight: 440)
                .focusable().focused($focused).focusEffectDisabled()
                .onKeyPress(keys: [.escape, .delete, .leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space]) { press in handleKey(press) }
            footer
        }
        .padding(32).belowFloatingNav().frame(maxWidth: 1400, maxHeight: .infinity, alignment: .topLeading)
        .motion(.panel, value: model.isMapScanning)
        .task { model.openMap(); focused = true }
        .onChange(of: model.mapNode?.path) { _, _ in hovered = nil }
        .onChange(of: hovered) { _, new in if new != nil { Haptics.play(.detent) } }       // Full level only
    }

    // MARK: Header and toolbar

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Map")
                Text("Where your space went").dsText(Token.h2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let n = node { DataText(text: "\(ByteFormat.string(n.bytes)) here", color: DS.textMuted) }
                if let d = model.mapUpdatedAt { Text("Updated \(d.formatted(.relative(presentation: .numeric, unitsStyle: .wide)))").dsText(Token.micro, color: DS.textFaint) }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { goBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium)).foregroundStyle(model.canGoBack ? DS.text : DS.textFaint)
                    .frame(width: 36, height: 36).contentShape(Circle()).cinnabarGlass(Circle(), interactive: model.canGoBack)
            }
            .buttonStyle(.plain).disabled(!model.canGoBack).help("Back (Esc)").accessibilityLabel("Back")
            breadcrumb
            Spacer()
            DSSegmented(options: [(AppModel.MapMode.map, "Map"), (AppModel.MapMode.list, "List")], selection: $model.mapMode)
            PillButton(title: model.isMapScanning ? "Measuring" : "Rescan", variant: .ghost, size: .small, icon: nil, isLoading: model.isMapScanning) { model.startMapScan() }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.mapTrail.enumerated()), id: \.offset) { i, path in
                if i > 0 { Text("/").dsText(Token.small, color: DS.textFaint).transition(.opacity) }
                Button { if i < model.mapTrail.count - 1 { Haptics.play(.select); model.mapUp(to: i) } } label: {
                    Text(i == 0 ? "Home" : (path as NSString).lastPathComponent)
                        .dsText(Token.small, color: i == model.mapTrail.count - 1 ? DS.text : DS.textMuted).lineLimit(1)
                }.buttonStyle(.plain).transition(.opacity.combined(with: .offset(x: -8, y: 0)))
            }
        }
        .motion(.panel, value: model.mapTrail)
    }

    private func progress(_ p: (done: Int, total: Int)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DSProgressBar(value: p.total > 0 ? Double(p.done) / Double(p.total) : nil,
                          label: model.mapUpdatedAt == nil ? "Measuring your disk" : "Updating the map")
        }
    }

    // MARK: Content states

    /// What the card is showing. When it changes, the old state fades out as the new one fades in.
    private var contentKey: String {
        guard let n = node, !(n.children.isEmpty && model.mapUpdatedAt == nil && model.isMapScanning) else { return "loader" }
        if n.isUnreadable { return "unreadable:\(n.path)" }
        if !n.isExpanded && n.children.isEmpty { return "measuring:\(n.path)" }
        if n.children.isEmpty { return "empty:\(n.path)" }
        return "\(model.mapMode.rawValue):\(n.path)"
    }

    private var content: some View {
        ZStack { contentBody.id(contentKey).transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.985)), removal: .opacity)) }
            .motion(.panel, value: contentKey)
    }

    @ViewBuilder private var contentBody: some View {
        if let n = node, !(n.children.isEmpty && model.mapUpdatedAt == nil && model.isMapScanning) {
            if n.isUnreadable { unreadable(n) }
            else if !n.isExpanded && model.deepening.contains(n.path) || (n.children.isEmpty && !n.isExpanded) { measuring(n) }
            else if n.children.isEmpty { DSEmptyState(title: "This folder is empty", message: "There is nothing in it to measure.") }
            else if model.mapMode == .list { MapList(model: model, node: n, hovered: $hovered, open: open, reveal: reveal) }
            else {
                GeometryReader { geo in
                    treemap(n, in: geo.size)
                }
            }
        } else {
            VStack(spacing: 18) {
                SparkTraceLoader(isRunning: true, height: 72)
                Text("Measuring your disk").dsText(Token.small, color: DS.textMuted)
                Text("The first scan takes about ten seconds. Room remembers the result, so after that the map opens instantly.").dsText(Token.micro, color: DS.textFaint).multilineTextAlignment(.center).frame(maxWidth: 380)
                Text("If macOS asks to let Room look inside a folder, choose Allow so it can be included. Folders you decline simply show as private.").dsText(Token.micro, color: DS.textFaint).multilineTextAlignment(.center).frame(maxWidth: 380)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func measuring(_ n: DiskNode) -> some View {
        VStack(spacing: 16) {
            SparkTraceLoader(isRunning: true, height: 56)
            Text("Measuring \(n.name)").dsText(Token.small, color: DS.textMuted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// macOS refused to list this folder. Say so, and say what to do, instead of pretending it is empty.
    private func unreadable(_ n: DiskNode) -> some View {
        DSEmptyState(title: "Room can't open \(n.name)",
                     message: "macOS keeps this folder private. To include it, allow Full Disk Access for Room in Privacy and Security, then rescan.",
                     actionTitle: "Open privacy settings") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Treemap

    /// Resting tiles are calm neutrals. Sindoor means exactly one thing here: "this is under your pointer".
    private static let resting: [Color] = [DS.series[1], DS.series[2], DS.series[3], DS.series[4]]

    private func treemap(_ n: DiskNode, in size: CGSize) -> some View {
        let pad: CGFloat = 8
        let tiles = Treemap.layout(n.children.map { (id: $0.path, name: $0.name, bytes: $0.bytes) },
                                   in: CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2))
        let byPath = Dictionary(n.children.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let anyHover = hovered != nil
        return ZStack(alignment: .topLeading) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, t in
                let child = byPath[t.id]
                let isHover = hovered == t.id
                let canFree = (child.map { model.freeable.bytes(under: $0.path) } ?? 0) > 0
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(isHover ? DS.sindoor.opacity(scheme == .dark ? 0.18 : 0.20) : Self.resting[i % Self.resting.count].opacity(scheme == .dark ? 0.14 : 0.34))
                    VStack(alignment: .leading, spacing: 2) {
                        if t.rect.width > 80 && t.rect.height > 36 {
                            Text(t.name).dsText(.init(13, 500), color: isHover ? DS.sindoorText : DS.text).lineLimit(1)
                            DataText(text: ByteFormat.string(t.bytes), style: Token.monoSmall, color: DS.textMuted)
                        }
                    }.padding(10)
                    if canFree && t.rect.width > 40 && t.rect.height > 30 {     // "look here": Room can free something in this folder
                        SindoorDot(size: 7).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .overlay(Rectangle().strokeBorder(isHover ? DS.sindoor : DS.bg, lineWidth: isHover ? 1.5 : 2))
                .opacity(anyHover && !isHover ? 0.6 : 1)
                .frame(width: max(0, t.rect.width), height: max(0, t.rect.height))
                .offset(x: t.rect.minX, y: t.rect.minY)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("\(t.name), \(ByteFormat.string(t.bytes))\(canFree ? ", Room can free space here" : "")")
                .accessibilityAddTraits(child?.isDirectory == true ? .isButton : [])
                .accessibilityAction { if let c = child { open(c) } }
            }
        }
        // Tiles are placed with offsets, which do not change layout, so without this the container is only as big as
        // the LARGEST tile and only that corner could be hovered or clicked.
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay { if Dev.env("ROOM_DEV_HITAREA") != nil { Rectangle().stroke(Color.red, lineWidth: 3).allowsHitTesting(false) } }      // dev only
        .contentShape(Rectangle())
        // One tracker for the whole map: no per-tile gaps to flicker across, and no tile left highlighted behind you.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hovered = Treemap.tile(at: point, in: tiles)?.id
            case .ended: hovered = nil
            }
        }
        .onTapGesture(count: 1, coordinateSpace: .local) { point in
            if let t = Treemap.tile(at: point, in: tiles), let c = byPath[t.id] { open(c) }
        }
        .contextMenu { if let h = hovered, let c = byPath[h] { actions(for: c) } }
        .pointerStyle(hovered.flatMap { byPath[$0] }?.isDirectory == true ? .link : .default)
        .motion(.fast, value: hovered)
        .motion(.slow, value: tiles)                          // tiles glide into place as the layout changes, including while a scan streams in
        .onAppear {      // dev only: force a hover state for screenshots, without touching the real pointer
            if let i = Dev.env("ROOM_DEV_HOVER").flatMap(Int.init), tiles.indices.contains(i) { hovered = tiles[i].id }
        }
    }

    // MARK: Actions

    private func open(_ n: DiskNode) {
        guard !n.isAggregate else { model.mapMode = .list; Haptics.play(.select); return }       // the long tail is easiest to read as a list
        if n.isDirectory { Haptics.play(.select); hovered = nil; Motion.run(.panel) { model.openFolder(n.path) } }
        else { reveal(n) }
    }

    private func reveal(_ n: DiskNode) { Haptics.play(.confirm); model.revealInFinder(n.path) }

    private func goBack() { Haptics.play(.select); Motion.run(.panel) { model.mapBack() } }

    @ViewBuilder private func actions(for n: DiskNode) -> some View {
        if n.isDirectory && !n.isAggregate { Button("Open") { open(n) } }
        if !n.isAggregate {
            Button("Reveal in Finder") { reveal(n) }
            Button("Copy path") { Haptics.play(.select); model.copyPath(n.path) }
            if model.freeable.bytes(under: n.path) > 0 {
                Button("Show what Room can free here") { Haptics.play(.select); model.showInReview(folder: n.path) }
            }
        }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let n = node else { return .ignored }
        let ids = n.children.map(\.path)
        func step(_ d: Int) {
            guard !ids.isEmpty else { return }
            let i = hovered.flatMap { ids.firstIndex(of: $0) } ?? (d > 0 ? -1 : ids.count)
            hovered = ids[max(0, min(ids.count - 1, i + d))]
        }
        switch press.key {
        case .escape, .delete: if model.canGoBack { goBack(); return .handled }; return .ignored
        case .leftArrow, .upArrow: step(-1); return .handled
        case .rightArrow, .downArrow: step(1); return .handled
        case .return, .space: if let h = hovered, let c = n.children.first(where: { $0.path == h }) { open(c); return .handled }; return .ignored
        default: return .ignored
        }
    }

    // MARK: Footer: what the pointer is on, in words

    private var footer: some View {
        ZStack(alignment: .leading) { footerBody.id(hovered ?? "idle").transition(.opacity) }.motion(.fast, value: hovered)
    }

    @ViewBuilder private var footerBody: some View {
        if let id = hovered, let n = node, let c = n.children.first(where: { $0.path == id }) {
            let share = n.bytes > 0 ? Double(c.bytes) / Double(n.bytes) * 100 : 0
            let freeBytes = model.freeable.bytes(under: c.path)
            HStack(spacing: 8) {
                SindoorDot(size: 6)
                DataText(text: "\(c.name) · \(ByteFormat.string(c.bytes)) · \(share < 1 ? "<1" : String(Int(share.rounded())))% of this folder", style: Token.monoSmall, color: DS.textSoft)
                if freeBytes > 0 { Text("Room can free \(ByteFormat.string(freeBytes)) here").dsText(Token.micro, color: DS.sindoorText) }
                else if c.isDirectory && !c.isAggregate { Text("Click to look inside").dsText(Token.micro, color: DS.textFaint) }
            }
        } else {
            Text("Click a folder to look inside. Esc goes back. A dot marks folders where Room can free space.").dsText(Token.micro, color: DS.textFaint)
        }
    }
}

// MARK: - List view: precise, keyboard and screen-reader friendly

private struct MapList: View {
    @Bindable var model: AppModel
    let node: DiskNode
    @Binding var hovered: String?
    let open: (DiskNode) -> Void
    let reveal: (DiskNode) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(node.children) { c in
                    let isHover = hovered == c.path
                    let freeBytes = model.freeable.bytes(under: c.path)
                    let share = node.bytes > 0 ? Double(c.bytes) / Double(node.bytes) : 0
                    Button { open(c) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: c.isAggregate ? "ellipsis" : (c.isDirectory ? "folder" : "doc")).font(.system(size: 14, weight: .regular))
                                .foregroundStyle(isHover ? DS.sindoorText : DS.textMuted).frame(width: 20)
                            Text(c.name).dsText(Token.small, color: isHover ? DS.sindoorText : DS.text).lineLimit(1)
                            if freeBytes > 0 { DSBadge(text: "\(ByteFormat.string(freeBytes)) can go", dot: DS.sindoor) }
                            Spacer()
                            DSProgressBar(value: share, fill: DS.lineStronger).frame(width: 160)
                            DataText(text: ByteFormat.string(c.bytes)).frame(width: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 20).frame(height: 48).contentShape(Rectangle())
                        .background(isHover ? DS.raised : .clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: Token.hairline) }
                        .motion(.fast, value: isHover)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in hovered = inside ? c.path : (hovered == c.path ? nil : hovered) }
                    .contextMenu {
                        if c.isDirectory && !c.isAggregate { Button("Open") { open(c) } }
                        if !c.isAggregate {
                            Button("Reveal in Finder") { reveal(c) }
                            Button("Copy path") { Haptics.play(.select); model.copyPath(c.path) }
                            if freeBytes > 0 { Button("Show what Room can free here") { Haptics.play(.select); model.showInReview(folder: c.path) } }
                        }
                    }
                    .accessibilityLabel("\(c.name), \(ByteFormat.string(c.bytes))")
                }
            }
        }
    }
}
