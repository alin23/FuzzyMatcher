import RustXcframework

public extension Array where Element == String {
    func fuzzyFind<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr) -> String? {
        FuzzyMatcher.fuzzyFind(pattern, in: self)
    }
}

public func fuzzyFind<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, in lines: [String]) -> String? {
    fuzzy_find(pattern, lines.joined(separator: "§") as! GenericToRustStr)?.toString()
}

func fuzzy_find<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustString? {
    return lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            { let val = __swift_bridge__$fuzzy_find(patternAsRustStr, linesAsRustStr); if val != nil { return RustString(ptr: val!) } else { return nil } }()
        }
    }
}
