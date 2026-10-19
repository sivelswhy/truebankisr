// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrueBalanceCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "TrueBalanceCore", targets: ["TrueBalanceCore"])],
    targets: [
        .target(name: "TrueBalanceCore"),
        .testTarget(name: "TrueBalanceCoreTests", dependencies: ["TrueBalanceCore"]),
    ]
)
