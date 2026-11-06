import Testing
import Foundation
import CryptoKit
@testable import RoomCore

@Suite("Paths and sizes") struct PathAndSizeTests {
    @Test func expandsTildeAndWildcards() throws {
        let sb = try Sandbox()
        try sb.file("Library/Caches/a.ShipIt/x.bin"); try sb.file("Library/Caches/b.ShipIt/y.bin"); try sb.file("Library/Caches/other/z.bin")
        let hits = PathExpander.expand("~/Library/Caches/*.ShipIt", home: sb.home).map(\.lastPathComponent).sorted()
        #expect(hits == ["a.ShipIt", "b.ShipIt"])
        #expect(PathExpander.expand("~/nope/*", home: sb.home).isEmpty)
        #expect(PathExpander.expand("relative/path", home: sb.home).isEmpty)
    }

    @Test func sparseFilesReportAllocatedNotLogicalSize() throws {
        let sb = try Sandbox()
        let url = sb.home.appendingPathComponent("sparse.img")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: 1_000_000_000)   // 1 GB logical, nothing written
        try h.close()
        let est = SizeEstimator.estimate(at: url)
        #expect(est.allocated < 10_000_000, "a 1 GB sparse file must not look like 1 GB")
    }

    @Test func apfsClonesAreNotCountedAsFreeable() throws {
        let sb = try Sandbox()
        let original = try sb.file("orig.bin", bytes: 40_000_000)
        let clone = sb.home.appendingPathComponent("clone.bin")
        let r = CommandRunner.run("cp", ["-c", original.path, clone.path])
        try #require(r.ok, "cp -c failed: \(r.output)")
        let est = SizeEstimator.estimate(at: clone)
        #expect(est.allocated >= 40_000_000)
        #expect(est.guaranteed < est.allocated / 2, "a clone shares its blocks, so deleting it frees little")
        #expect(est.isAmbiguous)
        #expect(est.planning == est.guaranteed)
    }

    @Test func plainFilesAreFullyFreeable() throws {
        let sb = try Sandbox()
        let f = try sb.file("plain.bin", bytes: 4_000_000)
        let est = SizeEstimator.estimate(at: f)
        #expect(est.guaranteed == est.allocated)
        #expect(!est.isAmbiguous)
    }

    @Test func symlinksAreNeverFollowed() throws {
        let sb = try Sandbox()
        let big = try sb.file("real/big.bin", bytes: 5_000_000)
        let dir = sb.home.appendingPathComponent("linkdir"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("l"), withDestinationURL: big)
        #expect(SizeEstimator.estimate(at: dir).allocated == 0)
    }

    @Test func dockerSizeParsing() {
        #expect(DockerInspector.parseDockerSize("28.66GB (91%)") == 28_660_000_000)
        #expect(DockerInspector.parseDockerSize("560.3MB") == 560_300_000)
        #expect(DockerInspector.parseDockerSize("0B") == 0)
        #expect(DockerInspector.parseDockerSize("garbage") == nil)
    }
}

@Suite("Safety rails") struct SafetyTests {
    @Test func protectedRootsAreNeverDeletable() throws {
        let sb = try Sandbox()
        for p in ["/", "/System", "/Users", sb.home.path, sb.home.appendingPathComponent("Documents").path,
                  sb.home.appendingPathComponent("Desktop").path, sb.home.appendingPathComponent(".ssh").path,
                  sb.home.appendingPathComponent("Library").path, "/Applications", "/private/var"] {
            #expect(!PathSafety.isDeletable(URL(fileURLWithPath: p), home: sb.home), "\(p) must be protected")
        }
        #expect(PathSafety.isDeletable(sb.home.appendingPathComponent("Documents/old.zip"), home: sb.home))
        #expect(PathSafety.isDeletable(sb.home.appendingPathComponent("Library/Caches/x"), home: sb.home))
        #expect(!PathSafety.isDeletable(URL(fileURLWithPath: "/usr/local/bin/tool"), home: sb.home))
        #expect(!PathSafety.isDeletable(URL(fileURLWithPath: "/etc/hosts"), home: sb.home))
    }

    @Test func pathTraversalCannotEscapeProtection() throws {
        let sb = try Sandbox()
        let sneaky = sb.home.appendingPathComponent("Library/Caches/../../Documents")
        #expect(!PathSafety.isDeletable(sneaky, home: sb.home))
        let up = sb.home.appendingPathComponent("../../etc")
        #expect(!PathSafety.isDeletable(up, home: sb.home))
    }

    @Test func gitGuardClassifiesRepos() throws {
        let sb = try Sandbox()
        let repo = sb.home.appendingPathComponent("proj"); try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        #expect(GitGuard.status(for: repo) == .notRepo)
        _ = CommandRunner.run("git", ["-C", repo.path, "init", "-q"])
        #expect(GitGuard.status(for: repo) == .noRemote)
        // a remote that exists, with an unpushed commit
        let bare = sb.root.appendingPathComponent("remote.git")
        _ = CommandRunner.run("git", ["init", "-q", "--bare", bare.path])
        _ = CommandRunner.run("git", ["-C", repo.path, "remote", "add", "origin", bare.path])
        try "a".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        #expect({ if case .dirty = GitGuard.status(for: repo) { return true } else { return false } }())
        _ = CommandRunner.run("git", ["-C", repo.path, "add", "."])
        _ = CommandRunner.run("git", ["-C", repo.path, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "x"])
        #expect({ if case .unpushed = GitGuard.status(for: repo) { return true } else { return false } }())
        _ = CommandRunner.run("git", ["-C", repo.path, "push", "-q", "origin", "HEAD"])
        #expect(GitGuard.status(for: repo) == .pushed)
    }
}

@Suite("Catalog") struct CatalogTests {
    @Test func builtInRulesAreWellFormed() {
        let rules = Catalog.builtIn.rules
        #expect(Set(rules.map(\.id)).count == rules.count, "rule ids must be unique")
        for r in rules {
            switch r.action {
            case .command(let c): #expect(r.paths.isEmpty); #expect(CommandID.allCases.contains(c))
            default: #expect(!r.paths.isEmpty, "\(r.id) needs paths")
                for p in r.paths { #expect(p.hasPrefix("~/") || p.hasPrefix("/"), "\(r.id): \(p) must be absolute or ~") }
            }
            #expect(!r.why.contains("—"), "\(r.id) copy has an em dash")
            #expect(!r.title.contains("—"))
        }
    }

    @Test func noBuiltInRuleTargetsAProtectedRoot() throws {
        let sb = try Sandbox()
        for r in Catalog.builtIn.rules {
            for p in r.paths where !p.contains("*") {
                let url = URL(fileURLWithPath: p.replacingOccurrences(of: "~", with: sb.home.path))
                if r.action == .deleteItem { #expect(PathSafety.isDeletable(url, home: sb.home), "\(r.id) deletes \(p)") }
            }
        }
    }

    @Test func signedCatalogVerifiesAndTamperingFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let data = try JSONEncoder().encode(Catalog(version: 99, rules: Catalog.builtIn.rules))
        let sig = try key.signature(for: data)
        #expect(try CatalogVerifier.decodeVerified(data: data, signature: sig, publicKeyBase64: pub).version == 99)
        var tampered = data; tampered.append(0x20)
        #expect(throws: CatalogVerifier.Failure.self) { try CatalogVerifier.verify(data: tampered, signature: sig, publicKeyBase64: pub) }
        #expect(throws: CatalogVerifier.Failure.self) { try CatalogVerifier.verify(data: data, signature: sig, publicKeyBase64: nil) }
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(throws: CatalogVerifier.Failure.self) { try CatalogVerifier.verify(data: data, signature: sig, publicKeyBase64: other) }
    }

    @Test func updaterIsDisabledWithoutAPinnedKey() async throws {
        let sb = try Sandbox()
        await #expect(throws: CatalogUpdater.UpdateError.self) { try await CatalogUpdater.update(paths: sb.paths, key: nil) }
        #expect(CatalogUpdater.current(paths: sb.paths).version == Catalog.builtIn.version)
    }

    @Test func catalogJSONRoundTrips() throws {
        let data = try JSONEncoder().encode(Catalog.builtIn)
        let back = try JSONDecoder().decode(Catalog.self, from: data)
        #expect(back.rules.count == Catalog.builtIn.rules.count)
        #expect(back.rule("cmd.docker-build")?.action == .command(.dockerBuilderPruneAndTrim))
    }
}

@Suite("Discovery") struct DiscoveryTests {
    @Test func findsCachesStaleNodeModulesInstallersAndVMs() async throws {
        let sb = try Sandbox()
        try sb.file("Library/Caches/com.spotify.client/blob", bytes: 3_000_000)
        try sb.file("Projects/old/package.json", bytes: 100); try sb.file("Projects/old/node_modules/dep/index.js", bytes: 2_000_000)
        try sb.age(sb.home.appendingPathComponent("Projects/old/package.json"), days: 200)
        try sb.age(sb.home.appendingPathComponent("Projects/old"), days: 200)
        try sb.file("Projects/fresh/package.json", bytes: 100); try sb.file("Projects/fresh/node_modules/dep/index.js", bytes: 2_000_000)
        try sb.file("Downloads/Thing.dmg", bytes: 2_000_000, age: 40)
        try sb.file("Downloads/Recent.dmg", bytes: 2_000_000, age: 1)
        try sb.file("Downloads/half.crdownload", bytes: 1_000_000)
        try sb.file("Virtual Machines.localized/Debian.vmwarevm/disk.vmdk", bytes: 4_000_000)

        let found = await Discovery(options: sb.options()).run()
        let titles = found.map(\.title)
        #expect(found.contains { $0.ruleID == "cache.spotify" && $0.tier == .safe && $0.preselected })
        #expect(titles.contains("node_modules: old"))
        #expect(!titles.contains("node_modules: fresh"), "an active project must not be flagged")
        #expect(titles.contains("Installer: Thing.dmg"))
        #expect(!titles.contains("Installer: Recent.dmg"), "a just-downloaded installer must not be flagged")
        #expect(titles.contains("Installer: half.crdownload"))
        let vm = try #require(found.first { $0.kind == .vm })
        #expect(vm.tier == .yours); #expect(!vm.preselected)
        #expect(found.sorted { $0.estimate.planning > $1.estimate.planning }.map(\.id) == found.map(\.id), "sorted largest first")
    }

    @Test func minAgeProtectsFreshUpdaterFiles() async throws {
        let sb = try Sandbox()
        try sb.file("Library/Caches/com.x.ShipIt/new.bin", bytes: 1_000_000)
        try sb.file("Library/Caches/com.x.ShipIt/old.bin", bytes: 1_000_000, age: 2)
        let found = await Discovery(options: sb.options()).run()
        let c = try #require(found.first { $0.ruleID == "cache.updaters" })
        #expect(c.targets.map(\.lastPathComponent) == ["old.bin"], "files modified within the last hour are left alone")
    }

    @Test func zipWithExtractedCopyIsFlagged() async throws {
        let sb = try Sandbox()
        try sb.file("Downloads/CN.zip", bytes: 2_000_000, age: 5); try sb.file("Downloads/CN/readme.txt", bytes: 100)
        try sb.file("Downloads/Solo.zip", bytes: 2_000_000, age: 5)
        let titles = await Discovery(options: sb.options()).run().map(\.title)
        #expect(titles.contains("Zip with extracted copy: CN.zip"))
        #expect(!titles.contains("Zip with extracted copy: Solo.zip"))
    }

    @Test func mergesMultiPathRulesIntoOneRow() async throws {
        let sb = try Sandbox()
        try sb.file("Library/Caches/Google/a", bytes: 2_000_000); try sb.file("Library/Caches/Mozilla/b", bytes: 2_000_000)
        let rows = await Discovery(options: sb.options()).run().filter { $0.ruleID == "cache.browsers" }
        #expect(rows.count == 1)
        #expect(rows[0].targets.count == 2)
    }
}

@Suite("Wording and titles") struct WordingTests {
    @Test func personalItemsAreNeverDescribedAsRebuildable() async throws {
        let sb = try Sandbox()
        try sb.file("Virtual Machines.localized/Debian.vmwarevm/disk.vmdk", bytes: 4_000_000)
        try sb.file("Downloads/Big/data.bin", bytes: 5_000_000, age: 200); try sb.age(sb.home.appendingPathComponent("Downloads/Big"), days: 200)
        var o = sb.options(); o.largeFileBytes = 1_000_000
        let found = await Discovery(options: o).run()
        let yours = found.filter { $0.tier == .yours }
        #expect(yours.count >= 2)
        for c in yours { #expect(c.regen == .never, "\(c.title) is personal data and cannot be rebuilt") }
        #expect(RegenCost.never.title == "Cannot be rebuilt")
    }

    @Test func perItemRulesGetDistinctTitles() async throws {
        let sb = try Sandbox()
        try sb.file("Library/Android/sdk/ndk/27.1/a.bin", bytes: 3_000_000); try sb.file("Library/Android/sdk/ndk/27.0/b.bin", bytes: 3_000_000)
        let titles = await Discovery(options: sb.options()).run().filter { $0.ruleID == "cache.android-ndk" }.map(\.title).sorted()
        #expect(titles == ["Android NDK versions: 27.0", "Android NDK versions: 27.1"])
    }
}
