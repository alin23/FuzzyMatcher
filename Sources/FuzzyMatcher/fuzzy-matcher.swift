import RustXcframework
public func fuzzy_find<GenericToRustStr: ToRustStr>(_ pattern: GenericToRustStr, _ lines: GenericToRustStr) -> RustString? {
    lines.toRustStr { linesAsRustStr in
        pattern.toRustStr { patternAsRustStr in
            {
                let val = __swift_bridge__$fuzzy_find(patternAsRustStr, linesAsRustStr); if val != nil { return RustString(ptr: val!) }
                else { return nil } }()
        }
    }
}
