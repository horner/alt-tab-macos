import Foundation
import Yams
import CYaml

/// Patch block fields rather than re-emitting documents. Unchanged fields retain their exact text;
/// comments in a replaced field remain immediately before its replacement.
enum ProjectYAML {
    static func parse(_ text: String) throws -> (ProjectFileDocument, Node) {
        let node = try parseNode(text)
        return (try YAMLDecoder().decode(ProjectFileDocument.self, from: node), node)
    }

    static func parseNode(_ text: String) throws -> Node {
        try validateSyntax(text)
        guard let node = try Yams.compose(yaml: text), let mapping = node.mapping,
              !mapping.isEmpty, mapping.allSatisfy({ $0.key.mark?.column == 1 }) else {
            throw ProjectFileError.invalid("YAML must contain one block mapping")
        }
        var remaining = 100_000
        try validate(node, depth: 0, remaining: &remaining)
        return node
    }

    // The bundled parser checks nesting using scanner state, which can advance past a flow
    // collection before returning its events. Bound events before Yams constructs recursive nodes.
    private static func validateSyntax(_ text: String) throws {
        try text.utf8CString.withUnsafeBytes { bytes in
            var parser = yaml_parser_t()
            guard yaml_parser_initialize(&parser) == 1 else { throw ProjectFileError.invalid("Cannot initialize YAML parser") }
            defer { yaml_parser_delete(&parser) }
            yaml_parser_set_input_string(&parser, bytes.bindMemory(to: UInt8.self).baseAddress!, bytes.count - 1)
            var depth = 0
            var remaining = 100_000
            while true {
                var event = yaml_event_t()
                guard yaml_parser_parse(&parser, &event) == 1 else {
                    let problem = parser.problem.map { String(cString: $0) } ?? "Invalid YAML"
                    throw ProjectFileError.invalid(problem)
                }
                defer { yaml_event_delete(&event) }
                switch event.type {
                case YAML_STREAM_END_EVENT: return
                case YAML_SEQUENCE_START_EVENT, YAML_MAPPING_START_EVENT:
                    depth += 1
                    remaining -= 1
                case YAML_SEQUENCE_END_EVENT, YAML_MAPPING_END_EVENT: depth -= 1
                case YAML_SCALAR_EVENT: remaining -= 1
                case YAML_ALIAS_EVENT: throw ProjectFileError.invalid("YAML aliases are unsupported")
                default: break
                }
                guard depth <= 32, remaining > 0 else { throw ProjectFileError.invalid("YAML is too complex to parse") }
            }
        }
    }

    private static func validate(_ node: Node, depth: Int, remaining: inout Int) throws {
        remaining -= 1
        guard depth < 32, remaining > 0 else { throw ProjectFileError.invalid("YAML is too complex") }
        if case .alias = node { throw ProjectFileError.invalid("YAML aliases are unsupported") }
        if let mapping = node.mapping {
            var keys = Set<String>()
            for pair in mapping {
                guard let key = pair.key.string, pair.key.scalar != nil, key != "<<", keys.insert(key).inserted else {
                    throw ProjectFileError.invalid("YAML keys must be unique strings; merge keys are unsupported")
                }
                try validate(pair.value, depth: depth + 1, remaining: &remaining)
            }
        }
        if let sequence = node.sequence {
            for value in sequence { try validate(value, depth: depth + 1, remaining: &remaining) }
        }
    }

    static func render(_ node: Node) throws -> String {
        var rendered = node
        rendered.mapping?.style = .block
        return try Yams.serialize(node: rendered, indent: 2, width: -1, allowUnicode: true, sortKeys: true)
    }

    static func updating(_ text: String, from disk: Node, to desired: Node) throws -> String {
        let lines = text.components(separatedBy: "\n")
        let end = lines.firstIndex(of: "...") ?? lines.count
        let edits = try changes(lines, from: disk, to: desired, end: end, indent: 0)
        var result = lines
        for edit in edits.enumerated().sorted(by: {
            $0.element.range.lowerBound == $1.element.range.lowerBound ? $0.offset > $1.offset : $0.element.range.lowerBound > $1.element.range.lowerBound
        }).map(\.element) {
            result.replaceSubrange(edit.range, with: edit.lines)
        }
        let updated = result.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        guard try parseNode(updated) == desired else {
            throw ProjectFileError.invalid("Cannot safely update this YAML layout; use ordinary block fields without aliases")
        }
        return updated
    }

    private struct Edit {
        let range: Range<Int>
        let lines: [String]
    }

    private static func changes(_ lines: [String], from disk: Node, to desired: Node, end: Int, indent: Int) throws -> [Edit] {
        guard let mapping = disk.mapping, let target = desired.mapping else { throw ProjectFileError.invalid("Expected a mapping") }
        let pairs = Array(mapping)
        let prefix = String(repeating: " ", count: indent)
        var edits = [Edit]()
        for (index, pair) in pairs.enumerated() {
            guard let key = pair.key.string, pair.value != target[key], let mark = pair.key.mark, mark.column == indent + 1 else { continue }
            let start = mark.line - 1
            let limit = index + 1 < pairs.count ? (pairs[index + 1].key.mark?.line ?? end + 1) - 1 : end
            if let nested = pair.value.mapping, !nested.isEmpty, let next = target[key], next.mapping?.isEmpty == false,
               nested.allSatisfy({ $0.key.mark?.column == indent + 3 && ($0.key.mark?.line ?? 0) > mark.line }) {
                edits += try changes(lines, from: pair.value, to: next, end: limit, indent: indent + 2)
                continue
            }
            let comments = comments(in: Array(lines[start..<limit]), node: pair.value, firstLine: start + 1).map { prefix + $0 }
            let replacement = try target[key].map { try render(Node([(Node(key), $0)])) } ?? ""
            edits.append(Edit(range: start..<limit, lines: comments + replacement.components(separatedBy: "\n").dropLast().map { prefix + $0 }))
        }
        let added = target.filter { disk[$0.key] == nil }
        if !added.isEmpty {
            let suffix = try render(Node(added.map { ($0.key, $0.value) }))
            edits.append(Edit(range: end..<end, lines: suffix.components(separatedBy: "\n").dropLast().map { prefix + $0 }))
        }
        return edits
    }

    private static func comments(in lines: [String], node: Node, firstLine: Int) -> [String] {
        let blockStarts = literalStarts(node)
        var blockIndent: Int?
        var quote: Character?
        var escaped = false
        var comments = [String]()
        for (offset, line) in lines.enumerated() {
            let indent = line.prefix(while: { $0 == " " }).count
            if let current = blockIndent, line.trimmingCharacters(in: .whitespaces).isEmpty || indent > current { continue }
            blockIndent = nil
            let chars = Array(line)
            for index in chars.indices {
                let char = chars[index]
                if escaped { escaped = false; continue }
                if let current = quote {
                    if char == "\\", current == "\"" { escaped = true }
                    if char == current {
                        if current == "'", index + 1 < chars.count, chars[index + 1] == "'" { escaped = true }
                        else { quote = nil }
                    }
                    continue
                }
                if char == "#", index == 0 || chars[index - 1].isWhitespace {
                    comments.append(String(chars[index...]))
                    break
                }
                if char == "\"" || char == "'" {
                    let previous = chars[..<index].last { !$0.isWhitespace }
                    if previous == nil || ":[{,-?".contains(previous!) { quote = char }
                }
            }
            if blockStarts.contains(firstLine + offset) { blockIndent = indent }
        }
        return comments
    }

    private static func literalStarts(_ node: Node) -> Set<Int> {
        if let scalar = node.scalar, [.literal, .folded].contains(scalar.style), let line = node.mark?.line { return [line] }
        return Set((node.mapping.map { $0.map(\.value) } ?? node.array()).flatMap { literalStarts($0) })
    }

    /// External edits win a field-level conflict. Only fields changed by the app since its last
    /// submitted snapshot are candidates for writing, so notes and unrelated editor changes survive.
    static func merge(base: Node, local: Node, disk: Node) -> Node {
        guard let localMap = local.mapping, let baseMap = base.mapping, var merged = disk.mapping else { return disk }
        let localKeys: [String] = localMap.keys.compactMap { $0.string }
        let baseKeys: [String] = baseMap.keys.compactMap { $0.string }
        let keys = Set(localKeys + baseKeys)
        for key in keys where local[key] != base[key] && disk[key] == base[key] { merged[key] = local[key] }
        return .mapping(merged)
    }
}
