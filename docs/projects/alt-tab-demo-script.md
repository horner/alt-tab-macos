# AltTab promotional demo — rough script

Target: 45 seconds, silent MP4, landscape. Use real Computer Use interactions with AltTab. Keep captions short and synchronized with the demonstrated action; leave room for a later voiceover.

| Time | Picture and action | On-screen caption |
| --- | --- | --- |
| 0–4 s | Open on AltTab's window switcher with both Project rows visible. Brief push-in on the selector. | Your work. One switch away. |
| 4–10 s | Open the Desktop switcher and choose a different populated Desktop. Show the destination settling. | Change desktops. Keep moving. |
| 10–16 s | Open the window switcher on the destination. Show its Desktop label and the windows available there. | Know where you are. |
| 16–23 s | Frame the two Project rows clearly. Select a Project in the first row and show its window list. | Find your project at a glance. |
| 23–30 s | Select a Project in the second row. Hold the changed window list long enough to read it. | Two rows. More within reach. |
| 30–36 s | Select one of that Project's windows and land in the app. | Pick a project. Get to work. |
| 36–42 s | Reopen AltTab and use Back to return to the previous Desktop. Verify the remembered context returns. | Jump straight back. |
| 42–45 s | End on a clean view of the two-row selector, with a small AltTab title. | AltTab · Stay in your flow. |

## Recording and edit notes

- Rehearse with two populated Desktops and two Projects whose windows visibly differ. At least one selected Project should be on row two.
- Choose demonstration windows suitable for a promotional video. Keep unrelated personal, customer, and account content out of the selected shots.
- Keep the Desktop switcher, Project selection, and window selection visually distinct.
- Show the actual UI and actual transitions. Trim automation pauses between takes; preserve the timing of the demonstrated app response.
- Put captions near the bottom, clear of the Project selector and window titles. Use one short phrase at a time, with subtle entrances.
- Prefer clean cuts and one or two restrained crops. Leave the two-row hero shot visible long enough to understand it.
- Record without microphone audio. Export a captioned H.264 MP4 and a clean version for later voiceover/editing, under `docs/projects/demo/`.
- Verify the exported duration is 30–60 seconds, both selector rows are legible, and the Desktop and Back transitions are visible.

This is the initial script draft. A 54-second rough cut was recorded on September 9, 2026, following the expanded request to include settings and menu-bar project navigation. The captioned video is `demo/alttab-rough-cut.mp4`; `demo/alttab-rough-clean.mp4` preserves the same edit without captions. The exact shot list is in `demo/edit.json`.

Video files stay local and are excluded from Git. With the two source recordings in `demo/`, run `python3 docs/projects/demo/render.py` from the repository root to rebuild the exports. Rendering requires macOS and ffmpeg with libx264 and drawtext support.
