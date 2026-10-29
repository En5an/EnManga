-- UI foundation: fonts, theme, input, widgets, screen stack
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local fillRect = Graphics.fillRect
local fprint, fwidth = Font.print, Font.getTextWidth
local check = Controls.check

------------------------------------------------------------------------
-- Fonts. vita2d keeps glyphs in a fixed-size atlas; long CJK libraries can
-- overflow it and glyphs silently disappear. We count distinct glyphs per
-- font and reload the face before it fills up.
------------------------------------------------------------------------
Fonts = {}
local FONT_DEFS = {
	s = {"app0:assets/fonts/regular.ttf", 15},
	m = {"app0:assets/fonts/regular.ttf", 18},
	b = {"app0:assets/fonts/bold.ttf", 18},
	l = {"app0:assets/fonts/bold.ttf", 24},
	xl = {"app0:assets/fonts/bold.ttf", 34}
}
FONT = {}
local glyphs, glyphCount, seenStrings, seenCount, dirty, limits = {}, {}, {}, {}, {}, {}

local function loadFace(key)
	local def = FONT_DEFS[key]
	local h = Font.load(def[1])
	Font.setPixelSizes(h, def[2])
	FONT[key] = h
	glyphs[key], glyphCount[key], seenStrings[key], seenCount[key] = {}, 0, {}, 0
	limits[key] = floor(150000 / (def[2] * def[2] * 1.3))
end

for k in pairs(FONT_DEFS) do
	loadFace(k)
end

local keyOf = {}
local function refreshKeys()
	keyOf = {}
	for k, h in pairs(FONT) do keyOf[h] = k end
end
refreshKeys()

local function noteText(font, s)
	local key = keyOf[font]
	if not key then return end
	local seen = seenStrings[key]
	if seen[s] then return end
	seenCount[key] = seenCount[key] + 1
	if seenCount[key] > 3000 then
		seenStrings[key], seenCount[key] = {}, 0
		seen = seenStrings[key]
	end
	seen[s] = true
	local g = glyphs[key]
	for c in Utf8Chars(s) do
		if not g[c] then
			g[c] = true
			glyphCount[key] = glyphCount[key] + 1
		end
	end
	if glyphCount[key] > limits[key] then
		dirty[key] = true
	end
end

-- Call outside of the blend phase (start of frame)
function Fonts.maintain()
	local any = false
	for key in pairs(dirty) do
		pcall(Font.unload, FONT[key])
		loadFace(key)
		any = true
	end
	if any then
		dirty = {}
		refreshKeys()
	end
end

local widthCache, widthCount = {}, 0
function TextWidth(font, s)
	local key = keyOf[font] or font
	if UI and UI.rot ~= 0 then
		-- rotated text uses the pre-rendered glyphs, which have their own widths
		local gk = "@" .. tostring(key)
		local c = widthCache[gk]
		if not c then c = {} widthCache[gk] = c end
		local w = c[s]
		if not w then
			w = Glyphs.width(key, s)
			c[s] = w
		end
		return w
	end
	local c = widthCache[key]
	if not c then
		c = {}
		widthCache[key] = c
	end
	local w = c[s]
	if not w then
		w = fwidth(font, s)
		widthCount = widthCount + 1
		if widthCount > 5000 then
			widthCache, widthCount = {}, 0
			widthCache[key] = {}
		end
		widthCache[key][s] = w
	end
	return w
end

------------------------------------------------------------------------
-- Theme
------------------------------------------------------------------------
THEMES = {
	Dark = {
		bg = {17, 17, 19}, surface = {27, 27, 31}, surface2 = {40, 40, 46}, line = {52, 52, 58},
		text = {236, 236, 240}, sub = {146, 146, 156}, accent = {233, 75, 60}, onAccent = {255, 255, 255}, shade = {0, 0, 0}
	},
	Black = {
		bg = {0, 0, 0}, surface = {14, 14, 16}, surface2 = {30, 30, 34}, line = {44, 44, 48},
		text = {232, 232, 236}, sub = {130, 130, 140}, accent = {233, 75, 60}, onAccent = {255, 255, 255}, shade = {0, 0, 0}
	},
	Light = {
		bg = {246, 245, 242}, surface = {255, 255, 255}, surface2 = {232, 230, 226}, line = {214, 212, 206},
		text = {28, 28, 30}, sub = {112, 112, 118}, accent = {214, 58, 44}, onAccent = {255, 255, 255}, shade = {0, 0, 0}
	}
}
C = {}
local themeRGB = THEMES.Dark

-- Colour helpers (accent picker)
function HexToRGB(hex)
	if type(hex) ~= "string" then return nil end
	local h = hex:gsub("^#", ""):gsub("%s", "")
	if #h == 3 then h = h:gsub("(.)", "%1%1") end
	if not h:match("^%x%x%x%x%x%x$") then return nil end
	return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end
function RGBToHex(r, g, b)
	return string.format("#%02X%02X%02X", r, g, b)
end
-- h 0..360, s and v 0..1
function HSVToRGB(h, s, v)
	h = (h % 360) / 60
	local i = floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then r, g, b = v, t, p
	elseif i == 1 then r, g, b = q, v, p
	elseif i == 2 then r, g, b = p, v, t
	elseif i == 3 then r, g, b = p, q, v
	elseif i == 4 then r, g, b = t, p, v
	else r, g, b = v, p, q end
	return floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)
end
function RGBToHSV(r, g, b)
	r, g, b = r / 255, g / 255, b / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then h = 60 * (((g - b) / d) % 6)
		elseif mx == g then h = 60 * ((b - r) / d + 2)
		else h = 60 * ((r - g) / d + 4) end
	end
	return h, mx > 0 and d / mx or 0, mx
end
-- Text colour that reads well on top of a colour
local function contrastOn(r, g, b)
	local l = 0.299 * r + 0.587 * g + 0.114 * b
	if l > 170 then return {24, 24, 26} end
	return {255, 255, 255}
end

-- name: theme; accent: optional "#RRGGBB" overriding the theme's accent
function SetTheme(name, accent)
	local base = THEMES[name] or THEMES.Dark
	themeRGB = {}
	for k, v in pairs(base) do themeRGB[k] = v end
	local r, g, b = HexToRGB(accent)
	if r then
		themeRGB.accent = {r, g, b}
		themeRGB.onAccent = contrastOn(r, g, b)
	end
	for k, v in pairs(themeRGB) do
		C[k] = Color.new(v[1], v[2], v[3])
	end
	C.white = Color.new(255, 255, 255)
	C.black = Color.new(0, 0, 0)
	C.dim = Color.new(0, 0, 0, 150)
	C.dim2 = Color.new(0, 0, 0, 90)
	C.accentSoft = Color.new(themeRGB.accent[1], themeRGB.accent[2], themeRGB.accent[3], 60)
	C.selected = Color.new(themeRGB.text[1], themeRGB.text[2], themeRGB.text[3], 26)
end
DEFAULT_ACCENT = "#F06E28"
SetTheme("Dark", DEFAULT_ACCENT)

function ThemeAlpha(name, a)
	local v = themeRGB[name]
	return Color.new(v[1], v[2], v[3], math.clamp(floor(a), 0, 255))
end

------------------------------------------------------------------------
-- Orientation: everything below draws in *logical* coordinates. In portrait the logical
-- screen is 544 x 960 and is rotated onto the physical 960 x 544 display.
------------------------------------------------------------------------
UI = {rot = 0, rad = 0}
PHYS_W, PHYS_H = 960, 544
local ROT, RAD = 0, 0
local layoutListeners = {}

local function toPhys(lx, ly)
	if ROT == 0 then return lx, ly
	elseif ROT == 90 then return PHYS_W - ly, lx
	else return ly, PHYS_H - lx end
end
local function toLogical(px, py)
	if ROT == 0 then return px, py
	elseif ROT == 90 then return py, PHYS_W - px
	else return PHYS_H - py, px end
end
local function deltaLogical(dx, dy)
	if ROT == 0 then return dx, dy
	elseif ROT == 90 then return dy, -dx
	else return -dy, dx end
end
UI.toPhys, UI.toLogical, UI.deltaLogical = toPhys, toLogical, deltaLogical

function UI.portrait() return ROT ~= 0 end

-- fn() is called whenever the logical screen size changes (and once when registered)
function UI.onLayout(fn)
	layoutListeners[#layoutListeners + 1] = fn
	fn()
end

function UI.setRotation(rot)
	if rot ~= 0 and rot ~= 90 and rot ~= 270 then rot = 0 end
	if rot == ROT then return false end
	if rot ~= 0 and not Glyphs.available() then rot = 0 end
	ROT = rot
	RAD = rot == 90 and PI / 2 or (rot == 270 and -PI / 2 or 0)
	UI.rot, UI.rad = ROT, RAD
	if rot == 0 then SCREEN_W, SCREEN_H = PHYS_W, PHYS_H else SCREEN_W, SCREEN_H = PHYS_H, PHYS_W end
	for _, fn in ipairs(layoutListeners) do
		local ok, e = pcall(fn)
		if not ok then Log("layout: " .. tostring(e)) end
	end
	Input.blocked = math.max(Input.blocked or 0, 2)
	if rot == 0 and not DRAW_PHASE and Glyphs.freeAll then Glyphs.freeAll() end
	return true
end

function UI.rect(x, y, w, h, color)
	if w <= 0 or h <= 0 then return end
	if ROT == 0 then
		fillRect(x, x + w, y, y + h, color)
		return
	end
	local ax, ay = toPhys(x, y)
	local bx, by = toPhys(x + w, y + h)
	if ax > bx then ax, bx = bx, ax end
	if ay > by then ay, by = by, ay end
	fillRect(ax, bx, ay, by, color)
end

-- Image with its logical top-left at (x, y), unscaled
function UI.image(img, x, y, color)
	if ROT == 0 then
		if color then Graphics.drawImage(floor(x), floor(y), img, color) else Graphics.drawImage(floor(x), floor(y), img) end
		return
	end
	local w, h = Graphics.getImageWidth(img), Graphics.getImageHeight(img)
	local cx, cy = toPhys(floor(x) + w / 2, floor(y) + h / 2)
	Graphics.drawImageExtended(cx, cy, img, 0, 0, w, h, RAD, 1, 1, color or Color.new(255, 255, 255))
end

-- Region of an image centred on logical (cx, cy), scaled by (zx, zy), extra rotation rad
function UI.imageExt(cx, cy, img, sx, sy, sw, sh, zx, zy, color, rad)
	local px, py = toPhys(cx, cy)
	Graphics.drawImageExtended(px, py, img, sx, sy, sw, sh, RAD + (rad or 0), zx, zy, color or Color.new(255, 255, 255))
end

function UI.frame(x, y, w, h, color, t)
	t = t or 1
	UI.rect(x, y, w, t, color)
	UI.rect(x, y + h - t, w, t, color)
	UI.rect(x, y + t, t, h - 2 * t, color)
	UI.rect(x + w - t, y + t, t, h - 2 * t, color)
end

function UI.text(font, x, y, s, color)
	if not s or s == "" then return end
	if ROT ~= 0 then
		Glyphs.print(keyOf[font] or "m", x, y, s, color or C.text, toPhys, RAD, ROT)
		return
	end
	noteText(font, s)
	fprint(font, floor(x), floor(y), s, color or C.text)
end

local fitCache, fitCount = {}, 0
-- Truncate with an ellipsis so text never exceeds maxw
function UI.fit(font, s, maxw)
	if not s then return "" end
	if TextWidth(font, s) <= maxw then return s end
	local key = (keyOf[font] or "?") .. (UI.rot ~= 0 and "@" or "") .. "|" .. maxw .. "|" .. s
	local r = fitCache[key]
	if r then return r end
	local chars = {}
	for c in Utf8Chars(s) do chars[#chars + 1] = c end
	local lo, hi = 0, #chars
	while lo < hi do
		local mid = floor((lo + hi + 1) / 2)
		if TextWidth(font, table.concat(chars, "", 1, mid) .. "...") <= maxw then
			lo = mid
		else
			hi = mid - 1
		end
	end
	r = table.concat(chars, "", 1, lo):gsub("[%s%.,·]+$", "") .. "..."
	fitCount = fitCount + 1
	if fitCount > 3000 then fitCache, fitCount = {}, 0 end
	fitCache[key] = r
	return r
end

function UI.textFit(font, x, y, s, color, maxw)
	UI.text(font, x, y, UI.fit(font, s, maxw), color)
end

function UI.textRight(font, x, y, s, color)
	UI.text(font, x - TextWidth(font, s), y, s, color)
end

function UI.textCenter(font, x, y, s, color)
	UI.text(font, x - TextWidth(font, s) / 2, y, s, color)
end

-- Split into lines that fit maxw (word wrap, falls back to char wrap for CJK)
function UI.wrap(font, s, maxw, maxLines)
	local lines, cur = {}, ""
	for c in Utf8Chars(s) do
		local test = cur .. c
		if TextWidth(font, test) > maxw and cur ~= "" then
			local cut = cur:match("^(.*%S)%s+%S*$")
			if cut and c ~= " " and TextWidth(font, cut) > maxw * 0.5 then
				local rest = cur:sub(#cut + 1):gsub("^%s+", "")
				lines[#lines + 1] = cut
				cur = rest .. c
			else
				lines[#lines + 1] = cur
				cur = (c == " ") and "" or c
			end
			if maxLines and #lines >= maxLines then
				cur = ""
				lines[#lines] = UI.fit(font, lines[#lines] .. "...", maxw)
				return lines
			end
		else
			cur = test
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	return lines
end

-- Icons ---------------------------------------------------------------
ICON = {}
local function loadIcon(dir, name)
	local ok, img = pcall(Graphics.loadImage, "app0:assets/" .. dir .. "/" .. name .. ".png")
	if ok and img then
		Graphics.setImageFilters(img, FILTER_LINEAR, FILTER_LINEAR)
		return img
	end
	return nil
end
for _, n in ipairs({"back", "history", "options", "search", "left", "right", "refresh", "star", "tag", "checkbox", "checkbox_checked", "radio", "radio_checked", "sort-1-9", "sort-9-1", "menu", "grid", "folder", "bookmark", "bookmark_on", "filter", "rotate", "play", "check", "book", "zip", "list", "close", "add", "sun", "lock", "screenrot"}) do
	ICON[n] = loadIcon("icons", n)
end
BTN = {}
for _, n in ipairs({"circle", "cross", "square", "triangle", "l", "r", "start", "select"}) do
	BTN[n] = loadIcon("images", n .. "_button")
end
BTN.dpad = loadIcon("images", "dpad")

function UI.icon(name, x, y, color)
	local img = ICON[name]
	if img then
		UI.image(img, x, y, color or C.text)
	end
end

function UI.iconScaled(name, cx, cy, size, color)
	local img = ICON[name]
	if img then
		local s = size / 24
		UI.imageExt(cx, cy, img, 0, 0, 24, 24, s, s, color or C.text)
	end
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
Input = {lx = 0, ly = 0, rx = 0, ry = 0}
local pad, oldPad = 0, 0
local holdTime, nextRep = {}, {}
local REPEAT_DELAY, REPEAT_RATE = 360, 70
local ALL_BUTTONS = {SCE_CTRL_UP, SCE_CTRL_DOWN, SCE_CTRL_LEFT, SCE_CTRL_RIGHT, SCE_CTRL_CROSS, SCE_CTRL_CIRCLE, SCE_CTRL_SQUARE, SCE_CTRL_TRIANGLE, SCE_CTRL_LTRIGGER, SCE_CTRL_RTRIGGER, SCE_CTRL_START, SCE_CTRL_SELECT}
local repeatFlag = {}
local touchStart, touchMoved, touchStartTime = nil, false, 0
local lastTouch = nil
Input.OK = SCE_CTRL_CROSS
Input.BACK = SCE_CTRL_CIRCLE
Input.okGlyph, Input.backGlyph = "cross", "circle"
Input.blocked = 0 -- frames to ignore input (after screen switches)

function Input.setConfirm(mode)
	local enter = SCE_CTRL_CROSS
	if mode == "Circle" then
		enter = SCE_CTRL_CIRCLE
	elseif mode == "Cross" then
		enter = SCE_CTRL_CROSS
	else
		local ok, e = pcall(Controls.getEnterButton)
		if ok and e then enter = e end
	end
	if enter == SCE_CTRL_CIRCLE then
		Input.OK, Input.BACK, Input.okGlyph, Input.backGlyph = SCE_CTRL_CIRCLE, SCE_CTRL_CROSS, "circle", "cross"
	else
		Input.OK, Input.BACK, Input.okGlyph, Input.backGlyph = SCE_CTRL_CROSS, SCE_CTRL_CIRCLE, "cross", "circle"
	end
end

local function stick(v, dz)
	v = (v - 128) / 127
	if abs(v) < dz then return 0 end
	local s = v > 0 and 1 or -1
	return s * math.clamp((abs(v) - dz) / (1 - dz), 0, 1)
end

-- In portrait the D-pad turns with the screen: "up" is whichever button now points up
local DPAD_MAP = {
	[90] = {[SCE_CTRL_RIGHT] = SCE_CTRL_UP, [SCE_CTRL_LEFT] = SCE_CTRL_DOWN, [SCE_CTRL_UP] = SCE_CTRL_LEFT, [SCE_CTRL_DOWN] = SCE_CTRL_RIGHT},
	[270] = {[SCE_CTRL_LEFT] = SCE_CTRL_UP, [SCE_CTRL_RIGHT] = SCE_CTRL_DOWN, [SCE_CTRL_DOWN] = SCE_CTRL_LEFT, [SCE_CTRL_UP] = SCE_CTRL_RIGHT}
}
local DPAD_ALL = SCE_CTRL_UP + SCE_CTRL_DOWN + SCE_CTRL_LEFT + SCE_CTRL_RIGHT
local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot
local function readPad()
	local p = Controls.read()
	local m = DPAD_MAP[ROT]
	if not m then return p end
	local out = band(p, bnot(DPAD_ALL))
	for phys, logical in pairs(m) do
		if band(p, phys) ~= 0 then out = bor(out, logical) end
	end
	return out
end
Input.readPad = readPad

function Input.update(dt)
	oldPad = pad
	pad = readPad()
	-- key repeat
	for i = 1, #ALL_BUTTONS do
		local b = ALL_BUTTONS[i]
		repeatFlag[b] = false
		if check(pad, b) then
			if not check(oldPad, b) then
				holdTime[b] = 0
				nextRep[b] = REPEAT_DELAY
				repeatFlag[b] = true
			else
				holdTime[b] = (holdTime[b] or 0) + dt
				if holdTime[b] >= nextRep[b] then
					nextRep[b] = nextRep[b] + REPEAT_RATE
					repeatFlag[b] = true
				end
			end
		end
	end
	local lx, ly = Controls.readLeftAnalog()
	local rx, ry = Controls.readRightAnalog()
	Input.lx, Input.ly = deltaLogical(stick(lx or 128, 0.18), stick(ly or 128, 0.18))
	Input.rx, Input.ry = deltaLogical(stick(rx or 128, 0.18), stick(ry or 128, 0.18))
	-- touch (in logical coordinates)
	local x1, y1, x2, y2 = Controls.readTouch()
	if x1 then x1, y1 = toLogical(x1, y1) end
	if x2 then x2, y2 = toLogical(x2, y2) end
	Input.tap = nil
	Input.touchBegan = false
	Input.dx, Input.dy = 0, 0
	Input.released = nil
	if x1 then
		if not lastTouch then
			Input.touchBegan = true
			touchStart = {x = x1, y = y1}
			touchStartTime = 0
			touchMoved = false
		else
			Input.dx, Input.dy = x1 - lastTouch.x, y1 - lastTouch.y
			touchStartTime = touchStartTime + dt
		end
		if touchStart and (abs(x1 - touchStart.x) > 12 or abs(y1 - touchStart.y) > 12) then
			touchMoved = true
		end
		Input.touch = {x = x1, y = y1}
		Input.touch2 = x2 and {x = x2, y = y2} or nil
		if x2 then touchMoved = true end
		lastTouch = Input.touch
	else
		if lastTouch then
			Input.released = {x = lastTouch.x, y = lastTouch.y, moved = touchMoved, time = touchStartTime}
			if not touchMoved and touchStartTime < 450 then
				Input.tap = {x = lastTouch.x, y = lastTouch.y}
			end
		end
		Input.touch, Input.touch2 = nil, nil
		lastTouch = nil
	end
	Input.dragging = Input.touch ~= nil and touchMoved
	Input.touchStart = touchStart
	if Input.blocked > 0 then
		Input.blocked = Input.blocked - 1
		pad = readPad()
		oldPad = pad
		for i = 1, #ALL_BUTTONS do repeatFlag[ALL_BUTTONS[i]] = false end
		Input.tap, Input.released = nil, nil
	end
end

function Input.down(b) return check(pad, b) end
function Input.pressed(b) return check(pad, b) and not check(oldPad, b) end
function Input.up(b) return check(oldPad, b) and not check(pad, b) end
function Input.rep(b) return repeatFlag[b] == true end
function Input.held(b) return check(pad, b) and holdTime[b] or 0 end
function Input.any() return pad ~= 0 or Input.touch ~= nil end
function Input.consumeTouch()
	Input.tap, Input.released = nil, nil
end

-- Hints bar: { {"cross", "Open"}, {"triangle", "Menu"} }
local function hintWidth(item)
	local g, label = item[1], item[2]
	if g == "ok" then g = Input.okGlyph elseif g == "back" then g = Input.backGlyph end
	local w = TextWidth(FONT.s, label) + 18
	if BTN[g] then w = w + Graphics.getImageWidth(BTN[g]) + 6 end
	return w
end

function UI.hints(list, y, rightX, color, leftLimit)
	y = y or SCREEN_H - 30
	local x = rightX or (SCREEN_W - 16)
	color = color or C.sub
	-- keep the first (most important) hints that fit
	local avail = x - (leftLimit or 8)
	local total, n = 0, 0
	for i = 1, #list do
		local w = hintWidth(list[i])
		if total + w > avail + 18 then break end
		total, n = total + w, i
	end
	for i = n, 1, -1 do
		local g, label = list[i][1], list[i][2]
		if g == "ok" then g = Input.okGlyph elseif g == "back" then g = Input.backGlyph end
		local w = TextWidth(FONT.s, label)
		x = x - w
		UI.text(FONT.s, x, y + 1, label, color)
		local img = BTN[g]
		if img then
			local iw = Graphics.getImageWidth(img)
			x = x - iw - 6
			UI.image(img, x, y + 3, color)
		end
		x = x - 18
	end
end

------------------------------------------------------------------------
-- Toast
------------------------------------------------------------------------
local toastMsg, toastTime = nil, 0
function UI.toast(msg, ms)
	toastMsg, toastTime = msg, ms or 1800
end

function UI.drawToast(dt)
	if not toastMsg then return end
	toastTime = toastTime - dt
	if toastTime <= 0 then
		toastMsg = nil
		return
	end
	local a = math.clamp(toastTime / 250, 0, 1)
	local w = TextWidth(FONT.m, toastMsg) + 36
	local x, y = floor((SCREEN_W - w) / 2), SCREEN_H - 84
	UI.rect(x, y, w, 40, ThemeAlpha("surface2", 235 * a))
	UI.text(FONT.m, x + 18, y + 9, toastMsg, ThemeAlpha("text", 255 * a))
end

------------------------------------------------------------------------
-- Panel: scrollable option list (used by Sheet drawers and the Settings tab)
--  item kinds: header, action, choice (options), toggle, slider, info
------------------------------------------------------------------------
Panel = {}
local ROW_H = 46

local function selectable(it) return it and it.kind ~= "header" and it.kind ~= "info" and not it.hidden end

function Panel.init(def)
	def.sel = def.sel or 1
	def.scroll = def.scroll or 0
	while def.items[def.sel] and not selectable(def.items[def.sel]) do
		def.sel = def.sel + 1
	end
	if not def.items[def.sel] then def.sel = 1 end
	return def
end

local function itemValueText(it)
	if it.kind == "toggle" then
		return it.get() and "On" or "Off"
	elseif it.kind == "choice" then
		local v = it.get()
		if it.labels then
			local i = table.find(it.options, v)
			return i and it.labels[i] or tostring(v)
		end
		return tostring(v)
	elseif it.kind == "slider" then
		local v = it.get()
		return it.fmt and it.fmt(v) or tostring(v)
	elseif it.kind == "action" or it.kind == "info" then
		if it.value then
			if type(it.value) == "function" then return it.value() end
			return it.value
		end
	end
	return nil
end

local function changeItem(it, dir)
	if it.kind == "toggle" then
		it.set(not it.get())
	elseif it.kind == "choice" then
		it.set(table.cycle(it.options, it.get(), dir))
	elseif it.kind == "slider" then
		local v = it.get() + (it.step or 1) * dir
		it.set(math.clamp(v, it.min, it.max))
	end
end

local function visibleItems(def)
	local list = {}
	for i = 1, #def.items do
		if not def.items[i].hidden then list[#list + 1] = i end
	end
	return list
end

local function move(def, d)
	local items = def.items
	local i = def.sel
	for _ = 1, #items do
		i = i + d
		if i < 1 then i = #items elseif i > #items then i = 1 end
		if selectable(items[i]) then
			def.sel = i
			return
		end
	end
end

-- geo = {x, w, top, bottom}; onActivate(it) handles actions. Returns true if consumed BACK
function Panel.input(def, geo, activate)
	local items = def.items
	if Input.rep(SCE_CTRL_UP) then move(def, -1) end
	if Input.rep(SCE_CTRL_DOWN) then move(def, 1) end
	local it = items[def.sel]
	if it and selectable(it) then
		if Input.rep(SCE_CTRL_LEFT) then changeItem(it, -1) end
		if Input.rep(SCE_CTRL_RIGHT) then changeItem(it, 1) end
		if Input.pressed(Input.OK) then
			if it.kind == "action" then activate(it) else changeItem(it, 1) end
			return
		end
	end
	if Input.touch and Input.touch.x >= geo.x and Input.touch.x < geo.x + geo.w and Input.dragging then
		def.scroll = def.scroll - Input.dy
	end
	if Input.tap then
		local tx, ty = Input.tap.x, Input.tap.y
		if tx < geo.x or tx >= geo.x + geo.w or ty < geo.top or ty >= geo.bottom then
			return "outside"
		end
		local y = geo.top - def.scroll
		for _, idx in ipairs(visibleItems(def)) do
			if ty >= y and ty < y + ROW_H then
				local item = items[idx]
				if selectable(item) then
					def.sel = idx
					if item.kind == "choice" or item.kind == "slider" then
						changeItem(item, tx < geo.x + geo.w * 0.35 and -1 or 1)
					elseif item.kind == "action" then
						activate(item)
					else
						changeItem(item, 1)
					end
				end
				return
			end
			y = y + ROW_H
		end
	end
end

function Panel.draw(def, geo)
	local x0, W, top, bottom = geo.x, geo.w, geo.top, geo.bottom
	local vis = visibleItems(def)
	local selPos = 0
	for i, idx in ipairs(vis) do
		if idx == def.sel then selPos = i end
	end
	local viewH = bottom - top
	local contentH = #vis * ROW_H
	local selY = (selPos - 1) * ROW_H
	if not Input.dragging then
		if selY - def.scroll < 0 then def.scroll = selY end
		if selY + ROW_H - def.scroll > viewH then def.scroll = selY + ROW_H - viewH end
	end
	def.scroll = math.clamp(def.scroll, 0, math.max(0, contentH - viewH))
	local y = top - def.scroll
	for _, idx in ipairs(vis) do
		local it = def.items[idx]
		if y > top - ROW_H and y < bottom then
			if it.kind == "header" then
				UI.text(FONT.s, x0 + 24, y + 20, it.label, C.accent)
			else
				if idx == def.sel and def.focused ~= false then
					UI.rect(x0 + 8, y + 2, W - 16, ROW_H - 4, C.selected)
					UI.rect(x0 + 8, y + 2, 3, ROW_H - 4, C.accent)
				end
				local val = itemValueText(it)
				local color = it.danger and C.accent or (it.kind == "info" and C.sub or C.text)
				local avail = W - 56
				local extra = (it.kind == "choice" or it.kind == "slider") and 40 or (it.kind == "toggle" and 50 or 24)
				local wantVal = val and (it.kind == "toggle" and 0 or TextWidth(FONT.m, val)) or 0
				local labelW = TextWidth(FONT.m, it.label)
				-- the label keeps its full width unless the value would get less than 90px
				local labelMax = math.max(avail - extra - math.min(wantVal, 90), math.min(labelW, avail - extra - wantVal))
				if not val then labelMax = avail end
				local shownLabel = UI.fit(FONT.m, it.label, labelMax)
				UI.text(FONT.m, x0 + 24, y + 12, shownLabel, color)
				local valMax = avail - extra - TextWidth(FONT.m, shownLabel)
				if val then
					local vx = x0 + W - 24
					if it.kind == "choice" or it.kind == "slider" then
						local vtxt = UI.fit(FONT.m, val, math.max(60, valMax))
						UI.textRight(FONT.m, vx - 14, y + 12, vtxt, C.sub)
						if idx == def.sel then
							UI.text(FONT.m, vx - 6, y + 12, "›", C.sub)
							UI.text(FONT.m, vx - 28 - TextWidth(FONT.m, vtxt), y + 12, "‹", C.sub)
						end
					elseif it.kind == "toggle" then
						local on = it.get()
						local tw, th = 38, 20
						local tx, ty = vx - tw, y + 13
						UI.rect(tx, ty, tw, th, on and C.accent or C.surface2)
						UI.rect(on and (tx + tw - 18) or (tx + 2), ty + 2, 16, th - 4, on and C.white or C.sub)
					else
						if it.swatch then
							local sc = it.swatch()
							if sc then
								UI.rect(vx - 22, y + 13, 22, 20, sc)
								vx = vx - 32
							end
						end
						UI.textRight(FONT.m, vx, y + 12, UI.fit(FONT.m, val, math.max(50, valMax)), C.sub)
					end
				end
			end
		end
		y = y + ROW_H
	end
	if contentH > viewH then
		local barH = math.max(24, viewH * viewH / contentH)
		local barY = top + (viewH - barH) * (def.scroll / (contentH - viewH))
		UI.rect(x0 + W - 4, barY, 2, barH, C.line)
	end
end

function Panel.hints(def)
	local it = def.items[def.sel]
	if it and (it.kind == "choice" or it.kind == "slider") then
		return {"dpad", "Change"}
	elseif it and (it.kind == "action" or it.kind == "toggle") then
		return {"ok", "Select"}
	end
end

------------------------------------------------------------------------
-- Sheet: modal side drawer built on Panel
------------------------------------------------------------------------
Sheet = {stack = {}}
local SHEET_W = 440

function Sheet.open(def)
	Panel.init(def)
	def.anim = 0
	Sheet.stack[#Sheet.stack + 1] = def
	Input.blocked = 1
	return def
end

function Sheet.isOpen()
	return #Sheet.stack > 0
end

function Sheet.close()
	local def = table.remove(Sheet.stack)
	if def and def.onClose then def.onClose() end
end

function Sheet.closeAll()
	while #Sheet.stack > 0 do Sheet.close() end
end

local function sheetGeo()
	return {x = SCREEN_W - SHEET_W, w = SHEET_W, top = 64, bottom = SCREEN_H - 40}
end

function Sheet.input()
	local def = Sheet.stack[#Sheet.stack]
	if not def then return end
	if Input.pressed(Input.BACK) or Input.pressed(SCE_CTRL_TRIANGLE) or (def.closeWithStart and Input.pressed(SCE_CTRL_START)) then
		Sheet.close()
		return
	end
	local r = Panel.input(def, sheetGeo(), function(it)
		if not it.keepOpen then
			-- close this sheet (only if it is still on top) before running
			if Sheet.stack[#Sheet.stack] == def then Sheet.close() end
		end
		it.run()
	end)
	if r == "outside" and Input.tap and Input.tap.x < SCREEN_W - SHEET_W then
		Sheet.close()
	end
end

function Sheet.draw(dt)
	for si = 1, #Sheet.stack do
		local def = Sheet.stack[si]
		def.anim = math.min(1, def.anim + dt / 140)
		local e = Ease(def.anim)
		if si == #Sheet.stack then
			UI.rect(0, 0, SCREEN_W, SCREEN_H, Color.new(0, 0, 0, math.floor(140 * e)))
		end
		local x0 = math.floor(SCREEN_W - SHEET_W * e)
		UI.rect(x0, 0, SHEET_W, SCREEN_H, C.surface)
		UI.rect(x0, 0, 1, SCREEN_H, C.line)
		UI.textFit(FONT.l, x0 + 24, 18, def.title or "", C.text, SHEET_W - 48)
		Panel.draw(def, {x = x0, w = SHEET_W, top = 64, bottom = SCREEN_H - 40})
		UI.rect(x0, SCREEN_H - 40, SHEET_W, 40, C.surface)
		local hints = {{"back", "Close"}}
		local h = Panel.hints(def)
		if h then table.insert(hints, 1, h) end
		UI.hints(hints, SCREEN_H - 30, x0 + SHEET_W - 16)
	end
end

-- Read mark: accent tile with a check (used on series and volume covers)
function UI.readMark(x, y, size)
	size = size or 26
	UI.rect(x, y, size, size, C.accent)
	UI.iconScaled("check", x + size / 2, y + size / 2, size * 0.72, C.onAccent)
end

-- Small "continue here" tag
function UI.tag(x, y, text, bg, fg)
	local w = TextWidth(FONT.s, text) + 12
	UI.rect(x, y, w, 22, bg or C.accent)
	UI.text(FONT.s, x + 6, y + 1, text, fg or C.onAccent)
	return w
end

-- Confirmation prompt built on Sheet
function UI.confirm(title, yesLabel, onYes)
	Sheet.open {
		title = title,
		items = {
			{kind = "action", label = yesLabel or "Yes", danger = true, run = onYes},
			{kind = "action", label = "Cancel", run = function() end}
		}
	}
end

------------------------------------------------------------------------
-- Screen stack
------------------------------------------------------------------------
App = {stack = {}}

function App.push(screen, ...)
	local top = App.stack[#App.stack]
	if top and top.pause then top:pause() end
	App.stack[#App.stack + 1] = screen
	if screen.enter then screen:enter(...) end
	Input.blocked = 2
end

function App.pop()
	local s = table.remove(App.stack)
	if s and s.leave then s:leave() end
	local top = App.stack[#App.stack]
	if top and top.resume then top:resume() end
	Input.blocked = 2
end

function App.top()
	return App.stack[#App.stack]
end

-- Status: clock + battery (minimal, top-right)
local statusCache, statusTimer = "", 0
function UI.status(x, y, color)
	statusTimer = statusTimer - 16
	if statusTimer <= 0 then
		statusTimer = 1000
		local ok, h, m = pcall(System.getTime)
		local okb, bat = pcall(System.getBatteryPercentage)
		local s = ""
		if ok and h then s = string.format("%02d:%02d", h, m) end
		if okb and bat and bat >= 0 then s = s .. "   " .. bat .. "%" end
		statusCache = s
	end
	UI.textRight(FONT.s, x, y, statusCache, color or C.sub)
	-- rotation lock indicator (only for people who use auto-rotate)
	if Settings.RotateUsed and not Settings.AutoRotate then
		local w = TextWidth(FONT.s, statusCache)
		UI.iconScaled("lock", x - w - 14, y + 10, 16, color or C.sub)
	end
end
