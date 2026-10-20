import CoreTransferable
import Foundation
import UIKit
import UniformTypeIdentifiers

/// What the app did, for troubleshooting: sign-in steps, retries, errors,
/// network changes. Kept on this iPhone (the last few hundred KB), never with
/// credentials or amounts, and only leaves it when you export it.
enum Log {
    private static let queue = DispatchQueue(label: "il.truebalance.log")
    private static let maxBytes = 400_000

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "log.txt")
    }

    static func add(_ message: String) {
        let line = "\(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current))) \(message)\n"
        print(line, terminator: "")
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url, options: .completeFileProtectionUntilFirstUserAuthentication)
            }
            // Keep the newest half once it grows too big.
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes,
               let data = try? Data(contentsOf: url) {
                var tail = data.suffix(maxBytes / 2)
                if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) { tail = tail[tail.index(after: newline)...] }
                try? Data(tail).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    static func text() -> String {
        queue.sync { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}

/// The log as a .txt file for the share sheet (Mail, Messages, Files…), with
/// a header describing the app and the phone.
struct LogFile: Transferable {
    var header: String

    var name: String { "truebalance-log-\(Date.now.formatted(.iso8601.year().month().day())).txt" }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            let body = Log.text()
            try Data((file.header + "\n" + (body.isEmpty ? "(empty)\n" : body)).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    @MainActor
    static func header(model: AppModel) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        var lines = [
            "True Balance \(version)",
            "iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model), \(Locale.current.identifier)",
            "Exported \(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current)))",
            "Network: \(Connectivity.shared.isOnline ? "online" : "offline")",
            "Demo: \(model.isDemo)",
        ]
        if let at = model.snapshot?.computedAt {
            lines.append("Last update: \(at.formatted(Date.ISO8601FormatStyle(timeZone: .current)))")
        }
        for (provider, error) in model.refreshErrors.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append("Current error \(provider.rawValue): \(error)")
        }
        if !model.euroConnections.isEmpty {
            lines.append("Other banks: " + model.euroConnections.map { "\($0.bank.id) until \($0.validUntil.formatted(.iso8601.year().month().day()))" }
                .joined(separator: ", "))
        }
        for (id, error) in model.euroErrors.sorted(by: { $0.key < $1.key }) {
            lines.append("Current error \(id): \(error)")
        }
        return lines.joined(separator: "\n") + "\n" + String(repeating: "-", count: 40)
    }
}
