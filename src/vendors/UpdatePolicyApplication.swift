enum UpdatePolicyApplication {
    static func apply(automaticChecks: Bool, automaticInstallation: Bool, setChecks: (Bool) -> Void, setDownloads: (Bool) -> Void) {
        // Sparkle ignores download changes while scheduled checks disable automatic updates.
        if automaticChecks { setChecks(true) }
        setDownloads(automaticInstallation)
        if !automaticChecks { setChecks(false) }
    }
}
