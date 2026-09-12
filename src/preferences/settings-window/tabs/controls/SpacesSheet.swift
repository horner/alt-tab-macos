import Cocoa

class SpacesSheet: SheetWindow {
    // Localized labels live here once. `searchableStrings` and `makeContentView` both reference
    // these constants so changing a string takes one edit, and search can't silently miss a row
    // because of a typo divergence between the two paths.
    private static let title = NSLocalizedString("Spaces switcher", comment: "")
    private static let labelHold = NSLocalizedString("Hold", comment: "")
    private static let labelNext = NSLocalizedString("Select next space", comment: "")
    private static let labelPrevious = NSLocalizedString("Select previous space", comment: "")
    private static let labelStyle = NSLocalizedString("On release", comment: "")
    private static let labelOrder = NSLocalizedString("Order spaces by", comment: "")
    private static let labelFullscreen = NSLocalizedString("Show fullscreen spaces", comment: "")

    /// Pre-build search index for the open-button. See `SettingsSearchIndex.sheetSearchableStrings`.
    static let searchableStrings: [String] = [
        title, labelHold, labelNext, labelPrevious, labelStyle, labelOrder, labelFullscreen,
    ] + SpacesOrderPreference.allCases.map { $0.localizedString }
        + ShortcutStylePreference.allCases.map { $0.localizedString }

    override func makeContentView() -> NSView {
        let table = TableGroupView(title: Self.title, width: SheetWindow.width)
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.labelHold, rightViews: [
            LabelAndControl.makeLabelWithRecorder(Self.labelHold, SpacesSwitcher.holdShortcutId,
                Preferences.holdSpacesShortcut, labelPosition: .right)[0],
        ]))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.labelNext, rightViews: [
            LabelAndControl.makeLabelWithRecorder(Self.labelNext, SpacesSwitcher.nextShortcutId,
                Preferences.nextSpaceShortcut, labelPosition: .right)[0],
        ]))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.labelPrevious, rightViews: [
            LabelAndControl.makeLabelWithRecorder(Self.labelPrevious, SpacesSwitcher.previousShortcutId,
                Preferences.previousSpaceShortcut, labelPosition: .right)[0],
        ]))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.labelStyle, rightViews: [
            LabelAndControl.makeDropdown("spacesShortcutStyle", ShortcutStylePreference.allCases),
        ]))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.labelOrder, rightViews: [
            LabelAndControl.makeDropdown("spacesOrder", SpacesOrderPreference.allCases),
        ]))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.labelFullscreen, rightViews: [
            LabelAndControl.makeSwitch("showFullscreenSpaces"),
        ]))
        return TableGroupSetView(originalViews: [table], padding: 0)
    }
}
