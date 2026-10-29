-- Async image loader (one async operation at a time, as the runtime requires).
-- Derived from NOBORU's Threads (net.lua), reduced to local files and extended
-- with priorities, cancellation, a VRAM guard and webtoon slicing.
Loader = {}

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local getAsyncState, getAsyncResult = System.getAsyncState, System.getAsyncResult
local doesFileExist = System.doesFileExist

local TMP = DATA_DIR .. "/temp/page.img"
local MAX_TEX = 4096
local VRAM_RESERVE = 10 * 1024 * 1024

local queue = {}
local current = nil
local seq = 0

local function texBytes(w, h)
	return (floor(w + 7) - floor(w + 7) % 8) * h * 4 + 1024
end

local function freeMemory()
	local ok, m = pcall(Graphics.getFreeMemory)
	if ok and m then return m end
	return 64 * 1024 * 1024
end

-- task fields: key, path, extract (zip entry), maxSide, priority, onDone(result, info, err)
function Loader.add(task)
	if task.key then
		for i = 1, #queue do
			if queue[i].key == task.key then
				queue[i].priority = min(queue[i].priority or 100, task.priority or 100)
				return queue[i]
			end
		end
		if current and current.key == task.key and not current.cancelled then
			return current
		end
	end
	seq = seq + 1
	task.seq = seq
	task.priority = task.priority or 100
	queue[#queue + 1] = task
	return task
end

function Loader.setPriority(key, p)
	for i = 1, #queue do
		if queue[i].key == key then queue[i].priority = p end
	end
end

function Loader.cancel(key)
	for i = #queue, 1, -1 do
		if queue[i].key == key then table.remove(queue, i) end
	end
	if current and current.key == key then
		current.cancelled = true
	end
end

-- Cancel every queued task whose key starts with prefix
function Loader.cancelPrefix(prefix)
	for i = #queue, 1, -1 do
		local k = queue[i].key
		if type(k) == "string" and k:find(prefix, 1, true) == 1 then table.remove(queue, i) end
	end
	if current and type(current.key) == "string" and current.key:find(prefix, 1, true) == 1 then
		current.cancelled = true
	end
end

function Loader.busy()
	return current ~= nil or #queue > 0
end

function Loader.pending()
	return #queue + (current and 1 or 0)
end

function Loader.isLoading(key)
	if current and current.key == key and not current.cancelled then return true end
	for i = 1, #queue do
		if queue[i].key == key then return true end
	end
	return false
end

local function finish(task, result, info, err)
	current = nil
	if task.cancelled then
		if result then
			if result.free then
				result:free()
			elseif type(result) == "table" then
				for i = 1, #result do
					if result[i] and result[i].free then result[i]:free() end
				end
			end
		end
		return
	end
	if err then
		Log("load: " .. tostring(err) .. " (" .. tostring(task.extract or task.path) .. ")")
	end
	if task.onDone then
		local ok, e = pcall(task.onDone, result, info, err)
		if not ok then Log("onDone: " .. tostring(e)) end
	end
end

local function pickNext()
	if #queue == 0 then return nil end
	local best, bi = nil, nil
	for i = 1, #queue do
		local t = queue[i]
		if not best or t.priority < best.priority or (t.priority == best.priority and t.seq < best.seq) then
			best, bi = t, i
		end
	end
	table.remove(queue, bi)
	return best
end

local function startDecode(task)
	local path = task.file
	local w, h = System.getPictureResolution(path)
	if not w or not h or w <= 0 or h <= 0 or w > 65535 or h > 65535 then
		return finish(task, nil, nil, "unreadable image")
	end
	task.ow, task.oh = w, h
	local free = freeMemory() - VRAM_RESERVE
	local want = texBytes(math.min(w, MAX_TEX), math.min(h, MAX_TEX))
	if Loader.onLowMemory and not task.lowMemRetried and want > free then
		task.lowMemRetried = true
		Loader.onLowMemory(task, want - free)
		free = freeMemory() - VRAM_RESERVE
	end
	-- Tall strips: keep full width and load in slices of <= 4096px
	if h > MAX_TEX and h / w > 2 and w <= MAX_TEX and not task.noSlice then
		if texBytes(w, h) > free then
			return finish(task, nil, nil, "not enough memory")
		end
		local parts = ceil(h / MAX_TEX)
		task.slices = {Parts = parts, SliceHeight = floor(h / parts), Width = w, Height = h}
		task.part = 0
		task.stage = "slice"
		Loader._nextSlice(task)
		return
	end
	local s = 1
	local limit = task.maxSide and task.maxSide * 1.25 or nil
	while s < 64 and (w / s > MAX_TEX or h / s > MAX_TEX or (limit and max(w, h) / s > limit) or texBytes(w / s, h / s) > free) do
		s = s * 2
	end
	if texBytes(w / s, h / s) > free then
		return finish(task, nil, nil, "not enough memory")
	end
	task.scale = s
	task.stage = "decode"
	Graphics.loadImageAsync(path, s)
end

function Loader._nextSlice(task)
	local sl = task.slices
	local i = task.part
	local y = sl.SliceHeight * i
	local hh = (i == sl.Parts - 1) and (sl.Height - y) or sl.SliceHeight
	Graphics.loadPartImageAsync(task.file, 0, y, sl.Width, hh)
end

local function start(task)
	current = task
	if task.unsupported then
		return finish(task, nil, nil, task.unsupported)
	end
	if task.gif then
		-- animated GIF: every frame becomes a full-size texture
		if not doesFileExist(task.path) then return finish(task, nil, nil, "file missing") end
		if (task.need or 0) > freeMemory() - VRAM_RESERVE - 24 * 1024 * 1024 then
			return finish(task, nil, nil, "not enough memory for animation")
		end
		if not Graphics.loadGifAsync then return finish(task, nil, nil, "no GIF support") end
		task.stage = "gif"
		Graphics.loadGifAsync(task.path)
		return
	end
	if task.extract then
		task.stage = "extract"
		task.file = TMP
		System.extractFromZipAsync(task.path, task.extract, TMP)
	else
		if not doesFileExist(task.path) then
			return finish(task, nil, nil, "file missing")
		end
		task.file = task.path
		startDecode(task)
	end
end

local function step(task)
	if task.stage == "extract" then
		if getAsyncState() < 0 or not doesFileExist(TMP) then
			return finish(task, nil, nil, "extract failed")
		end
		if task.cancelled then
			return finish(task, nil, nil, nil)
		end
		startDecode(task)
	elseif task.stage == "decode" then
		local res = getAsyncResult()
		local tex = res and tonumber(res)
		if not tex then
			return finish(task, nil, nil, "cannot decode (unsupported format?)")
		end
		local img = Image:new(tex, FILTER_LINEAR)
		finish(task, img, {w = task.ow, h = task.oh, tw = img.Width, th = img.Height}, nil)
	elseif task.stage == "gif" then
		local res = getAsyncResult()
		local ptr = res and tonumber(res)
		if not ptr then return finish(task, nil, nil, "cannot decode GIF") end
		local ok, t = pcall(Graphics.returnGif, ptr)
		if not ok or type(t) ~= "table" or not t.frames or t.frames < 1 then
			return finish(task, nil, nil, "cannot read GIF frames")
		end
		local frames, delays = {}, {}
		for i = 1, t.frames do
			local f = t[i]
			local img = f and Image:new(tonumber(f.image), FILTER_LINEAR)
			if img then
				frames[#frames + 1] = img
				local d = tonumber(f.delay) or 100
				delays[#delays + 1] = d < 20 and 100 or d
			end
		end
		if #frames == 0 then return finish(task, nil, nil, "empty GIF") end
		if task.cancelled then
			for _, f in ipairs(frames) do f:free() end
			return finish(task, nil, nil, nil)
		end
		finish(task, {frames = frames, delays = delays}, nil, nil)
	elseif task.stage == "slice" then
		local res = getAsyncResult()
		local tex = res and tonumber(res)
		if not tex then
			local sl = task.slices
			for i = 1, #sl do if sl[i] and sl[i].free then sl[i]:free() end end
			return finish(task, nil, nil, "cannot decode slice")
		end
		task.part = task.part + 1
		task.slices[task.part] = Image:new(tex, FILTER_LINEAR)
		if task.cancelled then
			return finish(task, task.slices, nil, nil)
		end
		if task.part >= task.slices.Parts then
			local sl = task.slices
			finish(task, sl, {w = sl.Width, h = sl.Height, tw = sl.Width, th = sl.Height, sliced = true}, nil)
		else
			Loader._nextSlice(task)
		end
	end
end

-- Call once per frame. Works for up to BUDGET ms: small images (covers) finish
-- several per frame instead of one step per frame.
local BUDGET_MS, MAX_POLLS = 6, 4000
local budgetTimer = Timer.new()
function Loader.update()
	Timer.reset(budgetTimer)
	local polls, steps = 0, 0
	while steps < 24 do
		if current then
			if getAsyncState() == 0 then
				polls = polls + 1
				if polls > MAX_POLLS or Timer.getTime(budgetTimer) >= BUDGET_MS then return end
			else
				step(current)
				steps = steps + 1
			end
		else
			if Timer.getTime(budgetTimer) >= BUDGET_MS then return end
			local t = pickNext()
			if not t then return end
			start(t)
			steps = steps + 1
		end
	end
end

-- Block until idle (used when leaving the app)
function Loader.drain()
	queue = {}
	if current then current.cancelled = true end
	local guard = 0
	while current and guard < 2000 do
		Loader.update()
		guard = guard + 1
	end
end
