import Charts
import SwiftUI
import TrueBalanceCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false
    @State private var query = ""
    @State private var searching = false
    @AppStorage("hideAmounts") private var hideAmounts = false
    @AppStorage("firstName") private var firstName = ""

    var body: some View {
        NavigationStack {
            content(model.snapshot)
            // No navigation bar: the title and its buttons are the first row and
            // scroll away with the content (no pinned header, no empty bar).
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showingSettings) { ProfileView() }
            .navigationDestination(for: CategoryRoute.self) { route in
                CategoryDetailView(route: route)
                    .redacted(reason: hideAmounts ? .privacy : [])
            }
            .purchaseDestinations()
            .sensoryFeedback(.success, trigger: model.snapshot?.computedAt)
        }
    }

    /// Greeting and profile; scrolls away with the content.
    private var header: some View {
        HStack(alignment: .center) {
            Text(Profile.greeting(name: firstName))
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                ProfileAvatar(name: firstName, size: 40)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Profile"))
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
    }

    @ViewBuilder
    private func content(_ snapshot: Snapshot?) -> some View {
        List {
            header

            if let s = snapshot {
                loaded(s)
            } else {
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
        .listStyle(.insetGrouped)
        .contentMargins(.top, 8, for: .scrollContent)
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if snapshot != nil {
                FloatingSearch(query: $query, isOpen: $searching)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .redacted(reason: hideAmounts ? .privacy : [])
        .animation(.default, value: snapshot)
        .animation(.default, value: model.isRefreshing)
    }

    @ViewBuilder
    private func loaded(_ s: Snapshot) -> some View {
            if model.isRefreshing {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(Format.progress(model.progressStep))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    .animation(.default, value: model.progressStep)
                }
            }

            if !model.refreshErrors.isEmpty {
                Section {
                    ForEach(Provider.allCases.filter { model.refreshErrors[$0] != nil }, id: \.self) { p in
                        BankErrorText(error: model.refreshErrors[p]!, provider: p)
                            .font(.subheadline)
                    }
                }
            }

            if !query.isEmpty {
                searchResults(s)
            } else {
                Section {
                    HeroView(snapshot: s, isDemo: model.isDemo)
                    if let f = Forecaster.forecast(s), !(f.income.isEmpty && f.debits.isEmpty) {
                        ForecastRow(forecast: f)
                    }
                }

                Section {
                    LabeledContent {
                        Text(s.bankBalance.shekels).privacySensitive()
                    } label: {
                        Text("Leumi balance")
                    }
                    LabeledContent {
                        Text((-(s.nextCharge?.total ?? 0)).shekels).privacySensitive()
                    } label: {
                        if let next = s.nextCharge {
                            Text("Max · \(Format.day(next.chargeDate))")
                        } else {
                            Text("Max")
                        }
                    }
                    LabeledContent {
                        Text(s.trueBalance.shekels)
                            .foregroundStyle(s.trueBalance < 0 ? .red : .primary)
                            .privacySensitive()
                    } label: {
                        Text("Available")
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

                CardsSection(snapshot: s)

                if s.upcoming.count > 1 {
                    UpcomingDebitsChart(upcoming: s.upcoming)
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

                if let next = s.nextCharge {
                    CategoryBreakdownSection(txns: next.txns, caption: String(localized: "Debited \(Format.day(next.chargeDate))"))
                }

                InsightsSection(snapshot: s)

                Section {
                } footer: {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("Updated \(s.computedAt.formatted(.relative(presentation: .named)))")
                    }
                    .frame(maxWidth: .infinity)
                }
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

/// Magnifying glass floating bottom-right in Liquid Glass; tapping it morphs
/// into a search field.
private struct FloatingSearch: View {
    @Binding var query: String
    @Binding var isOpen: Bool
    @FocusState private var focused: Bool
    @Namespace private var glass

    var body: some View {
        container {
            HStack(spacing: 10) {
                if isOpen {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search charges", text: $query)
                            .focused($focused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Clear"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .glass(id: "field", in: glass, shape: .capsule)

                    Button {
                        withAnimation(.bouncy) {
                            isOpen = false
                            query = ""
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .glass(id: "button", in: glass, shape: .circle)
                    .accessibilityLabel(Text("Cancel"))
                } else {
                    Button {
                        withAnimation(.bouncy) { isOpen = true }
                        focused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .glass(id: "button", in: glass, shape: .circle)
                    .accessibilityLabel(Text("Search charges"))
                }
            }
        }
        .onChange(of: isOpen) { _, open in focused = open }
    }

    @ViewBuilder
    private func container(@ViewBuilder _ content: () -> some View) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10) { content() }
        } else {
            content()
        }
    }
}

private extension View {
    /// Liquid Glass on iOS 26+, frosted material before.
    @ViewBuilder
    func glass(id: String, in namespace: Namespace.ID, shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.contentShape(shape)
                .glassEffect(.regular.interactive(), in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            self.contentShape(shape)
                .background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
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
