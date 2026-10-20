import Charts
import SwiftUI
import TrueBalanceCore

/// Signed in: one tab per question. What's really available, what leaves on
/// the 2nd, what was spent, and the analysis on top of it.
struct DashboardView: View {
    enum TabID: Hashable { case balance, charges, spending, insights }
    @State private var tab: TabID = .balance

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .balance) { BalanceTab() }
            Tab("Charges", systemImage: "creditcard", value: .charges) { ChargesTab() }
            Tab("Spending", systemImage: "chart.bar.xaxis", value: .spending) { SpendingTab() }
            Tab("Insights", systemImage: "lightbulb", value: .insights) { InsightsTab() }
        }
    }
}

/// What every tab shares: navigation, pull to refresh, the profile button,
/// hidden amounts, and the purchase / category pages.
struct TabScreen<Content: View>: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage("firstName") private var firstName = ""
    @State private var showingSettings = false
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar {
                    if model.isRefreshing || !model.refreshErrors.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) { RefreshStatusButton() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            ProfileAvatar(name: firstName, size: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Profile and settings"))
                    }
                }
                .refreshable { await model.refresh() }
                .sheet(isPresented: $showingSettings) { SettingsView() }
                .navigationDestination(for: CategoryRoute.self) { route in
                    CategoryDetailView(route: route)
                        .redacted(reason: hideAmounts ? .privacy : [])
                }
                .purchaseDestinations()
        }
        // On the stack, so pages opened from the tab are covered too.
        .redacted(reason: hideAmounts ? .privacy : [])
    }
}

/// Next to the profile while updating (a spinner) or after a failed update
/// (a warning sign). Tap it for the details.
struct RefreshStatusButton: View {
    @Environment(AppModel.self) private var model
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            if model.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityLabel(Text(model.isRefreshing ? LocalizedStringKey("Updating…") : "Update failed"))
        .popover(isPresented: $showingDetails) {
            RefreshStatusDetails()
                .frame(minWidth: 300, maxWidth: 360)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// What the status button shows: the current step, or what went wrong.
struct RefreshStatusDetails: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isRefreshing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(Format.progress(model.progressStep))
                        .font(.subheadline)
                        .contentTransition(.opacity)
                }
                .animation(.default, value: model.progressStep)
            } else {
                ForEach(Provider.allCases.filter { model.refreshErrors[$0] != nil }, id: \.self) { p in
                    BankErrorText(error: model.refreshErrors[p]!, provider: p)
                        .font(.subheadline)
                }
                Button("Try again", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .buttonStyle(.bordered)
            }
            if let at = model.snapshot?.computedAt {
                Text("Updated \(at.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Before the first refresh.
struct NoDataView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No data yet", systemImage: "arrow.clockwise")
        } description: {
            Text(model.isRefreshing
                ? Format.progress(model.progressStep)
                : String(localized: "Pull down to sign in to Leumi and Max."))
        }
        .listRowBackground(Color.clear)
    }
}

// MARK: - Home

/// What's really available (tap it for the calculation), then the latest payments.
struct BalanceTab: View {
    @Environment(AppModel.self) private var model
    @AppStorage("firstName") private var firstName = ""

    var body: some View {
        TabScreen(title: Profile.greeting(name: firstName)) {
            List {
                if let s = model.snapshot {
                    Section {
                        NavigationLink {
                            CalculationView()
                        } label: {
                            HeroView(snapshot: s, isDemo: model.isDemo)
                        }
                        if let f = Forecaster.forecast(s), !(f.income.isEmpty && f.debits.isEmpty) {
                            ForecastRow(forecast: f)
                        }
                    }
                    recentSection
                    LeumiSection()
                    Section {
                    } footer: {
                        TimelineView(.periodic(from: .now, by: 60)) { _ in
                            Text("Updated \(s.computedAt.formatted(.relative(presentation: .named)))")
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    NoDataView()
                }
            }
            // A little air between "Hello" and the balance.
            .contentMargins(.top, 20, for: .scrollContent)
            .animation(.default, value: model.snapshot)
            .sensoryFeedback(.success, trigger: model.snapshot?.computedAt)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = RecentPurchasesView.purchases(model.allPurchases)
        Section {
            if recent.isEmpty {
                Text("No purchases yet.").foregroundStyle(.secondary)
            }
            ForEach(recent.prefix(8)) { t in
                NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
            }
            if recent.count > 8 {
                NavigationLink("See all") { RecentPurchasesView() }
            }
        } header: {
            Text("Latest payments")
        }
    }
}

/// Every purchase, newest first, grouped by day.
struct RecentPurchasesView: View {
    @Environment(AppModel.self) private var model

    /// One row per purchase: later installments of the same purchase are left out.
    static func purchases(_ all: [Txn]) -> [Txn] {
        all.filter { ($0.installments?.number ?? 1) <= 1 }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let days = Dictionary(grouping: Self.purchases(model.allPurchases).prefix(300)) { Israel.day($0.date) }
        List {
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section {
                    ForEach(days[day]!) { t in
                        NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
                    }
                } header: {
                    HStack {
                        Text(Israel.date(fromDay: day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day)
                        Spacer()
                        Text(Spending.total(days[day]!).shekels).monospacedDigit().privacySensitive()
                    }
                }
            }
        }
        .navigationTitle("Latest payments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// How the true balance is obtained: Leumi − next Max debit, and per card.
struct CalculationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let s = model.snapshot {
                breakdown(s)
                CardsSection(snapshot: s)
            }
        }
        .navigationTitle("Calculation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    /// Leumi − Max = available.
    private func breakdown(_ s: Snapshot) -> some View {
        Section {
            LabeledContent {
                Text(s.bankBalance.shekels).privacySensitive()
            } label: {
                Label("Leumi balance", systemImage: "building.columns")
            }
            LabeledContent {
                Text((-(s.nextCharge?.total ?? 0)).shekels).privacySensitive()
            } label: {
                if let next = s.nextCharge {
                    Label("Max · \(Format.day(next.chargeDate))", systemImage: "creditcard")
                } else {
                    Label("Max", systemImage: "creditcard")
                }
            }
            LabeledContent {
                Text(s.trueBalance.shekels)
                    .foregroundStyle(s.trueBalance < 0 ? .red : .primary)
                    .privacySensitive()
            } label: {
                Label("Available", systemImage: "equal.circle")
            }
            .fontWeight(.semibold)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if s.upcoming.count > 1 {
                    Text("With later installments already committed: \(s.trueBalanceAllKnown.shekels)")
                }
                let converted = s.upcoming.flatMap(\.txns).filter(\.isConvertedEstimate).count
                if converted > 0 {
                    Text("Includes \(converted) foreign-currency charge(s) converted at the Bank of Israel rate (estimate).")
                }
                if !s.ignoredForeign.isEmpty {
                    Text("\(s.ignoredForeign.count) foreign-currency charge(s) not included.")
                }
            }
        }
        .monospacedDigit()
    }
}

// MARK: - Charges

/// What Max will take from Leumi: by debit date, by category, searchable.
struct ChargesTab: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        TabScreen(title: String(localized: "Charges")) {
            List {
                if let s = model.snapshot {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResults(s)
                    } else if s.upcoming.isEmpty {
                        ContentUnavailableView("Nothing to debit", systemImage: "checkmark.circle",
                                               description: Text("No Max charge is waiting to be debited."))
                            .listRowBackground(Color.clear)
                    } else {
                        if s.upcoming.count > 1 {
                            UpcomingDebitsChart(upcoming: s.upcoming)
                        }
                        if let next = s.nextCharge {
                            CategoryBreakdownSection(txns: next.txns, caption: String(localized: "Debited \(Format.day(next.chargeDate))"))
                        }
                        ForEach(s.upcoming) { charge in
                            Section {
                                ForEach(charge.txns) { t in
                                    NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
                                }
                            } header: {
                                HStack {
                                    Text("Debited \(Format.day(charge.chargeDate))")
                                    Spacer()
                                    Text(charge.total.shekels).monospacedDigit().privacySensitive()
                                }
                            }
                        }
                    }
                } else {
                    NoDataView()
                }
            }
            .searchable(text: $query, prompt: Text("Search charges"))
            .autocorrectionDisabled()
        }
    }

    /// Every upcoming charge whose merchant or category matches the search.
    @ViewBuilder
    private func searchResults(_ s: Snapshot) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = s.upcoming.flatMap { charge in charge.txns.map { (charge, $0) } }.filter { _, t in
            t.description.localizedStandardContains(q) || Format.categoryName(t.category).localizedStandardContains(q)
        }
        if matches.isEmpty {
            ContentUnavailableView.search(text: q)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(matches, id: \.1.id) { charge, t in
                    NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t, debitDay: charge.chargeDate) }
                }
            } header: {
                Text("\(matches.count) result(s)")
            } footer: {
                let total = matches.reduce(0) { $0 - $1.1.chargedAmount }
                Text("Total: \(total.shekels)").privacySensitive()
            }
        }
    }
}

private struct HeroView: View {
    var snapshot: Snapshot
    var isDemo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let next = snapshot.nextCharge {
                    Text("Really available after Max on \(Format.day(next.chargeDate))")
                } else {
                    Text("Really available")
                }
                if isDemo {
                    Text("DEMO")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(snapshot.trueBalance.shekels)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(snapshot.trueBalance < 0 ? .red : .primary)
                .contentTransition(.numericText(value: snapshot.trueBalance))
                .privacySensitive()

            if snapshot.trueBalance < 0 {
                Text("You’ll be overdrawn on the debit date unless money comes in first.")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if let next = snapshot.nextCharge {
                let days = TrueBalance.daysUntil(next.chargeDate)
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    if days == 0 {
                        Text("Max is debited today")
                    } else {
                        Text("\(days) day(s) until the debit")
                    }
                    if let budget = TrueBalance.dailyBudget(snapshot) {
                        Text("·")
                        Text("about \(budget.formatted(.currency(code: "ILS").precision(.fractionLength(0))))/day")
                            .privacySensitive()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The next debits side by side (installments make later months visible).
private struct UpcomingDebitsChart: View {
    var upcoming: [UpcomingCharge]

    var body: some View {
        Section {
            Chart(upcoming) { c in
                BarMark(
                    x: .value("Debit", Format.day(c.chargeDate)),
                    y: .value("Amount", c.total)
                )
                .foregroundStyle(c.id == upcoming.first?.id ? Color.accentColor.gradient : Color.secondary.opacity(0.5).gradient)
                .cornerRadius(6)
                .annotation(position: .top) {
                    Text(c.total.formatted(.currency(code: "ILS").precision(.fractionLength(0))))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .padding(.vertical, 8)
        } header: {
            Text("Upcoming debits")
        }
    }
}

struct TransactionRow: View {
    @Environment(AppModel.self) private var model
    var txn: Txn
    /// Shown when the row is outside its debit section (search results).
    var debitDay: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(key: txn.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(txn.description)
                        .lineLimit(1)
                    if model.notes[txn.id] != nil {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(Text("Has a note"))
                    }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((txn.isConvertedEstimate ? "≈ " : "") + (-txn.chargedAmount).shekels)
                    .monospacedDigit()
                    .privacySensitive()
                if let original = txn.originalAmount, let currency = txn.originalCurrency {
                    Text((-original).formatted(.currency(code: currency)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .privacySensitive()
                } else if txn.status == .pending {
                    Text("Pending")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button {
                UIPasteboard.general.string = txn.description
            } label: {
                Label("Copy merchant", systemImage: "doc.on.doc")
            }
            Button {
                UIPasteboard.general.string = String(format: "%.2f", -txn.chargedAmount)
            } label: {
                Label("Copy amount", systemImage: "number")
            }
        }
    }

    private var subtitle: String {
        var parts = [Format.day(txn.date), Format.categoryName(txn.category)]
        if let i = txn.installments {
            parts.append(String(localized: "\(i.number) of \(i.total)"))
        }
        if let debitDay {
            parts.append(String(localized: "Debited \(Format.day(debitDay))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// A category within a list of purchases (a debit, or a period in the profile).
struct CategoryRoute: Hashable {
    var key: String
    var txns: [Txn]
    /// Shown under the list, e.g. "Debited 2 Nov".
    var caption: String
}

/// Where the next debit goes: a donut chart (tap a slice) and its legend.
struct CategoryBreakdownSection: View {
    var txns: [Txn]
    var caption: String
    @State private var selectedAngle: Double?

    var body: some View {
        let totals = TrueBalanceCore.Category.totals(txns).filter { $0.total > 0 }
        let sum = totals.reduce(0) { $0 + $1.total }
        let selected = selection(in: totals)
        Section {
            Chart(totals) { c in
                SectorMark(
                    angle: .value("Amount", c.total),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(5)
                .foregroundStyle(Format.categoryColor(c.key).gradient)
                .opacity(selected == nil || selected?.key == c.key ? 1 : 0.35)
                .accessibilityLabel(Format.categoryName(c.key))
                .accessibilityValue(c.total.shekels)
            }
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame {
                        let rect = geo[frame]
                        VStack(spacing: 2) {
                            Text(selected.map { Format.categoryName($0.key) } ?? String(localized: "Total"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text((selected?.total ?? sum).shekels)
                                .privacySensitive()
                                .font(.title3.bold())
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .frame(width: rect.width * 0.55)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(height: 220)
            .padding(.vertical, 8)
            .animation(.snappy, value: selected?.key)
            .sensoryFeedback(.selection, trigger: selected?.key)

            ForEach(totals) { c in
                NavigationLink(value: CategoryRoute(key: c.key, txns: txns, caption: caption)) {
                    HStack(spacing: 12) {
                        CategoryIcon(key: c.key)
                        Text(Format.categoryName(c.key))
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(c.total.shekels).monospacedDigit().privacySensitive()
                            Text((c.total / sum).formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        } header: {
            Text("By category")
        } footer: {
            Text(caption)
        }
    }

    /// The slice under the finger, from the cumulative angle value.
    private func selection(in totals: [TrueBalanceCore.Category.Total]) -> TrueBalanceCore.Category.Total? {
        guard let angle = selectedAngle else { return nil }
        var running = 0.0
        for c in totals {
            running += c.total
            if angle <= running { return c }
        }
        return nil
    }
}

struct CategoryDetailView: View {
    var route: CategoryRoute

    var body: some View {
        let txns = route.txns.filter { ($0.category ?? TrueBalanceCore.Category.uncategorized) == route.key }
        List {
            Section {
                ForEach(txns) { t in
                    NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
                }
            } footer: {
                Text(route.caption)
            }
        }
        .navigationTitle(Format.categoryName(route.key))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
