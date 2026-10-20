import SwiftUI
import TrueBalanceCore
import UniformTypeIdentifiers

// MARK: - Home

/// Hello Bank, Revolut…: apart from the true balance, one bank at a time.
struct EuroBanksSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage("euroSelectedBank") private var selectedID = ""

    var body: some View {
        let banks = model.euroConnections.map(\.bank)
        if let current = banks.first(where: { $0.id == selectedID }) ?? banks.first {
            let data = model.euroData.first { $0.id == current.id }
            Section {
                EuroBankPicker(banks: banks, selection: current) { selectedID = $0.id }
                    .cardRow()
                if let data {
                    HeroCard(tint: Color(hex: current.color)) {
                        EuroBalanceCard(data: data, rates: model.snapshot?.fxRates ?? [:])
                    }
                    .cardRow()
                }
            } header: {
                SectionHeader("Other banks", seeAll: (data?.txns.count ?? 0) > 5) { EuroTransactionsView(bankID: current.id) }
            }
            .animation(.snappy, value: current)
            Section {
                if let data {
                    ForEach(data.txns.prefix(5)) { EuroTxnRow(txn: $0) }
                } else if model.euroErrors[current.id] == nil {
                    Text("Pull down to read \(current.name).").foregroundStyle(.secondary)
                }
                if let error = model.euroErrors[current.id] {
                    EuroErrorText(error: error)
                }
            }
        }
    }
}

/// Capsules with the banks' logos; the selected one fills with its color.
struct EuroBankPicker: View {
    var banks: [EuroBank]
    var selection: EuroBank
    var select: (EuroBank) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(banks) { bank in
                    let selected = bank == selection
                    Button {
                        withAnimation(.snappy) { select(bank) }
                    } label: {
                        HStack(spacing: 8) {
                            EuroBankLogo(bank: bank, size: 24)
                            Text(bank.name)
                        }
                    }
                    .buttonStyle(ChipStyle(selected: selected, tint: Color(hex: bank.color), leading: 5))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The bank's logo from Enable Banking, its initial while loading or offline.
struct EuroBankLogo: View {
    var bank: EuroBank
    var size: CGFloat

    var body: some View {
        AsyncImage(url: bank.logoURL) { image in
            image.resizable().scaledToFit().padding(size * 0.12).background(.white)
        } placeholder: {
            Text(bank.name.prefix(1))
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: bank.color).gradient)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Balance of each account, in its currency and roughly in shekels.
struct EuroBalanceCard: View {
    var data: EuroBankData
    var rates: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(data.accounts) { account in
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let balance = account.balance {
                        Text(balance.formatted(.currency(code: account.ref.currency)))
                            .font(.system(data.accounts.count == 1 ? .largeTitle : .title2, design: .rounded).weight(.bold))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: balance))
                            .privacySensitive()
                        if account.ref.currency != "ILS", let rate = rates[account.ref.currency] {
                            Text("≈ \((balance * rate).shekels)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .privacySensitive()
                        }
                    } else {
                        Text("Balance not available").foregroundStyle(.secondary)
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text("Updated \(data.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct EuroTxnRow: View {
    var txn: EuroTxn
    @ScaledMetric(relativeTo: .body) private var size = 30

    var body: some View {
        let incoming = txn.amount > 0
        HStack(spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background((incoming ? Color.green : Color.indigo).gradient,
                            in: .rect(cornerRadius: size * 0.26, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.title).lineLimit(1)
                Text(txn.party != nil && txn.details != nil
                     ? "\(Format.day(txn.date)) · \(txn.details!)"
                     : Format.day(txn.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((incoming ? "+" : "") + txn.amount.formatted(.currency(code: txn.currency)))
                    .monospacedDigit()
                    .foregroundStyle(incoming ? .green : .primary)
                    .privacySensitive()
                if txn.pending {
                    Text("Pending")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EuroErrorText: View {
    var error: EnableBankingError

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(error.message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(error == .rateLimited ? .orange : .red)
            if let detail = error.detail {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .font(.subheadline)
    }
}

/// Every transaction read from one bank, searchable, grouped by day.
struct EuroTransactionsView: View {
    @Environment(AppModel.self) private var model
    var bankID: String
    @State private var query = ""

    var body: some View {
        let data = model.euroData.first { $0.id == bankID }
        let q = query.trimmingCharacters(in: .whitespaces)
        let txns = (data?.txns ?? []).filter { t in
            q.isEmpty || [t.party ?? "", t.details ?? ""].contains { $0.localizedStandardContains(q) }
        }
        let days = Dictionary(grouping: txns, by: \.date)
        List {
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section {
                    ForEach(days[day]!) { EuroTxnRow(txn: $0) }
                } header: {
                    Text(Israel.date(fromDay: day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day)
                }
            }
        }
        .overlay {
            if txns.isEmpty { ContentUnavailableView.search(text: q) }
        }
        .searchable(text: $query)
        .navigationTitle(data?.bank.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

// MARK: - Settings

/// The Enable Banking key and the bank connections.
struct EuroBanksSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var pendingPEM: String?
    @State private var appID = ""
    @State private var startingBank: String?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                if let key = model.euroKey {
                    LabeledContent("Application ID") {
                        Text(key.appID).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                    Button("Replace the key") { importing = true }
                } else {
                    Button("Import the key (.pem)", systemImage: "key") { importing = true }
                }
            } header: {
                Text("Enable Banking key")
            } footer: {
                Text("The .pem file downloaded from the Enable Banking portal. It’s kept in this iPhone’s Keychain.")
            }

            Section {
                ForEach(EuroBank.supported) { bank in
                    bankRow(bank)
                }
            } header: {
                Text("Banks")
            } footer: {
                Text("You confirm on the bank’s site or app, then come back here. Access is read only and lasts 180 days.")
            }
        }
        .navigationTitle("Other banks")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "pem") ?? .data, .data]) { result in
            readKey(result)
        }
        .alert("Application ID", isPresented: Binding(get: { pendingPEM != nil }, set: { if !$0 { pendingPEM = nil } })) {
            TextField("Application ID", text: $appID)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveKey() }
        } message: {
            Text("Shown in the Enable Banking portal. The key file is usually named after it.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func bankRow(_ bank: EuroBank) -> some View {
        let connection = model.euroConnections.first { $0.id == bank.id }
        let busy = startingBank == bank.id || model.connectingEuroBank == bank.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                EuroBankLogo(bank: bank, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.name)
                    Group {
                        if let connection {
                            Text(connection.isExpired
                                 ? String(localized: "Access expired")
                                 : String(localized: "Connected until \(connection.validUntil.formatted(.dateTime.day().month(.wide)))"))
                        } else {
                            Text("Not connected")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(connection?.isExpired == true ? .orange : .secondary)
                }
                Spacer()
                if busy {
                    ProgressView()
                } else {
                    Button(connection == nil ? LocalizedStringKey("Connect") : "Reconnect") { connect(bank) }
                        .buttonStyle(.bordered)
                        .disabled(model.euroKey == nil)
                }
            }
            if let error = model.euroErrors[bank.id] {
                EuroErrorText(error: error)
            }
        }
        .swipeActions {
            if connection != nil {
                Button("Disconnect", role: .destructive) {
                    Task { await model.disconnectEuroBank(bank) }
                }
            }
        }
    }

    private func connect(_ bank: EuroBank) {
        startingBank = bank.id
        Task {
            defer { startingBank = nil }
            do {
                openURL(try await model.startEuroConnection(bank))
            } catch {
                let e = EnableBankingError.from(error)
                problem = [e.message, e.detail].compactMap { $0 }.joined(separator: "\n\n")
            }
        }
    }

    private func readKey(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let pem = try? String(contentsOf: url, encoding: .utf8), pem.contains("PRIVATE KEY") else {
            problem = EnableBankingError.badKey("not a private key").message
            return
        }
        appID = url.deletingPathExtension().lastPathComponent
        pendingPEM = pem
    }

    private func saveKey() {
        guard let pem = pendingPEM else { return }
        pendingPEM = nil
        do {
            try model.importEuroKey(pem: pem, appID: appID)
        } catch {
            let e = EnableBankingError.from(error)
            problem = [e.message, e.detail].compactMap { $0 }.joined(separator: "\n\n")
        }
    }
}
