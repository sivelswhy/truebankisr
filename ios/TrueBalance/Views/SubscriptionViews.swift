import SwiftUI
import TrueBalanceCore

/// A subscription in a list: opens the merchant's history, except hand-typed ones.
struct SubscriptionRow: View {
    var sub: Subscription

    var body: some View {
        if sub.source == .manual {
            RecurringRow(item: sub.recurring)
        } else {
            NavigationLink(value: MerchantRoute(key: sub.key, name: sub.recurring.name)) {
                RecurringRow(item: sub.recurring)
            }
        }
    }
}

/// Everything charged every month: detected, flagged from a purchase, or typed in.
struct SubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        let subs = model.subscriptions
        let due = model.subscriptionsDueBeforeNextDebit
        List {
            if !subs.isEmpty {
                Section {
                    let monthly = Subscriptions.monthlyTotal(subs.map(\.recurring))
                    LabeledContent {
                        Money(monthly)
                            .font(.title2.bold())
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Per month")
                            Text("\((monthly * 12).wholeShekels) a year")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .privacySensitive()
                        }
                    }
                }
            }
            if !due.isEmpty, let next = model.snapshot?.nextCharge {
                Section {
                    ForEach(due) { RecurringRow(item: $0.recurring) }
                } header: {
                    HStack {
                        Text("Due before \(Format.day(next.chargeDate))")
                        Spacer()
                        Text(Subscriptions.total(due).shekels).monospacedDigit().privacySensitive()
                    }
                }
            }
            Section {
                ForEach(subs) { sub in
                    SubscriptionRow(sub: sub)
                        .swipeActions {
                            Button("Remove", role: .destructive) { model.removeSubscription(sub) }
                        }
                }
            } footer: {
                Text("Max charges from the same merchant, for the same amount, every month. Installment plans aren’t included. Mark any purchase as a subscription from its details, or add one by hand.")
            }
        }
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
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

/// Name, monthly amount and day of the month, for a subscription the history doesn't show.
struct AddSubscriptionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amountText = ""
    @State private var day = Calendar.current.component(.day, from: .now)

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
            }
            .navigationTitle("Add a subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let amount {
                            model.addSubscription(name: name.trimmingCharacters(in: .whitespaces), amount: amount, dayOfMonth: day)
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
