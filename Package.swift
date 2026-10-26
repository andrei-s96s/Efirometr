// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Efirometr",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Efirometr",
            path: "Sources/Efirometr",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
