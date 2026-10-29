-- Cover thumbnails: resolved lazily, loaded async, LRU-limited
Covers = {}

-- Covers stay loaded for the whole session (so a series opened once shows its covers
-- instantly next time), limited by the video memory they use. Reading pages take
-- priority: when a page needs room, the least recently seen covers are dropped first.
local MAX_LOADED = 1200
local BUDGET = 56 * 1024 * 1024
local loadedBytes = 0
local entries = {}  -- [seriesKey] = {img, state = "loading"|"ready"|"failed", used}
local frame = 0
local resolvesThisFrame = 0
local resolveTimer = Timer.new()
local RESOLVE_MS, RESOLVE_MAX = 5, 8
Covers.dirty = false -- resolved cover locations not yet saved

local animTick
function Covers.tick()
	if animTick then animTick() end
	frame = frame + 1
	resolvesThisFrame = 0
	Timer.reset(resolveTimer)
end

local function dropEntry(k, e)
	if e.img then
		e.img:free()
		loadedBytes = loadedBytes - (e.bytes or 0)
	end
	entries[k] = nil
end

-- free least-recently-used covers (never ones drawn this frame or the last)
-- until 'need' bytes are released and the count / byte limits hold
local function evict(need)
	need = need or 0
	local count = 0
	for _, e in pairs(entries) do if e.state == "ready" then count = count + 1 end end
	if need <= 0 and count <= MAX_LOADED and loadedBytes <= BUDGET then return 0 end
	local loaded = {}
	for k, e in pairs(entries) do
		if e.state == "ready" and e.used < frame - 1 then loaded[#loaded + 1] = {k = k, used = e.used} end
	end
	table.sort(loaded, function(a, b) return a.used < b.used end)
	local freed = 0
	for _, it in ipairs(loaded) do
		if freed >= need and count <= MAX_LOADED and loadedBytes <= BUDGET then break end
		local e = entries[it.k]
		freed = freed + (e.bytes or 0)
		count = count - 1
		dropEntry(it.k, e)
	end
	return freed
end

-- Where a cover image lives. The answer is stored on the series / chapter so it is
-- saved with the library and the archive never has to be listed again.
local function resolveSource(series)
	if series.cover then return series.cover, true end
	local ch = series.chapters and series.chapters[1]
	if not ch then return nil end
	if ch.cover then
		-- a volume's own cover (also used for a series that has no cover image of its own)
		series.cover = ch.cover
		return series.cover, true
	end
	local p = Scanner.firstPage(ch)
	if p then
		series.cover = {path = p.path, extract = p.extract}
		if series.volume then ch.cover = series.cover end
		Covers.dirty = true
		return series.cover, false
	end
	return nil
end

-- Returns Image or nil; schedules a load when needed. priority: lower = sooner
function Covers.get(series, priority)
	local key = series.key
	local e = entries[key]
	if e then
		e.used = frame
		if e.state == "loading" and priority then
			Loader.setPriority("cover:" .. key, 50 + priority)
		end
		return e.img
	end
	-- resolving may list an archive: limit the time spent per frame
	if resolvesThisFrame >= RESOLVE_MAX or (resolvesThisFrame > 0 and Timer.getTime(resolveTimer) >= RESOLVE_MS) then return nil end
	resolvesThisFrame = resolvesThisFrame + 1
	e = {state = "loading", used = frame}
	entries[key] = e
	local src, cached = resolveSource(series)
	if not src then
		e.state = "failed"
		return nil
	end
	local name = src.extract and BaseName(src.extract) or BaseName(src.path)
	Loader.add {
		key = "cover:" .. key,
		path = src.path,
		extract = src.extract,
		maxSide = 280,
		noSlice = true,
		priority = 50 + (priority or 50),
		unsupported = IsUnsupportedImage(name) and "webp not supported" or nil,
		onDone = function(img, info, err)
			if entries[key] ~= e then
				if img then img:free() end
				return
			end
			if img then
				e.img = img
				e.state = "ready"
				e.bytes = img.Memory or (img.Width or 0) * (img.Height or 0) * 4
				loadedBytes = loadedBytes + e.bytes
				evict()
			elseif cached and not series.coverRetried and not series.fixedCover then
				-- remembered location is stale (file replaced): look it up again
				series.coverRetried = true
				series.cover = nil
				if series.volume and series.chapters[1] then series.chapters[1].cover = nil end
				entries[key] = nil
			else
				e.state = "failed"
			end
		end
	}
	return nil
end

function Covers.state(series)
	local e = entries[series.key]
	return e and e.state
end

-- Load without drawing (preloading). Never costs more than one resolve.
function Covers.prefetch(series, priority)
	if entries[series.key] then
		entries[series.key].used = frame
		return
	end
	Covers.get(series, priority)
end

-- Keep only the most recently used n covers (used when the reader needs memory)
function Covers.trim(n)
	local loaded = {}
	for k, e in pairs(entries) do loaded[#loaded + 1] = {k = k, used = e.used} end
	table.sort(loaded, function(a, b) return a.used > b.used end)
	for i = n + 1, #loaded do
		dropEntry(loaded[i].k, entries[loaded[i].k])
	end
	Loader.cancelPrefix("cover:")
	for k, e in pairs(entries) do
		if e.state == "loading" then entries[k] = nil end
	end
end

-- Pages come first: when a page would not fit in video memory, drop the covers seen
-- longest ago until it does (everything, if that is what it takes)
Loader.onLowMemory = function(task, need)
	if Covers.stopAnimations then Covers.stopAnimations() end
	local freed = evict((need or 0) + 4 * 1024 * 1024)
	if need and freed < need then Covers.clear() end
end

function Covers.memory()
	local n = 0
	for _, e in pairs(entries) do if e.state == "ready" then n = n + 1 end end
	return n, loadedBytes
end

-- After a rescan: keep covers that are still valid, drop only those whose series is gone
-- or whose cover image changed (so going back to the library doesn't reload everything)
local function coverSig(s)
	if not s then return nil end
	local c = s.cover
	if c then return c.path .. "!" .. (c.extract or "") end
	local ch = s.chapters and s.chapters[1]
	return ch and ("first:" .. ch.key) or nil
end
function Covers.afterScan(oldByKey)
	local chapters = {}
	for _, s in ipairs(Library.series) do
		for _, ch in ipairs(s.chapters) do chapters[ch.key] = true end
	end
	local dropped = 0
	for k, e in pairs(entries) do
		local keep
		if k:sub(1, 4) == "vol:" then
			keep = chapters[k:sub(5)] == true
		else
			local new = Library.byKey[k]
			keep = new ~= nil and coverSig(new) == coverSig(oldByKey and oldByKey[k])
		end
		if not keep then
			Loader.cancel("cover:" .. k)
			dropEntry(k, e)
			dropped = dropped + 1
		end
	end
	return dropped
end

function Covers.clear()
	if Covers.stopAnimations then Covers.stopAnimations() end
	Loader.cancelPrefix("cover:")
	for _, e in pairs(entries) do
		if e.img then e.img:free() end
	end
	entries = {}
	loadedBytes = 0
end

-- Draw cover cropped to fill (w x h) at (x, y); placeholder when not ready
------------------------------------------------------------------------
-- Animated GIF covers (cover.gif in a series or volume folder).
-- The static first frame is always shown first; the animation is loaded on top of it
-- when Settings.GifCovers allows (Off / Hover = only the selected cover / Always).
-- GIF frames are full-size textures, so each animation is checked against a memory
-- budget before it is loaded, and all animations are dropped when the reader opens.
------------------------------------------------------------------------
local anims = {}            -- [key] = {state, frames, delays, total, start, used, bytes, path}
local animBytes = 0
local ANIM_ONE_MAX = 32 * 1024 * 1024
local ANIM_BUDGET = 48 * 1024 * 1024
local ANIM_KEEP_MS = 8000   -- hover mode: keep a recently hovered animation this long
local gifInfoCache = {}
local band = bit32.band

local function texBytes(w, h)
	return (band(w + 7, bit32.bnot(7))) * h * 4 + 1024
end

-- width, height and frame count of a GIF file, without decoding it
local function gifInfo(path)
	local c = gifInfoCache[path]
	if c ~= nil then return c end
	c = false
	local ok, d = pcall(ReadFile, path)
	if ok and d and #d > 13 and d:sub(1, 3) == "GIF" then
		local byte = string.byte
		local w = byte(d, 7) + byte(d, 8) * 256
		local h = byte(d, 9) + byte(d, 10) * 256
		local pos = 14
		local flags = byte(d, 11)
		if band(flags, 0x80) ~= 0 then pos = pos + 3 * 2 ^ (band(flags, 7) + 1) end
		local frames, n = 0, #d
		local function skipBlocks()
			while pos <= n do
				local len = byte(d, pos)
				pos = pos + 1
				if len == 0 then return end
				pos = pos + len
			end
		end
		while pos <= n do
			local b = byte(d, pos)
			if b == 0x2C then
				frames = frames + 1
				local lf = byte(d, pos + 9) or 0
				pos = pos + 10
				if band(lf, 0x80) ~= 0 then pos = pos + 3 * 2 ^ (band(lf, 7) + 1) end
				pos = pos + 1 -- LZW code size
				skipBlocks()
			elseif b == 0x21 then
				pos = pos + 2
				skipBlocks()
			else
				break -- 0x3B trailer or junk
			end
		end
		if w > 0 and h > 0 then c = {w = w, h = h, frames = frames} end
	end
	gifInfoCache[path] = c
	return c
end
Covers._gifInfo = gifInfo

local function freeAnim(key)
	local a = anims[key]
	if not a then return end
	if a.frames then
		for _, f in ipairs(a.frames) do f:free() end
		animBytes = animBytes - (a.bytes or 0)
	end
	if a.state == "loading" then Loader.cancel("anim:" .. key) end
	anims[key] = nil
end

function Covers.stopAnimations()
	for k in pairs(anims) do freeAnim(k) end
end

-- make room for 'need' bytes of animation by dropping the least recently shown ones
local function animRoom(need)
	if animBytes + need <= ANIM_BUDGET then return true end
	local list = {}
	for k, a in pairs(anims) do
		if a.state == "ready" and a.used < frame - 1 then list[#list + 1] = {k = k, used = a.used} end
	end
	table.sort(list, function(a, b) return a.used < b.used end)
	for _, it in ipairs(list) do
		freeAnim(it.k)
		if animBytes + need <= ANIM_BUDGET then return true end
	end
	return animBytes + need <= ANIM_BUDGET
end

local function now() return Timer.getTime(GlobalTimer) end

-- current animation frame for an entity, or nil (then the static cover is drawn)
local function animFrame(series)
	local key = series.key
	local a = anims[key]
	if a then
		a.used = frame
		a.seen = now()
		if a.state ~= "ready" then return nil end
		local t = (now() - a.start) % a.total
		for i = 1, #a.frames do
			t = t - a.delays[i]
			if t < 0 then return a.frames[i] end
		end
		return a.frames[#a.frames]
	end
	local src = series.cover
	if not src or src.extract or Ext(src.path) ~= "gif" then return nil end
	-- only once the static cover is on screen
	local e = entries[key]
	if not e or e.state ~= "ready" then return nil end
	local info = gifInfo(src.path)
	local frames = info and math.min(info.frames, 128) or 0
	local bytes = info and frames * texBytes(info.w, info.h) or 0
	if not info or frames < 2 or info.w > 4096 or info.h > 4096 or bytes > ANIM_ONE_MAX then
		anims[key] = {state = "static", used = frame, seen = now()}
		return nil
	end
	if not animRoom(bytes) then return nil end
	a = {state = "loading", used = frame, seen = now(), bytes = bytes}
	anims[key] = a
	Loader.add {
		key = "anim:" .. key,
		path = src.path,
		gif = true,
		need = bytes,
		priority = 70,
		onDone = function(res, info2, err)
			if anims[key] ~= a then
				if res then for _, f in ipairs(res.frames) do f:free() end end
				return
			end
			if not res then
				a.state = "static"
				return
			end
			a.frames, a.delays, a.total = res.frames, res.delays, 0
			a.bytes = 0
			for i, f in ipairs(a.frames) do
				a.total = a.total + a.delays[i]
				a.bytes = a.bytes + (f.Memory or 0)
			end
			animBytes = animBytes + a.bytes
			a.start = now()
			a.state = "ready"
		end
	}
	return nil
end

-- per frame: drop animations nobody is looking at
function animTick()
	local t = now()
	local always = Settings.GifCovers == "Always"
	for k, a in pairs(anims) do
		if a.state == "loading" and a.used < frame - 30 then
			freeAnim(k)
		elseif a.state == "ready" and a.used < frame - 1 then
			if not always and t - (a.seen or 0) > ANIM_KEEP_MS then freeAnim(k) end
			if always and t - (a.seen or 0) > ANIM_KEEP_MS * 2 then freeAnim(k) end
		elseif a.state == "static" and t - (a.seen or 0) > 60000 then
			anims[k] = nil -- try again some time later (memory may be free by then)
		end
	end
end

function Covers._anim(key) return anims[key] end
function Covers._setKeep(ms) ANIM_KEEP_MS = ms end
function Covers.animMemory()
	local n = 0
	for _, a in pairs(anims) do if a.state == "ready" then n = n + 1 end end
	return n, animBytes
end

-- animate: this cover is the selected one (Settings.GifCovers "Hover") or any visible
-- cover ("Always") may play its GIF animation
function Covers.draw(series, x, y, w, h, priority, alpha, animate)
	local img = Covers.get(series, priority)
	local mode = Settings.GifCovers
	if img and mode ~= "Off" and (animate or mode == "Always") then
		img = animFrame(series) or img
	end
	if img and img.e then
		local iw, ih = img.Width, img.Height
		local s = math.max(w / iw, h / ih)
		local sw, sh = w / s, h / s
		local sx, sy = (iw - sw) / 2, (ih - sh) / 2
		if sy > 0 then sy = sy * 0.3 end -- favour the top of tall covers
		sx, sy = math.max(0, math.floor(sx)), math.max(0, math.floor(sy))
		sw, sh = math.min(sw, iw - sx), math.min(sh, ih - sy)
		UI.imageExt(x + w / 2, y + h / 2, img.e, sx, sy, sw, sh, s, s, alpha and Color.new(255, 255, 255, alpha) or Color.new(255, 255, 255))
	else
		UI.rect(x, y, w, h, C.surface2)
		local lines = UI.wrap(FONT.s, series.title, w - 16, 4)
		for i, l in ipairs(lines) do
			UI.text(FONT.s, x + 8, y + 8 + (i - 1) * 19, l, C.sub)
		end
	end
end
