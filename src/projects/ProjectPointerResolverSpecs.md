# ProjectPointerResolver

Project strip and popover hit areas are limited to both the control bounds and the visible region.
Non-clipping AppKit views can report a visible region larger than their own bounds.

## Test scenarios

- **testLillyClickDoesNotHitDesktopWithOversizedVisibleRect** — recorded coordinates from a physical Lilly click reject the Desktop button and accept Lilly despite oversized visible rectangles.
- **testClippedPopoverButtonOnlyAcceptsVisiblePart** — a partly scrolled-out button accepts only its visible portion.
- **testFullyClippedButtonDoesNotAcceptClick** — a fully clipped button is not a pointer target.
