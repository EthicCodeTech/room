import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public var ok: Bool { status == 0 }
}

/// Runs external tools. Rules reference fixed `CommandID`s, never free-form shell,
/// so a tampered catalog cannot execute arbitrary commands.
public enum CommandRunner {
    /// Finds an executable in the usual developer locations (GUI apps get a minimal PATH).
    public static func locate(_ tool: String) -> String? {
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                    NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/.cargo/bin"]
        return dirs.map { $0 + "/" + tool }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 600) -> CommandResult {
        guard let path = locate(tool) else { return CommandResult(status: 127, output: "\(tool) not found") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return CommandResult(status: 126, output: "\(error)") }

        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let reader = DispatchQueue(label: "room.cmd.read")
        let group = DispatchGroup()
        group.enter()
        reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        group.wait()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
