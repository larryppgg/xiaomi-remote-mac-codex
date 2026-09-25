// swift-tools-version:5.9
import Foundation
import PackageDescription

// Absolute path to the Info.plist embedded into the executable's __TEXT,
//__info_plist section. macOS TIS (TISSelectInputSource / TISCopyCurrentKeyboardInputSource)
// refuses to work from a process without a bundle identifier; embedding the
// plist here makes the helper select/restore input sources even when run as a
// plain binary or inside a minimal .app bundle.
let infoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist")
    .path

let package = Package(
    name: "RemoteVoiceRestore",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(name: "RemoteVoiceRestoreCore"),
        .executableTarget(
            name: "remote-voice-restore",
            dependencies: ["RemoteVoiceRestoreCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "RemoteVoiceRestoreCoreTests",
            dependencies: ["RemoteVoiceRestoreCore"]
        ),
    ]
)
