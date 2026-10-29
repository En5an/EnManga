-- Reader: paged (RTL/LTR/vertical) and continuous (webtoon / long strip)
-- Everything is laid out in a *logical* screen (LW x LH) which is rotated onto
-- the physical 960x544 display for portrait reading.
Reader = {}
local ReaderScreen = {}
Reader.screen = ReaderScreen

local floor, ceil, min, max, abs, sqrt = math.floor, math.ceil, math.min, math.max, math.abs, math.sqrt
local drawExt = Graphics.drawImageExtended
local band, rshift = bit32.band, bit32.rshift

local R = {}
local cfg = {}
local rot, LW, LH, ANG = 0, PHYS_W, PHYS_H, 0
local TINT = Color.new(255, 255, 255)
local ZERO_CROP = {l = 0, t = 0, r = 0, b = 0}
local QUALITY_MAX = {Full = nil, High = 2048, Balanced = 1280}
local FILTER_RGB = {Warm = {255, 160, 60}, Sepia = {150, 100, 40}, Night = {255, 70, 0}, Paper = {245, 228, 190}}
local BG_RGB = {Black = {0, 0, 0}, Gray = {64, 64, 68}, White = {255, 255, 255}}
-- Page tones multiply page colours: white paper takes the tone, black ink stays black
local TONE_RGB = {Normal = {255, 255, 255}, Sepia = {255, 228, 184}, Warm = {255, 236, 205}, Cool = {214, 230, 255}, Mint = {218, 242, 222}}
local STAT_IDLE_MS = 120000
local sessionSeq = 0

------------------------------------------------------------------------
-- Coordinate transforms (logical <-> physical)
------------------------------------------------------------------------
-- Pages are placed with toPhys (logical page space -> physical screen). Everything else
-- (menus, cards, text, input) goes through the UI layer, which uses the same rotation
-- while the reader is open, so input already arrives in logical coordinates.
local function toPhys(lx, ly)
	if rot == 0 then return lx, ly
	elseif rot == 90 then return PHYS_W - ly, lx
	else return ly, PHYS_H - lx end
end
local function toLogical(x, y) return x, y end
local function deltaLogical(dx, dy) return dx, dy end

local function lrect(x, y, w, h, color)
	UI.rect(x, y, w, h, color)
end

local function ltextCenter(font, lx, ly, s, color)
	UI.textCenter(font, lx, ly - 10, s, color)
end

local DIRMAP = {
	[0] = {up = SCE_CTRL_UP, down = SCE_CTRL_DOWN, left = SCE_CTRL_LEFT, right = SCE_CTRL_RIGHT}
}

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local function opt(k)
	return Store.readerValue(R.series and R.series.key, k)
end

local function isPaged()
	return cfg.ReadingMode == "RTL" or cfg.ReadingMode == "LTR" or cfg.ReadingMode == "Vertical"
end

-- page tint = page tone x brightness
local function updateTint()
	local b = cfg.Brightness / 100
	local t = TONE_RGB[cfg.PageTone] or TONE_RGB.Normal
	TINT = Color.new(floor(t[1] * b), floor(t[2] * b), floor(t[3] * b), 255)
end

local function loadConfig()
	for k in pairs(Settings) do cfg[k] = opt(k) end
	rot = cfg.Rotation or -1
	if rot == -1 then rot = Orient.appRotation() end -- "Same as app"
	if rot == 90 then
		LW, LH, ANG = PHYS_H, PHYS_W, PI / 2
	elseif rot == 270 then
		LW, LH, ANG = PHYS_H, PHYS_W, -PI / 2
	else
		rot, LW, LH, ANG = 0, PHYS_W, PHYS_H, 0
	end
	if Reader.isOpen and Reader.isOpen() then Orient.apply() end
	updateTint()
end

------------------------------------------------------------------------
-- Pages: loading, freeing, crop detection
------------------------------------------------------------------------
local function freePage(p)
	if p.img then p.img:free() p.img = nil end
	if p.slices then
		for i = 1, #p.slices do
			if p.slices[i] and p.slices[i].free then p.slices[i]:free() end
		end
		p.slices = nil
	end
	if p.state == "ready" or p.state == "loading" then p.state = nil end
	Loader.cancel(p.key)
end

local function isBgPixel(c, white)
	local r, g, b = band(c, 255), band(rshift(c, 8), 255), band(rshift(c, 16), 255)
	if white then return r > 215 and g > 215 and b > 215 end
	return r < 42 and g < 42 and b < 42
end

-- Detect uniform white/black borders by sampling the texture
local function detectCrop(img)
	local e, tw, th = img.e, img.Width, img.Height
	if tw < 40 or th < 40 then return ZERO_CROP end
	local gp = Graphics.getPixel
	local ok, corners = pcall(function()
		return {gp(1, 1, e), gp(tw - 2, 1, e), gp(1, th - 2, e), gp(tw - 2, th - 2, e)}
	end)
	if not ok then return ZERO_CROP end
	local white = 0
	local black = 0
	for _, c in ipairs(corners) do
		if isBgPixel(c, true) then white = white + 1 elseif isBgPixel(c, false) then black = black + 1 end
	end
	local isWhite
	if white >= 3 then isWhite = true elseif black >= 3 then isWhite = false else return ZERO_CROP end
	local N = 28
	local function rowBg(y)
		for i = 0, N - 1 do
			if not isBgPixel(gp(floor((i + 0.5) * tw / N), y, e), isWhite) then return false end
		end
		return true
	end
	local function colBg(x)
		for i = 0, N - 1 do
			if not isBgPixel(gp(x, floor((i + 0.5) * th / N), e), isWhite) then return false end
		end
		return true
	end
	local sy, sx = max(1, floor(th / 220)), max(1, floor(tw / 220))
	local t, b, l, r = 0, th - 1, 0, tw - 1
	while t < th * 0.3 and rowBg(t) do t = t + sy end
	while b > th * 0.7 and rowBg(b) do b = b - sy end
	while l < tw * 0.3 and colBg(l) do l = l + sx end
	while r > tw * 0.7 and colBg(r) do r = r - sx end
	-- leave a hairline of breathing room
	t, l = max(0, t - sy), max(0, l - sx)
	b, r = min(th - 1, b + sy), min(tw - 1, r + sx)
	return {l = l / tw, t = t / th, r = (tw - 1 - r) / tw, b = (th - 1 - b) / th}
end

local function onDims()
	if isPaged() then R.needViews = true else R.needLayout = true end
end

local function loadPage(i, priority)
	local p = R.pages[i]
	if not p or p.state == "ready" or p.state == "loading" or p.state == "error" then
		if p and p.state == "loading" then Loader.setPriority(p.key, priority) end
		return
	end
	p.state = "loading"
	local session = R.session
	Loader.add {
		key = p.key,
		path = p.path,
		extract = p.extract,
		maxSide = QUALITY_MAX[cfg.Quality],
		priority = priority,
		unsupported = IsUnsupportedImage(p.name) and "WebP pages are not supported" or nil,
		onDone = function(res, info, err)
			if R.session ~= session or R.pages[i] ~= p then
				if res then
					if res.free then res:free() else for k = 1, #res do if res[k].free then res[k]:free() end end end
				end
				return
			end
			if not res then
				p.state = "error"
				p.err = err or "Could not load page"
				return
			end
			if info.sliced then
				p.slices = res
				p.ts = 1
			else
				p.img = res
				p.ts = info.tw / info.w
			end
			local changed = (p.w ~= info.w or p.h ~= info.h)
			p.w, p.h = info.w, info.h
			R.defW, R.defH = info.w, info.h
			p.state = "ready"
			if cfg.CropBorders and p.img and not p.crop then
				p.crop = detectCrop(p.img)
				changed = true
			end
			if changed then onDims() end
		end
	}
end

local function keepWindow(first, last)
	for i, p in ipairs(R.pages) do
		if i < first or i > last then
			if p.img or p.slices or p.state == "loading" then freePage(p) end
		end
	end
end

local function freeAll()
	if R.pages then
		for _, p in ipairs(R.pages) do freePage(p) end
	end
	Loader.cancelPrefix("page:")
end

-- Effective source rect (original px) after crop + margin
local function srcRect(p)
	local w, h = p.w or R.defW, p.h or R.defH
	local c = (cfg.CropBorders and p.crop) or ZERO_CROP
	local m = cfg.Margin / 100
	local l, t, r, b = c.l + m, c.t + m, c.r + m, c.b + m
	if l + r > 0.8 then l, r = 0.4, 0.4 end
	if t + b > 0.8 then t, b = 0.4, 0.4 end
	return w * l, h * t, w * (1 - l - r), h * (1 - t - b)
end

local function isWide(p)
	if not p.w then return false end
	local _, _, sw, sh = srcRect(p)
	return sw > sh * 1.05
end

-- Draw region (sx,sy,sw,sh in original px) centered at logical (lcx,lcy).
-- kx, ky: logical px per original px along the image axes. extra: extra rotation (rad)
local function drawRegion(p, sx, sy, sw, sh, lcx, lcy, kx, ky, extra)
	local ang = ANG + (extra or 0)
	if p.slices then
		local sl = p.slices
		local y0 = 0
		for k = 1, sl.Parts do
			local img = sl[k]
			if img and img.e then
				local y1 = y0 + img.Height
				local a, b = max(sy, y0), min(sy + sh, y1)
				if b > a then
					local dy = ((a + b) / 2 - (sy + sh / 2)) * ky
					local px, py = toPhys(lcx, lcy + dy)
					local tx, ty = max(0, floor(sx)), max(0, floor(a - y0))
					drawExt(px, py, img.e, tx, ty, min(sw, img.Width - tx), min(b - a, img.Height - ty), ang, kx, ky, TINT)
				end
				y0 = y1
			end
		end
	elseif p.img and p.img.e then
		local ts = p.ts or 1
		local px, py = toPhys(lcx, lcy)
		local img = p.img
		local tx, ty = max(0, floor(sx * ts)), max(0, floor(sy * ts))
		drawExt(px, py, img.e, tx, ty, min(sw * ts, img.Width - tx), min(sh * ts, img.Height - ty), ang, kx / ts, ky / ts, TINT)
	end
end

local function drawPlaceholder(p, lx, ly, w, h, idx)
	lrect(lx, ly, w, h, Color.new(128, 128, 128, 28))
	local msg
	if p.state == "error" then
		msg = p.err or "Could not load page"
	else
		local dots = floor(Timer.getTime(GlobalTimer) / 300) % 4
		msg = "Loading" .. string.rep(".", dots)
	end
	ltextCenter(FONT.m, lx + w / 2, ly + h / 2 - 12, msg, p.state == "error" and C.accent or Color.new(150, 150, 150))
	ltextCenter(FONT.s, lx + w / 2, ly + h / 2 + 16, tostring(idx) .. (p.state == "error" and ("  ·  " .. (p.name or "")) or ""), Color.new(120, 120, 120))
end

------------------------------------------------------------------------
-- Paged mode
------------------------------------------------------------------------
local function buildViews()
	local anchorPage, anchorHalf
	if R.views and R.views[R.view] then
		anchorPage, anchorHalf = R.views[R.view].p1, R.views[R.view].half
	else
		anchorPage = R.startPage or 1
	end
	local views = {}
	local n = #R.pages
	local double = cfg.DoublePage == "On" or (cfg.DoublePage == "Auto" and LW > LH)
	local i = 1
	if double and cfg.DoubleShift and n > 0 then
		views[1] = {p1 = 1, rotate = cfg.WidePages == "Rotate" and isWide(R.pages[1])}
		i = 2
	end
	while i <= n do
		local p = R.pages[i]
		local wide = isWide(p)
		if wide and cfg.WidePages == "Split" then
			views[#views + 1] = {p1 = i, half = 1}
			views[#views + 1] = {p1 = i, half = 2}
			i = i + 1
		elseif double and not wide and i < n and not isWide(R.pages[i + 1]) then
			views[#views + 1] = {p1 = i, p2 = i + 1}
			i = i + 2
		else
			views[#views + 1] = {p1 = i, rotate = (wide and cfg.WidePages == "Rotate") or nil}
			i = i + 1
		end
	end
	R.views = views
	R.view = 1
	for vi, v in ipairs(views) do
		if v.p1 == anchorPage or v.p2 == anchorPage then
			if not anchorHalf or v.half == anchorHalf or not v.half then
				R.view = vi
				break
			end
		end
	end
	R.needViews = false
end

-- geometry of a view: parts + content size (in "content units" = source px of first page)
local function viewGeom(v)
	local p1 = R.pages[v.p1]
	local sx, sy, sw, sh = srcRect(p1)
	if v.half then
		local hw = sw / 2
		local rightFirst = cfg.ReadingMode == "RTL"
		local isRight = (v.half == 1) == rightFirst
		if isRight then sx = sx + hw end
		sw = hw
	end
	if v.p2 then
		local p2 = R.pages[v.p2]
		local sx2, sy2, sw2, sh2 = srcRect(p2)
		local s2 = sh / sh2
		local w2 = sw2 * s2
		local W, H = sw + w2, sh
		local c1, c2
		if cfg.ReadingMode == "RTL" then
			c1, c2 = w2 + sw / 2, w2 / 2
		else
			c1, c2 = sw / 2, sw + w2 / 2
		end
		return {
			{p = p1, idx = v.p1, sx = sx, sy = sy, sw = sw, sh = sh, cx = c1, cy = H / 2, s = 1},
			{p = p2, idx = v.p2, sx = sx2, sy = sy2, sw = sw2, sh = sh2, cx = c2, cy = H / 2, s = s2}
		}, W, H
	end
	local W, H = sw, sh
	if v.rotate then W, H = sh, sw end
	return {{p = p1, idx = v.p1, sx = sx, sy = sy, sw = sw, sh = sh, cx = W / 2, cy = H / 2, s = 1, rotate = v.rotate}}, W, H
end

local function baseZoom(W, H)
	local st = cfg.ScaleType
	local fs = min(LW / W, LH / H)
	if st == "Fit width" then return LW / W, LW / W
	elseif st == "Fit height" then return LH / H, LH / H
	elseif st == "Original" then return 1, 1
	elseif st == "Stretch" then return LW / W, LH / H
	elseif st == "Smart fit" then
		local z = min(LW / W, 2 * LH / H)
		return max(z, fs), max(z, fs)
	end
	return fs, fs
end

local function curGeom()
	local v = R.views and R.views[R.view]
	if not v then return nil end
	local parts, W, H = viewGeom(v)
	local zx, zy = baseZoom(W, H)
	return parts, W, H, zx * R.zoom, zy * R.zoom
end

local function panLimits()
	local parts, W, H, zx, zy = curGeom()
	if not parts then return 0, 0 end
	return max(0, (W * zx - LW) / 2), max(0, (H * zy - LH) / 2)
end

local function clampPan()
	local mx, my = panLimits()
	R.ox = math.clamp(R.ox, -mx, mx)
	R.oy = math.clamp(R.oy, -my, my)
	R.tox = math.clamp(R.tox, -mx, mx)
	R.toy = math.clamp(R.toy, -my, my)
end

local function forwardSign()
	-- sign of ox change that moves the view forward (reading direction)
	return cfg.ReadingMode == "RTL" and 1 or -1
end

local function setStart(atEnd)
	local mx, my = panLimits()
	local zs = cfg.ZoomStart
	local x
	if zs == "Left" then x = mx
	elseif zs == "Right" then x = -mx
	elseif zs == "Center" then x = 0
	else
		-- Auto: start on the reading side
		x = -forwardSign() * mx
		if atEnd then x = -x end
	end
	R.ox, R.tox = x, x
	R.oy = atEnd and -my or my
	R.toy = R.oy
	R.fresh = true
	R.freshEnd = atEnd
	R.freshApplied = false
end

local function pagedWindow()
	local v = R.views[R.view]
	if not v then return end
	local pre = cfg.Preload
	local first = v.p1
	local last = v.p2 or v.p1
	-- current view first, then forward, then one back
	loadPage(v.p1, 0)
	if v.p2 then loadPage(v.p2, 0) end
	local prio = 1
	for vi = R.view + 1, min(#R.views, R.view + pre) do
		local w = R.views[vi]
		loadPage(w.p1, prio)
		if w.p2 then loadPage(w.p2, prio) end
		last = max(last, w.p2 or w.p1)
		prio = prio + 1
	end
	if R.views[R.view - 1] then
		local w = R.views[R.view - 1]
		loadPage(w.p1, prio + 1)
		if w.p2 then loadPage(w.p2, prio + 1) end
		first = min(first, w.p1)
	end
	keepWindow(first - 1, last + 1)
end

local function viewLastPage(v)
	return v and (v.p2 or v.p1) or 1
end

local function flushStats()
	if R.series and ((R.statMs or 0) > 0 or (R.statPages or 0) > 0) then
		Store.addStats(R.series.key, R.statMs or 0, R.statPages or 0, 0)
	end
	R.statMs, R.statPages = 0, 0
end

local function saveProgress(page)
	if not R.ch or R.total == 0 then return end
	if page ~= R.savedPage then
		R.savedPage = page
		Store.setPage(R.series.key, R.ch.key, page, R.total)
		local key = R.ch.key .. "#" .. page
		if R.seen and not R.seen[key] then
			R.seen[key] = true
			R.statPages = (R.statPages or 0) + 1
		end
	end
end

local function zoomKey(v)
	return R.ch and v and (R.ch.key .. "#" .. v.p1 .. (v.half and ("h" .. v.half) or "")) or nil
end

local function rememberZoom()
	if not cfg.RememberZoom or not R.views then return end
	local k = zoomKey(R.views[R.view])
	if not k then return end
	if R.zoom > 1.01 then
		R.zmem[k] = {z = R.zoom, x = R.tox, y = R.toy}
	else
		R.zmem[k] = nil
	end
end

local function goView(vi, dir, atEnd)
	if vi < 1 or vi > #R.views then return false end
	if vi ~= R.view then rememberZoom() end
	if cfg.Animate and vi ~= R.view then
		R.anim = {from = R.view, zoom = R.zoom, ox = R.ox, oy = R.oy, dir = dir, t = 0, off = R.swipe or 0}
	end
	R.view = vi
	R.zoom = 1
	R.swipe = 0
	setStart(atEnd)
	local zm = cfg.RememberZoom and R.zmem[zoomKey(R.views[vi])]
	if zm then
		R.zoom = zm.z
		R.ox, R.oy, R.tox, R.toy = zm.x, zm.y, zm.x, zm.y
		R.fresh, R.freshApplied = false, true
	end
	pagedWindow()
	saveProgress(viewLastPage(R.views[vi]))
	return true
end

------------------------------------------------------------------------
-- Strip (webtoon) mode
------------------------------------------------------------------------
local function stripCards()
	local top = (R.ci > 1) and floor(LH * 0.32) or 0
	return top, floor(LH * 0.4)
end

local function layoutStrip()
	-- anchor: page at the top of viewport and fraction inside it
	local anchor, frac
	if R.ys and R.hs and #R.ys > 0 then
		local probe = R.sy + LH * 0.3
		for i = 1, #R.ys do
			if probe >= R.ys[i] and probe < R.ys[i] + R.hs[i] + R.gap then
				anchor, frac = i, (probe - R.ys[i]) / max(1, R.hs[i])
				break
			end
		end
	end
	local colW = LW * cfg.StripWidth / 100 * R.czoom
	R.colW = colW
	R.gap = (cfg.ReadingMode == "Strip") and 14 or 0
	local topCard, endCard = stripCards()
	R.topCard, R.endCard = topCard, endCard
	local y = topCard
	R.ys, R.hs = {}, {}
	for i, p in ipairs(R.pages) do
		local _, _, sw, sh = srcRect(p)
		local h = colW * sh / sw
		R.ys[i], R.hs[i] = y, h
		y = y + h + R.gap
	end
	R.endY = y
	R.contentH = y + endCard
	if anchor then
		R.sy = R.ys[anchor] + frac * R.hs[anchor] - LH * 0.3
		R.tsy = R.sy
	end
	R.needLayout = false
end

local function stripMax()
	return max(0, R.contentH - LH)
end

local function stripCurrentPage()
	local probe = R.sy + LH * 0.35
	local cur = 1
	for i = 1, #R.ys do
		if R.ys[i] <= probe then cur = i else break end
	end
	return cur
end

local function stripWindow()
	local a, b = R.sy - LH * 1.2, R.sy + LH * (1.6 + cfg.Preload * 0.6)
	local cur = stripCurrentPage()
	local first, last = nil, nil
	for i = 1, #R.pages do
		local y, h = R.ys[i], R.hs[i]
		if y + h >= a and y <= b then
			loadPage(i, abs(i - cur) + (y + h < R.sy and 2 or 0))
			first = first or i
			last = i
		end
	end
	if first then keepWindow(first - 1, last + 1) end
end

local function stripScrollToPage(page)
	R.sy = (page <= 1) and R.topCard or (R.ys[page] or 0)
	R.sy = math.clamp(R.sy, 0, stripMax())
	R.tsy = R.sy
	R.vy = 0
end

------------------------------------------------------------------------
-- Chapter loading
------------------------------------------------------------------------
local function loadChapter(ci, page, fromEnd)
	freeAll()
	sessionSeq = sessionSeq + 1
	R.session = sessionSeq
	R.ci = ci
	R.ch = R.series.chapters[ci]
	R.transition = nil
	R.anim = nil
	R.swipe = 0
	R.zoom, R.czoom, R.cx = 1, 1, 0
	R.views, R.ys, R.hs = nil, nil, nil
	R.savedPage = nil
	local pages, err = Scanner.pages(R.ch)
	R.pages = pages
	R.total = #pages
	R.empty = (#pages == 0) and (err or "No images found in this chapter") or nil
	for i, p in ipairs(pages) do
		p.key = "page:" .. R.session .. ":" .. i
	end
	if R.total == 0 then
		Store.setPage(R.series.key, R.ch.key, 0, 0)
		return
	end
	page = math.clamp(fromEnd and R.total or (page or 1), 1, R.total)
	R.startPage = page
	if isPaged() then
		buildViews()
		goView(R.view, 1, fromEnd)
		R.anim = nil
	else
		R.sy, R.tsy, R.vy = 0, 0, 0
		layoutStrip()
		stripScrollToPage(page)
		if fromEnd then
			R.sy = R.ys[R.total] or 0
			R.tsy = R.sy
		end
		stripWindow()
		saveProgress(stripCurrentPage())
	end
	R.savedPage = nil
	saveProgress(page)
end

function Reader.nextChapter()
	if R.ci < #R.series.chapters then
		if R.total > 0 then Store.setPage(R.series.key, R.ch.key, R.total, R.total) end
		loadChapter(R.ci + 1, 1)
		UI.toast(R.ch.name)
		return true
	end
	UI.toast("No more chapters")
	return false
end

function Reader.prevChapter()
	if R.ci > 1 then
		loadChapter(R.ci - 1, 1, true)
		UI.toast(R.ch.name)
		return true
	end
	UI.toast("This is the first chapter")
	return false
end

-- Re-apply config keeping the current page
local function reconfigure(reloadImages)
	local page = 1
	if R.views and R.views[R.view] then
		page = R.views[R.view].p1
	elseif R.ys then
		page = stripCurrentPage()
	end
	local wasPaged = R.views ~= nil
	loadConfig()
	if reloadImages then
		for _, p in ipairs(R.pages or {}) do
			freePage(p)
			if p.state == "error" then p.state = nil end
		end
	end
	if not R.pages or R.total == 0 then return end
	if cfg.CropBorders then
		for _, p in ipairs(R.pages) do
			if p.img and not p.crop then p.crop = detectCrop(p.img) end
		end
	end
	if isPaged() then
		R.ys, R.hs = nil, nil
		if not wasPaged then R.views = nil end
		R.startPage = page
		if R.views then
			-- keep anchor by page
			for vi, v in ipairs(R.views) do
				if v.p1 == page then R.view = vi end
			end
		end
		buildViews()
		R.zoom = 1
		setStart(false)
		pagedWindow()
	else
		R.views = nil
		if not R.ys then
			R.sy, R.tsy, R.vy = 0, 0, 0
			R.czoom, R.cx = 1, 0
			layoutStrip()
			stripScrollToPage(page)
		else
			layoutStrip()
		end
		stripWindow()
	end
end

------------------------------------------------------------------------
-- Options (shared with the Settings tab)
------------------------------------------------------------------------
local SPEC = {
	{"ReadingMode", "choice", "Reading mode", OPT.ReadingMode, OPT.ReadingModeLabels},
	{"ScaleType", "choice", "Scale type", OPT.ScaleType},
	{"ZoomStart", "choice", "Zoom start position", OPT.ZoomStart},
	{"DoublePage", "choice", "Two-page spreads", OPT.DoublePage, OPT.DoublePageLabels},
	{"DoubleShift", "toggle", "Show first page alone"},
	{"WidePages", "choice", "Wide pages", OPT.WidePages, OPT.WidePagesLabels},
	{"CropBorders", "toggle", "Crop white/black borders"},
	{"Margin", "slider", "Trim margins", 0, 20, 1, "%"},
	{"Rotation", "choice", "Orientation", OPT.Rotation, OPT.RotationLabels},
	{"StripWidth", "slider", "Webtoon width", 40, 100, 5, "%"},
	{"Background", "choice", "Background", OPT.Background},
	{"Brightness", "slider", "Brightness", 20, 100, 5, "%"},
	{"BrightnessSwipe", "choice", "Brightness swipe (screen edge)", OPT.BrightnessSwipe, OPT.BrightnessSwipeLabels},
	{"PageTone", "choice", "Page tone", OPT.PageTone},
	{"Filter", "choice", "Color filter", OPT.Filter},
	{"FilterStrength", "slider", "Filter strength", 5, 80, 5, "%"},
	{"TapZones", "choice", "Tap zones", OPT.TapZones, OPT.TapZonesLabels},
	{"_tapgrid", "action", "Edit custom tap grid..."},
	{"InvertTap", "toggle", "Invert tap zones"},
	{"InvertButtons", "toggle", "Invert page buttons"},
	{"PanFirst", "toggle", "Scroll zoomed pages before turning"},
	{"ScrollStep", "slider", "Scroll step", 25, 100, 5, "%"},
	{"Animate", "toggle", "Page turn animation"},
	{"DoubleTapZoom", "toggle", "Double-tap to zoom"},
	{"RememberZoom", "toggle", "Remember zoom per page"},
	{"AutoScrollSpeed", "slider", "Auto-scroll speed (webtoon)", 1, 10, 1, ""},
	{"PageNumber", "choice", "Page indicator", OPT.PageNumber},
	{"Preload", "slider", "Pages to preload", 1, 4, 1, ""},
	{"Quality", "choice", "Texture quality", OPT.Quality, OPT.QualityLabels},
	{"AutoNextChapter", "toggle", "Continue into next chapter"},
	{"KeepScreenOn", "toggle", "Keep screen on while reading"}
}

local function isSeriesKey(k)
	return table.find(SERIES_KEYS, k) ~= nil
end

local function makeItem(spec, get, set)
	local k = spec[1]
	if spec[2] == "action" then
		return {kind = "action", label = spec[3], run = function() App.push(TapGridEditor) end}
	end
	local it = {kind = spec[2], label = spec[3], key = k}
	it.get = function() return get(k) end
	it.set = function(v) set(k, v) end
	if spec[2] == "choice" then
		it.options, it.labels = spec[4], spec[5]
	elseif spec[2] == "slider" then
		it.min, it.max, it.step = spec[4], spec[5], spec[6]
		local unit = spec[7]
		it.fmt = function(v) return tostring(v) .. unit end
	end
	return it
end

-- get(k), set(k, v). When perSeries, series-overridable keys are grouped first.
function Reader.optionItems(get, set, global, perSeries)
	local items = {}
	if perSeries then
		items[#items + 1] = {kind = "header", label = "This series"}
		for _, s in ipairs(SPEC) do
			if isSeriesKey(s[1]) then items[#items + 1] = makeItem(s, get, set) end
		end
		items[#items + 1] = {kind = "header", label = "All series"}
		for _, s in ipairs(SPEC) do
			if not isSeriesKey(s[1]) then items[#items + 1] = makeItem(s, get, set) end
		end
	else
		for _, s in ipairs(SPEC) do items[#items + 1] = makeItem(s, get, set) end
	end
	return items
end

local RELOAD_KEYS = {Quality = true}
local REBUILD_KEYS = {ReadingMode = true, ScaleType = true, ZoomStart = true, DoublePage = true, DoubleShift = true, WidePages = true, CropBorders = true, Margin = true, Rotation = true, StripWidth = true}

local function readerSet(series, k, v)
	if isSeriesKey(k) then
		Store.setSeriesPref(series.key, k, v)
	else
		Store.set(k, v)
	end
end

function Reader.seriesSettingsSheet(series)
	local items = {}
	items[#items + 1] = {kind = "info", label = "Applies only to " .. series.title}
	for _, s in ipairs(SPEC) do
		if isSeriesKey(s[1]) then
			items[#items + 1] = makeItem(s, function(k) return Store.readerValue(series.key, k) end, function(k, v) Store.setSeriesPref(series.key, k, v) end)
		end
	end
	items[#items + 1] = {kind = "action", label = "Reset to global defaults", run = function()
		Store.clearSeriesPrefs(series.key)
		UI.toast("Series uses global reader settings")
	end}
	Sheet.open {title = "Reader · this series", items = items}
end

------------------------------------------------------------------------
-- Presets
------------------------------------------------------------------------
local function describePreset(p)
	local v = p.v
	local bits = {}
	if v.ReadingMode == "Webtoon" or v.ReadingMode == "Strip" then
		local o = (v.Rotation == -1 or v.Rotation == nil) and "" or ((v.Rotation == 0) and " · landscape" or " · portrait")
		return (v.ReadingMode == "Strip" and "strip" or "webtoon") .. o
	end
	if v.ReadingMode then bits[#bits + 1] = ({RTL = "RTL", LTR = "LTR", Vertical = "Vertical"})[v.ReadingMode] end
	if v.DoublePage and v.DoublePage ~= "Off" then bits[#bits + 1] = "2 pages"
	elseif v.ScaleType and v.ScaleType ~= "Fit screen" and v.ReadingMode ~= "Webtoon" then bits[#bits + 1] = v.ScaleType:lower()
	elseif v.Rotation ~= nil and v.Rotation ~= -1 then bits[#bits + 1] = v.Rotation == 0 and "landscape" or "portrait" end
	return table.concat(bits, " · ")
end
Reader.describePreset = describePreset

-- List presets; onPick(preset). currentName marks the active one.
function Reader.presetPicker(title, currentName, onPick, extra, subtitle)
	local items = {}
	if subtitle then items[#items + 1] = {kind = "info", label = subtitle} end
	local function group(builtin)
		for _, p in ipairs(Store.presets()) do
			if (p.builtin == true) == builtin then
				items[#items + 1] = {kind = "action", label = (p.name == currentName and "✓ " or "") .. p.name, value = describePreset(p), run = function() onPick(p) end}
			end
		end
	end
	items[#items + 1] = {kind = "header", label = "Built-in"}
	group(true)
	if #Settings.UserPresets > 0 then
		items[#items + 1] = {kind = "header", label = "Yours"}
		group(false)
	end
	for _, it in ipairs(extra or {}) do items[#items + 1] = it end
	Sheet.open {title = title, items = items}
end

local function savePresetPrompt(get)
	UI.prompt("Preset name", "", function(name)
		local ok, msg = Store.savePreset(name, Store.capturePreset(get))
		UI.toast(msg)
	end)
end
Reader.savePresetPrompt = savePresetPrompt

local function readerSettingsSheet()
	local s = R.series
	local items = Reader.optionItems(
		function(k) return opt(k) end,
		function(k, v)
			readerSet(s, k, v)
			if k == "KeepScreenOn" then Reader.applyScreenLock(v) end
			if RELOAD_KEYS[k] then
				reconfigure(true)
			elseif REBUILD_KEYS[k] then
				reconfigure(false)
			else
				loadConfig()
			end
		end, false, true)
	local presetItems = {
		{kind = "header", label = "Presets"},
		{kind = "action", label = "Apply a preset", value = function() return Store.matchPreset(opt) or "Custom" end, keepOpen = true, run = function()
			Reader.presetPicker("Apply preset", Store.matchPreset(opt), function(p)
				Store.applyPresetToSeries(s.key, p)
				Sheet.closeAll()
				reconfigure(false)
				Reader.applyScreenLock(cfg.KeepScreenOn)
				UI.toast(p.name .. " · " .. s.title)
			end)
		end},
		{kind = "action", label = "Save these settings as a preset...", run = function() savePresetPrompt(opt) end},
		{kind = "action", label = "Make these the default for all series", run = function()
			Store.applyPresetAsDefault({v = Store.capturePreset(opt)})
			UI.toast("Default reader settings updated")
		end}
	}
	for i = #presetItems, 1, -1 do table.insert(items, 1, presetItems[i]) end
	items[#items + 1] = {kind = "header", label = ""}
	items[#items + 1] = {kind = "action", label = "Reset this series to defaults", run = function()
		Store.clearSeriesPrefs(s.key)
		reconfigure(false)
		UI.toast("Series uses global reader settings")
	end}
	Sheet.open {title = "Reader settings", items = items, closeWithStart = true}
end

function Reader.applyScreenLock(on)
	if on then
		pcall(System.disableTimer, SCREEN_DIMMING_TIMER)
		pcall(System.disableTimer, SCREEN_OFF_TIMER)
		pcall(System.disableTimer, AUTO_SUSPEND_TIMER)
		R.locked = true
	elseif R.locked then
		pcall(System.enableTimer, SCREEN_DIMMING_TIMER)
		pcall(System.enableTimer, SCREEN_OFF_TIMER)
		pcall(System.enableTimer, AUTO_SUSPEND_TIMER)
		R.locked = false
	end
end

------------------------------------------------------------------------
-- Navigation actions
------------------------------------------------------------------------
local function stepX() return LW * cfg.ScrollStep / 100 end
local function stepY() return LH * cfg.ScrollStep / 100 end

local function pagedNext(direct)
	if R.transition == "prev" then R.transition = nil return end
	if R.transition == "next" then
		if cfg.AutoNextChapter or direct == "ok" then Reader.nextChapter() end
		return
	end
	if cfg.PanFirst and not direct then
		local mx, my = panLimits()
		local fs = forwardSign()
		if mx > 1 and abs(R.tox - fs * mx) > 1 then
			R.tox = math.clamp(R.tox + fs * stepX(), -mx, mx)
			R.fresh = false
			return
		end
		if my > 1 and R.toy > -my + 1 then
			R.toy = math.clamp(R.toy - stepY(), -my, my)
			if mx > 1 then R.tox = -fs * mx end
			R.fresh = false
			return
		end
	end
	if not goView(R.view + 1, 1, false) then
		saveProgress(R.total)
		R.transition = "next"
	end
end

local function pagedPrev(direct)
	if R.transition == "next" then R.transition = nil return end
	if R.transition == "prev" then
		if cfg.AutoNextChapter or direct == "ok" then Reader.prevChapter() end
		return
	end
	if cfg.PanFirst and not direct then
		local mx, my = panLimits()
		local fs = forwardSign()
		if mx > 1 and abs(R.tox + fs * mx) > 1 then
			R.tox = math.clamp(R.tox - fs * stepX(), -mx, mx)
			R.fresh = false
			return
		end
		if my > 1 and R.toy < my - 1 then
			R.toy = math.clamp(R.toy + stepY(), -my, my)
			if mx > 1 then R.tox = fs * mx end
			R.fresh = false
			return
		end
	end
	if not goView(R.view - 1, -1, true) then
		if R.ci > 1 then R.transition = "prev" end
	end
end

local function stripNext(amount)
	if R.sy >= stripMax() - 2 and R.tsy >= stripMax() - 2 then
		if cfg.AutoNextChapter then Reader.nextChapter() end
		return
	end
	R.tsy = math.clamp(R.tsy + (amount or stepY()), 0, stripMax())
	R.vy = 0
end

local function stripPrev(amount)
	if R.sy <= 2 and R.tsy <= 2 then
		if R.ci > 1 and cfg.AutoNextChapter then Reader.prevChapter() end
		return
	end
	R.tsy = math.clamp(R.tsy - (amount or stepY()), 0, stripMax())
	R.vy = 0
end

local function goNext(direct)
	if isPaged() then pagedNext(direct) else stripNext() end
end

local function goPrev(direct)
	if isPaged() then pagedPrev(direct) else stripPrev() end
end

-- visual horizontal direction (logical left / right) -> next/prev
local function goVisual(dir, direct)
	if cfg.ReadingMode == "RTL" then
		if dir == "left" then goNext(direct) else goPrev(direct) end
	else
		if dir == "right" then goNext(direct) else goPrev(direct) end
	end
end

local function jumpToPage(page)
	page = math.clamp(page, 1, max(1, R.total))
	R.transition = nil
	if isPaged() then
		for vi, v in ipairs(R.views) do
			if v.p1 == page or v.p2 == page then
				local a = cfg.Animate
				cfg.Animate = false
				goView(vi, 1, false)
				cfg.Animate = a
				return
			end
		end
	else
		stripScrollToPage(page)
		saveProgress(page)
	end
end

local function currentPage()
	if R.total == 0 then return 0 end
	if isPaged() then
		return R.views and R.views[R.view] and viewLastPage(R.views[R.view]) or 1
	end
	return R.ys and stripCurrentPage() or 1
end

local function zoomAt(lx, ly, factor)
	if isPaged() then
		local nz = math.clamp(R.zoom * factor, 0.5, 6)
		local f = nz / R.zoom
		local cx, cy = lx - LW / 2, ly - LH / 2
		R.ox = (R.ox - cx) * f + cx
		R.oy = (R.oy - cy) * f + cy
		R.zoom = nz
		R.tox, R.toy = R.ox, R.oy
		R.fresh = false
		clampPan()
	else
		local nz = math.clamp(R.czoom * factor, 1, 4)
		local f = nz / R.czoom
		if abs(f - 1) < 0.001 then return end
		local docY = R.sy + ly
		R.czoom = nz
		local oldH = R.contentH
		-- relayout without anchor, then keep the point under the finger
		R.ys = nil
		layoutStrip()
		R.sy = docY * (R.contentH / oldH) - ly
		R.tsy = R.sy
		R.cx = (R.cx - (lx - LW / 2)) * f + (lx - LW / 2)
	end
end

local function toggleZoomAt(lx, ly)
	if isPaged() then
		if R.zoom > 1.05 then
			zoomAt(lx, ly, 1 / R.zoom)
			setStart(false)
		else
			zoomAt(lx, ly, 2)
		end
	else
		if R.czoom > 1.05 then zoomAt(lx, ly, 1 / R.czoom) else zoomAt(lx, ly, 1.8) end
	end
end

------------------------------------------------------------------------
-- Tap zones
------------------------------------------------------------------------
local function tapAction(lx, ly)
	local fx, fy = lx / LW, ly / LH
	local z = cfg.TapZones
	local a = "menu"
	if z == "Edges" then
		if fx < 0.3 then a = "left" elseif fx > 0.7 then a = "right" end
	elseif z == "L-shape" then
		if fx > 0.33 and fx < 0.67 and fy > 0.33 and fy < 0.67 then
			a = "menu"
		elseif fy < 0.33 or (fx < 0.33 and fy < 0.67) then
			a = "prev"
		else
			a = "next"
		end
	elseif z == "Kindle" then
		if fy < 0.15 then a = "menu" elseif fx < 0.33 then a = "prev" else a = "next" end
	elseif z == "Custom" then
		local col = math.clamp(floor(fx * 3), 0, 2)
		local row = math.clamp(floor(fy * 3), 0, 2)
		a = (cfg.TapGrid and cfg.TapGrid[row * 3 + col + 1]) or "menu"
	elseif z == "Off" then
		a = "menu"
	end
	if a == "left" or a == "right" then
		if not isPaged() or cfg.ReadingMode == "Vertical" then
			a = (a == "left") and "prev" or "next"
		elseif cfg.ReadingMode == "RTL" then
			a = (a == "left") and "next" or "prev"
		else
			a = (a == "left") and "prev" or "next"
		end
	end
	if cfg.InvertTap then
		if a == "next" then a = "prev" elseif a == "prev" then a = "next" end
	end
	return a
end

------------------------------------------------------------------------
-- Page bookmarks & auto-scroll
------------------------------------------------------------------------
local function viewPages()
	if R.total == 0 then return {} end
	if isPaged() then
		local v = R.views and R.views[R.view]
		if not v then return {} end
		return v.p2 and {v.p1, v.p2} or {v.p1}
	end
	return {currentPage()}
end

local function currentBookmarked()
	if not R.ch then return false end
	for _, pg in ipairs(viewPages()) do
		if Store.isPageBookmarked(R.ch.key, pg) then return true end
	end
	return false
end

local function toggleBookmark()
	if not R.ch or R.total == 0 then return end
	local pages = viewPages()
	local pg = pages[1]
	-- in a spread, prefer whichever page is already marked so it can be removed
	for _, p in ipairs(pages) do
		if Store.isPageBookmarked(R.ch.key, p) then pg = p end
	end
	local on = Store.togglePageBookmark(R.ch.key, pg)
	UI.toast(on and ("Bookmarked page " .. pg) or ("Removed bookmark on page " .. pg))
end

local function bookmarksSheet()
	local items = {}
	local list = Store.pageBookmarks(R.ch.key)
	if #list == 0 then
		items[1] = {kind = "info", label = "No bookmarked pages in this chapter"}
	end
	for _, pg in ipairs(list) do
		items[#items + 1] = {kind = "action", label = "Page " .. pg, value = "›", run = function()
			R.menu = false
			jumpToPage(pg)
		end}
	end
	items[#items + 1] = {kind = "action", label = currentBookmarked() and "Remove bookmark here" or "Bookmark this page", run = toggleBookmark}
	Sheet.open {title = "Bookmarks · " .. R.ch.name, items = items}
end

local function autoSpeed()
	-- logical px per ms
	return (12 + cfg.AutoScrollSpeed * 14) / 1000
end

local function toggleAuto()
	if isPaged() then
		UI.toast("Auto-scroll works in Webtoon / Long strip mode")
		return
	end
	R.auto = not R.auto
	UI.toast(R.auto and ("Auto-scroll on · speed " .. cfg.AutoScrollSpeed) or "Auto-scroll off")
end

local function changeAutoSpeed(d)
	local v = math.clamp(cfg.AutoScrollSpeed + d, 1, 10)
	if v ~= cfg.AutoScrollSpeed then
		Store.set("AutoScrollSpeed", v)
		cfg.AutoScrollSpeed = v
	end
	UI.toast("Auto-scroll speed " .. v)
end

------------------------------------------------------------------------
-- Menu overlay (physical coordinates; never rotated)
------------------------------------------------------------------------
local MENU_TOP_H = 58
local MENU_BOT_Y, SLIDER_X1, SLIDER_X2
UI.onLayout(function()
	MENU_BOT_Y = SCREEN_H - 86
	SLIDER_X1 = UI.portrait() and 100 or 150
	SLIDER_X2 = SCREEN_W - SLIDER_X1
end)

local function sliderReversed()
	return cfg.ReadingMode == "RTL"
end

local function sliderPageAt(px)
	local f = math.clamp((px - SLIDER_X1) / (SLIDER_X2 - SLIDER_X1), 0, 1)
	if sliderReversed() then f = 1 - f end
	return math.clamp(floor(f * (R.total - 1) + 0.5) + 1, 1, R.total)
end

local function menuInput()
	if Input.pressed(Input.BACK) or Input.pressed(SCE_CTRL_TRIANGLE) or Input.pressed(Input.OK) then
		R.menu = false
		return
	end
	if Input.pressed(SCE_CTRL_START) then readerSettingsSheet() return end
	if Input.pressed(SCE_CTRL_SELECT) then toggleBookmark() return end
	if Input.pressed(SCE_CTRL_SQUARE) and R.total > 0 then bookmarksSheet() return end
	if Input.pressed(SCE_CTRL_LTRIGGER) then Reader.prevChapter() return end
	if Input.pressed(SCE_CTRL_RTRIGGER) then Reader.nextChapter() return end
	if R.total > 0 then
		local d = 0
		if Input.rep(SCE_CTRL_RIGHT) then d = 1 elseif Input.rep(SCE_CTRL_LEFT) then d = -1 end
		if sliderReversed() then d = -d end
		if Input.held(SCE_CTRL_RIGHT) > 900 or Input.held(SCE_CTRL_LEFT) > 900 then d = d * 3 end
		if d ~= 0 then jumpToPage(currentPage() + d) end
	end
	local t = Input.touch
	if t and t.y > MENU_BOT_Y and t.y < MENU_BOT_Y + 50 and t.x > SLIDER_X1 - 20 and t.x < SLIDER_X2 + 20 and R.total > 0 then
		local p = sliderPageAt(t.x)
		if p ~= currentPage() then jumpToPage(p) end
		return
	end
	if Input.tap then
		local x, y = Input.tap.x, Input.tap.y
		if y < MENU_TOP_H then
			if x < 70 then Reader.close()
			elseif x > SCREEN_W - 70 then readerSettingsSheet()
			elseif x > SCREEN_W - 285 and x < SCREEN_W - 235 then Orient.toggleLock()
			elseif x > SCREEN_W - 230 and x < SCREEN_W - 180 then toggleBookmark() end
		elseif y > MENU_BOT_Y then
			if y < SCREEN_H - 40 and x < 120 then Reader.prevChapter()
			elseif y < SCREEN_H - 40 and x > SCREEN_W - 120 then Reader.nextChapter()
			elseif y >= SCREEN_H - 40 then
				-- quick buttons row
				if x < SCREEN_W / 3 then
					readerSet(R.series, "ReadingMode", table.cycle(OPT.ReadingMode, cfg.ReadingMode, 1))
					reconfigure(false)
					UI.toast(OPT.ReadingModeLabels[table.find(OPT.ReadingMode, cfg.ReadingMode)])
				elseif x < SCREEN_W * 2 / 3 then
					if isPaged() then
						readerSet(R.series, "ScaleType", table.cycle(OPT.ScaleType, cfg.ScaleType, 1))
						reconfigure(false)
						UI.toast(cfg.ScaleType)
					else
						toggleAuto()
						R.menu = false
					end
				else
					readerSet(R.series, "Rotation", table.cycle(OPT.Rotation, cfg.Rotation, 1))
					reconfigure(false)
					UI.toast(OPT.RotationLabels[table.find(OPT.Rotation, cfg.Rotation)])
				end
			end
		else
			R.menu = false
		end
	end
end

local function drawMenu()
	local a = R.menuAnim
	if a <= 0.01 then return end
	local ty = floor(-MENU_TOP_H * (1 - a))
	local by = floor((SCREEN_H - MENU_BOT_Y) * (1 - a))
	local barC = ThemeAlpha("surface", 238)
	UI.rect(0, ty, SCREEN_W, MENU_TOP_H, barC)
	UI.icon("back", 22, ty + 17, C.text)
	UI.textFit(FONT.b, 64, ty + 8, R.series.title, C.text, SCREEN_W - 64 - 300)
	UI.textFit(FONT.s, 64, ty + 32, R.ch and R.ch.name or "", C.sub, UI.portrait() and (SCREEN_W - 64 - 300) or 300)
	UI.status(SCREEN_W - 70, ty + 6)
	if not UI.portrait() then
		UI.hints({{"select", "Bookmark"}, {"square", "List"}, {"start", "Settings"}, {"back", "Close"}}, ty + 32, SCREEN_W - 296, nil, 380)
	end
	-- rotation: locked (lock icon, accent) or auto-rotate
	UI.icon(Settings.AutoRotate and "screenrot" or "lock", SCREEN_W - 270, ty + 17, Settings.AutoRotate and C.text or C.accent)
	UI.icon("options", SCREEN_W - 46, ty + 17, C.text)
	if R.total > 0 then
		local on = currentBookmarked()
		UI.icon(on and "bookmark_on" or "bookmark", SCREEN_W - 217, ty + 17, on and C.accent or C.text)
	end
	local y0 = MENU_BOT_Y + by
	UI.rect(0, y0, SCREEN_W, SCREEN_H - MENU_BOT_Y, barC)
	-- chapter buttons
	UI.text(FONT.m, 24, y0 + 12, "‹ Prev", R.ci > 1 and C.text or C.line)
	UI.textRight(FONT.m, SCREEN_W - 24, y0 + 12, "Next ›", R.ci < #R.series.chapters and C.text or C.line)
	if R.total > 0 then
		local cur = currentPage()
		local f = (R.total > 1) and (cur - 1) / (R.total - 1) or 1
		if sliderReversed() then f = 1 - f end
		local sy = y0 + 22
		UI.rect(SLIDER_X1, sy, SLIDER_X2 - SLIDER_X1, 4, C.surface2)
		local kx = SLIDER_X1 + (SLIDER_X2 - SLIDER_X1) * f
		if sliderReversed() then
			UI.rect(kx, sy, SLIDER_X2 - kx, 4, C.accent)
		else
			UI.rect(SLIDER_X1, sy, kx - SLIDER_X1, 4, C.accent)
		end
		UI.rect(kx - 7, sy - 7, 14, 18, C.accent)
		local label = cur .. " / " .. R.total
		UI.textCenter(FONT.s, SCREEN_W / 2, y0 + 34, label, C.sub)
	end
	-- quick toggles row
	local qy = SCREEN_H - 30 + by
	local modeLabel = OPT.ReadingModeLabels[table.find(OPT.ReadingMode, cfg.ReadingMode)] or cfg.ReadingMode
	UI.textCenter(FONT.s, SCREEN_W / 6, qy, modeLabel, C.text)
	UI.textCenter(FONT.s, SCREEN_W / 2, qy, isPaged() and cfg.ScaleType or (R.auto and "Auto-scroll: on" or "Auto-scroll: off"), R.auto and C.accent or C.text)
	UI.textCenter(FONT.s, SCREEN_W * 5 / 6, qy, OPT.RotationLabels[table.find(OPT.Rotation, cfg.Rotation)] or "", C.text)
	UI.rect(SCREEN_W / 3, qy + 2, 1, 16, C.line)
	UI.rect(SCREEN_W * 2 / 3, qy + 2, 1, 16, C.line)
end

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
local pinchDist = nil
local pendingTap = nil
local lastTapTime = -1000
local lastTapPos = nil
local dragStartedOnContent = false

-- Brightness swipe: slide a finger up / down along the screen edge (the edge as you hold
-- the Vita, so it follows the rotation). Taps there still work as tap zones, and a
-- sideways swipe that starts there still turns the page.
local bgest = nil
local function edgeSide(x)
	local mode = cfg.BrightnessSwipe or "Right"
	if mode == "Off" then return nil end
	local ew = max(40, LW * 0.1)
	if x < ew and (mode == "Left" or mode == "Both") then return "left" end
	if x > LW - ew and (mode == "Right" or mode == "Both") then return "right" end
	return nil
end
local function brightnessGesture()
	if Input.touch2 then bgest = nil return false end
	if Input.touchBegan and Input.touch and not R.menu then
		local side = edgeSide(Input.touch.x)
		bgest = side and {side = side, sx = Input.touch.x, sy = Input.touch.y, active = false} or nil
	end
	if not bgest then return false end
	local t = Input.touch
	if t then
		if not bgest.active then
			local dx, dy = t.x - bgest.sx, t.y - bgest.sy
			if abs(dy) > 12 and abs(dy) > abs(dx) * 1.4 then
				bgest.active, bgest.sy, bgest.start = true, t.y, cfg.Brightness
			elseif abs(dx) > 12 then
				bgest = nil -- a sideways swipe: let it turn the page
				return false
			else
				return false
			end
		end
		-- up = brighter; the full range is about 60% of the screen height
		local v = math.clamp(floor(bgest.start - (t.y - bgest.sy) / (LH * 0.6) * 80 + 0.5), 20, 100)
		if v ~= cfg.Brightness then
			cfg.Brightness = v
			Settings.Brightness = v
			updateTint()
		end
		R.bright = {side = bgest.side, show = 1200}
		return true
	end
	-- finger lifted
	local was = bgest.active
	bgest = nil
	if was then
		Store.set("Brightness", cfg.Brightness)
		return true -- not a tap or a swipe
	end
	return false
end

local function drawBrightness()
	local b = R.bright
	if not b or b.show <= 0 then return end
	local a = math.min(1, b.show / 300)
	local h = floor(SCREEN_H * 0.42)
	local w = 8
	local x = (b.side == "left") and 26 or (SCREEN_W - 26 - w)
	local y = floor((SCREEN_H - h) / 2)
	local cx = x + w / 2
	UI.rect(x - 14, y - 44, w + 28, h + 76, Color.new(0, 0, 0, floor(150 * a)))
	UI.iconScaled("sun", cx, y - 24, 22, Color.new(255, 255, 255, floor(255 * a)))
	UI.rect(x, y, w, h, Color.new(255, 255, 255, floor(60 * a)))
	local f = floor(h * (cfg.Brightness - 20) / 80)
	UI.rect(x, y + h - f, w, f, Color.new(255, 255, 255, floor(235 * a)))
	UI.textCenter(FONT.s, cx, y + h + 6, cfg.Brightness .. "%", Color.new(255, 255, 255, floor(255 * a)))
end

local function handleTouch(dt)
	if brightnessGesture() then return end
	local t1, t2 = Input.touch, Input.touch2
	-- pinch zoom
	if t1 and t2 then
		local ax, ay = toLogical(t1.x, t1.y)
		local bx, by = toLogical(t2.x, t2.y)
		local d = sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
		if pinchDist and pinchDist > 10 then
			zoomAt((ax + bx) / 2, (ay + by) / 2, d / pinchDist)
		end
		pinchDist = d
		R.swipe = 0
		R.pinched = true
		return
	end
	pinchDist = nil
	if Input.touchBegan then
		R.over, R.swipe = 0, 0
	end
	if t1 and Input.dragging and not R.pinched then
		local dx, dy = deltaLogical(Input.dx, Input.dy)
		if isPaged() then
			local mx, my = panLimits()
			if mx > 1 or my > 1 then
				-- pan; collect overscroll at the edges for page turns
				local nx, ny = R.ox + dx, R.oy + dy
				R.ox, R.oy = math.clamp(nx, -mx, mx), math.clamp(ny, -my, my)
				R.tox, R.toy = R.ox, R.oy
				R.fresh = false
				if cfg.ReadingMode == "Vertical" then
					R.over = (R.over or 0) + (ny - R.oy)
				else
					R.over = (R.over or 0) + (nx - R.ox)
				end
			else
				R.swipe = (R.swipe or 0) + ((cfg.ReadingMode == "Vertical") and dy or dx)
			end
		else
			R.sy = math.clamp(R.sy - dy, 0, stripMax())
			R.tsy = R.sy
			R.vy = -dy / max(dt, 1) * 16
			if R.czoom > 1 then R.cx = R.cx + dx end
		end
	end
	local rel = Input.released
	if rel then
		if R.pinched then
			R.pinched = false
			R.swipe, R.over = 0, 0
			return
		end
		if rel.moved and isPaged() then
			local amount = (R.swipe ~= 0) and R.swipe or (R.over or 0)
			local threshold = (R.swipe ~= 0) and 70 or 110
			if abs(amount) > threshold then
				if cfg.ReadingMode == "Vertical" then
					if amount < 0 then pagedNext(true) else pagedPrev(true) end
				else
					-- dragging content right reveals what is on the left
					goVisual(amount > 0 and "left" or "right", true)
				end
			end
			R.over = 0
		end
	end
	if Input.tap then
		local lx, ly = toLogical(Input.tap.x, Input.tap.y)
		local now = Timer.getTime(GlobalTimer)
		if cfg.DoubleTapZoom and lastTapPos and now - lastTapTime < 300 and abs(lastTapPos.x - lx) < 70 and abs(lastTapPos.y - ly) < 70 then
			pendingTap = nil
			lastTapPos = nil
			toggleZoomAt(lx, ly)
			return
		end
		lastTapTime, lastTapPos = now, {x = lx, y = ly}
		local ta = tapAction(lx, ly)
		if cfg.DoubleTapZoom and (ta == "menu" or ta == "none") then
			pendingTap = {x = lx, y = ly, t = now}
		else
			pendingTap = {x = lx, y = ly, t = now - 1000}
		end
	end
	if pendingTap and Timer.getTime(GlobalTimer) - pendingTap.t > 300 then
		local a = tapAction(pendingTap.x, pendingTap.y)
		pendingTap = nil
		if a == "menu" then
			R.menu = not R.menu
		elseif a == "next" then
			goNext()
		elseif a == "prev" then
			goPrev()
		end
	end
end

-- Rear touchpad: tap = next page, drag = scroll / pan / swipe
local function handleRear(dt)
	local ev = Rear.read(dt)
	if not ev then return end
	if ev.kind == "tap" then
		if R.transition == "next" then Reader.nextChapter() return end
		goNext()
	elseif ev.kind == "drag" then
		local dx, dy = ev.dx, ev.dy
		if isPaged() then
			local mx, my = panLimits()
			if mx > 1 or my > 1 then
				R.ox, R.oy = math.clamp(R.ox + dx, -mx, mx), math.clamp(R.oy + dy, -my, my)
				R.tox, R.toy = R.ox, R.oy
				R.fresh = false
			else
				R.rswipe = (R.rswipe or 0) + ((cfg.ReadingMode == "Vertical") and dy or dx)
			end
		else
			R.sy = math.clamp(R.sy - dy, 0, stripMax())
			R.tsy = R.sy
			R.vy = -dy / max(dt, 1) * 16
		end
	elseif ev.kind == "release" then
		local amount = R.rswipe or 0
		R.rswipe = 0
		if isPaged() and abs(amount) > 70 then
			if cfg.ReadingMode == "Vertical" then
				if amount < 0 then pagedNext(true) else pagedPrev(true) end
			else
				goVisual(amount > 0 and "left" or "right", true)
			end
		end
	end
end

function ReaderScreen:input(dt)
	if R.menu then
		menuInput()
		return
	end
	if Input.pressed(Input.BACK) then Reader.close() return end
	if Input.pressed(SCE_CTRL_TRIANGLE) then R.menu = true return end
	if Input.pressed(SCE_CTRL_START) then readerSettingsSheet() return end
	if R.total == 0 then
		if Input.pressed(SCE_CTRL_RTRIGGER) then Reader.nextChapter() end
		if Input.pressed(SCE_CTRL_LTRIGGER) then Reader.prevChapter() end
		return
	end
	if Input.pressed(SCE_CTRL_SELECT) then
		readerSet(R.series, "Rotation", table.cycle(OPT.Rotation, cfg.Rotation, 1))
		reconfigure(false)
		UI.toast(OPT.RotationLabels[table.find(OPT.Rotation, cfg.Rotation)])
		return
	end
	if Input.pressed(SCE_CTRL_SQUARE) then
		if isPaged() then
			readerSet(R.series, "ScaleType", table.cycle(OPT.ScaleType, cfg.ScaleType, 1))
			reconfigure(false)
			UI.toast(cfg.ScaleType)
		else
			toggleAuto()
		end
		return
	end
	if Input.pressed(Input.OK) and R.transition then
		if R.transition == "next" then Reader.nextChapter() else Reader.prevChapter() end
		return
	end
	if Input.pressed(Input.OK) then R.menu = true return end
	local map = DIRMAP[0]
	local inv = cfg.InvertButtons
	if Input.rep(SCE_CTRL_RTRIGGER) then if inv then goPrev(true) else goNext(true) end end
	if Input.rep(SCE_CTRL_LTRIGGER) then if inv then goNext(true) else goPrev(true) end end
	if isPaged() then
		if cfg.ReadingMode == "Vertical" then
			if Input.rep(map.down) or Input.rep(map.right) then if inv then goPrev() else goNext() end end
			if Input.rep(map.up) or Input.rep(map.left) then if inv then goNext() else goPrev() end end
		else
			if Input.rep(map.left) then goVisual(inv and "right" or "left") end
			if Input.rep(map.right) then goVisual(inv and "left" or "right") end
			if Input.rep(map.down) then
				local _, my = panLimits()
				if my > 1 and R.toy > -my + 1 then
					R.toy = math.clamp(R.toy - stepY(), -my, my)
					R.fresh = false
				else
					goNext()
				end
			end
			if Input.rep(map.up) then
				local _, my = panLimits()
				if my > 1 and R.toy < my - 1 then
					R.toy = math.clamp(R.toy + stepY(), -my, my)
					R.fresh = false
				else
					goPrev()
				end
			end
		end
	elseif R.auto then
		if Input.rep(map.down) or Input.rep(map.right) then changeAutoSpeed(1) end
		if Input.rep(map.up) or Input.rep(map.left) then changeAutoSpeed(-1) end
	else
		if Input.rep(map.down) then stripNext() end
		if Input.rep(map.up) then stripPrev() end
		if Input.rep(map.right) then stripNext(LH * 0.9) end
		if Input.rep(map.left) then stripPrev(LH * 0.9) end
	end
	handleTouch(dt)
	handleRear(dt)
end

------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------
function ReaderScreen:update(dt)
	-- "Same as app": follow auto-rotate / lock changes while reading
	if cfg.Rotation == -1 and R.total and Orient.appRotation() ~= rot then
		reconfigure(false)
	end
	if R.bright and R.bright.show > 0 then R.bright.show = R.bright.show - dt end
	local k = min(1, dt / 80)
	R.menuAnim = R.menuAnim + ((R.menu and 1 or 0) - R.menuAnim) * min(1, dt / 60)
	-- reading time: counted while there was input recently (or auto-scroll runs)
	R.clock = (R.clock or 0) + dt
	if Input.any() or Input.lx ~= 0 or Input.ly ~= 0 or R.auto then R.lastActive = R.clock end
	if R.clock - (R.lastActive or 0) < STAT_IDLE_MS then
		R.statMs = (R.statMs or 0) + dt
	end
	R.statFlush = (R.statFlush or 0) + dt
	if R.statFlush > 30000 then
		R.statFlush = 0
		flushStats()
	end
	if R.total == 0 then return end
	-- analog: left stick pans/scrolls, right stick zooms
	local slx, sly = deltaLogical(Input.lx, Input.ly)
	local srx, sry = deltaLogical(Input.rx, Input.ry)
	local speed = 1.1 * dt
	if isPaged() then
		if R.needViews then
			buildViews()
			pagedWindow()
			if R.fresh then setStart(R.freshEnd) end
		end
		if not R.menu and (slx ~= 0 or sly ~= 0) then
			R.tox = R.tox - slx * speed
			R.toy = R.toy - sly * speed
			R.ox, R.oy = R.tox, R.toy
			R.fresh = false
		end
		if not R.menu and sry ~= 0 then
			zoomAt(LW / 2, LH / 2, 1 - sry * dt / 600)
		end
		clampPan()
		if not Input.dragging then
			R.ox = R.ox + (R.tox - R.ox) * k * 1.6
			R.oy = R.oy + (R.toy - R.oy) * k * 1.6
			if R.swipe and R.swipe ~= 0 then
				R.swipe = R.swipe * (1 - min(1, dt / 60))
				if abs(R.swipe) < 1 then R.swipe = 0 end
			end
		end
		if R.anim then
			R.anim.t = R.anim.t + dt / 230
			if R.anim.t >= 1 then R.anim = nil end
		end
		if R.fresh and not R.anim then
			-- geometry may change while placeholder pages load; keep start position
			local v = R.views[R.view]
			local p = v and R.pages[v.p1]
			if p and p.state == "ready" and not R.freshApplied then
				setStart(R.freshEnd)
				R.freshApplied = true
			end
		end
	else
		if R.needLayout then layoutStrip() end
		if not R.menu and sly ~= 0 then
			R.sy = math.clamp(R.sy + sly * speed * 1.4, 0, stripMax())
			R.tsy = R.sy
			R.vy = 0
		end
		if not R.menu and slx ~= 0 and R.czoom > 1 then
			R.cx = R.cx - slx * speed
		end
		if not R.menu and sry ~= 0 then
			zoomAt(LW / 2, LH / 2, 1 - sry * dt / 600)
		end
		if R.auto and not R.menu and not Input.touch and not Rear.touching() and not Sheet.isOpen() and not R.transition then
			if R.sy >= stripMax() - 1 then
				if cfg.AutoNextChapter and R.ci < #R.series.chapters then
					Reader.nextChapter()
					return
				end
				R.auto = false
				UI.toast("Auto-scroll finished")
			else
				R.tsy = math.min(stripMax(), R.tsy + autoSpeed() * dt)
				R.sy = R.tsy
				R.vy = 0
			end
		end
		if not Input.dragging and not Rear.touching() then
			if abs(R.vy or 0) > 0.3 then
				R.sy = math.clamp(R.sy + R.vy, 0, stripMax())
				R.tsy = R.sy
				R.vy = R.vy * 0.94
			else
				R.vy = 0
				R.sy = R.sy + (R.tsy - R.sy) * k * 1.5
			end
		end
		R.sy = math.clamp(R.sy, 0, stripMax())
		local maxCx = max(0, (R.colW - LW) / 2)
		R.cx = math.clamp(R.cx, -maxCx, maxCx)
		stripWindow()
		local cur = stripCurrentPage()
		if R.sy >= stripMax() - 4 then cur = R.total end
		saveProgress(cur)
	end
end

------------------------------------------------------------------------
-- Draw
------------------------------------------------------------------------
local function drawView(vi, zoom, ox, oy, offX, offY)
	local v = R.views[vi]
	if not v then return end
	local parts, W, H = viewGeom(v)
	local zx, zy = baseZoom(W, H)
	zx, zy = zx * zoom, zy * zoom
	local left = LW / 2 + ox + offX - W * zx / 2
	local top = LH / 2 + oy + offY - H * zy / 2
	for _, part in ipairs(parts) do
		local p = part.p
		local s = part.s
		local cxp, cyp = left + part.cx * zx, top + part.cy * zy
		local w, h = part.sw * s * zx, part.sh * s * zy
		if part.rotate then w, h = part.sh * s * zx, part.sw * s * zy end
		if p.state == "ready" then
			if part.rotate then
				drawRegion(p, part.sx, part.sy, part.sw, part.sh, cxp, cyp, s * zy, s * zx, PI / 2)
			else
				drawRegion(p, part.sx, part.sy, part.sw, part.sh, cxp, cyp, s * zx, s * zy, 0)
			end
		else
			local pw, ph = min(w, LW), min(h, LH)
			drawPlaceholder(p, cxp - pw / 2, max(0, cyp - ph / 2), pw, ph, part.idx)
		end
	end
end

local function drawTransition()
	local nextCh = R.series.chapters[R.ci + 1]
	local prevCh = R.series.chapters[R.ci - 1]
	lrect(0, 0, LW, LH, C.bg)
	local cx, cy = LW / 2, LH / 2
	if R.transition == "next" then
		ltextCenter(FONT.s, cx, cy - 70, "FINISHED", C.sub)
		ltextCenter(FONT.b, cx, cy - 44, UI.fit(FONT.b, R.ch.name, LW - 60), C.text)
		if nextCh then
			ltextCenter(FONT.s, cx, cy + 10, "NEXT", C.sub)
			ltextCenter(FONT.b, cx, cy + 36, UI.fit(FONT.b, nextCh.name, LW - 60), C.accent)
			ltextCenter(FONT.s, cx, cy + 80, cfg.AutoNextChapter and "Turn the page to continue" or "Press confirm to continue", C.sub)
		else
			ltextCenter(FONT.m, cx, cy + 20, "You're all caught up", C.accent)
		end
	else
		ltextCenter(FONT.s, cx, cy - 70, "START OF", C.sub)
		ltextCenter(FONT.b, cx, cy - 44, UI.fit(FONT.b, R.ch.name, LW - 60), C.text)
		if prevCh then
			ltextCenter(FONT.s, cx, cy + 10, "PREVIOUS", C.sub)
			ltextCenter(FONT.b, cx, cy + 36, UI.fit(FONT.b, prevCh.name, LW - 60), C.accent)
		end
	end
end

local function drawPaged()
	if R.transition then
		drawTransition()
		return
	end
	local swipe = R.swipe or 0
	local vertical = cfg.ReadingMode == "Vertical"
	if R.anim then
		local e = Ease(math.clamp(R.anim.t, 0, 1))
		local dir = R.anim.dir
		local span = vertical and LH or LW
		-- incoming offset from the side of travel
		local sgn
		if vertical then sgn = dir else sgn = (cfg.ReadingMode == "RTL") and -dir or dir end
		local inOff = sgn * span * (1 - e)
		local outOff = -sgn * span * e
		if vertical then
			drawView(R.anim.from, R.anim.zoom, R.anim.ox, R.anim.oy, 0, outOff)
			drawView(R.view, R.zoom, R.ox, R.oy, 0, inOff)
		else
			drawView(R.anim.from, R.anim.zoom, R.anim.ox, R.anim.oy, outOff, 0)
			drawView(R.view, R.zoom, R.ox, R.oy, inOff, 0)
		end
	else
		if vertical then
			drawView(R.view, R.zoom, R.ox, R.oy, 0, swipe)
		else
			drawView(R.view, R.zoom, R.ox, R.oy, swipe, 0)
		end
	end
end

local function drawStrip()
	local colW = R.colW
	local x = LW / 2 + R.cx - colW / 2
	for i, p in ipairs(R.pages) do
		local y, h = R.ys[i] - R.sy, R.hs[i]
		if y + h > 0 and y < LH then
			if p.state == "ready" then
				local sx, sy, sw, sh = srcRect(p)
				local kz = colW / sw
				drawRegion(p, sx, sy, sw, sh, x + colW / 2, y + h / 2, kz, kz, 0)
			else
				drawPlaceholder(p, x, y, colW, h, i)
			end
		end
	end
	-- top card (previous chapter)
	if R.topCard > 0 and R.sy < R.topCard then
		local prevCh = R.series.chapters[R.ci - 1]
		local y = -R.sy
		ltextCenter(FONT.s, LW / 2, y + R.topCard / 2 - 20, "PREVIOUS", C.sub)
		ltextCenter(FONT.b, LW / 2, y + R.topCard / 2 + 6, UI.fit(FONT.b, prevCh.name, LW - 60), C.text)
		ltextCenter(FONT.s, LW / 2, y + R.topCard / 2 + 34, "Scroll up to open", C.sub)
	end
	-- end card
	local ey = R.endY - R.sy
	if ey < LH then
		local nextCh = R.series.chapters[R.ci + 1]
		ltextCenter(FONT.s, LW / 2, ey + 40, "END OF " .. UI.fit(FONT.s, R.ch.name, LW - 120), C.sub)
		if nextCh then
			ltextCenter(FONT.b, LW / 2, ey + 70, UI.fit(FONT.b, "Next: " .. nextCh.name, LW - 60), C.accent)
			ltextCenter(FONT.s, LW / 2, ey + 100, cfg.AutoNextChapter and "Keep scrolling to continue" or "Press R to continue", C.sub)
		else
			ltextCenter(FONT.m, LW / 2, ey + 74, "You're all caught up", C.accent)
		end
	end
end

local function bgColor()
	if cfg.Background == "Theme" then return C.bg end
	local c = BG_RGB[cfg.Background] or BG_RGB.Black
	return Color.new(c[1], c[2], c[3])
end

function ReaderScreen:draw(dt)
	Screen.clear(bgColor())
	if R.total == 0 then
		UI.textCenter(FONT.l, SCREEN_W / 2, 210, R.empty or "Empty chapter", C.accent)
		UI.textCenter(FONT.m, SCREEN_W / 2, 252, R.ch and R.ch.name or "", C.sub)
		UI.hints({{"l", ""}, {"r", "Chapter"}, {"back", "Exit"}}, SCREEN_H - 30)
		return
	end
	if isPaged() then
		if R.views then drawPaged() end
	else
		if R.ys then drawStrip() end
	end
	-- color filter + extra dimming overlay
	local f = FILTER_RGB[cfg.Filter]
	if f then
		UI.rect(0, 0, SCREEN_W, SCREEN_H, Color.new(f[1], f[2], f[3], floor(255 * cfg.FilterStrength / 100)))
	end
	-- bookmark ribbon (logical top-right corner of the reading area)
	if not R.menu and not R.transition and currentBookmarked() then
		local rx = LW - 34
		lrect(rx, 0, 16, 26, C.accent)
	end
	-- page indicator
	if cfg.PageNumber ~= "Off" and not R.menu and not R.transition then
		local cur = currentPage()
		local s = cur .. " / " .. R.total
		if cfg.PageNumber == "Page + clock" then
			local ok, h, m = pcall(System.getTime)
			if ok and h then s = s .. "   " .. string.format("%02d:%02d", h, m) end
		end
		local w = TextWidth(FONT.s, s) + 16
		UI.rect(SCREEN_W / 2 - w / 2, SCREEN_H - 24, w, 22, Color.new(0, 0, 0, 120))
		UI.textCenter(FONT.s, SCREEN_W / 2, SCREEN_H - 23, s, Color.new(220, 220, 220))
	end
	drawBrightness()
	drawMenu()
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
local function openNow(series, ci, page)
	-- one reading session at a time: close any reader still on the stack first
	local inStack = false
	for _, sc in ipairs(App.stack) do
		if sc == ReaderScreen then inStack = true end
	end
	if inStack then
		while #App.stack > 0 and App.top() ~= ReaderScreen do App.pop() end
		App.pop()
	end
	App.push(ReaderScreen, series, ci, page)
end

function Reader.open(series, ci, page)
	local m = Store.meta[series.key]
	if Settings.AskPreset and not (m and m.asked) and not Store.hasSeriesPrefs(series.key) and not Sheet.isOpen() then
		local defaultName = Store.matchPreset(function(k) return Settings[k] end)
		Reader.presetPicker("Choose how to read", nil, function(p)
			Store.applyPresetToSeries(series.key, p)
			Sheet.closeAll()
			openNow(series, ci, page)
		end, {
			{kind = "header", label = ""},
			{kind = "action", label = "Use my defaults", value = defaultName or "", run = function()
				Store.series(series.key).asked = true
				Store.mark("meta")
				Sheet.closeAll()
				openNow(series, ci, page)
			end}
		}, series.title)
		return
	end
	openNow(series, ci, page)
end

function Reader.close()
	App.pop()
end

function ReaderScreen:enter(series, ci, page)
	R = {series = series, menu = false, menuAnim = 0, zoom = 1, czoom = 1, cx = 0, ox = 0, oy = 0, tox = 0, toy = 0,
		swipe = 0, sy = 0, tsy = 0, vy = 0, defW = 1000, defH = 1450, pages = {}, total = 0,
		zmem = {}, seen = {}, statMs = 0, statPages = 0, clock = 0, lastActive = 0, auto = false}
	loadConfig()
	Covers.stopAnimations() -- animated covers use a lot of memory; pages need it now
	Reader.applyScreenLock(cfg.KeepScreenOn)
	loadChapter(math.clamp(ci or 1, 1, #series.chapters), page or 1)
end

function ReaderScreen:resume()
	-- returning from the tap-grid editor
	loadConfig()
end

function ReaderScreen:leave()
	R.leaving = true
	if R.total and R.total > 0 then saveProgress(currentPage()) end
	flushStats()
	freeAll()
	Reader.applyScreenLock(false)
	Store.flush()
	Library.version = Library.version + 1
	Orient.apply()
end

function Reader.isOpen()
	return App.top() == ReaderScreen and not (R and R.leaving)
end

function Reader.rotation()
	return rot
end

-- test/debug accessor
function Reader._state()
	return R, cfg, LW, LH
end
function Reader._reconfigure(reload)
	reconfigure(reload)
end
