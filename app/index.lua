-- EnManga bootstrap
-- Runtime: NOBORU's lpp-vita fork (LuaJIT 2.0.5). Based on NOBORU by Creckeryop (GPL-3.0).

DATA_DIR = "ux0:data/enmanga"
APP_VERSION = "Beta 1.0"

DRAW_PHASE = false
local oldInit = Graphics.initBlend
local oldTerm = Graphics.termBlend
function Graphics.initBlend()
	DRAW_PHASE = true
	oldInit()
end
function Graphics.termBlend()
	DRAW_PHASE = false
	oldTerm()
end

if not System.doesDirExist(DATA_DIR) then
	System.createDirectory(DATA_DIR)
end

-- Append a line to ux0:data/enmanga/log.txt (kept small)
function LogWrite(msg)
	local path = DATA_DIR .. "/log.txt"
	local old = ""
	if System.doesFileExist(path) then
		local fh = System.openFile(path, FREAD)
		local size = System.sizeFile(fh)
		if size > 0 and size < 32768 then
			old = System.readFile(fh, size)
		end
		System.closeFile(fh)
		System.deleteFile(path)
	end
	local fh = System.openFile(path, FCREATE)
	local s = old .. tostring(msg) .. "\n"
	System.writeFile(fh, s, #s)
	System.closeFile(fh)
end

local df = dofile
function loadlib(name)
	df("app0:assets/libs/" .. name .. ".lua")
end

local ok, err = xpcall(dofile, debug.traceback, "app0:main.lua")
if not ok then
	if DRAW_PHASE then
		oldTerm()
		DRAW_PHASE = false
	end
	pcall(LogWrite, "[CRASH] " .. tostring(err))
	-- Crash screen: show error, START exits
	local lines = {}
	for line in (tostring(err) .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = (line:gsub("\t", "  "))
	end
	local pad = Controls.read()
	while true do
		local old = pad
		pad = Controls.read()
		oldInit()
		Screen.clear(Color.new(18, 18, 20))
		Graphics.debugPrint(20, 16, "EnManga hit an error. Details saved to ux0:data/enmanga/log.txt", Color.new(255, 120, 120))
		Graphics.debugPrint(20, 40, "Press START to exit.", Color.new(200, 200, 200))
		for i = 1, math.min(#lines, 24) do
			Graphics.debugPrint(20, 56 + i * 19, lines[i], Color.new(230, 230, 230))
		end
		oldTerm()
		Screen.flip()
		Screen.waitVblankStart()
		if Controls.check(pad, SCE_CTRL_START) and not Controls.check(old, SCE_CTRL_START) then
			System.exit()
		end
	end
end
