import Cocoa
import Carbon.HIToolbox.Events

extension SpaceItem: GridTileItem {
    var maximumTileWidth: CGFloat? { 380 }
    /// The fallback AppKit images are available on every supported macOS version.
    var icon: NSImage? {
        if let previewIcon { return previewIcon }
        return NSImage(named: isFullscreen ? NSImage.enterFullScreenTemplateName : NSImage.computerName)
    }
}

class SpacesPanel: GridPanel {
    static var shared: SpacesPanel!

    override init() {
        super.init()
        Self.shared = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Escape cancels. The window switcher's `cancelShortcut` is `.local`-scoped and gated on a live
    /// `SwitcherSession`, which a Spaces summon never creates, so it cannot serve this panel.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter): SpacesSwitcher.focusSelected()
        case UInt16(kVK_Escape): SpacesSwitcher.hide()
        default: super.keyDown(with: event)
        }
    }

}
