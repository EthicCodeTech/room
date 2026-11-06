import Foundation

/// Developer switches (ROOM_DEV_* and the ROOM_SECTION / ROOM_APPEARANCE launch overrides) for screenshots and testing.
/// They exist only in debug builds. A release build, the kind you share, always sees nil, so nothing in the
/// environment can change what the app does.
enum Dev {
    static func env(_ key: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[key]
        #else
        nil
        #endif
    }
}
