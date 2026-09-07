import Cocoa

final class ProjectsMenu: NSObject {
    private static var desktopItem: NSMenuItem!
    private static var projectsItem: NSMenuItem!
    private static weak var focusedWindow: Window?

    static func install(in menu: NSMenu) {
        desktopItem = item(NSLocalizedString("Name this Desktop…", comment: "Desktop menu action"), #selector(nameDesktop))
        projectsItem = item(NSLocalizedString("Projects", comment: "Projects menu"), nil)
        projectsItem.submenu = NSMenu()
        projectsItem.isHidden = !Projects.isEnabled
        menu.addItem(desktopItem)
        menu.addItem(projectsItem)
    }

    static func refresh(_ menu: NSMenu) {
        guard desktopItem?.menu === menu else { return }
        focusedWindow = Windows.list.first {
            !$0.isWindowlessApp && $0.application.pid == Applications.frontmostPid && $0.application.focusedWindow === $0
        }
        desktopItem.isEnabled = currentDesktop != nil
        projectsItem.isHidden = !Projects.isEnabled
        guard Projects.isEnabled, let submenu = projectsItem.submenu else { return }
        submenu.autoenablesItems = false
        submenu.removeAllItems()
        let create = item(NSLocalizedString("New Project from this Window…", comment: "Projects menu action"), #selector(createProject))
        create.isEnabled = focusedWindow != nil && currentDesktop != nil
        submenu.addItem(create)
        addProjects(to: submenu, title: NSLocalizedString("Add this Window to Project", comment: "Projects submenu"),
            action: #selector(addWindow), enabled: focusedWindow != nil)
        addProjects(to: submenu, title: NSLocalizedString("Rename Project", comment: "Projects submenu"), action: #selector(renameProject))
        addProjects(to: submenu, title: NSLocalizedString("Delete Project", comment: "Projects submenu"), action: #selector(deleteProject))
    }

    private static var currentDesktop: Project? {
        Projects.spaces.first { $0.isCurrent }.map { Projects.forSpace(uuid: $0.uuid) }
    }

    private static func addProjects(to menu: NSMenu, title: String, action: Selector, enabled: Bool = true) {
        let parent = item(title, nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for project in Projects.list where project.isCustom {
            let child = item(project.resolvedName, action)
            child.representedObject = project.id
            child.isEnabled = enabled
            submenu.addItem(child)
        }
        parent.submenu = submenu
        parent.isEnabled = enabled && !submenu.items.isEmpty
        menu.addItem(parent)
    }

    private static func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private static func nameDesktop() {
        guard let project = currentDesktop else { return }
        ProjectNamePrompt.present(project, title: NSLocalizedString("Name this Desktop…", comment: "Desktop menu action"))
    }

    @objc private static func createProject() {
        guard Projects.isEnabled, let window = focusedWindow, Windows.list.contains(where: { $0 === window }),
              let desktop = currentDesktop, let project = Projects.createCustom(homeSpaceUuid: desktop.homeSpaceUuid) else { return }
        Projects.add(windowId: window.tracked.id, to: project)
        project.autoName = ProjectNameResolver.claim(name: nil, autoName: nil, appName: window.application.localizedName)
        guard !ProjectNamePrompt.present(project, title: NSLocalizedString("New Project from this Window…", comment: "Projects menu action")) else { return }
        Projects.delete(id: project.id)
    }

    @objc private static func addWindow(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let window = focusedWindow, Windows.list.contains(where: { $0 === window }),
              let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        Projects.add(windowId: window.tracked.id, to: project)
    }

    @objc private static func renameProject(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        ProjectNamePrompt.present(project, title: NSLocalizedString("Rename Project", comment: "Projects submenu"))
    }

    @objc private static func deleteProject(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let id = sender.representedObject as? String else { return }
        Projects.delete(id: id)
    }
}
