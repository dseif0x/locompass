import Foundation

/// In-app debug log: keeps a rolling in-memory buffer for the Settings screen
/// and appends everything to a file in Documents for export — phone-only
/// iterative development, no attached log viewer needed.
final class Log: ObservableObject {
    static let shared = Log()

    @Published private(set) var lines: [String] = []
    let fileURL: URL

    private static let writeQueue = DispatchQueue(label: "locompass.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("locompass-log.txt")
    }

    static func add(_ tag: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(tag)] \(message)"
        print(line)
        if Thread.isMainThread {
            shared.append(line)
        } else {
            DispatchQueue.main.async { shared.append(line) }
        }
        writeQueue.async {
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: shared.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: shared.fileURL)
            }
        }
    }

    private func append(_ line: String) {
        lines.append(line)
        if lines.count > 3000 { lines.removeFirst(lines.count - 3000) }
    }

    func clear() {
        lines.removeAll()
        Log.writeQueue.async { try? Data().write(to: self.fileURL) }
    }
}
