# Thumbnail Caching Strategy

## Problem
Currently, AltTab refreshes all window thumbnails frequently, causing excessive ScreenCaptureKit API calls and system log noise. This is inefficient for windows that haven't changed.

## Proposed Solution
Cache screenshots with a configurable TTL (e.g., 5 minutes), with smart invalidation based on user focus patterns.

## Cache Rules

### Default Behavior
- Cache each window's thumbnail for **X minutes** (configurable, default: 5 min)
- Serve cached thumbnail if within TTL
- Skip ScreenCaptureKit calls for cached windows

### Exception 1: Focus-Out Refresh
**Trigger:** User leaves focus of a window (alt-tabs away, clicks another window, etc.)

**Action:** Immediately capture and cache that window's thumbnail

**Rationale:** The cache should always reflect "what I last saw" — the state of the window when I left it. This ensures the thumbnail is accurate and relevant.

**Implementation:**
- Hook into `NSWorkspace.didDeactivateApplicationNotification` or window focus change events
- On focus-out, capture the previously-focused window's thumbnail
- Update cache with new screenshot + timestamp

### Exception 2: Stale-on-Hover Refresh
**Trigger:** While alt-tab UI is open, user hovers/selects a window whose cache is older than **30 seconds**

**Action:** Refresh that specific window's thumbnail in the background

**Rationale:** If actively browsing through windows, slightly stale thumbnails (< 30s) are acceptable, but older ones should refresh on-demand to show current state.

**Implementation:**
- On hover/selection, check `cache_timestamp` for that window
- If `now - cache_timestamp > 30 seconds`, queue async refresh
- Update thumbnail in-place when capture completes

## Data Structure

```swift
struct CachedThumbnail {
    let image: CGImage
    let timestamp: Date
    let windowId: CGWindowID
}

class ThumbnailCache {
    private var cache: [CGWindowID: CachedThumbnail] = [:]

    /// Default cache TTL
    static let defaultTTL: TimeInterval = 5 * 60  // 5 minutes

    /// Threshold for on-hover refresh
    static let staleThreshold: TimeInterval = 30  // 30 seconds

    func get(_ windowId: CGWindowID) -> CGImage? {
        guard let cached = cache[windowId],
              Date().timeIntervalSince(cached.timestamp) < Self.defaultTTL else {
            return nil
        }
        return cached.image
    }

    func set(_ windowId: CGWindowID, image: CGImage) {
        cache[windowId] = CachedThumbnail(image: image, timestamp: Date(), windowId: windowId)
    }

    func isStale(_ windowId: CGWindowID) -> Bool {
        guard let cached = cache[windowId] else { return true }
        return Date().timeIntervalSince(cached.timestamp) > Self.staleThreshold
    }

    func invalidate(_ windowId: CGWindowID) {
        cache.removeValue(forKey: windowId)
    }

    func invalidateAll() {
        cache.removeAll()
    }
}
```

## Event Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Normal Operation                          │
├─────────────────────────────────────────────────────────────────┤
│  User working in Window A                                        │
│       │                                                          │
│       ▼                                                          │
│  User alt-tabs to Window B  ──► Capture Window A (Exception 1)   │
│       │                                                          │
│       ▼                                                          │
│  Alt-tab UI shows cached thumbnails                              │
│       │                                                          │
│       ▼                                                          │
│  User hovers Window C (cache age: 45s)                           │
│       │                                                          │
│       ▼                                                          │
│  Cache > 30s? ──► Yes ──► Async refresh Window C (Exception 2)   │
│       │                                                          │
│       ▼                                                          │
│  User selects Window B, UI closes                                │
│       │                                                          │
│       ▼                                                          │
│  User working in Window B                                        │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `thumbnailCacheTTL` | 300 (5 min) | Max age before cache is considered expired |
| `thumbnailStaleThreshold` | 30 | Age threshold for on-hover refresh |
| `enableThumbnailCaching` | true | Master toggle for caching feature |

## Benefits
1. **Reduced CPU/GPU usage** — fewer ScreenCaptureKit calls
2. **Less system log noise** — quieter debugging experience
3. **Faster UI response** — cached thumbnails display instantly
4. **Still accurate** — focus-out refresh ensures relevance

## Considerations
- Windows that update in background (videos, terminals) may show stale content
- Could add optional "live thumbnail" mode for specific apps if needed
- Cache should be cleared when display configuration changes (resolution, new monitor)
- Cache should evict entries for closed windows
