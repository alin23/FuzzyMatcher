import RustXcframework

public extension [String] {
    func fuzzyFind(_ pattern: some ToRustStr) -> String? {
        FuzzyMatcher.fuzzyFind(pattern, in: self)
    }
}

public func fuzzyFind<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, in lines: [String]) -> String? {
    fuzzy_find(pattern, lines.joined(separator: "\u{1}") as! GenericToRustStr)?.toString()
}

public func fuzzyFindAll<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, in lines: [String]) -> [String] {
    fuzzy_find_all(pattern, lines.joined(separator: "\u{1}") as! GenericToRustStr).map { $0.as_str().toString() }
}

public func fuzzyFindIndices<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, in lines: [String]) -> [(String, [Int])] {
    fuzzy_indices(pattern, lines.joined(separator: "\u{1}") as! GenericToRustStr).map {
        let s = $0.as_str().toString()
        let split = s.split(separator: "\u{1}", maxSplits: 1)
        let str = split[0]

        return (String(str), split[1].split(separator: "\u{2}").map { Int($0)! })
    }
}

func fuzzy_find<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustString? {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            {
                let val = __swift_bridge__$fuzzy_find(patternAsRustStr, linesAsRustStr); if val != nil { return RustString(ptr: val!) }
                else { return nil } }()
        }
    }
}

func fuzzy_find_all<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustVec<RustString> {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            RustVec(ptr: __swift_bridge__$fuzzy_find_all(patternAsRustStr, linesAsRustStr))
        }
    }
}

func fuzzy_indices<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustVec<RustString> {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            RustVec(ptr: __swift_bridge__$fuzzy_indices(patternAsRustStr, linesAsRustStr))
        }
    }
}
