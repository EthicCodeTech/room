import Foundation

/// Hard rules that run before any deletion. Learned models and AI can never relax these.
public enum PathSafety {
    public static func protectedPaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<String> {
        var set: Set<String> = ["/", "/System", "/Users", "/Library", "/Applications", "/private", "/private/var",
                                "/usr", "/bin", "/sbin", "/opt", "/Volumes", "/cores", "/etc", "/var"]
        set.insert(home.path)
        for sub in ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Library", "Projects",
                    "Applications", ".ssh", ".gnupg", "Public", "Library/Application Support", "Library/Keychains",
                    "Library/Mail", "Library/Messages", "Library/Containers", "Library/Group Containers"] {
            set.insert(home.appendingPathComponent(sub).path)
        }
        return set
    }

    /// A target is deletable only if it is strictly inside the user's space or a known cache location,
    /// and is not one of the protected roots themselves.
    public static func isDeletable(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = url.standardizedFileURL.path
        guard !path.isEmpty, path != "/" else { return false }
        if protectedPaths(home: home).contains(path) { return false }
        let underHome = path.hasPrefix(home.path + "/")
        let underApplications = path.hasPrefix("/Applications/") && path.split(separator: "/").count >= 3
        let underOpt = path.hasPrefix("/opt/") && path.split(separator: "/").count >= 3
        let underVarFolders = path.hasPrefix("/private/var/folders/")
        let underVolumes = path.hasPrefix("/Volumes/") && path.split(separator: "/").count >= 3
        return underHome || underApplications || underOpt || underVarFolders || underVolumes
    }
}

public enum FreeSpace {
    /// Real free bytes on the volume holding `url` (matches what the disk actually has free).
    public static func available(at url: URL = FileManager.default.homeDirectoryForCurrentUser) -> Int64 {
        var st = statfs()
        guard statfs(url.path, &st) == 0 else { return 0 }
        return Int64(st.f_bavail) * Int64(st.f_bsize)
    }
    public static func total(at url: URL = FileManager.default.homeDirectoryForCurrentUser) -> Int64 {
        var st = statfs()
        guard statfs(url.path, &st) == 0 else { return 0 }
        return Int64(st.f_blocks) * Int64(st.f_bsize)
    }
}
