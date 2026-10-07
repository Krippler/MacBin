// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "hello-swift",
  products: [.executable(name: "hello-swift", targets: ["hello-swift"])],
  targets: [.executableTarget(name: "hello-swift")]
)
