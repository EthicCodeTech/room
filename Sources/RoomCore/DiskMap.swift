import Foundation
import CoreGraphics

public struct DiskNode: Identifiable, Sendable, Equatable, Codable {
    public var id: String { path }
    public let path: String
    public let name: String
    public var bytes: Int64
    public var children: [DiskNode]
    public var isDirectory: Bool
    /// False for a folder whose contents were measured but not listed (drill in to expand it).
    public var isExpanded: Bool
    /// True when macOS wouldn't let us read this folder (usually Full Disk Access).
    public var isUnreadable: Bool
    /// A synthetic node standing in for many small items.
    public var isAggregate: Bool

    public init(path: String, name: String, bytes: Int64, children: [DiskNode], isDirectory: Bool,
                isExpanded: Bool = true, isUnreadable: Bool = false, isAggregate: Bool = false) {
        self.path = path; self.name = name; self.bytes = bytes; self.children = children; self.isDirectory = isDirectory
        self.isExpanded = isExpanded; self.isUnreadable = isUnreadable; self.isAggregate = isAggregate
    }

    /// Finds a node by path, descending only along the matching branch.
    public func find(_ target: String) -> DiskNode? {
        if path == target { return self }
        guard target.hasPrefix(path == "/" ? "/" : path + "/") else { return nil }
        for c in children { if let hit = c.find(target) { return hit } }
        return nil
    }

    /// Replaces the node at `node.path` with a deeper scan of the same folder, leaving every other size untouched.
    public func grafting(_ node: DiskNode) -> DiskNode {
        if path == node.path { return node }
        guard node.path.hasPrefix(path == "/" ? "/" : path + "/") else { return self }
        var copy = self
        copy.children = children.map { $0.grafting(node) }
        return copy
    }

    /// Keeps the biggest `max` children and folds the rest into one aggregate node, so no bytes are lost.
    public func trimmed(maxChildren max: Int) -> DiskNode {
        guard children.count > max else { return self }
        let sorted = children.sorted { $0.bytes > $1.bytes }
        let keep = Array(sorted.prefix(max)), rest = sorted.dropFirst(max)
        var copy = self
        copy.children = keep + [DiskNode(path: path + "/\u{0}smaller", name: "\(rest.count) smaller items",
                                         bytes: rest.reduce(0) { $0 + $1.bytes }, children: [], isDirectory: false, isAggregate: true)]
        return copy
    }
}

/// Squarified treemap layout (Bruls et al.). Pure geometry, so it's easy to test.
public enum Treemap {
    public struct Tile: Identifiable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var bytes: Int64
        public var rect: CGRect
    }

    public static func layout(_ items: [(id: String, name: String, bytes: Int64)], in rect: CGRect) -> [Tile] {
        let data = items.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        let total = Double(data.reduce(0) { $0 + $1.bytes })
        guard total > 0, rect.width > 0, rect.height > 0 else { return [] }
        let area = Double(rect.width * rect.height)
        var scaled = data.map { (item: $0, area: Double($0.bytes) / total * area) }
        var tiles: [Tile] = []
        var free = rect
        while !scaled.isEmpty {
            let shortSide = Double(min(free.width, free.height))
            var row: [(item: (id: String, name: String, bytes: Int64), area: Double)] = []
            var best = Double.infinity
            for entry in scaled {
                let candidate = row + [entry]
                let worst = worstRatio(candidate.map(\.area), shortSide)
                if worst <= best { row = candidate; best = worst } else { break }
            }
            scaled.removeFirst(row.count)
            let rowArea = row.reduce(0) { $0 + $1.area }
            let horizontal = free.width >= free.height     // lay the row along the short side
            let thickness = shortSide > 0 ? rowArea / shortSide : 0
            var offset = 0.0
            for e in row {
                let length = rowArea > 0 ? e.area / rowArea * shortSide : 0
                let r: CGRect = horizontal
                    ? CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                    : CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                tiles.append(Tile(id: e.item.id, name: e.item.name, bytes: e.item.bytes, rect: r))
                offset += length
            }
            free = horizontal
                ? CGRect(x: free.minX + thickness, y: free.minY, width: free.width - thickness, height: free.height)
                : CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: free.height - thickness)
        }
        return tiles
    }

    /// The tile under a point. Edges are half-open, so a point on a shared border belongs to exactly one tile.
    public static func tile(at point: CGPoint, in tiles: [Tile]) -> Tile? { tiles.first { $0.rect.contains(point) } }

    private static func worstRatio(_ areas: [Double], _ side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, side > 0 else { return .infinity }
        let mx = areas.max()!, mn = areas.min()!
        return max(side * side * mx / (sum * sum), (sum * sum) / (side * side * mn))
    }
}
