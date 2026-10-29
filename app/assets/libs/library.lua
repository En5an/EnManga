-- Library model: series list, stats, filtering/sorting, background scan
Library = {series = {}, byKey = {}, scanning = false, scanMsg = "", scanProgress = 0, version = 0}

-- Carry settings over when files that used to be separate series are now grouped
local function migrateMeta(s)
	if Store.meta[s.key] then return end
	local m = Store.series(s.key)
	for _, ch in ipairs(s.chapters) do
		local om = ch.key ~= s.key and Store.meta[ch.key]
		if om then
			if om.added and om.added > 0 and om.added < m.added then m.added = om.added end
			for c in pairs(om.cats or {}) do m.cats[c] = true end
			if not next(m.prefs) and om.prefs and next(om.prefs) then m.prefs = table.shallow(om.prefs) end
			if om.st then
				m.st = m.st or {t = 0, p = 0, c = 0}
				m.st.t, m.st.p, m.st.c = (m.st.t or 0) + (om.st.t or 0), (m.st.p or 0) + (om.st.p or 0), (m.st.c or 0) + (om.st.c or 0)
			end
		end
	end
end

-- Short display names (original names are kept in .rawTitle / .raw)
function Library.applyNames(s)
	s.rawTitle = s.rawTitle or s.title
	for _, ch in ipairs(s.chapters) do ch.raw = ch.raw or ch.name end
	if Settings.CleanNames == false then
		s.title = s.rawTitle
		for _, ch in ipairs(s.chapters) do ch.name = ch.raw end
		return
	end
	s.title = Scanner.cleanTitle(s.rawTitle)
	-- unit from the original names (they carry "v01", "Vol", "巻")
	local saved = {}
	for i, ch in ipairs(s.chapters) do saved[i] = ch.name ch.name = ch.raw end
	local unit = Library.unitName(s):match("(%a+)s?$") or "volume"
	unit = unit:gsub("s$", "")
	for _, ch in ipairs(s.chapters) do
		ch.name = Scanner.volumeLabel(ch.raw, s.title, unit)
	end
end

function Library.renameAll()
	for _, s in ipairs(Library.series) do Library.applyNames(s) end
	table.sort(Library.series, function(a, b) return NaturalLess(a.title, b.title) end)
	Library.version = Library.version + 1
end

function Library.set(list)
	-- keep cover locations already found for series / volumes that still exist
	local old = Library.byKey or {}
	for _, s in ipairs(list or {}) do
		local o = old[s.key]
		if o then
			if not s.cover and o.cover then s.cover = o.cover end
			local oc = {}
			for _, ch in ipairs(o.chapters) do oc[ch.key] = ch.cover end
			for _, ch in ipairs(s.chapters) do
				if not ch.cover and oc[ch.key] then ch.cover = oc[ch.key] end
			end
		end
	end
	Library.series = list or {}
	Library.byKey = {}
	for _, s in ipairs(Library.series) do
		Library.byKey[s.key] = s
		Library.applyNames(s)
		for i, ch in ipairs(s.chapters) do ch.index = i end
		migrateMeta(s)
		Store.series(s.key) -- ensure metadata (date added) exists
	end
	Library.version = Library.version + 1
end

-- Most recently read chapter of a series, from the reading progress itself
function Library.lastActivity(s)
	local m = Store.meta[s.key]
	local hide = m and m.hide or 0
	local bestT, bestI = 0, nil
	for i, ch in ipairs(s.chapters) do
		local p = Store.progress[ch.key]
		if p and p.t and p.t > bestT and p.t > hide then
			bestT, bestI = p.t, i
		end
	end
	return bestT, bestI
end

-- "volumes" or "chapters", from how the entries are named
function Library.unitName(s, n)
	n = n or #s.chapters
	local vol = 0
	for i = 1, math.min(#s.chapters, 12) do
		local nm = (s.chapters[i].raw or s.chapters[i].name):lower()
		if nm:find("vol") or nm:find("^v%.?%s*%d") or nm:find("[%s_%-]v%.?%s*%d") or nm:find("tome") or nm:find("巻") then vol = vol + 1 end
	end
	local word = (#s.chapters == 1 or vol * 2 >= math.min(#s.chapters, 12)) and "volume" or "chapter"
	return n .. " " .. word .. (n == 1 and "" or "s")
end

function Library.stats(s)
	local total, read, started, marked = #s.chapters, 0, 0, false
	for _, ch in ipairs(s.chapters) do
		local p = Store.progress[ch.key]
		if p then
			if p.r then read = read + 1 elseif p.p and p.p > 1 then started = started + 1 end
			if p.b or p.pb then marked = true end
		end
	end
	local m = Store.meta[s.key] or {}
	local lastT = Library.lastActivity(s)
	return {
		total = total, read = read, unread = total - read, started = started, bookmarked = marked,
		lastRead = lastT, added = m.added or 0
	}
end

local function matches(s, st, filter, cat, query)
	if cat and cat ~= "All" then
		local m = Store.meta[s.key]
		if not (m and m.cats and m.cats[cat]) then return false end
	end
	if filter == "Unread" and st.unread == 0 then return false end
	if filter == "In progress" and not ((st.read > 0 or st.started > 0) and st.unread > 0) then return false end
	if filter == "Completed" and st.unread > 0 then return false end
	if filter == "Bookmarked" and not st.bookmarked then return false end
	if query and query ~= "" then
		local q = query:lower()
		if not s.title:lower():find(q, 1, true) and not (s.rawTitle or ""):lower():find(q, 1, true) then return false end
	end
	return true
end

-- Returns array of {s = series, st = stats}
function Library.view(cat, filter, sort, desc, query)
	local out = {}
	for _, s in ipairs(Library.series) do
		local st = Library.stats(s)
		if matches(s, st, filter, cat, query) then
			out[#out + 1] = {s = s, st = st}
		end
	end
	local cmp
	if sort == "Last read" then
		cmp = function(a, b)
			if a.st.lastRead ~= b.st.lastRead then return a.st.lastRead > b.st.lastRead end
			return NaturalLess(a.s.title, b.s.title)
		end
	elseif sort == "Date added" then
		cmp = function(a, b)
			if a.st.added ~= b.st.added then return a.st.added > b.st.added end
			return NaturalLess(a.s.title, b.s.title)
		end
	elseif sort == "Unread" then
		cmp = function(a, b)
			if a.st.unread ~= b.st.unread then return a.st.unread > b.st.unread end
			return NaturalLess(a.s.title, b.s.title)
		end
	elseif sort == "Chapters" then
		cmp = function(a, b)
			if a.st.total ~= b.st.total then return a.st.total > b.st.total end
			return NaturalLess(a.s.title, b.s.title)
		end
	else
		cmp = function(a, b) return NaturalLess(a.s.title, b.s.title) end
	end
	table.sort(out, cmp)
	if desc then table.reverse(out) end
	return out
end

-- Where to continue a series: chapter index, page
function Library.resumePoint(s)
	local _, last = Library.lastActivity(s)
	if last then
		for i, ch in ipairs(s.chapters) do
			if i == last then
				local p = Store.progress[ch.key]
				if p and p.r then
					-- finished that chapter: continue with the next unread one after it
					for j = i + 1, #s.chapters do
						local pj = Store.progress[s.chapters[j].key]
						if not (pj and pj.r) then return j, (pj and pj.p) or 1 end
					end
					return i, 1
				end
				return i, (p and p.p) or 1
			end
		end
	end
	for i, ch in ipairs(s.chapters) do
		local p = Store.progress[ch.key]
		if not (p and p.r) then return i, (p and p.p) or 1 end
	end
	return 1, 1
end

function Library.resumeLabel(s)
	local i = Library.resumePoint(s)
	local ch = s.chapters[i]
	local _, last = Library.lastActivity(s)
	if not last then return "Start reading" end
	return "Continue · " .. (ch and ch.name or "")
end

-- Resume target with page info: chapter index, page, label
function Library.resumeInfo(s)
	local i, page = Library.resumePoint(s)
	local _, last = Library.lastActivity(s)
	local ch = s.chapters[i]
	local p = ch and Store.progress[ch.key]
	local detail = nil
	if last and p and p.n and p.n > 0 and not p.r then
		detail = "Page " .. (p.p or 1) .. " of " .. p.n
	end
	return i, page, last ~= nil, ch and ch.name or "", detail
end

-- Background scan; steps run from Library.update within a time budget
local scanCo = nil
local scanDone = nil
function Library.rescan(onDone)
	if scanCo then return end
	Library.scanning = true
	Library.scanMsg, Library.scanProgress = "Scanning...", 0
	scanDone = onDone
	scanCo = coroutine.create(function()
		return Scanner.scan(Settings.Folders)
	end)
end

local coverSaveTimer = 0
function Library.update(budgetMs)
	-- save newly found cover locations every few seconds
	coverSaveTimer = coverSaveTimer + 16
	if Covers.dirty and not scanCo and coverSaveTimer > 4000 then
		coverSaveTimer = 0
		Covers.dirty = false
		Store.saveScanCache(Library.series)
	end
	if not scanCo then return end
	local t = Timer.new()
	repeat
		local ok, a, b = coroutine.resume(scanCo)
		if not ok then
			Log("scan error: " .. tostring(a))
			scanCo = nil
			Library.scanning = false
			UI.toast("Scan failed — see log.txt")
			break
		end
		if coroutine.status(scanCo) == "dead" then
			scanCo = nil
			Library.scanning = false
			local list, roots = a, b
			local oldByKey = Library.byKey
			Library.set(list)
			Covers.afterScan(oldByKey)
			Store.saveScanCache(list)
			if scanDone then scanDone(list, roots) end
			scanDone = nil
			break
		else
			Library.scanMsg, Library.scanProgress = a or "", b or 0
		end
	until Timer.getTime(t) > (budgetMs or 8)
	Timer.destroy(t)
end

-- Run a scan to completion, drawing progress (used at boot)
function Library.scanBlocking(draw)
	Library.rescan()
	while Library.scanning do
		Library.update(30)
		if draw then draw(Library.scanMsg, Library.scanProgress) end
	end
end

------------------------------------------------------------------------
-- On-screen keyboard prompt (system IME runs over our frames)
------------------------------------------------------------------------
local kbCallback = nil
function UI.prompt(title, initial, cb)
	if kbCallback then return end
	local ok = pcall(Keyboard.show, title, initial or "", 128, TYPE_DEFAULT, MODE_TEXT, OPT_NO_AUTOCAP)
	if ok then kbCallback = cb end
end

function UI.keyboardActive()
	return kbCallback ~= nil
end

function UI.updateKeyboard()
	if not kbCallback then return false end
	local st = Keyboard.getState()
	if st == RUNNING then return true end
	local cb = kbCallback
	kbCallback = nil
	local text = nil
	if st == FINISHED then text = Keyboard.getInput() end
	Keyboard.clear()
	Input.blocked = 3
	if text ~= nil then
		local ok, e = pcall(cb, text)
		if not ok then Log("prompt cb: " .. tostring(e)) end
	end
	return false
end
