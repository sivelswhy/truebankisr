import SwiftUI
import WidgetKit

struct BalanceEntry: TimelineEntry {
    var date: Date
    var data: WidgetData?
}

struct BalanceProvider: TimelineProvider {
    static let sample = WidgetData(trueBalance: 1_240, nextChargeDay: nil, nextChargeTotal: 2_860, dailyBudget: 95,
                                   updatedAt: .now, hideAmounts: false, isDemo: true)

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: .now, data: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(BalanceEntry(date: .now, data: context.isPreview ? WidgetData.load() ?? Self.sample : WidgetData.load()))
    }

    /// The app reloads the widgets after each refresh; nothing to schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        completion(Timeline(entries: [BalanceEntry(date: .now, data: WidgetData.load())], policy: .never))
    }
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BalanceEntry

    var body: some View {
        Group {
            if let d = entry.data {
                switch family {
                case .accessoryInline: inline(d)
                case .accessoryCircular: circular(d)
                case .accessoryRectangular: rectangular(d)
                default: home(d)
                }
            } else {
                Text("Open True Balance to connect your accounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func amount(_ d: WidgetData, _ value: Double, whole: Bool = false) -> String {
        if d.hideAmounts { return "₪ ••••" }
        return value.formatted(.currency(code: "ILS").precision(.fractionLength(whole ? 0 : 2)))
    }

    private func day(_ d: WidgetData) -> String? {
        d.nextChargeDay.flatMap(Self.date(fromDay:))?.formatted(.dateTime.day().month(.abbreviated))
    }

    private func home(_ d: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Really available")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(amount(d, d.trueBalance, whole: family == .systemSmall))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(d.trueBalance < 0 ? .red : .primary)
                .privacySensitive()
            if let day = day(d) {
                Text("After Max · \(day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let budget = d.dailyBudget, family != .systemSmall || !d.hideAmounts {
                Text("about \(amount(d, budget, whole: true))/day")
                    .font(.caption2)
                    .privacySensitive()
            }
            Text(d.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rectangular(_ d: WidgetData) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("True balance")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text(amount(d, d.trueBalance, whole: true))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .privacySensitive()
            if let day = day(d) {
                Text("After Max · \(day)").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circular(_ d: WidgetData) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "shekelsign")
                .font(.caption2)
            Text(d.hideAmounts ? "••" : Self.compact(d.trueBalance))
                .font(.system(.body, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.5)
                .privacySensitive()
        }
    }

    private func inline(_ d: WidgetData) -> some View {
        Text("₪ \(d.hideAmounts ? "••••" : Self.compact(d.trueBalance)) available")
            .privacySensitive()
    }

    /// 1240 → "1.2K".
    static func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
    }

    static func date(fromDay day: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}

struct TrueBalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TrueBalance", provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("True balance")
        .description("What’s really available after the next Max debit.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct TrueBalanceWidgets: WidgetBundle {
    var body: some Widget {
        TrueBalanceWidget()
    }
}
