import Cocoa
import Sparkle

class UserDefaultsEvents: NSObject {
    private static var policyObserver = UserDefaultsEvents()
    private static var isObserving = false
    private var synchronizationScheduled = false

    static func observe() {
        guard !isObserving, App.updaterController != nil else { return }
        isObserving = true
        // .initial delivers synchronously; startup has already applied the saved policy.
        UserDefaults.standard.addObserver(policyObserver, forKeyPath: "SUAutomaticallyUpdate", options: [.new], context: nil)
        UserDefaults.standard.addObserver(policyObserver, forKeyPath: "SUEnableAutomaticChecks", options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        handleEvent(keyPath)
    }

    private func handleEvent(_ keyPath: String?) {
        Logger.debug { "\(keyPath ?? "keyPath:nil") updatePolicy:\(Preferences.updatePolicy) policyLock:\(GeneralTab.policyLock)" }
        guard !GeneralTab.policyLock, !synchronizationScheduled else { return }
        synchronizationScheduled = true
        // Sparkle writes defaults before recalculating dependent flags; wait until its setters finish.
        DispatchQueue.main.async {
            self.synchronizationScheduled = false
            self.synchronizePolicy()
        }
    }

    private func synchronizePolicy() {
        guard !GeneralTab.policyLock, let updater = App.updaterController?.updater else { return }
        GeneralTab.policyLock = true
        defer { GeneralTab.policyLock = false }
        let policy = updatePolicy(updater)
        if policy == .autoInstall {
            updater.automaticallyChecksForUpdates = true
        }
        GeneralTab.updatesPolicyDropdown?.selectItem(at: Int(policy.indexAsString)!)
        Preferences.set("updatePolicy", policy.indexAsString, false)
    }

    private func updatePolicy(_ updater: SPUUpdater) -> UpdatePolicyPreference {
        if updater.automaticallyDownloadsUpdates { return .autoInstall }
        if updater.automaticallyChecksForUpdates { return .autoCheck }
        return .manual
    }
}
