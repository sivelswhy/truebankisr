import Charts
import MapKit
import SwiftUI
import TrueBalanceCore

struct TxnRoute: Hashable { var txn: Txn }
struct MerchantRoute: Hashable { var key: String; var name: String }

extension View {
    /// Purchase detail and merchant history, reachable from any list of purchases.
    func purchaseDestinations() -> some View {
        navigationDestination(for: TxnRoute.self) { TransactionDetailView(txn: $0.txn) }
            .navigationDestination(for: MerchantRoute.self) { MerchantHistoryView(route: $0) }
    }
}

extension AppModel {
    /// Every card purchase known: full history, or the upcoming ones for older snapshots.
    var allPurchases: [Txn] {
        guard let s = snapshot else { return [] }
        return s.history ?? s.upcoming.flatMap(\.txns)
    }
}

/// Big merchant badge: the card company's logo when it sends one, otherwise
/// the merchant's initials in its category colour.
struct MerchantLogo: View {
    var txn: Txn
    var size: CGFloat

    var body: some View {
        Group {
            if let url = txn.logoURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().padding(size * 0.12).background(.white)
                } placeholder: {
                    monogram
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.26, style: .continuous))
        .shadow(color: Format.categoryColor(txn.category).opacity(0.35), radius: size * 0.12, y: size * 0.05)
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        Rectangle()
            .fill(Format.categoryColor(txn.category).gradient)
            .overlay {
                Text(Self.initials(txn.description))
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
    }

    /// "Aroma Espresso Bar" → "AE", "שופרסל דיל" → "שד".
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

/// Card row: generic card icon, two dots in the middle, last 4 digits.
struct CardRow: View {
    var last4: String?

    var body: some View {
        HStack {
            Image(systemName: "creditcard")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "••")
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: last4 ?? "––––")
                .monospacedDigit()
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
    enum Source { case provided, guessed }

    private(set) var item: MKMapItem?
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
        guard let found = try? await MKLocalSearch(request: request).start().mapItems.first,
              Self.isInIsrael(Self.coordinate(of: found)) else { return }
        item = found
        source = txn.merchantAddress == nil ? .guessed : .provided
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
                    Text((-txn.chargedAmount).formatted(.currency(code: txn.chargedCurrency)))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .privacySensitive()
                    HStack(spacing: 6) {
                        Text(txn.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
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

            if let item = location.item {
                LocationSection(item: item, source: location.source, address: txn.merchantAddress)
            }

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
        .navigationTitle(txn.description)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
            Text(source == .provided
                ? "Address given by Max."
                : "Probable location, found by the merchant’s name. It may be another branch.")
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
                        Text(total.shekels)
                            .font(.title.bold())
                            .monospacedDigit()
                            .privacySensitive()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(txns.count) purchase(s)").font(.subheadline).foregroundStyle(.secondary)
                        if !txns.isEmpty {
                            Text("about \((total / Double(txns.count)).formatted(.currency(code: "ILS").precision(.fractionLength(0)))) each")
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
    }
}
