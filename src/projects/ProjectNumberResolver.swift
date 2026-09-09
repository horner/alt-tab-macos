enum ProjectNumberResolver {
    struct Entry {
        let id: String
        let desktopNumber: Int?
        var claimIndex = Int.max
    }

    struct Choice: Equatable {
        let id: String
        let label: String?
        let shortcutIndex: Int?
    }

    private static let keyIndices: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8, 29: 9,
        83: 0, 84: 1, 85: 2, 86: 3, 87: 4, 88: 5, 89: 6, 91: 7, 92: 8, 82: 9]

    static func index(keyCode: UInt16) -> Int? { keyIndices[keyCode] }

    static func label(index: Int) -> String? {
        guard (0...9).contains(index) else { return nil }
        return String((index + 1) % 10)
    }

    static func choices(_ entries: [Entry], desktopCount: Int) -> [Choice] {
        guard desktopCount > 1 else {
            return entries.enumerated().map { index, entry in
                Choice(id: entry.id, label: label(index: index), shortcutIndex: index < 10 ? index : nil)
            }
        }
        return entries.enumerated().sorted { lhs, rhs in
            let left = lhs.element.desktopNumber ?? Int.max
            let right = rhs.element.desktopNumber ?? Int.max
            if left != right { return left < right }
            if lhs.element.claimIndex != rhs.element.claimIndex { return lhs.element.claimIndex < rhs.element.claimIndex }
            return lhs.offset < rhs.offset
        }.map { _, entry in
            let number = entry.desktopNumber.flatMap { $0 > 0 ? $0 : nil }
            return Choice(id: entry.id, label: number.map(String.init),
                shortcutIndex: number.flatMap { (1...10).contains($0) ? $0 - 1 : nil })
        }
    }

    static func projectId(keyCode: UInt16, choices: [Choice]) -> String? {
        guard let index = index(keyCode: keyCode) else { return nil }
        return choices.first { $0.shortcutIndex == index }?.id
    }
}
