import Foundation

/// What the home and lock screen widgets show, written by the app into the
/// shared App Group container. Compiled into both targets.
struct WidgetData: Codable, Equatable {
    var trueBalance: Double
    /// YYYY-MM-DD of the next Max debit, Israel time.
    var nextChargeDay: String?
    var nextChargeTotal: Double?
    var dailyBudget: Double?
    var updatedAt: Date
    var hideAmounts: Bool
    var isDemo: Bool

    /// Set in Info.plist (`TBAppGroup`) from the APP_GROUP_ID build setting.
    static var appGroup: String? { Bundle.main.object(forInfoDictionaryKey: "TBAppGroup") as? String }

    private static var url: URL? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appending(path: "widget.json")
    }

    static func load() -> WidgetData? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetData.self, from: data)
    }

    /// No-op when the App Group isn't available (e.g. signing without it).
    static func save(_ value: WidgetData?) {
        guard let url else { return }
        guard let value else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
