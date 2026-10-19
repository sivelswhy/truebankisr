import Charts
import SwiftUI
import TrueBalanceCore

enum Profile {
    /// "Bonjour, Léa" / "Bonsoir, Léa" / "Good morning, Léa", by the hour.
    static func greeting(name: String, now: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let n = name.trimmingCharacters(in: .whitespaces)
        switch (hour, n.isEmpty) {
        case (5..<12, true): return String(localized: "Good morning")
        case (5..<12, false): return String(localized: "Good morning, \(n)")
        case (12..<18, true): return String(localized: "Good afternoon")
        case (12..<18, false): return String(localized: "Good afternoon, \(n)")
        case (_, true): return String(localized: "Good evening")
        case (_, false): return String(localized: "Good evening, \(n)")
        }
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

/// Name, and card spending over any period.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("firstName") private var firstName = ""
    @State private var showingSettings = false

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
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        ProfileAvatar(name: firstName, size: 84)
                        TextField("Your first name", text: $firstName)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Used to greet you on the home screen.")
                        .frame(maxWidth: .infinity)
                }

                periodSection
                summary
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("Settings"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .navigationDestination(for: CategoryRoute.self) { CategoryDetailView(route: $0) }
            .purchaseDestinations()
        }
    }

    private var periodSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Preset.allCases) { p in
                        Button {
                            withAnimation(.snappy) {
                                preset = p
                                from = p.range().lowerBound
                                to = p.range().upperBound
                            }
                        } label: {
                            Text(p.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(preset == p ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                                .foregroundStyle(preset == p ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            DatePicker("From", selection: Binding(get: { from }, set: { from = $0; preset = nil }),
                       in: ...to, displayedComponents: .date)
            DatePicker("To", selection: Binding(get: { to }, set: { to = $0; preset = nil }),
                       in: from...Date.now, displayedComponents: .date)
        } header: {
            Text("Spending over a period")
        }
    }

    @ViewBuilder
    private var summary: some View {
        let txns = Spending.purchases(model.allPurchases, from: from, to: to).sorted { $0.date > $1.date }
        let total = Spending.total(txns)
        let days = max(1, (Israel.calendar.dateComponents([.day], from: Israel.calendar.startOfDay(for: from),
                                                          to: Israel.calendar.startOfDay(for: to)).day ?? 0) + 1)
        let unit: Calendar.Component = days > 62 ? .month : .day
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Card spending").font(.subheadline).foregroundStyle(.secondary)
                    Text(total.shekels)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: total))
                        .privacySensitive()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(txns.count) purchase(s)").font(.subheadline).foregroundStyle(.secondary)
                    Text("about \((total / Double(days)).formatted(.currency(code: "ILS").precision(.fractionLength(0))))/day")
                        .font(.subheadline)
                        .privacySensitive()
                }
            }

            if !txns.isEmpty {
                Chart(Spending.buckets(txns, from: from, to: to, by: unit)) { b in
                    BarMark(x: .value("Day", b.start, unit: unit), y: .value("Amount", b.total))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(3)
                }
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
                .frame(height: 150)
                .padding(.vertical, 6)
            }
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

    private var periodCaption: String {
        "\(from.formatted(.dateTime.day().month(.abbreviated))) – \(to.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}
