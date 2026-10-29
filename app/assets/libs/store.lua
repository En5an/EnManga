-- Persistent state: settings, library metadata, reading progress
Store = {}

local SETTINGS_PATH = DATA_DIR .. "/settings.lua"
local META_PATH = DATA_DIR .. "/library.lua"
local PROGRESS_PATH = DATA_DIR .. "/progress.lua"
local CACHE_PATH = DATA_DIR .. "/scan_cache.lua"

-- Option catalog (value list + labels) used by settings UI and validation
OPT = {
	Theme = {"Dark", "Black", "Light"},
	Confirm = {"Auto", "Cross", "Circle"},
	ConfirmLabels = {"System default", "✕ confirms", "○ confirms"},
	LibDisplay = {"Grid", "Compact", "List"},
	LibDisplayLabels = {"Cover grid", "Compact grid", "List"},
	LibSort = {"Title", "Last read", "Date added", "Unread", "Chapters"},
	LibFilter = {"All", "Unread", "In progress", "Completed", "Bookmarked"},
	LibOpen = {"Volumes", "Continue"},
	LibOpenLabels = {"Show volumes", "Continue reading"},
	VolumeView = {"Covers", "Compact", "List"},
	VolumeViewLabels = {"Cover grid", "Compact grid", "List"},
	VolumeSort = {"Number", "Last read", "Unread first", "Progress"},
	VolumeFilter = {"All", "Unread", "In progress", "Read", "Bookmarked"},
	CoverTitles = {"Two lines", "One line", "Hidden"},
	ReadingMode = {"RTL", "LTR", "Vertical", "Webtoon", "Strip"},
	ReadingModeLabels = {"Right to left", "Left to right", "Vertical", "Webtoon", "Long strip"},
	ScaleType = {"Fit screen", "Fit width", "Fit height", "Smart fit", "Original", "Stretch"},
	ZoomStart = {"Auto", "Left", "Right", "Center"},
	DoublePage = {"Off", "On", "Auto"},
	DoublePageLabels = {"Off", "Always", "Auto (landscape)"},
	WidePages = {"Fit", "Split", "Rotate"},
	WidePagesLabels = {"Fit as is", "Split in two", "Rotate to fit"},
	Rotation = {-1, 0, 90, 270},
	AppRotation = {0, 90, 270},
	AppRotationLabels = {"Landscape", "Portrait · D-pad down", "Portrait · D-pad up"},
	RotationLabels = {"Same as app", "Landscape", "Portrait · D-pad down", "Portrait · D-pad up"},
	Background = {"Black", "Gray", "White", "Theme"},
	Filter = {"None", "Warm", "Sepia", "Night", "Paper"},
	TapZones = {"Edges", "L-shape", "Kindle", "Custom", "Off"},
	TapZonesLabels = {"Left / right edges", "L-shaped", "Kindle-ish", "Custom grid", "Disabled"},
	TapAction = {"prev", "next", "menu", "none"},
	PageTone = {"Normal", "Sepia", "Warm", "Cool", "Mint"},
	Quality = {"Full", "High", "Balanced"},
	QualityLabels = {"Full resolution", "High (≤2048 px)", "Balanced (≤1280 px)"},
	PageNumber = {"Off", "Page", "Page + clock"},
	GifCovers = {"Off", "Hover", "Always"},
	BrightnessSwipe = {"Right", "Left", "Both", "Off"},
	BrightnessSwipeLabels = {"Right edge", "Left edge", "Both edges", "Off"},
	GifCoversLabels = {"Off", "When selected", "Always"}
}

-- Accent colour presets (Settings → Accent colour)
ACCENTS = {
	{"Orange", "#F06E28"}, {"Classic red", "#E94B3C"}, {"Amber", "#F2A12E"}, {"Lime", "#9CCC3C"},
	{"Green", "#3DBE6E"}, {"Teal", "#21B5A5"}, {"Sky", "#4AA8F0"}, {"Blue", "#4A7CF0"},
	{"Indigo", "#7068E8"}, {"Purple", "#A35DE0"}, {"Pink", "#E8559C"}, {"Silver", "#B8BCC8"}
}

local DEFAULTS = {
	-- general
	Theme = "Dark",
	Accent = "#F06E28",
	GifCovers = "Hover",
	Confirm = "Auto",
	Folders = {DATA_DIR .. "/import", "ux0:manga", "uma0:manga"},
	ScanOnStart = true,
	-- library
	LibDisplay = "Grid",
	Columns = 6,
	LibSort = "Title",
	LibSortDesc = false,
	LibFilter = "All",
	ShowBadges = true,
	ChapterSortDesc = false,
	LibOpen = "Volumes",
	CleanNames = true,
	CoverTitles = "Two lines",
	VolumeView = "Covers",
	VolumeSort = "Number",
	UserPresets = {},
	AutoRotate = false,
	RotateLock = 0,
	RotateFlip = false,
	LastOrientation = 0,
	RearTouch = true,
	RearSwap = false,
	OrientMigrated = false,
	FlipFixed = false,
	RotateUsed = false,
	AskPreset = false,
	VolumeFilter = "All",
	-- reader (global defaults; some can be overridden per series)
	ReadingMode = "RTL",
	ScaleType = "Fit screen",
	ZoomStart = "Auto",
	DoublePage = "Off",
	DoubleShift = true,
	WidePages = "Fit",
	CropBorders = false,
	Margin = 0,
	Rotation = -1,
	Background = "Black",
	StripWidth = 100,
	Brightness = 100,
	BrightnessSwipe = "Right",
	Filter = "None",
	FilterStrength = 30,
	TapZones = "Edges",
	InvertTap = false,
	InvertButtons = false,
	Animate = true,
	PanFirst = true,
	PageNumber = "Page",
	DoubleTapZoom = true,
	KeepScreenOn = true,
	Preload = 2,
	Quality = "High",
	AutoNextChapter = true,
	ScrollStep = 75,
	PageTone = "Normal",
	RememberZoom = true,
	AutoScrollSpeed = 4,
	TapGrid = {"prev", "menu", "next", "prev", "menu", "next", "prev", "menu", "next"}
}

-- Settings a series can override, and that a preset stores
SERIES_KEYS = {"ReadingMode", "ScaleType", "ZoomStart", "DoublePage", "DoubleShift", "WidePages", "CropBorders", "Margin", "Rotation", "StripWidth",
	"Background", "PageTone", "Filter", "FilterStrength", "TapZones", "InvertTap", "InvertButtons", "PageNumber"}
PRESET_KEYS = SERIES_KEYS

-- Built-in presets (only the keys that define the style; the rest keep your defaults)
BUILTIN_PRESETS = {
	{name = "Manga", v = {ReadingMode = "RTL", ScaleType = "Fit screen", Rotation = -1, DoublePage = "Off", WidePages = "Fit"}},
	{name = "Manga · two pages", v = {ReadingMode = "RTL", ScaleType = "Fit screen", Rotation = -1, DoublePage = "On", DoubleShift = true, WidePages = "Fit"}},
	{name = "Manga · portrait", v = {ReadingMode = "RTL", ScaleType = "Fit screen", Rotation = 90, DoublePage = "Off", WidePages = "Rotate"}},
	{name = "Comic", v = {ReadingMode = "LTR", ScaleType = "Fit screen", Rotation = -1, DoublePage = "Off", WidePages = "Fit"}},
	{name = "Comic · portrait", v = {ReadingMode = "LTR", ScaleType = "Fit screen", Rotation = 90, DoublePage = "Off", WidePages = "Rotate"}},
	{name = "Comic · fit width", v = {ReadingMode = "LTR", ScaleType = "Fit width", Rotation = -1, DoublePage = "Off", ZoomStart = "Auto"}},
	{name = "Webtoon", v = {ReadingMode = "Webtoon", ScaleType = "Fit width", Rotation = 90, StripWidth = 100}},
	{name = "Webtoon · landscape", v = {ReadingMode = "Webtoon", ScaleType = "Fit width", Rotation = 0, StripWidth = 60}}
}
for _, p in ipairs(BUILTIN_PRESETS) do p.builtin = true end

local VALIDATE = {
	Theme = OPT.Theme, Confirm = OPT.Confirm, LibDisplay = OPT.LibDisplay, LibSort = OPT.LibSort, LibFilter = OPT.LibFilter,
	ReadingMode = OPT.ReadingMode, ScaleType = OPT.ScaleType, ZoomStart = OPT.ZoomStart, DoublePage = OPT.DoublePage,
	WidePages = OPT.WidePages, Rotation = OPT.Rotation, Background = OPT.Background, Filter = OPT.Filter,
	TapZones = OPT.TapZones, Quality = OPT.Quality, GifCovers = OPT.GifCovers, BrightnessSwipe = OPT.BrightnessSwipe, PageNumber = OPT.PageNumber, PageTone = OPT.PageTone,
	RotateLock = OPT.AppRotation, LastOrientation = OPT.AppRotation,
	LibOpen = OPT.LibOpen, VolumeView = OPT.VolumeView, VolumeSort = OPT.VolumeSort, VolumeFilter = OPT.VolumeFilter, CoverTitles = OPT.CoverTitles
}
local RANGES = {Columns = {3, 9}, Margin = {0, 20}, StripWidth = {40, 100}, Brightness = {20, 100}, FilterStrength = {5, 80}, Preload = {1, 4}, ScrollStep = {25, 100}, AutoScrollSpeed = {1, 10}}

Settings = {}
Store.meta = {}      -- [seriesKey] = {added, cats = {name=true}, prefs = {}, lastRead, lastCh}
Store.progress = {}  -- [chapterKey] = {p = page, n = total, r = read, b = bookmark, t = stamp}
Store.cats = {}      -- ordered category names

local sanitizeSetting
sanitizeSetting = function(k, v)
	local d = DEFAULTS[k]
	if v == nil or type(v) ~= type(d) then return nil end
	if VALIDATE[k] and not table.find(VALIDATE[k], v) then return nil end
	if RANGES[k] then v = math.clamp(v, RANGES[k][1], RANGES[k][2]) end
	if k == "Accent" then
		local r, g, b = HexToRGB(v)
		if not r then return nil end
		return RGBToHex(r, g, b)
	end
	if k == "UserPresets" then
		local out = {}
		for _, p in ipairs(v) do
			if type(p) == "table" and type(p.name) == "string" and p.name ~= "" and type(p.v) == "table" then
				local vals = {}
				for _, key in ipairs(PRESET_KEYS) do
					local val = p.v[key]
					if val ~= nil then
						local ok = sanitizeSetting(key, val)
						if ok ~= nil then vals[key] = ok end
					end
				end
				out[#out + 1] = {name = p.name, v = vals}
			end
		end
		return out
	end
	if k == "TapGrid" then
		if #v ~= 9 then return nil end
		for i = 1, 9 do
			if not table.find(OPT.TapAction, v[i]) then return nil end
		end
	end
	return v
end

function Store.load()
	for k, v in pairs(DEFAULTS) do
		Settings[k] = type(v) == "table" and table.shallow(v) or v
	end
	local s = LoadTable(SETTINGS_PATH)
	if s then
		for k, v in pairs(s) do
			if DEFAULTS[k] ~= nil then
				local ok = sanitizeSetting(k, v)
				if ok ~= nil then Settings[k] = ok end
			end
		end
	end
	local m = LoadTable(META_PATH)
	if m then
		Store.meta = type(m.meta) == "table" and m.meta or {}
		Store.cats = type(m.cats) == "table" and m.cats or {}
	end
	Store.progress = LoadTable(PROGRESS_PATH) or {}
	-- 1.4: "Landscape" used to mean "normal"; it now means fixed landscape, so move old
	-- values to "Same as app" so the reader follows auto-rotate
	if not Settings.OrientMigrated then
		if Settings.Rotation == 0 then Settings.Rotation = -1 end
		for _, m in pairs(Store.meta) do
			if m.prefs and m.prefs.Rotation == 0 then m.prefs.Rotation = -1 end
		end
		for _, p in ipairs(Settings.UserPresets) do
			if p.v and p.v.Rotation == 0 then p.v.Rotation = -1 end
		end
		Settings.OrientMigrated = true
		Store.mark("all")
	end
	-- Beta 1.0: the auto-rotate portrait direction was backwards in 1.4.0 (fixed in Orient.classify),
	-- so a "flip" switched on as a workaround is reset
	if not Settings.FlipFixed then
		Settings.RotateFlip = false
		Settings.FlipFixed = true
		Store.mark("settings")
	end
	Store.apply()
end

-- Apply settings that affect global systems
function Store.apply()
	SetTheme(Settings.Theme, Settings.Accent)
	Input.setConfirm(Settings.Confirm)
end

local dirty = {}
local saveTimer = 0

function Store.mark(what)
	dirty[what or "all"] = true
	saveTimer = 2500
end

function Store.flush()
	if dirty.settings or dirty.all then SaveTable(SETTINGS_PATH, Settings) end
	if dirty.meta or dirty.all then SaveTable(META_PATH, {meta = Store.meta, cats = Store.cats}) end
	if dirty.progress or dirty.all then SaveTable(PROGRESS_PATH, Store.progress) end
	dirty = {}
	saveTimer = 0
end

function Store.update(dt)
	if saveTimer > 0 then
		saveTimer = saveTimer - dt
		if saveTimer <= 0 then Store.flush() end
	end
end

function Store.set(k, v)
	Settings[k] = v
	Store.mark("settings")
	if k == "Theme" or k == "Confirm" or k == "Accent" then Store.apply() end
end

-- Series metadata -------------------------------------------------------
function Store.series(key)
	local m = Store.meta[key]
	if not m then
		m = {added = Now(), cats = {}, prefs = {}}
		Store.meta[key] = m
		Store.mark("meta")
	end
	m.cats = m.cats or {}
	m.prefs = m.prefs or {}
	return m
end

-- Effective reader setting for a series (series override > global)
function Store.readerValue(seriesKey, k)
	local m = seriesKey and Store.meta[seriesKey]
	if m and m.prefs and m.prefs[k] ~= nil then return m.prefs[k] end
	return Settings[k]
end

function Store.setSeriesPref(seriesKey, k, v)
	local m = Store.series(seriesKey)
	m.prefs[k] = v
	Store.mark("meta")
end

function Store.clearSeriesPrefs(seriesKey)
	local m = Store.series(seriesKey)
	m.prefs = {}
	Store.mark("meta")
end

function Store.hasSeriesPrefs(seriesKey)
	local m = Store.meta[seriesKey]
	return m and m.prefs and next(m.prefs) ~= nil
end

-- Progress ------------------------------------------------------------------
function Store.chapter(key)
	return Store.progress[key]
end

function Store.setPage(seriesKey, chKey, page, total)
	local p = Store.progress[chKey]
	if not p then
		p = {}
		Store.progress[chKey] = p
	end
	p.p, p.n, p.t = page, total, Now()
	if total and total > 0 and page >= total then
		if not p.r then Store.addStats(seriesKey, 0, 0, 1) end
		p.r = true
	end
	local m = Store.series(seriesKey)
	m.lastRead, m.lastCh = p.t, chKey
	Store.mark("progress")
	Store.mark("meta")
end

function Store.setRead(chKey, read)
	local p = Store.progress[chKey]
	if not p then
		if not read then return end
		p = {}
		Store.progress[chKey] = p
	end
	p.r = read or nil
	if not read then p.p = nil end
	Store.mark("progress")
end

function Store.toggleBookmark(chKey)
	local p = Store.progress[chKey]
	if not p then
		p = {}
		Store.progress[chKey] = p
	end
	p.b = not p.b or nil
	Store.mark("progress")
	return p.b
end

-- Presets ------------------------------------------------------------------------
function Store.presets()
	local list = {}
	for _, p in ipairs(BUILTIN_PRESETS) do list[#list + 1] = p end
	for _, p in ipairs(Settings.UserPresets) do list[#list + 1] = p end
	return list
end

function Store.findPreset(name)
	for _, p in ipairs(Store.presets()) do
		if p.name == name then return p end
	end
end

-- Snapshot of the reader settings as seen by get(k)
function Store.capturePreset(get)
	local v = {}
	for _, k in ipairs(PRESET_KEYS) do v[k] = get(k) end
	return v
end

function Store.savePreset(name, values)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return false, "Give the preset a name" end
	for _, p in ipairs(BUILTIN_PRESETS) do
		if p.name:lower() == name:lower() then return false, "That name is used by a built-in preset" end
	end
	for _, p in ipairs(Settings.UserPresets) do
		if p.name:lower() == name:lower() then
			p.v = values
			Store.mark("settings")
			return true, "Updated preset " .. p.name
		end
	end
	table.insert(Settings.UserPresets, {name = name, v = values})
	Store.mark("settings")
	return true, "Saved preset " .. name
end

function Store.deletePreset(name)
	for i, p in ipairs(Settings.UserPresets) do
		if p.name == name then
			table.remove(Settings.UserPresets, i)
			Store.mark("settings")
			return true
		end
	end
	return false
end

function Store.renamePreset(old, new)
	new = (new or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if new == "" or Store.findPreset(new) then return false end
	for _, p in ipairs(Settings.UserPresets) do
		if p.name == old then
			p.name = new
			Store.mark("settings")
			return true
		end
	end
	return false
end

function Store.applyPresetToSeries(seriesKey, preset)
	local m = Store.series(seriesKey)
	for k, v in pairs(preset.v) do m.prefs[k] = v end
	m.asked = true
	Store.mark("meta")
end

function Store.applyPresetAsDefault(preset)
	for k, v in pairs(preset.v) do Settings[k] = v end
	Store.mark("settings")
end

-- Name of the preset matching what get(k) returns, or nil
function Store.matchPreset(get)
	local list = Store.presets()
	for i = #list, 1, -1 do -- prefer user presets
		local p = list[i]
		local same = next(p.v) ~= nil
		for k, v in pairs(p.v) do
			if get(k) ~= v then same = false break end
		end
		if same then return p.name end
	end
	return nil
end

-- Page bookmarks: progress[ch].pb = {[page] = true}
function Store.isPageBookmarked(chKey, page)
	local p = Store.progress[chKey]
	return p and p.pb and p.pb[page] == true or false
end

function Store.togglePageBookmark(chKey, page)
	local p = Store.progress[chKey]
	if not p then
		p = {}
		Store.progress[chKey] = p
	end
	p.pb = p.pb or {}
	if p.pb[page] then
		p.pb[page] = nil
		if next(p.pb) == nil then p.pb = nil end
		Store.mark("progress")
		return false
	end
	p.pb[page] = true
	Store.mark("progress")
	return true
end

function Store.pageBookmarks(chKey)
	local p = Store.progress[chKey]
	local out = {}
	if p and p.pb then
		for page in pairs(p.pb) do out[#out + 1] = page end
		table.sort(out)
	end
	return out
end

-- Reading statistics: meta.st = {t = ms, p = pages, c = chapters finished}
function Store.addStats(seriesKey, ms, pages, chapters)
	local m = Store.series(seriesKey)
	m.st = m.st or {t = 0, p = 0, c = 0}
	m.st.t = (m.st.t or 0) + (ms or 0)
	m.st.p = (m.st.p or 0) + (pages or 0)
	m.st.c = (m.st.c or 0) + (chapters or 0)
	Store.mark("meta")
end

function Store.stats(seriesKey)
	local m = Store.meta[seriesKey]
	return m and m.st or {t = 0, p = 0, c = 0}
end

function Store.totalStats()
	local t = {t = 0, p = 0, c = 0, series = 0}
	for _, m in pairs(Store.meta) do
		if m.st and ((m.st.t or 0) > 0 or (m.st.p or 0) > 0) then
			t.t = t.t + (m.st.t or 0)
			t.p = t.p + (m.st.p or 0)
			t.c = t.c + (m.st.c or 0)
			t.series = t.series + 1
		end
	end
	return t
end

function Store.clearStats()
	for _, m in pairs(Store.meta) do m.st = nil end
	Store.mark("meta")
end

function FormatDuration(ms)
	local mins = math.floor((ms or 0) / 60000)
	if mins < 1 then return "<1m" end
	local h, m = math.floor(mins / 60), mins % 60
	if h == 0 then return m .. "m" end
	return h .. "h " .. m .. "m"
end

-- Hiding from history keeps progress: only reading done after the stamp shows again
function Store.removeHistory(seriesKey)
	local m = Store.series(seriesKey)
	m.lastRead, m.lastCh = nil, nil
	m.hide = Now()
	Store.mark("meta")
end

function Store.clearHistory()
	local now = Now()
	for _, m in pairs(Store.meta) do
		m.lastRead, m.lastCh = nil, nil
		m.hide = now
	end
	Store.mark("meta")
end

-- Categories -----------------------------------------------------------------
function Store.addCategory(name)
	if not name or name == "" or table.find(Store.cats, name) or name == "All" then return false end
	Store.cats[#Store.cats + 1] = name
	Store.mark("meta")
	return true
end

function Store.removeCategory(name)
	local i = table.find(Store.cats, name)
	if i then table.remove(Store.cats, i) end
	for _, m in pairs(Store.meta) do
		if m.cats then m.cats[name] = nil end
	end
	Store.mark("meta")
end

function Store.renameCategory(old, new)
	local i = table.find(Store.cats, old)
	if not i or new == "" or table.find(Store.cats, new) or new == "All" then return false end
	Store.cats[i] = new
	for _, m in pairs(Store.meta) do
		if m.cats and m.cats[old] then
			m.cats[old] = nil
			m.cats[new] = true
		end
	end
	Store.mark("meta")
	return true
end

function Store.moveCategory(name, dir)
	local i = table.find(Store.cats, name)
	local j = i and i + dir
	if i and j >= 1 and j <= #Store.cats then
		Store.cats[i], Store.cats[j] = Store.cats[j], Store.cats[i]
		Store.mark("meta")
	end
end

-- Scan cache -----------------------------------------------------------------
function Store.loadScanCache()
	return LoadTable(CACHE_PATH)
end

function Store.saveScanCache(list)
	SaveTable(CACHE_PATH, list)
end

function Store.resetAll()
	Store.meta, Store.progress, Store.cats = {}, {}, {}
	Store.mark("all")
	Store.flush()
end
