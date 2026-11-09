import SwiftUI
import TrueBalanceCore

struct SubscriptionRoute: Hashable { var key: String }

/// Shekel card charges of one merchant that count as subscription payments, newest first.
func subscriptionCharges(_ txns: [Txn]) -> [Txn] {
    txns.filter { $0.chargedCurrency == "ILS" && $0.chargedAmount < 0 && $0.installments == nil }
        .sorted { $0.date > $1.date }
}

/// A subscription in a list: logo, next charge, amount, and a mark when the
/// price moved since the previous charge. Opens its page.
struct SubscriptionRow: View {
    var sub: Subscription
    var txn: Txn?
    /// Latest charge minus the one before, positive when it went up.
    var priceChange: Double?
    /// Marked on the icon when there is more than one bank to tell apart.
    var bank: TxnSource?

    init(sub: Subscription, txn: Txn? = nil, priceChange: Double? = nil, bank: TxnSource? = nil) {
        self.sub = sub
        self.txn = txn
        self.priceChange = priceChange
        self.bank = bank
    }

    var body: some View {
        NavigationLink(value: SubscriptionRoute(key: sub.key)) {
            HStack(spacing: 12) {
                Group {
                    if let txn {
                        MerchantLogo(txn: txn, size: 36, showLogo: bank == nil)
                    } else {
                        CategoryIcon(key: sub.recurring.category)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let bank { SourceBadge(source: bank, size: 16).offset(x: 5, y: 5) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.recurring.name).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(sub.recurring.nextDate, format: .relative(presentation: .named))
                        Text(verbatim: "·")
                        Text(Format.day(sub.recurring.nextDate))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Money(abs(sub.recurring.amount))
                    if let priceChange, abs(priceChange) >= 0.5 {
                        Label(abs(priceChange).shekels, systemImage: priceChange > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(priceChange > 0 ? .red : .green)
                            .privacySensitive()
                    }
                }
            }
        }
    }
}

/// The subscriptions tab: what they cost, when each is next charged, which
/// ones are due before the card debit, and a page per subscription.
struct SubscriptionsView: View {
    enum Order: String { case date, amount }

    @Environment(AppModel.self) private var model
    @AppStorage("subscriptionOrder") private var order = Order.date
    @State private var adding = false

    /// Which bank a subscription is charged on, once there are several to choose from.
    private func bankMark(_ sub: Subscription) -> TxnSource? {
        model.hasSeveralBanks ? model.subscriptionBank(sub.key) : nil
    }

    /// Monthly cost per bank, when more than one bank carries subscriptions.
    @ViewBuilder
    private func perBank(_ subs: [Subscription]) -> some View {
        let groups = Dictionary(grouping: subs) { model.subscriptionBank($0.key) }
        if model.hasSeveralBanks, groups.count > 1 {
            HStack(spacing: 14) {
                ForEach(model.subscriptionBanks.filter { groups[$0] != nil }, id: \.bankID) { bank in
                    HStack(spacing: 5) {
                        SourceBadge(source: bank, size: 18)
                        Text(Subscriptions.monthlyTotal(groups[bank]!.map(\.recurring)).wholeShekels)
                            .monospacedDigit()
                            .privacySensitive()
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        let subs = model.subscriptions
        let due = model.subscriptionsDueBeforeNextDebit
        let byKey = Dictionary(grouping: model.allPurchases, by: \.merchantKey)
        let shown = order == .date ? subs.sorted { $0.recurring.nextDate < $1.recurring.nextDate } : subs
        List {
            if subs.isEmpty {
                ContentUnavailableView {
                    Label("No subscriptions yet", systemImage: "repeat")
                } description: {
                    Text("Max charges from the same merchant, for the same amount, every month. Installment plans aren’t included. Mark any purchase as a subscription from its details, or add one by hand.")
                } actions: {
                    Button("Add a subscription") { adding = true }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    let monthly = Subscriptions.monthlyTotal(subs.map(\.recurring))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per month").font(.subheadline).foregroundStyle(.secondary)
                        Money(monthly, alignment: .leading)
                            .font(.largeTitle.bold())
                        HStack {
                            Text("\((monthly * 12).wholeShekels) a year").privacySensitive()
                            Spacer()
                            Text("\(subs.count) subscription(s)")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        perBank(subs)
                    }
                    .padding(.vertical, 4)
                }
                if !due.isEmpty, let next = model.snapshot?.nextCharge {
                    Section {
                        ForEach(due) { SubscriptionRow(sub: $0, txn: subscriptionCharges(byKey[$0.key] ?? []).first, bank: bankMark($0)) }
                    } header: {
                        HStack {
                            Text("Due before \(Format.day(next.chargeDate))")
                            Spacer()
                            Text(Subscriptions.total(due).shekels).monospacedDigit().privacySensitive()
                        }
                    }
                }
                Section {
                    ForEach(shown) { sub in
                        let charges = subscriptionCharges(byKey[sub.key] ?? [])
                        SubscriptionRow(sub: sub, txn: charges.first,
                                        priceChange: charges.count > 1
                                            ? abs(charges[0].chargedAmount) - abs(charges[1].chargedAmount) : nil,
                                        bank: bankMark(sub))
                            .swipeActions {
                                Button("Remove", role: .destructive) { model.removeSubscription(sub) }
                            }
                    }
                } header: {
                    Picker("Sort", selection: $order) {
                        Text("By date").tag(Order.date)
                        Text("By amount").tag(Order.amount)
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 4)
                } footer: {
                    Text("Max charges from the same merchant, for the same amount, every month. Installment plans aren’t included. Mark any purchase as a subscription from its details, or add one by hand.")
                }
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add a subscription", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { AddSubscriptionView() }
        .appBackground()
    }
}

/// One subscription: what it costs, since when, how the price moved, its latest charges.
struct SubscriptionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var route: SubscriptionRoute

    var body: some View {
        Group {
            if let sub = model.subscriptions.first(where: { $0.key == route.key }) {
                content(sub)
            } else {
                Color.clear
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .appBackground()
    }

    private func content(_ sub: Subscription) -> some View {
        let charges = subscriptionCharges(Spending.atMerchant(sub.key, in: model.allPurchases))
        let monthly = abs(sub.recurring.amount)
        return List {
            Section {
                VStack(spacing: 10) {
                    if let latest = charges.first {
                        MerchantLogo(txn: latest, size: 80)
                    } else {
                        CategoryIcon(key: sub.recurring.category)
                    }
                    Text(sub.recurring.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Money(monthly, alignment: .center)
                        .font(.largeTitle.bold())
                    Text("Per month").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Next charge", value: Format.day(sub.recurring.nextDate))
                LabeledContent("Per year") { Money(monthly * 12, whole: true) }
                if let first = charges.last {
                    LabeledContent("Since", value: Format.day(first.date))
                    LabeledContent("Total paid") { Money(Spending.total(charges)) }
                }
                if charges.count > 1, let first = charges.last, let latest = charges.first {
                    let diff = abs(latest.chargedAmount) - abs(first.chargedAmount)
                    LabeledContent("Price change") {
                        if abs(diff) < 0.5 {
                            Text("Unchanged").foregroundStyle(.secondary)
                        } else {
                            Label(abs(diff).shekels, systemImage: diff > 0 ? "arrow.up" : "arrow.down")
                                .foregroundStyle(diff > 0 ? .red : .green)
                                .privacySensitive()
                        }
                    }
                }
                if model.hasSeveralBanks {
                    Picker("Charged on", selection: Binding(
                        get: { model.subscriptionBank(sub.key).bankID },
                        set: { model.setSubscriptionBank($0, key: sub.key) })) {
                        ForEach(model.subscriptionBanks, id: \.bankID) { Text($0.name).tag($0.bankID) }
                    }
                }
                LabeledContent("Tracking") {
                    switch sub.source {
                    case .detected: Text("Detected automatically")
                    case .marked: Text("Marked by you")
                    case .manual: Text("Added by hand")
                    }
                }
            }

            if !charges.isEmpty {
                Section {
                    ForEach(charges.prefix(6)) { t in
                        NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
                    }
                    NavigationLink(value: MerchantRoute(key: sub.key, name: sub.recurring.name)) {
                        Label("All purchases at \(sub.recurring.name)", systemImage: "list.bullet.rectangle")
                    }
                } header: {
                    Text("Last charges")
                }
            }

            Section {
                Button("Stop tracking", role: .destructive) {
                    model.removeSubscription(sub)
                    dismiss()
                }
            }
        }
        .navigationTitle(sub.recurring.name)
    }
}

/// Name, monthly amount and day of the month, for a subscription the history doesn't show.
struct AddSubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var day = Calendar.current.component(.day, from: .now)
    @State private var bankID = TxnSource.leumi.bankID

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Amount per month", text: $amountText)
                    .keyboardType(.decimalPad)
                Stepper("Day of the month: \(day)", value: $day, in: 1...31)
                if model.hasSeveralBanks {
                    Picker("Charged on", selection: $bankID) {
                        ForEach(model.subscriptionBanks, id: \.bankID) { Text($0.name).tag($0.bankID) }
                    }
                }
            }
            .navigationTitle("Add a subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount {
                            model.addSubscription(name: name.trimmingCharacters(in: .whitespaces), amount: amount, dayOfMonth: day, bankID: bankID)
                            dismiss()
                        }
                    }
                    .disabled(amount == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// On a purchase: flag this merchant as a subscription, or clear a wrong detection.
struct SubscriptionToggleSection: View {
    @Environment(AppModel.self) private var model
    var txn: Txn

    var body: some View {
        // Monthly shekel card charges only: that is what the list can follow.
        if txn.chargedCurrency == "ILS", txn.chargedAmount < 0, txn.installments == nil {
            Section {
                Toggle("Subscription", isOn: Binding(
                    get: { model.isSubscription(merchantKey: txn.merchantKey) },
                    set: { model.setSubscription($0, merchantKey: txn.merchantKey) }))
            }
        }
    }
}

/// Under the next debit: subscriptions that should be charged before it, so
/// will be part of it. Not counted in the available balance.
struct SubscriptionsDueSection: View {
    @Environment(AppModel.self) private var model
    var chargeDate: String

    var body: some View {
        let due = model.subscriptionsDueBeforeNextDebit
        if !due.isEmpty, let s = model.snapshot {
            let total = Subscriptions.total(due)
            Section {
                ForEach(due) { RecurringRow(item: $0.recurring) }
                NavigationLink {
                    SubscriptionsView()
                } label: {
                    LabeledContent("Total") { Text(total.shekels).monospacedDigit().privacySensitive() }
                }
            } header: {
                Text("Subscriptions due before \(Format.day(chargeDate))")
            } footer: {
                Text("Not counted in the available balance; \((s.trueBalance - total).shekels) left after them.")
            }
        }
    }
}
