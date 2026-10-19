import Foundation
import Testing
@testable import TrueBalanceCore

@Test func parsesMaxMonth() throws {
    let json = """
    {"result":{"transactions":[
      {"shortCardNumber":"4580","paymentDate":"2026-11-02T00:00:00","purchaseDate":"2026-10-05T00:00:00",
       "originalAmount":412.9,"originalCurrency":"ILS","actualPaymentAmount":412.9,"paymentCurrency":376,
       "merchantName":" שופרסל דיל ","comments":"","planName":"רגילה","planTypeId":5,"categoryId":7,
       "dealData":{"arn":"A1"}},
      {"shortCardNumber":"4580","paymentDate":"2026-12-02T00:00:00","purchaseDate":"2026-10-10T00:00:00",
       "originalAmount":749.7,"actualPaymentAmount":249.9,"paymentCurrency":376,"merchantName":"IKEA",
       "comments":"תשלום 2 מתוך 3","planName":"תשלומים","categoryId":4,"dealData":{"arn":"A2"}},
      {"shortCardNumber":"4580","paymentDate":null,"purchaseDate":"2026-10-19T00:00:00",
       "actualPaymentAmount":38.5,"paymentCurrency":376,"merchantName":"רמי לוי","planName":"רגילה","categoryId":7},
      {"shortCardNumber":"4580","paymentDate":"2026-11-02T00:00:00","purchaseDate":"2026-10-12T00:00:00",
       "actualPaymentAmount":20,"paymentCurrency":840,"merchantName":"Netflix","planName":"אינטרנט/חו\\"ל","categoryId":9},
      {"shortCardNumber":"4580","planName":"","actualPaymentAmount":999}
    ]}}
    """
    let txns = try MaxParser.parseMonth(Data(json.utf8))
    #expect(txns.count == 4) // summary row dropped

    #expect(txns[0].description == "שופרסל דיל")
    #expect(txns[0].chargedAmount == -412.9)
    #expect(txns[0].category == "groceries")
    #expect(Israel.day(txns[0].processedDate) == "2026-11-02")
    #expect(txns[0].status == .completed)
    #expect(txns[0].cardLast4 == "4580")
    #expect(txns[0].logoURL == nil)
    #expect(txns[0].merchantAddress == nil)

    #expect(txns[1].installments == Installments(number: 2, total: 3))
    #expect(txns[1].id == "A2_2")
    #expect(txns[1].category == "home")

    #expect(txns[2].status == .pending)
    #expect(txns[3].chargedCurrency == "USD")
}

@Test func parsesLeumiBalance() throws {
    let inner = #"{"BalanceDisplay":"163.00","TodayTransactionsItems":[{"DateUTC":"2026-10-19T06:00:00Z","Description":"העברה","Amount":-50,"ReferenceNumberLong":1}],"HistoryTransactionsItems":[{"DateUTC":"2026-10-02T05:00:00Z","Description":"מקס איט פיננ","Amount":-964.2,"ReferenceNumberLong":2}]}"#
    let envelope = try JSONSerialization.data(withJSONObject: ["jsonResp": inner])
    let account = try LeumiParser.parse(envelope, accountNumber: "812-123456")
    #expect(account.balance == 163)
    #expect(account.txns.count == 2)
    #expect(account.txns[0].status == .pending)
    #expect(account.txns[1].chargedAmount == -964.2)
}

@Test func leumiWithoutBalanceFails() throws {
    let envelope = try JSONSerialization.data(withJSONObject: ["jsonResp": "{}"])
    #expect(throws: ParseError.self) { try LeumiParser.parse(envelope, accountNumber: "x") }
}

@Test func pendingMaxTxnUsesOriginalAmount() throws {
    let json = """
    {"result":{"transactions":[{"paymentDate":null,"purchaseDate":"2026-10-19T00:00:00","originalAmount":42,
      "originalCurrency":"ILS","actualPaymentAmount":0,"paymentCurrency":376,"merchantName":"שדה הראיה","planName":"רגילה"}]}}
    """
    let txn = try #require(try MaxParser.parseMonth(Data(json.utf8)).first)
    #expect(txn.status == .pending)
    #expect(txn.chargedAmount == -42)
    #expect(txn.chargedCurrency == "ILS")
}

@Test func parsesLeumiBalanceSentAsNumber() throws {
    let inner = #"{"BalanceDisplay":163.53,"TodayTransactionsItems":null,"HistoryTransactionsItems":[{"DateUTC":"2026-10-02T05:00:00Z","Description":"x","Amount":"-1,050.25","ReferenceNumberLong":"77"}]}"#
    let envelope = try JSONSerialization.data(withJSONObject: ["jsonResp": inner])
    let account = try LeumiParser.parse(envelope, accountNumber: "812")
    #expect(account.balance == 163.53)
    #expect(account.txns.first?.chargedAmount == -1050.25)
    #expect(account.txns.first?.id == "77")
}

@Test func maxLogoIsPickedUpWhenPresent() throws {
    let json = """
    {"result":{"transactions":[{"shortCardNumber":"1234","paymentDate":"2026-11-02T00:00:00","purchaseDate":"2026-10-05T00:00:00",
      "actualPaymentAmount":10,"paymentCurrency":376,"merchantName":"Wolt","planName":"רגילה",
      "merchantLogoUrl":"https://cdn.example.com/wolt.png","merchantAddress":"Dizengoff 50","merchantCity":"Tel Aviv"}]}}
    """
    let txn = try #require(try MaxParser.parseMonth(Data(json.utf8)).first)
    #expect(txn.logoURL == "https://cdn.example.com/wolt.png")
    #expect(txn.cardLast4 == "1234")
    #expect(txn.merchantAddress == "Dizengoff 50, Tel Aviv")
}
