-- Custom tap-zone editor: a 3x3 grid, each cell = prev / next / menu / none
TapGridEditor = {}
local E = {}
local floor = math.floor

local LABEL = {prev = "Previous", next = "Next", menu = "Menu", none = "Nothing"}
local TOP, BOTTOM = 58, SCREEN_H - 38
UI.onLayout(function() BOTTOM = SCREEN_H - 38 end)
local PRESETS = {
	{"prev", "menu", "next", "prev", "menu", "next", "prev", "menu", "next"},
	{"next", "menu", "prev", "next", "menu", "prev", "next", "menu", "prev"},
	{"menu", "menu", "menu", "prev", "menu", "next", "prev", "next", "next"},
	{"prev", "prev", "prev", "menu", "menu", "menu", "next", "next", "next"}
}
local PRESET_NAMES = {"Left = previous", "Left = next (manga)", "Bottom-heavy", "Rows: top previous"}

local function color(a)
	if a == "next" then return C.accent
	elseif a == "prev" then return Color.new(70, 120, 210)
	elseif a == "menu" then return C.surface2 end
	return C.bg
end

function TapGridEditor:enter()
	E = {grid = {}, sel = 5, preset = 0}
	local src = Settings.TapGrid or PRESETS[1]
	for i = 1, 9 do E.grid[i] = src[i] end
end

local function save()
	local g = {}
	for i = 1, 9 do g[i] = E.grid[i] end
	Store.set("TapGrid", g)
	Store.set("TapZones", "Custom")
end

local function cycle(i, d)
	E.grid[i] = table.cycle(OPT.TapAction, E.grid[i], d)
end

local function cellRect(i)
	local col, row = (i - 1) % 3, floor((i - 1) / 3)
	local w, h = SCREEN_W / 3, (BOTTOM - TOP) / 3
	return floor(col * w), floor(TOP + row * h), floor(w), floor(h)
end

function TapGridEditor:input()
	if Input.pressed(Input.BACK) or Input.pressed(SCE_CTRL_START) then
		save()
		UI.toast("Custom tap grid saved")
		App.pop()
		return
	end
	local col, row = (E.sel - 1) % 3, floor((E.sel - 1) / 3)
	if Input.rep(SCE_CTRL_UP) then row = math.max(0, row - 1) end
	if Input.rep(SCE_CTRL_DOWN) then row = math.min(2, row + 1) end
	if Input.rep(SCE_CTRL_LEFT) then col = math.max(0, col - 1) end
	if Input.rep(SCE_CTRL_RIGHT) then col = math.min(2, col + 1) end
	E.sel = row * 3 + col + 1
	if Input.pressed(Input.OK) then cycle(E.sel, 1) end
	if Input.pressed(SCE_CTRL_SQUARE) then cycle(E.sel, -1) end
	if Input.pressed(SCE_CTRL_TRIANGLE) then
		E.preset = E.preset % #PRESETS + 1
		for i = 1, 9 do E.grid[i] = PRESETS[E.preset][i] end
		UI.toast("Preset: " .. PRESET_NAMES[E.preset])
	end
	if Input.tap then
		local x, y = Input.tap.x, Input.tap.y
		if y < TOP then
			if x < 70 then
				save()
				App.pop()
			end
			return
		end
		for i = 1, 9 do
			local cx, cy, w, h = cellRect(i)
			if x >= cx and x < cx + w and y >= cy and y < cy + h then
				E.sel = i
				cycle(i, 1)
			end
		end
	end
end

function TapGridEditor:update() end

function TapGridEditor:draw()
	Screen.clear(C.bg)
	UI.icon("back", 20, 17, C.sub)
	UI.text(FONT.l, 60, 14, "Custom tap grid", C.text)
	if not UI.portrait() then UI.textRight(FONT.s, SCREEN_W - 16, 22, "Zones follow the reading orientation", C.sub) end
	for i = 1, 9 do
		local x, y, w, h = cellRect(i)
		local a = E.grid[i]
		UI.rect(x + 3, y + 3, w - 6, h - 6, color(a))
		if a == "none" then UI.frame(x + 3, y + 3, w - 6, h - 6, C.line, 1) end
		local tc = (a == "menu" or a == "none") and C.text or C.white
		UI.textCenter(FONT.b, x + w / 2, y + h / 2 - 12, LABEL[a], tc)
		if i == E.sel then UI.frame(x + 3, y + 3, w - 6, h - 6, C.text, 3) end
	end
	UI.hints({{"ok", "Change"}, {"square", "Reverse"}, {"triangle", "Preset"}, {"back", "Save"}}, SCREEN_H - 30)
end
