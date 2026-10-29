-- EnManga main
Console = {
	write = function() end,
	error = function(msg) Log("[console] " .. tostring(msg)) end
}

loadlib("core")
loadlib("image")
loadlib("glyphs")
loadlib("ui")

GlobalTimer = Timer.new()

-- Boot splash ------------------------------------------------------------------
local logo = nil
pcall(function()
	logo = Graphics.loadImage("app0:assets/images/logo.png")
	Graphics.setImageFilters(logo, FILTER_LINEAR, FILTER_LINEAR)
end)

local function splash(msg, progress)
	Graphics.initBlend()
	Screen.clear(Color.new(17, 17, 19))
	if logo then
		local w, h = Graphics.getImageWidth(logo), Graphics.getImageHeight(logo)
		Graphics.drawImage(math.floor(480 - w / 2), math.floor(225 - h / 2), logo)
	end
	if msg then
		UI.textCenter(FONT.s, 480, 360, UI.fit(FONT.s, msg, 700), Color.new(140, 140, 150))
	end
	if progress then
		UI.rect(330, 392, 300, 2, Color.new(50, 50, 56))
		UI.rect(330, 392, math.floor(300 * math.clamp(progress, 0, 1)), 2, C.accent)
	end
	Graphics.termBlend()
	Screen.flip()
	Screen.waitVblankStart()
end

splash("Starting...")

loadlib("loader")
loadlib("store")
loadlib("orient")
loadlib("scanner")
loadlib("covers")
loadlib("library")
loadlib("home")
loadlib("series")
loadlib("reader")
loadlib("tapgrid")
loadlib("colorpicker")

EnsureDir(DATA_DIR)
EnsureDir(DATA_DIR .. "/temp")
EnsureDir(DATA_DIR .. "/import")

local README = DATA_DIR .. "/import/README.txt"
if not System.doesFileExist(README) then
	WriteFile(README, table.concat({
		"EnManga - put your manga here (or in ux0:manga / uma0:manga).",
		"",
		"Supported layouts:",
		"  Series Name/Chapter 01/001.jpg ...",
		"  Series Name/Chapter 01.cbz",
		"  Series Name/Volume 01/Chapter 01.cbz",
		"  Series Name/001.jpg ...            (single chapter)",
		"  Book Title.cbz                     (single chapter)",
		"  Series Name/cover.jpg              (optional cover)",
		"",
		"Images: JPG, PNG, BMP, GIF. WebP is NOT supported by the Vita runtime -",
		"convert WebP pages to JPG first with EnManga-Converter.html (see the EnManga page on GitHub).",
		"Archives: .cbz / .zip. CBR/RAR is not supported.",
		""
	}, "\r\n"))
end

Store.load()

-- Library: show cached results instantly, rescan in background ------------------
local cached = Store.loadScanCache()
if cached and #cached > 0 then
	Library.set(cached)
	if Settings.ScanOnStart then
		Library.rescan()
	end
else
	Library.scanBlocking(function(msg, prog)
		splash("Scanning " .. (msg or ""), prog)
	end)
end

if logo then
	Graphics.freeImage(logo)
	logo = nil
end

Orient.init()
App.push(Home.screen)

-- Main loop ----------------------------------------------------------------------
local frameTimer = Timer.new()
while true do
	local dt = Timer.getTime(frameTimer)
	Timer.reset(frameTimer)
	dt = math.clamp(dt, 1, 100)

	Fonts.maintain()
	Orient.update(dt)
	Covers.tick()
	local keyboard = UI.updateKeyboard()
	Input.update(dt)
	local screen = App.top()
	if not keyboard then
		if Sheet.isOpen() then
			Sheet.input()
		elseif screen and screen.input then
			screen:input(dt)
		end
	end
	screen = App.top()
	if screen and screen.update then screen:update(dt) end
	Loader.update()
	Library.update(6)
	Store.update(dt)

	Graphics.initBlend()
	if screen and screen.draw then screen:draw(dt) end
	Sheet.draw(dt)
	UI.drawToast(dt)
	Graphics.termBlend()
	Screen.flip()
	Screen.waitVblankStart()
end
