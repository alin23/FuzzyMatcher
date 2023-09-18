import FuzzyMatcherRust
public func fuzzy_find<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustString? {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            { let val = __swift_bridge__$fuzzy_find(patternAsRustStr, linesAsRustStr); if val != nil { return RustString(ptr: val!) } else { return nil } }()
        }
    }
}
public func fuzzy_find_all<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustVec<RustString> {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            RustVec(ptr: __swift_bridge__$fuzzy_find_all(patternAsRustStr, linesAsRustStr))
        }
    }
}
public func fuzzy_indices<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustVec<RustString> {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            RustVec(ptr: __swift_bridge__$fuzzy_indices(patternAsRustStr, linesAsRustStr))
        }
    }
}
