enum ProjectNumberResolver {
    private static let keyIndices: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8, 29: 9,
        83: 0, 84: 1, 85: 2, 86: 3, 87: 4, 88: 5, 89: 6, 91: 7, 92: 8, 82: 9]

    static func index(keyCode: UInt16) -> Int? { keyIndices[keyCode] }

    static func label(index: Int) -> String? {
        guard (0...9).contains(index) else { return nil }
        return String((index + 1) % 10)
    }
}
