import Cocoa
import Carbon.HIToolbox.Events

extension SpaceItem: GridTileItem {
    /// Named AppKit images are available on every supported macOS version.
    var icon: NSImage? {
        NSImage(named: isFullscreen ? NSImage.enterFullScreenTemplateName : NSImage.computerName)
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
        guard event.keyCode == UInt16(kVK_Escape) else { return super.keyDown(with: event) }
        SpacesSwitcher.hide()
    }

}
