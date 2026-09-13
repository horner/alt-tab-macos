import Cocoa

final class ProjectAtticPrompt: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let entry: ProjectEntry
    private let desktopUuid: String
    private let pages: [ProjectAtticResolver.Page]
    private let alreadyOpen: Set<String>
    private var selected = Set<String>()
    private let bringWindows = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private init(_ entry: ProjectEntry, on desktopUuid: String) {
        self.entry = entry
        self.desktopUuid = desktopUuid
        pages = ProjectAtticResolver.pages(in: entry)
        alreadyOpen = Self.openPageKeys()
        super.init()
    }

    static func present(id: String, on desktopUuid: String, from parent: NSWindow?) {
        guard Projects.isEnabled, let entry = Projects.closedProjects.first(where: { $0.id == id }),
              let desktop = Projects.spaces.first(where: { $0.uuid == desktopUuid && $0.desktopNumber > 0 }) else { return }
        ProjectAtticPrompt(entry, on: desktopUuid).present(desktopNumber: desktop.desktopNumber, from: parent)
    }

    private func present(desktopNumber: Int, from parent: NSWindow?) {
        let name = ProjectNameResolver.resolved(name: entry.name, autoName: entry.autoName, desktopNumber: nil, projectNumber: 1)
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Restore %@ on Desktop %d?", comment: "Project Attic restoration"), name, desktopNumber)
        alert.informativeText = pages.isEmpty
            ? NSLocalizedString("Your Project will return to this Desktop with its name and history. Windows that have been closed must be reopened in their apps.", comment: "Project Attic restoration without browser pages")
            : NSLocalizedString("Your Project’s name and history are saved. Choose any browser pages to reopen below. Browsers decide whether pages open as tabs or windows; other app sessions must be reopened in those apps.", comment: "Project Attic restoration explanation")
        alert.accessoryView = accessory()
        alert.addButton(withTitle: NSLocalizedString("Restore Project", comment: "Restore from Project Attic"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: parent) { response in
            guard response == .alertFirstButtonReturn else { return }
            let move = self.bringWindows.state == .on
            DispatchQueue.main.async { self.restore(bringWindows: move, from: parent) }
        }
    }

    private func accessory() -> NSView {
        let count = Projects.atticWindows(entry).count
        bringWindows.title = String(format: NSLocalizedString("Bring open windows to this Desktop (%d)", comment: "Project Attic live windows option"), count)
        bringWindows.state = count > 0 ? .on : .off
        bringWindows.isEnabled = count > 0
        let content = NSStackView(views: [bringWindows])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        if pages.isEmpty {
            content.addArrangedSubview(NSTextField(wrappingLabelWithString: NSLocalizedString("No saved browser pages are available to reopen.", comment: "Project Attic empty recovery list")))
        } else {
            content.addArrangedSubview(NSTextField(labelWithString: NSLocalizedString("Reopen selected browser pages", comment: "Project Attic page selection")))
            content.addArrangedSubview(pageTable())
        }
        content.frame.size = NSSize(width: 520, height: pages.isEmpty ? 64 : 290)
        content.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return content
    }

    private func pageTable() -> NSView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        column.width = 500
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 48
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel(NSLocalizedString("Saved browser pages", comment: "Project Attic recovery table"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 228))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 520).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 228).isActive = true
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let page = pages[row]
        let identifier = NSUserInterfaceItemIdentifier("attic-page")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PageCell ?? PageCell()
        cell.identifier = identifier
        cell.choice.title = page.pattern.title.isEmpty ? page.pattern.url ?? "" : page.pattern.title
        cell.choice.tag = row
        cell.choice.target = self
        cell.choice.action = #selector(togglePage)
        cell.choice.state = selected.contains(page.key) ? .on : .off
        cell.choice.isEnabled = !alreadyOpen.contains(page.key)
        cell.choice.toolTip = page.pattern.url
        let browser = page.pattern.bundleIdentifier == "com.apple.Safari" ? "Safari" : "Chrome"
        let origin = page.wasOpen ? NSLocalizedString("Saved at close", comment: "Project Attic window snapshot") : NSLocalizedString("Older history", comment: "Project Attic historical page")
        let status = alreadyOpen.contains(page.key) ? NSLocalizedString("Already open", comment: "Project Attic duplicate page") : origin
        cell.detail.stringValue = "\(browser) · \(status) · \(page.pattern.url ?? "")"
        cell.detail.toolTip = page.pattern.url
        return cell
    }

    @objc private func togglePage(_ sender: NSButton) {
        guard pages.indices.contains(sender.tag) else { return }
        let key = pages[sender.tag].key
        if sender.state == .on { selected.insert(key) } else { selected.remove(key) }
    }

    private func restore(bringWindows: Bool, from parent: NSWindow?) {
        guard Projects.isEnabled, Projects.closedProjects.contains(entry) else { return }
        guard let project = Projects.reopen(id: entry.id, on: desktopUuid, bringWindows: bringWindows) else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("That Desktop is no longer available", comment: "Project Attic missing destination")
            alert.informativeText = NSLocalizedString("Your Project is still in the Project Attic. Restore it from another Desktop.", comment: "Project Attic destination recovery")
            ProjectPrompt.present(alert, from: parent) { _ in }
            return
        }
        let patterns = ProjectAtticResolver.pagesToOpen(in: entry, selected: selected, alreadyOpen: Self.openPageKeys())
        DispatchQueue.main.async { Self.openPages(patterns, for: project) }
    }

    private static func openPageKeys() -> Set<String> {
        Set(Windows.list.compactMap { window in
            guard let bundle = window.application.bundleIdentifier else { return nil }
            return ProjectAtticResolver.pageKey(ProjectWindowPattern(bundleIdentifier: bundle, title: window.title, url: ProjectBrowserURLs.url(for: window)))
        })
    }

    private static func openPages(_ patterns: [ProjectWindowPattern], for project: Project) {
        guard Projects.isEnabled, Projects.byId[project.id] === project, let bundle = patterns.first?.bundleIdentifier else { return }
        let open = openPageKeys()
        let urls = patterns.filter { $0.bundleIdentifier == bundle && ProjectAtticResolver.pageKey($0).map { !open.contains($0) } == true }
            .compactMap { $0.url.flatMap { URL(string: $0) } }
        let remaining = patterns.filter { $0.bundleIdentifier != bundle }
        guard !urls.isEmpty else { openPages(remaining, for: project); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            let opened = app.flatMap { try? NSWorkspace.shared.open(urls, withApplicationAt: $0, options: [], configuration: [:]) } != nil
            DispatchQueue.main.async {
                if !opened {
                    let browser = bundle == "com.apple.Safari" ? "Safari" : "Chrome"
                    ProjectRestoreNotice.showSummary(title: NSLocalizedString("Project restored; some pages could not be opened", comment: "Project Attic browser failure"), rows: [
                        .init(title: browser, detail: NSLocalizedString("Make sure the original browser is installed. Your saved pages remain in the Project’s Window History.", comment: "Project Attic recovery failure"))
                    ])
                }
                openPages(remaining, for: project)
            }
        }
    }

    private final class PageCell: NSView {
        let choice = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        let detail = NSTextField(labelWithString: "")

        init() {
            super.init(frame: .zero)
            choice.cell?.lineBreakMode = .byTruncatingTail
            choice.cell?.usesSingleLineMode = true
            detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detail.textColor = .secondaryLabelColor
            detail.lineBreakMode = .byTruncatingMiddle
            for view in [choice, detail] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
            NSLayoutConstraint.activate([
                choice.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                choice.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                choice.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 25),
                detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                detail.topAnchor.constraint(equalTo: choice.bottomAnchor, constant: 2)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
