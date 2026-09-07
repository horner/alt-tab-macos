import Foundation

/// Declared here rather than in `SpacesPreferences.swift` because this file is in the unit-tests target
/// and `MacroPreferences.swift` is not; the `MacroPreference` conformance is added there instead.
enum SpacesOrderPreference: CaseIterable {
    case recentlyFocused
    case desktopOrder
}

/// Pure decision kernel for the Spaces switcher's list order and selection movement. Extracted from
/// `SpacesList` so the ordering rules and the wrap-around arithmetic are unit-tested without a live
/// WindowServer; `SpacesList` is the adapter that gathers the inputs from SkyLight.
enum SpacesOrderResolver {
    /// `UInt64`, not `CGSSpaceID`: the SkyLight typealias is app-target-only, and the kernel only ever
    /// compares ids for equality.
    typealias SpaceId = UInt64

    struct Space: Equatable {
        let id: SpaceId
        /// 1-based "Desktop N" as macOS numbers it, counting user Spaces only. 0 for a fullscreen Space.
        let desktopNumber: Int
        /// Position in the WindowServer's own display/Space enumeration. The tie-break, and the whole
        /// order for fullscreen Spaces, which have no desktop number to sort by.
        let enumerationRank: Int
    }

    /// `mru` is most-recently-visited first. A Space absent from it has never been visited while AltTab
    /// was running, so it sorts after every visited one rather than to an arbitrary end of the list.
    static func sorted(_ spaces: [Space], mru: [SpaceId], by order: SpacesOrderPreference) -> [Space] {
        guard order == .recentlyFocused else {
            return spaces.sorted { lhs, rhs in
                if lhs.desktopNumber != rhs.desktopNumber {
                    // fullscreen Spaces (0) go last, not first
                    if lhs.desktopNumber == 0 { return false }
                    if rhs.desktopNumber == 0 { return true }
                    return lhs.desktopNumber < rhs.desktopNumber
                }
                return lhs.enumerationRank < rhs.enumerationRank
            }
        }
        let rank = Dictionary(uniqueKeysWithValues: mru.enumerated().map { ($0.element, $0.offset) })
        return spaces.sorted { lhs, rhs in
            let lhsRank = rank[lhs.id] ?? Int.max
            let rhsRank = rank[rhs.id] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.enumerationRank < rhs.enumerationRank
        }
    }

    /// Where the highlight lands when the panel opens: the first Space that is not the one the user is
    /// already on, so a press-and-release round-trips to the previous Space the way alt-tab does.
    static func initialSelection(count: Int, currentIndex: Int?) -> Int {
        guard count > 0 else { return 0 }
        guard let currentIndex, currentIndex >= 0, currentIndex < count else { return 0 }
        return count == 1 ? currentIndex : (currentIndex + 1) % count
    }

    static func cycle(selected: Int, step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = (selected + step) % count
        return next < 0 ? next + count : next
    }

    /// How many tiles per row. A Mac can hold far more Spaces than fit across the screen, so the row wraps;
    /// `maxColumns` is what the caller measured as fitting. Once wrapping is unavoidable the rows are then
    /// balanced: 13 Spaces in a 11-wide panel read as 7 + 6, not as a full row trailed by a stub of 2.
    static func gridColumns(count: Int, maxColumns: Int) -> Int {
        guard count > 0, maxColumns > 0 else { return 1 }
        guard count > maxColumns else { return count }
        let rows = Int((Double(count) / Double(maxColumns)).rounded(.up))
        return Int((Double(count) / Double(rows)).rounded(.up))
    }
}
