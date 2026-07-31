import Foundation

/// Minimal timestamped logger. No dependencies.
public enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let lock = NSLock()

    /// Optional sink so a GUI can mirror log lines into its own view.
    public static var sink: ((String) -> Void)?

    public static func info(_ message: @autoclosure () -> String) {
        let line = "\(formatter.string(from: Date()))  \(message())"
        write(stream: stdout, line)
        sink?(line)
    }

    public static func warn(_ message: @autoclosure () -> String) {
        let line = "\(formatter.string(from: Date()))  WARN  \(message())"
        write(stream: stderr, line)
        sink?(line)
    }

    public static func error(_ message: @autoclosure () -> String) {
        let line = "\(formatter.string(from: Date()))  ERROR \(message())"
        write(stream: stderr, line)
        sink?(line)
    }

    private static let stdout = FileHandle.standardOutput
    private static let stderr = FileHandle.standardError

    private static func write(stream: FileHandle, _ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data = (line + "\n").data(using: .utf8) {
            stream.write(data)
        }
    }
}
