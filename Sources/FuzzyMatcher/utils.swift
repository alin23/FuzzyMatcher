import Foundation

public extension [String] {
    func fuzzyFind(_ pattern: some ToRustStr) -> String? {
        FuzzyMatcher.fuzzyFind(pattern, in: self)
    }

    func fuzzyFindAll(_ pattern: some ToRustStr) -> [String] {
        FuzzyMatcher.fuzzyFindAll(pattern, in: self)
    }

    func fuzzyFindIndices(_ pattern: some ToRustStr) -> [(String, [Int])] {
        FuzzyMatcher.fuzzyFindIndices(pattern, in: self)
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
