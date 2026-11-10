import CryptoKit
import Foundation
import Security
import TrueBalanceCore

/// Encrypts the cache files below (balance, purchases, notes, subscriptions)
/// with a key that never leaves this device's Keychain, on top of Apple's own
/// file protection. Defense in depth: unreadable even if something ever read
/// the sandboxed file directly, not just while the device is locked.
enum LocalEncryption {
    private static let item = KeychainItem<Data>(account: "storage-key")

    /// 256-bit, made once; same Keychain tier as the bank credentials, so a
    /// background refresh can still decrypt and re-encrypt while the phone is locked.
    private static func key() -> SymmetricKey {
        if let existing = item.load(), existing.count == 32 { return SymmetricKey(data: existing) }
        var bytes = Data(count: 32)
        _ = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        item.save(bytes)
        return SymmetricKey(data: bytes)
    }

    static func seal(_ data: Data) -> Data? {
        try? AES.GCM.seal(data, using: key()).combined
    }

    static func open(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key())
    }

    /// Encrypts `data` and writes it, atomically, with the usual file protection.
    static func write(_ data: Data, to url: URL) {
        guard let sealed = seal(data) else { return }
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        try? sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Decrypts the file; falls back to it as plain data, so updating from a
    /// version that wrote these files unencrypted doesn't lose anything (the
    /// next `write` re-saves it encrypted).
    static func read(_ url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return open(raw) ?? raw
    }
}

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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        LocalEncryption.write(data, to: url)
    }

    static func load() -> Snapshot? {
        guard let data = LocalEncryption.read(url) else { return nil }
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
        guard let data = LocalEncryption.read(url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Txn].self, from: data)
    }

    static func save(_ txns: [Txn]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(txns) else { return }
        LocalEncryption.write(data, to: url)
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
        guard let data = LocalEncryption.read(url) else { return [:] }
        return (try? JSONDecoder().decode([String: PurchaseNote].self, from: data)) ?? [:]
    }

    static func save(_ notes: [String: PurchaseNote]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        LocalEncryption.write(data, to: url)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Which purchases the user flagged (or cleared) as subscriptions, and the ones typed in by hand.
enum SubscriptionStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "subscriptions.json")
    }

    static func load() -> SubscriptionSettings {
        guard let data = LocalEncryption.read(url) else { return SubscriptionSettings() }
        return (try? JSONDecoder().decode(SubscriptionSettings.self, from: data)) ?? SubscriptionSettings()
    }

    static func save(_ settings: SubscriptionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        LocalEncryption.write(data, to: url)
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
        guard let data = LocalEncryption.read(url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([EuroBankData].self, from: data)) ?? []
    }

    static func saveData(_ banks: [EuroBankData]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(banks) else { return }
        LocalEncryption.write(data, to: url)
    }

    static func deleteAll() {
        key.delete()
        connections.delete()
        try? FileManager.default.removeItem(at: url)
    }
}
