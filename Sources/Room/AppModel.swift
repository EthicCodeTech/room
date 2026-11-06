import SwiftUI
import UserNotifications
import AppKit
import RoomCore

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var source: String?
}

@MainActor @Observable
final class AppModel {
    // Services
    let paths: AppPaths
    private let settingsStore: SettingsStore
    let vault: Vault
    let log: DecisionLog
    let scorer: RegretScorer
    let growthStore: GrowthStore
    let toasts = ToastCenter()
    let motion = MotionSensor()
    private(set) var catalog: Catalog

    // Settings
    var settings: AppSettings { didSet { settingsStore.save(settings); Haptics.level = settings.hapticLevel } }

    /// nil follows the Mac. `ROOM_APPEARANCE=light|dark` overrides for screenshots only.
    var colorScheme: ColorScheme? {
        switch Dev.env("ROOM_APPEARANCE") ?? settings.appearance.rawValue {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    // Disk
    var freeBytes: Int64 = FreeSpace.available()
    var totalBytes: Int64 = FreeSpace.total()

    // Scan
    enum ScanState: Equatable { case idle, scanning(String), done(Date) }
    var scanState: ScanState = .idle
    var candidates: [Candidate] = []
    var selection: Set<String> = []
    var inspectedID: String?

    // Goal and plan
    var goalGB = 24 { didSet { replan() } }
    var plan: Plan?

    // Cleaning
    var isCleaning = false
    var lastReport: CleanReport?
    var showConfirm = false
    var confirmYours: Set<String> = []
    var confirmUnbacked: Set<String> = []

    // Vault, growth, map, assistant
    var vaultBatches: [VaultManifest] = []
    var growth: (from: GrowthSnapshot, to: GrowthSnapshot, deltas: [GrowthDelta])?
    var snapshots: [GrowthSnapshot] = []
    var isMeasuring = false
    enum MapMode: String { case map, list }
    var mapTree: DiskNode?
    var mapTrail: [String] = []
    var mapMode: MapMode = .map
    /// Folders measured so far during a scan; nil when idle.
    var mapProgress: (done: Int, total: Int)?
    var mapUpdatedAt: Date?
    var deepening: Set<String> = []
    var freeable = FreeableIndex(candidates: [])
    var pendingSection: Section?
    var reviewSearch: String?
    var messages: [ChatMessage] = []
    var isAsking = false
    var explanations: [String: String] = [:]

    private var timer: Timer?
    private var lastAlert: Date?

    init(paths: AppPaths = .standard) {
        self.paths = paths
        try? paths.ensureDirectories()
        settingsStore = SettingsStore(paths: paths)
        settings = settingsStore.load()
        vault = Vault(paths: paths)
        log = DecisionLog(paths: paths)
        scorer = RegretScorer(paths: paths)
        growthStore = GrowthStore(paths: paths)
        catalog = CatalogUpdater.current(paths: paths)
        Haptics.level = settings.hapticLevel

        vault.purgeExpired()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.motion.stop() }          // leave the sensor as we found it
        }
        let history = log.load()
        if !history.isEmpty { scorer.retrain(from: history) }
        refreshVault(); refreshGrowth(); refreshDisk()
        Task { await loadMapCache() }
        if let logPath = Dev.env("ROOM_DEV_SENSORLOG") {      // dev only: confirms the sensor streams inside the app
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    let m = self.motion.latest
                    let line = String(format: "state=%@ x=%.3f y=%.3f z=%.3f |g|=%.3f\n", String(describing: self.motion.state), m.x, m.y, m.z, m.magnitude)
                    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
                    else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    // MARK: Disk

    func refreshDisk() { freeBytes = FreeSpace.available(); totalBytes = FreeSpace.total() }
    var usedFraction: Double { totalBytes > 0 ? 1 - Double(freeBytes) / Double(totalBytes) : 0 }
    var goalBytes: Int64 { Int64(goalGB) * 1_000_000_000 }
    var isLow: Bool { freeBytes < Int64(settings.lowSpaceAlertGB) * 1_000_000_000 }

    private var wasLow = false
    private func tick() {
        refreshDisk(); refreshVault()
        if isLow && !wasLow { Haptics.play(.attention) }            // you just crossed the line
        wasLow = isLow
        guard isLow else { return }
        if let last = lastAlert, Date().timeIntervalSince(last) < 12 * 3600 { return }
        lastAlert = Date()
        notifyLow()
    }

    private func notifyLow() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let safe = candidates.filter { $0.tier == .safe }.reduce(Int64(0)) { $0 + $1.estimate.planning }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert]) { ok, _ in
            guard ok else { return }
            let n = UNMutableNotificationContent()
            n.title = "Your Mac has \(ByteFormat.string(self.freeBytes)) left"
            n.body = safe > 0 ? "Room can free about \(ByteFormat.string(safe)) of caches without touching your files." : "Open Room to see what is taking the space."
            c.add(UNNotificationRequest(identifier: "low-space", content: n, trigger: nil))
        }
    }

    // MARK: Scanning

    func scan() {
        guard scanState == .idle || { if case .done = scanState { return true } else { return false } }() else { return }
        scanState = .scanning("Reading rules")
        var options = DiscoveryOptions()
        options.staleProjectDays = settings.staleProjectDays
        options.catalog = catalog
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> [Candidate] in
                var list = await Discovery(options: options).run(progress: { msg in Task { @MainActor in self.scanState = .scanning(msg) } })
                for i in list.indices where list[i].tier == .yours { if let t = list[i].targets.first { list[i].git = GitGuard.status(for: t) } }
                return list
            }.value
            candidates = found
            freeable = FreeableIndex(candidates: found)
            selection = Set(found.filter(\.preselected).map(\.id))
            scanState = .done(Date())
            refreshDisk(); replan()
            Haptics.play(.spark)
            maybeSnapshot()
            refreshMapIfStale(gentle: true)          // quietly measure the map now, so it is ready when you open it
            if Dev.env("ROOM_DEV_CONFIRM") != nil { requestClean() }   // dev only, for screenshots
            if Dev.env("ROOM_DEV_INSPECT") != nil { inspectedID = candidates.first?.id }   // dev only
        }
    }

    func rescanAfterClean() {
        scanState = .idle; scan()
    }

    var restoreRates: [String: Double] { RegretScorer.restoreRates(from: log.load()) }

    func replan() {
        guard !candidates.isEmpty else { plan = nil; return }
        plan = Planner(scorer: scorer, restoreRates: restoreRates).plan(goalBytes: goalBytes, from: candidates)
    }

    func applyPlanToSelection() {
        guard let plan else { return }
        selection = Set(plan.items.map(\.id))
    }

    // MARK: Selection

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        Haptics.play(.select)
    }
    var selectedItems: [Candidate] { candidates.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.estimate.planning } }
    var inspected: Candidate? { candidates.first { $0.id == inspectedID } }

    // MARK: Cleaning

    func requestClean() {
        guard !selectedItems.isEmpty else { return }
        confirmYours = []; confirmUnbacked = []
        showConfirm = true
        Haptics.play(.attention)
    }

    /// What happens to an item on delete, given the user's undo setting.
    func policy(for c: Candidate) -> DeletionPolicy { .default(for: c, vaultRebuildable: settings.vaultRebuildable) }

    func confirmClean() {
        let items = selectedItems
        let confirmations = Confirmations(yours: confirmYours, unbackedRepo: confirmUnbacked,
                                          declined: candidates.filter { $0.preselected && !selection.contains($0.id) })
        showConfirm = false; isCleaning = true
        Task { while isCleaning { Haptics.play(.pending); try? await Task.sleep(for: .seconds(1.2)) } }      // a slow heartbeat while Room works
        let goalBefore = goalBytes
        let cleaner = Cleaner(vault: vault, log: log)
        let vaultRebuildable = settings.vaultRebuildable
        Task {
            let report = await Task.detached(priority: .userInitiated) { cleaner.execute(items, confirmations: confirmations, policy: { DeletionPolicy.default(for: $0, vaultRebuildable: vaultRebuildable) }) }.value
            isCleaning = false; lastReport = report
            refreshDisk(); refreshVault()
            present(report, goal: goalBefore)
            selection = []
            rescanAfterClean()
        }
    }

    private func present(_ r: CleanReport, goal: Int64) {
        let failed = r.results.filter { if case .failed = $0.status { return true } else { return false } }
        let skipped = r.results.filter { if case .skipped = $0.status { return true } else { return false } }
        let measured = ByteFormat.string(r.measuredFreed)
        let detail = "Measured: \(ByteFormat.string(r.freeBefore)) to \(ByteFormat.string(r.freeAfter)) free"
        if !failed.isEmpty {
            let why = failed.first.map { if case .failed(let m) = $0.status { return "\($0.candidate.title): \(m.trimmingCharacters(in: .whitespacesAndNewlines))" } else { return "" } } ?? ""
            toasts.show(.failed, "\(failed.count) item\(failed.count == 1 ? "" : "s") could not be removed", detail: String(why.prefix(160)))
        }
        if !skipped.isEmpty {
            toasts.show(.pending, "\(skipped.count) skipped for your safety", detail: skipped.compactMap { if case .skipped(let m) = $0.status { return m } else { return nil } }.first)
        }
        if r.vaultedBytes > 0 {
            toasts.show(.info, "\(ByteFormat.string(r.vaultedBytes)) is in the vault", detail: "Space returns when you empty it, or after 7 days")
        }
        if r.measuredFreed > 0 || failed.isEmpty {
            toasts.show(.success, "Freed \(measured)", detail: detail, haptic: r.freeAfter - r.freeBefore >= goal ? .spark : nil)   // the milestone gets the signature
        }
    }

    // MARK: Vault

    func refreshVault() { vaultBatches = vault.list() }

    func restore(_ batch: VaultManifest) {
        do {
            _ = try Cleaner(vault: vault, log: log).restore(batch, candidates: candidates)
            toasts.show(.success, "Restored \(batch.label)", detail: "\(batch.entries.count) item\(batch.entries.count == 1 ? "" : "s") back where they were")
            scorer.retrain(from: log.load())
        } catch {
            toasts.show(.failed, "Could not restore \(batch.label)", detail: error.localizedDescription)
        }
        refreshVault(); refreshDisk()
    }

    func emptyVaultNow() {
        let report = Cleaner(vault: vault, log: log).freeVaultNow()
        refreshVault(); refreshDisk()
        toasts.show(.success, "Vault emptied", detail: "Measured: \(ByteFormat.string(report.measuredFreed)) returned")
    }

    func deleteBatchNow(_ batch: VaultManifest) {
        let before = FreeSpace.available()
        vault.purge(batch.id)
        refreshVault(); refreshDisk()
        toasts.show(.success, "Deleted \(batch.label)", detail: "Measured: \(ByteFormat.string(max(0, FreeSpace.available() - before))) returned")
    }

    // MARK: Growth

    func refreshGrowth() { snapshots = growthStore.load(); growth = growthStore.recentDeltas(days: 7) }

    private func maybeSnapshot() {
        if let last = snapshots.last, Date().timeIntervalSince(last.date) < 12 * 3600 { return }
        takeSnapshot(silent: true)
    }

    func takeSnapshot(silent: Bool = false) {
        guard !isMeasuring else { return }
        isMeasuring = true
        Task {
            let areas = await Task.detached(priority: .utility) { await AreaMeter.measure(AreaMeter.defaultAreas()) }.value
            var all = areas
            for c in candidates where c.kind == .command { all[c.title] = c.estimate.planning }
            growthStore.add(GrowthSnapshot(date: Date(), freeBytes: FreeSpace.available(), totalBytes: FreeSpace.total(), areas: all))
            refreshGrowth(); isMeasuring = false
            if !silent { toasts.show(.success, "Snapshot saved", detail: "\(all.count) areas measured") }
        }
    }

    // MARK: Map

    /// The folder on screen. Falls back to the nearest folder we have, so a scan in progress never shows nothing.
    var mapNode: DiskNode? {
        guard let tree = mapTree else { return nil }
        for p in mapTrail.reversed() { if let n = tree.find(p) { return n } }
        return tree
    }
    var isMapScanning: Bool { mapProgress != nil }
    @ObservationIgnored private var mapTask: Task<Void, Never>?
    @ObservationIgnored private var mapGeneration = 0

    func openMap() {
        if Dev.env("ROOM_DEV_MAPSAMPLE") != nil { if mapTree == nil { loadSampleMap() }; return }
        // Show the last map instantly, then refresh it behind the scenes if it is stale.
        Task { await loadMapCache(); refreshMapIfStale() }
    }

    /// Reads the last map from disk off the main thread. Called at launch, so it is ready (and can order the next scan).
    private func loadMapCache() async {
        guard mapTree == nil else { return }
        let url = paths.mapCache
        let cache = await Task.detached(priority: .userInitiated) { MapCache.load(from: url) }.value
        if mapTree == nil, let cache { mapTree = cache.root; mapUpdatedAt = cache.scannedAt; if mapTrail.isEmpty { mapTrail = [cache.root.path] } }
    }

    /// Refreshes the map in the background when it is missing or more than ten minutes old.
    func refreshMapIfStale(gentle: Bool = false) {
        if mapTask == nil, mapTree == nil || Date().timeIntervalSince(mapUpdatedAt ?? .distantPast) > 600 { startMapScan(gentle: gentle) }
    }

    /// `gentle` uses fewer workers, for a background prefetch while you do something else. It does NOT lower the
    /// priority: macOS starves low-priority work for the whole run, which made a 12 second scan crawl.
    func startMapScan(gentle: Bool = false) {
        guard Dev.env("ROOM_DEV_MAPSAMPLE") == nil else { return }
        mapTask?.cancel()
        mapGeneration += 1
        let generation = mapGeneration
        mapProgress = (0, 1)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hadMap = mapTree != nil
        let hints = mapTree          // the last map says which folders are big, so the slowest work starts first
        let workers = gentle ? 4 : max(4, ProcessInfo.processInfo.activeProcessorCount)
        mapTask = Task(priority: .userInitiated) {
            let tree = await DiskScanner.scan(home, depth: 3, hints: hints, concurrency: workers) { [weak self] partial, done, total in
                Task { @MainActor in
                    guard let self, self.mapGeneration == generation else { return }
                    self.mapProgress = (done, total)
                    if !hadMap { self.mapTree = partial; if self.mapTrail.isEmpty { self.mapTrail = [partial.path] } }   // tiles appear as folders finish
                }
            }
            guard !Task.isCancelled, mapGeneration == generation else { return }
            mapTree = tree; mapUpdatedAt = Date(); mapProgress = nil; mapTask = nil
            if mapTrail.isEmpty || tree.find(mapTrail[0]) == nil { mapTrail = [tree.path] }
            persistMap()
        }
    }

    private func persistMap() {
        guard let tree = mapTree, let when = mapUpdatedAt else { return }
        let cache = MapCache(root: tree, scannedAt: when), url = paths.mapCache
        Task.detached(priority: .utility) { cache.save(to: url) }
    }

    /// Instant when the folder was already measured; otherwise measures it one level deeper in the background.
    func openFolder(_ path: String) {
        guard let node = mapTree?.find(path), node.isDirectory, !node.isAggregate else { return }
        mapTrail.append(path)
        if !node.isExpanded && !node.isUnreadable { deepen(path) }
    }

    private func deepen(_ path: String) {
        guard !deepening.contains(path), Dev.env("ROOM_DEV_MAPSAMPLE") == nil else { return }
        deepening.insert(path)
        Task {
            let node = await DiskScanner.scan(URL(fileURLWithPath: path), depth: 2)
            deepening.remove(path)
            mapTree = mapTree?.grafting(node)         // keyed by path, so it is harmless if you have already moved on
            persistMap()
        }
    }

    func mapBack() { if mapTrail.count > 1 { mapTrail.removeLast() } }
    func mapUp(to index: Int) { if index >= 0, index < mapTrail.count { mapTrail = Array(mapTrail.prefix(index + 1)) } }
    var canGoBack: Bool { mapTrail.count > 1 }

    func revealInFinder(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func copyPath(_ path: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }

    /// Jumps to Review filtered to one folder, so the map leads straight to what Room can free there.
    func showInReview(folder path: String) {
        reviewSearch = PathDisplay.pretty(path); pendingSection = .review
    }

    private func loadSampleMap() {      // dev only: an instant sample tree for screenshots
        func n(_ name: String, _ gb: Double, parent: String = "/sample", kids: [DiskNode] = []) -> DiskNode {
            DiskNode(path: "\(parent)/\(name)", name: name, bytes: Int64(gb * 1e9), children: kids, isDirectory: true)
        }
        let projects = (["cet-bot": 9.1, "AtharvaChauhan": 7.7, "conexion": 5.0, "prbot": 4.9, "meeting-ai": 3.9, "CET-Buddy": 2.9, "brewstack": 2.7, "LibraryAPI": 2.3])
            .map { n($0.key, $0.value, parent: "/sample/Projects") }.sorted { $0.bytes > $1.bytes }
        let kids = [n("Projects", 79.95, kids: projects), n("Library", 69.63), n(".colima", 22.11), n("CallArchive", 12.83), n("Downloads", 8.24),
                    n("Documents", 7.0), n(".gemini", 6.86), n(".gradle", 6.79), n(".ollama", 9.88), n("My project", 3.67), n(".codex", 3.38),
                    n(".android", 3.36), n("tizen-studio", 4.32), n("Movies", 1.6), n("Desktop", 1.4)].sorted { $0.bytes > $1.bytes }
        mapTree = DiskNode(path: "/sample", name: "Home", bytes: kids.reduce(0) { $0 + $1.bytes }, children: kids, isDirectory: true)
        mapTrail = ["/sample"]; mapUpdatedAt = Date().addingTimeInterval(-180)
        func cand(_ id: String, _ path: String, _ gb: Double) -> Candidate {
            Candidate(id: id, ruleID: "cache.spotify", kind: .rule, title: id, why: "", tier: .safe, regen: .instant, action: .deleteItem,
                      targets: [URL(fileURLWithPath: path)], displayPath: path, estimate: SizeEstimate(allocated: Int64(gb * 1e9), guaranteed: Int64(gb * 1e9)), lastModified: nil, preselected: true)
        }
        freeable = FreeableIndex(candidates: [cand("a", "/sample/Library/Caches/Spotify", 3.7), cand("b", "/sample/.gradle/caches", 6.2), cand("c", "/sample/Projects/cet-bot/node_modules", 0.9)])
        if Dev.env("ROOM_DEV_MAPMODE") == "list" { mapMode = .list }
        if Dev.env("ROOM_DEV_DRILL") != nil { openFolder("/sample/Projects") }
    }

    // MARK: Water tilt

    /// One-time setup. The sensor's axes aren't documented, so the app learns them from a "lower the left edge" gesture.
    func calibrateTilt() {
        guard motion.isAvailable, !motion.isCalibrating else { return }
        motion.onCalibrated = { [weak self] cal in
            guard let self else { return }
            self.settings.tilt = cal
            self.toasts.show(.success, "The water follows your Mac now", detail: "Tilt it and watch", haptic: .spark)
        }
        motion.beginCalibration()
        Task {
            try? await Task.sleep(for: .seconds(20))
            if motion.isCalibrating {
                motion.cancelCalibration()
                toasts.show(.pending, "Room didn't feel a tilt", detail: "Lower the left edge of your Mac for a moment, then try again")
            }
        }
    }

    func recalibrateTilt() { settings.tilt = .none; calibrateTilt() }

    // MARK: Assistant

    var advisor: any Advisor { AdvisorFactory.make(settings.advisorMode) }

    private func context() -> AdvisorContext {
        AdvisorContext(candidates: candidates, free: freeBytes, total: totalBytes, growth: growth?.deltas ?? [],
                       redactNames: AdvisorFactory.shouldRedact(settings.advisorMode), catalog: catalog)
    }

    func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        messages.append(.init(role: .user, text: q)); isAsking = true
        Haptics.play(.pending)
        let adv = advisor, ctx = context()
        Task {
            do {
                let a = try await adv.answer(q, context: ctx)
                messages.append(.init(role: .assistant, text: a, source: adv.name)); Haptics.play(.confirm)
            } catch {
                let fallback = (try? await RuleAdvisor().answer(q, context: ctx)) ?? ""
                messages.append(.init(role: .assistant, text: "The assistant couldn't answer just now, so here is what the built-in rules say. " + fallback, source: "Built-in rules"))
            }
            isAsking = false
        }
    }

    func askForPlan() {
        guard !isAsking else { return }
        let goal = goalBytes
        messages.append(.init(role: .user, text: "Find \(goalGB) GB with the least risk."))
        isAsking = true; Haptics.play(.pending)
        let adv = advisor, ctx = context(), pool = candidates
        Task {
            var reply = ""
            do {
                let proposal = try await adv.proposeIDs(goalBytes: goal, context: ctx)
                let valid = PlanValidator.validate(ids: proposal.ids, candidates: pool, allowYours: false)
                let total = valid.reduce(Int64(0)) { $0 + $1.estimate.planning }
                selection = Set(valid.map(\.id))
                reply = "\(proposal.rationale) I ticked \(valid.count) item\(valid.count == 1 ? "" : "s") in Review, about \(ByteFormat.string(total))."
                if total < goal { reply += " That is \(ByteFormat.string(goal - total)) short of your goal, and the rest would have to come from files only you can judge." }
            } catch { reply = "The assistant couldn't plan just now. The goal card on Overview uses the built-in planner instead." }
            messages.append(.init(role: .assistant, text: reply, source: adv.name)); isAsking = false; Haptics.play(.confirm)
        }
    }

    func explain(_ c: Candidate) {
        guard explanations[c.id] == nil else { return }
        let ctx = AdvisorContext(candidates: [c], free: freeBytes, total: totalBytes, redactNames: AdvisorFactory.shouldRedact(settings.advisorMode), catalog: catalog)
        guard let item = ctx.items.first else { return }
        let adv = advisor
        Task {
            var text = try? await adv.explain(item)
            if text == nil { text = try? await RuleAdvisor().explain(item) }
            explanations[c.id] = text ?? ""
        }
    }
}
