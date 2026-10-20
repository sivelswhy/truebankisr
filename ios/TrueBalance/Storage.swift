import Foundation
import Security
import TrueBalanceCore

/// Bank credentials in the iOS Keychain, this device only. Readable after the
/// first unlock so background refresh can sign in while the phone is locked.
enum Keychain {
    struct Stored: Codable, Equatable {
        var leumi: Credentials
        var max: Credentials
    }

    private static var base: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "TrueBalance",
        kSecAttrAccount as String: "bank-credentials",
    ] }

    static func save(_ value: Stored) throws {
        let data = try JSONEncoder().encode(value)
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load() -> Stored? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

/// Last computed balance, so the app opens instantly with data.
enum SnapshotStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "snapshot.json")
    }

    static func save(_ snapshot: Snapshot) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Past Max purchases (see `PurchaseCache`), kept across refreshes.
enum PurchaseCacheStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "purchases.json")
    }

    static func load() -> [Txn]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Txn].self, from: data)
    }

    static func save(_ txns: [Txn]) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(txns).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Notes and tags on purchases, by purchase id. Only on this iPhone.
enum NotesStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "notes.json")
    }

    static func load() -> [String: PurchaseNote] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: PurchaseNote].self, from: data)) ?? [:]
    }

    static func save(_ notes: [String: PurchaseNote]) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(notes).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Monthly budget per category key, in ILS.
enum BudgetStore {
    static func load() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: "budgets") as? [String: Double] ?? [:]
    }

    static func save(_ limits: [String: Double]) {
        UserDefaults.standard.set(limits.filter { $0.value > 0 }, forKey: "budgets")
    }
}

/// One Codable value in the Keychain, this device only (like `Keychain`).
struct KeychainItem<Value: Codable> {
    var account: String

    private var base: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "TrueBalance",
        kSecAttrAccount as String: account,
    ] }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        SecItemDelete(base as CFDictionary)
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> Value? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func delete() {
        SecItemDelete(base as CFDictionary)
    }
}

/// Enable Banking: the app key and the bank sessions (secrets), and the last
/// balances and transactions read (a file, like the snapshot).
enum EuroStore {
    static let key = KeychainItem<EnableBankingKey>(account: "enablebanking-key")
    static let connections = KeychainItem<[EuroConnection]>(account: "enablebanking-sessions")

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "euro-banks.json")
    }

    static func loadData() -> [EuroBankData] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([EuroBankData].self, from: data)) ?? []
    }

    static func saveData(_ banks: [EuroBankData]) {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(banks).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func deleteAll() {
        key.delete()
        connections.delete()
        try? FileManager.default.removeItem(at: url)
    }
}
