import SwiftUI
import TrueBalanceCore

extension Double {
    var shekels: String { (self == 0 ? 0 : self).formatted(.currency(code: "ILS")) } // also catches −0
}

enum Format {
    /// "2 Nov" / "2 nov." for a YYYY-MM-DD day.
    static func day(_ day: String) -> String {
        Israel.date(fromDay: day)?.formatted(.dateTime.day().month(.abbreviated)) ?? day
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func categoryName(_ key: String?) -> String {
        NSLocalizedString("category." + (key ?? Category.uncategorized), comment: "Max spending category")
    }

    static func categoryColor(_ key: String?) -> Color {
        Color(hex: Category.colors[key ?? Category.uncategorized] ?? "#A1A1A6")
    }

    static func categorySymbol(_ key: String?) -> String {
        Category.symbols[key ?? Category.uncategorized] ?? "questionmark.circle.fill"
    }

    static func message(_ error: BankError, _ provider: Provider) -> String {
        let name = provider == .leumi ? "Leumi" : "Max"
        return switch error {
        case .invalidCredentials: String(localized: "\(name) didn’t accept this username or password.")
        case .changePassword: String(localized: "\(name) asks you to change your password. Do it on their site, then sign in again.")
        case .blocked: String(localized: "Your \(name) account is blocked. Contact \(name).")
        case .extraVerification: String(localized: "\(name) asked for an extra verification step. Sign in once on their website, then try again.")
        case .timeout: String(localized: "\(name) took too long to respond. Try again.")
        case .unavailable: String(localized: "Couldn’t reach \(name). Check your connection and try again.")
        }
    }
}

extension Format {
    /// Friendly wording for a scraper step ("Leumi: filling the form" →
    /// "Signing in to Leumi…").
    static func progress(_ step: String?) -> String {
        guard let step else { return String(localized: "Updating…") }
        let leumi = step.hasPrefix("Leumi")
        if step.contains("balance") || step.contains("transactions") || step.contains("advanced search") {
            return leumi ? String(localized: "Reading your Leumi balance…") : String(localized: "Reading your Max charges…")
        }
        return leumi ? String(localized: "Signing in to Leumi…") : String(localized: "Signing in to Max…")
    }

    /// Technical detail for troubleshooting (which step failed), not localized.
    static func detail(_ error: BankError) -> String? {
        switch error {
        case .timeout(let step): step
        case .unavailable(let detail): detail
        default: nil
        }
    }
}

/// Error message with its technical detail underneath.
struct BankErrorText: View {
    var error: BankError
    var provider: Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(Format.message(error, provider), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            if let detail = Format.detail(error) {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Category glyph in a tinted rounded square, like Settings / Wallet.
struct CategoryIcon: View {
    var key: String?
    @ScaledMetric(relativeTo: .body) private var size = 30

    var body: some View {
        Image(systemName: Format.categorySymbol(key))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Format.categoryColor(key).gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}
