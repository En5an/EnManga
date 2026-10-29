# 10. Troubleshooting and FAQ

[← Documentation](README.md)

## My manga doesn't show up

- Check it's inside one of the scanned folders: `ux0:data/enmanga/import`, `ux0:manga`, `uma0:manga`, or one you added under Settings → Folders. A folder marked *missing* there doesn't exist on the card.
- Press △ → **Rescan library** after copying new files.
- Only `.cbz`, `.zip` and folders of images are read. `.cbr`, `.rar`, `.7z`, PDF and EPUB aren't supported.
- A folder containing only a cover image isn't a series.

## A page says WebP isn't supported

The Vita can't decode WebP. Convert the file with the [EnManga Converter](converter.md) and copy it over again.

## Volumes are grouped wrongly, or show strange names

- Loose files are grouped by the name before the volume number. Files that use different spellings of the series name (`One Piece v01`, `OnePiece v02`) become separate series. Put them in one folder named after the series.
- To see the original file names, turn off **Settings → Short names**.

## The series cover is wrong

Put an image called `cover.jpg` in the series folder and rescan. See [Series covers](getting-started.md#series-covers) for every name that's recognised. `cover.webp` is skipped.

## My cover.gif doesn't animate

- Check **Settings → Animated GIF covers** isn't *Off*. With *When selected*, only the cover you're on plays.
- The GIF may be too big. Animations over about 32 MB of frames (for example 60 frames at 1000×1400) stay still. Resize it to around 300×430 and keep it under about 40 frames.
- GIFs inside `.cbz` archives and one-frame GIFs never animate.
- Animations stop while you're reading and come back when you return to the library.

## Pages load slowly or the app runs out of memory

- Set **Texture quality** to *Balanced (≤1280 px)* for very large scans (above 3000 px).
- Lower **Pages to preload** to 1.
- Very large archives (hundreds of MB) take longer to open the first time.

## Auto-rotate shows portrait upside down, or the wrong half of the rear pad works

Use the two fallback switches under **Settings → Screen & controls**. See [If something is the wrong way round](orientation.md#if-something-is-the-wrong-way-round).

## Text in portrait shows □ boxes

Portrait text uses built-in glyph sheets, which cover Latin, kana, and roughly 6,000 common kanji and symbols. Rare characters show as □. Landscape mode uses the full font, so it shows everything.

## The app shows an error screen

EnManga writes the error to **`ux0:data/enmanga/log.txt`**. Press START to exit. Please [open an issue](../../../issues) with:
- the log file,
- what you were doing, and
- if possible, the name and layout of the file that caused it (not the file itself).

## Where is my data stored? How do I back it up or reset it?

Everything is in `ux0:data/enmanga/`:

| File | Contents |
|---|---|
| `settings.lua` | All settings and your presets |
| `library.lua` | Per-series data: categories, per-series settings, statistics, views |
| `progress.lua` | Reading progress, read marks and bookmarks |
| `scan_cache.lua` | Speeds up start-up; safe to delete |
| `import/` | A library folder you can copy manga into |

- **Back up:** copy the folder to your PC.
- **Reset everything:** delete the folder while EnManga is closed. Your manga files elsewhere are untouched.
- **Reset only reading data:** use Settings → Data.

## Does EnManga download manga?

No. EnManga reads only files that are already on your memory card. It has no online sources.

## Can I install it next to NOBORU?

Yes. EnManga has its own Title ID (`ENMG00001`) and its own data folder.

## Updating

Install the new `.vpk` over the old one in VitaShell. Your library, progress and settings are kept.

---
[← 9. EnManga Converter](converter.md) · Next: [11. Cover Animator →](cover-animator.md)
