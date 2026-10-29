# Changelog

## Beta v1.0 — first public release

This release combines all the private test builds (1.0 to 1.4). Like the rest of the project, it was built with an AI assistant; see *About this project and AI use* in the README.

**Library and series**
- One cover per series. Open a series to browse its volumes as covers, with read marks, progress bars, a **Next** tag and a **Continue** button that returns to your last page.
- Series covers come from `cover.*`, `folder.*`, `poster.*` or an image named after the series. Otherwise the first volume's cover is used. Cover images are never treated as pages or volumes.
- Messy folders are understood: loose volumes are grouped by name, shelf folders are recognised, and long file names are shortened to *Vol. 2* / *Ch. 12* (Settings → Short names).
- Hovering a volume shows its full original name, file type, progress and bookmarks.
- Cover grid, compact grid or list, with sorting and filters, both in the library and inside each series. The choice is remembered per series.
- Categories, search, history, page bookmarks and reading statistics.
- Covers stay loaded for the whole session: a series you've opened once shows all its volume covers straight away next time, and a background rescan no longer reloads the library's covers. Only when reading needs the memory are the covers seen longest ago dropped.

**Reader**
- Paged RTL / LTR / vertical, webtoon and long strip, with auto-scroll.
- Fit screen / width / height, smart fit, original and stretch. Zoom start position, two-page spreads, splitting or rotating wide pages, auto-cropping borders, trimming margins, and remembering zoom per page.
- Page tone, colour filters, brightness and background colour. Tap zones with a custom 3×3 grid.
- **Brightness swipe:** slide a finger up or down along the screen edge while reading (right, left, both or off; follows the rotation).
- Reader presets (built-in and your own), per series or as the default, with an optional choice the first time you open a series.

**Screen and controls**
- Portrait mode for the whole app, in either direction.
- Auto-rotate using the motion sensor, a lock icon by the clock, and the last orientation remembered.
- Rear touchpad: tap for the next page, drag to scroll. In portrait only the top half of the pad responds.

**Appearance**
- Dark, Black and Light themes.
- **Accent colour:** 12 presets (Orange by default) or any custom colour, from a colour picker with a hue bar, a colour square, hex entry and a live preview.
- New logo: a glowing blue circle with EnManga in orange.
- **Animated GIF covers:** a `cover.gif` plays when selected (default), always, or never, with memory limits so big GIFs can't slow reading.

**Tools**
- `EnManga-Converter.html`: converts WebP manga to JPG on your computer.
- `EnManga-Cover-Animator.html`: turns a still cover into a small animated `cover.gif` that plays on the Vita. Whole-cover effects (shine, sparkle, breathe, glow, sway, drift), plus a **Character** mode where you mark parts with a box or a freehand lasso, or let **Auto-detect** find anime faces: eyes blink and glance, hair and cloth sway, the chest breathes, small things float. Any whole-cover effects can be layered on top.
