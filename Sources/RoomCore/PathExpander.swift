import Foundation

/// Expands `~` and single-component wildcards (`*`, `?`, `[...]`) into existing URLs.
public enum PathExpander {
    public static func expand(_ pattern: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var p = pattern
        if p == "~" { p = home.path }
        else if p.hasPrefix("~/") { p = home.path + "/" + p.dropFirst(2) }
        guard p.hasPrefix("/") else { return [] }

        let fm = FileManager.default
        var results = [URL(fileURLWithPath: "/")]
        for comp in p.split(separator: "/").map(String.init) {
            var next: [URL] = []
            if comp.contains(where: { "*?[".contains($0) }) {
                for base in results {
                    guard let names = try? fm.contentsOfDirectory(atPath: base.path) else { continue }
                    for name in names where fnmatch(comp, name, 0) == 0 {
                        next.append(base.appendingPathComponent(name))
                    }
                }
            } else {
                for base in results {
                    let candidate = base.appendingPathComponent(comp)
                    if fm.fileExists(atPath: candidate.path) || (try? candidate.checkResourceIsReachable()) == true {
                        next.append(candidate)
                    }
                }
            }
            results = next
            if results.isEmpty { return [] }
        }
        return results
    }
}
