import Foundation
import Yams

struct ProjectFileDocument: Codable {
    var entry: ProjectEntry
    var order: Int
    var isDeleted: Bool
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, order, isDeleted, id, kind, spaceUuid, homeSpaceUuid, name, autoName, iconFileName
        case windowHistory, memberPatterns, excludedPatterns, linkedProjectIds, labelUuid, isClosed, closedWindows
    }

    init(entry: ProjectEntry, order: Int, isDeleted: Bool = false) {
        self.entry = Self.durable(entry)
        self.order = order
        self.isDeleted = isDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw ProjectFileError.invalid("Unsupported schemaVersion; expected 1")
        }
        let id = try c.decode(String.self, forKey: .id)
        let kind = try c.decode(String.self, forKey: .kind)
        let home = try c.decode(String.self, forKey: .homeSpaceUuid)
        let space = try c.decodeIfPresent(String.self, forKey: .spaceUuid)
        guard !id.isEmpty, !home.isEmpty, ["custom", "desktop"].contains(kind), kind != "desktop" || space == home else {
            throw ProjectFileError.invalid("A project needs an id, a homeSpaceUuid and a valid kind; desktop spaceUuid must match its home")
        }
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        entry = ProjectEntry(id: id, kind: kind, spaceUuid: space, homeSpaceUuid: home,
            name: try c.decodeIfPresent(String.self, forKey: .name), autoName: try c.decodeIfPresent(String.self, forKey: .autoName),
            iconFileName: try c.decodeIfPresent(String.self, forKey: .iconFileName),
            memberPatterns: try c.decodeIfPresent([ProjectWindowPattern].self, forKey: .memberPatterns) ?? [],
            excludedPatterns: try c.decodeIfPresent([ProjectWindowPattern].self, forKey: .excludedPatterns) ?? [],
            windowHistory: try c.decodeIfPresent([ProjectWindowPattern].self, forKey: .windowHistory) ?? [],
            linkedProjectIds: try c.decodeIfPresent([String].self, forKey: .linkedProjectIds) ?? [],
            labelUuid: try c.decodeIfPresent(String.self, forKey: .labelUuid),
            isClosed: try c.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false)
        entry.closedWindows = try c.decodeIfPresent([ProjectWindowPattern].self, forKey: .closedWindows)
        guard (entry.memberPatterns + entry.excludedPatterns + entry.windowHistory + (entry.closedWindows ?? [])).allSatisfy({ !$0.bundleIdentifier.isEmpty }) else {
            throw ProjectFileError.invalid("Window patterns need a bundleIdentifier")
        }
    }

    func encode(to encoder: Encoder) throws {
        try entry.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .schemaVersion)
        try c.encode(order, forKey: .order)
        try c.encode(isDeleted, forKey: .isDeleted)
    }

    func node() throws -> Node {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        encoder.options.mappingStyle = .block
        encoder.options.sequenceStyle = .block
        guard var node = try Yams.compose(yaml: encoder.encode(self)) else { throw ProjectFileError.invalid("Empty project") }
        for key in ["members", "excludedMembers", "pendingDesktopRemoval", "linkedProjectId"] { node.mapping?[key] = nil }
        return node
    }

    static func durable(_ source: ProjectEntry) -> ProjectEntry {
        var entry = source
        entry.members = []
        entry.excludedMembers = []
        entry.pendingDesktopRemoval = false
        entry.windowHistory = stablePatterns(entry.windowHistory)
        entry.memberPatterns = stablePatterns(entry.memberPatterns)
        entry.excludedPatterns = stablePatterns(entry.excludedPatterns)
        entry.closedWindows = entry.closedWindows.map(stablePatterns)
        return entry
    }

    private static func stablePatterns(_ patterns: [ProjectWindowPattern]) -> [ProjectWindowPattern] {
        patterns.map { pattern in
            var copy = pattern
            copy.lastSeenAt = nil
            return copy
        }.sorted { [$0.bundleIdentifier, $0.title, $0.url ?? "", $0.spaceUuid ?? ""].lexicographicallyPrecedes([$1.bundleIdentifier, $1.title, $1.url ?? "", $1.spaceUuid ?? ""]) }
    }
}

enum ProjectFileError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

struct ProjectRuntimeEntry: Codable {
    var id: String
    var members: [ProjectWindowIdentity]
    var excludedMembers: [ProjectWindowIdentity]
    var pendingDesktopRemoval: Bool
    var observations: [ProjectWindowPattern]

    init(_ entry: ProjectEntry) {
        id = entry.id
        members = entry.members
        excludedMembers = entry.excludedMembers
        pendingDesktopRemoval = entry.pendingDesktopRemoval
        observations = entry.windowHistory + entry.memberPatterns + entry.excludedPatterns + (entry.closedWindows ?? [])
    }

    func applying(to source: ProjectEntry) -> ProjectEntry {
        var entry = source
        entry.members = members
        entry.excludedMembers = excludedMembers
        entry.pendingDesktopRemoval = pendingDesktopRemoval
        entry.windowHistory = restoreDates(entry.windowHistory)
        entry.memberPatterns = restoreDates(entry.memberPatterns)
        entry.excludedPatterns = restoreDates(entry.excludedPatterns)
        entry.closedWindows = entry.closedWindows.map(restoreDates)
        return entry
    }

    private func restoreDates(_ patterns: [ProjectWindowPattern]) -> [ProjectWindowPattern] {
        patterns.map { pattern in
            var copy = pattern
            copy.lastSeenAt = observations.filter { $0 == pattern }.compactMap(\.lastSeenAt).max()
            return copy
        }
    }
}

struct ProjectFileRecovery: Codable {
    var schemaVersion = 2
    var projects: [String: ProjectFileDocument]
    var desktops: [String: ProjectFileDocument]

    static func decode(_ data: Data) -> ProjectFileRecovery? {
        let decoder = JSONDecoder()
        if let recovery = try? decoder.decode(Self.self, from: data), recovery.schemaVersion == 2 { return recovery }
        guard let projects = try? decoder.decode([String: ProjectFileDocument].self, from: data) else { return nil }
        return Self(projects: projects, desktops: [:])
    }
}

enum ProjectDesktopDocument {
    static func empty() -> Node {
        Node([(Node("schemaVersion"), Node(2)), (Node("desktops"), .mapping(Node.Mapping([])))])
    }

    static func parse(_ text: String) throws -> (documents: [String: ProjectFileDocument], node: Node) {
        let node = try ProjectYAML.parseNode(text)
        guard node["schemaVersion"]?.int == 2 else { throw ProjectFileError.invalid("Unsupported desktops.yaml schemaVersion; expected 2") }
        guard let mapping = node["desktops"]?.mapping else { throw ProjectFileError.invalid("desktops.yaml needs a desktops mapping keyed by id") }
        var documents = [String: ProjectFileDocument]()
        for pair in mapping {
            let document = try YAMLDecoder().decode(ProjectFileDocument.self, from: pair.value)
            guard document.entry.kind == "desktop", pair.key.string == document.entry.id else {
                throw ProjectFileError.invalid("Desktop mapping keys must match each desktop record's id and kind")
            }
            documents[document.entry.id] = document
        }
        return (documents, node)
    }
}
