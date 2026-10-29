-- Screen orientation: auto-rotate from the accelerometer, lock, remember the last one.
--  0   landscape
--  90  portrait, D-pad side down  (logical top = physical right edge)
--  270 portrait, D-pad side up
Orient = {detected = 0}

local abs = math.abs
local sensorsOn = false
local cand, candTime = nil, 0
local STABLE_MS = 450

local function sensors(on)
	if on == sensorsOn then return end
	if on then pcall(Controls.enableAccel) else pcall(Controls.disableAccel) end
	sensorsOn = on
end

function Orient.label(r)
	local i = table.find(OPT.AppRotation, r) or 1
	return OPT.AppRotationLabels[i]
end

function Orient.init()
	Orient.detected = Settings.LastOrientation or 0
	Orient.apply()
end

-- Orientation of the app screens (library, series, settings)
function Orient.appRotation()
	if Settings.AutoRotate then return Orient.detected end
	return Settings.RotateLock or 0
end

-- Which way gravity points in the screen plane. Upside-down landscape counts as landscape;
-- lying flat or in between returns nil (keep the current orientation).
function Orient.classify(x, y)
	if not x or not y then return nil end
	local ax, ay = abs(x), abs(y)
	if ax * ax + ay * ay < 0.25 then return nil end
	if ay > ax * 1.6 then return 0 end
	if ax > ay * 1.6 then
		-- checked on hardware: x > 0 when the D-pad side is down
		local r = x > 0 and 90 or 270
		if Settings.RotateFlip then r = (r == 90) and 270 or 90 end
		return r
	end
	return nil
end

function Orient.effective()
	if Reader and Reader.isOpen and Reader.isOpen() and Reader.rotation then
		return Reader.rotation()
	end
	return Orient.appRotation()
end

function Orient.apply()
	return UI.setRotation(Orient.effective())
end

function Orient.update(dt)
	local auto = Settings.AutoRotate == true
	sensors(auto)
	if auto then
		local ok, x, y = pcall(Controls.readAccel)
		local r = ok and Orient.classify(x, y) or nil
		if r and r ~= Orient.detected then
			if cand ~= r then
				cand, candTime = r, 0
			else
				candTime = candTime + dt
			end
			if candTime >= STABLE_MS then
				Orient.detected = r
				cand = nil
				Settings.LastOrientation = r
				Store.mark("settings")
			end
		else
			cand = nil
		end
	end
	Orient.apply()
end

-- Settings value for the single "Screen orientation" choice
function Orient.mode()
	return Settings.AutoRotate and "Auto" or Settings.RotateLock
end

function Orient.setMode(v)
	Settings.RotateUsed = true
	if v == "Auto" then
		Settings.AutoRotate = true
		Orient.detected = UI.rot
	else
		Settings.AutoRotate = false
		Settings.RotateLock = v
	end
	Settings.LastOrientation = (v == "Auto") and UI.rot or v
	Store.mark("settings")
	Orient.apply()
end

-- Quick lock: freeze the current orientation, or go back to auto-rotate
function Orient.toggleLock()
	Settings.RotateUsed = true
	if Settings.AutoRotate then
		Settings.AutoRotate = false
		Settings.RotateLock = Orient.detected
		UI.toast("Rotation locked · " .. Orient.label(Orient.detected))
	else
		Settings.AutoRotate = true
		Orient.detected = Settings.RotateLock or 0
		UI.toast("Auto-rotate on")
	end
	Store.mark("settings")
	Orient.apply()
end

MODE_OPTIONS = {"Auto", 0, 90, 270}
MODE_LABELS = {"Auto-rotate", "Landscape", "Portrait · D-pad down", "Portrait · D-pad up"}

------------------------------------------------------------------------
-- Rear touchpad (reader). In portrait only the half that is on top is used:
-- D-pad up (270) -> the L side, D-pad down (90) -> the R side.
------------------------------------------------------------------------
Rear = {}
local rearLast, rearStart, rearMoved, rearTime, rearActive = nil, nil, false, 0, false

local function inActiveHalf(px)
	if UI.rot == 270 then return px < PHYS_W / 2 end
	if UI.rot == 90 then return px >= PHYS_W / 2 end
	return true
end
Rear.inActiveHalf = inActiveHalf

-- Returns an event table for this frame or nil:
--  {kind = "drag", dx, dy} (logical), {kind = "tap"}, {kind = "release", moved = true}
function Rear.read(dt)
	if not Settings.RearTouch then return nil end
	local ok, x, y = pcall(Controls.readRetroTouch)
	if not ok then return nil end
	if x and Settings.RearSwap then x = PHYS_W - x end
	if x then
		if not rearLast then
			rearActive = inActiveHalf(x)
			rearStart, rearMoved, rearTime = {x = x, y = y}, false, 0
			rearLast = {x = x, y = y}
			return nil
		end
		rearTime = rearTime + dt
		local dx, dy = x - rearLast.x, y - rearLast.y
		rearLast = {x = x, y = y}
		if not rearActive then return nil end
		if abs(x - rearStart.x) > 14 or abs(y - rearStart.y) > 14 then rearMoved = true end
		if rearMoved then
			local lx, ly = UI.deltaLogical(dx, dy)
			return {kind = "drag", dx = lx, dy = ly}
		end
		return nil
	end
	if rearLast then
		rearLast = nil
		if not rearActive then return nil end
		if not rearMoved and rearTime < 350 then return {kind = "tap"} end
		if rearMoved then return {kind = "release"} end
	end
	return nil
end

function Rear.touching()
	return rearLast ~= nil and rearActive
end
