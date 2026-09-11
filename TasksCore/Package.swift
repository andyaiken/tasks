// swift-tools-version: 6.0
import PackageDescription

// Domain logic for the shared recurring task list: scheduling, urgency, the
// main list, the digest and participant labels (SPEC.md §3–§9). Deliberately
// free of CloudKit and UI types so it can be tested with `swift test`.
let package = Package(
    name: "TasksCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TasksCore", targets: ["TasksCore"]),
    ],
    targets: [
        .target(name: "TasksCore"),
        .testTarget(name: "TasksCoreTests", dependencies: ["TasksCore"]),
    ]
)
