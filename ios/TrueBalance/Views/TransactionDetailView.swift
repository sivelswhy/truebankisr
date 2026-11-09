import Charts
import MapKit
import SwiftUI
import TrueBalanceCore

struct TxnRoute: Hashable { var txn: Txn }
struct MerchantRoute: Hashable { var key: String; var name: String }

extension View {
    /// Purchase and bank movement details and merchant history, reachable from any list.
    func purchaseDestinations() -> some View {
        navigationDestination(for: TxnRoute.self) { TransactionDetailView(txn: $0.txn) }
            .navigationDestination(for: MerchantRoute.self) { MerchantHistoryView(route: $0) }
            .navigationDestination(for: SubscriptionRoute.self) { SubscriptionDetailView(route: $0) }
            .navigationDestination(for: BankRoute.self) { BankMovementDetailView(txn: $0.txn) }
    }
}

extension AppModel {
    /// Every card purchase known: full history, or the upcoming ones for older snapshots.
    var allPurchases: [Txn] {
        guard let s = snapshot else { return [] }
        return s.history ?? s.upcoming.flatMap(\.txns)
    }
}

/// A purchase's icon, the same in a list and on its page: the category glyph in
/// its colour, with the merchant's logo as a small badge when the card company
/// sends one. `size` nil follows Dynamic Type like the list rows.
struct MerchantLogo: View {
    var txn: Txn
    var size: CGFloat?
    /// Off where another badge takes the corner (the bank of a subscription).
    var showLogo = true
    @ScaledMetric(relativeTo: .body) private var scaled = 30

    var body: some View {
        let s = size ?? scaled
        Image(systemName: Format.categorySymbol(txn.category))
            .font(.system(size: s * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: s, height: s)
            .background(Format.categoryColor(txn.category).gradient, in: .rect(cornerRadius: s * 0.26, style: .continuous))
            .shadow(color: s > 60 ? Format.categoryColor(txn.category).opacity(0.35) : .clear, radius: s * 0.12, y: s * 0.05)
            .overlay(alignment: .bottomTrailing) {
                if showLogo, let url = txn.logoURL.flatMap(URL.init(string:)) {
                    let badge = max(s * 0.42, 14)
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit().padding(badge * 0.1).background(.white)
                            .frame(width: badge, height: badge)
                            .clipShape(.circle)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
                            .offset(x: badge * 0.25, y: badge * 0.25)
                    } placeholder: {
                        EmptyView()
                    }
                }
            }
            .accessibilityHidden(true)
    }

    /// "Aroma Espresso Bar" → "AE", "שופרסל דיל" → "שד".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// "Card" on the left; card icon, two dots and the last 4 digits together on the right.
struct CardRow: View {
    var last4: String?

    var body: some View {
        LabeledContent("Card") {
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                Text(verbatim: "••")
                Text(verbatim: last4 ?? "––––")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(last4.map { Text("Card ending in \($0)") } ?? Text("Card"))
    }
}

/// Where the purchase was made: the card company's address when it sends one,
/// otherwise the best Apple Maps match for the merchant's name in Israel.
@MainActor
@Observable
final class PurchaseLocation {
    enum Source { case provided, guessed, openStreetMap }

    private(set) var item: MKMapItem?
    private(set) var foundAddress: String?
    private(set) var source: Source = .guessed
    private(set) var searched = false

    func find(for txn: Txn) async {
        guard !searched else { return }
        defer { searched = true }
        guard !Self.looksOnline(txn) else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [txn.description, txn.merchantAddress].compactMap { $0 }.joined(separator: " ")
        request.resultTypes = .pointOfInterest
        // Israel; results outside it are dropped below.
        request.region = MKCoordinateRegion(center: .init(latitude: 31.6, longitude: 34.9),
                                            span: .init(latitudeDelta: 4, longitudeDelta: 3))
        if let found = try? await MKLocalSearch(request: request).start().mapItems.first,
           Self.isInIsrael(Self.coordinate(of: found)) {
            item = found
            source = txn.merchantAddress == nil ? .guessed : .provided
            return
        }

        // Apple Maps found nothing: OpenStreetMap, free and often better covered in Israel.
        if let place = await OSMPlaceFinder.find(key: txn.merchantKey, name: txn.description, address: txn.merchantAddress) {
            item = OSMPlaceFinder.mapItem(for: place)
            foundAddress = place.address
            source = .openStreetMap
        }
    }

    /// Online shops and payment platforms have no meaningful place.
    static func looksOnline(_ txn: Txn) -> Bool {
        let n = txn.description.lowercased()
        return [".com", ".co.il", "www", "paypal", "amazon", "aliexpress", "apple.com", "google", "netflix", "spotify", "*"]
            .contains(where: n.contains) || txn.category == "fx"
    }

    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26, *) { item.location.coordinate } else { item.placemark.coordinate }
    }

    static func isInIsrael(_ c: CLLocationCoordinate2D) -> Bool {
        (29.4...33.4).contains(c.latitude) && (34.2...35.95).contains(c.longitude)
    }
}

struct TransactionDetailView: View {
    @Environment(AppModel.self) private var model
    var txn: Txn
    @State private var location = PurchaseLocation()

    var body: some View {
        let others = Spending.atMerchant(txn.merchantKey, in: model.allPurchases)
        List {
            Section {
                VStack(spacing: 10) {
                    MerchantLogo(txn: txn, size: 96)
                    Text(txn.description)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    let display = DisplayCurrency.shared
                    let original = txn.original
                    Text(txn.chargedCurrency != "ILS"
                        ? (-txn.chargedAmount).formatted(.currency(code: txn.chargedCurrency))
                        : (txn.isConvertedEstimate && !display.otherFirst ? "≈ " : "") + display.primary(-txn.chargedAmount, original: original))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .privacySensitive()
                    // The grey line, unless it's the exact amount paid, just below.
                    if txn.chargedCurrency == "ILS", let other = display.secondary(-txn.chargedAmount, original: original),
                       !(original?.currency == display.code && !display.otherFirst) {
                        Text(other)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .privacySensitive()
                    }
                    if let original {
                        let paid = DisplayCurrency.format(original.amount, original.currency)
                        Label(txn.isConvertedEstimate ? "\(paid) at the Bank of Israel rate" : "Paid \(paid) in the shop’s currency",
                              systemImage: "globe")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .privacySensitive()
                    }
                    HStack(spacing: 6) {
                        Text(Format.fullDate(txn.date))
                        if txn.status == .pending {
                            Text("Pending")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.18), in: .capsule)
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                CardRow(last4: txn.cardLast4)
                LabeledContent("Category") {
                    HStack(spacing: 8) {
                        Text(Format.categoryName(txn.category))
                        CategoryIcon(key: txn.category)
                    }
                }
                if let i = txn.installments {
                    LabeledContent("Installment", value: String(localized: "\(i.number) of \(i.total)"))
                }
                LabeledContent("Debited", value: txn.status == .pending
                    ? String(localized: "Next debit")
                    : txn.processedDate.formatted(.dateTime.day().month(.wide).year()))
            }

            NoteSection(txnID: txn.id)

            SubscriptionToggleSection(txn: txn)

            if let item = location.item {
                LocationSection(item: item, source: location.source, address: txn.merchantAddress ?? location.foundAddress)
            }

            // Only worth a link when there is more than this one purchase.
            if others.count > 1 {
                Section {
                    NavigationLink(value: MerchantRoute(key: txn.merchantKey, name: txn.description)) {
                        LabeledContent {
                            Text("\(others.count) purchase(s)")
                        } label: {
                            Label("All purchases at \(txn.description)", systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
        }
        .navigationTitle(txn.description)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .appBackground()
        .task { await location.find(for: txn) }
    }
}

private struct LocationSection: View {
    var item: MKMapItem
    var source: PurchaseLocation.Source
    var address: String?

    var body: some View {
        let coordinate = PurchaseLocation.coordinate(of: item)
        Section {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
                interactionModes: []) {
                Marker(item.name ?? "", coordinate: coordinate)
            }
            .frame(height: 170)
            .listRowInsets(EdgeInsets())
            .allowsHitTesting(false)

            Button {
                item.openInMaps()
            } label: {
                LabeledContent {
                    Image(systemName: "arrow.up.right.square")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "")
                        if let line = address ?? Self.addressLine(item) {
                            Text(line).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Location")
        } footer: {
            switch source {
            case .provided: Text("Address given by Max.")
            case .guessed: Text("Probable location, found by the merchant’s name. It may be another branch.")
            case .openStreetMap: Text("Probable location, found by the merchant’s name on OpenStreetMap (© OpenStreetMap contributors). It may be another branch.")
            }
        }
    }

    static func addressLine(_ item: MKMapItem) -> String? {
        if #available(iOS 26, *) {
            return item.address?.shortAddress
        }
        let p = item.placemark
        let line = [p.thoroughfare, p.subThoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
        return line.isEmpty ? nil : line
    }
}

struct MerchantHistoryView: View {
    @Environment(AppModel.self) private var model
    var route: MerchantRoute

    var body: some View {
        let txns = Spending.atMerchant(route.key, in: model.allPurchases).filter { $0.chargedCurrency == "ILS" }
        let total = Spending.total(txns)
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total").font(.subheadline).foregroundStyle(.secondary)
                        Money(total, alignment: .leading, secondaryFont: .subheadline)
                            .font(.title.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(txns.count) purchase(s)").font(.subheadline).foregroundStyle(.secondary)
                        if !txns.isEmpty {
                            Text("about \((total / Double(txns.count)).wholeShekels) each")
                                .font(.subheadline)
                                .privacySensitive()
                        }
                    }
                }
                if let first = txns.last?.date, let last = txns.first?.date {
                    let months = Spending.buckets(txns, from: first, to: last, by: .month)
                    if months.count > 1 {
                        Chart(months) { m in
                            BarMark(x: .value("Month", m.start, unit: .month), y: .value("Amount", m.total))
                                .foregroundStyle(Format.categoryColor(txns.first?.category).gradient)
                                .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.narrow))
                            }
                        }
                        .chartYAxis(.hidden)
                        .frame(height: 120)
                    }
                }
            }

            Section {
                ForEach(txns) { t in
                    NavigationLink(value: TxnRoute(txn: t)) { TransactionRow(txn: t) }
                }
            } footer: {
                Text("Purchases saved on this iPhone.")
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .appBackground()
    }
}
