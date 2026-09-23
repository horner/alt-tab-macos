import Cocoa
import WebKit

final class SnapshotViewerWindow: NSPanel, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private final class MessageHandler: NSObject, WKScriptMessageHandler {
        weak var owner: SnapshotViewerWindow?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            owner?.userContentController(controller, didReceive: message)
        }
    }

    private final class ContentView: NSView {
        var appearanceChanged: (() -> Void)?
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            appearanceChanged?()
        }
    }

    private static let queue = DispatchQueue(label: "com.alt-tab.snapshot-viewer", qos: .userInitiated)
    private static var shared: SnapshotViewerWindow?
    private let body = ContentView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let details = NSTextField(labelWithString: "")
    private var webView: WKWebView?
    private var readme: URL?
    private var documentURL: URL?
    private var temporaryDirectory: URL?
    private var generation = UUID()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func open(_ entry: ProjectSnapshotHistory.Entry) {
        MainThreadStall.step()
        let viewer = shared ?? SnapshotViewerWindow()
        shared = viewer
        viewer.present(entry)
    }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        title = NSLocalizedString("Snapshot", comment: "Snapshot viewer window")
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 620, height: 420)
        delegate = self
        if !setFrameAutosaveNameSafely("SnapshotViewerWindow") { center() }
        setupContent()
    }

    private func setupContent() {
        let root = NSView()
        contentView = root
        let finder = NSButton(title: NSLocalizedString("Show in Finder", comment: "Reveal saved snapshot"), target: self, action: #selector(showInFinder))
        let external = NSButton(title: NSLocalizedString("Open Externally", comment: "Open snapshot with default Markdown app"), target: self, action: #selector(openExternally))
        finder.bezelStyle = .rounded
        external.bezelStyle = .rounded
        details.font = .systemFont(ofSize: 12)
        details.textColor = .secondaryLabelColor
        details.lineBreakMode = .byTruncatingTail
        details.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [details, finder, external])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.alignment = .centerY
        [bar, body].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        status.alignment = .center
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(status)
        body.appearanceChanged = { [weak self] in self?.updateTheme() }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            bar.heightAnchor.constraint(equalToConstant: 30),
            body.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: body.centerYAnchor),
            status.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor, constant: -64),
        ])
    }

    private func present(_ entry: ProjectSnapshotHistory.Entry) {
        MainThreadStall.step()
        generation = UUID()
        let request = generation
        clearDocument()
        readme = entry.readme
        title = NSLocalizedString("Snapshot", comment: "Snapshot viewer window") + " — " + entry.readme.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        details.stringValue = entry.capturedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .medium) }
            ?? NSLocalizedString("Saved snapshot", comment: "Snapshot without capture date")
        details.toolTip = entry.readme.path
        showStatus(NSLocalizedString("Loading snapshot…", comment: "Snapshot viewer loading"))
        if isMiniaturized { deminiaturize(nil) }
        // Activating the app can switch to another Desktop containing one of its windows.
        makeKeyAndOrderFront(nil)
        // Commit the loading window before WebKit starts its process or files are read.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == request else { return }
            self.prepare(entry.readme, request: request)
        }
    }

    private func prepare(_ readme: URL, request: UUID) {
        Self.queue.async { [weak self] in
            let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("AltTabSnapshotViewer-" + request.uuidString, isDirectory: true)
            do {
                guard let templateURL = Bundle.main.url(forResource: "viewer", withExtension: "html") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let template = try String(contentsOf: templateURL, encoding: .utf8)
                let page = try SnapshotViewerDocument.prepare(readme: readme, template: template, directory: directory)
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { Self.remove(directory); return }
                    self.temporaryDirectory = directory
                    self.load(page)
                }
            } catch {
                Self.remove(directory)
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    self.showStatus(NSLocalizedString("Couldn’t open snapshot", comment: "Snapshot viewer failure") + "\n" + error.localizedDescription)
                    ProjectPersistence.refreshSnapshotHistory()
                }
            }
        }
    }

    private func load(_ page: URL) {
        MainThreadStall.step()
        documentURL = page
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let handler = MessageHandler()
        handler.owner = self
        configuration.userContentController.add(handler, name: "snapshotViewer")
        let view = WKWebView(frame: body.bounds, configuration: configuration)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.isHidden = true
        body.addSubview(view, positioned: .below, relativeTo: status)
        webView = view
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = webView, message.webView === view, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" {
            status.isHidden = true
            webView?.isHidden = false
            updateTheme()
        } else if type == "error" {
            showStatus(NSLocalizedString("Couldn’t display snapshot", comment: "Snapshot rendering failure") + "\n" + (body["message"] as? String ?? ""))
        }
    }

    private func updateTheme() {
        guard let webView else { return }
        let theme = body.effectiveAppearance.isDarkMode ? "dark" : "light"
        webView.evaluateJavaScript("document.documentElement.setAttribute('data-theme','\(theme)')", completionHandler: nil)
    }

    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard view === webView, let url = action.request.url else { decisionHandler(.cancel); return }
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false).map { components -> URL? in
            var components = components
            components.fragment = nil
            return components.url
        } ?? nil
        if page == documentURL, action.targetFrame?.isMainFrame == true { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        guard action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        Self.queue.async { NSWorkspace.shared.open(url) }
    }

    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        guard view === webView else { return }
        view.evaluateJavaScript("document.documentElement.getAttribute('data-viewer-state')") { [weak self, weak view] result, error in
            guard let self, let view, view === self.webView else { return }
            if error != nil || result as? String != "ready" {
                self.showStatus(NSLocalizedString("Couldn’t display snapshot. You can open the Markdown externally or reveal it in Finder.", comment: "Viewer startup failure"))
            }
        }
    }

    func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(view, error: error) }
    func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(view, error: error) }
    func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
        guard view === webView else { return }
        showStatus(NSLocalizedString("The snapshot viewer stopped. Open the snapshot from History to try again.", comment: "WebKit process terminated"))
    }

    private func failed(_ view: WKWebView, error: Error) {
        guard view === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        showStatus(NSLocalizedString("Couldn’t display snapshot", comment: "Snapshot rendering failure") + "\n" + error.localizedDescription)
    }

    private func showStatus(_ text: String) {
        status.stringValue = text
        status.isHidden = false
        webView?.isHidden = true
    }

    @objc private func showInFinder() {
        guard let readme else { return }
        Self.queue.async { NSWorkspace.shared.activateFileViewerSelecting([readme]) }
    }

    @objc private func openExternally() {
        guard let readme else { return }
        let request = generation
        Self.queue.async { [weak self] in
            guard NSWorkspace.shared.open(readme) else {
                DispatchQueue.main.async {
                    guard let self, self.generation == request else { return }
                    self.showStatus(NSLocalizedString("No application could open this Markdown file.", comment: "External snapshot open failure"))
                }
                return
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        generation = UUID()
        clearDocument()
        readme = nil
    }

    private func clearDocument() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        documentURL = nil
        if let directory = temporaryDirectory { Self.remove(directory) }
        temporaryDirectory = nil
    }

    private static func remove(_ directory: URL) {
        queue.async { try? FileManager.default.removeItem(at: directory) }
    }
}
