# Copilot Instructions for alt-tab-macos

## Project Overview

AltTab is a macOS window switcher app that brings Windows-style Alt+Tab functionality to macOS. It's written in Swift using AppKit (not SwiftUI) and targets macOS 10.12+.

## Build & Run

### Debug Build
```bash
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Debug -configuration Debug build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Launch Debug Build
```bash
open ~/Library/Developer/Xcode/DerivedData/alt-tab-macos-*/Build/Products/Debug/AltTab\ Debug.app
```

### View Logs
```bash
log stream --predicate 'process == "AltTab Debug"' --level debug
```

### Check for Crashes
```bash
log show --predicate 'process == "AltTab Debug"' --last 1m | grep -iE "fatal|index|crash"
```

## Project Structure

```
src/
├── api-wrappers/
│   └── private-apis/      # Private macOS APIs (CGS/SLS via SkyLight.framework)
├── logic/
│   ├── events/            # Keyboard, mouse, trackpad, accessibility events
│   ├── Preferences.swift  # User preferences with per-shortcut arrays
│   └── Windows.swift      # Window management and listing
└── ui/
    ├── main-window/       # ThumbnailsView, ThumbnailView (the switcher UI)
    ├── preferences-window/# Preferences tabs (General, Appearance, Controls, etc.)
    └── App.swift          # Main app entry points
```

## Key Architecture Patterns

### Shortcut System
- **Indices 0-3**: Shortcut 1, Shortcut 2, Shortcut 3, Gesture (trackpad)
- **Index 4**: Spaces mode (if implemented)
- `App.app.shortcutIndex` holds the currently active shortcut index

### ⚠️ CRITICAL: Preferences Array Bounds
Many `Preferences` arrays only have 4 elements (indices 0-3):
- `shortcutStyle`, `appsToShow`, `showHiddenWindows`, `showWindowlessApps`
- `showFullscreenWindows`, `showMinimizedWindows`, `spacesToShow`, `screensToShow`, `windowOrder`

**When adding a new shortcut mode (index 4+), you MUST:**
1. Either extend all arrays with defaults, OR
2. Clamp the index: `let safeIndex = min(App.app.shortcutIndex, 3)`
3. Add guards: `guard !YourMode.isActive else { return }`

### Adding New Source Files
New `.swift` files must be added to `alt-tab-macos.xcodeproj/project.pbxproj`:
1. Generate a unique UUID (e.g., `D4XXXXXX...`)
2. Add `PBXBuildFile` entry
3. Add `PBXFileReference` entry
4. Add to `PBXGroup` children
5. Add to `PBXSourcesBuildPhase`

### Private macOS APIs
Located in `src/api-wrappers/private-apis/SkyLight.framework.swift`:
- `CGSSpaceID`, `CGSConnectionID` - Space and connection types
- `CGSCopySpaces`, `CGSManagedDisplayGetCurrentSpace` - Space queries
- `SLSMoveWindowsToManagedSpace` - Move windows between spaces
- Functions are loaded dynamically via `@_silgen_name`

## Code Conventions

### Preferences Declaration Pattern
```swift
// In MacroPreferences.swift
static var myNewPref = MacroPreference<Type>("keyName", defaultValue)

// In Preferences.swift
static var myNewPref: Type { MacroPreferences.myNewPref.value }
static func updateMyNewPref() { MacroPreferences.myNewPref.reload() }
```

### Per-Shortcut Preferences (arrays)
```swift
// 4-element array for shortcuts 0-3
static var myPref = MacroPreference<[MyType]>("myPref", [.default, .default, .default, .default])
```

### Event Handling
- Keyboard: `KeyboardEventsTestable.swift` → `handleKeyDown()`, `handleKeyUp()`
- Trackpad: `TrackpadEvents.swift`
- Spaces: `SpacesEvents.swift`

## Testing Tips

1. **Kill before relaunch**: Always `pkill -x "AltTab Debug"` before launching a new build
2. **Check logs immediately** after a crash to see the stack trace
3. **Array bounds crashes** show as "Index out of range" - search for `shortcutIndex` usages
4. **Debug bundle ID**: `com.lwouis.alt-tab-macos.debug` (set in `config/debug.xcconfig`)

## Common Pitfalls

1. **Don't forget Xcode project updates** - Adding Swift files without updating `project.pbxproj` causes build failures
2. **Private APIs may break** - They're undocumented and can change between macOS versions
3. **ThumbnailsView.highlight()** - Always check bounds before calling
4. **Spaces mode flag** - Use a static flag like `YourList.isInMode` to guard Windows-specific code paths
