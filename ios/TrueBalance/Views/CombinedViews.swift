import SwiftUI
import TrueBalanceCore

// MARK: - Source

/// Which app a movement comes from: Leumi's, or one of the European banks'.
enum TxnSource: Hashable {
    case leumi
    case euro(EuroBank)

    /// "leumi", or the European bank's id.
    var bankID: String {
        switch self {
        case .leumi: "leumi"
        case .euro(let bank): bank.id
        }
    }

    var name: String {
        switch self {
        case .leumi: String(localized: "Leumi")
        case .euro(let bank): bank.name
        }
    }
}

/// A small round mark on a row's icon: Leumi's column building, or the bank's logo.
struct SourceBadge: View {
    var source: TxnSource
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch source {
            case .leumi:
                Image("LeumiLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            case .euro(let bank):
                EuroBankLogo(bank: bank, size: size)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Totals

extension AppModel {
    /// What the European accounts hold, in shekels at the Bank of Israel rate,
    /// and how many accounts could not be counted (no balance, or no rate).
    var euroTotal: (shekels: Double, skipped: Int) {
        let rates = snapshot?.fxRates ?? [:]
        var total = 0.0
        var skipped = 0
        for account in euroData.flatMap(\.accounts) {
            guard let balance = account.balance else { skipped += 1; continue }
            if account.ref.currency == "ILS" {
                total += balance
            } else if let rate = rates[account.ref.currency], rate > 0 {
                total += balance * rate
            } else {
                skipped += 1
            }
        }
        return (total, skipped)
    }

    /// Leumi's really available money plus the European accounts.
    var combinedTotal: Double? {
        snapshot.map { $0.trueBalance + euroTotal.shekels }
    }
}

// MARK: - Page

/// Leumi + the European banks: one total, and every movement in one list.
struct CombinedView: View {
    @Environment(AppModel.self) private var model

    enum Filter: String, CaseIterable, Identifiable {
        case all, leumi, other
        var id: String { rawValue }
    }

    private struct Item: Identifiable {
        var id: String
        /// YYYY-MM-DD.
        var day: String
        var sort: Date
        var kind: Kind
        enum Kind {
            case leumi(Txn)
            case euro(EuroTxn, EuroBank)
        }
    }

    @State private var filter = Filter.all
    @State private var query = ""

    var body: some View {
        List {
            if let s = model.snapshot {
                totals(s)
            }
            Section {
                Picker("Source", selection: $filter) {
                    Text("All").tag(Filter.all)
                    Text("Leumi").tag(Filter.leumi)
                    Text("Other banks").tag(Filter.other)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            movements
        }
        .searchable(text: $query)
        .navigationTitle("Combined")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .appBackground()
    }

    // MARK: Totals

    @ViewBuilder
    private func totals(_ s: Snapshot) -> some View {
        let euro = model.euroTotal
        Section {
            LabeledContent {
                Money(s.trueBalance)
            } label: {
                HStack(spacing: 8) {
                    SourceBadge(source: .leumi, size: 20)
                    Text("Leumi, really available")
                }
            }
            ForEach(model.euroData) { data in
                ForEach(data.accounts) { account in
                    LabeledContent {
                        accountAmount(account, rates: s.fxRates ?? [:])
                    } label: {
                        HStack(spacing: 8) {
                            SourceBadge(source: .euro(data.bank), size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(data.bank.name)
                                if data.accounts.count > 1 {
                                    Text(account.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            LabeledContent {
                Money(s.trueBalance + euro.shekels)
                    .foregroundStyle(s.trueBalance + euro.shekels < 0 ? .red : .primary)
            } label: {
                Label("Total", systemImage: "equal.circle")
            }
            .fontWeight(.semibold)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Other banks are converted at the Bank of Israel rate, so their share is approximate.")
                if euro.skipped > 0 {
                    Text("Accounts left out, no balance or rate: \(euro.skipped)")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func accountAmount(_ account: EuroAccount, rates: [String: Double]) -> some View {
        if let balance = account.balance {
            VStack(alignment: .trailing, spacing: 0) {
                if account.ref.currency == "ILS" {
                    Money(balance)
                } else {
                    // Exact amount in the account's currency, then one estimate in shekels.
                    Text(balance.formatted(.currency(code: account.ref.currency)))
                        .monospacedDigit()
                        .privacySensitive()
                    if let rate = rates[account.ref.currency], rate > 0 {
                        Text("≈ \((balance * rate).ils)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .privacySensitive()
                    }
                }
            }
        } else {
            Text("Balance not available").foregroundStyle(.secondary)
        }
    }

    // MARK: Movements

    private var items: [Item] {
        var out: [Item] = []
        if filter != .other {
            for t in model.bankMovements {
                out.append(Item(id: "leumi-\(t.id)", day: Israel.day(t.date), sort: t.date, kind: .leumi(t)))
            }
        }
        if filter != .leumi {
            for data in model.euroData {
                for t in data.txns {
                    let date = Israel.date(fromDay: t.date) ?? .distantPast
                    out.append(Item(id: "\(data.id)-\(t.id)", day: t.date, sort: date, kind: .euro(t, data.bank)))
                }
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            out = out.filter { item in
                switch item.kind {
                case .leumi(let t): [t.description, t.memo ?? ""].contains { $0.localizedStandardContains(q) }
                case .euro(let t, _): [t.party ?? "", t.details ?? ""].contains { $0.localizedStandardContains(q) }
                }
            }
        }
        return out.sorted { $0.sort > $1.sort }
    }

    @ViewBuilder
    private var movements: some View {
        let shown = Array(items.prefix(300))
        let days = Dictionary(grouping: shown, by: \.day)
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
            Section {
                ForEach(days[day]!) { item in
                    switch item.kind {
                    case .leumi(let t):
                        NavigationLink(value: BankRoute(txn: t)) { BankMovementRow(txn: t, source: .leumi) }
                    case .euro(let t, let bank):
                        EuroTxnRow(txn: t, source: .euro(bank))
                    }
                }
            } header: {
                Text(Israel.date(fromDay: day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day)
            }
        }
    }
}
