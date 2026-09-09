# AltTabProjects

Saved Projects and Desktop navigation in a dedicated AltTab app, distributed from the [horner fork](https://github.com/horner/alt-tab-macos).

[Download the friends beta](https://github.com/horner/alt-tab-macos/releases/tag/projects-v0.1.0), or install the prebuilt app with Homebrew:

```sh
brew tap horner/projects https://github.com/horner/alt-tab-macos.git
brew install --cask horner/projects/alttab-projects
```

If Homebrew asks you to trust the cask, run `brew trust --cask horner/projects/alttab-projects`, then retry the install. Updates use `brew upgrade --cask horner/projects/alttab-projects` after `brew update`.

The ZIP contains `AltTabProjects.app`, signed with Developer ID and notarized by Apple. Both Apple silicon and Intel architectures are included. Packaging and Gatekeeper checks were tested on macOS 26.6.2 / Apple silicon; behavior on other Macs is still being tested.

Quit other AltTab variants before opening AltTabProjects and grant Accessibility and Screen Recording access. This app uses a separate identity from AltTabDebug: export/import settings if desired, and activate Pro normally. The existing licensing behavior is retained.

Release source and packaging instructions live on [`projects-release`](https://github.com/horner/alt-tab-macos/tree/projects-release). This repository's default branch carries the Homebrew cask. Based on [AltTab](https://github.com/lwouis/alt-tab-macos); upstream information follows.

---

<div align="center">

<a href="https://alt-tab.app/"><img src="docs/readme/main.svg" alt="AltTab Pro — 7.4M downloads — 15K GitHub stars — Get AltTab"/></a>

<a href="https://jb.gg/OpenSource"><img src="docs/readme/sponsor.svg" alt="Sponsored by JetBrains" width="900"/></a>

</div>
