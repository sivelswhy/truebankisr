import Charts
import SwiftUI
import TrueBalanceCore
import UniformTypeIdentifiers

// MARK: - Forecast

/// "Expected on 2 Nov, salary included", under the hero.
struct ForecastRow: View {
    var forecast: Forecast

    var body: some View {
        NavigationLink {
            ForecastView(forecast: forecast)
        } label: {
            LabeledContent {
                Text(forecast.projectedBalance.shekels)
                    .monospacedDigit()
                    .foregroundStyle(forecast.projectedBalance < 0 ? .red : .primary)
                    .privacySensitive()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Expected on \(Format.day(forecast.until))")
                        Text(forecast.income.isEmpty ? "Including regular debits" : "Salary and regular debits included")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
            }
        }
    }
}

struct ForecastView: View {
    @Environment(AppModel.self) private var model
    var forecast: Forecast

    var body: some View {
        let s = model.snapshot
        let all = s.flatMap { $0.bankTxns }.map { RecurringDetector.detect($0.filter { !TrueBalance.isCardDebit($0) }) } ?? []
        List {
            Section {
                if let s {
                    LabeledContent("Available after Max", value: s.trueBalance.shekels)
                }
                ForEach(forecast.income) { r in
                    LabeledContent(r.name, value: "+" + r.amount.shekels).foregroundStyle(.green)
                }
                ForEach(forecast.debits) { r in
                    LabeledContent(r.name, value: r.amount.shekels)
                }
                LabeledContent("Expected on \(Format.day(forecast.until))", value: forecast.projectedBalance.shekels)
                    .fontWeight(.semibold)
            } footer: {
                Text("Regular Leumi movements expected before the debit, detected from the last months: same payer or payee, about the same amount, every month.")
            }
            .monospacedDigit()
            .privacySensitive()

            if !all.isEmpty {
                Section {
                    ForEach(all) { r in
                        RecurringRow(item: r)
                    }
                } header: {
                    Text("Every month on Leumi")
                }
            }
        }
        .navigationTitle("Forecast")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// A recurring movement: name, next date, amount.
struct RecurringRow: View {
    var item: Recurring

    var body: some View {
        HStack(spacing: 12) {
            if item.amount > 0 {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            } else {
                CategoryIcon(key: item.category)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text("Next around \(Format.day(item.nextDate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.amount > 0 ? "+" + item.amount.shekels : (-item.amount).shekels)
                .monospacedDigit()
                .foregroundStyle(item.amount > 0 ? .green : .primary)
                .privacySensitive()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

/// Per card: what the next debit takes from it, and the credit line.
struct CardsSection: View {
    var snapshot: Snapshot

    var body: some View {
        let next = Spending.byCard(snapshot.nextCharge?.txns ?? [])
        let infos = snapshot.cards ?? []
        let ids = Array(Set(next.compactMap(\.last4) + infos.map(\.last4))).sorted()
        if ids.count > 1 || !infos.isEmpty {
            Section {
                ForEach(ids, id: \.self) { last4 in
                    CardSummaryRow(last4: last4, nextDebit: next.first { $0.last4 == last4 }?.total ?? 0,
                                   info: infos.first { $0.last4 == last4 })
                }
            } header: {
                Text("Cards")
            } footer: {
                if let next = snapshot.nextCharge {
                    Text("Amounts debited \(Format.day(next.chargeDate)).")
                }
            }
        }
    }
}

private struct CardSummaryRow: View {
    var last4: String
    var nextDebit: Double
    var info: CardInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill").foregroundStyle(Color.accentColor)
                Text(verbatim: "•• \(last4)").monospacedDigit()
                Spacer()
                Text(nextDebit.shekels).monospacedDigit().privacySensitive()
            }
            if let info, let limit = info.creditLimit, let used = info.used, limit > 0 {
                Gauge(value: min(max(used / limit, 0), 1)) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(used / limit > 0.8 ? .orange : .accentColor)
                HStack {
                    Text("Used \(used.wholeShekels)")
                    Spacer()
                    Text("Left \((info.available ?? 0).wholeShekels) of \(limit.wholeShekels)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .privacySensitive()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Subscriptions

struct SubscriptionsView: View {
    var subscriptions: [Recurring]

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(Subscriptions.monthlyTotal(subscriptions).shekels)
                        .font(.title2.bold())
                        .monospacedDigit()
                        .privacySensitive()
                } label: {
                    VStack(alignment: .leading) {
                        Text("Per month")
                        Text("\((Subscriptions.monthlyTotal(subscriptions) * 12).wholeShekels) a year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .privacySensitive()
                    }
                }
            }
            Section {
                ForEach(subscriptions) { s in
                    NavigationLink(value: MerchantRoute(key: s.name.lowercased(), name: s.name)) {
                        RecurringRow(item: s)
                    }
                }
            } footer: {
                Text("Max charges from the same merchant, for the same amount, every month. Installment plans aren’t included.")
            }
        }
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Wealth

struct WealthView: View {
    var wealth: Wealth

    var body: some View {
        List {
            Section {
                Text(wealth.total.shekels)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .privacySensitive()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Total")
            } footer: {
                Text("Current account after the Max debits already known, savings and foreign-currency accounts at today’s Bank of Israel rate.")
            }
            Section {
                ForEach(wealth.lines) { line in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(line.amount.shekels)
                            if let original = line.original, let currency = line.currency {
                                Text(original.formatted(.currency(code: currency)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                        .privacySensitive()
                    } label: {
                        Label(title(line), systemImage: symbol(line.kind))
                    }
                }
                ForEach(wealth.unconverted) { f in
                    LabeledContent {
                        Text(f.balance.formatted(.currency(code: f.currency))).monospacedDigit().privacySensitive()
                    } label: {
                        Label("\(f.currency) account (not counted, no rate)", systemImage: "globe")
                    }
                }
            }
        }
        .navigationTitle("Net worth")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func title(_ line: Wealth.Line) -> String {
        switch line.kind {
        case .current: String(localized: "Leumi current account")
        case .card: String(localized: "Max charges to come")
        case .savings: line.name.isEmpty ? String(localized: "Savings") : line.name
        case .foreign: String(localized: "\(line.name) account")
        }
    }

    private func symbol(_ kind: Wealth.Line.Kind) -> String {
        switch kind {
        case .current: "building.columns"
        case .card: "creditcard"
        case .savings: "banknote"
        case .foreign: "globe"
        }
    }
}

// MARK: - Budgets

struct BudgetsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        let progress = model.budgetProgress
        List {
            if progress.isEmpty {
                ContentUnavailableView {
                    Label("No budgets yet", systemImage: "gauge.with.dots.needle.33percent")
                } description: {
                    Text("Set a monthly amount for a category, e.g. groceries ₪1,500. You’ll get a notification at 80% and 100%.")
                } actions: {
                    Button("Set budgets") { editing = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(progress) { p in
                        BudgetRow(progress: p)
                    }
                } footer: {
                    Text("Max purchases since the 1st of the month. Notifications at 80% and 100%.")
                }
            }
        }
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !progress.isEmpty {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { BudgetEditView() }
    }
}

struct BudgetRow: View {
    var progress: BudgetProgress

    var body: some View {
        let color: Color = progress.ratio >= 1 ? .red : progress.ratio >= 0.8 ? .orange : Format.categoryColor(progress.category)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CategoryIcon(key: progress.category)
                Text(Format.categoryName(progress.category))
                Spacer()
                Text(progress.ratio.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            Gauge(value: min(progress.ratio, 1)) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(color)
            HStack {
                Text("\(progress.spent.wholeShekels) spent")
                Spacer()
                Text(progress.spent <= progress.limit
                    ? String(localized: "\((progress.limit - progress.spent).wholeShekels) left")
                    : String(localized: "\((progress.spent - progress.limit).wholeShekels) over"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .privacySensitive()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct BudgetEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Categories seen on the card first, then the rest.
    private var keys: [String] {
        let seen = TrueBalanceCore.Category.totals(model.allPurchases).map(\.key)
        let rest = TrueBalanceCore.Category.colors.keys.filter { !seen.contains($0) }.sorted()
        return seen + rest
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(keys, id: \.self) { key in
                        HStack(spacing: 12) {
                            CategoryIcon(key: key)
                            Text(Format.categoryName(key))
                            Spacer()
                            TextField("None", value: Binding(
                                get: { model.budgets[key] },
                                set: { model.setBudget($0 ?? 0, for: key) }
                            ), format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                            Text(verbatim: "₪").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Monthly amount. Leave empty for no budget.")
                }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Month comparison

struct MonthComparisonView: View {
    var comparison: MonthComparison

    var body: some View {
        let rows = comparison.byCategory.filter { abs($0.value) >= 1 }.sorted { abs($0.value) > abs($1.value) }
        List {
            Section {
                LabeledContent("This month", value: comparison.thisMonth.shekels)
                LabeledContent("Last month, same days", value: comparison.lastMonthSamePeriod.shekels)
                LabeledContent("Last month, whole", value: comparison.lastMonthTotal.shekels)
                    .foregroundStyle(.secondary)
                if let change = comparison.change {
                    LabeledContent("Change") {
                        ChangeBadge(change: change)
                    }
                }
            }
            .monospacedDigit()
            .privacySensitive()

            if !rows.isEmpty {
                Section {
                    ForEach(rows, id: \.key) { key, delta in
                        HStack(spacing: 12) {
                            CategoryIcon(key: key)
                            Text(Format.categoryName(key))
                            Spacer()
                            Label((delta > 0 ? "+" : "") + delta.wholeShekels,
                                  systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(delta > 0 ? .red : .green)
                                .monospacedDigit()
                                .privacySensitive()
                        }
                    }
                } header: {
                    Text("By category")
                } footer: {
                    Text("Compared with the same days of last month.")
                }
            }
        }
        .navigationTitle("Month to month")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// "+12 %" in red (spending more) or "−8 %" in green.
struct ChangeBadge: View {
    var change: Double

    var body: some View {
        Text((change > 0 ? "+" : "") + change.formatted(.percent.precision(.fractionLength(0))))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(change > 0 ? .red : .green)
    }
}

// MARK: - Insights links on the dashboard

struct InsightsSection: View {
    @Environment(AppModel.self) private var model
    var snapshot: Snapshot

    var body: some View {
        let history = model.allPurchases
        let subs = Subscriptions.detect(history)
        let comparison = Spending.compareMonths(history)
        let budgets = model.budgetProgress
        let wealth = Wealth.of(snapshot)
        Section {
            NavigationLink {
                MonthComparisonView(comparison: comparison)
            } label: {
                LabeledContent {
                    if let change = comparison.change { ChangeBadge(change: change) }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This month vs last month")
                            Text("\(comparison.thisMonth.wholeShekels) so far").font(.caption).foregroundStyle(.secondary).privacySensitive()
                        }
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                }
            }
            NavigationLink {
                BudgetsView()
            } label: {
                LabeledContent {
                    if let worst = budgets.first {
                        Text(worst.ratio.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(worst.ratio >= 1 ? .red : worst.ratio >= 0.8 ? .orange : .secondary)
                            .monospacedDigit()
                    }
                } label: {
                    Label("Budgets", systemImage: "gauge.with.dots.needle.33percent")
                }
            }
            if !subs.isEmpty {
                NavigationLink {
                    SubscriptionsView(subscriptions: subs)
                } label: {
                    LabeledContent {
                        Text("\(Subscriptions.monthlyTotal(subs).wholeShekels)/month").monospacedDigit().privacySensitive()
                    } label: {
                        Label("\(subs.count) subscription(s)", systemImage: "repeat")
                    }
                }
            }
            if snapshot.savings != nil || snapshot.foreignAccounts != nil {
                NavigationLink {
                    WealthView(wealth: wealth)
                } label: {
                    LabeledContent {
                        Text(wealth.total.wholeShekels).monospacedDigit().privacySensitive()
                    } label: {
                        Label("Net worth", systemImage: "building.columns")
                    }
                }
            }
        } header: {
            Text("Insights")
        }
    }
}

// MARK: - Notes

struct NoteSection: View {
    @Environment(AppModel.self) private var model
    var txnID: String
    @State private var text = ""
    @State private var addingTag = false
    @State private var newTag = ""

    /// Suggested even before they've been used once.
    static let presetTags = [String(localized: "Work"), String(localized: "Reimbursed"), String(localized: "Shared")]

    var body: some View {
        let note = model.notes[txnID] ?? PurchaseNote()
        let tags = Array(NSOrderedSet(array: Self.presetTags + model.knownTags + note.tags)) as? [String] ?? []
        Section {
            TextField("Add a note (e.g. reimbursed by Dana)", text: $text, axis: .vertical)
                .onAppear { text = note.text }
                .onChange(of: text) { _, value in
                    var n = model.notes[txnID] ?? PurchaseNote()
                    n.text = value
                    model.setNote(n, for: txnID)
                }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        let on = note.tags.contains(tag)
                        Button {
                            var n = model.notes[txnID] ?? PurchaseNote()
                            if on { n.tags.removeAll { $0 == tag } } else { n.tags.append(tag) }
                            model.setNote(n, for: txnID)
                        } label: {
                            Label(tag, systemImage: on ? "checkmark" : "tag")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                                .foregroundStyle(on ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        addingTag = true
                    } label: {
                        Image(systemName: "plus")
                            .padding(7)
                            .background(Color.secondary.opacity(0.15), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("New tag"))
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        } header: {
            Text("Note and tags")
        } footer: {
            Text("Kept on this iPhone only, and included in the CSV export.")
        }
        .alert("New tag", isPresented: $addingTag) {
            TextField("Tag", text: $newTag)
            Button("Add") {
                let tag = newTag.trimmingCharacters(in: .whitespaces)
                newTag = ""
                guard !tag.isEmpty else { return }
                var n = model.notes[txnID] ?? PurchaseNote()
                if !n.tags.contains(tag) { n.tags.append(tag) }
                model.setNote(n, for: txnID)
            }
            Button("Cancel", role: .cancel) { newTag = "" }
        }
    }
}

// MARK: - CSV export

/// A CSV file for the share sheet (Numbers, Excel, Files…).
struct CSVFile: Transferable {
    var name: String
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            // BOM so Excel opens the Hebrew merchant names as UTF-8.
            try Data(("\u{FEFF}" + file.text).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

extension Double {
    /// "₪1,500" without agorot, for budgets and summaries.
    var wholeShekels: String { (self == 0 ? 0 : self).formatted(.currency(code: "ILS").precision(.fractionLength(0))) }
}
