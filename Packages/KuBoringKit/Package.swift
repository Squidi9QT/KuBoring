// swift-tools-version: 6.0

import PackageDescription

let features = ["FeatureMusic", "FeatureShelf", "FeatureClipboard", "FeatureTimer", "FeatureAI",
                "FeatureScreenText", "FeatureSystem", "FeatureCalendar", "FeatureCamera", "FeatureIndicators"]

let package = Package(
    name: "KuBoringKit",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KuBoringKit", targets: ["KuBoringCore"] + features)
    ],
    targets: [
        .target(name: "KuBoringCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KuBoringCoreTests", dependencies: ["KuBoringCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FeatureTests",
                    dependencies: ["FeatureMusic", "FeatureIndicators", "FeatureCalendar", "FeatureShelf", "FeatureClipboard"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ] + features.map {
        .target(name: $0, dependencies: ["KuBoringCore"], swiftSettings: [.swiftLanguageMode(.v5)])
    }
)
