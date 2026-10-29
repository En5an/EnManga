-- Core helpers shared by every module
SCREEN_W, SCREEN_H = 960, 544
PI = math.pi

local floor, min, max = math.floor, math.min, math.max
local format = string.format
local doesFileExist = System.doesFileExist
local doesDirExist = System.doesDirExist
local openFile, readFile, writeFile, closeFile, sizeFile = System.openFile, System.readFile, System.writeFile, System.closeFile, System.sizeFile
local deleteFile, rename = System.deleteFile, System.rename

function math.clamp(v, a, b)
	if v < a then return a elseif v > b then return b end
	return v
end

function math.lerp(a, b, t)
	return a + (b - a) * t
end

function math.round(v)
	return floor(v + 0.5)
end

function Ease(t)
	if t < 0.5 then return 4 * t * t * t end
	local f = 2 * t - 2
	return 0.5 * f * f * f + 1
end

-- UTF-8 ------------------------------------------------------------
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"
function Utf8Chars(s)
	return s:gmatch(UTF8_CHAR)
end

function Utf8Len(s)
	local n = 0
	for _ in s:gmatch(UTF8_CHAR) do n = n + 1 end
	return n
end

-- File IO ----------------------------------------------------------
function ReadFile(path)
	if not doesFileExist(path) then return nil end
	local fh = openFile(path, FREAD)
	if not fh then return nil end
	local size = sizeFile(fh)
	local data = size > 0 and readFile(fh, size) or ""
	closeFile(fh)
	return data
end

-- Write via temp file + rename so a power-off mid-save never leaves a half file
function WriteFile(path, data)
	local tmp = path .. ".tmp"
	if doesFileExist(tmp) then deleteFile(tmp) end
	local fh = openFile(tmp, FCREATE)
	if not fh then return false end
	writeFile(fh, data, #data)
	closeFile(fh)
	if doesFileExist(path) then deleteFile(path) end
	rename(tmp, path)
	return true
end

function EnsureDir(path)
	if not doesDirExist(path) then
		System.createDirectory(path)
	end
end

-- Serialization (round-trips any string safely via %q) -------------
local function ser(v, indent, out)
	local t = type(v)
	if t == "string" then
		out[#out + 1] = format("%q", v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			out[#out + 1] = "0"
		elseif v == floor(v) and v > -1e15 and v < 1e15 then
			out[#out + 1] = format("%.0f", v)
		else
			out[#out + 1] = format("%.17g", v)
		end
	elseif t == "boolean" then
		out[#out + 1] = v and "true" or "false"
	elseif t == "table" then
		out[#out + 1] = "{\n"
		local pad = string.rep(" ", indent + 1)
		local n = #v
		for i = 1, n do
			out[#out + 1] = pad
			ser(v[i], indent + 1, out)
			out[#out + 1] = ",\n"
		end
		for k, val in pairs(v) do
			local kt = type(k)
			if not (kt == "number" and k >= 1 and k <= n and k == floor(k)) and (kt == "string" or kt == "number") then
				local vt = type(val)
				if vt == "string" or vt == "number" or vt == "boolean" or vt == "table" then
					out[#out + 1] = pad .. "["
					ser(k, indent + 1, out)
					out[#out + 1] = "] = "
					ser(val, indent + 1, out)
					out[#out + 1] = ",\n"
				end
			end
		end
		out[#out + 1] = string.rep(" ", indent) .. "}"
	else
		out[#out + 1] = "nil"
	end
end

function Serialize(v)
	local out = {"return "}
	ser(v, 0, out)
	return table.concat(out)
end

function SaveTable(path, t)
	local ok, err = pcall(WriteFile, path, Serialize(t))
	if not ok then
		Log("save failed " .. path .. ": " .. tostring(err))
	end
	return ok
end

function LoadTable(path)
	local data = ReadFile(path)
	if not data then
		-- fall back to an interrupted save
		data = ReadFile(path .. ".tmp")
		if not data then return nil end
	end
	local fn = loadstring(data)
	if not fn then
		Log("corrupt file ignored: " .. path)
		return nil
	end
	setfenv(fn, {})
	local ok, res = pcall(fn)
	if ok and type(res) == "table" then
		return res
	end
	return nil
end

function Log(msg)
	pcall(LogWrite, msg)
end

-- Natural sort: "Ch 2" < "Ch 10", "Vol.1 Ch.10.5" handled ---------
local naturalKeys = {}
local naturalCount = 0
function NaturalKey(s)
	local k = naturalKeys[s]
	if k then return k end
	k = s:lower():gsub("^%s+", ""):gsub("%d+", function(d)
		d = d:gsub("^0+(%d)", "%1")
		if #d < 12 then
			return string.rep("0", 12 - #d) .. d
		end
		return d
	end)
	naturalCount = naturalCount + 1
	if naturalCount > 4000 then
		naturalKeys = {}
		naturalCount = 0
	end
	naturalKeys[s] = k
	return k
end

function NaturalLess(a, b)
	local ka, kb = NaturalKey(a), NaturalKey(b)
	if ka == kb then return a < b end
	return ka < kb
end

-- Time -------------------------------------------------------------
-- Composite sortable stamp YYYYMMDDhhmmss as a number
function Now()
	local ok, _, d, m, y = pcall(System.getDate)
	local ok2, h, mi, s = pcall(System.getTime)
	if not ok or not ok2 or not y then
		return 0
	end
	return ((((y * 100 + m) * 100 + d) * 100 + h) * 100 + mi) * 100 + s
end

function StampDate(stamp)
	if not stamp or stamp == 0 then return "" end
	local s = floor(stamp)
	local y = floor(s / 1e10)
	local mo = floor(s / 1e8) % 100
	local d = floor(s / 1e6) % 100
	local h = floor(s / 1e4) % 100
	local mi = floor(s / 100) % 100
	return format("%04d-%02d-%02d %02d:%02d", y, mo, d, h, mi)
end

function StampDay(stamp)
	if not stamp or stamp == 0 then return 0 end
	return floor(stamp / 1e6)
end

-- Paths ------------------------------------------------------------
function PathJoin(a, b)
	if a:sub(-1) == "/" then return a .. b end
	return a .. "/" .. b
end

function BaseName(p)
	p = p:gsub("/+$", "")
	return p:match("([^/]+)$") or p
end

function StripExt(name)
	return name:match("^(.*)%.[^%.]+$") or name
end

function Ext(name)
	local e = name:match("%.([^%./]+)$")
	return e and e:lower() or ""
end

IMAGE_EXT = {jpg = true, jpeg = true, png = true, bmp = true, gif = true, webp = true, jfif = true}
ARCHIVE_EXT = {cbz = true, zip = true}

function IsImageName(name)
	if name:find("^%._") then return false end -- macOS resource forks
	return IMAGE_EXT[Ext(name)] == true
end

function IsArchiveName(name)
	if name:find("^%._") then return false end
	return ARCHIVE_EXT[Ext(name)] == true
end

function IsUnsupportedImage(name)
	return Ext(name) == "webp"
end

-- Tables -----------------------------------------------------------
function table.find(t, v)
	for i = 1, #t do
		if t[i] == v then return i end
	end
	return nil
end

function table.cycle(list, current, dir)
	local i = table.find(list, current) or 1
	i = i + (dir or 1)
	if i > #list then i = 1 elseif i < 1 then i = #list end
	return list[i]
end

function table.shallow(t)
	local r = {}
	for k, v in pairs(t) do r[k] = v end
	return r
end

function table.reverse(t)
	local i, j = 1, #t
	while i < j do
		t[i], t[j] = t[j], t[i]
		i, j = i + 1, j - 1
	end
	return t
end
