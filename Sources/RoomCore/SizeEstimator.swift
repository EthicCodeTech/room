import Foundation
import Darwin

/// What deleting something would really give back.
///
/// APFS clones and sparse files make plain `du` lie. We report two numbers:
/// - `allocated`: blocks the files occupy (what `du` shows; overstated for clones)
/// - `guaranteed`: blocks used by no other file, i.e. freed no matter what else remains
///
/// The truth for a set of clones that are all deleted together lies between them.
public struct SizeEstimate: Codable, Sendable, Equatable {
    public var allocated: Int64
    public var guaranteed: Int64

    public init(allocated: Int64 = 0, guaranteed: Int64 = 0) {
        self.allocated = allocated
        self.guaranteed = guaranteed
    }

    public static let zero = SizeEstimate()
    public var isAmbiguous: Bool { allocated - guaranteed > max(10_000_000, allocated / 5) }

    public static func + (l: SizeEstimate, r: SizeEstimate) -> SizeEstimate {
        SizeEstimate(allocated: l.allocated + r.allocated, guaranteed: l.guaranteed + r.guaranteed)
    }

    /// A single number to rank by: be conservative when it's ambiguous.
    public var planning: Int64 { isAmbiguous ? guaranteed : allocated }

    public var display: String {
        isAmbiguous
            ? "\(ByteFormat.string(guaranteed)) to \(ByteFormat.string(allocated))"
            : ByteFormat.string(allocated)
    }
}

public enum SizeEstimator {
    private static let attrCmnExtPrivateSize: UInt32 = 0x0000_0008   // ATTR_CMNEXT_PRIVATESIZE
    private static let fsoptAttrCmnExtended: UInt32 = 0x0000_0020    // FSOPT_ATTR_CMN_EXTENDED
    private static let fsoptNoFollow: UInt32 = 0x0000_0001           // FSOPT_NOFOLLOW

    /// Bytes owned only by this file (not shared with a clone). nil if unsupported.
    public static func privateSize(ofFileAt path: String) -> Int64? {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.forkattr = attrCmnExtPrivateSize
        var buffer = [UInt8](repeating: 0, count: 32)
        let rc = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &list, raw.baseAddress, raw.count, fsoptAttrCmnExtended | fsoptNoFollow)
        }
        guard rc == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> Int64 in
            Int64(raw.loadUnaligned(fromByteOffset: 4, as: Int64.self))
        }
    }

    /// Estimate for a file or whole directory tree. Symlinks are never followed.
    public static func estimate(at url: URL, precise: Bool = true) -> SizeEstimate {
        // Without the clone check there is nothing per-file to do, so use the bulk walker: several times faster.
        if !precise { let bytes = FastSize.allocatedBytes(atPath: url.path); return SizeEstimate(allocated: bytes, guaranteed: bytes) }
        let fm = FileManager.default
        var total = SizeEstimate.zero
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]

        func add(_ fileURL: URL, _ values: URLResourceValues) {
            guard values.isRegularFile == true else { return }
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard allocated > 0 else { return }
            var guaranteed = allocated
            if precise, let p = privateSize(ofFileAt: fileURL.path) { guaranteed = min(p, allocated) }
            total.allocated += allocated
            total.guaranteed += guaranteed
        }

        if let v = try? url.resourceValues(forKeys: keys), v.isSymbolicLink != true {
            if v.isRegularFile == true { add(url, v); return total }
        } else { return total }

        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                         options: [], errorHandler: { _, _ in true }) else { return total }
        for case let item as URL in walker {
            guard let v = try? item.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            add(item, v)
        }
        return total
    }

    /// Cheap allocated-only size for big tree scans.
    public static func allocatedBytes(at url: URL) -> Int64 { FastSize.allocatedBytes(atPath: url.path) }
}
