import Foundation

/// Max spending categories. Keys are stable; the app localizes them as
/// `category.<key>` in its String Catalog.
/// Source: https://onlinelcapi.max.co.il/api/contents/getCategories
public enum Category {
    public static let uncategorized = "uncategorized"

    /// Max `categoryId` → key.
    static let byMaxId: [Int: String] = [
        1: "insurance", 2: "energy", 3: "fashion", 4: "home", 5: "travel", 6: "electronics",
        7: "groceries", 8: "books", 9: "leisure", 10: "transport", 11: "government", 12: "health",
        13: "telecom", 14: "other", 15: "max", 16: "cash", 17: "transfer", 18: "pets",
        19: "beauty", 20: "restaurants", 21: "fx", 22: "max",
    ]

    public static func key(forMaxId id: Int?) -> String? {
        id.flatMap { byMaxId[$0] }
    }

    /// Hex colour per key (Max's own palette, so it matches their app).
    public static let colors: [String: String] = [
        "insurance": "#2550FF", "energy": "#3DC0E9", "fashion": "#00A3AD", "home": "#C20017",
        "travel": "#B200DF", "electronics": "#7800F7", "groceries": "#FF3F9B", "books": "#FF2A11",
        "leisure": "#FF7121", "transport": "#009950", "government": "#F9B300", "health": "#879AFF",
        "telecom": "#B6C700", "other": "#A1A1A6", "max": "#002AA9", "cash": "#1BC200",
        "transfer": "#AA82FF", "pets": "#922108", "beauty": "#FF8DAB", "restaurants": "#13E2BF",
        "fx": "#D9A364", uncategorized: "#A1A1A6",
    ]

    /// SF Symbol per key.
    public static let symbols: [String: String] = [
        "insurance": "umbrella.fill", "energy": "fuelpump.fill", "fashion": "tshirt.fill", "home": "sofa.fill",
        "travel": "airplane", "electronics": "desktopcomputer", "groceries": "cart.fill", "books": "book.fill",
        "leisure": "figure.run", "transport": "car.fill", "government": "building.columns.fill",
        "health": "cross.case.fill", "telecom": "antenna.radiowaves.left.and.right", "other": "square.grid.2x2.fill",
        "max": "creditcard.fill", "cash": "banknote.fill", "transfer": "arrow.left.arrow.right",
        "pets": "pawprint.fill", "beauty": "sparkles", "restaurants": "fork.knife", "fx": "dollarsign.circle.fill",
        uncategorized: "questionmark.circle.fill",
    ]

    public struct Total: Hashable, Identifiable, Sendable {
        public var key: String
        public var total: Double
        public var count: Int
        public var id: String { key }
    }

    /// Spend per category, biggest first.
    public static func totals(_ txns: [Txn]) -> [Total] {
        var map: [String: Total] = [:]
        for t in txns {
            let key = t.category ?? uncategorized
            map[key, default: Total(key: key, total: 0, count: 0)].total += -t.chargedAmount
            map[key]!.count += 1
        }
        return map.values
            .map { Total(key: $0.key, total: TrueBalance.round2($0.total), count: $0.count) }
            .sorted { $0.total > $1.total }
    }
}
