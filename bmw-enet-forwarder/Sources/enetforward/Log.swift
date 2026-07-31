import Foundation

/// Minimal timestamped logger. No dependencies.
enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let lock = NSLock()

    static func info(_ message: @autoclosure () -> String) {
        write(stream: stdout, "\(formatter.string(from: Date()))  \(message())")
    }

    static func warn(_ message: @autoclosure () -> String) {
        write(stream: stderr, "\(formatter.string(from: Date()))  WARN  \(message())")
    }

    static func error(_ message: @autoclosure () -> String) {
        write(stream: stderr, "\(formatter.string(from: Date()))  ERROR \(message())")
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
