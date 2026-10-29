"""Pre-render EnManga's font into PNG atlas pages + binary metrics, so rotated (portrait)
text can be drawn as images. Output: assets/glyphs/<key>_<n>.png and <key>.bin"""
import os, struct
from PIL import Image, ImageFont
from fontTools.ttLib import TTFont

B = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "assets")
OUT = f'{B}/glyphs'
FONTS = {'s': ('regular.ttf', 15), 'm': ('regular.ttf', 18), 'b': ('bold.ttf', 18), 'l': ('bold.ttf', 24)}
PAGE = 512

def charset(cmap):
    cps = []
    def add(rng):
        for c in rng:
            if c in cmap and c not in seen:
                seen.add(c); cps.append(c)
    seen = set()
    add(range(0x20, 0x7F)); add(range(0xA0, 0x100))
    add(range(0x2010, 0x2060)); add([0x2190, 0x2191, 0x2192, 0x2193, 0x2605, 0x2606, 0x2713, 0x2715, 0x25CB, 0x25CF, 0x25A1, 0x25A0, 0x25B3, 0x25BD, 0x266A, 0x2026])
    add(range(0x3000, 0x3040)); add(range(0x3040, 0x30A0)); add(range(0x30A0, 0x3100))
    add(range(0xFF01, 0xFF5F)); add(range(0xFF61, 0xFFA0))
    # JIS X 0208 via Shift-JIS: level 1 kanji first (most common), then level 2, then the rest
    def sjis(lead_rng):
        for lead in lead_rng:
            for trail in list(range(0x40, 0x7F)) + list(range(0x80, 0xFD)):
                try:
                    ch = bytes([lead, trail]).decode('cp932')
                except UnicodeDecodeError:
                    continue
                add([ord(ch)])
    sjis(range(0x88, 0xA0))          # level 1 kanji (0x889F-0x9872) + start of level 2
    sjis(range(0xE0, 0xEB))          # level 2 kanji
    sjis(range(0x81, 0x88))          # symbols, Greek, Cyrillic, box drawing
    sjis(range(0xED, 0xF0))          # NEC/IBM extensions (common in file names)
    return cps

def build(key, fname, size):
    path = f'{B}/fonts/{fname}'
    cmap = TTFont(path).getBestCmap()
    font = ImageFont.truetype(path, size)
    cps = charset(cmap)
    pages, page = [], Image.new('LA', (PAGE, PAGE), (255, 0))
    x = y = 1
    rowh = 0
    recs = []
    for cp in cps:
        ch = chr(cp)
        adv = font.getlength(ch)
        mask, (ox, oy) = font.getmask2(ch, mode='L')
        w, h = mask.size
        # oy is measured from the top of the ascender line; convert to "pixels above baseline"
        asc, _ = font.getmetrics()
        top = asc - oy
        if w == 0 or h == 0:
            recs.append((cp, 255, 0, 0, 0, 0, 0, 0, round(adv * 8)))
            continue
        if x + w + 1 > PAGE:
            x, y, rowh = 1, y + rowh + 1, 0
        if y + h + 1 > PAGE:
            pages.append(page); page = Image.new('LA', (PAGE, PAGE), (255, 0)); x = y = 1; rowh = 0
        glyph = Image.frombytes('L', (w, h), bytes(mask))
        page.paste(Image.merge('LA', (Image.new('L', (w, h), 255), glyph)), (x, y))
        recs.append((cp, len(pages), x, y, w, h, max(-128, min(127, ox)), max(-128, min(127, top)), round(adv * 8)))
        x += w + 1
        rowh = max(rowh, h)
    pages.append(page)
    for i, p in enumerate(pages):
        p.convert('RGBA').save(f'{OUT}/{key}_{i}.png', optimize=True)
    asc, desc = font.getmetrics()
    with open(f'{OUT}/{key}.bin', 'wb') as f:
        f.write(struct.pack('<HHBB', len(recs), len(pages), size, asc))
        for r in recs:
            cp, pg, gx, gy, w, h, ox, top, adv = r
            f.write(struct.pack('<I', cp)[:3] + struct.pack('<BHHBBbbH', pg, gx, gy, w, h, ox, top, adv))
    return len(recs), len(pages)

os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT): os.remove(f'{OUT}/{f}')
for key, (fname, size) in FONTS.items():
    n, p = build(key, fname, size)
    print(f'{key}: {n} glyphs, {p} pages')
tot = sum(os.path.getsize(f'{OUT}/{f}') for f in os.listdir(OUT))
print(f'total {tot/1e6:.2f} MB')
