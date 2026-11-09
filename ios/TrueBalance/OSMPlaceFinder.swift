import CoreLocation
import Foundation
import MapKit

/// Free fallback when Apple Maps finds nothing: OpenStreetMap through Nominatim
/// (name + address search).
/// Results, and misses, are cached per merchant so each name is looked up once.
enum OSMPlaceFinder {
    struct Place {
        var name: String
        var coordinate: CLLocationCoordinate2D
        var address: String?
    }

    // Israel's bounding box (south, west, north, east).
    private static let bbox = (s: 29.4, w: 34.2, n: 33.4, e: 35.95)
    private static let userAgent = "TrueBalance/1.0 (iOS personal finance app)"
    private static let cacheKey = "osmPlaceCache"
    private static let missTTL: TimeInterval = 14 * 86_400

    static func find(key: String, name: String, address: String?) async -> Place? {
        if let cached = cached(key) { return cached.place }
        let place = await nominatim(name: name, address: address)
        // A network failure is not a miss: only cache real answers.
        if let place { store(key, place) } else if reachable { store(key, nil) }
        return place
    }

    // MARK: Nominatim

    private static func nominatim(name: String, address: String?) async -> Place? {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comps.queryItems = [
            .init(name: "q", value: [name, address].compactMap { $0 }.joined(separator: " ")),
            .init(name: "format", value: "jsonv2"),
            .init(name: "countrycodes", value: "il"),
            .init(name: "addressdetails", value: "1"),
            .init(name: "limit", value: "5"),
            .init(name: "accept-language", value: "he,en"),
        ]
        guard let url = comps.url, let data = await fetch(URLRequest(url: url)),
              let rows = try? JSONDecoder().decode([NominatimRow].self, from: data) else { return nil }
        // Without an address, a street or a city is not the merchant: keep real places only.
        let skip: Set<String> = ["boundary", "highway", "place", "landuse", "natural"]
        let row = rows.first { address != nil || !skip.contains($0.category ?? "") }
        guard let row, let lat = Double(row.lat), let lon = Double(row.lon) else { return nil }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        guard inIsrael(c) else { return nil }
        let a = row.address
        let line = [a?.road, a?.houseNumber, a?.city ?? a?.town ?? a?.village]
            .compactMap { $0 }.joined(separator: " ")
        return Place(name: row.name?.isEmpty == false ? row.name! : name,
                     coordinate: c, address: line.isEmpty ? nil : line)
    }

    private struct NominatimRow: Decodable {
        var lat: String
        var lon: String
        var name: String?
        var category: String?
        var address: Addr?
        struct Addr: Decodable {
            var road: String?
            var houseNumber: String?
            var city: String?
            var town: String?
            var village: String?
            enum CodingKeys: String, CodingKey {
                case road, city, town, village
                case houseNumber = "house_number"
            }
        }
    }

    // MARK: Plumbing

    /// Set by the last request: false when the network itself failed.
    nonisolated(unsafe) private static var reachable = true

    private static func fetch(_ request: URLRequest) async -> Data? {
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            reachable = true
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { reachable = false; return nil }
            return data
        } catch {
            reachable = false
            return nil
        }
    }

    private static func inIsrael(_ c: CLLocationCoordinate2D) -> Bool {
        (bbox.s...bbox.n).contains(c.latitude) && (bbox.w...bbox.e).contains(c.longitude)
    }

    private struct Entry: Codable {
        var name: String?
        var lat: Double?
        var lon: Double?
        var address: String?
        var date: Date
        var place: Place? {
            guard let name, let lat, let lon else { return nil }
            return Place(name: name, coordinate: .init(latitude: lat, longitude: lon), address: address)
        }
    }

    /// A valid entry: a hit, or a miss younger than `missTTL`.
    private static func cached(_ key: String) -> Entry? {
        guard let all = try? JSONDecoder().decode([String: Entry].self,
                                                  from: UserDefaults.standard.data(forKey: cacheKey) ?? Data()),
              let e = all[key] else { return nil }
        return e.place != nil || Date().timeIntervalSince(e.date) < missTTL ? e : nil
    }

    private static func store(_ key: String, _ place: Place?) {
        var all = (try? JSONDecoder().decode([String: Entry].self,
                                             from: UserDefaults.standard.data(forKey: cacheKey) ?? Data())) ?? [:]
        all[key] = Entry(name: place?.name, lat: place?.coordinate.latitude,
                         lon: place?.coordinate.longitude, address: place?.address, date: Date())
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: cacheKey)
    }

    static func mapItem(for place: Place) -> MKMapItem {
        let item: MKMapItem
        if #available(iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: place.coordinate.latitude,
                                                  longitude: place.coordinate.longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        }
        item.name = place.name
        return item
    }
}
