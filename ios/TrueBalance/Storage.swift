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
