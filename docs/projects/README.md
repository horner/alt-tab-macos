# Projects phase screenshots

Native captures of the running Debug app.

**M2 baseline Spaces panel**

![M2 baseline Spaces panel](screenshots/m2-spaces-baseline.jpg)

**M3 shared grid** — matching tile geometry, typography and highlight. Desktop 1/2 order changed after relaunch because visit history is session-local.

![M3 shared grid](screenshots/m3-shared-grid.jpg)


M3 settings and panel checks:

**Projects disabled** — only the enable switch is shown.

![Projects disabled](screenshots/m3-disabled-settings.jpg)

**Preset applied** — Option hold, Tab next, Shift previous, Focus release.

![Preset applied](screenshots/m3-preset-settings.jpg)

**Conflict warning** — a deliberate shared Option hold identifies Window shortcut 2; the full warning wraps.

![Conflict warning](screenshots/m3-shortcut-conflict.jpg)

**Project panel** — the current Desktop appears in the shared grid. This capture contains no custom Project; the live Research creation and cross-Space membership walkthrough remains pending.

![Project panel](screenshots/m3-desktop-panel.jpg)


These captures show actual Debug app UI, with no mock content or image edits.

**Phase 3 menu addition — requested behavior**

The annotated capture below shows the menu before this addition. The updated menu names the active Project and offers **Add this Window to Active Project** and **Add All Visible Windows to Active Project**. Under **Projects**, choose **New Project…** for an empty collection or **New Project from All Visible Windows…** to capture the current Desktop and activate the new Project after saving its name. Covered windows are included; minimized windows, hidden apps, other Desktops, and inactive tabs are excluded. This is a one-time capture; automatic membership remains outside phase 3.

![User-annotated menu before the phase 3 addition](screenshots/m3-menu-request.png)

**Saved Desktop names in the Spaces switcher**

Tiles now show their Desktop number alongside the saved name. User names take priority over automatic app names; unnamed Desktops retain their original labels. The live capture confirms the saved Desktop 2 name survives relaunch and appears without clipping.

![Spaces switcher showing saved Desktop names](screenshots/m3-named-desktops.jpg)

**Window details above the Desktop label**

The current layout uses the most recently focused eligible window's app icon and **app - window title** on the first line. A smaller second line shows **Desktop N** and any distinct explicit Desktop name. Long titles truncate within the grid; their full text remains in the tooltip and accessibility label. Empty Desktops keep a name and desktop-icon fallback.

![Spaces tiles with window titles and smaller Desktop subtitles](screenshots/m3-window-title-subtitles.jpg)

**Title-only refinement**

The primary line now contains only the window title. The app name appears with Desktop N in the smaller second line, beside any distinct custom Desktop name. The preceding screenshot documents the earlier app-and-title layout; a screenshot of this refinement is pending.

**Project menu navigation**

The active/no-active Project row now opens a submenu. It lists the active Project's windows and offers **Other Projects → Project → Activate Project / window**. Choosing a window selects its Project and focuses that window. **Use Desktop (No Project)** returns to normal window filtering. The bulk-add action names its destination: **Add all visible to: Research**. A live screenshot of this menu revision is pending.

**Main switcher context and named Desktop hierarchy**

The main window switcher now shows its Project or Desktop scope above the windows. Here the current Desktop is named “AltTab”.

![Main switcher showing its Desktop context](screenshots/m3-window-context.jpg)

Named Desktop tiles put the explicit name first, with smaller `D:N - window title` below. Unnamed tiles show just `D:N - window title`. Desktop 3 shows the shared `cloud (-zsh)` title.

![Desktop names above compact window details](screenshots/m3-desktop-name-first.jpg)

**Link a Desktop to a Project**

In **Name this Desktop…**, check **Link this Desktop to a Project**. Choose **Create a new Project** to use the Desktop name, or choose an existing Project. Each Desktop can link to one Project, and each Project to one Desktop. Linking enables Projects and includes existing and future windows on that Desktop, including hidden or minimized windows. You can still manually add windows from other Desktops. Unchecking the box removes the link and keeps the memberships. Links and memberships survive AltTab restarts.

This capture uses the production AppKit dialog with isolated sample data (“Research” and “Casework”); it does not modify your Desktops or Projects.

![Desktop naming dialog with an existing Project selected](screenshots/m3-desktop-project-link.jpg)
