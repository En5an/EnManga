-- Accent colour picker: hue bar + saturation/brightness square, live preview of the UI.
-- App.push(ColorPicker, "#RRGGBB", onSave)
ColorPicker = {}
local P = {}
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local CELLS = 32           -- the square is drawn as CELLS x CELLS blocks
local SQ = 256             -- square size (px)
local HUE_W = 30
local SQ_X, SQ_Y, HUE_X, PREV_X, PREV_Y, PREV_W
local cellColors, cellHue = {}, nil
local hueColors = {}

local function layout()
	if UI.portrait() then
		SQ_X, SQ_Y = floor((SCREEN_W - (SQ + 24 + HUE_W)) / 2), 84
		HUE_X = SQ_X + SQ + 24
		PREV_X, PREV_Y, PREV_W = SQ_X, SQ_Y + SQ + 44, SQ + 24 + HUE_W
	else
		SQ_X, SQ_Y = 48, 78
		HUE_X = SQ_X + SQ + 22
		PREV_X, PREV_Y, PREV_W = HUE_X + HUE_W + 50, 78, SCREEN_W - (HUE_X + HUE_W + 50) - 40
	end
end
UI.onLayout(layout)

for i = 0, 63 do
	local r, g, b = HSVToRGB(i / 64 * 360, 1, 1)
	hueColors[i] = Color.new(r, g, b)
end

local function rebuildCells()
	if cellHue == P.h then return end
	cellHue = P.h
	for row = 0, CELLS - 1 do
		local v = 1 - (row + 0.5) / CELLS
		for col = 0, CELLS - 1 do
			local s = (col + 0.5) / CELLS
			local r, g, b = HSVToRGB(P.h, s, v)
			cellColors[row * CELLS + col] = Color.new(r, g, b)
		end
	end
end

local function current()
	return RGBToHex(HSVToRGB(P.h, P.s, P.v))
end

-- show the chosen colour across the whole UI while picking
local function preview()
	SetTheme(Settings.Theme, current())
end

local function setHex(hex)
	local r, g, b = HexToRGB(hex)
	if not r then return false end
	P.h, P.s, P.v = RGBToHSV(r, g, b)
	preview()
	return true
end

function ColorPicker:enter(hex, onSave)
	P = {orig = hex or Settings.Accent or DEFAULT_ACCENT, onSave = onSave, drag = nil}
	setHex(P.orig)
	cellHue = nil
end

local function finish(save)
	if save then
		local hex = current()
		if P.onSave then P.onSave(hex) end
	else
		SetTheme(Settings.Theme, Settings.Accent)
	end
	App.pop()
end

function ColorPicker:leave()
	-- make sure the theme matches what's saved (also when the screen is left another way)
	SetTheme(Settings.Theme, Settings.Accent)
end

function ColorPicker:input(dt)
	if UI.keyboardActive() then return end
	if Input.pressed(Input.BACK) then finish(false) return end
	if Input.pressed(Input.OK) or Input.pressed(SCE_CTRL_START) then finish(true) return end
	if Input.pressed(SCE_CTRL_TRIANGLE) then setHex(P.orig) UI.toast("Back to " .. P.orig) return end
	if Input.pressed(SCE_CTRL_SQUARE) then
		UI.prompt("Hex colour (e.g. F06E28)", current():sub(2), function(t)
			if t and not setHex(t) then UI.toast("Not a colour: " .. t) end
		end)
		return
	end
	local changed = false
	local step = (Input.held(SCE_CTRL_LEFT) > 600 or Input.held(SCE_CTRL_RIGHT) > 600 or Input.held(SCE_CTRL_UP) > 600 or Input.held(SCE_CTRL_DOWN) > 600) and 0.05 or 1 / CELLS
	if Input.rep(SCE_CTRL_LEFT) then P.s = max(0, P.s - step) changed = true end
	if Input.rep(SCE_CTRL_RIGHT) then P.s = min(1, P.s + step) changed = true end
	if Input.rep(SCE_CTRL_UP) then P.v = min(1, P.v + step) changed = true end
	if Input.rep(SCE_CTRL_DOWN) then P.v = max(0, P.v - step) changed = true end
	if Input.rep(SCE_CTRL_LTRIGGER) then P.h = (P.h - 5) % 360 changed = true end
	if Input.rep(SCE_CTRL_RTRIGGER) then P.h = (P.h + 5) % 360 changed = true end
	-- sticks: left = square, right = hue
	local lx, ly = Input.lx or 0, Input.ly or 0
	if lx ~= 0 or ly ~= 0 then
		P.s = math.clamp(P.s + lx * dt / 900, 0, 1)
		P.v = math.clamp(P.v - ly * dt / 900, 0, 1)
		changed = true
	end
	local ry = Input.ry or 0
	if ry ~= 0 then P.h = (P.h + ry * dt / 6) % 360 changed = true end
	-- touch
	local t = Input.touch
	if t then
		if not P.drag and Input.touchBegan then
			if t.x >= SQ_X - 10 and t.x < SQ_X + SQ + 10 and t.y >= SQ_Y - 10 and t.y < SQ_Y + SQ + 10 then P.drag = "sq"
			elseif t.x >= HUE_X - 14 and t.x < HUE_X + HUE_W + 14 and t.y >= SQ_Y - 10 and t.y < SQ_Y + SQ + 10 then P.drag = "hue" end
		end
		if P.drag == "sq" then
			P.s = math.clamp((t.x - SQ_X) / SQ, 0, 1)
			P.v = math.clamp(1 - (t.y - SQ_Y) / SQ, 0, 1)
			changed = true
		elseif P.drag == "hue" then
			P.h = math.clamp((t.y - SQ_Y) / SQ, 0, 0.999) * 360
			changed = true
		end
	else
		P.drag = nil
	end
	if Input.tap then
		local tx, ty = Input.tap.x, Input.tap.y
		if ty < 60 and tx < 70 then finish(false) return end
		if ty < 60 and tx > SCREEN_W - 150 then finish(true) return end
	end
	if changed then preview() end
end

function ColorPicker:update(dt) end

function ColorPicker:draw(dt)
	Screen.clear(C.bg)
	rebuildCells()
	-- header
	UI.icon("back", 22, 28, C.text)
	UI.text(FONT.l, 60, 14, "Accent colour", C.text)
	UI.rect(SCREEN_W - 140, 12, 120, 34, C.accent)
	UI.textCenter(FONT.b, SCREEN_W - 80, 18, "Save", C.onAccent)
	-- saturation / brightness square
	local cs = SQ / CELLS
	for row = 0, CELLS - 1 do
		for col = 0, CELLS - 1 do
			UI.rect(SQ_X + col * cs, SQ_Y + row * cs, cs, cs, cellColors[row * CELLS + col])
		end
	end
	local cx, cy = SQ_X + P.s * SQ, SQ_Y + (1 - P.v) * SQ
	UI.frame(cx - 8, cy - 8, 16, 16, P.v > 0.6 and C.black or C.white, 2)
	-- hue bar
	local hs = SQ / 64
	for i = 0, 63 do UI.rect(HUE_X, SQ_Y + i * hs, HUE_W, hs + 0.5, hueColors[i]) end
	local hy = SQ_Y + P.h / 360 * SQ
	UI.frame(HUE_X - 4, hy - 4, HUE_W + 8, 8, C.white, 2)
	-- preview of the UI with this accent
	local x, y, w = PREV_X, PREV_Y, PREV_W
	local hex = current()
	UI.rect(x, y, 64, 64, C.accent)
	UI.text(FONT.l, x + 80, y + 4, hex, C.text)
	UI.text(FONT.s, x + 80, y + 38, "Was " .. P.orig, C.sub)
	y = y + 88
	-- sample Continue button
	UI.rect(x, y, min(w, 300), 52, C.accent)
	UI.iconScaled("play", x + 26, y + 26, 22, C.onAccent)
	UI.text(FONT.b, x + 46, y + 6, "Continue", C.onAccent)
	UI.text(FONT.s, x + 46, y + 28, "Vol. 2 · p. 4 / 6", C.onAccent)
	y = y + 70
	-- badge, toggle, progress, header
	UI.rect(x, y, 30, 22, C.accent)
	UI.textCenter(FONT.s, x + 15, y + 1, "3", C.onAccent)
	UI.rect(x + 50, y + 1, 38, 20, C.accent)
	UI.rect(x + 50 + 20, y + 3, 16, 16, C.white)
	UI.text(FONT.s, x + 104, y + 1, "Next", C.accent)
	y = y + 40
	UI.rect(x, y, min(w, 300), 3, C.surface2)
	UI.rect(x, y, floor(min(w, 300) * 0.6), 3, C.accent)
	-- hints
	if UI.portrait() then
		UI.hints({{"dpad", "Colour"}, {"l", "Hue"}, {"square", "Hex"}, {"ok", "Save"}}, SCREEN_H - 30)
	else
		UI.hints({{"dpad", "Colour"}, {"l", "Hue"}, {"square", "Hex"}, {"triangle", "Reset"}, {"ok", "Save"}, {"back", "Cancel"}}, SCREEN_H - 30)
	end
end
