import Cocoa
import Sparkle

class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    /// Availability reported by Sparkle, shared with the feedback preflight.
    enum UpdateCheckResult {
        case updateAvailable(SUAppcastItem)
        case upToDate
    }

    /// Memory-only availability shared by checks during this launch.
    var cachedResult: UpdateCheckResult?

    /// One-shot listener for feedback UI; caching does not depend on a listener being present.
    var onNextCheckCompletion: ((UpdateCheckResult) -> Void)?

    func feedURLString(for updater: SPUUpdater) -> String? {
        return Endpoints.appcastUrl
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        #if PROJECTS_DISTRIBUTION
        return ["beta"]
        #else
        return []
        #endif
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        #if PROJECTS_DISTRIBUTION
        return []
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return [
            ["key": "version", "value": App.version],
            ["key": "macos", "value": "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"],
            ["key": "arch", "value": Sysctl.run("hw.machine")],
            ["key": "lang", "value": Locale.preferredLanguages.first ?? "unknown"],
            ["key": "tier", "value": LicenseManager.shared.state.appcastTier],
        ]
        #endif
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        store(.updateAvailable(item))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        store(.upToDate)
    }

    private func store(_ result: UpdateCheckResult) {
        cachedResult = result
        let cb = onNextCheckCompletion
        onNextCheckCompletion = nil
        cb?(result)
    }
}
