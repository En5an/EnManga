-- Home: navigation rail + Library / History / Settings
Home = {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
-- Layout (recomputed when the screen rotates). Landscape: navigation rail on the left.
-- Portrait: tab bar at the bottom, categories on a second header line.
local RAIL_W, BAR_H, X0, CW, TOP, BOTTOM, PORTRAIT, HINT_Y
local function layout()
	PORTRAIT = UI.portrait()
	if PORTRAIT then
		RAIL_W, BAR_H = 0, 56
		X0, CW = 0, SCREEN_W
		TOP = 96
		BOTTOM = SCREEN_H - BAR_H - 34
		HINT_Y = SCREEN_H - BAR_H - 30
	else
		RAIL_W, BAR_H = 64, 0
		X0, CW = RAIL_W, SCREEN_W - RAIL_W
		TOP = 62
		BOTTOM = SCREEN_H - 38
		HINT_Y = SCREEN_H - 30
	end
end
UI.onLayout(layout)
local TABS = {
	{id = "library", icon = "grid", label = "Library"},
	{id = "history", icon = "history", label = "History"},
	{id = "settings", icon = "options", label = "Settings"}
}

local state = {
	tab = 1, railFocus = false, cat = "All", query = "",
	items = {}, sel = 1, scroll = 0, scrollV = 0, builtVersion = -1,
	hist = {}, hsel = 1, hscroll = 0,
	settings = nil
}

------------------------------------------------------------------------
-- Shared sheets
------------------------------------------------------------------------
function Home.categorySheet(series)
	local items = {}
	if #Store.cats == 0 then
		items[#items + 1] = {kind = "info", label = "No categories yet"}
	end
	for _, name in ipairs(Store.cats) do
		items[#items + 1] = {
			kind = "toggle", label = name,
			get = function()
				local m = Store.meta[series.key]
				return m and m.cats and m.cats[name] == true or false
			end,
			set = function(v)
				Store.series(series.key).cats[name] = v or nil
				Store.mark("meta")
				Library.version = Library.version + 1
			end
		}
	end
	items[#items + 1] = {kind = "action", label = "New category...", run = function()
		UI.prompt("New category", "", function(t)
			t = t and t:gsub("^%s+", ""):gsub("%s+$", "")
			if t and Store.addCategory(t) then
				Store.series(series.key).cats[t] = true
				Store.mark("meta")
				Library.version = Library.version + 1
				Home.categorySheet(series)
			end
		end)
	end}
	Sheet.open {title = "Categories", items = items}
end

function Home.manageCategories()
	local items = {}
	for _, name in ipairs(Store.cats) do
		items[#items + 1] = {kind = "action", label = name, value = "›", run = function()
			Sheet.open {title = name, items = {
				{kind = "action", label = "Rename...", run = function()
					UI.prompt("Rename category", name, function(t)
						if Store.renameCategory(name, t) then
							if state.cat == name then state.cat = t end
							Library.version = Library.version + 1
						end
						Home.manageCategories()
					end)
				end},
				{kind = "action", label = "Move up", run = function() Store.moveCategory(name, -1) Home.manageCategories() end},
				{kind = "action", label = "Move down", run = function() Store.moveCategory(name, 1) Home.manageCategories() end},
				{kind = "action", label = "Delete", danger = true, run = function()
					UI.confirm("Delete \"" .. name .. "\"?", "Delete", function()
						Store.removeCategory(name)
						if state.cat == name then state.cat = "All" end
						Library.version = Library.version + 1
						Home.manageCategories()
					end)
				end}
			}}
		end}
	end
	items[#items + 1] = {kind = "action", label = "Add category...", run = function()
		UI.prompt("New category", "", function(t)
			t = t and t:gsub("^%s+", ""):gsub("%s+$", "")
			if t and Store.addCategory(t) then Library.version = Library.version + 1 end
			Home.manageCategories()
		end)
	end}
	Sheet.closeAll()
	Sheet.open {title = "Categories", items = items}
end

function Home.manageFolders()
	local items = {{kind = "info", label = "EnManga scans these folders:"}}
	for i, f in ipairs(Settings.Folders) do
		local exists = System.doesDirExist(f)
		items[#items + 1] = {kind = "action", label = f, value = exists and "" or "missing", run = function()
			UI.confirm("Remove " .. f .. "?", "Remove", function()
				table.remove(Settings.Folders, i)
				Store.mark("settings")
				Home.manageFolders()
			end)
		end}
	end
	items[#items + 1] = {kind = "action", label = "Add folder...", run = function()
		Sheet.closeAll()
		App.push(FolderPicker, function(path)
			if not table.find(Settings.Folders, path) then
				Settings.Folders[#Settings.Folders + 1] = path
				Store.mark("settings")
				Home.rescan()
			end
		end)
	end}
	items[#items + 1] = {kind = "action", label = "Rescan now", run = function() Home.rescan() end}
	Sheet.closeAll()
	Sheet.open {title = "Library folders", items = items}
end

function Home.rescan()
	if Library.scanning then return end
	UI.toast("Scanning library...")
	Library.rescan(function(list, roots)
		UI.toast(#list .. " series found in " .. roots .. " folder" .. (roots == 1 and "" or "s"))
	end)
end

-- Accent colour: presets + custom picker
local function accentName(hex)
	for _, a in ipairs(ACCENTS) do if a[2] == hex then return a[1] end end
	return hex
end
function Home.accentSheet()
	local items = {}
	for _, a in ipairs(ACCENTS) do
		local name, hex = a[1], a[2]
		local r, g, b = HexToRGB(hex)
		items[#items + 1] = {kind = "action", label = (Settings.Accent == hex and "✓ " or "") .. name, value = "",
			swatch = function() return Color.new(r, g, b) end,
			keepOpen = true, run = function()
				Store.set("Accent", hex)
				Home.accentSheet()
			end}
	end
	items[#items + 1] = {kind = "header", label = ""}
	items[#items + 1] = {kind = "action", label = "Custom colour...", value = function()
		return accentName(Settings.Accent) == Settings.Accent and Settings.Accent or ""
	end, run = function()
		Sheet.closeAll()
		App.push(ColorPicker, Settings.Accent, function(hex)
			Store.set("Accent", hex)
			UI.toast("Accent colour " .. hex)
		end)
	end}
	Sheet.closeAll()
	Sheet.open {title = "Accent colour", items = items}
end

-- Context actions for one series (SELECT in library, △ in details)
function Home.seriesSheet(s)
	Sheet.open {title = s.title, items = {
		{kind = "action", label = Library.resumeLabel(s), run = function() Home.resume(s) end},
		{kind = "action", label = "Open details", run = function() App.push(SeriesScreen, s) end},
		{kind = "action", label = "Categories...", run = function() Home.categorySheet(s) end},
		{kind = "action", label = "Mark all as read", run = function()
			for _, ch in ipairs(s.chapters) do Store.setRead(ch.key, true) end
			Library.version = Library.version + 1
		end},
		{kind = "action", label = "Mark all as unread", run = function()
			for _, ch in ipairs(s.chapters) do Store.setRead(ch.key, false) end
			Library.version = Library.version + 1
		end},
		{kind = "action", label = "Reader settings for this series...", run = function() Reader.seriesSettingsSheet(s) end},
		{kind = "action", label = "Remove from history", run = function()
			Store.removeHistory(s.key)
			Library.version = Library.version + 1
		end}
	}}
end

function Home.statsSheet()
	local list = {}
	for _, s in ipairs(Library.series) do
		local st = Store.stats(s.key)
		if (st.t or 0) > 0 or (st.p or 0) > 0 then list[#list + 1] = {s = s, st = st} end
	end
	table.sort(list, function(a, b) return (a.st.t or 0) > (b.st.t or 0) end)
	local items = {}
	if #list == 0 then items[1] = {kind = "info", label = "Read something first"} end
	for i = 1, math.min(#list, 30) do
		local e = list[i]
		items[#items + 1] = {kind = "action", label = e.s.title, value = FormatDuration(e.st.t) .. " · " .. (e.st.p or 0) .. "p", run = function()
			App.push(SeriesScreen, e.s)
		end}
	end
	Sheet.open {title = "Most read", items = items}
end

-- Opening a series from the library: volumes grid, or straight back to the last page
function Home.open(s)
	if Settings.LibOpen == "Continue" and Library.lastActivity(s) > 0 then
		Home.resume(s)
	else
		App.push(SeriesScreen, s)
	end
end

-- Presets: make one the default, save the current defaults, rename / delete your own
function Home.presetManager()
	local current = Store.matchPreset(function(k) return Settings[k] end)
	local items = {{kind = "info", label = "Default for all series: " .. (current or "custom settings")}}
	local function presetActions(p)
		local acts = {
			{kind = "info", label = Reader.describePreset(p)},
			{kind = "action", label = "Use as default for all series", run = function()
				Store.applyPresetAsDefault(p)
				UI.toast(p.name .. " is now the default")
				Home.presetManager()
			end}
		}
		if not p.builtin then
			acts[#acts + 1] = {kind = "action", label = "Replace with current defaults", run = function()
				Store.savePreset(p.name, Store.capturePreset(function(k) return Settings[k] end))
				UI.toast("Updated " .. p.name)
			end}
			acts[#acts + 1] = {kind = "action", label = "Rename...", run = function()
				UI.prompt("Rename preset", p.name, function(t)
					if not Store.renamePreset(p.name, t) then UI.toast("That name is empty or already used") end
					Home.presetManager()
				end)
			end}
			acts[#acts + 1] = {kind = "action", label = "Delete", danger = true, run = function()
				UI.confirm("Delete preset \"" .. p.name .. "\"?", "Delete", function()
					Store.deletePreset(p.name)
					Home.presetManager()
				end)
			end}
		end
		Sheet.open {title = p.name, items = acts}
	end
	for _, builtin in ipairs({true, false}) do
		local any = false
		for _, p in ipairs(Store.presets()) do
			if (p.builtin == true) == builtin then
				if not any then
					items[#items + 1] = {kind = "header", label = builtin and "Built-in" or "Yours"}
					any = true
				end
				items[#items + 1] = {kind = "action", label = (p.name == current and "✓ " or "") .. p.name, value = "›", keepOpen = true, run = function() presetActions(p) end}
			end
		end
	end
	items[#items + 1] = {kind = "header", label = ""}
	items[#items + 1] = {kind = "action", label = "Save current defaults as a preset...", run = function()
		Reader.savePresetPrompt(function(k) return Settings[k] end)
	end}
	Sheet.closeAll()
	Sheet.open {title = "Reader presets", items = items}
end

function Home.resume(s)
	local ci, page = Library.resumePoint(s)
	Reader.open(s, ci, page)
end

------------------------------------------------------------------------
-- Library tab
------------------------------------------------------------------------
local function catList()
	local l = {"All"}
	for _, c in ipairs(Store.cats) do l[#l + 1] = c end
	return l
end

local function rebuild()
	local keepKey = state.items[state.sel] and state.items[state.sel].s.key
	if not table.find(catList(), state.cat) then state.cat = "All" end
	state.items = Library.view(state.cat, Settings.LibFilter, Settings.LibSort, Settings.LibSortDesc, state.query)
	state.builtVersion = Library.version
	state.sel = 1
	if keepKey then
		for i, it in ipairs(state.items) do
			if it.s.key == keepKey then state.sel = i break end
		end
	end
	state.sel = math.clamp(state.sel, 1, max(1, #state.items))
end

function Home.refresh()
	Library.version = Library.version + 1
end

local function geom()
	local mode = Settings.LibDisplay
	if mode == "List" then
		return {list = true, cols = 1, cellW = CW - 32, cellH = 78, coverW = 50, coverH = 72}
	end
	local cols = Settings.Columns
	if PORTRAIT then cols = max(2, floor(cols * 0.55 + 0.5)) end
	local gap = 12
	local cellW = floor((CW - 32 - (cols - 1) * gap) / cols)
	local coverH = floor(cellW * 1.42)
	local titleH = ({["Two lines"] = 60, ["One line"] = 40, Hidden = gap})[Settings.CoverTitles] or 60
	local cellH = (mode == "Compact") and (coverH + gap) or (coverH + titleH)
	return {cols = cols, gap = gap, cellW = cellW, cellH = cellH, coverW = cellW, coverH = coverH, compact = mode == "Compact"}
end

local function libraryOptions()
	Sheet.open {title = "Library", items = {
		{kind = "header", label = "Display"},
		{kind = "choice", label = "Layout", options = OPT.LibDisplay, labels = OPT.LibDisplayLabels, get = function() return Settings.LibDisplay end, set = function(v) Store.set("LibDisplay", v) end},
		{kind = "slider", label = "Columns", min = 3, max = 9, get = function() return Settings.Columns end, set = function(v) Store.set("Columns", v) end},
		{kind = "choice", label = "Titles under covers", options = OPT.CoverTitles, get = function() return Settings.CoverTitles end, set = function(v) Store.set("CoverTitles", v) end},
		{kind = "toggle", label = "Unread badges", get = function() return Settings.ShowBadges end, set = function(v) Store.set("ShowBadges", v) end},
		{kind = "choice", label = "Animated GIF covers", options = OPT.GifCovers, labels = OPT.GifCoversLabels, get = function() return Settings.GifCovers end, set = function(v) Store.set("GifCovers", v) if v == "Off" then Covers.stopAnimations() end end},
		{kind = "header", label = "Sort & filter"},
		{kind = "choice", label = "Sort by", options = OPT.LibSort, get = function() return Settings.LibSort end, set = function(v) Store.set("LibSort", v) Home.refresh() end},
		{kind = "toggle", label = "Reverse order", get = function() return Settings.LibSortDesc end, set = function(v) Store.set("LibSortDesc", v) Home.refresh() end},
		{kind = "choice", label = "Show", options = OPT.LibFilter, get = function() return Settings.LibFilter end, set = function(v) Store.set("LibFilter", v) Home.refresh() end},
		{kind = "header", label = "Library"},
		{kind = "action", label = "Search...", run = function() Home.search() end},
		{kind = "action", label = "Categories...", run = function() Home.manageCategories() end},
		{kind = "action", label = "Folders...", run = function() Home.manageFolders() end},
		{kind = "action", label = "Rescan library", run = function() Home.rescan() end}
	}}
end

function Home.search()
	UI.prompt("Search library", state.query, function(t)
		state.query = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
		Home.refresh()
	end)
end

local function libInput(dt)
	local g = geom()
	local n = #state.items
	local cols = g.cols
	local cats = catList()
	if Input.pressed(SCE_CTRL_LTRIGGER) and #cats > 1 then
		state.cat = table.cycle(cats, state.cat, -1)
		Home.refresh()
	elseif Input.pressed(SCE_CTRL_RTRIGGER) and #cats > 1 then
		state.cat = table.cycle(cats, state.cat, 1)
		Home.refresh()
	end
	if n > 0 then
		local sel = state.sel
		if Input.rep(SCE_CTRL_RIGHT) and not g.list then sel = min(n, sel + 1) end
		if Input.rep(SCE_CTRL_LEFT) then
			if g.list or (sel - 1) % cols == 0 then
				state.railFocus = true
				return
			end
			sel = max(1, sel - 1)
		end
		if Input.rep(SCE_CTRL_DOWN) then
			if PORTRAIT and floor((sel - 1) / cols) == floor((n - 1) / cols) then
				state.railFocus = true
				return
			end
			sel = min(n, sel + cols)
		end
		if Input.rep(SCE_CTRL_UP) then sel = max(1, sel - cols) end
		if sel ~= state.sel then
			state.sel = sel
			state.scrollV = 0
		end
		local it = state.items[state.sel]
		if Input.pressed(Input.OK) then Home.open(it.s) return end
		if Input.pressed(SCE_CTRL_START) then Home.resume(it.s) return end
		if Input.pressed(SCE_CTRL_SELECT) then Home.seriesSheet(it.s) return end
	elseif Input.pressed(SCE_CTRL_LEFT) then
		state.railFocus = true
		return
	end
	if Input.pressed(SCE_CTRL_TRIANGLE) then libraryOptions() return end
	if Input.pressed(SCE_CTRL_SQUARE) then Home.search() return end
	if Input.pressed(Input.BACK) and state.query ~= "" then
		state.query = ""
		Home.refresh()
	end
	-- touch: drag scroll with momentum, tap to open
	if Input.touch and Input.touch.y > TOP and Input.touch.x > X0 then
		if Input.dragging then
			state.scroll = state.scroll - Input.dy
			state.scrollV = -Input.dy
			state.dragged = true
		end
	elseif state.dragged then
		state.dragged = false
	end
	if Input.tap and Input.tap.y > TOP and Input.tap.y < BOTTOM and Input.tap.x > X0 then
		local tx, ty = Input.tap.x - X0 - 16, Input.tap.y - TOP + state.scroll - 8
		local col = g.list and 0 or floor(tx / (g.cellW + g.gap))
		local row = floor(ty / g.cellH)
		local idx = row * cols + col + 1
		if col >= 0 and col < cols and idx >= 1 and idx <= n then
			if idx == state.sel or Settings.LibDisplay ~= "x" then
				state.sel = idx
				Home.open(state.items[idx].s)
			end
		end
	end
	-- category tabs tap
	if Input.tap and Input.tap.y < TOP and Input.tap.y >= (state.catY or 0) and state.catHit then
		for _, h in ipairs(state.catHit) do
			if Input.tap.x >= h.x1 and Input.tap.x <= h.x2 then
				state.cat = h.cat
				Home.refresh()
			end
		end
	end
end

local function libUpdate(dt)
	if state.builtVersion ~= Library.version then rebuild() end
	-- preload the volume covers of the series you rest on, so opening it is instant
	if state.hoverSel ~= state.sel then
		state.hoverSel, state.hoverTime = state.sel, 0
	else
		state.hoverTime = (state.hoverTime or 0) + dt
		local it = state.items[state.sel]
		if it and state.hoverTime > 300 and not Loader.busy() then
			SeriesScreen.prefetch(it.s, 10)
		end
	end
	local g = geom()
	local viewH = BOTTOM - TOP
	local rows = math.ceil(#state.items / g.cols)
	local contentH = rows * g.cellH + 16
	local maxScroll = max(0, contentH - viewH)
	if Input.touch and Input.dragging then
		-- direct manipulation
	elseif abs(state.scrollV) > 0.5 then
		state.scroll = state.scroll + state.scrollV
		state.scrollV = state.scrollV * 0.92
	else
		state.scrollV = 0
		-- keep selection visible
		local row = floor((state.sel - 1) / g.cols)
		local y1 = row * g.cellH
		local y2 = y1 + g.cellH + 16
		local target = state.scroll
		if y1 < state.scroll then target = y1 end
		if y2 > state.scroll + viewH then target = y2 - viewH end
		state.scroll = state.scroll + (target - state.scroll) * min(1, dt / 70)
	end
	state.scroll = math.clamp(state.scroll, 0, maxScroll)
end

local function drawBadge(x, y, text)
	local w = TextWidth(FONT.s, text) + 12
	UI.rect(x, y, w, 22, C.accent)
	UI.text(FONT.s, x + 6, y + 1, text, C.onAccent)
end

local function drawProgress(x, y, w, frac)
	if frac <= 0 then return end
	UI.rect(x, y, w, 3, Color.new(0, 0, 0, 120))
	UI.rect(x, y, floor(w * math.min(1, frac)), 3, C.accent)
end

local function libDraw(dt)
	local g = geom()
	local n = #state.items
	local function header()
		-- header: categories
		local cats = catList()
		local hx = X0 + 20
		UI.text(FONT.l, hx, 14, "Library", C.text)
		hx = hx + TextWidth(FONT.l, "Library") + 24
		local cy = 0
		local limit = SCREEN_W - 170
		if PORTRAIT then hx, cy, limit = X0 + 20, 44, SCREEN_W - 60 end
		state.catHit = {}
		state.catY = cy
		if #cats > 1 then
			UI.image(BTN.l, hx, 24 + cy, C.sub)
			hx = hx + 32
			for _, c in ipairs(cats) do
				local w = TextWidth(FONT.m, c)
				if hx + w > limit then
					UI.text(FONT.m, hx, 18 + cy, "...", C.sub)
					break
				end
				local active = c == state.cat
				UI.text(FONT.m, hx, 18 + cy, c, active and C.text or C.sub)
				if active then UI.rect(hx, 44 + cy, w, 2, C.accent) end
				state.catHit[#state.catHit + 1] = {x1 = hx - 8, x2 = hx + w + 8, cat = c}
				hx = hx + w + 22
			end
			UI.image(BTN.r, hx, 24 + cy, C.sub)
		end
		UI.status(SCREEN_W - 16, 20)
		local info = {}
		if state.query ~= "" then info[#info + 1] = "\"" .. state.query .. "\"" end
		if Settings.LibFilter ~= "All" then info[#info + 1] = Settings.LibFilter end
		if #info > 0 then
			UI.textRight(FONT.s, SCREEN_W - 16, 42, UI.fit(FONT.s, table.concat(info, " · ") .. "  (" .. n .. ")", 300), C.accent)
		end
	end
	-- empty state
	if n == 0 then
		local msg
		if Library.scanning then
			msg = {"Scanning library...", Library.scanMsg}
		elseif #Library.series == 0 then
			msg = {"No manga found", "Copy folders of images or .cbz/.zip files into", "ux0:data/enmanga/import  or  ux0:manga", "then press △ → Rescan library."}
		else
			msg = {"Nothing here", "No series match the current category, filter or search."}
		end
		local y = 200
		for i, l in ipairs(msg) do
			UI.textCenter(i == 1 and FONT.l or FONT.m, X0 + CW / 2, y, l, i == 1 and C.text or C.sub)
			y = y + (i == 1 and 44 or 28)
		end
		header()
		return
	end
	-- items
	local viewTop = TOP
	local firstRow = max(0, floor((state.scroll - 8) / g.cellH))
	local lastRow = floor((state.scroll + (BOTTOM - TOP)) / g.cellH) + 1
	local selRow = floor((state.sel - 1) / g.cols)
	for row = firstRow, lastRow do
		for col = 0, g.cols - 1 do
			local idx = row * g.cols + col + 1
			local it = state.items[idx]
			if not it then break end
			local x = X0 + 16 + col * (g.cellW + (g.gap or 0))
			local y = floor(viewTop + 8 + row * g.cellH - state.scroll)
			local selected = idx == state.sel and not state.railFocus
			local s, st = it.s, it.st
			local prio = abs(row - selRow)
			if g.list then
				if selected then UI.rect(x - 8, y - 3, g.cellW + 16, g.cellH - 2, C.selected) UI.rect(x - 8, y - 3, 3, g.cellH - 2, C.accent) end
				Covers.draw(s, x, y, g.coverW, g.coverH, prio, nil, selected)
				UI.textFit(FONT.b, x + 66, y + 8, s.title, C.text, g.cellW - 200)
				local sub = Library.unitName(s)
				if st.unread > 0 and st.unread < st.total then sub = sub .. " · " .. st.unread .. " unread" end
				if st.unread == 0 then sub = sub .. " · completed" end
				if st.lastRead > 0 then sub = sub .. " · read " .. StampDate(st.lastRead):sub(1, 10) end
				UI.textFit(FONT.s, x + 66, y + 36, sub, C.sub, g.cellW - 90)
				if st.total > 0 then
					UI.rect(x + 66, y + 62, 200, 3, C.surface2)
					UI.rect(x + 66, y + 62, floor(200 * st.read / st.total), 3, C.accent)
				end
				if st.total > 0 and st.unread == 0 then
					UI.readMark(x + g.cellW - 30, y + 8, 24)
				elseif Settings.ShowBadges and st.unread > 0 then
					local t = tostring(st.unread)
					drawBadge(x + g.cellW - TextWidth(FONT.s, t) - 14, y + 8, t)
				end
			else
				Covers.draw(s, x, y, g.coverW, g.coverH, prio, nil, selected)
				if g.compact then
					UI.rect(x, y + g.coverH - 52, g.coverW, 52, Color.new(0, 0, 0, 165))
					local lines = UI.wrap(FONT.s, s.title, g.coverW - 12, 2)
					for li, l in ipairs(lines) do
						UI.text(FONT.s, x + 6, y + g.coverH - 50 + (li - 1) * 20 + (2 - #lines) * 10, l, C.white)
					end
				end
				local done = st.total > 0 and st.unread == 0
				if done then
					UI.rect(x, y, g.coverW, g.coverH, Color.new(0, 0, 0, 90))
					UI.readMark(x + g.coverW - 30, y + 6, 24)
				elseif st.total > 0 and (st.read > 0 or st.started > 0) then
					drawProgress(x, y + g.coverH - 3, g.coverW, math.max(0.04, st.read / st.total))
				end
				if Settings.ShowBadges and st.unread > 0 then
					drawBadge(x + 6, y + 6, tostring(st.unread))
				end
				if selected then
					UI.frame(x - 4, y - 4, g.coverW + 8, g.coverH + 8, C.accent, 3)
				end
				if not g.compact and Settings.CoverTitles ~= "Hidden" then
					local lines = UI.wrap(FONT.s, s.title, g.coverW, Settings.CoverTitles == "One line" and 1 or 2)
					for li, l in ipairs(lines) do
						UI.text(FONT.s, x, y + g.coverH + 5 + (li - 1) * 19, l, selected and C.text or C.sub)
					end
				end
			end
		end
	end
	-- scroll indicator
	local rows = math.ceil(n / g.cols)
	local contentH = rows * g.cellH + 16
	local viewH = BOTTOM - TOP
	if contentH > viewH then
		local bh = max(30, viewH * viewH / contentH)
		local by = TOP + (viewH - bh) * state.scroll / (contentH - viewH)
		UI.rect(SCREEN_W - 5, by, 3, bh, C.line)
	end
	-- header on top of anything scrolled under it
	UI.rect(X0, 0, SCREEN_W - X0, TOP, C.bg)
	header()
end

------------------------------------------------------------------------
-- History tab
------------------------------------------------------------------------
local function buildHistory()
	local out = {}
	for _, s in ipairs(Library.series) do
		local t, ci = Library.lastActivity(s)
		if ci then
			local ch = s.chapters[ci]
			local p = Store.progress[ch.key]
			out[#out + 1] = {s = s, t = t, ch = ch.name, page = p and p.p, total = p and p.n}
		end
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	state.hist = out
	state.hsel = math.clamp(state.hsel, 1, max(1, #out))
	state.histVersion = Library.version
end

local HROW = 78
local function histInput()
	local n = #state.hist
	if Input.pressed(SCE_CTRL_LEFT) then state.railFocus = true return end
	if n > 0 then
		if Input.rep(SCE_CTRL_DOWN) then state.hsel = min(n, state.hsel + 1) end
		if Input.rep(SCE_CTRL_UP) then state.hsel = max(1, state.hsel - 1) end
		local h = state.hist[state.hsel]
		if Input.pressed(Input.OK) or Input.pressed(SCE_CTRL_START) then Home.resume(h.s) return end
		if Input.pressed(SCE_CTRL_SELECT) then App.push(SeriesScreen, h.s) return end
		if Input.pressed(SCE_CTRL_SQUARE) then
			Store.removeHistory(h.s.key)
			Library.version = Library.version + 1
			return
		end
		if Input.pressed(SCE_CTRL_TRIANGLE) then
			UI.confirm("Clear all reading history?", "Clear history", function()
				Store.clearHistory()
				Library.version = Library.version + 1
			end)
			return
		end
	end
	if Input.touch and Input.dragging and Input.touch.x > X0 then
		state.hscroll = state.hscroll - Input.dy
	end
	if Input.tap and Input.tap.y > TOP and Input.tap.x > X0 then
		local idx = floor((Input.tap.y - TOP - 8 + state.hscroll) / HROW) + 1
		if idx >= 1 and idx <= n then
			state.hsel = idx
			Home.resume(state.hist[idx].s)
		end
	end
end

local function histDraw(dt)
	if state.histVersion ~= Library.version then buildHistory() end
	UI.text(FONT.l, X0 + 20, 14, "History", C.text)
	UI.status(SCREEN_W - 16, 20)
	local n = #state.hist
	if n == 0 then
		UI.textCenter(FONT.l, X0 + CW / 2, 220, "Nothing read yet", C.text)
		UI.textCenter(FONT.m, X0 + CW / 2, 264, "Chapters you open will show up here.", C.sub)
		return
	end
	local viewH = BOTTOM - TOP
	if not Input.dragging then
		local y1 = (state.hsel - 1) * HROW
		if y1 < state.hscroll then state.hscroll = y1 end
		if y1 + HROW > state.hscroll + viewH then state.hscroll = y1 + HROW - viewH end
	end
	state.hscroll = math.clamp(state.hscroll, 0, max(0, n * HROW + 16 - viewH))
	local lastDay = nil
	for i, h in ipairs(state.hist) do
		local y = TOP + 8 + (i - 1) * HROW - state.hscroll
		if y > TOP - HROW and y < BOTTOM then
			local x = X0 + 16
			local selected = i == state.hsel and not state.railFocus
			if selected then
				UI.rect(x - 8, y - 3, CW - 16, HROW - 4, C.selected)
				UI.rect(x - 8, y - 3, 3, HROW - 4, C.accent)
			end
			Covers.draw(h.s, x, y, 50, 70, abs(i - state.hsel))
			UI.textFit(FONT.b, x + 66, y + 8, h.s.title, C.text, CW - 290)
			local sub = h.ch
			if h.page and h.total then sub = sub .. "  ·  page " .. h.page .. " / " .. h.total end
			UI.textFit(FONT.s, x + 66, y + 38, sub, C.sub, CW - 290)
			UI.textRight(FONT.s, SCREEN_W - 24, y + 10, StampDate(h.t), C.sub)
		end
	end
end

------------------------------------------------------------------------
-- Settings tab (embedded Panel)
------------------------------------------------------------------------
local function buildSettings()
	local items = {
		{kind = "header", label = "Appearance"},
		{kind = "choice", label = "Theme", options = OPT.Theme, get = function() return Settings.Theme end, set = function(v) Store.set("Theme", v) end},
		{kind = "action", label = "Accent colour", value = function() return accentName(Settings.Accent) end,
			swatch = function() return C.accent end, run = function() Home.accentSheet() end},
		{kind = "choice", label = "Confirm button", options = OPT.Confirm, labels = OPT.ConfirmLabels, get = function() return Settings.Confirm end, set = function(v) Store.set("Confirm", v) end},
		{kind = "choice", label = "Library layout", options = OPT.LibDisplay, labels = OPT.LibDisplayLabels, get = function() return Settings.LibDisplay end, set = function(v) Store.set("LibDisplay", v) end},
		{kind = "slider", label = "Grid columns", min = 3, max = 9, get = function() return Settings.Columns end, set = function(v) Store.set("Columns", v) end},
		{kind = "toggle", label = "Unread badges", get = function() return Settings.ShowBadges end, set = function(v) Store.set("ShowBadges", v) end},
		{kind = "choice", label = "Opening a series", options = OPT.LibOpen, labels = OPT.LibOpenLabels, get = function() return Settings.LibOpen end, set = function(v) Store.set("LibOpen", v) end},
		{kind = "choice", label = "Titles under covers", options = OPT.CoverTitles, get = function() return Settings.CoverTitles end, set = function(v) Store.set("CoverTitles", v) end},
		{kind = "choice", label = "Animated GIF covers", options = OPT.GifCovers, labels = OPT.GifCoversLabels, get = function() return Settings.GifCovers end, set = function(v) Store.set("GifCovers", v) if v == "Off" then Covers.stopAnimations() end end},
		{kind = "toggle", label = "Short names (Vol. 2 instead of file name)", get = function() return Settings.CleanNames end, set = function(v) Store.set("CleanNames", v) Library.renameAll() end},
		{kind = "header", label = "Screen & controls"},
		{kind = "choice", label = "Screen orientation", options = MODE_OPTIONS, labels = MODE_LABELS, get = function() return Orient.mode() end, set = function(v) Orient.setMode(v) end},
		{kind = "toggle", label = "Flip portrait direction (auto-rotate)", get = function() return Settings.RotateFlip end, set = function(v) Store.set("RotateFlip", v) end},
		{kind = "toggle", label = "Rear touchpad (tap = next page, drag = scroll)", get = function() return Settings.RearTouch end, set = function(v) Store.set("RearTouch", v) end},
		{kind = "toggle", label = "Rear touchpad is mirrored", get = function() return Settings.RearSwap end, set = function(v) Store.set("RearSwap", v) end},
		{kind = "header", label = "Inside a series"},
		{kind = "choice", label = "Default view", options = OPT.VolumeView, labels = OPT.VolumeViewLabels, get = function() return Settings.VolumeView end, set = function(v) Store.set("VolumeView", v) end},
		{kind = "choice", label = "Default sort", options = OPT.VolumeSort, get = function() return Settings.VolumeSort end, set = function(v) Store.set("VolumeSort", v) end},
		{kind = "toggle", label = "Newest first", get = function() return Settings.ChapterSortDesc end, set = function(v) Store.set("ChapterSortDesc", v) end},
		{kind = "header", label = "Library"},
		{kind = "action", label = "Folders", value = function() return #Settings.Folders .. " folders" end, run = function() Home.manageFolders() end},
		{kind = "action", label = "Categories", value = function() return tostring(#Store.cats) end, run = function() Home.manageCategories() end},
		{kind = "toggle", label = "Rescan on startup", get = function() return Settings.ScanOnStart end, set = function(v) Store.set("ScanOnStart", v) end},
		{kind = "action", label = "Rescan now", run = function() Home.rescan() end},
		{kind = "header", label = "Reader defaults"},
		{kind = "action", label = "Reader presets...", value = function()
			return Store.matchPreset(function(k) return Settings[k] end) or "Custom"
		end, run = function() Home.presetManager() end},
		{kind = "toggle", label = "Ask for a preset when opening a new series", get = function() return Settings.AskPreset end, set = function(v) Store.set("AskPreset", v) end}
	}
	for _, it in ipairs(Reader.optionItems(
		function(k) return Settings[k] end,
		function(k, v) Store.set(k, v) end, true)) do
		items[#items + 1] = it
	end
	local more = {
		{kind = "header", label = "Statistics"},
		{kind = "info", label = "Total reading time", value = function() return FormatDuration(Store.totalStats().t) end},
		{kind = "info", label = "Pages read", value = function() return tostring(Store.totalStats().p) end},
		{kind = "info", label = "Chapters finished", value = function() return tostring(Store.totalStats().c) end},
		{kind = "info", label = "Series started", value = function() return tostring(Store.totalStats().series) end},
		{kind = "action", label = "Most read series...", run = function() Home.statsSheet() end},
		{kind = "action", label = "Reset statistics", run = function()
			UI.confirm("Reset all reading statistics?", "Reset", function() Store.clearStats() UI.toast("Statistics reset") end)
		end},
		{kind = "header", label = "Data"},
		{kind = "action", label = "Clear reading history", run = function()
			UI.confirm("Clear reading history?", "Clear", function() Store.clearHistory() Library.version = Library.version + 1 end)
		end},
		{kind = "action", label = "Reset all progress & categories", danger = true, run = function()
			UI.confirm("Erase progress, categories and per-series settings?", "Erase everything", function()
				Store.resetAll()
				Library.version = Library.version + 1
				UI.toast("All reading data erased")
			end)
		end},
		{kind = "info", label = "Data folder", value = DATA_DIR},
		{kind = "header", label = "About"},
		{kind = "info", label = "EnManga", value = APP_VERSION},
		{kind = "info", label = "Based on NOBORU by Creckeryop · GPL-3.0"},
		{kind = "info", label = "Inspired by Komikku"},
		{kind = "info", label = "Font: M PLUS 1p · SIL OFL 1.1"}
	}
	for _, it in ipairs(more) do items[#items + 1] = it end
	return Panel.init({items = items})
end

local function settingsGeo()
	return {x = X0 + 4, w = CW - 8, top = TOP, bottom = BOTTOM}
end

local function settingsInput()
	state.settings = state.settings or buildSettings()
	if Input.pressed(Input.BACK) then state.railFocus = true return end
	if Input.pressed(SCE_CTRL_LEFT) then
		local it = state.settings.items[state.settings.sel]
		if not it or (it.kind ~= "choice" and it.kind ~= "slider" and it.kind ~= "toggle") then
			state.railFocus = true
			return
		end
	end
	Panel.input(state.settings, settingsGeo(), function(it) it.run() end)
end

local function settingsDraw()
	state.settings = state.settings or buildSettings()
	UI.text(FONT.l, X0 + 20, 14, "Settings", C.text)
	UI.status(SCREEN_W - 16, 20)
	state.settings.focused = not state.railFocus
	Panel.draw(state.settings, settingsGeo())
end

------------------------------------------------------------------------
-- Screen
------------------------------------------------------------------------
local HomeScreen = {}
Home.screen = HomeScreen

function HomeScreen:enter()
	Home.refresh()
end

function HomeScreen:resume()
	Home.refresh()
	Store.flush()
end

function HomeScreen:input(dt)
	local tab = TABS[state.tab].id
	-- rail / tab bar touch
	if Input.tap and ((not PORTRAIT and Input.tap.x < RAIL_W) or (PORTRAIT and Input.tap.y > SCREEN_H - BAR_H)) then
		for i = 1, #TABS do
			if PORTRAIT then
				local w = SCREEN_W / #TABS
				if Input.tap.x >= (i - 1) * w and Input.tap.x < i * w then state.tab = i end
			else
				local cy = 40 + (i - 1) * 64
				if Input.tap.y > cy - 28 and Input.tap.y < cy + 28 then state.tab = i end
			end
		end
		state.railFocus = false
		return
	end
	-- tap on the clock / battery: lock or unlock rotation
	if Input.tap and Input.tap.y < 44 and Input.tap.x > SCREEN_W - 150 then
		Orient.toggleLock()
		return
	end
	if state.railFocus then
		local prev, nextB, leave = SCE_CTRL_UP, SCE_CTRL_DOWN, SCE_CTRL_RIGHT
		if PORTRAIT then prev, nextB, leave = SCE_CTRL_LEFT, SCE_CTRL_RIGHT, SCE_CTRL_UP end
		if Input.rep(prev) then state.tab = max(1, state.tab - 1) end
		if Input.rep(nextB) then state.tab = min(#TABS, state.tab + 1) end
		if Input.pressed(leave) or Input.pressed(Input.OK) then state.railFocus = false end
		if Input.pressed(SCE_CTRL_TRIANGLE) and tab == "library" then libraryOptions() end
		if Input.tap or Input.touch then state.railFocus = false end
		return
	end
	if tab == "library" then libInput(dt)
	elseif tab == "history" then histInput(dt)
	else settingsInput(dt) end
end

function HomeScreen:update(dt)
	if TABS[state.tab].id == "library" then libUpdate(dt) end
end

function HomeScreen:draw(dt)
	Screen.clear(C.bg)
	local tab = TABS[state.tab].id
	if tab == "library" then libDraw(dt)
	elseif tab == "history" then histDraw(dt)
	else settingsDraw(dt) end
	-- rail (landscape) / tab bar (portrait)
	if PORTRAIT then
		local by = SCREEN_H - BAR_H
		UI.rect(0, by, SCREEN_W, BAR_H, C.surface)
		local w = SCREEN_W / #TABS
		for i, t in ipairs(TABS) do
			local cx = floor((i - 0.5) * w)
			local active = i == state.tab
			if active then
				UI.rect(cx - 40, by, 80, 3, C.accent)
				if state.railFocus then UI.rect(cx - 50, by + 6, 100, BAR_H - 12, C.selected) end
			end
			UI.iconScaled(t.icon, cx, by + BAR_H / 2, 26, active and C.text or C.sub)
		end
	else
		UI.rect(0, 0, RAIL_W, SCREEN_H, C.surface)
		for i, t in ipairs(TABS) do
			local cy = 40 + (i - 1) * 64
			local active = i == state.tab
			if active then
				UI.rect(0, cy - 24, 3, 48, C.accent)
				if state.railFocus then UI.rect(6, cy - 24, RAIL_W - 12, 48, C.selected) end
			end
			UI.iconScaled(t.icon, RAIL_W / 2, cy, 26, active and C.text or C.sub)
		end
	end
	if Library.scanning then
		UI.rect(0, SCREEN_H - 3, floor(SCREEN_W * Library.scanProgress), 3, C.accent)
	end
	-- hints
	UI.rect(X0, BOTTOM, CW, SCREEN_H - BOTTOM - BAR_H, C.bg)
	local hints
	if state.railFocus then
		hints = {{"dpad", "Navigate"}, {"ok", "Open"}}
	elseif tab == "library" then
		hints = #state.items > 0 and {{"ok", "Open"}, {"start", "Continue"}, {"select", "Actions"}, {"square", "Search"}, {"triangle", "Options"}} or {{"triangle", "Options"}}
	elseif tab == "history" then
		hints = #state.hist > 0 and {{"ok", "Resume"}, {"select", "Details"}, {"square", "Remove"}, {"triangle", "Clear all"}} or {}
	else
		local h = state.settings and Panel.hints(state.settings)
		hints = h and {h, {"back", "Menu"}} or {{"back", "Menu"}}
	end
	UI.hints(hints, HINT_Y)
end

-- test hook: select a series (or an index) in the library tab
function Home._select(target)
	state.tab, state.railFocus = 1, false
	if type(target) == "number" then state.sel = target return end
	for i, it in ipairs(state.items or {}) do
		if it.s == target then state.sel = i return end
	end
end
