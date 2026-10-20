import Charts
import SwiftUI
import TrueBalanceCore

enum Profile {
    /// "Bonjour, Léa" / "Hello, Léa".
    static func greeting(name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? String(localized: "Hello") : String(localized: "Hello, \(n)")
    }
}

struct ProfileAvatar: View {
    var name: String
    var size: CGFloat

    var body: some View {
        let initial = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() }
        Circle()
            .fill(LinearGradient(colors: [Color(hex: "#0A84FF"), Color(hex: "#0040C8")], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                if let initial {
                    Text(initial)
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white)
                }
            }
    }
}

/// Card spending over any period, by day or month and by category.
struct SpendingTab: View {
    @Environment(AppModel.self) private var model

    enum Preset: String, CaseIterable, Identifiable {
        case week, month30, thisMonth, lastMonth
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .week: "7 days"
            case .month30: "30 days"
            case .thisMonth: "This month"
            case .lastMonth: "Last month"
            }
        }

        func range(now: Date = .now) -> ClosedRange<Date> {
            let cal = Israel.calendar
            let today = cal.startOfDay(for: now)
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            switch self {
            case .week: return cal.date(byAdding: .day, value: -6, to: today)!...now
            case .month30: return cal.date(byAdding: .day, value: -29, to: today)!...now
            case .thisMonth: return monthStart...now
            case .lastMonth:
                let start = cal.date(byAdding: .month, value: -1, to: monthStart)!
                return start...cal.date(byAdding: .second, value: -1, to: monthStart)!
            }
        }
    }

    @State private var preset: Preset? = .thisMonth
    @State private var from = Preset.thisMonth.range().lowerBound
    @State private var to = Date.now

    var body: some View {
        TabScreen(title: String(localized: "Spending")) {
            List {
                if model.snapshot == nil {
                    NoDataView()
                } else {
                    periodSection
                    summary
                    exportSection
                }
            }
            .headerProminence(.increased)
            .listSectionSpacing(20)
        }
    }

    /// The presets as chips; the dates only for a custom period.
    @ViewBuilder
    private var periodSection: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Preset.allCases) { p in
                        Button(p.label) {
                            withAnimation(.snappy) {
                                preset = p
                                from = p.range().lowerBound
                                to = p.range().upperBound
                            }
                        }
                        .buttonStyle(ChipStyle(selected: preset == p))
                    }
                    Button {
                        withAnimation(.snappy) { preset = nil }
                    } label: {
                        Label("Custom", systemImage: "calendar")
                    }
                    .buttonStyle(ChipStyle(selected: preset == nil))
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .cardRow()
            .sensoryFeedback(.selection, trigger: preset)
        }

        if preset == nil {
            Section {
                DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from...Date.now, displayedComponents: .date)
            }
        }
    }

    private var exportSection: some View {
        let txns = Spending.purchases(model.allPurchases, from: from, to: to)
        return Section {
            ShareLink(item: CSVFile(name: csvName, text: CSVExport.make(txns, notes: model.notes)),
                      preview: SharePreview(csvName)) {
                Label("Export \(txns.count) purchase(s) as CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(txns.isEmpty)
        }
    }

    @ViewBuilder
    private var summary: some View {
        let txns = Spending.purchases(model.allPurchases, from: from, to: to).sorted { $0.date > $1.date }
        let total = Spending.total(txns)
        let days = max(1, (Israel.calendar.dateComponents([.day], from: Israel.calendar.startOfDay(for: from),
                                                          to: Israel.calendar.startOfDay(for: to)).day ?? 0) + 1)
        Section {
            HeroCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Card spending")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(total.shekels)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: total))
                        .privacySensitive()
                    HStack(spacing: 6) {
                        Text("\(txns.count) purchase(s)")
                        Text(verbatim: "·")
                        Text("about \((total / Double(days)).formatted(.currency(code: "ILS").precision(.fractionLength(0))))/day")
                            .privacySensitive()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if !txns.isEmpty {
                        CumulativeSpendChart(txns: txns, from: from, to: to)
                            .padding(.top, 4)
                    }
                }
            }
            .cardRow()
        } footer: {
            if let oldest = model.allPurchases.last?.date {
                Text("Max purchases since \(oldest.formatted(.dateTime.day().month(.wide).year())).")
            }
        }
        .animation(.default, value: txns)

        if !txns.isEmpty {
            CategoryBreakdownSection(txns: txns, caption: periodCaption)
            Section {
                ForEach(txns) { t in
                    NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
                }
            } header: {
                Text("Purchases")
            }
        } else {
            ContentUnavailableView("No purchases", systemImage: "cart", description: Text("Nothing on your Max card in this period."))
                .listRowBackground(Color.clear)
        }
    }

    /// "truebalance-2026-10-01_2026-10-19.csv".
    private var csvName: String {
        "truebalance-\(Israel.day(from))_\(Israel.day(to)).csv"
    }

    private var periodCaption: String {
        "\(from.formatted(.dateTime.day().month(.abbreviated))) – \(to.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}

/// Running total over the period; touch and hold to read it on a given day.
private struct CumulativeSpendChart: View {
    var txns: [Txn]
    var from: Date
    var to: Date
    @State private var selected: Date?

    struct Point: Identifiable {
        var day: Date
        var total: Double
        var id: Date { day }
    }

    private var points: [Point] {
        var running = 0.0
        return Spending.buckets(txns, from: from, to: to, by: .day).map {
            running += $0.total
            return Point(day: $0.start, total: (running * 100).rounded() / 100)
        }
    }

    var body: some View {
        let points = points
        let picked = selected.flatMap { s in
            points.last { $0.day <= s } ?? points.first
        }
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Day", p.day, unit: .day), y: .value("Total", p.total))
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", p.day, unit: .day), y: .value("Total", p.total))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let picked {
                RuleMark(x: .value("Day", picked.day, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(picked.total.shekels)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .privacySensitive()
                            Text(picked.day.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
                PointMark(x: .value("Day", picked.day, unit: .day), y: .value("Total", picked.total))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(60)
            }
        }
        .chartXSelection(value: $selected)
        .chartGesture { proxy in
            // Only a touch-and-hold picks a day, so the list still scrolls.
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, let drag?) = value {
                        proxy.selectXValue(at: drag.location.x)
                    }
                }
                .onEnded { _ in selected = nil }
        }
        .sensoryFeedback(.selection, trigger: picked?.day)
        .chartYAxis {
            AxisMarks(position: .trailing) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let n = v.as(Double.self) {
                        Text(n.formatted(.number.notation(.compactName)))
                    }
                }
            }
        }
        .frame(height: 170)
        .padding(.top, 24)
    }
}
