// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserPicker",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BrowserPicker", targets: ["BrowserPicker"]),
    ],
    targets: [
        .target(name: "BrowserPickerCore"),
        .executableTarget(name: "BrowserPicker", dependencies: ["BrowserPickerCore"]),
        .testTarget(name: "BrowserPickerCoreTests", dependencies: ["BrowserPickerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
