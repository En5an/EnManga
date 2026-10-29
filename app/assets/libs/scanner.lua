-- Local library scanner (Komikku "Local source" layout)
--  <root>/<Series>/<Chapter folder>/*.jpg
--  <root>/<Series>/<Chapter>.cbz|zip
--  <root>/<Series>/<Volume>/<Chapter folder or .cbz>    (one nesting level)
--  <root>/<Series>/*.jpg                                 (single chapter)
--  <root>/<Book>.cbz                                     (single chapter series)
--  <root>/<Series>/cover.jpg|folder.jpg|poster.jpg       (cover image)
--  <root>/<Shelf>/<Series>/...                           (any number of grouping folders)
--  <root>/Naruto v01.cbz, Naruto v02.cbz                 (loose files grouped by name)
Scanner = {}

local listDirectory = System.listDirectory
local doesDirExist = System.doesDirExist

local COVER_NAMES = {cover = true, folder = true, poster = true, thumb = true, thumbnail = true}

local function list(path)
	local ok, l = pcall(listDirectory, path)
	if ok and type(l) == "table" then return l end
	return {}
end

local function classify(path)
	local images, archives, dirs = {}, {}, {}
	for _, f in ipairs(list(path)) do
		local name = f.name
		if name ~= "." and name ~= ".." and not name:find("^%.") then
			if f.directory then
				dirs[#dirs + 1] = name
			elseif IsArchiveName(name) then
				archives[#archives + 1] = name
			elseif IsImageName(name) then
				images[#images + 1] = name
			end
		end
	end
	table.sort(images, NaturalLess)
	table.sort(archives, NaturalLess)
	table.sort(dirs, NaturalLess)
	return images, archives, dirs
end


local function chapterSort(a, b)
	return NaturalLess(a.name, b.name)
end

-- Names that mean "a part of one series" rather than "a different series"
local VOLUME_PATTERNS = {
	"^vol", "volume", "^v%.?%s*%d", "^tome", "^book%s*%d", "^bk%s*%d", "^part", "^season", "^s%d",
	"^arc", "^ch", "chapter", "^ep", "episode", "^extra", "^special", "^omake", "^side", "^%d+$", "^%d+[%s%.%-_]",
	"巻", "話", "章", "部", "編", "^第", "^番外"
}

-- "Vagabond v01 (2001) [Digital].cbz" -> "Vagabond"
local SPLIT_PATTERNS = {
	"[%s%-_%.]+[vV][oO][lL][uU][mM][eE][%s%._]*%d", "[%s%-_%.]+[vV][oO][lL]%.?[%s_]*%d", "[%s%-_%.]+[vV]%.?%s*%d",
	"[%s%-_%.]+[cC][hH][aA][pP][tT][eE][rR][%s%._]*%d", "[%s%-_%.]+[cC][hH]%.?[%s_]*%d", "[%s%-_%.]+[tT][oO][mM][eE][%s%._]*%d",
	"[%s%-_%.]+#%s*%d", "[%s%-_]*第", "[%s%-_%.]+%d+[%s%._%-]*$", "[%s%-_]+%d+[%s%-_]", "%d+巻", "%d+話"
}
function Scanner.seriesNameOf(stem)
	local s = stem:gsub("%b[]", " "):gsub("%b()", " "):gsub("%b{}", " ")
	s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	local cut = nil
	for _, pat in ipairs(SPLIT_PATTERNS) do
		local i = s:find(pat)
		if i and i > 1 and (not cut or i < cut) then cut = i end
	end
	if cut then s = s:sub(1, cut - 1) end
	s = s:gsub("[%s%-_%.,:]+$", "")
	if s == "" then return stem end
	return s
end

function Scanner.isVolumeName(name)
	local n = name:lower():gsub("^[%s%-%_%.%[%(]+", "")
	for _, pat in ipairs(VOLUME_PATTERNS) do
		if n:find(pat) then return true end
	end
	-- "Naruto Vol 01" style: the name carries its own volume number
	return Scanner.seriesNameOf(name) ~= name:gsub("%s+$", "")
end

-- Display names ---------------------------------------------------------------
local function trim(x)
	return (x:gsub("^[%s%-_%.,:;~]+", ""):gsub("[%s%-_%.,:;~]+$", ""))
end

-- "Vagabond (2000) [Viz] {Digital}" -> "Vagabond"; underscores become spaces
function Scanner.cleanTitle(name)
	local s = name:gsub("%b[]", " "):gsub("%b()", " "):gsub("%b{}", " ")
	if not s:find(" ") then s = s:gsub("_", " ") end
	s = trim(s:gsub("%s+", " "))
	return s ~= "" and s or name
end

local function num(d)
	local n = tonumber(d)
	if not n then return d end
	if d:find("%.") then return (tostring(n)) end
	return tostring(math.floor(n))
end

local function escape(x) return (x:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")) end

-- One part of a volume name, with the series title removed and numbering normalised:
-- "Vagabond, v02 [2002] [Viz]" -> "Vol. 2"; "Chapter 010.5" -> "Ch. 10.5"; "第3巻" stays
local function cleanPart(part, series, unit)
	local s = Scanner.cleanTitle(part)
	if series and series ~= "" then
		local low, ser = s:lower(), series:lower()
		if low:sub(1, #ser) == ser and #s > #ser then
			s = trim(s:sub(#ser + 1))
		end
	end
	local rest
	local function form(prefix, d, tail)
		tail = trim(tail or "")
		return prefix .. num(d) .. (tail ~= "" and (" · " .. tail) or "")
	end
	local d, tail
	d, tail = s:match("^[Vv][Oo][Ll][Uu][Mm][Ee]%s*%.?%s*(%d+%.?%d*)(.*)$")
	if not d then d, tail = s:match("^[Vv][Oo][Ll]%s*%.?%s*(%d+%.?%d*)(.*)$") end
	if not d then d, tail = s:match("^[Vv]%s*%.?%s*(%d+%.?%d*)(.*)$") end
	if not d then d, tail = s:match("^[Tt][Oo][Mm][Ee]%s*%.?%s*(%d+%.?%d*)(.*)$") end
	if d then
		-- "v02 c010" keeps the chapter too
		local c, t2 = (tail or ""):match("^%s*[Cc][Hh]?%s*%.?%s*(%d+%.?%d*)(.*)$")
		if c then return "Vol. " .. num(d) .. " Ch. " .. num(c) .. (trim(t2) ~= "" and (" · " .. trim(t2)) or "") end
		return form("Vol. ", d, tail)
	end
	d, tail = s:match("^[Cc][Hh][Aa][Pp][Tt][Ee][Rr]%s*%.?%s*(%d+%.?%d*)(.*)$")
	if not d then d, tail = s:match("^[Cc][Hh]%s*%.?%s*(%d+%.?%d*)(.*)$") end
	if not d then d, tail = s:match("^[Cc]%s*(%d+%.?%d*)(.*)$") end
	if d then return form("Ch. ", d, tail) end
	d, tail = s:match("^[Ee][Pp][Ii][Ss][Oo][Dd][Ee]%s*%.?%s*(%d+%.?%d*)(.*)$")
	if not d then d, tail = s:match("^[Ee][Pp]%s*%.?%s*(%d+%.?%d*)(.*)$") end
	if d then return form("Ep. ", d, tail) end
	d, tail = s:match("^#%s*(%d+%.?%d*)(.*)$")
	if d then return form("#", d, tail) end
	d, tail = s:match("^(%d+%.?%d*)(.*)$")
	if d and not (tail or ""):find("^%a") then
		return form(unit == "volume" and "Vol. " or "Ch. ", d, tail)
	end
	return s ~= "" and s or Scanner.cleanTitle(part)
end

function Scanner.volumeLabel(name, series, unit)
	local parts = {}
	for part in (name .. " / "):gmatch("(.-) / ") do
		parts[#parts + 1] = cleanPart(part, series, unit)
	end
	local label = table.concat(parts, " / ")
	if label == "" then return name end
	return label
end

-- How strongly a file name says "I am the cover" (lower is stronger, nil = not a cover)
--  1 cover.* / 表紙.*   2 folder.* / poster.*   3 cover_front.*, "cover 2".*   4 <series name>.*   5 thumb.*
function Scanner.coverRank(name, seriesName)
	if IsUnsupportedImage(name) or not IsImageName(name) then return nil end
	local stem = StripExt(name):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if stem == "cover" or stem == "表紙" then return 1 end
	if stem == "folder" or stem == "poster" then return 2 end
	if stem:find("^cover[%s%-_%.%(%[%d]") or stem:find("^表紙") or stem:find("^front[%s%-_]*cover") then return 3 end
	if seriesName then
		local sn = seriesName:lower()
		local clean = Scanner.cleanTitle(seriesName):lower()
		if stem == sn or stem == clean or Scanner.cleanTitle(StripExt(name)):lower() == clean
			or stem == sn .. " cover" or stem == clean .. " cover" then
			return 4
		end
	end
	if stem == "thumb" or stem == "thumbnail" then return 5 end
	return nil
end

-- Best cover image among a folder's images
local function coverIn(path, images, seriesName)
	local best, bestRank = nil, 99
	for _, img in ipairs(images) do
		local r = Scanner.coverRank(img, seriesName)
		if r and r < bestRank then best, bestRank = img, r end
	end
	return best and {path = PathJoin(path, best)} or nil
end

-- Pages in a folder; cover.jpg / folder.jpg never count as pages
-- Cover images are never pages, chapters or volumes. folderName lets "<Series>.jpg" count as a cover too.
local function pageCount(images, folderName)
	local n = 0
	for _, i in ipairs(images) do
		if not Scanner.coverRank(i, folderName) then n = n + 1 end
	end
	return n
end

-- Chapter entries directly inside a folder (archives + image folders).
-- prefix: label prefix for nested volume folders ("Vol 1 / ")
local function collectChapters(path, archives, dirs, prefix, out)
	for _, a in ipairs(archives) do
		local p = PathJoin(path, a)
		out[#out + 1] = {key = p, name = prefix .. StripExt(a), path = p, kind = "zip"}
	end
	local nested = {}
	for _, d in ipairs(dirs) do
		local dp = PathJoin(path, d)
		local simg, sarc, sdir = classify(dp)
		local n = pageCount(simg, d)
		if n > 0 then
			out[#out + 1] = {key = dp, name = prefix .. d, path = dp, kind = "dir", n = n, cover = coverIn(dp, simg)}
		end
		if #sarc > 0 or #sdir > 0 then
			nested[#nested + 1] = {name = d, path = dp, images = simg, archives = sarc, dirs = sdir, pages = n}
		end
	end
	return nested
end

-- A folder that holds one series. Volume sub-folders are flattened into it.
local function seriesFromDir(path, title, images, archives, dirs)
	local chapters = {}
	local nested = collectChapters(path, archives, dirs, "", chapters)
	for _, nd in ipairs(nested) do
		local before = #chapters
		local deeper = collectChapters(nd.path, nd.archives, nd.dirs, nd.name .. " / ", chapters)
		for _, dd in ipairs(deeper) do
			collectChapters(dd.path, dd.archives, {}, nd.name .. " / " .. dd.name .. " / ", chapters)
		end
		-- a volume folder's own cover.jpg becomes the cover of its first entry
		if #chapters > before and not chapters[before + 1].cover then
			chapters[before + 1].cover = coverIn(nd.path, nd.images)
		end
	end
	table.sort(chapters, chapterSort)
	if #chapters == 0 and pageCount(images, title) > 0 then
		chapters[1] = {key = path, name = title, path = path, kind = "dir", n = pageCount(images, title)}
	end
	if #chapters == 0 then return nil end
	return {key = path, title = title, path = path, chapters = chapters, cover = coverIn(path, images, title)}
end

-- Loose archives in one folder: group "Naruto v01.cbz", "Naruto v02.cbz" into one series
local function groupLooseArchives(path, archives, images, root, result)
	local groups, order = {}, {}
	for _, a in ipairs(archives) do
		local name = Scanner.seriesNameOf(StripExt(a))
		local k = name:lower()
		if not groups[k] then
			groups[k] = {name = name, files = {}}
			order[#order + 1] = k
		end
		table.insert(groups[k].files, a)
	end
	for _, k in ipairs(order) do
		local g = groups[k]
		if #g.files == 1 then
			local p = PathJoin(path, g.files[1])
			local title = StripExt(g.files[1])
			local cover = nil
			for _, img in ipairs(images) do
				if Scanner.coverRank(img, title) == 4 or Scanner.coverRank(img, g.name) == 4 then cover = {path = PathJoin(path, img)} end
			end
			result[#result + 1] = {key = p, title = title, path = p, root = root, cover = cover,
				chapters = {{key = p, name = title, path = p, kind = "zip"}}}
		else
			local chapters = {}
			for _, a in ipairs(g.files) do
				local p = PathJoin(path, a)
				chapters[#chapters + 1] = {key = p, name = StripExt(a), path = p, kind = "zip"}
			end
			table.sort(chapters, chapterSort)
			-- optional "<Series>.jpg" next to the files
			-- an image named after the series next to the files ("Naruto.jpg", "Naruto cover.png")
			local cover, best = nil, 99
			for _, img in ipairs(images) do
				local r = Scanner.coverRank(img, g.name)
				if r == 4 and r < best then cover, best = {path = PathJoin(path, img)}, r end
			end
			result[#result + 1] = {key = path .. "/#" .. g.name, title = g.name, path = path, root = root,
				chapters = chapters, cover = cover, grouped = true}
		end
	end
end

-- Decide what a folder is: one series, or a shelf of several series
local function scanFolder(path, title, root, depth, result)
	local images, archives, dirs = classify(path)
	local hasCover = coverIn(path, images, title) ~= nil
	local chapterDirs, partDirs, otherDirs = 0, 0, 0
	local infos = {}
	for _, d in ipairs(dirs) do
		local dp = PathJoin(path, d)
		local simg, sarc, sdir = classify(dp)
		local info = {name = d, path = dp, pages = pageCount(simg, d), arch = #sarc, sub = #sdir}
		infos[#infos + 1] = info
		if info.pages > 0 then
			chapterDirs = chapterDirs + 1
		elseif info.arch > 0 or info.sub > 0 then
			if Scanner.isVolumeName(d) then partDirs = partDirs + 1 else otherDirs = otherDirs + 1 end
		end
	end
	local ownContent = #archives > 0 or chapterDirs > 0 or pageCount(images, title) > 0
	-- A shelf: no pages/archives of its own, and sub-folders named like titles, not like volumes
	local isShelf = depth < 4 and not hasCover and otherDirs > 0 and otherDirs >= partDirs
		and chapterDirs == 0 and pageCount(images, title) == 0
	if isShelf then
		if #archives > 0 then groupLooseArchives(path, archives, images, root, result) end
		for _, info in ipairs(infos) do
			if info.pages == 0 and (info.arch > 0 or info.sub > 0) then
				scanFolder(info.path, info.name, root, depth + 1, result)
			end
		end
		return
	end
	if not ownContent and partDirs == 0 and otherDirs == 0 then return end
	local s = seriesFromDir(path, title, images, archives, dirs)
	if s then
		s.root = root
		result[#result + 1] = s
	end
end

-- Scan all roots. Runs as a coroutine: yields (message, progress0to1).
function Scanner.scan(roots)
	local result = {}
	local seen = {}
	local valid = {}
	for _, r in ipairs(roots) do
		local root = r:gsub("/+$", "")
		local dev = root:match("^(%w+0):")
		if dev and doesDirExist(dev .. ":") ~= false and doesDirExist(root) and not seen[root] then
			seen[root] = true
			valid[#valid + 1] = root
		end
	end
	local steps, done = 0, 0
	local plan = {}
	for _, root in ipairs(valid) do
		local images, archives, dirs = classify(root)
		plan[#plan + 1] = {root = root, images = images, archives = archives, dirs = dirs}
		steps = steps + #dirs + 1
	end
	for _, pl in ipairs(plan) do
		-- the root itself is always a shelf
		groupLooseArchives(pl.root, pl.archives, pl.images, pl.root, result)
		done = done + 1
		for _, d in ipairs(pl.dirs) do
			scanFolder(PathJoin(pl.root, d), d, pl.root, 1, result)
			done = done + 1
			if coroutine.running() then coroutine.yield(d, done / math.max(1, steps)) end
		end
	end
	-- drop duplicates (same folder reached from two roots)
	local uniq, out = {}, {}
	for _, s in ipairs(result) do
		if not uniq[s.key] then
			uniq[s.key] = true
			out[#out + 1] = s
		end
	end
	table.sort(out, function(a, b) return NaturalLess(a.title, b.title) end)
	return out, #valid
end

-- Page list for a chapter: { {path=..., extract=...|nil, name=...}, ... }
function Scanner.pages(ch)
	local pages = {}
	if ch.kind == "zip" then
		local ok, z = pcall(System.listZip, ch.path)
		if not ok or type(z) ~= "table" then return pages, "Cannot open archive" end
		local names = {}
		for _, f in ipairs(z) do
			local n = f.name
			if not f.directory and IsImageName(BaseName(n)) and not n:find("__MACOSX", 1, true) then
				names[#names + 1] = n
			end
		end
		table.sort(names, NaturalLess)
		for _, n in ipairs(names) do
			pages[#pages + 1] = {path = ch.path, extract = n, name = BaseName(n)}
		end
	else
		local images = classify(ch.path)
		local folder = BaseName(ch.path)
		local filtered = {}
		for _, n in ipairs(images) do
			if not Scanner.coverRank(n, folder) then filtered[#filtered + 1] = n end
		end
		for _, n in ipairs(filtered) do
			pages[#pages + 1] = {path = PathJoin(ch.path, n), name = n}
		end
	end
	return pages
end

-- First usable page of a chapter (for covers)
function Scanner.firstPage(ch)
	local pages = Scanner.pages(ch)
	for _, p in ipairs(pages) do
		if not IsUnsupportedImage(p.name) then return p end
	end
	return pages[1]
end

-- Folder browsing for the folder picker
function Scanner.listFolders(path)
	local out = {}
	for _, f in ipairs(list(path)) do
		if f.directory and f.name ~= "." and f.name ~= ".." and not f.name:find("^%.") then
			out[#out + 1] = f.name
		end
	end
	table.sort(out, NaturalLess)
	return out
end
