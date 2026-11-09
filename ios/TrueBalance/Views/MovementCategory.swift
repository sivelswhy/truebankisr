import Foundation
import TrueBalanceCore

/// Max sends a category with each card purchase; Leumi and European banks do
/// not. This guesses one from the wording, so every row can show a category icon.
enum MovementCategory {
    /// Keyword → category key, first match wins. Hebrew, English and French.
    private static let rules: [(key: String, words: [String])] = [
        ("transfer", ["העברה", "ביט", "paybox", "פייבוקס", "transfer", "virement", "vir ", "sepa", "wise", "revolut", "paypal"]),
        ("cash", ["משיכת מזומן", "כספומט", "atm", "retrait", "cash", "dab "]),
        ("groceries", ["שופרסל", "רמי לוי", "מגה", "יוחננוף", "ויקטורי", "אושר עד", "טיב טעם", "קרפור", "carrefour", "lidl", "aldi",
                       "leclerc", "auchan", "monoprix", "franprix", "intermarche", "casino", "mercadona", "tesco", "rewe", "edeka",
                       "supermarche", "supermarket", "boulangerie", "bakery"]),
        ("restaurants", ["מסעדה", "קפה", "ארומה", "מקדונלד", "פיצה", "וולט", "wolt", "restaurant", "mcdonald", "burger", "starbucks",
                         "uber eats", "deliveroo", "just eat", "cafe", "café", "brasserie", "pizz", "sushi"]),
        ("transport", ["רב קו", "רב-קו", "גט", "דן", "אגד", "רכבת", "פנגו", "סונול", "uber", "bolt", "sncf", "ratp", "navigo", "taxi",
                       "transavia", "flixbus", "blablacar", "parking", "péage", "peage", "autoroute", "metro", "train"]),
        ("energy", ["דלק", "פז", "דור אלון", "חברת החשמל", "מי ", "edf", "engie", "total", "shell", "esso", "bp ", "carburant", "essence"]),
        ("telecom", ["סלקום", "פלאפון", "פרטנר", "הוט", "בזק", "yes", "orange", "sfr", "bouygues", "free mobile", "free ", "vodafone", "telekom"]),
        ("insurance", ["ביטוח", "הראל", "מגדל", "כלל", "הפניקס", "מנורה", "assurance", "axa", "maif", "macif", "allianz", "insurance"]),
        ("health", ["מכבי", "כללית", "מאוחדת", "לאומית", "סופר פארם", "בית מרקחת", "pharmacie", "pharmacy", "doctolib", "médecin", "medecin",
                    "dentist", "dentiste", "hopital", "hôpital", "clinique", "optic"]),
        ("government", ["מס הכנסה", "ביטוח לאומי", "עירייה", "ארנונה", "רשות", "impot", "impôt", "dgfip", "tresor", "trésor", "ameli",
                        "caf ", "urssaf", "tax", "mairie"]),
        ("leisure", ["netflix", "spotify", "disney", "youtube", "apple.com", "cinema", "cinéma", "ugc", "pathé", "pathe", "fnac",
                     "steam", "playstation", "xbox", "gym", "fitness", "basic-fit", "decathlon", "סינמה", "קולנוע", "הולמס"]),
        ("travel", ["airbnb", "booking", "hotel", "hôtel", "ryanair", "easyjet", "air france", "el al", "אל על", "אל-על", "expedia", "trip"]),
        ("fashion", ["zara", "h&m", "castro", "קסטרו", "פוקס", "uniqlo", "primark", "kiabi", "nike", "adidas"]),
        ("home", ["ikea", "איקאה", "leroy merlin", "castorama", "bricomarche", "בית", "loyer", "rent", "שכר דירה"]),
        ("electronics", ["אייבורי", "ksp", "בי אס טי", "amazon", "darty", "boulanger", "apple store", "micromania", "mediamarkt"]),
        ("pets", ["וטרינר", "פט", "vétérinaire", "veterinaire", "animalerie", "zooplus"]),
        ("beauty", ["קוסמטיקה", "מספרה", "sephora", "coiffeur", "salon"]),
        ("books", ["steimatzky", "צומת ספרים", "librairie", "kindle"]),
    ]

    static func key(_ text: String, incoming: Bool) -> String {
        let t = " " + text.lowercased() + " "
        for rule in rules where rule.words.contains(where: { t.contains($0) }) { return rule.key }
        return incoming ? "transfer" : "other"
    }

    /// A Leumi movement: card debits and transfers are known from its kind.
    static func key(_ txn: Txn) -> String {
        switch BankMovement.kind(txn) {
        case .cardDebit: return "max"
        case .transferIn, .transferOut: return "transfer"
        case .income, .expense:
            return key([txn.description, txn.memo ?? ""].joined(separator: " "), incoming: txn.chargedAmount > 0)
        }
    }

    static func key(_ txn: EuroTxn) -> String {
        key([txn.party ?? "", txn.details ?? ""].joined(separator: " "), incoming: txn.amount > 0)
    }
}
