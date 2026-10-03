// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RemoteVoiceSwitcher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "RemoteVoiceSwitcher", targets: ["RemoteVoiceSwitcher"])],
    targets: [
        .target(name: "VoiceSwitchCore"),
        .executableTarget(name: "RemoteVoiceSwitcher", dependencies: ["VoiceSwitchCore"]),
        .executableTarget(name: "VoiceSwitchChecks", dependencies: ["VoiceSwitchCore"], path: "Tests/VoiceSwitchCoreTests"),
    ]
)
