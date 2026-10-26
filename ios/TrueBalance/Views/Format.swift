import Observation
import SwiftUI
import TrueBalanceCore

/// A second currency for people used to another one (a French person in
/// Israel thinking in euros): amounts in shekels with the converted amount in
/// grey underneath, or the other way round. Converted at the Bank of Israel
/// rate of the last refresh. Observable, so every amount on screen follows a
/// change in Settings.
@MainActor
@Observable
final class DisplayCurrency {
    static let shared = DisplayCurrency()
    /// The ones the Bank of Israel publishes, most likely first.
    static let choices = ["EUR", "USD", "GBP", "CHF", "CAD", "AUD", "JPY", "SEK", "NOK", "DKK", "JOD", "EGP", "ZAR"]

    /// "" = shekels only.
    var code: String = UserDefaults.standard.string(forKey: "displayCurrency") ?? "" {
        didSet { UserDefaults.standard.set(code, forKey: "displayCurrency") }
    }
    /// The other currency on top, shekels in grey underneath.
    var first: Bool = UserDefaults.standard.bool(forKey: "displayCurrencyFirst") {
        didSet { UserDefaults.standard.set(first, forKey: "displayCurrencyFirst") }
    }
    /// Shekels per unit, from the last snapshot.
    var rates: [String: Double] = [:]

    /// Shekels per unit of `code`, when there's one to convert with.
    var rate: Double? { code.isEmpty ? nil : rates[code].flatMap { $0 > 0 ? $0 : nil } }
    /// The main line is in the other currency.
    var otherFirst: Bool { first && rate != nil }

    static func format(_ value: Double, _ currency: String, whole: Bool = false) -> String {
        let v = value == 0 ? 0 : value // also catches −0
        return whole
            ? v.formatted(.currency(code: currency).precision(.fractionLength(0)))
            : v.formatted(.currency(code: currency))
    }

    /// A converted amount starts with ≈: it's an estimate, unlike a purchase
    /// actually paid in that currency (`original`), shown exactly.
    func format(_ shekels: Double, whole: Bool, inOther: Bool, original: (amount: Double, currency: String)? = nil) -> String {
        guard inOther else { return Self.format(shekels, "ILS", whole: whole) }
        if let original, original.currency == code { return Self.format(original.amount, code, whole: whole) }
        return "≈ " + Self.format(shekels / (rate ?? 1), code, whole: whole)
    }

    func primary(_ shekels: Double, whole: Bool = false, original: (amount: Double, currency: String)? = nil) -> String {
        format(shekels, whole: whole, inOther: otherFirst, original: original)
    }

    /// The grey line, nil when no second currency is set.
    func secondary(_ shekels: Double, whole: Bool = false, original: (amount: Double, currency: String)? = nil) -> String? {
        rate == nil ? nil : format(shekels, whole: whole, inOther: !first, original: original)
    }
}

extension Txn {
    /// What a purchase paid in a foreign currency cost there, as an expense.
    var original: (amount: Double, currency: String)? {
        isForeignPurchase ? (-(originalAmount ?? 0), originalCurrency ?? "") : nil
    }
}

extension Double {
    /// In the display currency: shekels unless the other currency comes first.
    @MainActor var shekels: String { DisplayCurrency.shared.primary(self) }
    /// "₪1,500" without agorot, for budgets and summaries.
    @MainActor var wholeShekels: String { DisplayCurrency.shared.primary(self, whole: true) }
    /// Always in shekels, for amounts typed in shekels (alert threshold, budgets).
    var ils: String { (self == 0 ? 0 : self).formatted(.currency(code: "ILS")) }
}

/// An amount with the other currency in grey underneath when one is set.
/// Style it like a Text: font and colour apply to the main line.
struct Money: View {
    var amount: Double
    var prefix: String = ""
    var whole = false
    var alignment: HorizontalAlignment = .trailing
    var secondaryFont: Font = .caption
    /// What a purchase in a foreign currency actually cost there.
    var original: (amount: Double, currency: String)?

    init(_ amount: Double, prefix: String = "", whole: Bool = false, alignment: HorizontalAlignment = .trailing,
         secondaryFont: Font = .caption, original: (amount: Double, currency: String)? = nil) {
        self.amount = amount
        self.prefix = prefix
        self.whole = whole
        self.alignment = alignment
        self.secondaryFont = secondaryFont
        self.original = original
    }

    var body: some View {
        let display = DisplayCurrency.shared
        VStack(alignment: alignment, spacing: 1) {
            Text(prefix + display.primary(amount, whole: whole, original: original))
            if let other = display.secondary(amount, whole: whole, original: original) {
                Text(prefix + other)
                    .font(secondaryFont.weight(.regular))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .privacySensitive()
    }
}

enum Format {
    /// "2 Nov" / "2 nov." for a YYYY-MM-DD day.
    static func day(_ day: String) -> String {
        Israel.date(fromDay: day)?.formatted(.dateTime.day().month(.abbreviated)) ?? day
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "2 Nov, 14:32" when the bank gave the time, else "2 Nov".
    static func dayTime(_ date: Date) -> String {
        Israel.hasTime(date) ? date.formatted(.dateTime.day().month(.abbreviated).hour().minute()) : day(date)
    }

    /// "Monday 2 November 2026 at 14:32" when the bank gave the time.
    static func fullDate(_ date: Date) -> String {
        Israel.hasTime(date)
            ? date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
            : date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
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
        let name = provider == .leumi ? String(localized: "Leumi") : String(localized: "Max")
        return switch error {
        case .invalidCredentials: String(localized: "\(name) didn’t accept this username or password.")
        case .changePassword: String(localized: "\(name) asks you to change your password. Do it on their site, then sign in again.")
        case .blocked: String(localized: "Your \(name) account is blocked. Contact \(name).")
        case .extraVerification: String(localized: "\(name) asked for an extra verification step. Sign in once on their website, then try again.")
        case .timeout: String(localized: "\(name) took too long to respond. The connection may be slow or the site busy: try again.")
        case .unavailable: String(localized: "Couldn’t reach \(name). Check your connection and try again.")
        case .offline: String(localized: "No internet connection. The update will start again as soon as you’re back online.")
        case .refused: String(localized: "\(name) refused the connection from this network. This happens from abroad or through a VPN: turn the VPN off or try another network.")
        case .maintenance: String(localized: "\(name)’s site is under maintenance or unavailable for now. Try again later.")
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
        case .unavailable(let detail), .refused(let detail), .maintenance(let detail): detail
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

/// A pill to pick one option among a few (period, bank, tag): filled with
/// `tint` when selected. The unselected fill is translucent, so it shows both
/// inside a list row and on the grouped background. Shrinks under the finger.
struct ChipStyle: ButtonStyle {
    var selected: Bool
    var tint: Color = .accentColor
    /// Less on the leading side when the label starts with a logo.
    var leading: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.leading, leading)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.fill.tertiary), in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
            .animation(.snappy, value: selected)
    }
}
