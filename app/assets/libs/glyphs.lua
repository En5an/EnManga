-- Rotated text: draws pre-rendered glyph images (assets/glyphs) so text can follow the
-- screen orientation. The runtime's own Font.print can only draw upright text.
Glyphs = {}

local floor = math.floor
local byte = string.byte
local drawExt = Graphics.drawImageExtended

local DIR = "app0:assets/glyphs/"
local MAX_PAGES = 16

local fonts = {}      -- [key] = {size, asc, data, index = {[cp] = offset}, pages = {}}
local loadedPages = {} -- list of {font, n, img, used}
local useTick = 0

local function u16(s, i) local a, b = byte(s, i, i + 1) return a + b * 256 end
local function s8(v) return v >= 128 and v - 256 or v end

local function loadFont(key)
	local f = fonts[key]
	if f then return f end
	local data = ReadFile(DIR .. key .. ".bin")
	if not data then return nil end
	local count, npages, size, asc = u16(data, 1), u16(data, 3), byte(data, 5), byte(data, 6)
	local index = {}
	local off = 7
	for _ = 1, count do
		local a, b, c = byte(data, off, off + 2)
		index[a + b * 256 + c * 65536] = off
		off = off + 14
	end
	f = {key = key, size = size, asc = asc, data = data, index = index, pages = {}, npages = npages}
	fonts[key] = f
	return f
end

-- record: page, x, y, w, h, ox, top, adv (px)
local function rec(f, cp)
	local off = f.index[cp]
	if not off then return nil end
	local d = f.data
	local pg = byte(d, off + 3)
	return pg, u16(d, off + 4), u16(d, off + 6), byte(d, off + 8), byte(d, off + 9),
		s8(byte(d, off + 10)), s8(byte(d, off + 11)), u16(d, off + 12) / 8
end

local function pageImage(f, n)
	useTick = useTick + 1
	local p = f.pages[n]
	if p then
		p.used = useTick
		return p.img
	end
	local ok, img = pcall(Graphics.loadImage, DIR .. f.key .. "_" .. n .. ".png")
	if not ok or not img then return nil end
	Graphics.setImageFilters(img, FILTER_POINT, FILTER_POINT)
	p = {font = f, n = n, img = img, used = useTick}
	f.pages[n] = p
	loadedPages[#loadedPages + 1] = p
	if #loadedPages > MAX_PAGES then
		table.sort(loadedPages, function(a, b) return a.used < b.used end)
		local old = table.remove(loadedPages, 1)
		old.font.pages[old.n] = nil
		Graphics.freeImage(old.img)
	end
	return img
end

-- release all glyph pages (back in landscape, where FreeType text is used)
function Glyphs.freeAll()
	for _, p in ipairs(loadedPages) do
		p.font.pages[p.n] = nil
		Graphics.freeImage(p.img)
	end
	loadedPages = {}
end

local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local function codepoint(c)
	local a, b, d, e = byte(c, 1, 4)
	if a < 0x80 then return a
	elseif a < 0xE0 then return (a - 0xC0) * 64 + (b - 0x80)
	elseif a < 0xF0 then return ((a - 0xE0) * 64 + (b - 0x80)) * 64 + (d - 0x80)
	else return (((a - 0xF0) * 64 + (b - 0x80)) * 64 + (d - 0x80)) * 64 + (e - 0x80) end
end

local QMARK = 63
function Glyphs.width(key, s)
	local f = loadFont(key)
	if not f then return 0 end
	local w = 0
	for c in s:gmatch(UTF8) do
		local cp = codepoint(c)
		local _, _, _, _, _, _, _, adv = rec(f, cp)
		if not adv then
			local _, _, _, _, _, _, _, qa = rec(f, cp >= 0x2E80 and 0x25A1 or QMARK)
			adv = qa or f.size * 0.5
		end
		w = w + adv
	end
	return floor(w + 0.5)
end

function Glyphs.available()
	return loadFont("s") ~= nil
end

-- Laid-out strings are cached: {pg, gx, gy, w, h, dx, top, ...} per glyph (dx relative to x)
local layoutCache, layoutCount = {}, 0
local function layout(f, s)
	local ck = f.key .. s
	local L = layoutCache[ck]
	if L then return L end
	L = {}
	local pen = 0
	for c in s:gmatch(UTF8) do
		local cp = codepoint(c)
		local pg, gx, gy, w, h, ox, top, adv = rec(f, cp)
		if not pg then
			pg, gx, gy, w, h, ox, top, adv = rec(f, cp >= 0x2E80 and 0x25A1 or QMARK)
		end
		if pg and pg ~= 255 and w > 0 then
			local n = #L
			L[n + 1], L[n + 2], L[n + 3], L[n + 4], L[n + 5], L[n + 6], L[n + 7] = pg, gx, gy, w, h, pen + ox, top
		end
		pen = pen + (adv or f.size * 0.5)
	end
	if layoutCount > 600 then layoutCache, layoutCount = {}, 0 end
	layoutCache[ck] = L
	layoutCount = layoutCount + 1
	return L
end

-- Draw text whose logical top-left is (x, y). toPhys maps logical -> physical points,
-- rad is the screen rotation. Glyph quads are placed on whole pixels for sharp text.
function Glyphs.print(key, x, y, s, color, toPhys, rad, rot)
	local f = loadFont(key)
	if not f then return end
	local base = floor(y + f.size + 0.5)
	local L = layout(f, s)
	for i = 1, #L, 7 do
		local img = pageImage(f, L[i])
		if img then
			local w, h = L[i + 3], L[i + 4]
			local lx, ly = floor(x + L[i + 5] + 0.5), base - L[i + 6]
			local ax, ay = toPhys(lx, ly)
			local bx, by = toPhys(lx + w, ly + h)
			drawExt((ax + bx) / 2, (ay + by) / 2, img, L[i + 1], L[i + 2], w, h, rad, 1, 1, color)
		end
	end
end
