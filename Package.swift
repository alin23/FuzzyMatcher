// swift-tools-version:5.5.0
import PackageDescription
let package = Package(
	name: "FuzzyMatcher",
	products: [
		.library(
			name: "FuzzyMatcher",
			targets: ["FuzzyMatcher"]),
	],
	dependencies: [],
	targets: [
		.binaryTarget(
			name: "RustXcframework",
			path: "RustXcframework.xcframework"
		),
		.target(
			name: "FuzzyMatcher",
			dependencies: ["RustXcframework"])
	]
)
	