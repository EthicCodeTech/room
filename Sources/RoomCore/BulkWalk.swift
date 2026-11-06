import Foundation
import Darwin

/// Measures a folder with `getattrlistbulk`, which returns the attributes of hundreds of entries per system call
/// instead of one `stat` per file. On folders with many small files (node_modules, caches) that is several times
/// faster than `fts`. Symlinks are never followed and other volumes are not crossed.
///
/// Returns nil when the kernel interface is unavailable for this path, so the caller can fall back to `fts`.
enum BulkWalk {
    private static let bufferSize = 256 * 1024
    private static let attrCmnName: UInt32 = 0x0000_0001
    private static let attrCmnObjType: UInt32 = 0x0000_0008
    private static let attrCmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let attrFileAllocSize: UInt32 = 0x0000_0004
    private static let packInvalidAttrs: UInt64 = 0x0000_0008        // FSOPT_PACK_INVAL_ATTRS
    private static let vReg: UInt32 = 1, vDir: UInt32 = 2

    static func measure(path: String) -> FastSize.Result? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return FastSize.Result(bytes: 0, rootUnreadable: true) }
        let mode = st.st_mode & S_IFMT
        if mode == S_IFREG { return FastSize.Result(bytes: Int64(st.st_blocks) * 512, rootUnreadable: false) }
        guard mode == S_IFDIR else { return FastSize.Result(bytes: 0, rootUnreadable: false) }
        let rootDevice = st.st_dev

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(attrCmnReturnedAttrs | attrCmnName | attrCmnObjType)
        attrs.fileattr = attrgroup_t(attrFileAllocSize)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var total: Int64 = 0
        var rootUnreadable = false
        var pending = [path]
        var visited = 0
        while let dir = pending.popLast() {
            visited += 1
            if visited & 0x3F == 0 && Task.isCancelled { break }
            let fd = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if fd < 0 { if dir == path { rootUnreadable = true }; continue }
            defer { close(fd) }
            var dst = stat()
            if fstat(fd, &dst) == 0, dst.st_dev != rootDevice { continue }               // do not cross into another volume

            while true {
                let count = getattrlistbulk(fd, &attrs, buffer, bufferSize, packInvalidAttrs)
                if count < 0 {
                    if dir == path && visited == 1 && total == 0 { return nil }          // unsupported here: let the caller use fts
                    break
                }
                if count == 0 { break }
                var entry = UnsafeRawPointer(buffer)
                for _ in 0..<count {
                    let length = Int(entry.loadUnaligned(as: UInt32.self))
                    var cursor = entry + 4
                    let returnedCommon = cursor.loadUnaligned(as: UInt32.self)
                    let returnedFile = (cursor + 12).loadUnaligned(as: UInt32.self)       // attribute_set_t: common, vol, dir, file, fork
                    cursor += 20
                    var namePointer: UnsafePointer<CChar>?
                    if returnedCommon & attrCmnName != 0 {
                        let offset = Int(cursor.loadUnaligned(as: Int32.self))
                        namePointer = (cursor + offset).assumingMemoryBound(to: CChar.self)
                        cursor += 8                                                       // attrreference_t
                    }
                    var type: UInt32 = 0
                    if returnedCommon & attrCmnObjType != 0 { type = cursor.loadUnaligned(as: UInt32.self); cursor += 4 }
                    if type == vReg, returnedFile & attrFileAllocSize != 0 {
                        total += Int64(cursor.loadUnaligned(as: Int64.self))
                    } else if type == vDir, let namePointer {
                        pending.append(dir + "/" + String(cString: namePointer))
                    }
                    entry += length
                }
            }
        }
        return FastSize.Result(bytes: total, rootUnreadable: rootUnreadable)
    }
}
