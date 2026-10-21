import SwiftUI
import TrueBalanceCore

struct BankRoute: Hashable { var txn: Txn }

extension AppModel {
    /// Leumi current-account movements, newest first.
    var bankMovements: [Txn] { (snapshot?.bankTxns ?? []).sorted { $0.date > $1.date } }
}

extension BankMovement.Kind {
    var symbol: String {
        switch self {
        case .transferIn: "arrow.down.left"
        case .transferOut: "arrow.up.right"
        case .cardDebit: "creditcard.fill"
        case .income: "plus"
        case .expense: "minus"
        }
    }

    var color: Color {
        switch self {
        case .transferIn, .income: .green
        case .transferOut: .orange
        case .cardDebit: Color(hex: "#002AA9")
        case .expense: .gray
        }
    }

    var label: String {
        switch self {
        case .transferIn: String(localized: "Transfer received")
        case .transferOut: String(localized: "Transfer sent")
        case .cardDebit: String(localized: "Max debit")
        case .income: String(localized: "Money in")
        case .expense: String(localized: "Debit")
        }
    }
}

/// Icon in a tinted rounded square, like the category icons.
struct BankKindIcon: View {
    var kind: BankMovement.Kind
    @ScaledMetric(relativeTo: .body) private var size = 30

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.color.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct BankMovementRow: View {
    var txn: Txn

    var body: some View {
        let kind = BankMovement.kind(txn)
        HStack(spacing: 12) {
            BankKindIcon(kind: kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(BankMovement.party(txn)?.name ?? txn.description)
                    .lineLimit(1)
                Text([Format.dayTime(txn.date), kind.label].joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((txn.chargedAmount > 0 ? "+" : "") + txn.chargedAmount.shekels)
                    .monospacedDigit()
                    .foregroundStyle(txn.chargedAmount > 0 ? .green : .primary)
                    .privacySensitive()
                if txn.status == .pending {
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if let balance = txn.runningBalance {
                    Text("Balance \(balance.shekels)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .privacySensitive()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The latest Leumi movements, on the home screen.
struct LeumiSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let movements = model.bankMovements
        if !movements.isEmpty {
            Section {
                ForEach(movements.prefix(5)) { t in
                    NavigationLink(value: BankRoute(txn: t)) { BankMovementRow(txn: t) }
                }
            } header: {
                SectionHeader("Leumi account", seeAll: movements.count > 5) { BankMovementsView() }
            }
        }
    }
}

/// Every Leumi movement fetched, filterable, grouped by day.
struct BankMovementsView: View {
    @Environment(AppModel.self) private var model

    enum Filter: String, CaseIterable, Identifiable {
        case all, moneyIn, moneyOut, transfers
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .moneyIn: "In"
            case .moneyOut: "Out"
            case .transfers: "Transfers"
            }
        }

        func keeps(_ t: Txn) -> Bool {
            switch self {
            case .all: true
            case .moneyIn: t.chargedAmount > 0
            case .moneyOut: t.chargedAmount < 0
            case .transfers: BankMovement.isTransfer(t)
            }
        }
    }

    @State private var filter = Filter.all
    @State private var query = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let txns = model.bankMovements.filter { t in
            filter.keeps(t) && (q.isEmpty || [t.description, t.memo ?? ""].contains { $0.localizedStandardContains(q) })
        }
        let days = Dictionary(grouping: txns) { Israel.day($0.date) }
        let totals = BankMovement.totals(txns)
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In").font(.caption).foregroundStyle(.secondary)
                        Text("+" + totals.in.shekels).foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Out").font(.caption).foregroundStyle(.secondary)
                        Text((-totals.out).shekels)
                    }
                }
                .font(.headline)
                .monospacedDigit()
                .privacySensitive()
            } footer: {
                if let oldest = model.bankMovements.last?.date {
                    Text("Leumi movements since \(oldest.formatted(.dateTime.day().month(.wide))).")
                }
            }

            if txns.isEmpty {
                ContentUnavailableView("No movements", systemImage: "tray")
                    .listRowBackground(Color.clear)
            }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section {
                    ForEach(days[day]!) { t in
                        NavigationLink(value: BankRoute(txn: t)) { BankMovementRow(txn: t) }
                    }
                } header: {
                    Text(Israel.date(fromDay: day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day)
                }
            }
        }
        .searchable(text: $query, prompt: Text("Search movements"))
        .navigationTitle("Leumi account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .appBackground()
        .animation(.default, value: filter)
    }
}

struct BankMovementDetailView: View {
    var txn: Txn

    var body: some View {
        let kind = BankMovement.kind(txn)
        let party = BankMovement.party(txn)
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(kind.color.gradient, in: .rect(cornerRadius: 22, style: .continuous))
                        .accessibilityHidden(true)
                    Text(party?.name ?? txn.description)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text((txn.chargedAmount > 0 ? "+" : "") + txn.chargedAmount.shekels)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(txn.chargedAmount > 0 ? .green : .primary)
                        .privacySensitive()
                    Text(kind.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            if let party {
                Section {
                    LabeledContent("Name") {
                        Text(party.name).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                    if let code = party.bankCode {
                        LabeledContent("Bank") {
                            Text(party.bankName.map { "\($0) (\(code))" } ?? "\(code)")
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let branch = party.branch {
                        LabeledContent("Branch") { Text(verbatim: branch).monospacedDigit() }
                    }
                    if let account = party.account {
                        LabeledContent("Account") { Text(verbatim: account).monospacedDigit().textSelection(.enabled) }
                    }
                } header: {
                    Text(txn.chargedAmount >= 0 ? "Sender" : "Recipient")
                } footer: {
                    Text("This is everything Leumi gives about the other side, also on its website.")
                }
            }

            Section {
                LabeledContent("Date", value: Format.fullDate(txn.date))
                if let value = txn.valueDate {
                    LabeledContent("Value date", value: value.formatted(.dateTime.day().month(.wide).year()))
                }
                LabeledContent("Description", value: txn.description)
                if let memo = txn.memo {
                    LabeledContent("Details") {
                        Text(memo).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                }
                if let balance = txn.runningBalance {
                    LabeledContent("Balance after", value: balance.shekels)
                        .monospacedDigit()
                        .privacySensitive()
                }
                LabeledContent("Reference") {
                    Text(verbatim: txn.id).monospacedDigit().textSelection(.enabled)
                }
            }
            if txn.status == .pending {
                Section {
                } footer: {
                    Text("Today’s movement: Leumi may still adjust it.")
                }
            }
        }
        .navigationTitle(party?.name ?? txn.description)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .appBackground()
    }
}
