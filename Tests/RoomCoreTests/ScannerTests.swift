import Testing
import Foundation
@testable import RoomCore

@Suite("Fast map scanner") struct ScannerTests {
    func tree(_ sb: Sandbox) throws {
        try sb.file("A/a1.bin", bytes: 3_000_000); try sb.file("A/deep/a2.bin", bytes: 2_000_000); try sb.file("A/deep/deeper/a3.bin", bytes: 1_000_000)
        try sb.file("B/b1.bin", bytes: 5_000_000); try sb.file("loose.bin", bytes: 500_000)
        let link = sb.home.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sb.home.appendingPathComponent("B"))
    }

    @Test func fastSizeAgreesWithTheSlowEstimator() throws {
        let sb = try Sandbox(); try tree(sb)
        for sub in ["A", "B", ""] {
            let url = sub.isEmpty ? sb.home : sb.home.appendingPathComponent(sub)
            let fast = FastSize.allocatedBytes(atPath: url.path), slow = SizeEstimator.estimate(at: url, precise: true).allocated      // the independent per-file implementation
            #expect(fast == slow, "\(sub.isEmpty ? "home" : sub): fts \(fast) vs enumerator \(slow)")
        }
    }

    @Test func missingAndUnreadablePathsAreSafe() throws {
        #expect(FastSize.allocatedBytes(atPath: "/definitely/not/here") == 0)
        let sb = try Sandbox(); try sb.file("locked/x.bin", bytes: 1_000_000)
        let dir = sb.home.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(FastSize.measure(path: dir.path).rootUnreadable, "a folder macOS won't let us read is reported, not called empty")
    }

    @Test func theTreeAddsUpAndSkipsSymlinks() async throws {
        let sb = try Sandbox(); try tree(sb)
        let root = await DiskScanner.scan(sb.home, depth: 3)
        #expect(Set(root.children.map(\.name)) == ["A", "B", "loose.bin"], "the symlink to B is not counted twice")
        let a = try #require(root.children.first { $0.name == "A" })
        #expect(a.bytes == a.children.reduce(0) { $0 + $1.bytes })
        #expect(root.bytes == root.children.reduce(0) { $0 + $1.bytes })
        #expect(abs(root.bytes - SizeEstimator.estimate(at: sb.home, precise: true).allocated) < 1_000_000)
        #expect(root.find(sb.home.appendingPathComponent("A/deep").path)?.name == "deep")
    }

    @Test func depthLimitsListingButNotMeasuring() async throws {
        let sb = try Sandbox(); try tree(sb)
        let shallow = await DiskScanner.scan(sb.home, depth: 1)
        let a = try #require(shallow.children.first { $0.name == "A" })
        #expect(a.children.isEmpty && !a.isExpanded, "not listed yet")
        #expect(a.bytes >= 6_000_000, "but its full size is known")
        let deep = await DiskScanner.scan(sb.home, depth: 3)
        #expect(deep.bytes == shallow.bytes)
    }

    @Test func progressIsMonotonicEndsComplete_andThePartialNeverExceedsTheTotal() async throws {
        let sb = try Sandbox(); try tree(sb)
        let seen = Box<[(done: Int, total: Int, bytes: Int64)]>([])
        let final = await DiskScanner.scan(sb.home, depth: 1) { partial, done, total in seen.value.append((done, total, partial.bytes)) }
        let calls = seen.value
        #expect(!calls.isEmpty); #expect(calls.last?.done == calls.last?.total, "the last report says the work is complete")
        #expect(calls.last?.total == 2, "depth 1 measures the folders A and B")
        #expect(zip(calls, calls.dropFirst()).allSatisfy { $0.done <= $1.done }, "progress never goes backwards")
        #expect(calls.allSatisfy { $0.bytes <= final.bytes }, "a partial map is never bigger than the finished one")
        #expect(calls.last?.bytes == final.bytes)
    }

    @Test func manyFoldersMeasuredInParallelGiveExactlyTheSameAnswerAsOneAtATime() async throws {
        let sb = try Sandbox()
        for i in 0..<24 { for j in 0..<4 { try sb.file("d\(i)/s\(j)/f.bin", bytes: 100_000 + i * 7_000 + j * 3_000) } }
        let parallel = await DiskScanner.scan(sb.home, depth: 3, concurrency: 8)
        let serial = await DiskScanner.scan(sb.home, depth: 3, concurrency: 1)
        #expect(parallel == serial, "concurrency must not change the result")
        #expect(abs(parallel.bytes - SizeEstimator.estimate(at: sb.home, precise: true).allocated) < 1_000_000)
    }

    @Test func hintsOnlyChangeTheOrderNeverTheResult() async throws {
        let sb = try Sandbox(); try tree(sb)
        let plain = await DiskScanner.scan(sb.home, depth: 3)
        let hinted = await DiskScanner.scan(sb.home, depth: 3, hints: plain)
        let wrongHints = DiskNode(path: sb.home.path, name: "x", bytes: 1, children: [DiskNode(path: sb.home.appendingPathComponent("B").path, name: "B", bytes: 9_999_999_999, children: [], isDirectory: true)], isDirectory: true)
        let misled = await DiskScanner.scan(sb.home, depth: 3, hints: wrongHints)
        #expect(plain == hinted); #expect(plain == misled, "bad hints are harmless")
    }

    @Test func everyDepthAgreesOnTheTotal() async throws {
        let sb = try Sandbox(); try tree(sb)
        let totals = await [DiskScanner.scan(sb.home, depth: 1).bytes, DiskScanner.scan(sb.home, depth: 2).bytes, DiskScanner.scan(sb.home, depth: 4).bytes]
        #expect(Set(totals).count == 1, "listing deeper must not change how big something is: \(totals)")
    }

    @Test func aCancelledScanStopsInsteadOfFinishingTheWholeDisk() async throws {
        let sb = try Sandbox()
        for i in 0..<30 { try sb.file("d\(i)/f.bin", bytes: 200_000) }
        let task = Task { await DiskScanner.scan(sb.home, depth: 3) }
        task.cancel()
        let result = await task.value
        #expect(result.children.count <= 30)      // returns promptly with whatever it had; must not hang or crash
    }

    @Test func trimmingKeepsEveryByte() {
        let kids = (1...60).map { DiskNode(path: "/r/\($0)", name: "\($0)", bytes: Int64($0) * 1000, children: [], isDirectory: false) }
        let root = DiskNode(path: "/r", name: "r", bytes: kids.reduce(0) { $0 + $1.bytes }, children: kids, isDirectory: true)
        let t = root.trimmed(maxChildren: 40)
        #expect(t.children.count == 41); #expect(t.children.last?.isAggregate == true)
        #expect(t.children.reduce(0) { $0 + $1.bytes } == root.bytes)
        #expect(t.children.first?.bytes == 60_000, "biggest first")
    }

    @Test func graftingADeeperScanChangesOnlyThatBranch() async throws {
        let sb = try Sandbox(); try tree(sb)
        let shallow = await DiskScanner.scan(sb.home, depth: 1)
        let a = sb.home.appendingPathComponent("A")
        let deeper = await DiskScanner.scan(a, depth: 3)
        let merged = shallow.grafting(deeper)
        #expect(merged.find(a.path)?.isExpanded == true); #expect(merged.find(a.path)?.children.isEmpty == false)
        #expect(merged.children.first { $0.name == "B" } == shallow.children.first { $0.name == "B" }, "other branches are untouched")
        #expect(merged.bytes == shallow.bytes)
    }

    @Test func theCacheSurvivesARestart() async throws {
        let sb = try Sandbox(); try tree(sb)
        let root = await DiskScanner.scan(sb.home, depth: 2)
        let url = sb.appRoot.appendingPathComponent("map.json")
        MapCache(root: root, scannedAt: Date(timeIntervalSince1970: 1_700_000_000)).save(to: url)
        let back = try #require(MapCache.load(from: url))
        #expect(back.root == root); #expect(back.scannedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(MapCache.load(from: sb.appRoot.appendingPathComponent("nope.json")) == nil)
    }

    @Test func foldersKnowWhatRoomCanFreeInsideThem() throws {
        let sb = try Sandbox()
        let cache = sb.home.appendingPathComponent("Library/Caches/x"), nm = sb.home.appendingPathComponent("Projects/p/node_modules")
        let mine = sb.home.appendingPathComponent("Downloads/photos")
        let list = [sb.candidate("c", tier: .safe, targets: [cache], bytes: 4_000), sb.candidate("n", tier: .rebuildable, targets: [nm], bytes: 9_000),
                    sb.candidate("y", tier: .yours, targets: [mine], bytes: 50_000),
                    sb.candidate("cmd", tier: .safe, targets: [], bytes: 700, action: .command(.brewCleanup))]
        let idx = FreeableIndex(candidates: list)
        #expect(idx.bytes(under: sb.home.path) == 13_000, "yours and commands are never counted")
        #expect(idx.bytes(under: sb.home.appendingPathComponent("Library").path) == 4_000)
        #expect(idx.bytes(under: sb.home.appendingPathComponent("Projects").path) == 9_000)
        #expect(idx.count(under: sb.home.path) == 2)
        #expect(idx.bytes(under: sb.home.appendingPathComponent("Lib").path) == 0, "a folder whose name merely starts the same is not a parent")
    }
}

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@Suite("Bulk walker matches fts exactly") struct BulkWalkTests {
    @Test func identicalTotalsOnAVariedTree() throws {
        let sb = try Sandbox()
        for i in 0..<30 { for j in 0..<6 { try sb.file("d\(i)/s\(j)/deep/f\(j).bin", bytes: 1_000 + i * 913 + j * 4_097) } }
        try sb.file("top.bin", bytes: 3_000_000); try sb.file("empty/.keep", bytes: 0)
        try FileManager.default.createSymbolicLink(at: sb.home.appendingPathComponent("lnk"), withDestinationURL: sb.home.appendingPathComponent("d0"))
        let sparse = sb.home.appendingPathComponent("sparse.img"); FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let h = try FileHandle(forWritingTo: sparse); try h.truncate(atOffset: 500_000_000); try h.close()
        let fast = FastSize.measure(path: sb.home.path), ref = FastSize.ftsMeasure(path: sb.home.path)
        #expect(fast == ref, "bulk \(fast.bytes) vs fts \(ref.bytes)")
        #expect(fast.bytes < 20_000_000, "the sparse file and the symlink are not counted as their logical size")
    }

    @Test func aFileASymlinkAndAMissingPathBehave() throws {
        let sb = try Sandbox(); let f = try sb.file("one.bin", bytes: 2_000_000)
        #expect(FastSize.measure(path: f.path) == FastSize.ftsMeasure(path: f.path))
        #expect(FastSize.measure(path: "/definitely/not/here").bytes == 0)
        let link = sb.home.appendingPathComponent("l"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f)
        #expect(FastSize.measure(path: link.path).bytes == 0, "a symlink itself is never followed")
    }

    @Test func manyEntriesInOneFolderSpanSeveralKernelBuffers() throws {
        let sb = try Sandbox()
        let dir = sb.home.appendingPathComponent("wide"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<6_000 { FileManager.default.createFile(atPath: dir.appendingPathComponent("f\(i)").path, contents: Data(repeating: 1, count: 100)) }
        #expect(FastSize.measure(path: dir.path) == FastSize.ftsMeasure(path: dir.path), "6,000 entries do not fit in one 256 KB buffer")
    }

    @Test func aFolderMacOSWontOpenIsReportedNotCalledEmpty() throws {
        let sb = try Sandbox(); try sb.file("locked/x.bin", bytes: 1_000_000)
        let dir = sb.home.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(FastSize.measure(path: dir.path).rootUnreadable)
    }

    @Test func cancellingStopsTheWalkEarly() async throws {
        let sb = try Sandbox()
        for i in 0..<400 { try sb.file("d\(i)/f.bin", bytes: 4_000) }
        let task = Task { FastSize.measure(path: sb.home.path) }
        task.cancel()
        _ = await task.value          // must return, not hang
    }
}

@Suite("Discovery speed-ups keep the answers") struct DiscoveryParityTests {
    @Test func concurrentDiscoveryFindsExactlyWhatTheSerialOneDid() async throws {
        let sb = try Sandbox()
        try sb.file("Library/Caches/com.spotify.client/blob", bytes: 3_000_000)
        try sb.file("Library/Caches/Google/a", bytes: 2_000_000); try sb.file("Library/Caches/Mozilla/b", bytes: 2_000_000)
        try sb.file("Projects/old/package.json", bytes: 100); try sb.file("Projects/old/node_modules/dep/index.js", bytes: 2_000_000)
        try sb.age(sb.home.appendingPathComponent("Projects/old/package.json"), days: 200); try sb.age(sb.home.appendingPathComponent("Projects/old"), days: 200)
        try sb.file("Downloads/Thing.dmg", bytes: 2_000_000, age: 40)
        let d = Discovery(options: sb.options())
        let concurrent = await d.run()
        let serialRules = d.ruleCandidates().filter { $0.kind != .command }
        let serialIDs = Set((serialRules + d.nodeModules() + d.downloadsAndDesktop() + d.virtualMachines()).filter { $0.estimate.planning >= 1 }.map(\.id))
        #expect(Set(concurrent.filter { $0.kind != .command }.map(\.id)) == serialIDs)
        for c in concurrent where c.kind != .command {
            let ref = (serialRules + d.nodeModules() + d.downloadsAndDesktop()).first { $0.id == c.id }
            #expect(ref == nil || ref!.estimate == c.estimate, "\(c.title): concurrent sizing must equal serial sizing")
        }
    }

    @Test func onlyCloneTaggedRulesPayForThePerFileCloneCheck() throws {
        let tagged = Catalog.builtIn.rules.filter { $0.tags.contains("clone") }.map(\.id)
        #expect(tagged == ["cache.chrome-clones"], "the clone check is reserved for rules that can actually contain clones")
    }

    @Test func aPlainFolderStillReportsFullyFreeableBytes() throws {
        let sb = try Sandbox(); try sb.file("c/a.bin", bytes: 3_000_000)
        let e = SizeEstimator.estimate(at: sb.home.appendingPathComponent("c"), precise: false)
        #expect(e.guaranteed == e.allocated); #expect(!e.isAmbiguous); #expect(e.allocated >= 3_000_000)
    }
}
