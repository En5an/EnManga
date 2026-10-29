-- Series details screen + folder picker
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

SeriesScreen = {}
local S = {}
-- Layout. Landscape: info column on the left, volumes on the right.
-- Portrait: info strip across the top, volumes below.
local ROW = 50
local PORTRAIT, LIST_X, TOP, BOTTOM, HEADER_Y, PANEL_H, GRID_X, GRID_W
local COV_X, COV_Y, COV_W, COV_H, TX, TY, TW, NAME_LINES
local BTN_X, BTN_Y, BTN_W, BTN_H
local function layout()
	PORTRAIT = UI.portrait()
	BOTTOM = SCREEN_H - 38
	if PORTRAIT then
		PANEL_H = 268
		HEADER_Y, TOP = PANEL_H + 12, PANEL_H + 56
		LIST_X, GRID_X, GRID_W = 12, 16, SCREEN_W - 28
		COV_X, COV_Y, COV_W, COV_H = 16, 56, 140, 199
		TX, TY, TW, NAME_LINES = 172, 58, SCREEN_W - 188, 3
		BTN_X, BTN_W, BTN_H = 172, SCREEN_W - 188, 60
		BTN_Y = COV_Y + COV_H - BTN_H
	else
		PANEL_H = 0
		HEADER_Y, TOP = 16, 66
		LIST_X = 300
		GRID_X, GRID_W = LIST_X, SCREEN_W - LIST_X - 12
		COV_W, COV_H = 150, 213
		COV_X, COV_Y = math.floor((LIST_X - 12 - COV_W) / 2), 56
		TX, TY, TW, NAME_LINES = 24, 280, LIST_X - 48, 4
		BTN_X, BTN_Y, BTN_W, BTN_H = 20, BOTTOM - 70, LIST_X - 52, 60
	end
end
UI.onLayout(layout)

local drawLeft

-- View options: per series (meta.view) with the global settings as defaults
local VIEW_KEYS = {view = "VolumeView", sort = "VolumeSort", desc = "ChapterSortDesc", filter = "VolumeFilter"}
local function V(k)
	local m = Store.meta[S.series.key]
	local v = m and m.view and m.view[k]
	if v == nil then return Settings[VIEW_KEYS[k]] end
	return v
end
local function setV(k, v)
	local m = Store.series(S.series.key)
	m.view = m.view or {}
	m.view[k] = v
	Store.mark("meta")
end

local function chapterOrder()
	local s = S.series
	local filter, sort = V("filter"), V("sort")
	local items = {}
	for i, ch in ipairs(s.chapters) do
		local p = Store.progress[ch.key]
		local read = p and p.r
		local started = p and not read and p.p and p.p > 1
		local ok = filter == "All" or (filter == "Unread" and not read) or (filter == "Read" and read)
			or (filter == "In progress" and started) or (filter == "Bookmarked" and p and (p.b or p.pb))
		if ok then
			local frac = (started and p.n and p.n > 0) and (p.p / p.n) or 0
			items[#items + 1] = {i = i, t = p and p.t or 0, read = read and 1 or 0, frac = frac, started = started and 1 or 0}
		end
	end
	local cmp
	if sort == "Last read" then
		cmp = function(a, b) if a.t ~= b.t then return a.t > b.t end return a.i < b.i end
	elseif sort == "Unread first" then
		cmp = function(a, b) if a.read ~= b.read then return a.read < b.read end return a.i < b.i end
	elseif sort == "Progress" then
		cmp = function(a, b)
			if a.started ~= b.started then return a.started > b.started end
			if a.frac ~= b.frac then return a.frac > b.frac end
			if a.read ~= b.read then return a.read < b.read end
			return a.i < b.i
		end
	else
		cmp = function(a, b) return a.i < b.i end
	end
	table.sort(items, cmp)
	if V("desc") then table.reverse(items) end
	local order = {}
	for k, it in ipairs(items) do order[k] = it.i end
	return order
end

local function reorder()
	local cur = S.order and S.sel > 0 and S.order[S.sel]
	S.order = chapterOrder()
	S.sel = 0
	if cur then
		for k, ci in ipairs(S.order) do if ci == cur then S.sel = k end end
	end
	S.scroll = 0
	S.snap = true
end

local function refreshStats()
	S.stats = Library.stats(S.series)
	S.order = chapterOrder()
	S.resumeLabel = Library.resumeLabel(S.series)
	if S.sel then S.sel = math.min(S.sel, #S.order) end
end

function SeriesScreen:enter(series)
	S = {series = series, sel = 0, scroll = 0, lastSel = 1}
	refreshStats()
	-- start with the resume row selected; position list near resume chapter
	local ci = Library.resumePoint(series)
	S.focusChapter = ci
end

function SeriesScreen:resume()
	if S.series then
		-- series may have been rescanned
		local fresh = Library.byKey[S.series.key]
		if fresh then S.series = fresh end
		refreshStats()
	end
end

local function selectedChapter()
	if S.sel == 0 then return nil end
	return S.series.chapters[S.order[S.sel]], S.order[S.sel]
end

local function chapterMenu(ch, ci)
	local p = Store.progress[ch.key]
	Sheet.open {title = ch.name, items = {
		{kind = "action", label = "Read from start", run = function() Reader.open(S.series, ci, 1) end},
		{kind = "action", label = (p and p.r) and "Mark as unread" or "Mark as read", run = function()
			Store.setRead(ch.key, not (p and p.r))
			refreshStats()
		end},
		{kind = "action", label = "Mark previous chapters as read", run = function()
			for i = 1, ci - 1 do Store.setRead(S.series.chapters[i].key, true) end
			refreshStats()
		end},
		{kind = "action", label = (p and p.b) and "Remove chapter bookmark" or "Bookmark chapter", run = function()
			Store.toggleBookmark(ch.key)
		end},
		{kind = "action", label = "Bookmarked pages", value = tostring(#Store.pageBookmarks(ch.key)), run = function()
			SeriesScreen.pageBookmarks(ch, ci)
		end}
	}}
end

function SeriesScreen.pageBookmarks(ch, ci)
	local items = {}
	local list = Store.pageBookmarks(ch.key)
	if #list == 0 then items[1] = {kind = "info", label = "No bookmarked pages"} end
	for _, pg in ipairs(list) do
		items[#items + 1] = {kind = "action", label = "Page " .. pg, value = "›", run = function() Reader.open(S.series, ci, pg) end}
	end
	Sheet.open {title = ch.name, items = items}
end

local function allBookmarks()
	local items = {}
	for ci, ch in ipairs(S.series.chapters) do
		local p = Store.progress[ch.key]
		if p and p.b then
			items[#items + 1] = {kind = "action", label = ch.name, value = "chapter", run = function()
				Reader.open(S.series, ci, (not p.r and p.p) or 1)
			end}
		end
		for _, pg in ipairs(Store.pageBookmarks(ch.key)) do
			items[#items + 1] = {kind = "action", label = ch.name, value = "p. " .. pg, run = function() Reader.open(S.series, ci, pg) end}
		end
	end
	if #items == 0 then
		items[1] = {kind = "info", label = "No bookmarks yet"}
		items[2] = {kind = "info", label = "In the reader: open the menu, press SELECT"}
	end
	Sheet.open {title = "Bookmarks", items = items}
end

local function seriesMenu()
	local s = S.series
	local st = Store.stats(s.key)
	Sheet.open {title = s.title, items = {
		{kind = "action", label = S.resumeLabel, run = function() Home.resume(s) end},
		{kind = "header", label = "View"},
		{kind = "choice", label = "Show as", options = OPT.VolumeView, labels = OPT.VolumeViewLabels, get = function() return V("view") end, set = function(v) setV("view", v) S.scroll = 0 end},
		{kind = "choice", label = "Sort by", options = OPT.VolumeSort, get = function() return V("sort") end, set = function(v) setV("sort", v) reorder() end},
		{kind = "toggle", label = "Reverse order", get = function() return V("desc") end, set = function(v) setV("desc", v) reorder() end},
		{kind = "choice", label = "Show", options = OPT.VolumeFilter, get = function() return V("filter") end, set = function(v) setV("filter", v) reorder() end},
		{kind = "action", label = "Use this view for all series", run = function()
			Store.set("VolumeView", V("view")) Store.set("VolumeSort", V("sort"))
			Store.set("ChapterSortDesc", V("desc")) Store.set("VolumeFilter", V("filter"))
			for _, m in pairs(Store.meta) do m.view = nil end
			Store.mark("meta")
			UI.toast("Default view updated")
		end},
		{kind = "header", label = "Series"},
		{kind = "action", label = "Bookmarks...", run = allBookmarks},
		{kind = "action", label = "Categories...", run = function() Home.categorySheet(s) end},
		{kind = "action", label = "Reader preset...", value = function()
			return Store.matchPreset(function(k) return Store.readerValue(s.key, k) end) or "Custom"
		end, keepOpen = true, run = function()
			Reader.presetPicker("Reader preset", Store.matchPreset(function(k) return Store.readerValue(s.key, k) end), function(p)
				Store.applyPresetToSeries(s.key, p)
				Sheet.closeAll()
				UI.toast(p.name .. " · " .. s.title)
			end)
		end},
		{kind = "action", label = "Reader settings for this series...", run = function() Reader.seriesSettingsSheet(s) end},
		{kind = "action", label = "Mark all as read", run = function()
			for _, ch in ipairs(s.chapters) do Store.setRead(ch.key, true) end
			refreshStats()
		end},
		{kind = "action", label = "Mark all as unread", run = function()
			for _, ch in ipairs(s.chapters) do Store.setRead(ch.key, false) end
			refreshStats()
		end},
		{kind = "action", label = "Remove from history", run = function() Store.removeHistory(s.key) end},
		{kind = "info", label = "Reading time", value = FormatDuration(st.t)},
		{kind = "info", label = "Pages read", value = tostring(st.p or 0)},
		{kind = "info", label = "Finished", value = tostring(st.c or 0)},
		{kind = "info", label = "Location", value = s.path}
	}}
end

local function listInput(dt)
	local n = #S.order
	if Input.pressed(Input.BACK) then App.pop() return end
	if Input.rep(SCE_CTRL_DOWN) then S.sel = min(n, S.sel + 1) end
	if Input.rep(SCE_CTRL_UP) then S.sel = max(0, S.sel - 1) end
	if Input.rep(SCE_CTRL_RIGHT) or Input.rep(SCE_CTRL_RTRIGGER) then S.sel = min(n, S.sel + 8) end
	if Input.rep(SCE_CTRL_LEFT) or Input.rep(SCE_CTRL_LTRIGGER) then S.sel = max(0, S.sel - 8) end
	local ch, ci = selectedChapter()
	if Input.pressed(Input.OK) then
		if not ch then
			Home.resume(S.series)
		else
			local p = Store.progress[ch.key]
			local page = (p and not p.r and p.p) or 1
			Reader.open(S.series, ci, page)
		end
		return
	end
	if Input.pressed(SCE_CTRL_START) then Home.resume(S.series) return end
	if Input.pressed(SCE_CTRL_TRIANGLE) then seriesMenu() return end
	if ch then
		if Input.pressed(SCE_CTRL_SQUARE) then
			local p = Store.progress[ch.key]
			Store.setRead(ch.key, not (p and p.r))
			refreshStats()
		end
		if Input.pressed(SCE_CTRL_SELECT) then chapterMenu(ch, ci) return end
	end
	if Input.touch and Input.dragging and (PORTRAIT and Input.touch.y > TOP or (not PORTRAIT and Input.touch.x > LIST_X)) then
		S.scroll = S.scroll - Input.dy
		S.dragging = true
	end
	if Input.tap then
		local tx, ty = Input.tap.x, Input.tap.y
		if tx < 60 and ty < 60 then App.pop() return end
		if (PORTRAIT or tx > LIST_X) and ty > TOP and ty < BOTTOM then
			local idx = floor((ty - TOP + S.scroll) / ROW)
			if idx >= 0 and idx <= n then
				S.sel = idx
				local c, i = selectedChapter()
				if not c then
					Home.resume(S.series)
				else
					local p = Store.progress[c.key]
					Reader.open(S.series, i, (p and not p.r and p.p) or 1)
				end
			end
		elseif not PORTRAIT and tx < LIST_X and ty > 380 and ty < 440 then
			Home.resume(S.series)
		end
	end
end

local function listUpdate(dt)
	if S.focusChapter then
		-- place selection on resume chapter on first frame
		for i, idx in ipairs(S.order) do
			if idx == S.focusChapter then S.sel = (S.focusChapter > 1) and i or 0 end
		end
		S.focusChapter = nil
	end
	local n = #S.order
	local viewH = BOTTOM - TOP
	if not Input.dragging then
		local y1 = S.sel * ROW
		if y1 < S.scroll + ROW then S.scroll = S.scroll + (max(0, y1 - ROW) - S.scroll) * min(1, dt / 60) end
		if y1 + 2 * ROW > S.scroll + viewH then S.scroll = S.scroll + (y1 + 2 * ROW - viewH - S.scroll) * min(1, dt / 60) end
	end
	S.scroll = math.clamp(S.scroll, 0, max(0, (n + 1) * ROW - viewH))
end

local function listHeader(s)
	if PORTRAIT then
		UI.rect(0, PANEL_H, SCREEN_W, TOP - PANEL_H, C.bg)
		UI.text(FONT.l, LIST_X + 12, HEADER_Y, Library.unitName(s):gsub("^%d+ ", ""):gsub("^%l", string.upper), C.text)
	else
		UI.rect(LIST_X - 12, 0, SCREEN_W - LIST_X + 12, TOP, C.bg)
		UI.text(FONT.l, LIST_X + 12, 18, UI.fit(FONT.l, s.title, SCREEN_W - LIST_X - 140), C.text)
		UI.status(SCREEN_W - 16, 22)
	end
end

local function listDraw(dt)
	local s = S.series
	local viewTop, viewBottom = TOP, BOTTOM
	local n = #S.order
	for i = 0, n do
		local ry = floor(viewTop + i * ROW - S.scroll)
		if ry > viewTop - ROW and ry < viewBottom then
			local selected = i == S.sel
			if selected then
				UI.rect(LIST_X, ry, SCREEN_W - LIST_X - 12, ROW - 4, C.selected)
				UI.rect(LIST_X, ry, 3, ROW - 4, C.accent)
			end
			if i == 0 then
				UI.icon("play", LIST_X + 14, ry + 12, C.accent)
				UI.textFit(FONT.b, LIST_X + 48, ry + 13, S.resumeLabel, C.accent, SCREEN_W - LIST_X - 80)
			else
				local ci = S.order[i]
				local ch = s.chapters[ci]
				local p = Store.progress[ch.key]
				local read = p and p.r
				local right = ""
				if read then
					right = ""
					UI.readMark(SCREEN_W - 52, ry + 11, 22)
				elseif p and p.p and p.p > 1 then
					right = "p. " .. p.p .. (p.n and (" / " .. p.n) or "")
				elseif ch.n then
					right = ch.n .. " p."
				end
				if p and p.pb then
					local n = 0
					for _ in pairs(p.pb) do n = n + 1 end
					right = "★" .. n .. (right ~= "" and ("  " .. right) or "")
				end
				local rw = TextWidth(FONT.s, right)
				local tx = LIST_X + 16
				if p and (p.b or p.pb) then
					UI.icon("bookmark_on", tx - 2, ry + 11, C.accent)
					tx = tx + 26
				end
				UI.textFit(FONT.m, tx, ry + 12, ch.name, read and C.sub or C.text, SCREEN_W - tx - rw - 60)
				UI.textRight(FONT.s, SCREEN_W - 32, ry + 15, right, read and C.sub or C.accent)
			end
			UI.rect(LIST_X + 12, ry + ROW - 4, SCREEN_W - LIST_X - 36, 1, C.line)
		end
	end
	listHeader(s)
	drawLeft(false)
	UI.rect(LIST_X - 12, BOTTOM, SCREEN_W - LIST_X + 12, SCREEN_H - BOTTOM, C.bg)
	local hints = {{"ok", "Read"}, {"square", "Read/unread"}, {"select", "Chapter"}, {"triangle", "Series"}, {"back", "Back"}}
	if S.sel == 0 then hints = {{"ok", "Continue"}, {"triangle", "Series"}, {"back", "Back"}} end
	UI.hints(hints, SCREEN_H - 30)
end

-- Volume cover entities (kept outside the chapter tables so saving them never loops)
local volCovers = setmetatable({}, {__mode = "k"})
local function volEntity(ch)
	local e = volCovers[ch]
	if not e then
		e = {key = "vol:" .. ch.key, title = ch.name, cover = ch.cover, chapters = {ch}, volume = true}
		volCovers[ch] = e
	end
	return e
end

local GAP_NORMAL, GAP = 14, 14
local GRID_COLS, CELL_W, COVER_H, CELL_H, COMPACT
local function applyGeom()
	COMPACT = V("view") == "Compact"
	if PORTRAIT then GRID_COLS = COMPACT and 4 or 3 else GRID_COLS = COMPACT and 7 or 5 end
	local gap = COMPACT and 10 or GAP_NORMAL
	CELL_W = floor((GRID_W - (GRID_COLS - 1) * gap) / GRID_COLS)
	COVER_H = floor(CELL_W * 1.42)
	CELL_H = COVER_H + (COMPACT and 30 or 50)
	GAP = gap
end

local function openChapter(ci)
	local ch = S.series.chapters[ci]
	local p = Store.progress[ch.key]
	Reader.open(S.series, ci, (p and not p.r and p.p) or 1)
end

local function toggleRead(ci)
	local ch = S.series.chapters[ci]
	local p = Store.progress[ch.key]
	Store.setRead(ch.key, not (p and p.r))
	refreshStats()
end

drawLeft = function(withButton)
	local s, st = S.series, S.stats
	if PORTRAIT then
		UI.rect(0, 0, SCREEN_W, PANEL_H, C.surface)
	else
		UI.rect(0, 0, LIST_X - 12, SCREEN_H, C.surface)
	end
	UI.icon("back", 20, 20, C.sub)
	local textW = TW
	local ci = S.sel > 0 and S.order and S.order[S.sel]
	local ch = ci and s.chapters[ci]
	if ch then
		-- preview of the volume you are on: its cover, short name, full name and status
		UI.textFit(FONT.m, 52, 18, s.title, C.sub, (PORTRAIT and SCREEN_W - 200 or LIST_X - 12 - 64))
		local p = Store.progress[ch.key]
		Covers.draw(volEntity(ch), COV_X, COV_Y, COV_W, COV_H, 0, nil, true)
		if p and p.r then UI.readMark(COV_X + COV_W - 30, COV_Y + 4, 24) end
		local y = TY
		UI.textFit(FONT.b, TX, y, ch.name, C.text, textW)
		y = y + 26
		local full = ch.raw or ch.name
		if full ~= ch.name then
			local lines = UI.wrap(FONT.s, full, textW, NAME_LINES)
			for _, l in ipairs(lines) do
				UI.text(FONT.s, TX, y, l, C.sub)
				y = y + 19
			end
		end
		y = y + 4
		local status, color
		if p and p.r then
			status, color = "Read", C.accent
		elseif p and p.p and p.n and p.p > 1 then
			status, color = "Page " .. p.p .. " of " .. p.n, C.accent
		else
			local n = ch.n or (p and p.n)
			status, color = n and (n .. " pages · not started") or "Not started", C.sub
		end
		local kind = ch.kind == "zip" and (Ext(ch.path):upper() .. " · ") or "Folder · "
		UI.textFit(FONT.s, TX, y, kind .. status, color, textW)
		if p and p.pb then
			local k = 0
			for _ in pairs(p.pb) do k = k + 1 end
			UI.text(FONT.s, TX, y + 20, "★ " .. k .. (k == 1 and " bookmark" or " bookmarks"), C.sub)
		end
	else
		Covers.draw(s, COV_X, COV_Y, COV_W, COV_H, 0, nil, true)
		if st.total > 0 and st.unread == 0 then UI.readMark(COV_X + COV_W - 30, COV_Y + 4, 24) end
		local lines = UI.wrap(FONT.b, s.title, textW, 2)
		local y = TY
		for _, l in ipairs(lines) do
			UI.text(FONT.b, TX, y, l, C.text)
			y = y + 24
		end
		y = y + 2
		local sub = Library.unitName(s) .. " · " .. (st.total > 0 and st.unread == 0 and "completed" or (st.read .. " read"))
		UI.text(FONT.s, TX, y, sub, st.unread == 0 and C.accent or C.sub)
		local rs = Store.stats(s.key)
		if (rs.t or 0) > 0 or (rs.p or 0) > 0 then
			y = y + 20
			UI.text(FONT.s, TX, y, "Read " .. FormatDuration(rs.t) .. " · " .. (rs.p or 0) .. " pages", C.sub)
		end
		if Store.hasSeriesPrefs(s.key) and (not withButton or y + 20 < BTN_Y - 18) then
			UI.text(FONT.s, TX, y + 20, "Custom reader settings", C.sub)
		end
	end
	if PORTRAIT then UI.status(SCREEN_W - 16, 22) end
	if withButton then
		local ci, _, started, name, detail = Library.resumeInfo(s)
		local focused = S.sel == 0
		UI.rect(BTN_X, BTN_Y, BTN_W, BTN_H, focused and C.accent or C.surface2)
		local fg = focused and C.onAccent or C.text
		UI.iconScaled("play", BTN_X + 26, BTN_Y + BTN_H / 2, 22, focused and C.onAccent or C.accent)
		UI.text(FONT.b, BTN_X + 46, BTN_Y + 8, started and "Continue" or "Start reading", fg)
		local right = 0
		if detail then
			local pg = detail:gsub("^Page ", "p. "):gsub(" of ", " / ")
			UI.textRight(FONT.s, BTN_X + BTN_W - 10, BTN_Y + 11, pg, focused and C.onAccent or C.accent)
			right = TextWidth(FONT.s, pg) + 14
		end
		UI.textFit(FONT.s, BTN_X + 46, BTN_Y + 34, name, focused and C.onAccent or C.sub, BTN_W - 56)
	end
end

------------------------------------------------------------------------
-- Cover grid
------------------------------------------------------------------------
local function gridInput(dt)
	applyGeom()
	local n = #S.order
	if Input.pressed(Input.BACK) then App.pop() return end
	if Input.pressed(SCE_CTRL_START) then Home.resume(S.series) return end
	if Input.pressed(SCE_CTRL_TRIANGLE) then seriesMenu() return end
	if S.sel == 0 then
		if Input.pressed(Input.OK) then Home.resume(S.series) return end
		if (Input.rep(SCE_CTRL_RIGHT) or Input.rep(SCE_CTRL_DOWN) or Input.rep(SCE_CTRL_UP)) and n > 0 then
			S.sel = math.clamp(S.lastSel or 1, 1, n)
		end
	else
		local col = (S.sel - 1) % GRID_COLS
		if Input.rep(SCE_CTRL_RIGHT) and col < GRID_COLS - 1 and S.sel < n then S.sel = S.sel + 1
		elseif Input.rep(SCE_CTRL_LEFT) then
			if col == 0 then
				S.lastSel = S.sel
				S.sel = 0
				return
			end
			S.sel = S.sel - 1
		end
		if Input.rep(SCE_CTRL_DOWN) then
			if S.sel + GRID_COLS <= n then
				S.sel = S.sel + GRID_COLS
			elseif floor((S.sel - 1) / GRID_COLS) < floor((n - 1) / GRID_COLS) then
				S.sel = n
			end
		end
		if Input.rep(SCE_CTRL_UP) and S.sel - GRID_COLS >= 1 then S.sel = S.sel - GRID_COLS end
		if Input.rep(SCE_CTRL_RTRIGGER) then S.sel = min(n, S.sel + GRID_COLS * 2) end
		if Input.rep(SCE_CTRL_LTRIGGER) then S.sel = max(1, S.sel - GRID_COLS * 2) end
		local ci = S.order[S.sel]
		if Input.pressed(Input.OK) then openChapter(ci) return end
		if Input.pressed(SCE_CTRL_SQUARE) then toggleRead(ci) end
		if Input.pressed(SCE_CTRL_SELECT) then chapterMenu(S.series.chapters[ci], ci) return end
	end
	if Input.touch and Input.dragging and Input.touch.y > TOP and Input.touch.x > GRID_X - 12 then
		S.scroll = S.scroll - Input.dy
	end
	if Input.tap then
		local tx, ty = Input.tap.x, Input.tap.y
		if tx < 60 and ty < 56 then App.pop() return end
		if ty < 44 and tx > SCREEN_W - 150 then Orient.toggleLock() return end
		if tx >= BTN_X and tx < BTN_X + BTN_W and ty >= BTN_Y and ty < BTN_Y + BTN_H then
			S.sel = 0
			Home.resume(S.series)
			return
		end
		if tx >= GRID_X and ty > TOP and ty < BOTTOM then
			local col = floor((tx - GRID_X) / (CELL_W + GAP))
			local row = floor((ty - TOP - 4 + S.scroll) / CELL_H)
			local idx = row * GRID_COLS + col + 1
			if col >= 0 and col < GRID_COLS and idx >= 1 and idx <= n then
				S.sel = idx
				openChapter(S.order[idx])
			end
		end
	end
end

-- Preload the first volume covers of a series (used while hovering it in the library)
function SeriesScreen.prefetch(series, n)
	local count = #series.chapters
	local desc = Settings.ChapterSortDesc
	for k = 1, math.min(n, count) do
		local ch = series.chapters[desc and (count - k + 1) or k]
		Covers.prefetch(volEntity(ch), 60 + k)
	end
end

local function gridUpdate(dt)
	applyGeom()
	-- preload one row above and two rows below what is visible
	do
		local n = #S.order
		local firstRow = max(0, floor(S.scroll / CELL_H) - 1)
		local lastRow = floor((S.scroll + BOTTOM - TOP) / CELL_H) + 3
		for i = firstRow * GRID_COLS + 1, math.min(n, (lastRow + 1) * GRID_COLS) do
			local ch = S.series.chapters[S.order[i]]
			if ch then Covers.prefetch(volEntity(ch), 20 + abs(floor((i - 1) / GRID_COLS) - firstRow)) end
		end
	end
	-- then, while nothing else is loading, the rest of the series (so scrolling and coming
	-- back later is instant); capped so a huge series doesn't push everything else out
	if not Loader.busy() then
		for i = 1, math.min(#S.order, 80) do
			local ch = S.series.chapters[S.order[i]]
			if ch then Covers.prefetch(volEntity(ch), 120 + i) end
		end
	end
	local n = #S.order
	if S.focusChapter then
		for i, idx in ipairs(S.order) do
			if idx == S.focusChapter then S.lastSel = i end
		end
		S.focusChapter = nil
		S.snap = true
	end
	local viewH = BOTTOM - TOP
	local rows = math.ceil(n / GRID_COLS)
	local maxScroll = max(0, rows * CELL_H + 8 - viewH)
	local target = S.sel > 0 and S.sel or (S.lastSel or 1)
	if not Input.dragging then
		local row = floor((target - 1) / GRID_COLS)
		local y1 = row * CELL_H
		local goal = S.scroll
		if y1 < S.scroll then goal = y1 end
		if y1 + CELL_H > S.scroll + viewH then goal = y1 + CELL_H - viewH end
		if S.snap then
			S.scroll = goal
			S.snap = false
		else
			S.scroll = S.scroll + (goal - S.scroll) * min(1, dt / 70)
		end
	end
	S.scroll = math.clamp(S.scroll, 0, maxScroll)
end

local function gridDraw(dt)
	applyGeom()
	local s = S.series
	local n = #S.order
	local resumeCi, _, started = Library.resumeInfo(s)
	local first = max(0, floor(S.scroll / CELL_H))
	local last = floor((S.scroll + BOTTOM - TOP) / CELL_H) + 1
	local focusRow = floor(((S.sel > 0 and S.sel or (S.lastSel or 1)) - 1) / GRID_COLS)
	for row = first, last do
		for col = 0, GRID_COLS - 1 do
			local i = row * GRID_COLS + col + 1
			if i > n then break end
			local ci = S.order[i]
			local ch = s.chapters[ci]
			local x = GRID_X + col * (CELL_W + GAP)
			local y = floor(TOP + 4 + row * CELL_H - S.scroll)
			local p = Store.progress[ch.key]
			local read = p and p.r
			Covers.draw(volEntity(ch), x, y, CELL_W, COVER_H, abs(row - focusRow) + 1, nil, i == S.sel)
			if read then
				UI.rect(x, y, CELL_W, COVER_H, Color.new(0, 0, 0, 110))
				UI.readMark(x + CELL_W - 28, y + 4, 24)
			elseif p and p.p and p.n and p.n > 0 and p.p > 1 then
				UI.rect(x, y + COVER_H - 4, CELL_W, 4, Color.new(0, 0, 0, 140))
				UI.rect(x, y + COVER_H - 4, floor(CELL_W * math.min(1, p.p / p.n)), 4, C.accent)
			end
			if started and ci == resumeCi and not read and not COMPACT then
				UI.tag(x + 4, y + 4, "Next", C.accent, C.onAccent)
			elseif started and ci == resumeCi and not read then
				UI.rect(x, y, CELL_W, 4, C.accent)
			end
			local selected = i == S.sel
			if selected then UI.frame(x - 4, y - 4, CELL_W + 8, COVER_H + 8, C.accent, 3) end
			UI.textFit(FONT.s, x, y + COVER_H + 6, ch.name, (selected and C.text) or (read and C.sub) or C.text, CELL_W)
			local info
			if read then info = "Read"
			elseif p and p.p and p.n and p.p > 1 then info = "Page " .. p.p .. " / " .. p.n
			elseif ch.n then info = ch.n .. " pages"
			else info = "" end
			if p and p.pb then
				local k = 0
				for _ in pairs(p.pb) do k = k + 1 end
				info = "★" .. k .. (info ~= "" and ("  " .. info) or "")
			end
			if not COMPACT then
				UI.textFit(FONT.s, x, y + COVER_H + 25, info, (read and C.sub) or (p and p.p and p.p > 1 and C.accent) or C.sub, CELL_W)
			end
		end
	end
	if n == 0 then
		UI.textCenter(FONT.m, GRID_X + GRID_W / 2, 220, "No " .. V("filter"):lower() .. " " .. (Library.unitName(s):match("(%a+)$") or "volumes"), C.sub)
		UI.textCenter(FONT.s, GRID_X + GRID_W / 2, 250, "Press △ to change the filter", C.sub)
	end
	-- fade the partly hidden next row into the hints bar
	for k = 0, 5 do
		UI.rect(GRID_X - 12, BOTTOM - 24 + k * 4, SCREEN_W - GRID_X + 12, 4, ThemeAlpha("bg", 60 + k * 39))
	end
	-- header over the grid: "Volumes 12" (title is already in the info panel)
	if PORTRAIT then
		UI.rect(0, 0, SCREEN_W, TOP, C.bg)
	else
		UI.rect(GRID_X - 12, 0, SCREEN_W - GRID_X + 12, TOP, C.bg)
	end
	local unit = Library.unitName(s):gsub("^%d+ ", "")
	unit = unit:sub(1, 1):upper() .. unit:sub(2)
	UI.text(FONT.l, GRID_X, HEADER_Y, unit, C.text)
	local cnt = S.stats.read .. " of " .. S.stats.total .. " read"
	if V("filter") ~= "All" then cnt = cnt .. " · showing " .. V("filter"):lower() .. " (" .. n .. ")" end
	if V("sort") ~= "Number" then cnt = cnt .. " · " .. V("sort"):lower() end
	UI.textFit(FONT.m, GRID_X + TextWidth(FONT.l, unit) + 14, HEADER_Y + 5, cnt, C.sub, GRID_W - TextWidth(FONT.l, unit) - 20 - (PORTRAIT and 0 or 140))
	if not PORTRAIT then UI.status(SCREEN_W - 16, 22) end
	drawLeft(true)
	local rows = math.ceil(n / GRID_COLS)
	local contentH = rows * CELL_H + 8
	local viewH = BOTTOM - TOP
	if contentH > viewH then
		local bh = max(30, viewH * viewH / contentH)
		UI.rect(SCREEN_W - 5, TOP + (viewH - bh) * S.scroll / (contentH - viewH), 3, bh, C.line)
	end
	UI.rect(GRID_X - 12, BOTTOM, SCREEN_W - GRID_X + 12, SCREEN_H - BOTTOM, C.bg)
	local hints
	if S.sel == 0 then
		hints = {{"ok", started and "Continue" or "Start"}, {"dpad", "Volumes"}, {"triangle", "Series"}, {"back", "Back"}}
	else
		hints = {{"ok", "Read"}, {"square", "Read / unread"}, {"select", "More"}, {"triangle", "Series"}, {"back", "Back"}}
	end
	UI.hints(hints, SCREEN_H - 30)
end

function SeriesScreen:input(dt)
	if V("view") == "List" then listInput(dt) else gridInput(dt) end
end

function SeriesScreen:update(dt)
	if V("view") == "List" then listUpdate(dt) else gridUpdate(dt) end
end

function SeriesScreen:draw(dt)
	Screen.clear(C.bg)
	if V("view") == "List" then listDraw(dt) else gridDraw(dt) end
end

------------------------------------------------------------------------
-- Folder picker: browse devices/folders and choose a library folder
------------------------------------------------------------------------
FolderPicker = {}
local P = {}
local DEVICES = {"ux0:", "uma0:", "imc0:", "xmc0:", "grw0:", "ur0:"}

local function loadDir()
	P.items = {}
	if P.path == nil then
		for _, d in ipairs(DEVICES) do
			if System.doesDirExist(d) then P.items[#P.items + 1] = {name = d, path = d} end
		end
	else
		for _, n in ipairs(Scanner.listFolders(P.path)) do
			P.items[#P.items + 1] = {name = n, path = PathJoin(P.path, n)}
		end
	end
	P.sel = math.clamp(P.sel or 1, 1, max(1, #P.items))
	P.scroll = 0
end

function FolderPicker:enter(cb)
	P = {cb = cb, path = nil, history = {}}
	loadDir()
end

local function goUp()
	if P.path == nil then App.pop() return end
	local parent = P.path:match("^(.*)/[^/]+$")
	if not parent then
		P.path = nil
	else
		P.path = parent
	end
	P.sel = table.remove(P.history) or 1
	loadDir()
end

local function choose()
	if not P.path then return end
	local cb = P.cb
	local path = P.path
	App.pop()
	cb(path)
	UI.toast("Added " .. path)
end

function FolderPicker:input()
	local n = #P.items
	if Input.pressed(Input.BACK) then goUp() return end
	if Input.rep(SCE_CTRL_DOWN) then P.sel = min(n, P.sel + 1) end
	if Input.rep(SCE_CTRL_UP) then P.sel = max(1, P.sel - 1) end
	if Input.pressed(SCE_CTRL_LEFT) then goUp() return end
	if (Input.pressed(Input.OK) or Input.pressed(SCE_CTRL_RIGHT)) and P.items[P.sel] then
		P.history[#P.history + 1] = P.sel
		P.path = P.items[P.sel].path:gsub("/$", "")
		P.sel = 1
		loadDir()
		return
	end
	if Input.pressed(SCE_CTRL_TRIANGLE) or Input.pressed(SCE_CTRL_START) then choose() return end
	if Input.touch and Input.dragging then P.scroll = P.scroll - Input.dy end
	if Input.tap then
		if Input.tap.y < 56 then
			if Input.tap.x < 80 then goUp() elseif Input.tap.x > SCREEN_W - 260 then choose() end
			return
		end
		local idx = floor((Input.tap.y - 64 + P.scroll) / 46) + 1
		if P.items[idx] then
			P.history[#P.history + 1] = idx
			P.path = P.items[idx].path:gsub("/$", "")
			P.sel = 1
			loadDir()
		end
	end
end

function FolderPicker:update() end

function FolderPicker:draw()
	Screen.clear(C.bg)
	UI.icon("back", 20, 18, C.sub)
	UI.textFit(FONT.l, 60, 14, P.path or "Choose a storage device", C.text, SCREEN_W - 340)
	if P.path then
		UI.rect(SCREEN_W - 250, 12, 230, 34, C.accent)
		UI.textCenter(FONT.b, SCREEN_W - 135, 18, "Use this folder", C.onAccent)
	end
	local viewH = SCREEN_H - 64 - 38
	if not Input.dragging then
		local y1 = (P.sel - 1) * 46
		if y1 < P.scroll then P.scroll = y1 end
		if y1 + 46 > P.scroll + viewH then P.scroll = y1 + 46 - viewH end
	end
	P.scroll = math.clamp(P.scroll, 0, max(0, #P.items * 46 - viewH))
	if #P.items == 0 then
		UI.textCenter(FONT.m, SCREEN_W / 2, 240, "No subfolders here", C.sub)
	end
	for i, it in ipairs(P.items) do
		local y = 64 + (i - 1) * 46 - P.scroll
		if y > 20 and y < SCREEN_H - 38 then
			if i == P.sel then
				UI.rect(12, y, SCREEN_W - 24, 42, C.selected)
				UI.rect(12, y, 3, 42, C.accent)
			end
			UI.icon("folder", 28, y + 9, C.sub)
			UI.textFit(FONT.m, 66, y + 10, it.name, C.text, SCREEN_W - 120)
		end
	end
	UI.rect(0, SCREEN_H - 38, SCREEN_W, 38, C.bg)
	UI.hints({{"ok", "Open"}, {"triangle", "Use this folder"}, {"back", "Up"}}, SCREEN_H - 30)
end
