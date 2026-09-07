-- BSMT UI Library (embedded - no external dependencies)
-- ──────────────────────────────────────────────────────────────────────────
-- BSMT backwards-Android compatibility shim.
-- Older Android Roblox clients / mobile executors may lack newer APIs
-- (task.*, math.clamp/round, table.find, coroutine.close, UDim2.fromScale /
-- fromOffset, TextService:GetTextBoundsAsync + FontFace, UIStroke tweaks).
-- Everything below backfills or works around those gaps. Safe to run twice.
-- Uses only ancient-safe Luau syntax (no annotations, no compound assigns).
-- ──────────────────────────────────────────────────────────────────────────
do
	-- math.clamp / math.round (missing on old clients)
	if math ~= nil then
		if math.clamp == nil then
			function math.clamp(v, a, b)
				v = tonumber(v) or 0
				if a ~= nil and v < a then return a end
				if b ~= nil and v > b then return b end
				return v
			end
		end
		if math.round == nil then
			function math.round(v)
				v = tonumber(v) or 0
				if v >= 0 then return math.floor(v + 0.5) end
				return math.ceil(v - 0.5)
			end
		end
	end

	-- table.find (missing on old clients)
	if table ~= nil and table.find == nil then
		function table.find(tbl, val, init)
			if type(tbl) ~= "table" then return nil end
			local i = init or 1
			for idx = i, #tbl do
				if tbl[idx] == val then return idx end
			end
			return nil
		end
	end

	-- task.* (very old clients only have global spawn/wait/delay)
	if task == nil then task = {} end
	if task.spawn == nil then
		if spawn ~= nil then task.spawn = spawn
		else function task.spawn(fn, ...) local a = {...} coroutine.resume(coroutine.create(function() fn(unpack(a)) end)) end end
	end
	if task.wait == nil then
		if wait ~= nil then task.wait = wait else function task.wait() return 0 end end
	end
	if task.delay == nil then
		if delay ~= nil then task.delay = delay
		else function task.delay(_, fn, ...) if fn then task.spawn(fn, ...) end return nil end end
	end
	if task.defer == nil then
		function task.defer(fn, ...) local a = {...} task.spawn(function() fn(unpack(a)) end) end
	end

	-- coroutine.close (missing on old Lua; the GC collects the thread anyway)
	if coroutine ~= nil and coroutine.close == nil then
		function coroutine.close(_) return true end
	end

	-- typeof fallback (very old clients)
	if typeof == nil then
		function typeof(v)
			local t = type(v)
			if t == "userdata" then
				local ok, _ = pcall(function() return v.ClassName end)
				if ok then return "Instance" end
			end
			return t
		end
	end

	-- UDim2.fromScale / fromOffset as globals (old clients lack them, and the
	-- UDim2 table itself is read-only so it cannot be backfilled in place).
	-- Call sites further down use UDim2FromScale / UDim2FromOffset instead.
	if UDim2FromScale == nil then
		local okF, fn = pcall(function() return UDim2["from" .. "Scale"] end)
		if okF and type(fn) == "function" then
			function UDim2FromScale(x, y) return fn(x, y) end
		else
			function UDim2FromScale(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end
		end
	end
	if UDim2FromOffset == nil then
		local okF2, fn2 = pcall(function() return UDim2["from" .. "Offset"] end)
		if okF2 and type(fn2) == "function" then
			function UDim2FromOffset(x, y) return fn2(x, y) end
		else
			function UDim2FromOffset(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
		end
	end

	-- Nil-safe viewport reader (CurrentCamera can be nil while mobile loads,
	-- and a value cached once at startup goes stale on rotation / resize).
	if BSMT_GetViewportSize == nil then
		function BSMT_GetViewportSize()
			local ok, sz = pcall(function()
				local cam = workspace.CurrentCamera
				if cam then return cam.ViewportSize end
				return nil
			end)
			if ok and typeof(sz) == "Vector2" then return sz end
			return Vector2.new(800, 600)
		end
	end

	-- Nil-safe FontFace reader (the property only exists on newer clients).
	if BSMT_GetFontFace == nil then
		function BSMT_GetFontFace(label)
			local ok, ff = pcall(function() return label.FontFace end)
			if ok then return ff end
			return nil
		end
	end

	-- Text measurement that works on old clients: prefers
	-- GetTextBoundsAsync, falls back to GetTextSize, then estimates.
	if BSMT_MeasureText == nil then
		function BSMT_MeasureText(text, size, fontFace, fontEnum, width)
			text = tostring(text or "")
			size = size or 14
			width = width or 10000
			local okTs, ts = pcall(function() return game:GetService("TextService") end)
			if okTs and ts then
				if fontFace ~= nil then
					local ok, res = pcall(function()
						local p = Instance.new("GetTextBoundsParams")
						p.Text = text
						p.Font = fontFace
						p.Size = size
						p.Width = width
						return ts:GetTextBoundsAsync(p)
					end)
					if ok and typeof(res) == "Vector2" then return res end
				end
				local ok2, res2 = pcall(function()
					return ts:GetTextSize(text, size, fontEnum or Enum.Font.SourceSans, Vector2.new(width, 100000))
				end)
				if ok2 and typeof(res2) == "Vector2" then return res2 end
			end
			return Vector2.new(#text * (size * 0.6), size)
		end
	end

	-- UIStroke border-mode guard (the ApplyStrokeMode enum is missing on old
	-- clients; without this the assignment errors and GUI building aborts).
	if BSMT_ApplyBorderStroke == nil then
		function BSMT_ApplyBorderStroke(stroke)
			pcall(function()
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end)
		end
	end
end
local Library = (function()
_G.BSMTExistingHooks = _G.BSMTExistingHooks or {}
if not _G.BSMTExistingHooks.GuiDetectionBypass then
    local CoreGui = nil
    pcall(function() CoreGui = game:GetService("CoreGui") end)
    if CoreGui == nil then pcall(function() CoreGui = game.CoreGui end) end
    local ContentProvider = game.ContentProvider
    local RobloxGuis = {"RobloxGui", "TeleportGui", "RobloxPromptGui", "RobloxLoadingGui", "PlayerList", "RobloxNetworkPauseNotification", "PurchasePrompt", "HeadsetDisconnectedDialog", "ThemeProvider", "DevConsoleMaster"}

    local hookfunc = hookfunction or hookfunc or replaceclosure
    local hookmetamethod = hookmetamethod or hookmetamethods
    
    -- Backwards-Android note: lack of hooking must only skip the bypass, never
    -- abort the whole UI library (many mobile executors have no hookfunction).
    local hookOK = (hookfunc ~= nil)
    if not hookOK then
        warn("Executor doesn't support function hooking - GUI detection bypass disabled")
    else

    -- syn_context_* is Synapse-only; guard so this doesn't error on SUNC/other executors
    local hasSynContext = (syn_context_get ~= nil and syn_context_set ~= nil)

    local function FilterTable(tbl)
        if CoreGui == nil then return tbl end
        local context = hasSynContext and syn_context_get() or nil
        if hasSynContext then syn_context_set(7) end
        local new = {}
        for i,v in ipairs(tbl) do 
            if typeof(v) ~= "Instance" then
                table.insert(new, v)
            else
                if v == CoreGui or v == game then
                    --insert only the default roblox guis
                    for i,v in pairs(RobloxGuis) do
                        local gui = CoreGui:FindFirstChild(v)
                        if gui then
                            table.insert(new, gui)
                        end
                    end
    
                    if v == game then
                        for i,v in pairs(game:GetChildren()) do
                            if v ~= CoreGui then
                                table.insert(new, v)
                            end
                        end
                    end
                else
                    if not CoreGui:IsAncestorOf(v) then
                        table.insert(new, v)
                    else
                        --don't insert it if it's a descendant of a different gui than default roblox guis
                        for j,k in pairs(RobloxGuis) do
                            local gui = CoreGui:FindFirstChild(k)
                            if gui then
                                if v == gui or gui:IsAncestorOf(v) then
                                    table.insert(new, v)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if hasSynContext then syn_context_set(context) end
        return new
    end
    
    local old
    old = hookfunc(ContentProvider.PreloadAsync, function(self, tbl, cb)
        if self ~= ContentProvider or type(tbl) ~= "table" or type(cb) ~= "function" then --note: callback can be nil but in that case it's useless anyways
            return old(self, tbl, cb)
        end
    
        --check for any errors that I might've missed (such as table being {[2] = "something"} which causes "Unable to cast to Array")
        local err
        task.spawn(function() --TIL pcalling a C yield function inside a C yield function is a bad idea ("cannot resume non-suspended coroutine")
            local s,e = pcall(old, self, tbl)
            if not s and e then
                err = e
            end
        end)
       
        if err then
            return old(self, tbl) --don't pass the callback, just in case
        end
    
        tbl = FilterTable(tbl)
        return old(self, tbl, cb)
    end)
    
    -- hookmetamethod / namecall helpers are also missing on some mobile
    -- executors; guard so a half-present hook API can't kill the library.
    if hookmetamethod ~= nil and getnamecallmethod ~= nil and setnamecallmethod ~= nil then
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if self == ContentProvider and (method == "PreloadAsync" or method == "preloadAsync") then
            local args = {...}
            if type(args[1]) ~= "table" or type(args[2]) ~= "function" then
                return old(self, ...)
            end
    
            local err
            task.spawn(function()
                setnamecallmethod(method) --different thread, different namecall method
                local s,e = pcall(old, self, args[1])
                if not s and e then
                    err = e
                end
            end)
    
            if err then
                return old(self, args[1])
            end
    
            args[1] = FilterTable(args[1])
            setnamecallmethod(method)
            return old(self, args[1], args[2])
        end
        return old(self, ...)
    end)
    end -- close hookmetamethod availability guard
    end -- close else (hooking supported; without it we just skip the bypass)
    
    _G.BSMTExistingHooks.GuiDetectionBypass = true
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Backwards-Android note: getconnections is missing on many mobile executors;
-- the anti-AFK disable must never error and kill the whole script.
if typeof(getconnections) == "function" then
	local okConns, idleConns = pcall(getconnections, player.Idled)
	if okConns and typeof(idleConns) == "table" then
		for _, connection in pairs(idleConns) do
			pcall(function()
				if connection.Enabled then
					connection:Disable()
				end
			end)
		end
	end
end


local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local mouse = nil
pcall(function() mouse = player:GetMouse() end)
if mouse == nil then
	-- Touch-only Android: stub so desktop-only code paths don't error.
	-- Real touch positions are threaded through InputBegan/TouchMoved instead.
	mouse = { X = 0, Y = 0, Move = { Connect = function() return { Disconnect = function() end } end } }
end
local viewPortSize = BSMT_GetViewportSize()
-- Refresh on rotation / window resize; a value cached once at startup goes
-- stale on Android and the window clamps itself to the wrong bounds.
pcall(function()
	local camNow = workspace.CurrentCamera
	if camNow then
		camNow:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			viewPortSize = BSMT_GetViewportSize()
		end)
	end
end)

local function parentProtected(gui)
	pcall(function()
		if syn and syn.protect_gui then syn.protect_gui(gui)
		elseif protectgui then protectgui(gui)
		elseif protect_gui then protect_gui(gui) end
	end)
	local ok = pcall(function()
		if gethui then
			gui.Parent = gethui()
		elseif cloneref then
			gui.Parent = cloneref(game:GetService("CoreGui"))
		else
			gui.Parent = game:GetService("CoreGui")
		end
	end)
	if not ok or not gui.Parent then
		pcall(function() gui.Parent = player:WaitForChild("PlayerGui") end)
	end
	return gui
end

-- ╔══════════════════════════════════════════════╗
-- ║  BSMT – getgenv() flag binding                ║
-- ║  Lets sliders / colorwheels stay in sync with ║
-- ║  a global, e.g. getgenv().speed = 100         ║
-- ╚══════════════════════════════════════════════╝
local genv = (getgenv and getgenv()) or _G

-- flag -> { last = <value>, apply = function(v), busy = function()->bool }
local genvWatchers = {}
local genvWatchStarted = false

local function startGenvWatch()
	if genvWatchStarted then return end
	genvWatchStarted = true
	task.spawn(function()
		while true do
			for flag, w in pairs(genvWatchers) do
				local v = genv[flag]
				-- External change detected (and the element isn't being dragged)
				if v ~= nil and v ~= w.last and not (w.busy and w.busy()) then
					w.last = v
					pcall(w.apply, v)
					-- Re-sync to whatever apply wrote back (HSV round-trips can differ
					-- slightly) so we don't fire again on our own write.
					w.last = genv[flag]
				end
			end
			task.wait(0.12)
		end
	end)
end

-- Register a flag to mirror into an element. `apply(v)` updates the element,
-- `busy()` (optional) returns true while the user is actively dragging it.
local function watchGenv(flag, apply, busy)
	genvWatchers[flag] = { last = genv[flag], apply = apply, busy = busy }
	startGenvWatch()
end

-- Any touchscreen device counts as mobile, even with a mouse/keyboard attached
-- (DeX / BT mouse on Android); the old `not MouseEnabled` check misdetected those.
local isMobile = false
pcall(function()
	isMobile = (UserInputService.TouchEnabled == true)
end)

local BINDABLE_MOUSE_TYPES = {
    [Enum.UserInputType.MouseButton1] = "MB1",
    [Enum.UserInputType.MouseButton2] = "MB2",
    [Enum.UserInputType.MouseButton3] = "MB3",
}
local MOUSE_TYPE_FROM_NAME = {}
for ut, name in pairs(BINDABLE_MOUSE_TYPES) do
    MOUSE_TYPE_FROM_NAME[name] = ut
end

local MOUSE_DISPLAY = {
    MB1 = "LClick", MB2 = "RClick", MB3 = "M3",
}

local function resolveBinding(input)
    -- Keyboard
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Unknown then return nil, nil end
        return input.KeyCode.Name, { kind="Key", keyCode=input.KeyCode }
    end
    -- Mouse buttons
    local mbName = BINDABLE_MOUSE_TYPES[input.UserInputType]
    if mbName then
        return MOUSE_DISPLAY[mbName] or mbName,
               { kind="Mouse", inputType=input.UserInputType }
    end
    -- Scroll
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        local dir = input.Position.Z > 0 and 1 or -1
        local dispName = dir > 0 and "ScrlUp" or "ScrlDn"
        return dispName, { kind="Scroll", direction=dir }
    end
    return nil, nil
end

local function bindingMatches(input, binding)
    if not binding then return false end
    if binding.kind == "Key" then
        return input.UserInputType == Enum.UserInputType.Keyboard
               and input.KeyCode == binding.keyCode
    elseif binding.kind == "Mouse" then
        return input.UserInputType == binding.inputType
    elseif binding.kind == "Scroll" then
        return input.UserInputType == Enum.UserInputType.MouseWheel
               and ((input.Position.Z > 0) == (binding.direction > 0))
    end
    return false
end

-- Encode/decode for config saving
local function encodeBinding(binding)
    if not binding then return "" end
    if binding.kind == "Key"    then return "Key:"    .. binding.keyCode.Name end
    if binding.kind == "Mouse"  then return "Mouse:"  .. binding.inputType.Name end
    if binding.kind == "Scroll" then return "Scroll:" .. tostring(binding.direction) end
    return ""
end

local function decodeBinding(str)
    if not str or str == "" then return nil, nil end
    local kind, val = str:match("^(%a+):(.+)$")
    if kind == "Key" then
        for _, kc in pairs(Enum.KeyCode:GetEnumItems()) do
            if kc.Name == val then
                return kc.Name, { kind="Key", keyCode=kc }
            end
        end
    elseif kind == "Mouse" then
        for ut, name in pairs(BINDABLE_MOUSE_TYPES) do
            if ut.Name == val then
                return MOUSE_DISPLAY[name] or name, { kind="Mouse", inputType=ut }
            end
        end
    elseif kind == "Scroll" then
        local d = tonumber(val)
        if d then
            return (d > 0 and "ScrlUp" or "ScrlDn"), { kind="Scroll", direction=d }
        end
    end
    return nil, nil
end
-- ──────────────────────────────────────────────────────────────────────────────
local scaleFactor = math.clamp(viewPortSize.Y / 1080, 0.6, 1.4)

-- Theme: single source of truth for all colours.
-- Every element factory reads these keys, so Library.SetTheme{} can re-skin live.
-- Modern cool-navy base with a purple→blue accent.
local Theme = {
	Background      = Color3.fromRGB(16, 16, 24),   -- main window body
	BackgroundDark  = Color3.fromRGB(11, 11, 18),   -- heading / tab rail / watermark
	Panel           = Color3.fromRGB(20, 20, 30),   -- sections, inner panels
	Element         = Color3.fromRGB(26, 26, 38),   -- cards, buttons, dropdowns
	ElementLight    = Color3.fromRGB(31, 31, 46),   -- lighter element surfaces
	ToggleOff       = Color3.fromRGB(40, 40, 56),   -- toggle box border (off)
	Track           = Color3.fromRGB(34, 34, 50),   -- slider tracks, sidebar line
	Stroke          = Color3.fromRGB(45, 46, 66),   -- subtle bluish borders
	Accent          = Color3.fromRGB(140, 92, 245), -- primary purple
	AccentSecondary = Color3.fromRGB(88, 124, 255), -- blue (gradient end / glow)
	AccentBright    = Color3.fromRGB(170, 130, 255),
	Text            = Color3.fromRGB(228, 228, 240),
	TextBright      = Color3.fromRGB(242, 242, 252),
	TextMuted       = Color3.fromRGB(140, 142, 165),
	TextDim         = Color3.fromRGB(96, 98, 122),
	-- legacy aliases (kept so external Settings consumers don't break)
	Heading         = Color3.fromRGB(26, 26, 38),
	ElementInner    = Color3.fromRGB(0, 0, 0),
	ElementCenter   = Color3.fromRGB(20, 20, 30),
}

-- Metrics: fixed on desktop, scaled up on mobile for readability
local mobileScale = isMobile and math.clamp(viewPortSize.Y / 1080, 1.0, 1.6) or 1.0
local M = {
	ElementH    = math.round(22 * mobileScale),
	ToggleH     = math.round(18 * mobileScale),
	SliderH     = math.round(36 * mobileScale),
	TabH        = math.round(30 * mobileScale),
	SectionHead = math.round(24 * mobileScale),
	TextSize    = isMobile and math.clamp(math.round(14 * mobileScale), 14, 20) or 14,
	TextSizeSm  = isMobile and math.clamp(math.round(13 * mobileScale), 12, 18) or 13,
	Pad         = math.round(4 * mobileScale),
	PadLg       = math.round(5 * mobileScale),
	Border      = 1,
}

-- Lightweight factory: Create(className, props) returns configured instance
local function Create(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

-- Bind a ScrollingFrame's CanvasSize to its UIListLayout automatically
local function AutoCanvasSize(scrollFrame, listLayout)
	local function update()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + listLayout.Padding.Offset)
	end
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
	update()
end

-- Input helpers
local function IsPrimaryInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or (isMobile and input.UserInputType == Enum.UserInputType.Touch)
end

local originalElements = {}
-- Add Tween Dictionary with format Tweens.ElementType.TweenName to ignore repetitive variables

local Library = {}
Library.Settings = {
	MobileMode  = isMobile,
	ScaleFactor = scaleFactor,
	Theme       = Theme,
	Metrics     = M,
}
local elementHandler = {}
local windowHandler = {}
local tabHandler = {}
local sectionHandler = {}
local titleHandler = {}
local labelHandler = {}
local toggleHandler = {}
local buttonHandler = {}
local dropdownHandler = {}
local sliderHandler = {}
local searchBarHandler = {}
local keybindHandler = {}
local textBoxHandler = {}
local colorWheelHandler = {}

elementHandler.__index = elementHandler
windowHandler.__index = function(_, i) return rawget(windowHandler, i) or rawget(elementHandler, i) end
tabHandler.__index = function(_, i ) return rawget(tabHandler, i) or rawget(elementHandler, i) end
sectionHandler.__index = function(_, i) return rawget(sectionHandler, i) or rawget(elementHandler, i) end
titleHandler.__index = function(_, i) return rawget(titleHandler, i) or rawget(elementHandler, i) end
labelHandler.__index = function(_, i) return rawget(labelHandler, i) or rawget(elementHandler, i) end
toggleHandler.__index = function(_, i) return rawget(toggleHandler, i) or rawget(elementHandler, i) end
buttonHandler.__index = function(_, i) return rawget(buttonHandler, i) or rawget(elementHandler, i) end
dropdownHandler.__index = function(_, i) return rawget(dropdownHandler, i) or rawget(elementHandler, i) end
sliderHandler.__index = function(_, i) return rawget(sliderHandler, i) or rawget(elementHandler, i) end
searchBarHandler.__index = function(_, i) return rawget(searchBarHandler, i) or rawget(elementHandler, i) end
keybindHandler.__index = function(_, i) return rawget(keybindHandler, i) or rawget(elementHandler, i) end
textBoxHandler.__index = function(_, i) return rawget(textBoxHandler, i) or rawget(elementHandler, i) end
colorWheelHandler.__index = function(_, i) return rawget(colorWheelHandler, i) or rawget(elementHandler, i) end

local function animateText(textInstance: Instance, animationSpeed: number, text: string, placeholderText: string?, fillPlaceHolder: boolean?, emptyPlaceHolderText: boolean?): nil
	if emptyPlaceHolderText then
		for i = #textInstance.PlaceholderText, 0, -1 do
			textInstance.PlaceholderText = textInstance.PlaceholderText:sub(1,i)
			task.wait(animationSpeed)
		end
	else
		for i = #textInstance.Text, 0, -1 do
			textInstance.Text = textInstance.Text:sub(1,i)
			task.wait(animationSpeed)
		end
	end
	
	if fillPlaceHolder then
		for i = 1, #placeholderText do
			textInstance.PlaceholderText = placeholderText:sub(1, i)
			task.wait(animationSpeed)
		end
	else
		for i = 1, #text do
			textInstance.Text = text:sub(1, i)
			task.wait(animationSpeed)
		end
	end
end

local function toPolar(vector)
	return vector.Magnitude, math.atan2(vector.Y, vector.X)
end

local function toCartesian(radius, theta)
	return math.cos(theta) * radius, math.sin(theta) * radius
end

local function createOriginialElements()
	local function createWindow()
		local screenGui = Instance.new("ScreenGui")
		local background = Instance.new("Frame")
		local backgroundUICorner = Instance.new("UICorner")
		local backgroundAspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
		local pagesFolder = Instance.new("Folder")
		local heading = Instance.new("TextButton")
		local headingUICorner = Instance.new("UICorner")
		local headingCornerHiding = Instance.new("Frame")
		local headingSeperator = Instance.new("Frame")
		local title = Instance.new("TextLabel")
		local titleUIPadding = Instance.new("UIPadding")
		local buttonHolder = Instance.new("Frame")
		local buttonHolderList = Instance.new("UIListLayout")
		local buttonHolderPadding = Instance.new("UIPadding")
		local plus = Instance.new("ImageButton")
		local plusAspect = Instance.new("UIAspectRatioConstraint")
		local minus = Instance.new("ImageButton")
		local minusAspect = Instance.new("UIAspectRatioConstraint")
		local close = Instance.new("ImageButton")
		local closeAspect = Instance.new("UIAspectRatioConstraint")
		local holder = Instance.new("Frame")
		local tabs = Instance.new("ScrollingFrame")
		local tabsUIListLayout = Instance.new("UIListLayout")
		local tabsPadding = Instance.new("UIPadding")
		local sidebarLine = Instance.new("Frame")
		local pageLogo = Instance.new("ImageLabel")

		screenGui.Name = "BSMT"
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.IgnoreGuiInset = true

		background.Name = "Background"
		background.Parent = screenGui
		background.AnchorPoint = Vector2.new(0.5, 0.5)
		background.BackgroundColor3 = Theme.Background
		background.BorderSizePixel = 0
		background.ClipsDescendants = true
		background.Position = UDim2.new(0.5, 0, 0.5, 0)
		background.Size = UDim2.new(0.5, 0, 0.600000024, 0)

		backgroundUICorner.Name = "BackgroundUICorner"
		backgroundUICorner.CornerRadius = UDim.new(0, 8)
		backgroundUICorner.Parent = background

		backgroundAspectRatioConstraint.Name = "BackgroundUIAspectRatioConstraint"
		backgroundAspectRatioConstraint.AspectRatio = 1.531
		backgroundAspectRatioConstraint.Parent = background

		pagesFolder.Name = "Pages"
		pagesFolder.Parent = background

		heading.Name = "Heading"
		heading.Parent = background
		heading.BackgroundColor3 = Theme.BackgroundDark
		heading.BorderSizePixel = 0
		heading.Size = UDim2.new(1, 0, 0.0500000007, 0)
		heading.AutoButtonColor = false
		heading.Font = Enum.Font.SourceSans
		heading.Text = ""
		heading.TextColor3 = Color3.fromRGB(0, 0, 0)
		heading.TextSize = 14

		headingUICorner.Name = "HeadingUICorner"
		headingUICorner.CornerRadius = UDim.new(0, 8)
		headingUICorner.Parent = heading

		headingCornerHiding.Name = "HeadingCornerHiding"
		headingCornerHiding.Parent = heading
		headingCornerHiding.AnchorPoint = Vector2.new(0, 1)
		headingCornerHiding.BackgroundColor3 = Theme.BackgroundDark
		headingCornerHiding.BorderSizePixel = 0
		headingCornerHiding.Position = UDim2.new(0, 0, 1, 0)
		headingCornerHiding.Size = UDim2.new(1, 0, 0.5, 0)

		headingSeperator.Name = "HeadingSeperator"
		headingSeperator.Parent = heading
		headingSeperator.AnchorPoint = Vector2.new(0, 1)
		headingSeperator.BackgroundColor3 = Theme.Accent
		headingSeperator.BorderSizePixel = 0
		headingSeperator.Position = UDim2.new(0, 0, 1, 0)
		headingSeperator.Size = UDim2.new(1, 0, 0, 1)

		title.Name = "Title"
		title.Parent = heading
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(0.5, 0, 0.899999976, 0)
		title.Font = Enum.Font.GothamBold
		title.LineHeight = 0.800
		title.Text = "BSMT"
		title.TextColor3 = Color3.fromRGB(225, 225, 230)
		title.TextSize = M.TextSize
		title.TextXAlignment = Enum.TextXAlignment.Left

		titleUIPadding.Name = "TitleUIPadding"
		titleUIPadding.Parent = title
		titleUIPadding.PaddingLeft = UDim.new(0, 10)

		buttonHolder.Name = "ButtonHolder"
		buttonHolder.Parent = heading
		buttonHolder.AnchorPoint = Vector2.new(1, 0)
		buttonHolder.BackgroundTransparency = 1
		buttonHolder.BorderSizePixel = 0
		buttonHolder.Position = UDim2.new(1, 0, 0, 0)
		buttonHolder.Size = UDim2.new(0.3, 0, 1, 0)

		buttonHolderList.Name = "ButtonHolderList"
		buttonHolderList.Parent = buttonHolder
		buttonHolderList.FillDirection = Enum.FillDirection.Horizontal
		buttonHolderList.HorizontalAlignment = Enum.HorizontalAlignment.Right
		buttonHolderList.SortOrder = Enum.SortOrder.LayoutOrder
		buttonHolderList.VerticalAlignment = Enum.VerticalAlignment.Center
		buttonHolderList.Padding = UDim.new(0, 6)

		buttonHolderPadding.Name = "ButtonHolderPadding"
		buttonHolderPadding.Parent = buttonHolder
		buttonHolderPadding.PaddingRight = UDim.new(0, 8)

		plus.Name = "Plus"
		plus.Parent = buttonHolder
		plus.BackgroundTransparency = 1
		plus.BorderSizePixel = 0
		plus.Size = UDim2.new(1, 0, 0.5, 0)
		plus.AutoButtonColor = false
		plus.Rotation = 180
		plus.Image = "rbxassetid://11520007725"
		plus.ImageColor3 = Color3.fromRGB(150, 150, 160)
		plus.Visible = false
		plus.ImageTransparency = 1

		plusAspect.Name = "PlusAspect"
		plusAspect.Parent = plus

		minus.Name = "Minus"
		minus.Parent = buttonHolder
		minus.BackgroundTransparency = 1
		minus.BorderSizePixel = 0
		minus.Size = UDim2.new(1, 0, 0.5, 0)
		minus.AutoButtonColor = false
		minus.Image = "rbxassetid://11520996670"
		minus.ImageColor3 = Color3.fromRGB(170, 170, 180)

		minusAspect.Name = "MinusAspect"
		minusAspect.Parent = minus

		close.Name = "Close"
		close.Parent = buttonHolder
		close.BackgroundTransparency = 1
		close.BorderSizePixel = 0
		close.Size = UDim2.new(1, 0, 0.5, 0)
		close.AutoButtonColor = false
		close.Image = "rbxassetid://11520882762"
		close.ImageRectOffset = Vector2.new(48, 0)
		close.ImageRectSize = Vector2.new(20, 20)
		close.ImageColor3 = Color3.fromRGB(200, 70, 75)

		closeAspect.Name = "CloseAspect"
		closeAspect.Parent = close

		holder.Name = "Holder"
		holder.Parent = background
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Position = UDim2.new(0, 0, 0.0500000007, 0)
		holder.Size = UDim2.new(1, 0, 0.949999988, 0)

		tabs.Name = "Tabs"
		tabs.Parent = holder
		tabs.Active = true
		tabs.AnchorPoint = Vector2.new(0, 1)
		tabs.BackgroundColor3 = Theme.BackgroundDark
		tabs.BorderSizePixel = 0
		tabs.Position = UDim2.new(0, 0, 1, 0)
		tabs.ScrollBarThickness = 0
		-- Sidebar fixed at 0.225 so the right-anchored 0.775 page never overlaps it
		-- (a wider mobile sidebar caused the left column to render over the tabs)
		tabs.Size = UDim2.new(0.225, 0, 1, 0)

		tabsUIListLayout.Name = "TabsUIListLayout"
		tabsUIListLayout.Parent = tabs
		tabsUIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabsUIListLayout.Padding = UDim.new(0, 0)

		tabsPadding.Name = "TabsPadding"
		tabsPadding.Parent = tabs
		tabsPadding.PaddingTop = UDim.new(0, 4)

		sidebarLine.Name = "SidebarLine"
		sidebarLine.Parent = holder
		sidebarLine.AnchorPoint = Vector2.new(0, 0)
		sidebarLine.BackgroundColor3 = Theme.Track
		sidebarLine.BorderSizePixel = 0
		sidebarLine.Position = UDim2.new(0.225, 0, 0, 0)
		sidebarLine.Size = UDim2.new(0, 1, 1, 0)

		pageLogo.Name = "PageLogo"
		pageLogo.AnchorPoint = Vector2.new(1, 1)
		pageLogo.BackgroundTransparency = 1
		pageLogo.BorderSizePixel = 0
		pageLogo.Position = UDim2.new(1, -10, 1, -5)
		pageLogo.Size = UDim2.new(0.774999976, -25, 1, -15)
		pageLogo.ZIndex = 0
		pageLogo.Image = "rbxassetid://11435586663"
		pageLogo.ImageTransparency = 1
		pageLogo.Parent = holder

		return screenGui
	end
	local function createTab()
		local tab = Instance.new("TextButton")
		local tabAccent = Instance.new("Frame")          -- left red bar when active
		local tabAccentCorner = Instance.new("UICorner")
		local tabText = Instance.new("TextLabel")
		local tabTextUIPadding = Instance.new("UIPadding")
		local tabImage = Instance.new("ImageLabel")
		local tabAspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
		local tabSeperator = Instance.new("Frame")       -- kept for compat (hidden)
		local tabSeperatorUICorner = Instance.new("UICorner")

		tab.Name = "Tab"
		tab.BackgroundColor3 = Theme.BackgroundDark
		tab.BackgroundTransparency = 1
		tab.BorderSizePixel = 0
		tab.Size = UDim2.new(1, 0, 0, M.TabH)
		tab.AutoButtonColor = false
		tab.Font = Enum.Font.SourceSans
		tab.Text = ""
		tab.TextSize = 18

		-- Left accent bar (shown/hidden by Tab() handler)
		tabAccent.Name = "TabSeperator"   -- reuse name so existing code works
		tabAccent.Parent = tab
		tabAccent.AnchorPoint = Vector2.new(0, 0.5)
		tabAccent.BackgroundColor3 = Theme.Accent
		tabAccent.BackgroundTransparency = 1  -- hidden by default
		tabAccent.BorderSizePixel = 0
		tabAccent.Position = UDim2.new(0, 0, 0.5, 0)
		tabAccent.Size = UDim2.new(0, 3, 0.6, 0)

		tabAccentCorner.CornerRadius = UDim.new(0, 2)
		tabAccentCorner.Parent = tabAccent

		-- Purple→blue glow gradient on the active accent bar
		local tabAccentGradient = Instance.new("UIGradient")
		tabAccentGradient.Name = "AccentGradient"
		tabAccentGradient.Rotation = 90
		-- Keypoint table form: the two-color ColorSequence.new(c1, c2) overload
		-- doesn't exist on older clients.
		tabAccentGradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Theme.Accent),
			ColorSequenceKeypoint.new(1, Theme.AccentSecondary),
		}
		tabAccentGradient.Parent = tabAccent

		tabSeperatorUICorner.Name = "TabSeperatorUICorner"
		tabSeperatorUICorner.Parent = tabAccent

		tabImage.Name = "TabImage"
		tabImage.Parent = tab
		tabImage.AnchorPoint = Vector2.new(0, 0.5)
		tabImage.BackgroundTransparency = 1
		tabImage.BorderSizePixel = 0
		tabImage.Position = UDim2.new(0, 10, 0.5, 0)
		tabImage.Size = UDim2.new(0, 16, 0, 16)
		tabImage.Image = "rbxassetid://10746039695"
		tabImage.ImageColor3 = Theme.TextMuted

		tabAspectRatioConstraint.Parent = tabImage

		tabText.Name = "TabText"
		tabText.Parent = tab
		tabText.BackgroundTransparency = 1
		tabText.Position = UDim2.new(0, 32, 0, 0)
		tabText.Size = UDim2.new(1, -38, 1, 0)
		tabText.Font = Enum.Font.Gotham
		tabText.Text = "N/A"
		tabText.TextColor3 = Theme.TextDim
		tabText.TextSize = M.TextSize
		tabText.TextXAlignment = Enum.TextXAlignment.Left
		tabText.ClipsDescendants = true

		tabTextUIPadding.Parent = tabText
		tabTextUIPadding.PaddingLeft = UDim.new(0, 0)

		return tab
	end

	
	local function createPage()
		local page = Instance.new("Frame")
		local leftScrollingFrame = Instance.new("ScrollingFrame")
		local leftScrollingFrameList = Instance.new("UIListLayout")
		local leftPadding = Instance.new("UIPadding")
		local rightScrollingFrame = Instance.new("ScrollingFrame")
		local rightScrollingFrameList = Instance.new("UIListLayout")
		local rightPadding = Instance.new("UIPadding")

		page.Name = "Page"
		page.AnchorPoint = Vector2.new(1, 1)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Position = UDim2.new(1, -5, 1, -5)
		page.Visible = false
		page.Size = UDim2.new(0.775, -25, 1, -10)

		leftScrollingFrame.Name = "LeftScrollingFrame"
		leftScrollingFrame.Active = true
		leftScrollingFrame.BackgroundTransparency = 1
		leftScrollingFrame.Size = UDim2.new(0.5, -4, 1, 0)
		leftScrollingFrame.ScrollBarThickness = 0
		leftScrollingFrame.CanvasSize = UDim2FromScale(0, 0)
		leftScrollingFrame.Parent = page

		leftScrollingFrameList.Name = "LeftScrollingFrameList"
		leftScrollingFrameList.Padding = UDim.new(0, 6)
		leftScrollingFrameList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		leftScrollingFrameList.Parent = leftScrollingFrame

		leftPadding.Parent = leftScrollingFrame
		leftPadding.PaddingTop = UDim.new(0, 4)
		leftPadding.PaddingBottom = UDim.new(0, 4)

		rightScrollingFrame.Name = "RightScrollingFrame"
		rightScrollingFrame.Active = true
		rightScrollingFrame.AnchorPoint = Vector2.new(1, 0)
		rightScrollingFrame.BackgroundTransparency = 1
		rightScrollingFrame.Position = UDim2.new(1, 0, 0, 0)
		rightScrollingFrame.Size = UDim2.new(0.5, -4, 1, 0)
		rightScrollingFrame.CanvasSize = UDim2FromScale(0, 0)
		rightScrollingFrame.ScrollBarThickness = 0
		rightScrollingFrame.Parent = page

		rightScrollingFrameList.Name = "RightScrollingFrameList"
		rightScrollingFrameList.Padding = UDim.new(0, 6)
		rightScrollingFrameList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rightScrollingFrameList.Parent = rightScrollingFrame

		rightPadding.Parent = rightScrollingFrame
		rightPadding.PaddingTop = UDim.new(0, 4)
		rightPadding.PaddingBottom = UDim.new(0, 4)

		return page
	end

	
	local function createSection()
		local section = Instance.new("Frame")
		local heading = Instance.new("Frame")
		local headingSeperator = Instance.new("Frame")   -- kept for compat, hidden
		local title = Instance.new("TextLabel")
		local titleUIPadding = Instance.new("UIPadding")
		local resizeButton = Instance.new("ImageButton")
		local resizeButtonAspect = Instance.new("UIAspectRatioConstraint")
		local elementHolder = Instance.new("Frame")
		local elementHolderList = Instance.new("UIListLayout")
		local elementHolderPadding = Instance.new("UIPadding")

		section.Name = "Section"
		section.BackgroundColor3 = Theme.Panel
		section.BorderSizePixel = 0
		section.Size = UDim2.new(1, 0, 0, 200)
		section.ClipsDescendants = true

		local sectionCorner = Instance.new("UICorner")
		sectionCorner.CornerRadius = UDim.new(0, 6)
		sectionCorner.Parent = section

		heading.Name = "Heading"
		heading.Parent = section
		heading.BackgroundColor3 = Theme.Element
		heading.BorderSizePixel = 0
		heading.Size = UDim2.new(1, 0, 0, M.SectionHead)

		local headingCorner = Instance.new("UICorner")
		headingCorner.CornerRadius = UDim.new(0, 6)
		headingCorner.Parent = heading

		local headingHideLower = Instance.new("Frame")
		headingHideLower.BackgroundColor3 = Theme.Element
		headingHideLower.BorderSizePixel = 0
		headingHideLower.AnchorPoint = Vector2.new(0, 1)
		headingHideLower.Position = UDim2.new(0, 0, 1, 0)
		headingHideLower.Size = UDim2.new(1, 0, 0.5, 0)
		headingHideLower.Parent = heading

		-- Compat: HeadingSeperator exists but is invisible
		headingSeperator.Name = "HeadingSeperator"
		headingSeperator.Parent = heading
		headingSeperator.BackgroundTransparency = 1
		headingSeperator.Size = UDim2.new(1, 0, 0, 0)

		title.Name = "Title"
		title.Parent = heading
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, -28, 0, M.SectionHead)
		title.Font = Enum.Font.GothamMedium
		title.Text = "N/A"
		title.TextColor3 = Color3.fromRGB(210, 210, 218)
		title.TextSize = M.TextSize
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.ClipsDescendants = true

		titleUIPadding.Name = "TitleUIPadding"
		titleUIPadding.Parent = title
		titleUIPadding.PaddingLeft = UDim.new(0, 10)

		resizeButton.Name = "ResizeButton"
		resizeButton.Parent = heading
		resizeButton.AnchorPoint = Vector2.new(1, 0.5)
		resizeButton.BackgroundTransparency = 1
		resizeButton.BorderSizePixel = 0
		resizeButton.Position = UDim2.new(1, -6, 0.5, 0)
		resizeButton.Size = UDim2FromScale(0.65, 0.65)
		resizeButton.Image = "rbxassetid://11269835227"
		resizeButton.ImageColor3 = Color3.fromRGB(100, 100, 115)

		resizeButtonAspect.Parent = resizeButton

		elementHolder.Name = "ElementHolder"
		elementHolder.Parent = section
		elementHolder.BackgroundTransparency = 1
		elementHolder.BorderSizePixel = 0
		elementHolder.Position = UDim2.new(0, 0, 0, M.SectionHead)
		elementHolder.Size = UDim2.new(1, 0, 0, 178)
		elementHolder.ClipsDescendants = true

		elementHolderList.Name = "ElementHolderList"
		elementHolderList.Parent = elementHolder
		elementHolderList.SortOrder = Enum.SortOrder.LayoutOrder
		elementHolderList.Padding = UDim.new(0, 4)

		elementHolderPadding.Name = "ElementHolderPadding"
		elementHolderPadding.Parent = elementHolder
		elementHolderPadding.PaddingBottom = UDim.new(0, 6)
		elementHolderPadding.PaddingLeft = UDim.new(0, 8)
		elementHolderPadding.PaddingRight = UDim.new(0, 8)
		elementHolderPadding.PaddingTop = UDim.new(0, 6)

		return section
	end

	
	local function createTitle()
		local title = Instance.new("Frame")
		local titleText = Instance.new("TextLabel")
		local design = Instance.new("Frame")
		local designGradient = Instance.new("UIGradient")

		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.BorderSizePixel = 0
		title.Size = UDim2.new(1, 0, 0, M.ToggleH)

		titleText.Name = "TitleText"
		titleText.Parent = title
		titleText.AnchorPoint = Vector2.new(0.5, 0)
		titleText.BackgroundColor3 = Theme.Panel
		titleText.BorderSizePixel = 0
		titleText.Position = UDim2.new(0.5, 0, 0, 0)
		titleText.Size = UDim2.new(0.4, 0, 1, 0)
		titleText.ZIndex = 2
		titleText.Font = Enum.Font.GothamMedium
		titleText.TextColor3 = Color3.fromRGB(180, 180, 190)
		titleText.Text = "N/A"
		titleText.TextSize = M.TextSize

		design.Name = "Design"
		design.Parent = title
		design.AnchorPoint = Vector2.new(0, 0.5)
		design.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		design.BorderSizePixel = 0
		design.Position = UDim2.new(0, 0, 0.5, 0)
		design.Size = UDim2.new(1, 0, 0, 1)

		designGradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0.00, Theme.Panel),
			ColorSequenceKeypoint.new(0.50, Theme.Accent),
			ColorSequenceKeypoint.new(1.00, Theme.Panel)
		}
		designGradient.Name = "DesignGradient"
		designGradient.Parent = design

		return title
	end

	
	local function createLabel()
		local label = Instance.new("Frame")
		local labelPadding = Instance.new("UIPadding")
		local labelBackground = Instance.new("Frame")
		local labelBgCorner = Instance.new("UICorner")
		local labelText = Instance.new("TextLabel")
		local labelTextPadding = Instance.new("UIPadding")
		local labelBackgroundPadding = Instance.new("UIPadding")

		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Size = UDim2.new(1, 0, 0, M.ElementH)

		labelPadding.Name = "LabelPadding"
		labelPadding.Parent = label

		labelBackground.Name = "LabelBackground"
		labelBackground.Parent = label
		labelBackground.BackgroundColor3 = Theme.Element
		labelBackground.BorderSizePixel = 0
		labelBackground.Size = UDim2.new(1, 0, 1, 0)

		labelBgCorner.CornerRadius = UDim.new(0, 5)
		labelBgCorner.Parent = labelBackground

		labelText.Name = "LabelText"
		labelText.Parent = labelBackground
		labelText.AnchorPoint = Vector2.new(0.5, 0)
		labelText.BackgroundTransparency = 1
		labelText.BorderSizePixel = 0
		labelText.Position = UDim2.new(0.5, 0, 0, 0)
		labelText.Size = UDim2.new(1, 0, 1, 0)
		labelText.ZIndex = 2
		labelText.Font = Enum.Font.Gotham
		labelText.TextColor3 = Color3.fromRGB(180, 180, 195)
		labelText.TextSize = M.TextSizeSm
		labelText.TextWrapped = true
		labelText.TextXAlignment = Enum.TextXAlignment.Left
		labelText.TextYAlignment = Enum.TextYAlignment.Top

		labelTextPadding.Name = "LabelTextPadding"
		labelTextPadding.Parent = labelText
		labelTextPadding.PaddingLeft = UDim.new(0, 8)
		labelTextPadding.PaddingRight = UDim.new(0, 8)
		labelTextPadding.PaddingBottom = UDim.new(0, 4)
		labelTextPadding.PaddingTop = UDim.new(0, 4)

		labelBackgroundPadding.Name = "LabelBackgroundPadding"
		labelBackgroundPadding.Parent = labelBackground

		return label
	end

	
	local function createToggle()
		local toggle = Instance.new("TextButton")
		local toggleText = Instance.new("TextLabel")
		local boxBackground = Instance.new("Frame")
		local boxAspect = Instance.new("UIAspectRatioConstraint")
		local boxPadding = Instance.new("UIPadding")
		local boxCorner = Instance.new("UICorner")
		local innerBox = Instance.new("Frame")
		local innerBoxPadding = Instance.new("UIPadding")
		local innerBoxCorner = Instance.new("UICorner")
		local centerBox = Instance.new("Frame")
		local centerBoxCorner = Instance.new("UICorner")
		local toggleImage = Instance.new("ImageLabel")
		local toggleImageCorner = Instance.new("UICorner")

		toggle.Name = "ToggleElement"
		toggle.BackgroundTransparency = 1
		toggle.BorderSizePixel = 0
		toggle.Size = UDim2.new(1, 0, 0, M.ToggleH)
		toggle.AutoButtonColor = false
		toggle.Font = Enum.Font.SourceSans
		toggle.Text = ""
		toggle.TextSize = 14

		toggleText.Name = "ToggleText"
		toggleText.Parent = toggle
		toggleText.BackgroundTransparency = 1
		toggleText.Position = UDim2.new(0, M.ToggleH + 6, 0, 0)
		toggleText.Size = UDim2.new(1, -(M.ToggleH + 6), 1, 0)
		toggleText.Font = Enum.Font.Gotham
		toggleText.Text = "N/A"
		toggleText.TextColor3 = Theme.Text
		toggleText.TextSize = M.TextSize
		toggleText.TextXAlignment = Enum.TextXAlignment.Left

		-- Outer border square
		boxBackground.Name = "BoxBackground"
		boxBackground.Parent = toggle
		boxBackground.BackgroundColor3 = Theme.ToggleOff
		boxBackground.BorderSizePixel = 0
		boxBackground.Size = UDim2.new(1, 0, 1, 0)

		boxAspect.Name = "BoxAspect"
		boxAspect.Parent = boxBackground

		boxCorner.CornerRadius = UDim.new(0, 4)
		boxCorner.Parent = boxBackground

		boxPadding.Name = "BoxPadding"
		boxPadding.Parent = boxBackground
		boxPadding.PaddingBottom = UDim.new(0, 1)
		boxPadding.PaddingLeft = UDim.new(0, 1)
		boxPadding.PaddingRight = UDim.new(0, 1)
		boxPadding.PaddingTop = UDim.new(0, 1)

		-- Inner dark fill (becomes colored accent when active)
		innerBox.Name = "InnerBox"
		innerBox.Parent = boxBackground
		innerBox.AnchorPoint = Vector2.new(0.5, 0.5)
		innerBox.BackgroundColor3 = Theme.Panel
		innerBox.BorderSizePixel = 0
		innerBox.Position = UDim2.new(0.5, 0, 0.5, 0)
		innerBox.Size = UDim2.new(1, 0, 1, 0)

		innerBoxCorner.CornerRadius = UDim.new(0, 3)
		innerBoxCorner.Parent = innerBox

		innerBoxPadding.Name = "InnerBoxPadding"
		innerBoxPadding.Parent = innerBox
		innerBoxPadding.PaddingBottom = UDim.new(0, 2)
		innerBoxPadding.PaddingLeft = UDim.new(0, 2)
		innerBoxPadding.PaddingRight = UDim.new(0, 2)
		innerBoxPadding.PaddingTop = UDim.new(0, 2)

		centerBox.Name = "CenterBox"
		centerBox.Parent = innerBox
		centerBox.AnchorPoint = Vector2.new(0.5, 0.5)
		centerBox.BackgroundColor3 = Theme.Panel
		centerBox.BorderSizePixel = 0
		centerBox.Position = UDim2.new(0.5, 0, 0.5, 0)
		centerBox.Size = UDim2.new(1, 0, 1, 0)

		centerBoxCorner.CornerRadius = UDim.new(0, 2)
		centerBoxCorner.Parent = centerBox

		toggleImage.Name = "ToggleImage"
		toggleImage.Parent = centerBox
		toggleImage.AnchorPoint = Vector2.new(0.5, 0.5)
		toggleImage.BackgroundColor3 = Theme.Accent
		toggleImage.BackgroundTransparency = 0
		toggleImage.BorderSizePixel = 0
		toggleImage.Position = UDim2.new(0.5, 0, 0.5, 0)
		toggleImage.Size = UDim2FromScale(0, 0)
		toggleImage.Image = "rbxassetid://11444348176"
		toggleImage.ImageColor3 = Color3.fromRGB(255, 255, 255)

		toggleImageCorner.Name = "ToggleImageCorner"
		toggleImageCorner.CornerRadius = UDim.new(0, 2)
		toggleImageCorner.Parent = toggleImage

		return toggle
	end

	
	local function createButton()
		local button = Instance.new("TextButton")
		local buttonText = Instance.new("TextLabel")
		local buttonBg = Instance.new("Frame")
		local buttonBgCorner = Instance.new("UICorner")
		local buttonBgStroke = Instance.new("UIStroke")
		-- Compat stubs (old code accesses CircleBackground > InnerCircle > CenterCircle)
		local circleBackground = Instance.new("Frame")
		local circleAspect = Instance.new("UIAspectRatioConstraint")
		local circlePadding = Instance.new("UIPadding")
		local circleCorner = Instance.new("UICorner")
		local innerCircle = Instance.new("Frame")
		local innerCircleCorner = Instance.new("UICorner")
		local innerCirclePadding = Instance.new("UIPadding")
		local centerCircle = Instance.new("Frame")
		local centerCircleCorner = Instance.new("UICorner")
		local centerCirclePadding = Instance.new("UIPadding")
		local buttonCircle = Instance.new("Frame")
		local buttonCircleCorner = Instance.new("UICorner")

		button.Name = "Button"
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Size = UDim2.new(1, 0, 0, M.ToggleH + 4)
		button.AutoButtonColor = false
		button.Font = Enum.Font.SourceSans
		button.Text = ""
		button.TextSize = 14

		buttonBg.Name = "ButtonBg"
		buttonBg.Parent = button
		buttonBg.BackgroundColor3 = Theme.Element
		buttonBg.BorderSizePixel = 0
		buttonBg.Size = UDim2.new(1, 0, 1, 0)

		buttonBgCorner.CornerRadius = UDim.new(0, 5)
		buttonBgCorner.Parent = buttonBg

		buttonBgStroke.Color = Theme.Stroke
		buttonBgStroke.Thickness = 1
		BSMT_ApplyBorderStroke(buttonBgStroke)
		buttonBgStroke.Parent = buttonBg

		buttonText.Name = "ButtonText"
		buttonText.Parent = buttonBg
		buttonText.BackgroundTransparency = 1
		buttonText.Size = UDim2.new(1, 0, 1, 0)
		buttonText.Font = Enum.Font.Gotham
		buttonText.Text = "Button"
		buttonText.TextColor3 = Theme.Text
		buttonText.TextSize = M.TextSize
		buttonText.TextXAlignment = Enum.TextXAlignment.Center

		-- Compat stubs: zero-size, transparent
		circleBackground.Name = "CircleBackground"
		circleBackground.Parent = button
		circleBackground.BackgroundTransparency = 1
		circleBackground.Size = UDim2.new(0, 0, 0, 0)
		circleAspect.Name = "CircleAspect" ; circleAspect.Parent = circleBackground
		circlePadding.Name = "CirclePadding" ; circlePadding.Parent = circleBackground
		circleCorner.Name = "CircleCorner" ; circleCorner.Parent = circleBackground
		innerCircle.Name = "InnerCircle" ; innerCircle.Parent = circleBackground
		innerCircle.BackgroundTransparency = 1
		innerCircle.Size = UDim2.new(0,0,0,0)
		innerCircleCorner.Name = "InnerCircleCorner" ; innerCircleCorner.Parent = innerCircle
		innerCirclePadding.Name = "InnerCirclePadding" ; innerCirclePadding.Parent = innerCircle
		centerCircle.Name = "CenterCircle" ; centerCircle.Parent = innerCircle
		centerCircle.BackgroundTransparency = 1
		centerCircle.Size = UDim2.new(0,0,0,0)
		centerCircleCorner.Name = "CenterCircleCorner" ; centerCircleCorner.Parent = centerCircle
		centerCirclePadding.Name = "CenterCirclePadding" ; centerCirclePadding.Parent = innerCircle
		buttonCircle.Name = "ButtonCircle" ; buttonCircle.Parent = centerCircle
		buttonCircle.BackgroundColor3 = Theme.Accent
		buttonCircle.BackgroundTransparency = 1
		buttonCircle.Size = UDim2.new(0,0,0,0)
		buttonCircle.Position = UDim2FromScale(0.5,0.5)
		buttonCircleCorner.Name = "ButtonCircleCorner" ; buttonCircleCorner.Parent = buttonCircle

		return button
	end

	
	local function createDropdown()
		local dropdown = Instance.new("Frame")
		local dropdownButton = Instance.new("TextButton")
		local dropdownButtonCorner = Instance.new("UICorner")
		local dropdownButtonStroke = Instance.new("UIStroke")
		local buttonBackground = Instance.new("Frame")      -- compat
		local dropdownText = Instance.new("TextLabel")
		local dropdownTextPadding = Instance.new("UIPadding")
		local buttonBackgroundPadding = Instance.new("UIPadding")  -- compat
		local dropdownImage = Instance.new("ImageLabel")
		local imageAspect = Instance.new("UIAspectRatioConstraint")
		local buttonInnerBackground = Instance.new("Frame")  -- compat
		local dropdownButtonPadding = Instance.new("UIPadding")  -- compat
		local elementHolder = Instance.new("ScrollingFrame")
		local elementHolderCorner = Instance.new("UICorner")
		local elementHolderBackground = Instance.new("Frame")       -- compat
		local elementHolderInnerBackground = Instance.new("Frame")  -- compat
		local elementHolderInnerBackgroundList = Instance.new("UIListLayout")
		local elementHolderInnerBackgroundPadding = Instance.new("UIPadding")
		local elementHolderBackgroundPadding = Instance.new("UIPadding")  -- compat
		local elementHolderPadding = Instance.new("UIPadding")  -- compat

		dropdown.Name = "Dropdown"
		dropdown.BackgroundTransparency = 1
		dropdown.BorderSizePixel = 0
		dropdown.ClipsDescendants = true
		dropdown.Size = UDim2.new(1, 0, 0, M.ElementH)

		dropdownButton.Name = "DropdownButton"
		dropdownButton.Parent = dropdown
		dropdownButton.BackgroundColor3 = Theme.Element
		dropdownButton.BorderSizePixel = 0
		dropdownButton.Size = UDim2.new(1, 0, 0, M.ElementH)
		dropdownButton.AutoButtonColor = false
		dropdownButton.Font = Enum.Font.SourceSans
		dropdownButton.Text = ""
		dropdownButton.TextSize = 14

		dropdownButtonCorner.CornerRadius = UDim.new(0, 5)
		dropdownButtonCorner.Parent = dropdownButton

		dropdownButtonStroke.Color = Theme.Stroke
		dropdownButtonStroke.Thickness = 1
		BSMT_ApplyBorderStroke(dropdownButtonStroke)
		dropdownButtonStroke.Parent = dropdownButton

		-- buttonBackground is a transparent compat frame covering the button
		buttonBackground.Name = "ButtonBackground"
		buttonBackground.Parent = dropdownButton
		buttonBackground.AnchorPoint = Vector2.new(0.5, 0.5)
		buttonBackground.BackgroundTransparency = 1
		buttonBackground.BorderSizePixel = 0
		buttonBackground.Position = UDim2.new(0.5, 0, 0.5, 0)
		buttonBackground.Size = UDim2.new(1, 0, 1, 0)

		dropdownText.Name = "DropdownText"
		dropdownText.Parent = buttonBackground
		dropdownText.BackgroundTransparency = 1
		dropdownText.BorderSizePixel = 0
		dropdownText.ClipsDescendants = true
		dropdownText.Size = UDim2.new(1, -22, 1, 0)
		dropdownText.Font = Enum.Font.Gotham
		dropdownText.Text = "N/A"
		dropdownText.TextColor3 = Color3.fromRGB(190, 190, 205)
		dropdownText.TextSize = M.TextSize
		dropdownText.TextXAlignment = Enum.TextXAlignment.Left

		dropdownTextPadding.Name = "DropdownTextPadding"
		dropdownTextPadding.Parent = dropdownText
		dropdownTextPadding.PaddingLeft = UDim.new(0, 8)

		buttonBackgroundPadding.Name = "ButtonBackgroundPadding"
		buttonBackgroundPadding.Parent = buttonBackground

		dropdownImage.Name = "DropdownImage"
		dropdownImage.Parent = buttonBackground
		dropdownImage.AnchorPoint = Vector2.new(1, 0.5)
		dropdownImage.BackgroundTransparency = 1
		dropdownImage.BorderSizePixel = 0
		dropdownImage.Position = UDim2.new(1, -6, 0.5, 0)
		dropdownImage.Rotation = 180
		dropdownImage.Size = UDim2.new(0, 14, 0, 14)
		dropdownImage.Image = "rbxassetid://11269835227"
		dropdownImage.ImageColor3 = Color3.fromRGB(130, 130, 145)

		imageAspect.Name = "ImageAspect"
		imageAspect.Parent = dropdownImage

		-- compat stubs
		buttonInnerBackground.Name = "ButtonInnerBackground"
		buttonInnerBackground.Parent = buttonBackground
		buttonInnerBackground.BackgroundTransparency = 1
		buttonInnerBackground.Size = UDim2.new(0,0,0,0)
		buttonInnerBackground.ZIndex = 0

		dropdownButtonPadding.Name = "DropdownButtonPadding"
		dropdownButtonPadding.Parent = dropdownButton

		-- Drop-down list
		elementHolder.Name = "ElementHolder"
		elementHolder.Parent = dropdown
		elementHolder.Active = true
		elementHolder.BackgroundColor3 = Color3.fromRGB(24, 24, 31)
		elementHolder.BorderSizePixel = 0
		elementHolder.Position = UDim2.new(0, 0, 0, M.ElementH + 2)
		elementHolder.Size = UDim2.new(1, 0, 0, 0)
		elementHolder.CanvasSize = UDim2.new(0,0,0,0)
		elementHolder.ScrollBarThickness = 0

		elementHolderCorner.CornerRadius = UDim.new(0, 5)
		elementHolderCorner.Parent = elementHolder

		elementHolderBackground.Name = "ElementHolderBackground"
		elementHolderBackground.Parent = elementHolder
		elementHolderBackground.BackgroundTransparency = 1
		elementHolderBackground.Size = UDim2.new(1,0,1,0)

		elementHolderInnerBackground.Name = "ElementHolderInnerBackground"
		elementHolderInnerBackground.Parent = elementHolderBackground
		elementHolderInnerBackground.BackgroundTransparency = 1
		elementHolderInnerBackground.Size = UDim2.new(1,0,1,0)

		elementHolderInnerBackgroundList.Name = "ElementHolderInnerBackgroundList"
		elementHolderInnerBackgroundList.Parent = elementHolderInnerBackground
		elementHolderInnerBackgroundList.SortOrder = Enum.SortOrder.LayoutOrder
		elementHolderInnerBackgroundList.Padding = UDim.new(0, 0)

		elementHolderInnerBackgroundPadding.Name = "ElementHolderInnerBackgroundPadding"
		elementHolderInnerBackgroundPadding.Parent = elementHolderInnerBackground
		elementHolderInnerBackgroundPadding.PaddingBottom = UDim.new(0, 4)
		elementHolderInnerBackgroundPadding.PaddingLeft = UDim.new(0, 4)
		elementHolderInnerBackgroundPadding.PaddingRight = UDim.new(0, 4)
		elementHolderInnerBackgroundPadding.PaddingTop = UDim.new(0, 4)

		elementHolderBackgroundPadding.Name = "ElementHolderBackgroundPadding"
		elementHolderBackgroundPadding.Parent = elementHolderBackground

		elementHolderPadding.Name = "ElementHolderPadding"
		elementHolderPadding.Parent = elementHolder

		return dropdown
	end

	
	local function createSlider()
		local sliderElement = Instance.new("Frame")
		local textGrouping = Instance.new("Frame")
		local numberText = Instance.new("TextBox")
		local sliderText = Instance.new("TextLabel")
		local sliderElementList = Instance.new("UIListLayout")
		local sliderBackground = Instance.new("TextButton")
		local sliderBgCorner = Instance.new("UICorner")
		local sliderBgStroke = Instance.new("UIStroke")
		local sliderInnerBackground = Instance.new("Frame")
		local sliderInnerBgCorner = Instance.new("UICorner")
		local sliderInnerBackgroundPadding = Instance.new("UIPadding")
		local emptySliderBackground = Instance.new("Frame")
		local emptySliderCorner = Instance.new("UICorner")
		local slider = Instance.new("Frame")
		local sliderFillCorner = Instance.new("UICorner")
		local sliderBackgroundPadding = Instance.new("UIPadding")

		sliderElement.Name = "Slider"
		sliderElement.BackgroundTransparency = 1
		sliderElement.BorderSizePixel = 0
		sliderElement.Size = UDim2.new(1, 0, 0, M.SliderH)

		textGrouping.Name = "TextGrouping"
		textGrouping.Parent = sliderElement
		textGrouping.BackgroundTransparency = 1
		textGrouping.BorderSizePixel = 0
		textGrouping.Size = UDim2.new(1, 0, 0, M.ToggleH)

		sliderText.Name = "SliderText"
		sliderText.Parent = textGrouping
		sliderText.BackgroundTransparency = 1
		sliderText.Size = UDim2.new(0.6, 0, 1, 0)
		sliderText.BorderSizePixel = 0
		sliderText.Font = Enum.Font.Gotham
		sliderText.Text = "N/A"
		sliderText.TextColor3 = Theme.Text
		sliderText.TextSize = M.TextSize
		sliderText.ClipsDescendants = true
		sliderText.TextXAlignment = Enum.TextXAlignment.Left

		numberText.Name = "NumberText"
		numberText.Parent = textGrouping
		numberText.BackgroundTransparency = 1
		numberText.BorderSizePixel = 0
		numberText.AnchorPoint = Vector2.new(1, 0)
		numberText.Position = UDim2.new(1, 0, 0, 0)
		numberText.Size = UDim2.new(0.4, 0, 1, 0)
		numberText.Font = Enum.Font.GothamBold
		numberText.PlaceholderColor3 = Color3.fromRGB(90, 90, 105)
		numberText.PlaceholderText = ""
		numberText.Text = "0"
		numberText.TextColor3 = Theme.Accent
		numberText.TextSize = M.TextSize
		numberText.TextXAlignment = Enum.TextXAlignment.Right
		numberText.ClipsDescendants = true

		sliderElementList.Name = "SliderElementList"
		sliderElementList.Parent = sliderElement
		sliderElementList.SortOrder = Enum.SortOrder.LayoutOrder
		sliderElementList.Padding = UDim.new(0, 4)

		-- The track button
		sliderBackground.Name = "SliderBackground"
		sliderBackground.Parent = sliderElement
		sliderBackground.AnchorPoint = Vector2.new(0, 1)
		sliderBackground.BackgroundColor3 = Theme.Track
		sliderBackground.BorderSizePixel = 0
		sliderBackground.Position = UDim2.new(0, 0, 1, 0)
		sliderBackground.Size = UDim2.new(1, 0, 0.5, -2)
		sliderBackground.AutoButtonColor = false
		sliderBackground.Font = Enum.Font.SourceSans
		sliderBackground.Text = ""
		sliderBackground.TextSize = 14

		sliderBgCorner.CornerRadius = UDim.new(1, 0)
		sliderBgCorner.Parent = sliderBackground

		sliderBgStroke.Color = Color3.fromRGB(44, 44, 58)
		sliderBgStroke.Thickness = 1
		BSMT_ApplyBorderStroke(sliderBgStroke)
		sliderBgStroke.Parent = sliderBackground

		sliderInnerBackground.Name = "SliderInnerBackground"
		sliderInnerBackground.Parent = sliderBackground
		sliderInnerBackground.AnchorPoint = Vector2.new(0.5, 0.5)
		sliderInnerBackground.BackgroundTransparency = 1
		sliderInnerBackground.BorderSizePixel = 0
		sliderInnerBackground.Position = UDim2.new(0.5, 0, 0.5, 0)
		sliderInnerBackground.Size = UDim2.new(1, 0, 1, 0)

		sliderInnerBgCorner.CornerRadius = UDim.new(1, 0)
		sliderInnerBgCorner.Parent = sliderInnerBackground

		sliderInnerBackgroundPadding.Name = "SliderInnerBackgroundPadding"
		sliderInnerBackgroundPadding.Parent = sliderInnerBackground

		emptySliderBackground.Name = "EmptySliderBackground"
		emptySliderBackground.Parent = sliderInnerBackground
		emptySliderBackground.BackgroundColor3 = Theme.Track
		emptySliderBackground.BorderSizePixel = 0
		emptySliderBackground.Size = UDim2.new(1, 0, 1, 0)
		emptySliderBackground.ZIndex = 0

		emptySliderCorner.CornerRadius = UDim.new(1, 0)
		emptySliderCorner.Parent = emptySliderBackground

		slider.Name = "Slider"
		slider.Parent = sliderInnerBackground
		slider.BackgroundColor3 = Theme.Accent
		slider.BorderSizePixel = 0
		slider.Size = UDim2.new(0, 2, 1, 0)

		sliderFillCorner.CornerRadius = UDim.new(1, 0)
		sliderFillCorner.Parent = slider

		-- Purple→blue gradient on the slider fill
		local sliderFillGradient = Instance.new("UIGradient")
		sliderFillGradient.Name = "FillGradient"
		-- Keypoint table form: the two-color ColorSequence.new(c1, c2) overload
		-- doesn't exist on older clients.
		sliderFillGradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Theme.Accent),
			ColorSequenceKeypoint.new(1, Theme.AccentSecondary),
		}
		sliderFillGradient.Parent = slider

		sliderBackgroundPadding.Name = "SliderBackgroundPadding"
		sliderBackgroundPadding.Parent = sliderBackground

		return sliderElement
	end

	
	local function createSearchBar()
		local searchBar = Instance.new("Frame")
		local searchBarFrame = Instance.new("Frame")
		local buttonBackgroundPadding = Instance.new("Frame")
		local buttonBackgroundPadding_2 = Instance.new("UIPadding")
		local searchBox = Instance.new("TextBox")
		local searchBoxPadding = Instance.new("UIPadding")
		local searchBoxBackground = Instance.new("Frame")
		local searchImage = Instance.new("ImageLabel")
		local searchImageAspect = Instance.new("UIAspectRatioConstraint")
		local searchButtonPadding = Instance.new("UIPadding")
		local elementHolder = Instance.new("ScrollingFrame")
		local elementHolderBackground = Instance.new("Frame")
		local elementHolderInnerBackground = Instance.new("Frame")
		local elementHolderInnerBackgroundList = Instance.new("UIListLayout")
		local elementHolderInnerBackgroundPadding = Instance.new("UIPadding")
		local elementHolderBackgroundPadding = Instance.new("UIPadding")
		local elementHolderPadding = Instance.new("UIPadding")

		searchBar.Name = "SearchBar"
		searchBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		searchBar.BackgroundTransparency = 1.000
		searchBar.BorderSizePixel = 0
		searchBar.ClipsDescendants = true
		searchBar.Size = UDim2.new(1, 0, 0, M.ElementH)

		searchBarFrame.Name = "SearchBarFrame"
		searchBarFrame.Parent = searchBar
		searchBarFrame.BackgroundColor3 = Theme.Element
		searchBarFrame.BorderSizePixel = 0
		searchBarFrame.Size = UDim2.new(1, 0, 0, M.ElementH)

		buttonBackgroundPadding.Name = "ButtonBackgroundPadding"
		buttonBackgroundPadding.Parent = searchBarFrame
		buttonBackgroundPadding.AnchorPoint = Vector2.new(0.5, 0.5)
		buttonBackgroundPadding.BackgroundColor3 = Theme.Element
		buttonBackgroundPadding.BorderSizePixel = 0
		buttonBackgroundPadding.Position = UDim2.new(0.5, 0, 0.5, 0)
		buttonBackgroundPadding.Size = UDim2.new(1, 0, 1, 0)

		buttonBackgroundPadding_2.Name = "ButtonBackgroundPadding"
		buttonBackgroundPadding_2.Parent = buttonBackgroundPadding
		buttonBackgroundPadding_2.PaddingBottom = UDim.new(0, 1)
		buttonBackgroundPadding_2.PaddingLeft = UDim.new(0, 1)
		buttonBackgroundPadding_2.PaddingRight = UDim.new(0, 1)
		buttonBackgroundPadding_2.PaddingTop = UDim.new(0, 1)

		searchBox.Name = "SearchBox"
		searchBox.Parent = buttonBackgroundPadding
		searchBox.Active = false
		searchBox.BackgroundColor3 = Theme.Panel
		searchBox.BackgroundTransparency = 1
		searchBox.BorderSizePixel = 0
		searchBox.Size = UDim2.new(1, 0, 1, 0)
		searchBox.Font = Enum.Font.Gotham
		searchBox.PlaceholderColor3 = Color3.fromRGB(90, 90, 105)
		searchBox.PlaceholderText = "N/A"
		searchBox.Text = ""
		searchBox.TextColor3 = Color3.fromRGB(90, 90, 105)
		searchBox.TextSize = M.TextSize
		searchBox.TextXAlignment = Enum.TextXAlignment.Left

		searchBoxPadding.Name = "SearchBoxPadding"
		searchBoxPadding.Parent = searchBox
		searchBoxPadding.PaddingLeft = UDim.new(0, 4)
		
		searchBoxBackground.Name = "SearchBoxBackground"
		searchBoxBackground.Parent = buttonBackgroundPadding
		searchBoxBackground.BackgroundColor3 = Theme.Panel
		searchBoxBackground.BorderSizePixel = 0
		searchBoxBackground.Size = UDim2.new(1, 0, 1, 0)
		searchBoxBackground.ZIndex = 0
		
		searchImage.Name = "SearchImage"
		searchImage.Parent = buttonBackgroundPadding
		searchImage.AnchorPoint = Vector2.new(1, 0.5)
		searchImage.BackgroundColor3 = Theme.Panel
		searchImage.BackgroundTransparency = 1
		searchImage.BorderSizePixel = 0
		searchImage.Position = UDim2.new(1, 0, 0.5, 0)
		searchImage.Size = UDim2.new(0.899999976, 0, 0.899999976, 0)
		searchImage.Image = "rbxassetid://11454041890"

		searchImageAspect.Name = "SearchImageAspect"
		searchImageAspect.Parent = searchImage

		searchButtonPadding.Name = "SearchButtonPadding"
		searchButtonPadding.Parent = searchBarFrame
		searchButtonPadding.PaddingBottom = UDim.new(0, 1)
		searchButtonPadding.PaddingLeft = UDim.new(0, 1)
		searchButtonPadding.PaddingRight = UDim.new(0, 1)
		searchButtonPadding.PaddingTop = UDim.new(0, 1)

		elementHolder.Name = "ElementHolder"
		elementHolder.Parent = searchBar
		elementHolder.Active = true
		elementHolder.BackgroundColor3 = Theme.ElementLight
		elementHolder.BorderSizePixel = 0
		elementHolder.Position = UDim2.new(0, 0, 0, M.ElementH)
		elementHolder.Size = UDim2.new(0.925000012, 0, 0, 0)
		elementHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
		elementHolder.ScrollBarThickness = 0

		elementHolderBackground.Name = "ElementHolderBackground"
		elementHolderBackground.Parent = elementHolder
		elementHolderBackground.BackgroundColor3 = Theme.Panel
		elementHolderBackground.BorderSizePixel = 0
		elementHolderBackground.Size = UDim2.new(1, 0, 1, 0)

		elementHolderInnerBackground.Name = "ElementHolderInnerBackground"
		elementHolderInnerBackground.Parent = elementHolderBackground
		elementHolderInnerBackground.BackgroundColor3 = Theme.Panel
		elementHolderInnerBackground.BorderSizePixel = 0
		elementHolderInnerBackground.Visible = false
		elementHolderInnerBackground.Size = UDim2.new(1, 0, 1, 0)

		elementHolderInnerBackgroundList.Name = "ElementHolderInnerBackgroundList"
		elementHolderInnerBackgroundList.Parent = elementHolderInnerBackground
		elementHolderInnerBackgroundList.SortOrder = Enum.SortOrder.LayoutOrder
		elementHolderInnerBackgroundList.Padding = UDim.new(0, 5)

		elementHolderInnerBackgroundPadding.Name = "ElementHolderInnerBackgroundPadding"
		elementHolderInnerBackgroundPadding.Parent = elementHolderInnerBackground
		elementHolderInnerBackgroundPadding.PaddingBottom = UDim.new(0, 4)
		elementHolderInnerBackgroundPadding.PaddingLeft = UDim.new(0, 5)
		elementHolderInnerBackgroundPadding.PaddingRight = UDim.new(0, 5)
		elementHolderInnerBackgroundPadding.PaddingTop = UDim.new(0, 4)

		elementHolderBackgroundPadding.Name = "ElementHolderBackgroundPadding"
		elementHolderBackgroundPadding.Parent = elementHolderBackground
		elementHolderBackgroundPadding.PaddingBottom = UDim.new(0, 1)
		elementHolderBackgroundPadding.PaddingLeft = UDim.new(0, 1)
		elementHolderBackgroundPadding.PaddingRight = UDim.new(0, 1)
		elementHolderBackgroundPadding.PaddingTop = UDim.new(0, 1)

		elementHolderPadding.Name = "ElementHolderPadding"
		elementHolderPadding.Parent = elementHolder
		elementHolderPadding.PaddingBottom = UDim.new(0, 1)
		elementHolderPadding.PaddingLeft = UDim.new(0, 1)
		elementHolderPadding.PaddingRight = UDim.new(0, 1)
		
		return searchBar
	end
	
	local function createKeybind()
		local row       = Instance.new("TextButton")
		local nameLabel = Instance.new("TextLabel")
		local tag       = Instance.new("Frame")
		local tagCorner = Instance.new("UICorner")
		local tagBorder = Instance.new("UIStroke")
		local keyLabel  = Instance.new("TextLabel")

		-- Invisible clickable row
		row.Name                   = "Keybind"
		row.BackgroundTransparency = 1
		row.BorderSizePixel        = 0
		row.Size                   = UDim2.new(1, 0, 0, M.ElementH)
		row.AutoButtonColor        = false
		row.Text                   = ""
		row.Font                   = Enum.Font.SourceSans
		row.TextSize               = 14

		-- Left: the element name
		nameLabel.Name             = "KeybindText"
		nameLabel.Parent           = row
		nameLabel.BackgroundTransparency = 1
		nameLabel.AnchorPoint      = Vector2.new(0, 0.5)
		nameLabel.Position         = UDim2.new(0, 0, 0.5, 0)
		nameLabel.Size             = UDim2.new(1, -60, 1, 0)
		nameLabel.Font             = Enum.Font.GothamMedium
		nameLabel.Text             = "N/A"
		nameLabel.TextColor3       = Theme.Text
		nameLabel.TextSize         = M.TextSize
		nameLabel.ClipsDescendants = true
		nameLabel.TextXAlignment   = Enum.TextXAlignment.Left

		-- Right: key tag box
		tag.Name                   = "BoxBackground"   -- keep old name for compat
		tag.Parent                 = row
		tag.AnchorPoint            = Vector2.new(1, 0.5)
		tag.BackgroundColor3       = Color3.fromRGB(22, 23, 32)
		tag.BorderSizePixel        = 0
		tag.Position               = UDim2.new(1, -2, 0.5, 0)
		tag.Size                   = UDim2.new(0, 52, 0, M.ElementH - 2)

		tagCorner.CornerRadius     = UDim.new(0, 5)
		tagCorner.Parent           = tag

		tagBorder.Name             = "TagBorder"
		tagBorder.Color            = Theme.Accent
		tagBorder.Thickness        = 1.5
		BSMT_ApplyBorderStroke(tagBorder)
		tagBorder.Parent           = tag

		-- The key text (no InnerBox needed, just direct child)
		keyLabel.Name              = "KeyText"
		keyLabel.Parent            = tag
		keyLabel.BackgroundTransparency = 1
		keyLabel.BorderSizePixel   = 0
		keyLabel.Size              = UDim2.new(1, 0, 1, 0)
		keyLabel.Font              = Enum.Font.GothamBold
		keyLabel.Text              = "—"
		keyLabel.TextColor3        = Theme.Accent
		keyLabel.TextSize          = M.TextSize
		keyLabel.TextXAlignment    = Enum.TextXAlignment.Center
		keyLabel.TextTruncate      = Enum.TextTruncate.AtEnd

		-- Compatibility shim: BoxBackground.InnerBox.KeyText path still works
		local innerBox             = Instance.new("Frame")
		innerBox.Name              = "InnerBox"
		innerBox.Parent            = tag
		innerBox.BackgroundTransparency = 1
		innerBox.BorderSizePixel   = 0
		innerBox.Size              = UDim2.new(0, 0, 0, 0)  -- invisible, zero size
		-- Mirror KeyText on InnerBox for old code paths
		keyLabel.Parent = tag  -- already set above; InnerBox.KeyText is an alias
		local _alias               = Instance.new("ObjectValue")
		_alias.Name                = "KeyText"   -- ObjectValue named KeyText won't collide
		_alias.Value               = keyLabel
		_alias.Parent              = innerBox

		-- BoxPadding stub so old padding reads don't error
		local boxPad               = Instance.new("UIPadding")
		boxPad.Name                = "BoxPadding"
		boxPad.PaddingLeft         = UDim.new(0, 0)
		boxPad.PaddingRight        = UDim.new(0, 0)
		boxPad.Parent              = tag

		local boxPad2              = Instance.new("UIPadding")
		boxPad2.Name               = "BoxPadding"
		boxPad2.Parent             = innerBox

		-- BoxAspect stub
		local boxAspect            = Instance.new("UIAspectRatioConstraint")
		boxAspect.Name             = "BoxAspect"
		boxAspect.Parent           = tag

		return row
	end
	
	local function createTextBox()
		local textBox         = Instance.new("TextButton")
		local textBoxNameText = Instance.new("TextLabel")
		local boxBackground   = Instance.new("Frame")
		local boxBgCorner     = Instance.new("UICorner")
		local boxBgStroke     = Instance.new("UIStroke")
		local boxPadding      = Instance.new("UIPadding")
		local innerBox        = Instance.new("Frame")
		local innerBoxCorner  = Instance.new("UICorner")
		local boxPadding_2    = Instance.new("UIPadding")
		local textBoxText     = Instance.new("TextBox")

		textBox.Name                 = "TextBox"
		textBox.BackgroundTransparency = 1
		textBox.BorderSizePixel      = 0
		textBox.Size                 = UDim2.new(1, 0, 0, M.ElementH)
		textBox.AutoButtonColor      = false
		textBox.Font                 = Enum.Font.SourceSans
		textBox.Text                 = ""
		textBox.TextSize             = 14

		-- Label above the input (left-aligned)
		textBoxNameText.Name         = "TextBoxNameText"
		textBoxNameText.Parent       = textBox
		textBoxNameText.BackgroundTransparency = 1
		textBoxNameText.Size         = UDim2.new(0.45, 0, 1, 0)
		textBoxNameText.Font         = Enum.Font.Gotham
		textBoxNameText.Text         = "Textbox"
		textBoxNameText.ClipsDescendants = true
		textBoxNameText.TextColor3   = Color3.fromRGB(190, 190, 205)
		textBoxNameText.TextSize     = M.TextSize
		textBoxNameText.TextXAlignment = Enum.TextXAlignment.Left

		-- Right-side input box
		boxBackground.Name           = "BoxBackground"
		boxBackground.Parent         = textBox
		boxBackground.AnchorPoint    = Vector2.new(1, 0.5)
		boxBackground.BackgroundColor3 = Theme.Element
		boxBackground.BorderSizePixel = 0
		boxBackground.Position       = UDim2.new(1, -2, 0.5, 0)
		boxBackground.Size           = UDim2.new(0.52, 0, 1, -2)

		boxBgCorner.CornerRadius     = UDim.new(0, 5)
		boxBgCorner.Parent           = boxBackground

		boxBgStroke.Color            = Theme.Stroke
		boxBgStroke.Thickness        = 1
		BSMT_ApplyBorderStroke(boxBgStroke)
		boxBgStroke.Parent           = boxBackground

		boxPadding.Name              = "BoxPadding"
		boxPadding.Parent            = boxBackground

		innerBox.Name                = "InnerBox"
		innerBox.Parent              = boxBackground
		innerBox.AnchorPoint         = Vector2.new(0.5, 0.5)
		innerBox.BackgroundTransparency = 1
		innerBox.BorderSizePixel     = 0
		innerBox.Position            = UDim2.new(0.5, 0, 0.5, 0)
		innerBox.Size                = UDim2.new(1, 0, 1, 0)

		innerBoxCorner.CornerRadius  = UDim.new(0, 4)
		innerBoxCorner.Parent        = innerBox

		boxPadding_2.Name            = "BoxPadding"
		boxPadding_2.Parent          = innerBox
		boxPadding_2.PaddingLeft     = UDim.new(0, 6)
		boxPadding_2.PaddingRight    = UDim.new(0, 6)

		textBoxText.Name             = "TextBoxText"
		textBoxText.Parent           = innerBox
		textBoxText.BackgroundTransparency = 1
		textBoxText.BorderSizePixel  = 0
		textBoxText.ClipsDescendants = true
		textBoxText.Size             = UDim2.new(1, 0, 1, 0)
		textBoxText.Font             = Enum.Font.Gotham
		textBoxText.PlaceholderColor3 = Color3.fromRGB(80, 80, 95)
		textBoxText.PlaceholderText  = "Type here..."
		textBoxText.Text             = ""
		textBoxText.TextXAlignment   = Enum.TextXAlignment.Left
		textBoxText.TextColor3       = Color3.fromRGB(200, 200, 212)
		textBoxText.TextSize         = M.TextSize

		return textBox
	end

	
	local function createColorWheel()
		local colorWheel = Instance.new("Frame")
		local heading = Instance.new("TextButton")
		local colorWheelName = Instance.new("TextLabel")
		local boxBackground = Instance.new("Frame")
		local boxBackgroundPadding = Instance.new("UIPadding")
		local innerBox = Instance.new("Frame")
		local innerBoxPadding = Instance.new("UIPadding")
		local innerBoxCorner = Instance.new("UICorner")
		local centerBox = Instance.new("Frame")
		local centerBoxPadding = Instance.new("UIPadding")
		local centerBoxCorner = Instance.new("UICorner")
		local wheelImage = Instance.new("ImageLabel")
		local wheelImageAspect = Instance.new("UIAspectRatioConstraint")
		local dropdownImage = Instance.new("ImageLabel")
		local dropdownButtonAspect = Instance.new("UIAspectRatioConstraint")
		local boxBackgroundCorner = Instance.new("UICorner")
		local wheelHolder = Instance.new("Frame")
		local valueHolder = Instance.new("Frame")
		local colorInputHolder = Instance.new("Frame")
		local colorInputHolderList = Instance.new("UIListLayout")
		local red = Instance.new("Frame")
		local colorText = Instance.new("TextLabel")
		local boxBackground_2 = Instance.new("Frame")
		local boxPadding = Instance.new("UIPadding")
		local innerBox_2 = Instance.new("Frame")
		local boxPadding_2 = Instance.new("UIPadding")
		local colorValue = Instance.new("TextBox")
		local green = Instance.new("Frame")
		local colorText_2 = Instance.new("TextLabel")
		local boxBackground_3 = Instance.new("Frame")
		local boxPadding_3 = Instance.new("UIPadding")
		local innerBox_3 = Instance.new("Frame")
		local boxPadding_4 = Instance.new("UIPadding")
		local colorValue_2 = Instance.new("TextBox")
		local blue = Instance.new("Frame")
		local colorText_3 = Instance.new("TextLabel")
		local boxBackground_4 = Instance.new("Frame")
		local boxPadding_5 = Instance.new("UIPadding")
		local innerBox_4 = Instance.new("Frame")
		local boxPadding_6 = Instance.new("UIPadding")
		local colorValue_3 = Instance.new("TextBox")
		local colorSample = Instance.new("Frame")
		local colorSampleCorner = Instance.new("UICorner")
		local valueSlider = Instance.new("TextButton")
		local valueSliderCorner = Instance.new("UICorner")
		local valueSliderGradient = Instance.new("UIGradient")
		local sliderBar = Instance.new("Frame")
		local sliderBarCorner = Instance.new("UICorner")
		local wheel = Instance.new("ImageButton")
		local wheelAspect = Instance.new("UIAspectRatioConstraint")
		local selector = Instance.new("ImageLabel")
		local selectorAspect = Instance.new("UIAspectRatioConstraint")

		colorWheel.Name = "ColorWheel"
		colorWheel.BackgroundColor3 = Theme.Panel
		colorWheel.BackgroundTransparency = 1.000
		colorWheel.BorderSizePixel = 0
		colorWheel.ClipsDescendants = true
		colorWheel.Size = UDim2.new(1, 0, 0, M.ElementH)

		heading.Name = "Heading"
		heading.Parent = colorWheel
		heading.BackgroundColor3 = Theme.Element
		heading.BackgroundTransparency = 1.000
		heading.BorderSizePixel = 0
		heading.Size = UDim2.new(1, 0, 0, M.ElementH)
		heading.Font = Enum.Font.SourceSans
		heading.Text = ""
		heading.TextColor3 = Color3.fromRGB(0, 0, 0)
		heading.TextSize = 14.000

		colorWheelName.Name = "ColorWheelName"
		colorWheelName.Parent = heading
		colorWheelName.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		colorWheelName.BackgroundTransparency = 1.000
		colorWheelName.BorderSizePixel = 0
		colorWheelName.Size = UDim2.new(1, 0, 1, 0)
		colorWheelName.Font = Enum.Font.Gotham
		colorWheelName.Text = "ColorWheel"
		colorWheelName.ClipsDescendants = true
		colorWheelName.TextColor3 = Color3.fromRGB(255, 255, 255)
		colorWheelName.TextSize = M.TextSize
		colorWheelName.TextXAlignment = Enum.TextXAlignment.Left

		boxBackground.Name = "BoxBackground"
		boxBackground.Parent = heading
		boxBackground.AnchorPoint = Vector2.new(1, 0)
		boxBackground.BackgroundColor3 = Theme.ElementLight
		boxBackground.BorderSizePixel = 0
		boxBackground.Position = UDim2.new(1, 0, 0, 0)
		boxBackground.Size = UDim2.new(0.174999997, 0, 1, 0)

		boxBackgroundPadding.Name = "BoxBackgroundPadding"
		boxBackgroundPadding.Parent = boxBackground
		boxBackgroundPadding.PaddingBottom = UDim.new(0, 1)
		boxBackgroundPadding.PaddingLeft = UDim.new(0, 1)
		boxBackgroundPadding.PaddingRight = UDim.new(0, 1)
		boxBackgroundPadding.PaddingTop = UDim.new(0, 1)

		innerBox.Name = "InnerBox"
		innerBox.Parent = boxBackground
		innerBox.AnchorPoint = Vector2.new(1, 0)
		innerBox.BackgroundColor3 = Theme.Panel
		innerBox.BorderSizePixel = 0
		innerBox.Position = UDim2.new(1, 0, 0, 0)
		innerBox.Size = UDim2.new(1, 0, 1, 0)

		innerBoxPadding.Name = "InnerBoxPadding"
		innerBoxPadding.Parent = innerBox
		innerBoxPadding.PaddingBottom = UDim.new(0, 1)
		innerBoxPadding.PaddingLeft = UDim.new(0, 1)
		innerBoxPadding.PaddingRight = UDim.new(0, 1)
		innerBoxPadding.PaddingTop = UDim.new(0, 1)

		innerBoxCorner.Name = "InnerBoxCorner"
		innerBoxCorner.Parent = innerBox

		centerBox.Name = "CenterBox"
		centerBox.Parent = innerBox
		centerBox.AnchorPoint = Vector2.new(1, 0)
		centerBox.BackgroundColor3 = Theme.Panel
		centerBox.BorderSizePixel = 0
		centerBox.Position = UDim2.new(1, 0, 0, 0)
		centerBox.Size = UDim2.new(1, 0, 1, 0)

		centerBoxPadding.Name = "CenterBoxPadding"
		centerBoxPadding.Parent = centerBox
		centerBoxPadding.PaddingBottom = UDim.new(0, 1)
		centerBoxPadding.PaddingLeft = UDim.new(0, 3)
		centerBoxPadding.PaddingRight = UDim.new(0, 1)
		centerBoxPadding.PaddingTop = UDim.new(0, 1)

		centerBoxCorner.Name = "CenterBoxCorner"
		centerBoxCorner.Parent = centerBox

		wheelImage.Name = "WheelImage"
		wheelImage.Parent = centerBox
		wheelImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		wheelImage.BackgroundTransparency = 1.000
		wheelImage.Size = UDim2.new(1, 0, 1, 0)
		wheelImage.Image = "rbxassetid://11515288750"

		wheelImageAspect.Name = "WheelImageAspect"
		wheelImageAspect.Parent = wheelImage

		dropdownImage.Name = "DropdownImage"
		dropdownImage.Parent = centerBox
		dropdownImage.AnchorPoint = Vector2.new(1, 0)
		dropdownImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		dropdownImage.BackgroundTransparency = 1.000
		dropdownImage.BorderSizePixel = 0
		dropdownImage.Rotation = 180
		dropdownImage.Position = UDim2.new(1, 0, 0, 0)
		dropdownImage.Size = UDim2.new(1, 0, 1, 0)
		dropdownImage.Image = "rbxassetid://11269835227"

		dropdownButtonAspect.Name = "DropdownButtonAspect"
		dropdownButtonAspect.Parent = dropdownImage

		boxBackgroundCorner.Name = "BoxBackgroundCorner"
		boxBackgroundCorner.Parent = boxBackground

		wheelHolder.Name = "WheelHolder"
		wheelHolder.Parent = colorWheel
		wheelHolder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		wheelHolder.BackgroundTransparency = 1.000
		wheelHolder.BorderSizePixel = 0
		wheelHolder.Position = UDim2.new(0, 0, 0, 22)
		wheelHolder.Size = UDim2.new(1, 0, 0, 98)

		valueHolder.Name = "ValueHolder"
		valueHolder.Parent = wheelHolder
		valueHolder.AnchorPoint = Vector2.new(1, 0)
		valueHolder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		valueHolder.BackgroundTransparency = 1.000
		valueHolder.BorderSizePixel = 0
		valueHolder.Position = UDim2.new(1, 0, 0, 0)
		valueHolder.Size = UDim2.new(0.899999976, -102, 1, 0)

		colorInputHolder.Name = "ColorInputHolder"
		colorInputHolder.Parent = valueHolder
		colorInputHolder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		colorInputHolder.BackgroundTransparency = 1.000
		colorInputHolder.BorderSizePixel = 0
		colorInputHolder.Size = UDim2.new(1, 0, 1, -36)

		colorInputHolderList.Name = "ColorInputHolderList"
		colorInputHolderList.Parent = colorInputHolder
		colorInputHolderList.SortOrder = Enum.SortOrder.LayoutOrder
		colorInputHolderList.Padding = UDim.new(0, 4)

		red.Name = "Red"
		red.Parent = colorInputHolder
		red.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		red.BackgroundTransparency = 1.000
		red.BorderSizePixel = 0
		red.ClipsDescendants = true
		red.Size = UDim2.new(1, 0, 0, 18)

		colorText.Name = "ColorText"
		colorText.Parent = red
		colorText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		colorText.BackgroundTransparency = 1.000
		colorText.BorderSizePixel = 0
		colorText.Size = UDim2.new(0.670000017, 0, 1, 0)
		colorText.Font = Enum.Font.Gotham
		colorText.Text = "Red:"
		colorText.TextColor3 = Color3.fromRGB(255, 255, 255)
		colorText.TextSize = M.TextSize
		colorText.TextXAlignment = Enum.TextXAlignment.Right

		boxBackground_2.Name = "BoxBackground"
		boxBackground_2.Parent = red
		boxBackground_2.AnchorPoint = Vector2.new(1, 0)
		boxBackground_2.BackgroundColor3 = Theme.ElementLight
		boxBackground_2.BorderSizePixel = 0
		boxBackground_2.Position = UDim2.new(1, 0, 0, 0)
		boxBackground_2.Size = UDim2.new(0.300000012, 0, 1, 0)

		boxPadding.Name = "BoxPadding"
		boxPadding.Parent = boxBackground_2
		boxPadding.PaddingBottom = UDim.new(0, 1)
		boxPadding.PaddingLeft = UDim.new(0, 1)
		boxPadding.PaddingRight = UDim.new(0, 1)
		boxPadding.PaddingTop = UDim.new(0, 1)

		innerBox_2.Name = "InnerBox"
		innerBox_2.Parent = boxBackground_2
		innerBox_2.AnchorPoint = Vector2.new(0.5, 0.5)
		innerBox_2.BackgroundColor3 = Theme.Panel
		innerBox_2.BorderSizePixel = 0
		innerBox_2.Position = UDim2.new(0.5, 0, 0.5, 0)
		innerBox_2.Size = UDim2.new(1, 0, 1, 0)

		boxPadding_2.Name = "BoxPadding"
		boxPadding_2.Parent = innerBox_2
		boxPadding_2.PaddingBottom = UDim.new(0, 1)
		boxPadding_2.PaddingLeft = UDim.new(0, 1)
		boxPadding_2.PaddingRight = UDim.new(0, 1)
		boxPadding_2.PaddingTop = UDim.new(0, 1)

		colorValue.Name = "ColorValue"
		colorValue.Parent = innerBox_2
		colorValue.BackgroundColor3 = Theme.Panel
		colorValue.BorderSizePixel = 0
		colorValue.ClipsDescendants = true
		colorValue.Size = UDim2.new(1, 0, 1, 0)
		colorValue.Font = Enum.Font.Gotham
		colorValue.PlaceholderColor3 = Color3.fromRGB(90, 90, 105)
		colorValue.Text = "255"
		colorValue.TextColor3 = Color3.fromRGB(90, 90, 105)
		colorValue.TextSize = M.TextSize

		green.Name = "Green"
		green.Parent = colorInputHolder
		green.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		green.BackgroundTransparency = 1.000
		green.BorderSizePixel = 0
		green.Size = UDim2.new(1, 0, 0, 18)

		colorText_2.Name = "ColorText"
		colorText_2.Parent = green
		colorText_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		colorText_2.BackgroundTransparency = 1.000
		colorText_2.BorderSizePixel = 0
		colorText_2.Size = UDim2.new(0.699999988, 0, 1, 0)
		colorText_2.Font = Enum.Font.Gotham
		colorText_2.Text = "Green:"
		green.ClipsDescendants = true
		colorText_2.TextColor3 = Color3.fromRGB(255, 255, 255)
		colorText_2.TextSize = M.TextSize
		colorText_2.TextXAlignment = Enum.TextXAlignment.Right

		boxBackground_3.Name = "BoxBackground"
		boxBackground_3.Parent = green
		boxBackground_3.AnchorPoint = Vector2.new(1, 0)
		boxBackground_3.BackgroundColor3 = Theme.ElementLight
		boxBackground_3.BorderSizePixel = 0
		boxBackground_3.Position = UDim2.new(1, 0, 0, 0)
		boxBackground_3.Size = UDim2.new(0.300000012, 0, 1, 0)

		boxPadding_3.Name = "BoxPadding"
		boxPadding_3.Parent = boxBackground_3
		boxPadding_3.PaddingBottom = UDim.new(0, 1)
		boxPadding_3.PaddingLeft = UDim.new(0, 1)
		boxPadding_3.PaddingRight = UDim.new(0, 1)
		boxPadding_3.PaddingTop = UDim.new(0, 1)

		innerBox_3.Name = "InnerBox"
		innerBox_3.Parent = boxBackground_3
		innerBox_3.AnchorPoint = Vector2.new(0.5, 0.5)
		innerBox_3.BackgroundColor3 = Theme.Panel
		innerBox_3.BorderSizePixel = 0
		innerBox_3.Position = UDim2.new(0.5, 0, 0.5, 0)
		innerBox_3.Size = UDim2.new(1, 0, 1, 0)

		boxPadding_4.Name = "BoxPadding"
		boxPadding_4.Parent = innerBox_3
		boxPadding_4.PaddingBottom = UDim.new(0, 1)
		boxPadding_4.PaddingLeft = UDim.new(0, 1)
		boxPadding_4.PaddingRight = UDim.new(0, 1)
		boxPadding_4.PaddingTop = UDim.new(0, 1)

		colorValue_2.Name = "ColorValue"
		colorValue_2.Parent = innerBox_3
		colorValue_2.BackgroundColor3 = Theme.Panel
		colorValue_2.BorderSizePixel = 0
		colorValue_2.ClipsDescendants = true
		colorValue_2.Size = UDim2.new(1, 0, 1, 0)
		colorValue_2.Font = Enum.Font.Gotham
		colorValue_2.PlaceholderColor3 = Color3.fromRGB(90, 90, 105)
		colorValue_2.Text = "255"
		colorValue_2.TextColor3 = Color3.fromRGB(90, 90, 105)
		colorValue_2.TextSize = M.TextSize

		blue.Name = "Blue"
		blue.Parent = colorInputHolder
		blue.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		blue.BackgroundTransparency = 1.000
		blue.ClipsDescendants = true
		blue.BorderSizePixel = 0
		blue.Size = UDim2.new(1, 0, 0, 18)

		colorText_3.Name = "ColorText"
		colorText_3.Parent = blue
		colorText_3.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		colorText_3.BackgroundTransparency = 1.000
		colorText_3.BorderSizePixel = 0
		colorText_3.Size = UDim2.new(0.670000017, 0, 1, 0)
		colorText_3.Font = Enum.Font.Gotham
		colorText_3.Text = "Blue:"
		colorText_3.TextColor3 = Color3.fromRGB(255, 255, 255)
		colorText_3.TextSize = M.TextSize
		colorText_3.TextXAlignment = Enum.TextXAlignment.Right

		boxBackground_4.Name = "BoxBackground"
		boxBackground_4.Parent = blue
		boxBackground_4.AnchorPoint = Vector2.new(1, 0)
		boxBackground_4.BackgroundColor3 = Theme.ElementLight
		boxBackground_4.BorderSizePixel = 0
		boxBackground_4.Position = UDim2.new(1, 0, 0, 0)
		boxBackground_4.Size = UDim2.new(0.300000012, 0, 1, 0)

		boxPadding_5.Name = "BoxPadding"
		boxPadding_5.Parent = boxBackground_4
		boxPadding_5.PaddingBottom = UDim.new(0, 1)
		boxPadding_5.PaddingLeft = UDim.new(0, 1)
		boxPadding_5.PaddingRight = UDim.new(0, 1)
		boxPadding_5.PaddingTop = UDim.new(0, 1)

		innerBox_4.Name = "InnerBox"
		innerBox_4.Parent = boxBackground_4
		innerBox_4.AnchorPoint = Vector2.new(0.5, 0.5)
		innerBox_4.BackgroundColor3 = Theme.Panel
		innerBox_4.BorderSizePixel = 0
		innerBox_4.Position = UDim2.new(0.5, 0, 0.5, 0)
		innerBox_4.Size = UDim2.new(1, 0, 1, 0)

		boxPadding_6.Name = "BoxPadding"
		boxPadding_6.Parent = innerBox_4
		boxPadding_6.PaddingBottom = UDim.new(0, 1)
		boxPadding_6.PaddingLeft = UDim.new(0, 1)
		boxPadding_6.PaddingRight = UDim.new(0, 1)
		boxPadding_6.PaddingTop = UDim.new(0, 1)

		colorValue_3.Name = "ColorValue"
		colorValue_3.Parent = innerBox_4
		colorValue_3.BackgroundColor3 = Theme.Panel
		colorValue_3.BorderSizePixel = 0
		colorValue_3.ClipsDescendants = true
		colorValue_3.Size = UDim2.new(1, 0, 1, 0)
		colorValue_3.Font = Enum.Font.Gotham
		colorValue_3.PlaceholderColor3 = Color3.fromRGB(90, 90, 105)
		colorValue_3.Text = "255"
		colorValue_3.TextColor3 = Color3.fromRGB(90, 90, 105)
		colorValue_3.TextSize = M.TextSize

		colorSample.Name = "ColorSample"
		colorSample.Parent = valueHolder
		colorSample.AnchorPoint = Vector2.new(0, 1)
		colorSample.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		colorSample.BorderSizePixel = 0
		colorSample.Position = UDim2.new(0, 0, 1, -18)
		colorSample.Size = UDim2.new(1, 0, 0, 14)

		colorSampleCorner.CornerRadius = UDim.new(0.25, 0)
		colorSampleCorner.Name = "ColorSampleCorner"
		colorSampleCorner.Parent = colorSample

		valueSlider.Name = "ValueSlider"
		valueSlider.Parent = valueHolder
		valueSlider.AnchorPoint = Vector2.new(0, 1)
		valueSlider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		valueSlider.BorderSizePixel = 0
		valueSlider.Position = UDim2.new(0, 0, 1, 0)
		valueSlider.Size = UDim2.new(1, 0, 0, 14)
		valueSlider.AutoButtonColor = false
		valueSlider.Font = Enum.Font.SourceSans
		valueSlider.Text = ""
		valueSlider.TextColor3 = Color3.fromRGB(0, 0, 0)
		valueSlider.TextSize = 14.000

		valueSliderCorner.CornerRadius = UDim.new(0.25, 0)
		valueSliderCorner.Name = "ValueSliderCorner"
		valueSliderCorner.Parent = valueSlider

		valueSliderGradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(0, 0, 0)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 255, 255))}
		valueSliderGradient.Name = "ValueSliderGradient"
		valueSliderGradient.Parent = valueSlider

		sliderBar.Name = "SliderBar"
		sliderBar.Parent = valueSlider
		sliderBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		sliderBar.BorderSizePixel = 0
		sliderBar.Size = UDim2.new(0, 3, 1, 0)

		sliderBarCorner.CornerRadius = UDim.new(0.25, 0)
		sliderBarCorner.Name = "SliderBarCorner"
		sliderBarCorner.Parent = sliderBar

		wheel.Name = "Wheel"
		wheel.Parent = wheelHolder
		wheel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		wheel.BackgroundTransparency = 1.000
		wheel.BorderSizePixel = 0
		wheel.Size = UDim2.new(1, 0, 1, 0)
		wheel.AutoButtonColor = false
		wheel.Image = "rbxassetid://11515288750"

		wheelAspect.Name = "WheelAspect"
		wheelAspect.Parent = wheel

		selector.Name = "Selector"
		selector.Parent = wheel
		selector.AnchorPoint = Vector2.new(0.5, 0.5)
		selector.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		selector.BackgroundTransparency = 1.000
		selector.BorderSizePixel = 0
		selector.Position = UDim2.new(0.5, 0, 0.5, 0)
		selector.Size = UDim2.new(0.125, 0, 0.125, 0)
		selector.Image = "rbxassetid://11515686713"

		selectorAspect.Name = "SelectorAspect"
		selectorAspect.Parent = selector
		
		return colorWheel
	end
	
	originalElements.Window = createWindow()
	originalElements.Tab = createTab()	
	originalElements.Page = createPage()	
	originalElements.Section = createSection()
	originalElements.Title = createTitle()
	originalElements.Label = createLabel()
	originalElements.Toggle = createToggle()
	originalElements.Button = createButton()
	originalElements.Dropdown = createDropdown()
	originalElements.Slider = createSlider()
	originalElements.SearchBar = createSearchBar()
	originalElements.Keybind = createKeybind()
	originalElements.TextBox = createTextBox()
	originalElements.ColorWheel = createColorWheel()
end

function elementHandler:Remove()
	self.GuiToRemove:Destroy()
end

--Add zindex var to determine which window goes over which
--Add var to only have one window open at a time allowed
function Library.new(windowName: string, constrainToScreen: boolean?, width: number?, height: number?, visibilityKeybind: string?, backgroundImageId: string?): table
	local window = setmetatable({}, windowHandler) -- remove elementhandler from window hanlers index?
	local windowInstance = originalElements.Window:Clone()
	local startDragMousePos
	local startDragWindowPos
	local originialWindowSize
	local minimizedLongBarOriginialSize
	local minimizedShortBarOriginialSize
    window.IsHidden = false
    window.TabInfo = {}

	local background = windowInstance.Background
	local heading = background.Heading
	local buttonHolder = heading.ButtonHolder
	local holder = background.Holder

	local function getMatchingKeyCodeFromName(name: string)
		if not name then return end
		for i, keycode in pairs(Enum.KeyCode:GetEnumItems()) do
			if keycode.Name:lower() == name:lower() then
				return keycode
			end
		end
	end

	local function updateWindowPos()
		local deltaPos = Vector2.new(mouse.X, mouse.Y) - startDragMousePos
		local windowPos = background.Position

		if window.isConstraintedToScreenBoundaries then
			local backgroundAbsPos = background.AbsolutePosition
			local backgroundAbsSize = background.AbsoluteSize
			
			background.Position = UDim2.new(0,math.clamp(startDragWindowPos.X + deltaPos.X, 0 + backgroundAbsSize.X / 2, viewPortSize.X - backgroundAbsSize.X / 2), windowPos.Y.Scale, math.clamp(startDragWindowPos.Y + deltaPos.Y, 0 + backgroundAbsSize.Y / 2,viewPortSize.Y - backgroundAbsSize.Y / 2))
		else
			background.Position = UDim2.new(0, startDragWindowPos.X + deltaPos.X, 0, startDragWindowPos.Y + deltaPos.Y)	
		end
	end

	local function onHeadingMouseDown()
		-- Desktop only – touch drag is handled separately via TouchMoved
		if isMobile then return end
		local mouseMovedConnection = mouse.Move:Connect(updateWindowPos)
		local inputEndedConnection

		startDragMousePos = Vector2.new(mouse.X, mouse.Y)
		startDragWindowPos = Vector2.new(background.Position.X.Offset, background.Position.Y.Offset)
		updateWindowPos()

		inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				mouseMovedConnection:Disconnect()
				inputEndedConnection:Disconnect()
			end
		end)
	end

	-- Mobile drag via UserInputService (heading.TouchStarted is unreliable on TextButton)
	if isMobile then
		local dragging    = false
		local dragTouchId = nil
		UserInputService.TouchStarted:Connect(function(touch, _gp)
			if dragging then return end
			-- Only start drag if touch began inside the heading
			local headingPos  = heading.AbsolutePosition
			local headingSize = heading.AbsoluteSize
			local tx, ty = touch.Position.X, touch.Position.Y
			if tx >= headingPos.X and tx <= headingPos.X + headingSize.X
				and ty >= headingPos.Y and ty <= headingPos.Y + headingSize.Y then
				dragging = true
				dragTouchId = touch.TouchId
				startDragMousePos  = Vector2.new(tx, ty)
				startDragWindowPos = Vector2.new(background.Position.X.Offset, background.Position.Y.Offset)
			end
		end)
		UserInputService.TouchMoved:Connect(function(touch, _gp)
			if not dragging or touch.TouchId ~= dragTouchId then return end
			local delta  = Vector2.new(touch.Position.X, touch.Position.Y) - startDragMousePos
			local bgSize = background.AbsoluteSize
			local newX   = math.clamp(startDragWindowPos.X + delta.X, bgSize.X / 2, viewPortSize.X - bgSize.X / 2)
			local newY   = math.clamp(startDragWindowPos.Y + delta.Y, bgSize.Y / 2, viewPortSize.Y - bgSize.Y / 2)
			background.Position = UDim2.new(0, newX, 0, newY)
		end)
		UserInputService.TouchEnded:Connect(function(touch, _gp)
			if touch.TouchId == dragTouchId then
				dragging    = false
				dragTouchId = nil
			end
		end)
	end

	local function closeWindow()
        local closeWindowTween = TweenService:Create(windowInstance.Background, TweenInfo.new(.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0,0,0,0)})
        closeWindowTween.Completed:Connect(function()
            task.wait()
			if window and window._visibilityConn then
				window._visibilityConn:Disconnect()
				window._visibilityConn = nil
			end
			windowInstance:Destroy() -- add cool tween cause cool
            window = nil
        end)
        closeWindowTween:Play()
	end

	local function minimizeWindow()
		window.IsMinimized = true
		local backgroundAbsPos = background.AbsolutePosition
		local backgroundAbsSize = background.AbsoluteSize
		local minimizeWindowUpTween = TweenService:Create(background, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Size = UDim2.new(0,minimizedLongBarOriginialSize.X,0, minimizedLongBarOriginialSize.Y), Position = UDim2.new(0,backgroundAbsPos.X + minimizedLongBarOriginialSize.X / 2,0, backgroundAbsPos.Y + minimizedLongBarOriginialSize.Y / 2 + 36)})
		local minimizeMinusImageTween = TweenService:Create(buttonHolder.Minus, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Rotation = 180, ImageTransparency = 1})
		local minimizePlusImageTween = TweenService:Create(buttonHolder.Plus, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Rotation = 0, ImageTransparency = 0})
		
		minimizeWindowUpTween.Completed:Connect(function()
			task.wait(.1)
			if minimizeWindowUpTween.PlaybackState == Enum.PlaybackState.Completed then
				local minimizeWindowLeftTween = TweenService:Create(background, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Size = UDim2.new(0, minimizedShortBarOriginialSize.X,0,minimizedShortBarOriginialSize.Y), Position = UDim2.new(0,background.AbsolutePosition.X + minimizedShortBarOriginialSize.X / 2,0, background.AbsolutePosition.Y + minimizedShortBarOriginialSize.Y / 2 + 36)})
				minimizeWindowLeftTween:Play()
			end
		end)
		
		minimizeMinusImageTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				buttonHolder.Minus.Visible = false
				buttonHolder.Plus.Visible = true
				minimizePlusImageTween:Play()
			end
		end)
		
		minimizeWindowUpTween:Play()
		minimizeMinusImageTween:Play()
	end

	local function maximizeWindow()
		window.IsMinimized = false
		local backgroundAbsPos = background.AbsolutePosition
		local backgroundAbsSize = background.AbsoluteSize
		local maximizeWindowRightTween = TweenService:Create(background, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Size = UDim2.new(0,minimizedLongBarOriginialSize.X,0,minimizedLongBarOriginialSize.Y), Position = UDim2.new(0, backgroundAbsPos.X + minimizedLongBarOriginialSize.X / 2,0,backgroundAbsPos.Y + minimizedLongBarOriginialSize.Y / 2 + 36)})
		local maximizePlusImageTween = TweenService:Create(buttonHolder.Plus, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Rotation = 180, ImageTransparency = 1})
		local maximizeMinusImageTween = TweenService:Create(buttonHolder.Minus, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Rotation = 0, ImageTransparency = 0})
		
		maximizeWindowRightTween.Completed:Connect(function()
			task.wait(.1)
			if maximizeWindowRightTween.PlaybackState == Enum.PlaybackState.Completed then
				local maximizeWindowDownTween = TweenService:Create(background, TweenInfo.new(.2, Enum.EasingStyle.Linear), {Size = UDim2.new(0, originialWindowSize.X, 0, originialWindowSize.Y), Position = UDim2.new(0,backgroundAbsPos.X + originialWindowSize.X / 2,0,backgroundAbsPos.Y + originialWindowSize.Y / 2 + 36)})
				buttonHolder.Plus.Visible = false
				buttonHolder.Minus.Visible = true
				maximizeWindowDownTween:Play()
				maximizeMinusImageTween:Play()
			end
		end)
		
		maximizeWindowRightTween:Play()
		maximizePlusImageTween:Play()
	end

	if constrainToScreen == nil then
		constrainToScreen = true
	end

	-- Parse & store the starting keybind on the window object itself
	window.CurrentKeybind = getMatchingKeyCodeFromName(visibilityKeybind) or Enum.KeyCode.RightShift

	window.Type = "Window"
	window.Instance = windowInstance
	window.GuiToRemove = windowInstance
	window.isConstraintedToScreenBoundaries = constrainToScreen
	window.IsMinimized = false
	window.IsHidden = false
	window.TabInfo = {}

	heading.MouseButton1Down:Connect(onHeadingMouseDown)
	buttonHolder.Close.MouseButton1Click:Connect(closeWindow)
	buttonHolder.Plus.MouseButton1Click:Connect(maximizeWindow)
	buttonHolder.Minus.MouseButton1Click:Connect(minimizeWindow)

	-- Visibility toggle — always reads window.CurrentKeybind so SetKeybind changes take effect
	window._visibilityConn = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then return end
		-- Window was closed/destroyed: tear this listener down instead of erroring
		if not background or not background.Parent then
			if window and window._visibilityConn then
				window._visibilityConn:Disconnect()
				window._visibilityConn = nil
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == window.CurrentKeybind then
				background.Visible = not background.Visible
			end
		end
	end)

	AutoCanvasSize(holder.Tabs, holder.Tabs.TabsUIListLayout)

	heading.Title.Text = windowName or "BSMT"
	parentProtected(windowInstance)
	-- Background image removed
	window._backgroundImageId = ""

	-- Responsive window sizing
	if isMobile then
		-- Drop the desktop aspect-ratio lock BEFORE sizing, otherwise it distorts the
		-- mobile size and the absolutes we read below are wrong (window off-screen / wrong size).
		local arc = background:FindFirstChild("BackgroundUIAspectRatioConstraint")
		if arc then arc:Destroy() end

		background.Size = UDim2.new(0.92, 0, 0.72, 0)
		game:GetService("RunService").Heartbeat:Wait()  -- let absolutes settle at the new size

		-- Center from the viewport (anchor 0.5,0.5) — no stale AbsolutePosition read and no
		-- +36 topbar offset (IgnoreGuiInset is on), so it can never land off-screen.
		-- BSMT_GetViewportSize: CurrentCamera can be nil while mobile is loading.
		local vp = BSMT_GetViewportSize()
		background.Position = UDim2.new(0, math.round(vp.X / 2), 0, math.round(vp.Y / 2))

		holder.Size     = UDim2.new(0, holder.AbsoluteSize.X, 0, holder.AbsoluteSize.Y)
		holder.Position = UDim2.new(0, 0, 0, heading.AbsoluteSize.Y)
		heading.Size    = UDim2.new(1, 0, 0, heading.AbsoluteSize.Y)
	else
		background.Size = UDim2FromOffset(background.AbsoluteSize.X, background.AbsoluteSize.Y)
		if width then
			background.Size = UDim2FromOffset(width, background.AbsoluteSize.Y)
		end
		if height then
			background.Size = UDim2FromOffset(background.AbsoluteSize.X, height)
		end

		background.Position = UDim2.new(0, background.AbsolutePosition.X + background.AbsoluteSize.X / 2, 0, background.AbsolutePosition.Y + background.AbsoluteSize.Y / 2 + 36)
		background.BackgroundUIAspectRatioConstraint:Destroy()
		holder.Size = UDim2.new(0,holder.AbsoluteSize.X,0,holder.AbsoluteSize.Y)
		holder.Position = UDim2.new(0,0,0,heading.AbsoluteSize.Y)
		heading.Size = UDim2.new(1,0,0,heading.AbsoluteSize.Y)
	end
	buttonHolder.Size = UDim2.new(0,buttonHolder.ButtonHolderList.AbsoluteContentSize.X + buttonHolder.ButtonHolderPadding.PaddingRight.Offset,.9,0)
	heading.Title.Size = UDim2.new(1,-(buttonHolder.ButtonHolderList.AbsoluteContentSize.X + buttonHolder.ButtonHolderPadding.PaddingRight.Offset + 4),.9,0)
	minimizedLongBarOriginialSize = Vector2.new(heading.AbsoluteSize.X, heading.AbsoluteSize.Y)
	minimizedShortBarOriginialSize = Vector2.new(heading.AbsoluteSize.X / 6 * 2, heading.AbsoluteSize.Y)
	originialWindowSize = background.AbsoluteSize
	
	return window
end

function windowHandler:LockScreenBoundaries(constrainWindowToScreenBoundaries)
	self.isConstraintedToScreenBoundaries = constrainWindowToScreenBoundaries
end

function windowHandler:Tab(tabName: string, tabImage: string): table
	local tab = setmetatable({}, tabHandler)
	local tabInstance = originalElements.Tab:Clone()
	local pageInstance = originalElements.Page:Clone()
	
	local tabOpenTween = TweenService:Create(tabInstance, TweenInfo.new(.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 0.88})
	local tabCloseTween = TweenService:Create(tabInstance, TweenInfo.new(.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
	local tabSeperatorOpenTween = TweenService:Create(tabInstance.TabSeperator, TweenInfo.new(.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 0})
	local tabSeperatorCloseTween = TweenService:Create(tabInstance.TabSeperator, TweenInfo.new(.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
	local tabTextOpenTween = TweenService:Create(tabInstance.TabText, TweenInfo.new(.2, Enum.EasingStyle.Quad), {TextColor3 = Theme.TextBright})
	local tabTextCloseTween = TweenService:Create(tabInstance.TabText, TweenInfo.new(.2, Enum.EasingStyle.Quad), {TextColor3 = Theme.TextDim})
	local tabImageOpenTween = TweenService:Create(tabInstance.TabImage, TweenInfo.new(.2, Enum.EasingStyle.Quad), {ImageColor3 = Theme.Accent})
	local tabImageCloseTween = TweenService:Create(tabInstance.TabImage, TweenInfo.new(.2, Enum.EasingStyle.Quad), {ImageColor3 = Theme.TextMuted})
	local pageOpenTween = TweenService:Create(pageInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(0.774999976, -25, 1, -15)})	
	local pageCloseTween = TweenService:Create(pageInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(0.775, -25, 0, 0)})
	local logoShowTween = TweenService:Create(self.Instance.Background.Holder.PageLogo, TweenInfo.new(.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = .65})
	local logoHideTween = TweenService:Create(self.Instance.Background.Holder.PageLogo, TweenInfo.new(.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {ImageTransparency = 1})
	
	local function isTabFirstTab()
		local amountOfTabs = 0
		for _, foundTab in ipairs(self.Instance.Background.Holder.Tabs:GetChildren()) do
			if foundTab:IsA("TextButton") then
				amountOfTabs += 1
			end
		end

		if amountOfTabs == 1 then
			return true
		end
		
		return false
	end
	
	local function onMouseEnter()
		if not pageInstance.Visible then
			tabOpenTween:Play()
		end
	end
	
	local function onMouseLeave()
		if not pageInstance.Visible then
			tabCloseTween:Play()
		end
	end
	
	local function onMouseClick()
		local selfInfo = self.TabInfo[tabInstance]
		
		local function openTab()
			local isATabOpen = false
			
			for foundTabInstance, tabInfo in pairs(self.TabInfo) do
				if foundTabInstance ~= tabInstance then
					if tabInfo.isOpen then
						local foundPageCloseTween = TweenService:Create(tabInfo.Page, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(0.775, -25, 0, 0)})
						local foundTabCloseTween = TweenService:Create(foundTabInstance, TweenInfo.new(.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
						local foundTabSeperatorCloseTween = TweenService:Create(foundTabInstance.TabSeperator, TweenInfo.new(.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
						TweenService:Create(foundTabInstance.TabText, TweenInfo.new(.2, Enum.EasingStyle.Quad), {TextColor3 = Theme.TextDim}):Play()
						TweenService:Create(foundTabInstance.TabImage, TweenInfo.new(.2, Enum.EasingStyle.Quad), {ImageColor3 = Theme.TextDim}):Play()

						isATabOpen = true
						tabInfo.isOpen = false

						foundPageCloseTween.Completed:Connect(function()
							task.wait(.15)
							if selfInfo.isQueued and foundPageCloseTween.PlaybackState == Enum.PlaybackState.Completed then
								selfInfo.isOpen = true
								pageInstance.Visible = true
								tabInfo.Page.Visible = false
								tabOpenTween:Play()
								tabSeperatorOpenTween:Play()
								tabTextOpenTween:Play()
								tabImageOpenTween:Play()
								pageOpenTween:Play()
							end
						end)
						
						pageOpenTween.Completed:Connect(function()
							if pageOpenTween.PlaybackState == Enum.PlaybackState.Completed then
								logoHideTween:Play()
							end
						end)
						
						selfInfo.isQueued = true
						foundPageCloseTween:Play()
						foundTabCloseTween:Play()
						foundTabSeperatorCloseTween:Play()
						logoShowTween:Play()
					elseif tabInfo.isQueued then
						tabInfo.isQueued = false
					end
				end
			end
			
			if not isATabOpen then
				selfInfo.isOpen = true
				pageInstance.Visible = true
				pageOpenTween:Play()
				tabOpenTween:Play()
				tabSeperatorOpenTween:Play()
				tabTextOpenTween:Play()
				tabImageOpenTween:Play()
				logoHideTween:Play()
			end
		end
		
		local function closeTab()
			selfInfo.isOpen = false
			tabCloseTween:Play()
			tabSeperatorCloseTween:Play()
			tabTextCloseTween:Play()
			tabImageCloseTween:Play()
			pageCloseTween:Play()
			logoShowTween:Play()
		end
		
		if selfInfo.isOpen then
			closeTab()
		else
			openTab()
		end
	end	
	
	tab.Type = "Tab"
	tab.IdentifierText = tabName or "N/A"
	tab.TabToRemove = tabInstance
	tab.PageToRemove = pageInstance
	tab.ElementToParentChildren = pageInstance
	
	tabInstance.TabText.Text = tabName or "N/A"
	tabInstance.TabImage.Image = tabImage or "rbxassetid://11436779516" -- Add n/a found image here later on

	tabInstance.MouseEnter:Connect(onMouseEnter)
	tabInstance.MouseLeave:Connect(onMouseLeave)
	tabInstance.MouseButton1Click:Connect(onMouseClick)
	
	self.TabInfo[tabInstance] = {Page = pageInstance, isOpen = false, isQueued = false}
	tabInstance.Parent = self.Instance.Background.Holder.Tabs
	-- Icon is at x=12, fixed 15px. Text starts after it.
	tabInstance.TabText.Position = UDim2.new(0, 32, 0, 0)
	tabInstance.TabText.Size     = UDim2.new(1, -36, 1, 0)
	pageInstance.Parent = self.Instance.Background.Holder

	-- Background image feature removed

	if isTabFirstTab() then
		tabInstance.TabSeperator.BackgroundTransparency = 0
		tabInstance.BackgroundTransparency = 0.88
		tabInstance.TabText.TextColor3 = Theme.TextBright
		tabInstance.TabImage.ImageColor3 = Theme.Accent
		pageInstance.Visible = true
		pageInstance.Size = UDim2.new(0.774999976, -25, 1, -15)
		self.TabInfo[tabInstance].isOpen = true
	end
	
	pageCloseTween.Completed:Connect(function()
		if pageCloseTween.PlaybackState == Enum.PlaybackState.Completed then
			pageInstance.Visible = false	
		end
	end)
	
	for _, scrollingFrame in ipairs(pageInstance:GetChildren()) do
		if scrollingFrame:IsA("ScrollingFrame") then
			local list = scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
			if list then
				scrollingFrame.ScrollingEnabled = true
				scrollingFrame.ClipsDescendants = true
				scrollingFrame.Active = true
				AutoCanvasSize(scrollingFrame, list)
			end
		end
	end
	
	return tab
end

function tabHandler:Remove()
	self.TabToRemove:Destroy()
	self.PageToRemove:Destroy()
end

function tabHandler:Section(sectionTitle: string) -- Add option to make on left or right after
	local section = setmetatable({}, sectionHandler)
	local sectionInstance = originalElements.Section:Clone()
	local isMaximized = true
	local resizeButtonMinimizeTween = TweenService:Create(sectionInstance.Heading.ResizeButton, TweenInfo.new(.15, Enum.EasingStyle.Linear), {Rotation = 180})
	local resizeButtonMaximizeTween = TweenService:Create(sectionInstance.Heading.ResizeButton, TweenInfo.new(.15, Enum.EasingStyle.Linear), {Rotation = 0})
	local sectionInstanceMinimizeTween = TweenService:Create(sectionInstance, TweenInfo.new(.15, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,sectionInstance.Heading.Size.Y.Offset)})
	
	local function getSectionNeededYOffsetSize()
		local minimumSize = 200
		return math.max(minimumSize, sectionInstance.Heading.Size.Y.Offset + sectionInstance.ElementHolder.ElementHolderList.AbsoluteContentSize.Y + sectionInstance.ElementHolder.ElementHolderPadding.PaddingBottom.Offset + sectionInstance.ElementHolder.ElementHolderPadding.PaddingTop.Offset)
	end
	
	local function getShorterScrollingFrame()
		local pageScrollingFrame
		local pageScrollingFrameContentSizeY = math.huge
		
		for _, scrollingFrame in ipairs(self.ElementToParentChildren:GetChildren()) do
			if not scrollingFrame:IsA("ScrollingFrame") then continue end
			local list = scrollingFrame:FindFirstChildWhichIsA("UIListLayout")
			if not list then continue end
			if pageScrollingFrameContentSizeY > list.AbsoluteContentSize.Y then
				pageScrollingFrame = scrollingFrame
				pageScrollingFrameContentSizeY = list.AbsoluteContentSize.Y
			end
		end
		
		return pageScrollingFrame
	end
	
	local function onResizeClick()
		if isMaximized then
			isMaximized = false
			resizeButtonMinimizeTween:Play()
			sectionInstanceMinimizeTween:Play()
		else
			isMaximized = true
			local sectionInstanceMaximizeTween = TweenService:Create(sectionInstance, TweenInfo.new(.15, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,getSectionNeededYOffsetSize())})
			resizeButtonMaximizeTween:Play()
			sectionInstanceMaximizeTween:Play()
			sectionInstanceMaximizeTween:Play()
		end
	end
	
	section.Type = "Section"
	section.IdentifierText = sectionTitle or "N/A"
	section.Instance = sectionInstance
	section.GuiToRemove = sectionInstance
	section.ElementToParentChildren = sectionInstance.ElementHolder
	
	sectionInstance.Heading.ResizeButton.MouseButton1Click:Connect(onResizeClick)
	
	sectionInstance.ElementHolder.ElementHolderList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sectionInstance.Size = UDim2.new(1, 0, 0, getSectionNeededYOffsetSize())
		sectionInstance.ElementHolder.Size = UDim2.new(1,0,0, math.max(200 - sectionInstance.Heading.Size.Y.Offset, sectionInstance.ElementHolder.ElementHolderList.AbsoluteContentSize.Y + sectionInstance.ElementHolder.ElementHolderPadding.PaddingBottom.Offset + sectionInstance.ElementHolder.ElementHolderPadding.PaddingTop.Offset))
	end)
	
	sectionInstance.Heading.Title.Text = sectionTitle or "N/A"
	sectionInstance.Parent = getShorterScrollingFrame()
	sectionInstance.Heading.Title.Size = UDim2.new(1,-(sectionInstance.Heading.ResizeButton.AbsoluteSize.X + 5 + 3),0,20)
	
	return section
end

function elementHandler:Title(titleName: string)
	local title = setmetatable({}, titleHandler)
	local titleInstance = originalElements.Title:Clone()

	local textSpaceOffset = Vector2.new(10,0)
	-- BSMT_MeasureText: GetTextBoundsAsync/FontFace don't exist on older clients
	local requiredTextSpace = BSMT_MeasureText(titleName or "N/A", 14, BSMT_GetFontFace(titleInstance.TitleText), Enum.Font.Gotham, 10000) + textSpaceOffset

	title.Type = "Title"
	title.IdentifierText = titleName or "N/A"
	title.Instance = titleInstance
	title.GuiToRemove = titleInstance
	
	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[titleInstance] = title
	end

	titleInstance.TitleText.Text = titleName or "N/A"
	titleInstance.TitleText.Size = UDim2.new(0, requiredTextSpace.X, 1, 0)

	titleInstance.Parent = self.ElementToParentChildren

	return title
end

function titleHandler:ChangeText(newText: string): nil
	local textSpaceOffset = Vector2.new(10,0)
	-- BSMT_MeasureText: GetTextBoundsAsync/FontFace don't exist on older clients
	local requiredTextSpace = BSMT_MeasureText(newText or "N/A", 14, BSMT_GetFontFace(self.Instance.TitleText), Enum.Font.Gotham, 10000) + textSpaceOffset
	
	self.Instance.TitleText.Text = newText or "N/A"
	self.Instance.TitleText.Size = UDim2.new(0, requiredTextSpace.X, 1, 0)
end

function elementHandler:Label(labelInputtedText: string, textSize: number, textColor: Color3): table
	local label = setmetatable({}, labelHandler)
	local labelInstance = originalElements.Label:Clone()
	
	-- BSMT_MeasureText: GetTextBoundsAsync/FontFace don't exist on older clients
	local labelFontFace = BSMT_GetFontFace(labelInstance.LabelBackground.LabelText)
	local labelTextSize = textSize or 13

	label.Type = "Label"
	label.IdentifierText = labelInputtedText or "N/A"
	label.Instance = labelInstance
	label.GuiToRemove = labelInstance
	label.PlayingAnimations = {}
	
	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[labelInstance] = label
	end
	
	labelInstance.LabelBackground.LabelText.Text = labelInputtedText or "N/A"
	labelInstance.LabelBackground.LabelText.TextColor3 = textColor or Color3.fromRGB(255,255,255)
	labelInstance.LabelBackground.LabelText.TextSize = textSize or 13
	
	labelInstance.Parent = self.ElementToParentChildren
	local labelMeasureWidth = labelInstance.LabelBackground.LabelText.AbsoluteSize.X - labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingLeft.Offset - labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingRight.Offset
	labelInstance.Size = UDim2.new(1,0,0,BSMT_MeasureText(labelInputtedText or "N/A", labelTextSize, labelFontFace, Enum.Font.Gotham, labelMeasureWidth).Y + labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingTop.Offset + labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingBottom.Offset + labelInstance.LabelPadding.PaddingTop.Offset + labelInstance.LabelPadding.PaddingBottom.Offset + labelInstance.LabelBackground.LabelBackgroundPadding.PaddingTop.Offset + labelInstance.LabelBackground.LabelBackgroundPadding.PaddingBottom.Offset)
	
	return label
end

function labelHandler:ChangeText(newText: string, playAnimation: boolean): nil
	-- (legacy GetTextBoundsParams measuring removed: unsupported on older
	-- Android clients, and this path only assigns text directly)
	
	playAnimation = playAnimation or false
	
	local function closeAllRunningAnimations()
		for i, foundAnimation in pairs(self.PlayingAnimations) do
			coroutine.close(foundAnimation)
			table.remove(self.PlayingAnimations, i)
		end
	end
	
	if playAnimation then
		closeAllRunningAnimations()
		
		local animationCoroutine = coroutine.create(function()
			for i = 1, #newText do
				self.Instance.LabelBackground.LabelText.Text = string.sub(newText or "N/A", 1, i)
				task.wait(.01)	
			end
		end)
		
		table.insert(self.PlayingAnimations, animationCoroutine)
		coroutine.resume(animationCoroutine)
	else
		closeAllRunningAnimations()
		self.Instance.LabelBackground.LabelText.Text = newText or "N/A"
	end
end

-- Toggle and Set handlers defined below with full config support

function elementHandler:Button(buttonName: string, callback): table
	local button = setmetatable({}, buttonHandler)
	local buttonInstance = originalElements.Button:Clone()
	local bg = buttonInstance.ButtonBg

	buttonName = buttonName or "N/A"
	callback   = callback   or function() end

	local pressDown = TweenService:Create(bg, TweenInfo.new(0.1, Enum.EasingStyle.Quad),
		{BackgroundColor3 = Theme.Accent})
	local pressUp = TweenService:Create(bg, TweenInfo.new(0.2, Enum.EasingStyle.Quad),
		{BackgroundColor3 = Theme.Element})

	buttonInstance.MouseButton1Down:Connect(function() pressDown:Play() end)
	buttonInstance.MouseButton1Up:Connect(function() pressUp:Play() end)
	buttonInstance.MouseButton1Click:Connect(function()
		pressUp:Play()
		callback()
	end)

	button.Type          = "Button"
	button.IdentifierText = buttonName or "N/A"
	button.Instance      = buttonInstance
	button.GuiToRemove   = buttonInstance

	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[buttonInstance] = button
	end

	buttonInstance.ButtonBg.ButtonText.Text = buttonName
	buttonInstance.Parent = self.ElementToParentChildren

	return button
end

function elementHandler:Dropdown(dropdownName: string): table
	local dropdown = setmetatable({}, dropdownHandler)
	local dropdownInstance = originalElements.Dropdown:Clone()
	local elementHolderInnerBackground = dropdownInstance.ElementHolder.ElementHolderBackground.ElementHolderInnerBackground
	local elementHolderInnerBackgroundPaddings = 8  -- total vertical padding in the dropdown list
	
	local imageRotationOpenTween = TweenService:Create(dropdownInstance.DropdownButton.ButtonBackground.DropdownImage, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Rotation = 0})
	local imageRotationCloseTween = TweenService:Create(dropdownInstance.DropdownButton.ButtonBackground.DropdownImage, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Rotation = 180})
	local dropdownInstanceCloseTween = TweenService:Create(dropdownInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,dropdownInstance.DropdownButton.Size.Y.Offset)})
	local dropdownInstanceOpenTween
	
	local function onDropdownClicked()
		if dropdown.IsExpanded then
			dropdown.IsExpanded = false
			imageRotationCloseTween:Play()
			dropdownInstanceCloseTween:Play()
		else
			dropdown.IsExpanded = true
			imageRotationOpenTween:Play()
			dropdownInstanceOpenTween:Play()
		end
	end
	
	dropdown.Type = "Dropdown"
	dropdown.IdentifierText = dropdownName or "N/A"
	dropdown.Instance = dropdownInstance
	dropdown.GuiToRemove = dropdownInstance
	dropdown.ElementToParentChildren = dropdownInstance.ElementHolder.ElementHolderBackground.ElementHolderInnerBackground
	dropdown.IsExpanded = false
	
	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[dropdownInstance] = dropdown
	end
	
	dropdownInstance.DropdownButton.MouseButton1Click:Connect(onDropdownClicked)
	
	elementHolderInnerBackground.ElementHolderInnerBackgroundList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if dropdown.IsExpanded then
			if elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y == 0 then
				dropdownInstanceOpenTween = TweenService:Create(dropdownInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0, dropdownInstance.DropdownButton.AbsoluteSize.Y)})
			else
				local elementHolderTween = TweenService:Create(dropdownInstance.ElementHolder, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings)})
				dropdownInstanceOpenTween = TweenService:Create(dropdownInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings + dropdownInstance.DropdownButton.Size.Y.Offset)})
				
				elementHolderTween:Play()
			end
			dropdownInstanceOpenTween:Play()	
		else
			dropdownInstance.ElementHolder.Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings)
			if elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y == 0 then
				dropdownInstanceOpenTween = TweenService:Create(dropdownInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0, dropdownInstance.DropdownButton.AbsoluteSize.Y)})
			else
				dropdownInstanceOpenTween = TweenService:Create(dropdownInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings + dropdownInstance.DropdownButton.Size.Y.Offset)})
			end
		end
	end)
	
	dropdownInstance.DropdownButton.ButtonBackground.DropdownText.Text = dropdownName or "N/A"
	
	dropdownInstance.Parent = self.ElementToParentChildren
	dropdownInstanceOpenTween = TweenService:Create(dropdownInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0, dropdownInstance.DropdownButton.AbsoluteSize.Y + dropdownInstance.ElementHolder.AbsoluteSize.Y)})
	return dropdown
end

function dropdownHandler:ChangeText(newText: string)
	newText = newText or "N/A"
	self.Instance.DropdownButton.ButtonBackground.DropdownText.Text = newText
	self.IdentifierText = newText
end

function elementHandler:Slider(sliderName: string, callback, maximumValue: number, minimumValue: number, flag: string?): table
	local slider = setmetatable({}, sliderHandler) -- MAKE RIGHT CLICK AND BAR GOES TO MID
	local sliderInstance = originalElements.Slider:Clone()
	local isMouseDown = false
	local sliderBar = sliderInstance.SliderBackground.SliderInnerBackground.Slider
	local minimumClosePixelsLeft = 2
	local textPixelOffset = 2
	local absPos
	local absSize

	minimumValue = minimumValue or 0
	maximumValue = maximumValue or 100
	
	-- Degrade gracefully instead of hard-erroring the caller's script
	if maximumValue == minimumValue then maximumValue = minimumValue + 1 end
	if maximumValue < minimumValue then minimumValue, maximumValue = maximumValue, minimumValue end
	
	-- BSMT_MeasureText: GetTextBoundsAsync/FontFace don't exist on older clients
	local sliderNumFace = BSMT_GetFontFace(sliderInstance.TextGrouping.NumberText)
	local requiredNumberTextSpace = BSMT_MeasureText(tostring(maximumValue) or "N/A", 14, sliderNumFace, Enum.Font.GothamBold, 10000)
	local requiredErrorTextSpace = BSMT_MeasureText("ERR", 14, sliderNumFace, Enum.Font.GothamBold, 10000)

	local maxMinRange = math.abs(minimumValue - maximumValue)
	local sliderValue = minimumValue
	
	local sliderConnection
	local endInputConnection

	callback = callback or function() end
	
	-- Apply a value from an absolute X screen coordinate (works for mouse AND touch)
	local function applyFromX(px)
		local absPos = sliderBar.AbsolutePosition
		local absSize = sliderBar.Parent.EmptySliderBackground.AbsoluteSize

		if px < absPos.X then
			sliderBar.Size = UDim2.new(0,minimumClosePixelsLeft,1,0)
			sliderValue = minimumValue
		elseif px > absPos.X + absSize.X then
			sliderBar.Size = UDim2.new(1,0,1,0)
			sliderValue = maximumValue
		else
			local percentOfBarFilled = (px - absPos.X) / absSize.X
			sliderBar.Size = UDim2.new(0,math.max(minimumClosePixelsLeft, px - absPos.X),1,0)
			sliderValue = minimumValue + (maxMinRange * percentOfBarFilled)
		end

		sliderInstance.TextGrouping.NumberText.Text = math.round(sliderValue)
		slider._currentValue = sliderValue
		_G.BSMTConfigData[slider.ConfigIdentifier] = sliderValue
		if slider.Flag then genv[slider.Flag] = sliderValue end
		callback(sliderValue)
	end

	local function onMouseDown(startX)
		isMouseDown = true
		applyFromX(startX or mouse.X)
		sliderConnection = mouse.Move:Connect(function() applyFromX(mouse.X) end)
		local touchConnection = UserInputService.TouchMoved:Connect(function(touch)
			applyFromX(touch.Position.X)
		end)

		endInputConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				isMouseDown = false
				if sliderConnection then sliderConnection:Disconnect() end
				if touchConnection then touchConnection:Disconnect() end
				endInputConnection:Disconnect()
			end
		end)
	end
	
	local function onFocusLost(enterPressed)
		if enterPressed then
			local enteredNum = tonumber(sliderInstance.TextGrouping.NumberText.Text)
			if typeof(enteredNum) == "number" and enteredNum >= minimumValue and enteredNum <= maximumValue then
				sliderValue = enteredNum
				slider._currentValue = sliderValue
				sliderInstance.TextGrouping.NumberText.Text = math.round(sliderValue)
				sliderBar.Size = UDim2.new((sliderValue - minimumValue) / maxMinRange,0,1,0)
				_G.BSMTConfigData[slider.ConfigIdentifier] = sliderValue
				if slider.Flag then genv[slider.Flag] = sliderValue end
				callback(sliderValue)
			else
				sliderInstance.TextGrouping.NumberText.Text = "ERR"
				task.wait(.5)
				if sliderInstance.TextGrouping.NumberText.Text == "ERR" then
					sliderInstance.TextGrouping.NumberText.Text = math.round(sliderValue)
				end
			end
		else
			sliderInstance.TextGrouping.NumberText.Text = math.round(sliderValue)
		end
	end
	
	slider.Type = "Slider"
	slider.IdentifierText = sliderName or "N/A"
	slider.Instance = sliderInstance
	slider.GuiToRemove = sliderInstance
	slider._minValue = minimumValue
	slider._maxValue = maximumValue
	slider._currentValue = minimumValue
	
	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[sliderInstance] = slider
	end

	-- Config / getgenv binding. `flag` (5th arg) names a getgenv() key to mirror.
	slider.Flag = flag
	local sliderConfigKey = flag or sliderName or "N/A"
	slider.ConfigIdentifier = sliderConfigKey
	_G.BSMTConfigElements[sliderConfigKey] = slider

	-- Initial value priority: getgenv flag > saved config > minimum
	if flag and genv[flag] ~= nil then
		slider._currentValue = math.clamp(tonumber(genv[flag]) or minimumValue, minimumValue, maximumValue)
	elseif _G.BSMTConfigData[sliderConfigKey] ~= nil then
		slider._currentValue = _G.BSMTConfigData[sliderConfigKey]
	end

	-- Publish the resolved starting value so external reads are consistent
	_G.BSMTConfigData[sliderConfigKey] = slider._currentValue
	if flag then genv[flag] = slider._currentValue end

	-- Internal helper used by LoadConfig
	function slider:SetValue(v)
		v = math.clamp(tonumber(v) or self._minValue, self._minValue, self._maxValue)
		self._currentValue = v
		local pct = (v - self._minValue) / (self._maxValue - self._minValue)
		sliderBar.Size = UDim2.new(0, math.max(minimumClosePixelsLeft, math.round(pct * sliderBar.Parent.EmptySliderBackground.AbsoluteSize.X)), 1, 0)
		sliderInstance.TextGrouping.NumberText.Text = math.round(v)
		_G.BSMTConfigData[self.ConfigIdentifier] = v
		if self.Flag then genv[self.Flag] = v end
		callback(v)
	end

	-- Live-sync: external `getgenv()[flag] = x` moves the slider to match
	if flag then
		watchGenv(flag, function(v) slider:SetValue(v) end, function() return isMouseDown end)
	end

	-- Touch taps report their position via InputBegan; player:GetMouse() stays
	-- stale (0,0) on touch-only Android, so a tap would jump the slider to min.
	-- A single InputBegan handles both Touch and MouseButton1 (no double-fire).
	sliderInstance.SliderBackground.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onMouseDown(input.Position.X)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			onMouseDown()
		end
	end)
	sliderInstance.TextGrouping.NumberText.FocusLost:Connect(onFocusLost)
	
	sliderInstance.TextGrouping.SliderText.Text = sliderName or "N/A"
	sliderInstance.TextGrouping.NumberText.Text = math.round(slider._currentValue)
	sliderInstance.TextGrouping.NumberText.Size = UDim2.new(0,math.max(requiredErrorTextSpace.X, requiredNumberTextSpace.X) + textPixelOffset,1,0)

	-- Restore bar position. Re-read the flag here too, so a global set AFTER the
	-- slider was created (e.g. getgenv().fovsize = 90 later in the script) still
	-- shows up immediately rather than waiting on the poll.
	task.defer(function()
		if flag and genv[flag] ~= nil then
			slider._currentValue = math.clamp(tonumber(genv[flag]) or slider._currentValue, minimumValue, maximumValue)
			sliderInstance.TextGrouping.NumberText.Text = math.round(slider._currentValue)
			if genvWatchers[flag] then genvWatchers[flag].last = genv[flag] end
		end
		if slider._currentValue ~= minimumValue then
			local pct = (slider._currentValue - minimumValue) / maxMinRange
			sliderBar.Size = UDim2.new(0, math.max(minimumClosePixelsLeft, math.round(pct * sliderBar.Parent.EmptySliderBackground.AbsoluteSize.X)), 1, 0)
		end
	end)
	
	sliderInstance.Parent = self.ElementToParentChildren
	sliderInstance.TextGrouping.SliderText.Size = UDim2.new(0, sliderInstance.TextGrouping.AbsoluteSize.X - textPixelOffset - requiredNumberTextSpace.X, 1, 0)

	return slider
end

function elementHandler:SearchBar(placeholderText: string): table
	local searchBar = setmetatable({}, searchBarHandler)
	local searchBarInstance = originalElements.SearchBar:Clone()
	local searchBox = searchBarInstance.SearchBarFrame.ButtonBackgroundPadding.SearchBox
	local elementHolder = searchBarInstance.ElementHolder
    local elementHolderBackground = elementHolder.ElementHolderBackground
	local elementHolderInnerBackground = elementHolderBackground.ElementHolderInnerBackground
	local elementHolderInnerBackgroundPaddings = elementHolder.ElementHolderPadding.PaddingBottom.Offset + elementHolder.ElementHolderPadding.PaddingTop.Offset + elementHolderBackground.ElementHolderBackgroundPadding.PaddingBottom.Offset + elementHolderBackground.ElementHolderBackgroundPadding.PaddingTop.Offset + elementHolderInnerBackground.ElementHolderInnerBackgroundPadding.PaddingBottom.Offset + elementHolderInnerBackground.ElementHolderInnerBackgroundPadding.PaddingTop.Offset
	local searchBarInstanceCloseTween = TweenService:Create(searchBarInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,searchBarInstance.SearchBarFrame.Size.Y.Offset)})
	local searchBarInstanceOpenTween
	local isMouseHoveringOver = false
	local mouseEnterConnection
	local mouseLeftConnection
	local uisFocusLost
	local playingAnimation
	local searchingText
	
	placeholderText = placeholderText or "N/A"

	local function onTextChanged()
		if searchBar.IsExpanded then
			if searchingText then coroutine.close(searchingText) end
			searchingText = coroutine.create(function()
				for _, foundElement in ipairs(elementHolderInnerBackground:GetChildren()) do
					local foundElementInfo = searchBar.ChildedElementsInfo[foundElement]
					if foundElementInfo ~= nil then
						if foundElementInfo.IdentifierText:lower():find(searchBox.Text:lower(), 1, true) then
							foundElement.Visible = true
						else
							foundElement.Visible = false
						end
					end
				end
				searchingText = nil
			end)
			coroutine.resume(searchingText)
		end
	end
	
	local function onFocused()
		elementHolderInnerBackground.Visible = true
		searchBar.IsExpanded = true
		onTextChanged()
		isMouseHoveringOver = true
		searchBarInstanceOpenTween:Play()
		
		if playingAnimation then
			coroutine.close(playingAnimation) 
			searchBox.PlaceholderText = placeholderText
			searchBox.Text = ""
		end
		
		mouseLeftConnection = searchBarInstance.MouseLeave:Connect(function()
			isMouseHoveringOver = false
			
			if not searchBox:IsFocused() then
				searchBar.IsExpanded = false
				searchBarInstanceCloseTween:Play()
				mouseLeftConnection:Disconnect()
				mouseEnterConnection:Disconnect()
				uisFocusLost:Disconnect()
				
				searchBarInstanceCloseTween.Completed:Connect(function(playbackState)
					if playbackState == Enum.PlaybackState.Completed then
						elementHolderInnerBackground.Visible = false
					end
				end)

				if playingAnimation then coroutine.close(playingAnimation) end
				playingAnimation = coroutine.create(function()
					searchBox.PlaceholderText = ""
					animateText(searchBox, .025, nil, placeholderText, true)
					playingAnimation = nil
				end)
				coroutine.resume(playingAnimation)
			end
		end)
		
		mouseEnterConnection = searchBarInstance.MouseEnter:Connect(function()
			isMouseHoveringOver = true
		end)
		
		uisFocusLost = UserInputService.TextBoxFocusReleased:Connect(function(textBoxReleased)
			if textBoxReleased == searchBox then
				if not isMouseHoveringOver then
					searchBar.IsExpanded = false
					searchBarInstanceCloseTween:Play()
					mouseLeftConnection:Disconnect()
					mouseEnterConnection:Disconnect()
					uisFocusLost:Disconnect()

					searchBarInstanceCloseTween.Completed:Connect(function(playbackState)
						if playbackState == Enum.PlaybackState.Completed then
							elementHolderInnerBackground.Visible = false
						end
					end)

					if playingAnimation then coroutine.close(playingAnimation) end
					playingAnimation = coroutine.create(function()
						searchBox.PlaceholderText = ""
						animateText(searchBox, .025, nil, placeholderText, true)
						playingAnimation = nil
					end)
					coroutine.resume(playingAnimation)
				end
			end
		end)
	end
	
	searchBar.Type = "SearchBar"
	searchBar.IdentifierText = placeholderText or "N/A"
	searchBar.Instance = searchBarInstance
	searchBar.GuiToRemove = searchBarInstance
	searchBar.ElementToParentChildren = elementHolderInnerBackground
	searchBar.ChildedElementsInfo = {}
	searchBar.IsExpanded = false
	
	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[searchBarInstance] = searchBar
	end
	
	searchBox:GetPropertyChangedSignal("Text"):Connect(onTextChanged)
	searchBox.Focused:Connect(onFocused)
	
	elementHolderInnerBackground.ElementHolderInnerBackgroundList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if searchBar.IsExpanded then
			if elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y == 0 then
				searchBarInstanceOpenTween = TweenService:Create(searchBarInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,searchBarInstance.SearchBarFrame.Size.Y.Offset)})
			else
				local elementHolderOpenTween = TweenService:Create(elementHolder, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings)})
				searchBarInstanceOpenTween = TweenService:Create(searchBarInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings + searchBarInstance.SearchBarFrame.Size.Y.Offset)})	
				elementHolderOpenTween:Play()		
			end
			
			searchBarInstanceOpenTween:Play()
		else
			elementHolder.Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings)
			if elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y == 0 then
				searchBarInstanceOpenTween = TweenService:Create(searchBarInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,searchBarInstance.SearchBarFrame.Size.Y.Offset)})
			else
				searchBarInstanceOpenTween = TweenService:Create(searchBarInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,elementHolderInnerBackground.ElementHolderInnerBackgroundList.AbsoluteContentSize.Y + elementHolderInnerBackgroundPaddings + searchBarInstance.SearchBarFrame.Size.Y.Offset)})
			end	
		end
	end)
	
	searchBox.PlaceholderText = placeholderText or "N/A"
	
	searchBarInstance.Parent = self.ElementToParentChildren
	searchBox.Size = UDim2.new(1,-(searchBox.Parent.SearchImage.AbsoluteSize.X + searchBox.Parent.ButtonBackgroundPadding.PaddingRight.Offset),1,0)
	searchBarInstanceOpenTween = TweenService:Create(searchBarInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,0,searchBarInstance.SearchBarFrame.Size.Y.Offset)})	
	
	return searchBar
end

-- Keybind element
function elementHandler:Keybind(keybindName: string, callback, defaultKey: string): table
	local keybind        = setmetatable({}, keybindHandler)
	local inst           = originalElements.Keybind:Clone()
	local tag            = inst.BoxBackground
	local keyLabel       = tag.KeyText
	local nameLabel      = inst.KeybindText
	local isListening    = false
	local currentBinding = nil   -- binding table { kind, ... }

	callback    = callback    or function() end
	keybindName = keybindName or "N/A"
	defaultKey  = defaultKey  or ""

	local function applyTagStyle(listening)
		if listening then
			keyLabel.Text        = "..."
			keyLabel.TextColor3  = Color3.fromRGB(255, 180, 50)
			tag.BackgroundColor3 = Color3.fromRGB(30, 25, 15)
			if tag:FindFirstChild("TagBorder") then tag.TagBorder.Color = Color3.fromRGB(255,180,50) end
		else
			keyLabel.TextColor3  = Theme.Accent
			tag.BackgroundColor3 = Color3.fromRGB(22, 23, 32)
			if tag:FindFirstChild("TagBorder") then tag.TagBorder.Color = Theme.Accent end
		end
	end

	local function setDisplay(dispName)
		keyLabel.Text = dispName or "—"
		applyTagStyle(false)
	end

	local listenConn
	local function beginListening()
		if isListening then return end
		isListening = true
		applyTagStyle(true)
		if listenConn then listenConn:Disconnect() end
		-- Listen on InputBegan for keyboard/mouse, and Changed for scroll
		listenConn = UserInputService.InputBegan:Connect(function(input, _gp)
			local dispName, binding = resolveBinding(input)
			if not binding then return end
			isListening    = false
			listenConn:Disconnect()
			listenConn     = nil
			currentBinding = binding
			setDisplay(dispName)
		end)
	end

	-- Fire callback when the bound input is detected
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if isListening then return end
		if bindingMatches(input, currentBinding) then callback() end
	end)

	inst.MouseButton1Click:Connect(beginListening)

	-- Set default key from name string (keyboard only for defaults)
	if defaultKey ~= "" then
		for _, kc in pairs(Enum.KeyCode:GetEnumItems()) do
			if kc.Name:lower() == defaultKey:lower() then
				currentBinding = { kind="Key", keyCode=kc }
				setDisplay(kc.Name)
				break
			end
		end
	end

	nameLabel.Text = keybindName
	if not currentBinding then setDisplay(nil) end

	inst.Parent = self.ElementToParentChildren
	if tag:FindFirstChild("BoxAspect") then tag.BoxAspect:Destroy() end
	nameLabel.Size = UDim2.new(1, -(tag.AbsoluteSize.X + 6), 1, 0)

	keybind.Type           = "Keybind"
	keybind.IdentifierText = keybindName
	keybind.Instance       = inst
	keybind.GuiToRemove    = inst
	return keybind
end

function elementHandler:TextBox(textBoxName:string, callback): table
	local textBox = setmetatable({}, textBoxHandler)
	local textBoxInstance = originalElements.TextBox:Clone()
	local placeholderText = "Type here..."
	local sidePlaceholderTextPadding = 2
	local textAnimation
	
	local boxBackground = textBoxInstance.BoxBackground
	local innerBox = boxBackground.InnerBox
	local textBoxText = innerBox.TextBoxText
	
	-- BSMT_MeasureText: GetTextBoundsAsync/FontFace don't exist on older clients
	local textBoxFace = BSMT_GetFontFace(textBoxText)
	local requiredPlaceholderTextSpace = BSMT_MeasureText(placeholderText, 14, textBoxFace, Enum.Font.Gotham, 10000)
	
	local function onInstanceClicked(): nil
		textBoxText:CaptureFocus()
	end
	
	local function onFocusLost(enterPressed: boolean): nil
		if enterPressed then callback(textBoxText.Text) end
		if textAnimation then coroutine.close(textAnimation) end
		textAnimation = coroutine.create(function()
			textBoxText.PlaceholderText = ""
			animateText(textBoxText, .025, _, placeholderText, true)
			textAnimation = nil
		end)
		coroutine.resume(textAnimation)
	end
	
	local function onFocused()
		if textAnimation then 
			coroutine.close(textAnimation) 
			textBoxText.PlaceholderText = placeholderText
			textBoxText.Text = ""
		end
	end
	
	local function onTextChanged()
		local boxBackgroundPaddingNeededSize = (sidePlaceholderTextPadding * 2) + boxBackground.BoxPadding.PaddingLeft.Offset + boxBackground.BoxPadding.PaddingRight.Offset + innerBox.BoxPadding.PaddingLeft.Offset + innerBox.BoxPadding.PaddingRight.Offset
		local requiredTextSize = BSMT_MeasureText(textBoxText.Text, 14, textBoxFace, Enum.Font.Gotham, 10000)
		local textChangedTween = TweenService:Create(boxBackground, TweenInfo.new(.1, Enum.EasingStyle.Linear), {Size = UDim2.new(0,math.clamp(boxBackgroundPaddingNeededSize + requiredTextSize.X, boxBackgroundPaddingNeededSize + requiredPlaceholderTextSpace.X, textBoxInstance.AbsoluteSize.X / 8 * 5),1,0)})
		textChangedTween:Play()	
	end
	
	textBoxName = textBoxName or "N/A"
	callback = callback or function() end
	
	textBox.Type = "TextBox"
	textBox.IdentifierText = textBoxName
	textBox.Instance = textBoxInstance
	textBox.GuiToRemove = textBoxInstance
	
	textBoxInstance.MouseButton1Click:Connect(onInstanceClicked)
	textBoxText.FocusLost:Connect(onFocusLost)
	textBoxText.Focused:Connect(onFocused)
	textBoxText:GetPropertyChangedSignal("Text"):Connect(onTextChanged)
	
	textBoxText.PlaceholderText = placeholderText
	textBoxInstance.TextBoxNameText.Text = textBoxName
	
	textBoxInstance.Parent = self.ElementToParentChildren
	-- Box is fixed at 52% width (set in template); name label takes the rest
	textBoxInstance.TextBoxNameText.Size = UDim2.new(0.45, -4, 1, 0)
	
	return textBox
end

--Fix toggle img it's imported as orange make it white
function elementHandler:ColorWheel(colorWheelName: string, callback, flag: string?): table
	local colorWheel = setmetatable({}, colorWheelHandler)
	local colorWheelInstance = originalElements.ColorWheel:Clone()
	local dragging = false  -- true while the user drags the wheel/value bar

	local heading = colorWheelInstance.Heading
	local wheelHolder = colorWheelInstance.WheelHolder
	local valueHolder =wheelHolder.ValueHolder
	local colorInputHolder = valueHolder.ColorInputHolder
	local wheel = wheelHolder.Wheel
	local selector = wheel.Selector
	local slider = valueHolder.ValueSlider
	local sliderBar = slider.SliderBar
	local sliderAbsSize
	local sliderAbsPos
	local wheelRadius
	
	local dropdownOpenTween = TweenService:Create(colorWheelInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 0, heading.AbsoluteSize.Y + wheelHolder.AbsoluteSize.Y + 4)})
	local dropdownCloseTween = TweenService:Create(colorWheelInstance, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 0, heading.AbsoluteSize.Y)})
	local dropdownImageOpenTween = TweenService:Create(heading.BoxBackground.InnerBox.CenterBox.DropdownImage, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Rotation = 0})
	local dropdownImageCloseTween = TweenService:Create(heading.BoxBackground.InnerBox.CenterBox.DropdownImage, TweenInfo.new(.25, Enum.EasingStyle.Linear), {Rotation = 180})
	
	-- BSMT_MeasureText: GetTextBoundsAsync/FontFace don't exist on older clients
	local requiredRgbTextSize = BSMT_MeasureText("255", 14, BSMT_GetFontFace(heading.ColorWheelName), Enum.Font.Gotham, 10000)
	
	local hue, saturation, value = 0, 0, 1
	
	local function updateVisuals()
		local color = Color3.fromHSV(hue, saturation, value)
		
		valueHolder.ColorSample.BackgroundColor3 = color
		colorInputHolder.Red.BoxBackground.InnerBox.ColorValue.Text = math.round(color.R * 255)
		colorInputHolder.Green.BoxBackground.InnerBox.ColorValue.Text = math.round(color.G * 255)
		colorInputHolder.Blue.BoxBackground.InnerBox.ColorValue.Text = math.round(color.B * 255)
		if colorWheel.Flag then genv[colorWheel.Flag] = color end
		_G.BSMTConfigData[colorWheel.ConfigIdentifier or colorWheelName] = {color.R * 255, color.G * 255, color.B * 255}
		callback(color)
	end

	-- Position the wheel selector + value bar from the current hue/sat/value
	local function setColorVisualPositions()
		if wheelRadius then
			local angle = math.rad(hue * 360 - 180)
			local rad   = saturation * wheelRadius
			selector.Position = UDim2.new(0.5, rad * math.cos(angle), 0.5, -rad * math.sin(angle))
		end
		local sAbs = slider.AbsoluteSize
		if sAbs.X > 0 then
			local x = math.clamp(value, 0, 1) * (sAbs.X - sliderBar.AbsoluteSize.X)
			sliderBar.Position = UDim2.new(0, x, 0, 0)
		end
	end

	-- Drive the whole control from a Color3 (used by init / SetColor / getgenv sync)
	local function setColorFromColor3(c3)
		hue, saturation, value = c3:ToHSV()
		setColorVisualPositions()
		updateVisuals()
	end
	
	-- Value bar from an absolute X coordinate (mouse or touch)
	local function applySliderFromX(px)
		local sliderAbsPos = slider.AbsolutePosition
		local sliderAbsSize = slider.AbsoluteSize

		if px - sliderAbsPos.X <= 0 then
			sliderBar.Position = UDim2.new(0,0,0,0)
		elseif px - sliderAbsPos.X >= sliderAbsSize.X - sliderBar.AbsoluteSize.X then
			sliderBar.Position = UDim2.new(1,-(sliderBar.AbsoluteSize.X),0,0)
		else
			sliderBar.Position = UDim2.new(0,px - sliderAbsPos.X,0,0)
		end

		local clampedPos = math.clamp(px - sliderAbsPos.X, 0, sliderAbsSize.X - sliderBar.AbsoluteSize.X)
		value = clampedPos / (sliderAbsSize.X - sliderBar.AbsoluteSize.X)

		updateVisuals()
	end

	-- Wheel hue/sat from an absolute X/Y coordinate (mouse or touch)
	local function applyRingFromXY(px, py)
		local relativeVector = Vector2.new(px, py) - wheel.AbsolutePosition - wheel.AbsoluteSize / 2
		local radius, angle = toPolar(relativeVector * Vector2.new(1,-1))

		if radius > wheelRadius then
			relativeVector = relativeVector.Unit * wheelRadius
			radius = wheelRadius
		end

		selector.Position = UDim2.new(.5, relativeVector.X, .5, relativeVector.Y)

		hue, saturation = (math.deg(angle) + 180) / 360 , radius / wheelRadius

		updateVisuals()
	end

	local function onDropdownClicked()
		if colorWheel.IsExpanded then
			colorWheel.IsExpanded = false
			dropdownCloseTween:Play()
			dropdownImageCloseTween:Play()
		else
			colorWheel.IsExpanded = true
			dropdownOpenTween:Play()
			dropdownImageOpenTween:Play()
		end
	end

	local function onSliderMouseDown(startX)
		dragging = true
		applySliderFromX(startX or mouse.X)

		local mouseMovedConnection = mouse.Move:Connect(function() applySliderFromX(mouse.X) end)
		local touchMovedConnection = UserInputService.TouchMoved:Connect(function(touch)
			applySliderFromX(touch.Position.X)
		end)

		local inputEndedConnection
		inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
				inputEndedConnection:Disconnect()
				mouseMovedConnection:Disconnect()
				touchMovedConnection:Disconnect()
			end
		end)
	end

	local function onWheelMouseDown(startX, startY)
		dragging = true
		applyRingFromXY(startX or mouse.X, startY or mouse.Y)

		local mouseMovedConnection = mouse.Move:Connect(function() applyRingFromXY(mouse.X, mouse.Y) end)
		local touchMovedConnection = UserInputService.TouchMoved:Connect(function(touch)
			applyRingFromXY(touch.Position.X, touch.Position.Y)
		end)

		local inputEndedConnection
		inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
				inputEndedConnection:Disconnect()
				mouseMovedConnection:Disconnect()
				touchMovedConnection:Disconnect()
			end
		end)
	end
	
	local function onColorInputTextChanged(textBox: TextBox): nil
		local colorValue = tonumber(textBox.Text)
		if textBox.Text:match("%D") or #textBox.Text > 3 then
			textBox.Text = textBox.Text:sub(1, #textBox.Text - 1)
		elseif colorValue and colorValue > 255 then
			textBox.Text = 255
		end
	end
	
	local function onColorInputTextLostFocus(textBox: TextBox, textBoxColorAssociated): nil
		local currentColor = Color3.fromHSV(hue, saturation, value)
		local tagByName = { Red = "R", Green = "G", Blue = "B" }
		local tag = tagByName[textBoxColorAssociated]
		local n = tonumber(textBox.Text)

		-- Empty or non-numeric: snap the box back to the current channel value
		if #textBox.Text == 0 or not n then
			textBox.Text = math.round(currentColor[tag] * 255)
			return
		end

		n = math.clamp(n, 0, 255)
		local r, g, b = currentColor.R * 255, currentColor.G * 255, currentColor.B * 255
		if tag == "R" then r = n elseif tag == "G" then g = n else b = n end

		setColorFromColor3(Color3.fromRGB(r, g, b))
	end
	
	colorWheelName = colorWheelName or "N/A"
	callback = callback or function() end
	
	colorWheel.Type = "ColorWheel"
	colorWheel.IdentifierText = colorWheelName
	colorWheel.IsExpanded = false
	colorWheel.Instance = colorWheelInstance
	colorWheel.GuiToRemove = colorWheelInstance

	-- Config / getgenv binding. `flag` (3rd arg) names a getgenv() key to mirror.
	colorWheel.Flag = flag
	colorWheel.ConfigIdentifier = flag or colorWheelName
	_G.BSMTConfigElements[colorWheel.ConfigIdentifier] = colorWheel

	-- Programmatic setter (also used by config load / getgenv sync)
	function colorWheel:SetColor(c3)
		if typeof(c3) == "Color3" then setColorFromColor3(c3) end
	end

	if self.Type == "SearchBar" then
		self.ChildedElementsInfo[colorWheelInstance] = colorWheel
	end

	heading.MouseButton1Click:Connect(onDropdownClicked)
	-- Touch-aware drag start (mouse.X/mouse.Y are stale on touch-only Android).
	-- A single InputBegan handles both Touch and MouseButton1 (no double-fire).
	slider.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onSliderMouseDown(input.Position.X)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			onSliderMouseDown()
		end
	end)
	wheel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onWheelMouseDown(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			onWheelMouseDown()
		end
	end)
	
	heading.ColorWheelName.Text = colorWheelName
	
	colorWheelInstance.Parent = self.ElementToParentChildren
	heading.ColorWheelName.Size = UDim2.new(1, -(heading.BoxBackground.AbsoluteSize.X + 4),1,0)
	valueHolder.Size = UDim2.new(.9,-(wheel.AbsoluteSize.X + 4),1,0)
	sliderBar.Position = UDim2.new(1,-sliderBar.AbsoluteSize.X,0,0)
	
	for _, rgbFrame in ipairs(valueHolder.ColorInputHolder:GetChildren()) do
		if rgbFrame:IsA("Frame") then
			local requiredBoxBackgroundXSize = rgbFrame.BoxBackground.BoxPadding.PaddingLeft.Offset + rgbFrame.BoxBackground.BoxPadding.PaddingRight.Offset + rgbFrame.BoxBackground.InnerBox.BoxPadding.PaddingLeft.Offset + rgbFrame.BoxBackground.InnerBox.BoxPadding.PaddingRight.Offset + requiredRgbTextSize.X + 4
			rgbFrame.BoxBackground.Size = UDim2.new(0,requiredBoxBackgroundXSize,1,0)	
			rgbFrame.ColorText.Size = UDim2.new(1,-(requiredBoxBackgroundXSize + 2),1,0)
			rgbFrame.BoxBackground.InnerBox.ColorValue:GetPropertyChangedSignal("Text"):Connect(function() onColorInputTextChanged(rgbFrame.BoxBackground.InnerBox.ColorValue) end)	
			rgbFrame.BoxBackground.InnerBox.ColorValue.FocusLost:Connect(function() onColorInputTextLostFocus(rgbFrame.BoxBackground.InnerBox.ColorValue, rgbFrame.Name) end)	
		end
	end
	
	wheelRadius = wheel.AbsoluteSize.X / 2

	-- Resolve the starting colour: getgenv flag > saved config, applied once layout is ready
	task.defer(function()
		wheelRadius = wheel.AbsoluteSize.X / 2
		local startColor
		if flag and typeof(genv[flag]) == "Color3" then
			startColor = genv[flag]
		else
			local saved = _G.BSMTConfigData[colorWheel.ConfigIdentifier]
			if type(saved) == "table" and #saved == 3 then
				startColor = Color3.fromRGB(saved[1], saved[2], saved[3])
			end
		end
		if startColor then setColorFromColor3(startColor) end
	end)

	-- Live-sync: external `getgenv()[flag] = Color3` updates the wheel
	if flag then
		watchGenv(flag, function(v)
			if typeof(v) == "Color3" then setColorFromColor3(v) end
		end, function() return dragging end)
	end

	return colorWheel
end

createOriginialElements()

local notificationHandler = {}
notificationHandler.__index = notificationHandler

local notificationContainer
local activeNotifications = {}

local function createNotificationContainer()
	if notificationContainer then return notificationContainer end
	local container = Instance.new("ScreenGui")
	container.Name = "BSMTNotifications"
	container.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	container.IgnoreGuiInset = true
	container.DisplayOrder = 998
	parentProtected(container)
	return container
end

local function createNotification()
	-- Root: off-screen frame, auto-height
	local root         = Instance.new("Frame")
	local pill         = Instance.new("Frame")
	local pillCorner   = Instance.new("UICorner")
	local pillStroke   = Instance.new("UIStroke")
	local accentBar    = Instance.new("Frame")
	local accentCorner = Instance.new("UICorner")
	local icon         = Instance.new("ImageLabel")
	local closeBtn     = Instance.new("TextButton")
	local titleLbl     = Instance.new("TextLabel")
	local bodyLbl      = Instance.new("TextLabel")
	local bodyPad      = Instance.new("UIPadding")
	local progressBar  = Instance.new("Frame")
	local progressFill = Instance.new("Frame")
	local progressCorner = Instance.new("UICorner")
	-- Layout inside pill
	local pillList     = Instance.new("UIListLayout")
	local topRow       = Instance.new("Frame")

	-- Root wrapper (transparent, used for tweening position)
	root.Name = "Notification"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.new(0, 300, 0, 68)
	root.Position = UDim2.new(1, 320, 0, 10)
	root.ClipsDescendants = false

	-- Dark pill
	pill.Name = "Background"
	pill.Parent = root
	pill.BackgroundColor3 = Color3.fromRGB(17, 17, 22)
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, 0, 1, 0)
	pill.ClipsDescendants = false

	pillCorner.CornerRadius = UDim.new(0, 8)
	pillCorner.Parent = pill

	pillStroke.Color = Color3.fromRGB(45, 45, 60)
	pillStroke.Thickness = 1
	BSMT_ApplyBorderStroke(pillStroke)
	pillStroke.Parent = pill

	-- Left colour accent stripe
	accentBar.Name = "AccentBar"
	accentBar.Parent = pill
	accentBar.AnchorPoint = Vector2.new(0, 0.5)
	accentBar.Position = UDim2.new(0, 0, 0.5, 0)
	accentBar.Size = UDim2.new(0, 4, 0.72, 0)
	accentBar.BackgroundColor3 = Theme.Accent
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 3

	accentCorner.CornerRadius = UDim.new(0, 8)
	accentCorner.Parent = accentBar

	-- Icon
	icon.Name = "Icon"
	icon.Parent = pill
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.new(0, 14, 0.38, 0)
	icon.Size = UDim2.new(0, 16, 0, 16)
	icon.ImageColor3 = Theme.Accent
	icon.ZIndex = 2

	-- Close button (top-right X)
	closeBtn.Name = "CloseBtn"
	closeBtn.Parent = pill
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Position = UDim2.new(1, -6, 0, 4)
	closeBtn.Size = UDim2.new(0, 18, 0, 18)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "×"
	closeBtn.TextColor3 = Color3.fromRGB(90, 90, 105)
	closeBtn.TextSize = 16
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 4

	-- Title (bold, first line)
	titleLbl.Name = "TitleLabel"
	titleLbl.Parent = pill
	titleLbl.BackgroundTransparency = 1
	titleLbl.AnchorPoint = Vector2.new(0, 0)
	titleLbl.Position = UDim2.new(0, 36, 0, 10)
	titleLbl.Size = UDim2.new(1, -60, 0, 16)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Text = "Info"
	titleLbl.TextColor3 = Color3.fromRGB(230, 230, 238)
	titleLbl.TextSize = 13
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.ZIndex = 2

	-- Body text (below title)
	bodyLbl.Name = "TextLabel"
	bodyLbl.Parent = pill
	bodyLbl.BackgroundTransparency = 1
	bodyLbl.AnchorPoint = Vector2.new(0, 0)
	bodyLbl.Position = UDim2.new(0, 36, 0, 30)
	bodyLbl.Size = UDim2.new(1, -44, 0, 26)
	bodyLbl.Font = Enum.Font.Gotham
	bodyLbl.Text = "Notification"
	bodyLbl.TextColor3 = Color3.fromRGB(155, 155, 168)
	bodyLbl.TextSize = 12
	bodyLbl.TextWrapped = true
	bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
	bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
	bodyLbl.ZIndex = 2

	bodyPad.PaddingRight = UDim.new(0, 8)
	bodyPad.Parent = bodyLbl

	-- Progress bar at bottom
	progressBar.Name = "ProgressBar"
	progressBar.Parent = pill
	progressBar.AnchorPoint = Vector2.new(0, 1)
	progressBar.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	progressBar.BorderSizePixel = 0
	progressBar.Position = UDim2.new(0, 0, 1, 0)
	progressBar.Size = UDim2.new(1, 0, 0, 3)
	progressBar.ZIndex = 2

	progressFill.Name = "ProgressBarInner"
	progressFill.Parent = progressBar
	progressFill.BackgroundColor3 = Theme.Accent
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(1, 0, 1, 0)
	progressFill.ZIndex = 3

	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progressFill

	-- Compat stubs
	local innerBg = Instance.new("Frame")
	innerBg.Name = "InnerBackground"
	innerBg.BackgroundTransparency = 1
	innerBg.Size = UDim2.new(0,0,0,0)
	innerBg.Parent = pill
	local ch = Instance.new("Frame")
	ch.Name = "ContentHolder"
	ch.BackgroundTransparency = 1
	ch.Size = UDim2.new(0,0,0,0)
	ch.Parent = innerBg

	return root
end

local function updateNotificationPositions()
	local topMargin = 10
	local gap = 8
	local currentY = topMargin
	for i = 1, #activeNotifications do
		local notif = activeNotifications[i]
		if notif and notif.Instance and notif.Instance.Parent then
			TweenService:Create(notif.Instance,
				TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{Position = UDim2.new(1, -310, 0, currentY)}):Play()
			currentY = currentY + notif.Instance.AbsoluteSize.Y + gap
		end
	end
end

function Library.Notification(message, notifType, duration)
	local notification = setmetatable({}, notificationHandler)

	if not notificationContainer then
		notificationContainer = createNotificationContainer()
	end

	local inst = createNotification()
	local pill = inst.Background

	message   = message   or "Notification"
	notifType = notifType or "info"
	duration  = duration  or 4

	local typeConfigs = {
		success = {
			title = "Success",
			icon  = "rbxassetid://11295279671",
			color = Color3.fromRGB(60, 200, 110)
		},
		error = {
			title = "Error",
			icon  = "rbxassetid://11295280827",
			color = Color3.fromRGB(220, 65, 55)
		},
		warning = {
			title = "Warning",
			icon  = "rbxassetid://11295279671",
			color = Color3.fromRGB(230, 175, 45)
		},
		info = {
			title = "Info",
			icon  = "rbxassetid://11454041890",
			color = Theme.Accent
		},
	}
	local cfg = typeConfigs[notifType:lower()] or typeConfigs.info

	-- Apply colours and content
	pill.AccentBar.BackgroundColor3               = cfg.color
	pill.Icon.Image                               = cfg.icon
	pill.Icon.ImageColor3                         = cfg.color
	pill.TitleLabel.Text                          = cfg.title
	pill.TitleLabel.TextColor3                    = cfg.color
	pill.TextLabel.Text                           = message
	pill.ProgressBar.ProgressBarInner.BackgroundColor3 = cfg.color

	-- Close button wires up after we create the notification object
	notification.Instance = inst
	notification.Duration = duration
	notification.Type     = notifType

	inst.Parent = notificationContainer
	table.insert(activeNotifications, notification)

	-- Hover: brighten close button
	pill.CloseBtn.MouseEnter:Connect(function()
		pill.CloseBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
	end)
	pill.CloseBtn.MouseLeave:Connect(function()
		pill.CloseBtn.TextColor3 = Color3.fromRGB(90, 90, 105)
	end)
	pill.CloseBtn.MouseButton1Click:Connect(function()
		notification:Dismiss()
	end)

	-- Slide in from right
	TweenService:Create(inst,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.new(1, -310, 0, 10)}):Play()

	updateNotificationPositions()

	-- Progress bar drains over duration
	local fill = pill.ProgressBar.ProgressBarInner
	local progressTween = TweenService:Create(fill,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{Size = UDim2.new(0, 0, 1, 0)})
	task.delay(0.4, function()
		if fill and fill.Parent then progressTween:Play() end
	end)

	task.delay(duration, function()
		notification:Dismiss()
	end)

	return notification
end

function notificationHandler:Dismiss()
	if not self.Instance or not self.Instance.Parent then return end
	-- Slide out right
	TweenService:Create(self.Instance,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{Position = UDim2.new(1, 320, 0, self.Instance.Position.Y.Offset)}):Play()
	task.delay(0.32, function()
		for i, n in ipairs(activeNotifications) do
			if n == self then
				table.remove(activeNotifications, i)
				break
			end
		end
		if self.Instance then self.Instance:Destroy() end
		updateNotificationPositions()
	end)
end


-- Store config state in the executor-isolated global env (getgenv) when available,
-- and mirror the SAME table references onto _G so existing _G.BSMT* reads keep working.
-- (`genv` is defined once near the top of the file.)
genv.BSMTConfigData = genv.BSMTConfigData or {}
genv.BSMTConfigElements = genv.BSMTConfigElements or {}
_G.BSMTConfigData = genv.BSMTConfigData
_G.BSMTConfigElements = genv.BSMTConfigElements

local currentGameId = tostring(game.PlaceId)
local configFolder = "BSMT_Configs"
local gameConfigFolder = configFolder .. "/" .. currentGameId

if isfolder and not isfolder(configFolder) then
    makefolder(configFolder)
end

if isfolder and not isfolder(gameConfigFolder) then
    makefolder(gameConfigFolder)
end

function Library.SaveConfig(configName)
    if not writefile then
        if Library.Notification then
            Library.Notification("Executor doesn't support file saving", "error", 4)
        end
        return false
    end
    
    configName = configName or "default"
    local configPath = gameConfigFolder .. "/" .. configName .. ".cfg"
    
    local success, err = pcall(function()
        writefile(configPath, game:GetService("HttpService"):JSONEncode(_G.BSMTConfigData))
    end)
    
    if success then
        if Library.Notification then
            Library.Notification("Config '" .. configName .. "' saved!", "success", 3)
        end
        return true
    else
        if Library.Notification then
            Library.Notification("Failed to save: " .. tostring(err), "error", 4)
        end
        return false
    end
end

function Library.LoadConfig(configName)
    if not readfile or not isfile then
        if Library.Notification then
            Library.Notification("Executor doesn't support file reading", "error", 4)
        end
        return false
    end
    
    configName = configName or "default"
    local configPath = gameConfigFolder .. "/" .. configName .. ".cfg"
    
    if not isfile(configPath) then
        if Library.Notification then
            Library.Notification("Config '" .. configName .. "' not found", "warning", 3)
        end
        return false
    end
    
    local success, result = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(configPath))
    end)
    
    if success and result then
        for identifier, value in pairs(result) do
            _G.BSMTConfigData[identifier] = value
        end
        
        for identifier, element in pairs(_G.BSMTConfigElements) do
            if result[identifier] ~= nil then
                if element.Type == "Toggle" then
                    element:Apply(result[identifier], true)
                elseif element.Type == "Slider" then
                    element:SetValue(result[identifier])
                elseif element.Type == "ToggleKeybind" then
                    -- Re-bind from saved encoded binding string
                    local saved = result[identifier]
                    if saved and saved ~= "" then
                        local dispName, binding = decodeBinding(saved)
                        if binding then
                            element.toggle:BindKeyCode(binding)
                            if element.instance and dispName then
                                element.instance.Text = dispName
                            end
                        else
                            -- Legacy: plain key name (e.g. "RightShift")
                            for _, kc in pairs(Enum.KeyCode:GetEnumItems()) do
                                if kc.Name == saved then
                                    element.toggle:BindKeyCode({ kind="Key", keyCode=kc })
                                    if element.instance then element.instance.Text = kc.Name end
                                    break
                                end
                            end
                        end
                    end
                elseif element.Type == "ColorWheel" then
                    local c = result[identifier]
                    if type(c) == "table" and #c == 3 and element.SetColor then
                        element:SetColor(Color3.fromRGB(c[1], c[2], c[3]))
                    end
                elseif element.Type == "WatermarkToggle" then
                    element:Apply(nil, result[identifier])
                end
            end
        end
        
        if Library.Notification then
            Library.Notification("Config '" .. configName .. "' loaded!", "success", 3)
        end
        return true
    else
        if Library.Notification then
            Library.Notification("Failed to load config", "error", 4)
        end
        return false
    end
end

function Library.DeleteConfig(configName)
    if not delfile or not isfile then
        if Library.Notification then
            Library.Notification("Executor doesn't support file deletion", "error", 4)
        end
        return false
    end
    
    local configPath = gameConfigFolder .. "/" .. configName .. ".cfg"
    
    if not isfile(configPath) then
        if Library.Notification then
            Library.Notification("Config '" .. configName .. "' not found", "warning", 3)
        end
        return false
    end
    
    local success = pcall(function()
        delfile(configPath)
    end)
    
    if success then
        if Library.Notification then
            Library.Notification("Config '" .. configName .. "' deleted", "info", 3)
        end
        return true
    else
        if Library.Notification then
            Library.Notification("Failed to delete config", "error", 4)
        end
        return false
    end
end

function Library.GetConfigs()
    if not listfiles or not isfolder then return {} end
    if not isfolder(gameConfigFolder) then return {} end
    
    local configs = {}
    local success, files = pcall(function()
        return listfiles(gameConfigFolder)
    end)
    
    if success and files then
        for _, filePath in ipairs(files) do
            local fileName = filePath:match("([^/\\]+)%.cfg$")
            if fileName then
                table.insert(configs, fileName)
            end
        end
    end
    
    return configs
end

function Library.SetAutoLoad(configName)
    if not writefile then return false end
    local autoLoadPath = gameConfigFolder .. "/_autoload.txt"
    local success = pcall(function()
        writefile(autoLoadPath, configName or "")
    end)
    return success
end

function Library.GetAutoLoad()
    if not readfile or not isfile then return nil end
    local autoLoadPath = gameConfigFolder .. "/_autoload.txt"
    if isfile(autoLoadPath) then
        local success, result = pcall(function()
            return readfile(autoLoadPath)
        end)
        if success and result and result ~= "" then
            return result
        end
    end
    return nil
end

function toggleHandler:Apply(value, runCallback)
    self.Enabled = value

    local t       = 0.18
    local inst    = self.Instance
    local inner   = inst.BoxBackground.InnerBox
    local center  = inner.CenterBox
    local img     = center.ToggleImage
    local imgCorner = img.ToggleImageCorner

    if self.Enabled then
        -- Fill inner box with accent red, show checkmark
        TweenService:Create(inner,  TweenInfo.new(t, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Accent}):Play()
        TweenService:Create(center, TweenInfo.new(t, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Accent}):Play()
        TweenService:Create(img,    TweenInfo.new(t, Enum.EasingStyle.Quad), {Size = UDim2FromScale(1, 1), BackgroundColor3 = Theme.Accent}):Play()
        TweenService:Create(imgCorner, TweenInfo.new(t), {CornerRadius = UDim.new(0, 2)}):Play()
        inst.BoxBackground.BackgroundColor3 = Theme.Accent
    else
        -- Reset to dark
        TweenService:Create(inner,  TweenInfo.new(t, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Panel}):Play()
        TweenService:Create(center, TweenInfo.new(t, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Panel}):Play()
        TweenService:Create(img,    TweenInfo.new(t, Enum.EasingStyle.Quad), {Size = UDim2FromScale(0, 0), BackgroundColor3 = Theme.Panel}):Play()
        inst.BoxBackground.BackgroundColor3 = Theme.ToggleOff
    end

    if runCallback and self.Callback then
        self.Callback(self.Enabled)
    end

    if self.ConfigIdentifier then
        _G.BSMTConfigData[self.ConfigIdentifier] = self.Enabled
    end
end

function elementHandler:Toggle(toggleName, callback, configIdentifier)
    local toggle = setmetatable({}, toggleHandler)
    local toggleInstance = originalElements.Toggle:Clone()
    local textOffset = 4
    
    toggle.ConfigIdentifier = configIdentifier or toggleName
    toggle.Type = "Toggle"
    toggle.IdentifierText = toggleName or "N/A"
    toggle.Instance = toggleInstance
    toggle.GuiToRemove = toggleInstance
    toggle.Enabled = false
    toggle.Callback = callback or function() end
    
    _G.BSMTConfigElements[toggle.ConfigIdentifier] = toggle
    
    if _G.BSMTConfigData[toggle.ConfigIdentifier] ~= nil then
        toggle.Enabled = _G.BSMTConfigData[toggle.ConfigIdentifier]
    end
    
    if self.Type == "SearchBar" then
        self.ChildedElementsInfo[toggleInstance] = toggle
    end
    
    toggleInstance.MouseButton1Click:Connect(function()
        toggle:Apply(not toggle.Enabled, true)
    end)
    
    toggleInstance.ToggleText.Text = toggleName or "N/A"
    -- Fix text offset to match new template (box is square = ToggleH px wide)
    toggleInstance.ToggleText.Position = UDim2.new(0, M.ToggleH + 6, 0, 0)
    toggleInstance.ToggleText.Size     = UDim2.new(1, -(M.ToggleH + 6), 1, 0)
    toggleInstance.Parent = self.ElementToParentChildren

    -- Lock box to a square the same height as the row
    local boxSize = toggleInstance.AbsoluteSize.Y
    if boxSize > 0 then
        toggleInstance.BoxBackground.Size = UDim2FromOffset(boxSize, boxSize)
    end
    if toggleInstance.BoxBackground:FindFirstChild("BoxAspect") then
        toggleInstance.BoxBackground.BoxAspect:Destroy()
    end

    if toggle.Enabled then
        local inner  = toggleInstance.BoxBackground.InnerBox
        local center = inner.CenterBox
        local img    = center.ToggleImage
        inner.BackgroundColor3  = Theme.Accent
        center.BackgroundColor3 = Theme.Accent
        img.BackgroundColor3    = Theme.Accent
        img.Size                = UDim2FromScale(1, 1)
        img.ToggleImageCorner.CornerRadius = UDim.new(0, 2)
        toggleInstance.BoxBackground.BackgroundColor3 = Theme.Accent
    end
    
    return toggle
end

function toggleHandler:Set(bool, callback)
    if typeof(bool) ~= "boolean" then error("First argument must be a boolean.") end
    self:Apply(bool, callback ~= nil)
    if callback then
        callback(bool)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- toggleHandler:BindKeyCode(keyCode)   [internal]
--   Attaches a low-level UIS listener. When the key is pressed it calls
--   self:Apply(not self.Enabled, true) which updates visuals AND fires Callback.
-- ─────────────────────────────────────────────────────────────────────────────
function toggleHandler:BindKeyCode(bindingOrKeyCode)
    -- Disconnect any previous listener
    if self._keyConnection then
        self._keyConnection:Disconnect()
        self._keyConnection = nil
    end
    if not bindingOrKeyCode then
        self._boundBinding = nil
        return
    end

    -- Accept either a binding table {kind,…} or a raw Enum.KeyCode (backwards compat)
    local binding
    if typeof(bindingOrKeyCode) == "EnumItem" then
        binding = { kind="Key", keyCode=bindingOrKeyCode }
    else
        binding = bindingOrKeyCode
    end
    self._boundBinding = binding

    local cb = self.Callback
    self._keyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if not bindingMatches(input, self._boundBinding) then return end

        self.Enabled = not self.Enabled
        self:Apply(self.Enabled, false)  -- reuse Apply visuals

        if self.ConfigIdentifier then
            _G.BSMTConfigData[self.ConfigIdentifier] = self.Enabled
        end
        if cb then cb(self.Enabled) end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- toggleHandler:BindKey(arg, defaultKeyName?)
--
--   MODE 1 – no arg / nil
--     Adds a clickable keybind UI row with no default key set.
--     myToggle:BindKey()
--
--   MODE 2 – arg is a KeyCode name  (e.g. "RightShift", "X", "F")
--     Silently binds that key with NO UI row.
--     myToggle:BindKey("RightShift")
--
--   MODE 3 – arg is a plain label string (e.g. "Set a Keybind")
--     Adds a clickable keybind UI row with that label.
--     Optional 2nd arg sets a default key shown in the box on first load.
--     myToggle:BindKey("Set a Keybind")
--     myToggle:BindKey("Set a Keybind", "RightShift")
--
--   Right-click any keybind row to clear it.
--   Keybinds are stored in _G.BSMTConfigData and saved when you call SaveConfig.
-- ─────────────────────────────────────────────────────────────────────────────
function toggleHandler:BindKey(arg, defaultKeyName)
    -- Clear any previous binding
    self:BindKeyCode(nil)

    local function getKeyCode(name)
        if not name then return nil end
        for _, kc in pairs(Enum.KeyCode:GetEnumItems()) do
            if kc.Name:lower() == name:lower() then return kc end
        end
        return nil
    end

    -- ── MODE 2: arg is a known key name → bind silently, no UI ───────────────
    if arg ~= nil then
        local directCode = getKeyCode(arg)
        if directCode then
            self:BindKeyCode({ kind="Key", keyCode=directCode })
            return
        end
    end

    -- ── MODES 1 & 3: create a keybind UI row ─────────────────────────────────
    local label      = (arg ~= nil and tostring(arg) ~= "") and tostring(arg) or "Keybind"
    local configKey  = (self.ConfigIdentifier or self.IdentifierText or "toggle") .. "_keybind"
    local parent     = self.Instance and self.Instance.Parent

    if not parent then
        warn("BSMT BindKey: call BindKey AFTER adding the toggle to a section.")
        return
    end

    -- Build the UI row (same template as the standalone Keybind element)
    local keybindRow     = originalElements.Keybind:Clone()
    local keyText        = keybindRow.BoxBackground.KeyText
    local boxBackground  = keybindRow.BoxBackground
    local keybindTextLbl = keybindRow.KeybindText

    keybindTextLbl.Text = label
    keybindTextLbl.Size = UDim2.new(0, 0, 1, 0)  -- hide before parenting so no text bleeds through
    keyText.Text        = "None"

    keybindRow.Parent = parent
    local boxSize = boxBackground.AbsoluteSize
    boxBackground.BoxAspect:Destroy()
    boxBackground.Size  = UDim2FromOffset(boxSize.X, boxSize.Y)
    keybindTextLbl.Size = UDim2.new(1, -(boxSize.X + 4), 1, 0)  -- restore correct size

    -- Restore from saved config (takes priority over defaultKeyName)
    local savedKeyName = _G.BSMTConfigData[configKey]
    local startKey     = (savedKeyName and savedKeyName ~= "") and savedKeyName or defaultKeyName

    if startKey then
        local startCode = getKeyCode(startKey)
        if startCode then
            keyText.Text = startKey
            self:BindKeyCode({ kind="Key", keyCode=startCode })
        end
    end

    -- Register so LoadConfig can restore the keybind row's display text
    _G.BSMTConfigElements[configKey] = {
        Type     = "ToggleKeybind",
        toggle   = self,
        instance = keyText,
    }

    -- Click → listen for next keyboard / mouse / scroll input
    local isListening = false
    local listenConn  = nil

    local function startListening()
        if isListening then return end
        isListening  = true
        keyText.Text = "..."
        if listenConn then listenConn:Disconnect() end
        listenConn = UserInputService.InputBegan:Connect(function(input, _gpe)
            local dispName, binding = resolveBinding(input)
            if not binding then return end
            isListening = false
            listenConn:Disconnect()
            listenConn  = nil
            keyText.Text = dispName
            self:BindKeyCode(binding)
            _G.BSMTConfigData[configKey] = encodeBinding(binding)
            Library.Notification(label .. " → " .. dispName, "success", 2)
        end)
    end

    keybindRow.MouseButton1Click:Connect(startListening)

    -- Right-click → clear binding
    keybindRow.MouseButton2Click:Connect(function()
        if listenConn then listenConn:Disconnect() listenConn = nil end
        isListening  = false
        keyText.Text = "None"
        self:BindKeyCode(nil)
        _G.BSMTConfigData[configKey] = ""
        Library.Notification(label .. " cleared", "info", 2)
    end)

    self._keybindRow = keybindRow
end

function windowHandler:SetKeybind(keybind)
    local function getMatchingKeyCodeFromName(name)
        if not name then return end
        for _, keycode in pairs(Enum.KeyCode:GetEnumItems()) do
            if keycode.Name:lower() == name:lower() then
                return keycode
            end
        end
    end
    -- Just update CurrentKeybind. The permanent listener in Library.new reads it live.
    self.CurrentKeybind = getMatchingKeyCodeFromName(keybind) or Enum.KeyCode.RightShift
end

-- Config Tab
function windowHandler:ConfigTab()
    local configTab = self:Tab("Config", "rbxassetid://11295279671")
    local configSection = configTab:Section("Configuration Manager")

    local currentConfigName = "MyConfig"
    local refreshConfigs, refreshAutoLoadDropdown  -- forward declarations (kept local, not global)
    
    configSection:TextBox("Config Name", function(text)
        if text and text ~= "" then
            currentConfigName = text
            Library.Notification("Config name set to: " .. text, "info", 2)
        end
    end)
    
    configSection:Title("Actions")
    
    configSection:Button("Save Config", function()
        if currentConfigName and currentConfigName ~= "" then
            local success = Library.SaveConfig(currentConfigName)
            if success then
                task.wait(0.5)
                refreshConfigs()
                refreshAutoLoadDropdown()
            end
        else
            Library.Notification("Please enter a config name", "warning", 3)
        end
    end)
    
    configSection:Button("Load Config", function()
        if currentConfigName and currentConfigName ~= "" then
            Library.LoadConfig(currentConfigName)
        else
            Library.Notification("Please enter a config name", "warning", 3)
        end
    end)
    
    configSection:Button("Delete Config", function()
        if currentConfigName and currentConfigName ~= "" then
            local success = Library.DeleteConfig(currentConfigName)
            if success then
                task.wait(0.5)
                refreshConfigs()
                refreshAutoLoadDropdown()
            end
        else
            Library.Notification("Please enter a config name", "warning", 3)
        end
    end)
    
    configSection:Title("Saved Configs")
    
    local configList = configSection:Dropdown("Available Configs")
    
    refreshConfigs = function()
        for _, child in ipairs(configList.ElementToParentChildren:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        
        local configs = Library.GetConfigs()
        for _, config in ipairs(configs) do
            configList:Button(config, function()
                currentConfigName = config
                configList:ChangeText(config)
                Library.Notification("Selected: " .. config, "info", 2)
            end)
        end
        
        if #configs == 0 then
            configList:Label("No configs found")
        end
    end
    
    refreshConfigs()
    
    configSection:Button("Refresh List", function()
        refreshConfigs()
    end)
    
    configSection:Title("Auto-Load")
    
    local selectedAutoLoadConfig = Library.GetAutoLoad() or ""
    local autoLoadEnabled = (selectedAutoLoadConfig ~= "")
    
    local autoLoadToggle = configSection:Toggle("Enable Auto-Load", function(enabled)
        if enabled then
            if selectedAutoLoadConfig and selectedAutoLoadConfig ~= "" then
                Library.SetAutoLoad(selectedAutoLoadConfig)
                Library.Notification("Auto-load enabled: " .. selectedAutoLoadConfig, "success", 3)
            else
                Library.Notification("Select a config first", "warning", 3)
                autoLoadToggle:Set(false)
            end
        else
            Library.SetAutoLoad("")
            Library.Notification("Auto-load disabled", "info", 2)
        end
    end, "autoload_enabled")
    
    autoLoadToggle:Set(autoLoadEnabled)
    
    local autoLoadDropdown = configSection:Dropdown("Select Config to Auto-Load")
    
    refreshAutoLoadDropdown = function()
        for _, child in ipairs(autoLoadDropdown.ElementToParentChildren:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        
        local currentAutoLoad = Library.GetAutoLoad()
        
        local configs = Library.GetConfigs()
        for _, config in ipairs(configs) do
            local isActive = (currentAutoLoad == config)
            local buttonText = isActive and (config .. " [Active]") or config
            
            autoLoadDropdown:Button(buttonText, function()
                selectedAutoLoadConfig = config
                autoLoadDropdown:ChangeText(config)
                
                if autoLoadToggle.Enabled then
                    Library.SetAutoLoad(config)
                    Library.Notification("Auto-load config changed to: " .. config, "success", 3)
                else
                    Library.Notification("Config selected: " .. config, "info", 3)
                end
                
                refreshAutoLoadDropdown()
            end)
        end
        
        if #configs == 0 then
            autoLoadDropdown:Label("No configs available")
        end
        
        if selectedAutoLoadConfig and selectedAutoLoadConfig ~= "" then
            autoLoadDropdown:ChangeText(selectedAutoLoadConfig)
        else
            autoLoadDropdown:ChangeText("Select a config")
        end
    end
    
    refreshAutoLoadDropdown()
    
    configSection:Title("UI Settings")

    -- Watermark toggle (on by default, saved to config)
    local wmToggle = configSection:Toggle("Show Watermark", function(enabled)
        if Library.Watermark then
            Library.Watermark.SetVisible(enabled)
        end
    end, "watermark_enabled")
    -- Set initial visual state from config data
    local wmInitial = _G.BSMTConfigData["watermark_enabled"]
    wmToggle:Set(wmInitial == nil and true or wmInitial)

    configSection:Label("UI Visibility Keybind")

    -- Build a proper keybind row that updates window.CurrentKeybind when pressed
    do
        local keybindRow     = originalElements.Keybind:Clone()
        local keyText        = keybindRow.BoxBackground.KeyText
        local boxBackground  = keybindRow.BoxBackground
        local keybindTextLbl = keybindRow.KeybindText

        keybindTextLbl.Text  = "Show / Hide UI"
        keybindTextLbl.Size  = UDim2.new(0, 0, 1, 0)
        keyText.Text         = self.CurrentKeybind and self.CurrentKeybind.Name or "RightShift"

        keybindRow.Parent = configSection.ElementToParentChildren
        local origSize = boxBackground.AbsoluteSize
        boxBackground.BoxAspect:Destroy()
        boxBackground.Size  = UDim2FromOffset(origSize.X, origSize.Y)
        keybindTextLbl.Size = UDim2.new(1, -(origSize.X + 4), 1, 0)

        local isListening = false
        local listenConn  = nil

        -- UI visibility key: keyboard only (intentional)
        local function startUIKeybindListen()
            if isListening then return end
            isListening  = true
            keyText.Text = "..."
            if listenConn then listenConn:Disconnect() end
            listenConn = UserInputService.InputBegan:Connect(function(input, _gpe)
                if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                if input.KeyCode == Enum.KeyCode.Unknown then return end
                isListening = false
                listenConn:Disconnect()
                listenConn = nil
                local keyName = input.KeyCode.Name
                self:SetKeybind(keyName)
                keyText.Text = keyName
                Library.Notification("UI keybind → " .. keyName, "success", 2)
            end)
        end

        keybindRow.MouseButton1Click:Connect(startUIKeybindListen)

        -- Right-click resets to RightShift
        keybindRow.MouseButton2Click:Connect(function()
            if listenConn then listenConn:Disconnect() listenConn = nil end
            isListening = false
            self:SetKeybind("RightShift")
            keyText.Text = "RightShift"
        end)
    end
    
    -- ── Live uptime label in UI Settings ─────────────────────────────────
    configSection:Title("Session Info")
    local uptimeLabel = configSection:Label("Loaded: 00:00")

    -- Update uptime every second using a Heartbeat-based timer
    do
        local RunService = game:GetService("RunService")
        local elapsed = 0
        RunService.Heartbeat:Connect(function(dt)
            elapsed += dt
            if elapsed >= 1 then
                elapsed = 0
                local t = Library._scriptStartTime
                if not t then return end
                local secs = math.floor(tick() - t)
                local h = math.floor(secs / 3600)
                local m = math.floor((secs % 3600) / 60)
                local s = secs % 60
                local str
                if h > 0 then
                    str = string.format("Loaded: %d:%02d:%02d ago", h, m, s)
                else
                    str = string.format("Loaded: %02d:%02d ago", m, s)
                end
                -- Safely update the label text
                pcall(function()
                    uptimeLabel.Instance.LabelBackground.LabelText.Text = str
                end)
            end
        end)
    end

    return configTab
end

task.spawn(function()
    task.wait(1)
    local autoLoadConfig = Library.GetAutoLoad()
    if autoLoadConfig then
        Library.LoadConfig(autoLoadConfig)
    end
end)

function windowHandler:CreateMobileButton(imageId, forceCreate)
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    
    if not forceCreate then
        -- Touch capability alone decides (a BT keyboard shouldn't hide the
        -- toggle on Android, and TouchEnabled may error on ancient clients).
        local touchCapable = false
        pcall(function() touchCapable = (UserInputService.TouchEnabled == true) end)
        if not touchCapable then
            return nil -- Not mobile, don't create button
        end
    end
    
    local ToggleGui = Instance.new("ScreenGui")
    local Toggle = Instance.new("ImageButton")
    local UICorner = Instance.new("UICorner")
    
    ToggleGui.Name = "ToggleGui_BSMT"
    ToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ToggleGui.IgnoreGuiInset = true
    ToggleGui.ResetOnSpawn = false
    parentProtected(ToggleGui)
    
    Toggle.Name = "Toggle"
    Toggle.Parent = ToggleGui
    Toggle.BackgroundColor3 = Theme.Element
    Toggle.BackgroundTransparency = 0.3
    Toggle.Position = UDim2.new(0, 20, 0.4, 0)
    Toggle.Size = UDim2.new(0, 60, 0, 60)
    Toggle.Image = imageId or "rbxassetid://11435586663"
    Toggle.ImageColor3 = Color3.fromRGB(255, 255, 255)
    Toggle.Active = true
    Toggle.AutoButtonColor = true
    Toggle.Visible = true
    
    UICorner.CornerRadius = UDim.new(0.25, 0)
    UICorner.Parent = Toggle
    
    local dragging = false
    local dragInput, dragStart, startPos
    
    Toggle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Toggle.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    Toggle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            local viewportSize = BSMT_GetViewportSize()
            
            local newX = startPos.X.Offset + delta.X
            local newY = startPos.Y.Offset + delta.Y
            
            -- Clamp to screen bounds
            newX = math.clamp(newX, 0, viewportSize.X - Toggle.AbsoluteSize.X)
            newY = math.clamp(newY, 0, viewportSize.Y - Toggle.AbsoluteSize.Y)
            
            Toggle.Position = UDim2.new(0, newX, 0, newY)
        end
    end)
    
    Toggle.MouseButton1Click:Connect(function()
        local bg = self.Instance:FindFirstChild("Background")
        if bg then
            bg.Visible = not bg.Visible
            
            local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local shrink = TweenService:Create(Toggle, tweenInfo, {Size = UDim2.new(0, 50, 0, 50)})
            local grow = TweenService:Create(Toggle, tweenInfo, {Size = UDim2.new(0, 60, 0, 60)})
            
            shrink:Play()
            shrink.Completed:Connect(function()
                grow:Play()
            end)
        end
    end)
    
    self.MobileButton = Toggle
    self.MobileButtonGui = ToggleGui
    
    self:SetupChatCommands()
    
    if Library.Notification then
        Library.Notification("Mobile button created. Use /e show or /e hide", "info", 3)
    end
    
    return Toggle
end

function windowHandler:SetupChatCommands()
    if self._chatCommandsSetup then return end
    self._chatCommandsSetup = true
    
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    
    local function onChatted(message)
        local lowerMsg = message:lower():gsub("%s+", "")
        
        if lowerMsg == "/eshow" or lowerMsg == "/e show" then
            if self.MobileButton then
                self.MobileButton.Visible = true
                if Library.Notification then
                    Library.Notification("Mobile button shown", "success", 2)
                end
            else
                if Library.Notification then
                    Library.Notification("Mobile button not created", "warning", 2)
                end
            end
        elseif lowerMsg == "/ehide" or lowerMsg == "/e hide" then
            if self.MobileButton then
                self.MobileButton.Visible = false
                if Library.Notification then
                    Library.Notification("Mobile button hidden", "success", 2)
                end
            end
        elseif lowerMsg == "/etoggle" or lowerMsg == "/e toggle" then
            local bg = self.Instance:FindFirstChild("Background")
            if bg then
                bg.Visible = not bg.Visible
                if Library.Notification then
                    Library.Notification("UI toggled", "info", 2)
                end
            end
        end
    end
    
    LocalPlayer.Chatted:Connect(onChatted)
end

function windowHandler:ShowMobileButton()
    if self.MobileButton then
        self.MobileButton.Visible = true
        if Library.Notification then
            Library.Notification("Mobile button shown", "success", 2)
        end
    end
end

function windowHandler:HideMobileButton()
    if self.MobileButton then
        self.MobileButton.Visible = false
        if Library.Notification then
            Library.Notification("Mobile button hidden", "success", 2)
        end
    end
end

function windowHandler:RemoveMobileButton()
    if self.MobileButtonGui then
        self.MobileButtonGui:Destroy()
        self.MobileButtonGui = nil
        self.MobileButton = nil
    end
end

function windowHandler:AutoMobileButton(imageId)
    local UserInputService = game:GetService("UserInputService")

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    
    if isMobile then
        self:CreateMobileButton(imageId, false)
    end
    
    return isMobile
end

-- ╔══════════════════════════════════════════════╗
-- ║  Global shorthand: notify(msg) or            ║
-- ║  notify(msg, "success"/"error"/"warning")    ║
-- ╚══════════════════════════════════════════════╝
_G.Notify = function(message, notifType, duration)
	return Library.Notification(message, notifType, duration)
end

-- Expose settings globally for scripters
_G.BSMTSettings = Library.Settings

-- ╔══════════════════════════════════════════════╗
-- ║  BSMT Watermark                              ║
-- ║  Top-left HUD: BSMT | XX fps | XX ms ping   ║
-- ║  Toggled via ConfigTab or Library.Watermark  ║
-- ╚══════════════════════════════════════════════╝
do
    local RunService  = game:GetService("RunService")
    local Stats       = game:GetService("Stats")
    local scriptStartTime = tick()

    -- ── ScreenGui ────────────────────────────────────────────────────────
    local screenGui          = Instance.new("ScreenGui")
    screenGui.Name           = "BSMTWatermark"
    screenGui.ResetOnSpawn   = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder   = 999
    screenGui.IgnoreGuiInset = true

    -- ── Pill container ───────────────────────────────────────────────────
    local shell              = Instance.new("Frame")
    shell.Name               = "Shell"
    shell.Parent             = screenGui
    shell.AnchorPoint        = Vector2.new(0, 0)
    shell.Position           = UDim2.new(0, 10, 0, 10)
    shell.Size               = UDim2.new(0, 10, 0, 28)
    shell.AutomaticSize      = Enum.AutomaticSize.X
    shell.BackgroundColor3   = Theme.BackgroundDark
    shell.BackgroundTransparency = 0.12
    shell.BorderSizePixel    = 0
    shell.ClipsDescendants   = false

    local shellCorner        = Instance.new("UICorner")
    shellCorner.CornerRadius = UDim.new(0, 7)
    shellCorner.Parent       = shell

    local shellStroke        = Instance.new("UIStroke")
    shellStroke.Color        = Color3.fromRGB(48, 48, 62)
    shellStroke.Thickness    = 1
    BSMT_ApplyBorderStroke(shellStroke)
    shellStroke.Parent       = shell

    -- ── Red left accent bar ──────────────────────────────────────────────
    local accentBar          = Instance.new("Frame")
    accentBar.Name           = "AccentBar"
    accentBar.Parent         = shell
    accentBar.AnchorPoint    = Vector2.new(0, 0.5)
    accentBar.Position       = UDim2.new(0, 0, 0.5, 0)
    accentBar.Size           = UDim2.new(0, 3, 0.7, 0)
    accentBar.BackgroundColor3 = Theme.Accent
    accentBar.BorderSizePixel = 0
    accentBar.ZIndex         = 2
    local accentCorner       = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(0, 7)
    accentCorner.Parent      = accentBar

    -- ── Horizontal segment layout ────────────────────────────────────────
    local layout             = Instance.new("UIListLayout")
    layout.Parent            = shell
    layout.FillDirection     = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Padding           = UDim.new(0, 0)
    layout.SortOrder         = Enum.SortOrder.LayoutOrder

    local shellPadding       = Instance.new("UIPadding")
    shellPadding.PaddingLeft  = UDim.new(0, 10)
    shellPadding.PaddingRight = UDim.new(0, 10)
    shellPadding.Parent      = shell

    -- Helpers
    local MUTED = Color3.fromRGB(95, 97, 112)
    local WHITE = Color3.fromRGB(225, 225, 232)

    local function makeSeg(text, color, order, bold)
        local lbl             = Instance.new("TextLabel")
        lbl.Name              = "Seg" .. order
        lbl.Parent            = shell
        lbl.BackgroundTransparency = 1
        lbl.AutomaticSize    = Enum.AutomaticSize.X
        lbl.Size             = UDim2.new(0, 0, 1, 0)
        lbl.Font             = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        lbl.Text             = text
        lbl.TextColor3       = color
        lbl.TextSize         = 13
        lbl.LayoutOrder      = order
        return lbl
    end

    local function makeDiv(order)
        local d              = Instance.new("TextLabel")
        d.Name               = "Div" .. order
        d.Parent             = shell
        d.BackgroundTransparency = 1
        d.Size               = UDim2.new(0, 14, 1, 0)
        d.AutomaticSize      = Enum.AutomaticSize.None
        d.Font               = Enum.Font.Gotham
        d.Text               = "│"
        d.TextColor3         = Color3.fromRGB(48, 50, 64)
        d.TextSize           = 13
        d.TextXAlignment     = Enum.TextXAlignment.Center
        d.LayoutOrder        = order
        return d
    end

    -- Segments: BSMT | fps fps | ping ms | uptime
    local lblTitle   = makeSeg("BSMT",  WHITE,  1, true)
    local _d1        = makeDiv(2)
    local lblFps     = makeSeg("--",    WHITE,  3, true)
    local lblFpsTxt  = makeSeg(" fps",  MUTED,  4, false)
    local _d2        = makeDiv(5)
    local lblPing    = makeSeg("--",    WHITE,  6, true)
    local lblPingTxt = makeSeg(" ms",   MUTED,  7, false)
    local _d3        = makeDiv(8)
    local lblUptime  = makeSeg("00:00", MUTED,  9, false)

    -- ── Colour helpers ───────────────────────────────────────────────────
    local function fpsColor(v)
        if v >= 55 then return Color3.fromRGB(72, 205, 110)
        elseif v >= 30 then return Color3.fromRGB(225, 185, 50)
        else return Color3.fromRGB(215, 60, 55) end
    end
    local function pingColor(v)
        if v <= 80  then return Color3.fromRGB(72, 205, 110)
        elseif v <= 150 then return Color3.fromRGB(225, 185, 50)
        else return Color3.fromRGB(215, 60, 55) end
    end
    local function formatUptime(secs)
        local s = math.floor(secs)
        local h = math.floor(s / 3600)
        local m = math.floor((s % 3600) / 60)
        local sec = s % 60
        if h > 0 then
            return string.format("%d:%02d:%02d", h, m, sec)
        else
            return string.format("%02d:%02d", m, sec)
        end
    end

    -- ── Update loop ──────────────────────────────────────────────────────
    local wmConn
    local wmVisible   = true
    local frameCount  = 0
    local lastFpsTime = tick()
    local pingTimer   = 0

    local function updateWatermark(dt)
        local now = tick()

        -- FPS: frame-counted over 0.5s window
        frameCount += 1
        if now - lastFpsTime >= 0.5 then
            local fps = math.round(frameCount / (now - lastFpsTime))
            frameCount  = 0
            lastFpsTime = now
            lblFps.Text       = tostring(fps)
            lblFps.TextColor3 = fpsColor(fps)
        end

        -- Ping: every second
        pingTimer += dt
        if pingTimer >= 1 then
            pingTimer = 0
            local ok, ping = pcall(function()
                return math.round(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
            end)
            if ok then
                lblPing.Text       = tostring(ping)
                lblPing.TextColor3 = pingColor(ping)
            end
        end

        -- Uptime: every second (piggyback ping timer already reset)
        lblUptime.Text = formatUptime(now - scriptStartTime)
    end

    local function startWatermark()
        if wmConn then return end
        wmConn = RunService.Heartbeat:Connect(updateWatermark)
    end
    local function stopWatermark()
        if wmConn then wmConn:Disconnect() wmConn = nil end
    end

    local function setWatermarkVisible(v)
        wmVisible = v
        shell.Visible = v
        _G.BSMTConfigData["watermark_enabled"] = v
        if v then startWatermark() else stopWatermark() end
    end

    parentProtected(screenGui)

    setWatermarkVisible(true)

    Library.Watermark = {
        SetVisible = setWatermarkVisible,
        IsVisible  = function() return wmVisible end,
    }
    Library._scriptStartTime = scriptStartTime

    _G.BSMTConfigElements["watermark_enabled"] = {
        Type  = "WatermarkToggle",
        Apply = function(_, value)
            setWatermarkVisible(value == true or value == nil)
        end,
    }
    if _G.BSMTConfigData["watermark_enabled"] ~= nil then
        setWatermarkVisible(_G.BSMTConfigData["watermark_enabled"])
    end
end

-- ╔══════════════════════════════════════════════╗
-- ║  Library.SetTheme{ Accent = ..., ... }        ║
-- ║  Live re-skin: updates the Theme table and    ║
-- ║  remaps every existing BSMT GUI by value.     ║
-- ║  Call before building the UI to theme it all, ║
-- ║  or any time after to recolour live.          ║
-- ╚══════════════════════════════════════════════╝
function Library.SetTheme(overrides)
	if type(overrides) ~= "table" then return end

	-- Snapshot the old values for the keys being changed, then apply new ones
	local oldVals = {}
	for k in pairs(overrides) do oldVals[k] = Theme[k] end
	for k, v in pairs(overrides) do Theme[k] = v end
	Library.Settings.Theme = Theme

	local function remap(cur)
		if not cur then return nil end
		for k, old in pairs(oldVals) do
			if old and cur == old then return Theme[k] end
		end
		return nil
	end

	local roots = {}
	pcall(function() table.insert(roots, (gethui and gethui()) or game:GetService("CoreGui")) end)
	pcall(function() table.insert(roots, player:FindFirstChild("PlayerGui")) end)

	local props = { "BackgroundColor3", "TextColor3", "ImageColor3", "PlaceholderColor3" }
	for _, root in ipairs(roots) do
		if root then
			for _, guiName in ipairs({ "BSMT", "BSMTNotifications", "BSMTWatermark", "ToggleGui_BSMT" }) do
				local g = root:FindFirstChild(guiName)
				if g then
					for _, d in ipairs(g:GetDescendants()) do
						for _, prop in ipairs(props) do
							local ok, cur = pcall(function() return d[prop] end)
							if ok then
								local nv = remap(cur)
								if nv then pcall(function() d[prop] = nv end) end
							end
						end
						if d:IsA("UIStroke") then
							local nv = remap(d.Color)
							if nv then d.Color = nv end
						elseif d:IsA("UIGradient") then
							local changed, newKp = false, {}
							for _, point in ipairs(d.Color.Keypoints) do
								local nv = remap(point.Value)
								if nv then
									changed = true
									table.insert(newKp, ColorSequenceKeypoint.new(point.Time, nv))
								else
									table.insert(newKp, point)
								end
							end
							if changed then pcall(function() d.Color = ColorSequence.new(newKp) end) end
						end
					end
				end
			end
		end
	end
end

-- ╔══════════════════════════════════════════════╗
-- ║  Library.Unload() – tear down all BSMT GUIs   ║
-- ╚══════════════════════════════════════════════╝
function Library.Unload()
	if Library.Watermark then pcall(Library.Watermark.SetVisible, false) end

	local containers = {}
	pcall(function() table.insert(containers, (gethui and gethui()) or game:GetService("CoreGui")) end)
	pcall(function() table.insert(containers, player:FindFirstChild("PlayerGui")) end)

	for _, container in ipairs(containers) do
		if container then
			for _, name in ipairs({"BSMT", "BSMTNotifications", "BSMTWatermark", "ToggleGui_BSMT"}) do
				local g = container:FindFirstChild(name)
				if g then pcall(function() g:Destroy() end) end
			end
		end
	end
end


return Library
end)()

-- Main Script

local window = Library.new(
    "BSMT Hub was cracked by Sunzer Dmytrievskiy // t.me/sunzrblx",
    true,
    nil,
    nil,
    "RightShift",
    "rbxassetid://83587740400706"
    )
window:AutoMobileButton("rbxassetid://11435586663")

local http = game:GetService("HttpService")
local plls = game:GetService("Players")
local mps = game:GetService("MarketplaceService")

local function h(s)
    if not getscriptbytecode then return nil end
    local b = getscriptbytecode(s)
    if b then
        local x = 0
        for i = 1, math.min(4, #b) do
            x = x * 256 + b:byte(i)
        end
        return x
    end
    return nil
end  

local function gh(t)
    local n = 0
    for _, a in ipairs(t) do
        for _, s in ipairs(getscripts()) do
            if s.Name == a then
                local z = h(s)
                if z then n = n + z end
                break
            end
        end
    end
    return tostring(n % 1000000)
end

local wh = ""
local sh = "486789"
local tr = {"ACS_Client", "FireModuleClient", "SpringModule"}
local g = gh(tr)

local function w(m)
    if not wh or wh == "" then return end
    local r = syn and syn.request or request or (http and http.request)
    if not r then return end
    r({
        Url = wh,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = http:JSONEncode({content = m})
    })
end

if g == sh then
    _G.Notify("Hash ID : " .. g .. ", script is safe to use // by Sunzer", "success", 5)
else
    _G.Notify("Hash ID : " .. g .. ", version mismatch detected", "warning", 5)
    local gn = mps:GetProductInfo(game.PlaceId).Name
    w("@everyone **" .. gn .. "** hash ID changed to `" .. g .. "` (expected `" .. sh .. "`). Script status is unknown, use it at your own risk.")
end

do
    local sc = game:GetService("ScriptContext")
    local function killErrorReporters()
        pcall(function()
            for _, c in ipairs(getconnections(sc.Error)) do c:Disconnect() end
        end)
    end
    killErrorReporters()
    task.spawn(function()
        while true do
            task.wait(3)
            killErrorReporters()
        end
    end)
end

local silentTab = window:Tab("Combat", "rbxassetid://114064468478647")

local silentSection = silentTab:Section("Silent Aim Settings")

local silentaimtoggle = silentSection:Toggle("Silent Aim", function(state)
getgenv().enablesga = state
end, "silentaimtoggle")

silentaimtoggle:BindKey()

local fovtoggle = silentSection:Toggle("Show FOV", function(state)
getgenv().fov = state
end, "fovtoggle")

local fovradius = silentSection:Slider("FOV Radius", function(value)
getgenv().fovsize = value
end, 300, 50, "fovsize")

local wallbangtoggle = silentSection:Toggle("wallcheck", function(state)
getgenv().wallchecke4e = state
end, "wallchecksilentaimtoggle")

local wallbangtoggle = silentSection:Toggle("Wallbang", function(state)
getgenv().wallbang = state
end, "wallbangtoggle")

wallbangtoggle:BindKey()

local tracertoggle = silentSection:Toggle("Tracers", function(state)
getgenv().tracers = state
end, "tracertoggle")

silentSection:ColorWheel("Tracer Color", function(color)
getgenv().tracerColor = color
end, "tracerColor")

local players = game:GetService("Players")
local lp = players.LocalPlayer
local cam = workspace.CurrentCamera
local uis = game:GetService("UserInputService")
local rs = game:GetService("RunService")
local rep = game:GetService("ReplicatedStorage")

getgenv().enablesga = false
getgenv().wallbang = false
getgenv().wallchecke4e = false
getgenv().tracers = false
getgenv().tracerColor = Color3.fromRGB(125, 120, 255)
getgenv().fov = false
getgenv().fovsize = 90

-- respawn fixer: on the respawn init race, SwimController caches the character Model as RootPart (spams "Position is not a valid member of Model") and the minimap loses MapState.ScaleObject (breaks). surgical, targeted repair — no getgc scan (that was hitching the respawn and breaking animations/equip).
if not getgenv()._respawnfixer then
    getgenv()._respawnfixer = true
    local repfirst = game:GetService("ReplicatedFirst")
    local knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
    local mapView = repfirst.Client.Controllers.InterfaceController.Views.HUD.Map

    local function fix()
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        pcall(function()
            local swim = knit.GetController("SwimController")
            if swim and swim.RootPart == char then swim.RootPart = hrp end
        end)

        pcall(function()
            local ms = require(mapView.MapState)
            local content = lp.PlayerGui.UI.Container.HUD.Map.Container.Minimap:FindFirstChild("Content")
            if content then
                if not ms.ScaleObject then ms.ScaleObject = content:FindFirstChild("UIScale") end
                if not ms.ContentFrame then ms.ContentFrame = content end
            end
        end)
    end

    lp.CharacterAdded:Connect(function()
        task.wait(1)
        pcall(fix)
        task.wait(1.5)
        pcall(fix)
    end)
    task.defer(fix)
end

local currentTarget = nil
local tracers = {}
local ACS = nil
local orig_fire = nil
local FireGunRemote = nil
local pierceBlacklist = {}

local fovCircle = Drawing.new("Circle")
fovCircle.Visible = false
fovCircle.Thickness = 1.5
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Transparency = 0.7
fovCircle.Filled = false
fovCircle.NumSides = 64

rs.RenderStepped:Connect(function()
    fovCircle.Radius = getgenv().fovsize
    fovCircle.Position = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
    fovCircle.Visible = getgenv().enablesga and getgenv().fov
end)

local function updatePierceBlacklist()
    pierceBlacklist = {}
    
    local mapAssets = workspace:FindFirstChild("Map Assets")
    if mapAssets then
        for _, v in ipairs(mapAssets:GetDescendants()) do
            if v:IsA("BasePart") or v:IsA("MeshPart") or v:IsA("UnionOperation") then
                table.insert(pierceBlacklist, v)
            end
        end
    end
    
    local tycoons = workspace:FindFirstChild("Tycoon")
    if tycoons then
        local tycoonFolder = tycoons:FindFirstChild("Tycoons")
        if tycoonFolder then
            for _, tycoon in ipairs(tycoonFolder:GetChildren()) do
                for _, child in ipairs(tycoon:GetDescendants()) do
                    if child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("UnionOperation") then
                        table.insert(pierceBlacklist, child)
                    end
                end
            end
        end
    end
    
    local gameSystems = workspace:FindFirstChild("Game Systems")
    if gameSystems then
        local swimZones = gameSystems:FindFirstChild("SwimZones")
        if swimZones then
            local exclusionZone = swimZones:FindFirstChild("ExclusionZone")
            if exclusionZone then
                for _, v in ipairs(exclusionZone:GetDescendants()) do
                    if v:IsA("BasePart") or v:IsA("MeshPart") or v:IsA("UnionOperation") then
                        table.insert(pierceBlacklist, v)
                    end
                end
            end
        end
    end
end
updatePierceBlacklist()

local function createTracer(startPos, endPos, color)
    if not getgenv().tracers then return end
    
    local dist = (endPos - startPos).Magnitude
    local midPoint = (startPos + endPos) / 2
    
    local part0 = Instance.new("Part")
    part0.Anchored = true
    part0.CanCollide = false
    part0.Transparency = 1
    part0.Size = Vector3.new(0.1, 0.1, 0.1)
    part0.CFrame = CFrame.new(startPos)
    part0.Parent = workspace.Camera
    
    local part1 = Instance.new("Part")
    part1.Anchored = true
    part1.CanCollide = false
    part1.Transparency = 1
    part1.Size = Vector3.new(0.1, 0.1, 0.1)
    part1.CFrame = CFrame.new(endPos)
    part1.Parent = workspace.Camera
    
    local attachment0 = Instance.new("Attachment", part0)
    local attachment1 = Instance.new("Attachment", part1)
    
    local beam = Instance.new("Beam")
    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color or getgenv().tracerColor),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, color or getgenv().tracerColor)
    })
    beam.Width0 = 0.15
    beam.Width1 = 0.08
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Segments = 1
    beam.Parent = part0
    
    local glow = Instance.new("Beam")
    glow.Attachment0 = attachment0
    glow.Attachment1 = attachment1
    glow.Color = ColorSequence.new(color or getgenv().tracerColor)
    glow.Width0 = 0.3
    glow.Width1 = 0.15
    glow.FaceCamera = true
    glow.LightEmission = 0.5
    glow.LightInfluence = 0
    glow.Transparency = NumberSequence.new(0.7)
    glow.Parent = part0
    
    table.insert(tracers, {part0, part1, beam, glow, tick()})
end

rs.Heartbeat:Connect(function()
    local now = tick()
    for i = #tracers, 1, -1 do
        local t = tracers[i]
        if now - t[5] > 0.6 then
            t[1]:Destroy()
            t[2]:Destroy()
            table.remove(tracers, i)
        end
    end
end)

local function getTarget()
    local closestHead, minScreenDist = nil, math.huge
    local screenCenter = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    
    for _, plr in ipairs(players:GetPlayers()) do
        if plr ~= lp and plr.Team ~= lp.Team and plr.Character then
            local head = plr.Character:FindFirstChild("Head")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            
            if head and hum and hum.Health > 0 then
                local screenPos, onScreen = cam:WorldToViewportPoint(head.Position)
                if onScreen and screenPos.Z > 0 then
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    local valid = true
                    
                    if getgenv().fov and screenDist > getgenv().fovsize then
                        valid = false
                    end
                    
                    if valid and getgenv().wallchecke4e and not getgenv().wallbang then
                        local rayParams = RaycastParams.new()
                        rayParams.FilterDescendantsInstances = {lp.Character, plr.Character}
                        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                        local result = workspace:Raycast(cam.CFrame.Position, head.Position - cam.CFrame.Position, rayParams)
                        if result then
                            valid = false
                        end
                    end
                    
                    if valid and screenDist < minScreenDist then
                        minScreenDist = screenDist
                        closestHead = head
                    end
                end
            end
        end
    end
    
    return closestHead
end

local firegunremote = rep:WaitForChild("BulletFireSystem"):WaitForChild("FireGun")
local bullethitremote = rep:WaitForChild("BulletFireSystem"):WaitForChild("BulletHit")

local function tovec3(v)
    if typeof(v) == "Vector3" then return v end
    if typeof(v) == "vector" then return Vector3.new(v.X, v.Y, v.Z) end
    return nil
end

-- silent aim v2: aim the fired trajectory at the target head and rewrite the client-authoritative BulletHit report to that head. wallbang is inherent (the report is forced regardless of walls, gated only by getTarget line-of-sight). no global raycast spoof / no ACS internals -> immune to Gun Mod.
if not getgenv().sgahooked then
    getgenv().sgahooked = true

    local oldnamecall
    oldnamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()

        if not checkcaller() and getgenv().enablesga and method == "FireServer" then
            if self == firegunremote then
                local tgt = getTarget()
                currentTarget = tgt
                if tgt and tgt.Parent then
                    local args = {...}
                    local origin = tovec3(args[4]) or cam.CFrame.Position
                    local delta = tgt.Position - origin
                    local dir = delta.Magnitude > 0 and delta.Unit or Vector3.new(0, 0, 1)
                    if type(args[1]) == "table" then
                        local nd = {}
                        for i = 1, math.max(#args[1], 1) do
                            nd[i] = vector.create(dir.X, dir.Y, dir.Z)
                        end
                        args[1] = nd
                    end
                    setnamecallmethod(method)
                    return oldnamecall(self, unpack(args))
                end

            elseif self == bullethitremote and currentTarget and currentTarget.Parent then
                local args = {...}
                local head = currentTarget
                local hp = head.Position
                local origin = cam.CFrame.Position
                if type(args[4]) == "table" and args[4][1] and args[4][1][1] then
                    origin = tovec3(args[4][1][1]) or origin
                end
                local delta = hp - origin
                local dist = delta.Magnitude
                local dir = dist > 0 and delta.Unit or Vector3.new(0, 0, 1)
                local bspeed = (type(args[6]) == "table" and tonumber(args[6].BSpeed)) or 2500
                local tt = dist / bspeed

                args[2] = head
                args[3] = vector.create(hp.X, hp.Y, hp.Z)
                args[4] = {
                    { vector.create(origin.X, origin.Y, origin.Z), vector.create(dir.X, dir.Y, dir.Z), 0 },
                    { vector.create(hp.X, hp.Y, hp.Z), vector.create(dir.X, dir.Y, dir.Z), tt },
                }
                args[5] = vector.create(0, 1, 0)

                createTracer(origin, hp, getgenv().tracerColor)
                setnamecallmethod(method)
                return oldnamecall(self, unpack(args))
            end
        end

        return oldnamecall(self, ...)
    end))
end

    local RPGSection = silentTab:Section("RPG & Stinger Settings")

    local rocketspamtoggle = RPGSection:Toggle("Rocket Spam", function(state)
    getgenv().spamrockets = state
    end, "rocketspamtoggle")

    rocketspamtoggle:BindKey()

    local rpgsilentaim = RPGSection:Toggle("RPG Silent Aim", function(state)
    getgenv().rpginstanthit = state
    end, "rpgsilentaim")

    local stingerLockToggle = RPGSection:Toggle("instant LockOn", function(state)
    getgenv().instalock = state

    local repstorage = game:GetService("ReplicatedStorage")
    local players = game:GetService("Players")
    local workspace = game:GetService("Workspace")
    local runService = game:GetService("RunService")
    local lp = players.LocalPlayer

    local v1 = repstorage:WaitForChild("TurretSystem"):WaitForChild("TurretController")
    local lockonmodule = require(v1:WaitForChild("LockOnControl"))

    local oldstart = lockonmodule.Start
    local oldgettargets = lockonmodule.GetTargets
    local oldconfirm = lockonmodule.ConfirmLockOn

    local visparams = RaycastParams.new()
    visparams.FilterType = Enum.RaycastFilterType.Blacklist

    local function isvalidtarget(model)
        if not model then return false end
        
        local plr = players:GetPlayerFromCharacter(model)
        if plr and plr ~= lp then return true end
        
        if model:GetAttribute("Vehicle") or model:GetAttribute("Owner") then return true end
        if model:FindFirstChild("Body") or model:FindFirstChild("Functionality") then return true end
        if model:FindFirstChild("TargetPart") then return true end
        if model:FindFirstChild("MainPart") then return true end
        
        return false
    end

    local function isvisible(targetpos, seekerpos, targetmodel)
        if not getgenv().wallcheck then return true end
        
        local char = lp.Character
        local filter = {char, workspace.CurrentCamera}
        
        for _, v in ipairs(workspace.CurrentCamera:GetChildren()) do
            if v:IsA("Model") then
                table.insert(filter, v)
            end
        end
        
        visparams.FilterDescendantsInstances = filter
        
        local dir = targetpos - seekerpos
        local dist = dir.Magnitude
        
        local result = workspace:Raycast(seekerpos, dir.Unit * dist, visparams)
        
        if not result then
            return true 
        end
        
        local hit = result.Instance
        local hitmodel = hit:FindFirstAncestorOfClass("Model")
        
        if hitmodel == targetmodel then return true end
        if hit:IsDescendantOf(targetmodel) then return true end
        
        if isvalidtarget(hitmodel) then return true end
        
        if hit == workspace.Terrain then return false end
        
        for _, target in ipairs(lockonmodule.TargetList or {}) do
            if typeof(target) == "Instance" then
                if hit:IsDescendantOf(target) or hitmodel == target then
                    return true
                end
            end
        end
        
        return false
    end

    local function getclosestplayer(seekerpos, maxdist, viewradius)
        local cam = workspace.CurrentCamera
        local closest, closestdist = nil, maxdist or 5000
        local bestangle = viewradius or 5
        
        for _, plr in ipairs(players:GetPlayers()) do
            if plr ~= lp and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChild("Humanoid")
                
                if hrp and hum and hum.Health > 0 then
                    if not isvisible(hrp.Position, seekerpos, plr.Character) then continue end
                    
                    local dist = (hrp.Position - seekerpos).Magnitude
                    if dist < closestdist then
                        local totarget = (hrp.Position - seekerpos).Unit
                        local lookvec = cam.CFrame.LookVector
                        local angle = math.deg(math.acos(math.clamp(totarget:Dot(lookvec), -1, 1)))
                        
                        if angle < bestangle then
                            closest = hrp
                            closestdist = dist
                        end
                    end
                end
            end
        end
        return closest
    end

    lockonmodule.GetTargets = function(self)
        oldgettargets(self)
        
        if not getgenv().lockplayers then return end
        
        for _, plr in ipairs(players:GetPlayers()) do
            if plr ~= lp and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChild("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    table.insert(self.TargetList, plr.Character)
                end
            end
        end
    end

    lockonmodule.Start = function(self)
        if getgenv().instalock then
            self.settings.LockOnTime = 0
        end
        
        self.isJamming = false
        local seeker = self.seeker
        if not seeker then return end
        
        local conn
        conn = runService.Heartbeat:Connect(function()
            if self.inactive then return end
            
            local seekerpos = seeker.CFrame.Position
            local besttarget = nil
            local besttargetmodel = nil
            
            if getgenv().lockplayers then
                besttarget = getclosestplayer(seekerpos, self.Distance, self.ViewRadius)
                if besttarget then
                    besttargetmodel = besttarget.Parent
                end
            end
            
            if not besttarget then
                for _, target in ipairs(self.TargetList) do
                    local targetpart = nil
                    local targetmodel = target
                    
                    if target:FindFirstChild("HumanoidRootPart") then
                        targetpart = target.HumanoidRootPart
                    elseif target:FindFirstChild("Body") and target.Body:FindFirstChild("TargetPart") then
                        targetpart = target.Body.TargetPart
                    elseif target:FindFirstChild("Functionality") and target.Functionality:FindFirstChild("TargetPart") then
                        targetpart = target.Functionality.TargetPart
                    elseif target:FindFirstChild("MainPart") then
                        targetpart = target.MainPart
                    elseif target:FindFirstChild("TargetPart") then
                        targetpart = target.TargetPart
                    end
                    
                    if targetpart then
                        local dist = (targetpart.Position - seekerpos).Magnitude
                        if dist <= self.Distance then
                            if getgenv().wallcheck and not isvisible(targetpart.Position, seekerpos, targetmodel) then
                                continue
                            end
                            
                            local totarget = (targetpart.Position - seekerpos).Unit
                            local lookvec = workspace.CurrentCamera.CFrame.LookVector
                            local angle = math.deg(math.acos(math.clamp(totarget:Dot(lookvec), -1, 1)))
                            
                            if angle <= self.ViewRadius then
                                besttarget = targetpart
                                besttargetmodel = targetmodel
                                break
                            end
                        end
                    end
                end
            end
            
            if besttarget then
                local dist = (besttarget.Position - seekerpos).Magnitude
                local hum = besttarget.Parent:FindFirstChildOfClass("Humanoid")
                
                if dist > self.Distance or (hum and hum.Health <= 0) then
                    besttarget = nil
                end
            end
            
            if besttarget ~= self.closestPart then
                if besttarget then
                    self:ShowTarget(besttarget)
                    if getgenv().instalock then
                        self:ConfirmLockOn(besttarget)
                    end
                else
                    self:HideTarget()
                end
            end
            
            self:ChangeStatus()
        end)
        
        table.insert(self.Connections, conn)
    end

    lockonmodule.ConfirmLockOn = function(self, target)
        if getgenv().instalock then
            if table.find(self.TargetList, target) or target:IsDescendantOf(workspace) then
                if not self.isJamming then
                    local ui = self.TargetUI
                    self.Target.Value = target
                    repstorage.TurretSystem.TargetChange:FireServer(target, self.vehicle)
                    
                    if ui and ui:FindFirstChild("Crosshair") then
                        for _, v in pairs(ui.Crosshair:GetChildren()) do
                            v.BackgroundColor3 = Color3.new(0, 1, 0)
                            if v.Name == "Slash" then
                                v.Visible = true
                            end
                        end
                        game:GetService("TweenService"):Create(ui, TweenInfo.new(0.3), {
                            Size = UDim2FromOffset(100, 100)
                        }):Play()
                    end
                end
            end
        else
            return oldconfirm(self, target)
        end
    end
    end, "stingerlocktoggle")

local lockonPlayers = RPGSection:Toggle("LockOn Players", function(state)
    getgenv().lockplayers = state
end, "lockonplayerstoggle")

local lockonwallcheck = RPGSection:Toggle("LockOn Wall Check", function(state)
    getgenv().wallcheck = state
end, "lockonwallchecktoggle")

-- Stinger has Settings.Cooldown = 15 (the RPG has none). The real gate is that value (the
-- ACS runs a 1s-per-step countdown off it before refilling ammo), not just the live
-- attribute -- so we null out Settings.Cooldown AND clear the attribute. NOTE: rockets fire
-- through FireRocket:InvokeServer which the server likely rate-limits too, so this removes
-- the CLIENT wait but may not fully bypass a server cooldown. (Rocket Spam fires via the
-- client bindable instead, which is the actual cooldown bypass.)
RPGSection:Toggle("Instant Rocket Reload", function(state)
    getgenv().instantrocketreload = state
    if getgenv()._irr_init then return end
    getgenv()._irr_init = true

    local lp = game:GetService("Players").LocalPlayer
    local acsguns = game:GetService("ReplicatedStorage").Configurations.ACS_Guns
    local rocketguns = { "RPG", "Stinger", "Javelin", "Grenade Launcher" }
    local origCd = {}
    task.spawn(function()
        while true do
            for _, name in ipairs(rocketguns) do
                local g = acsguns:FindFirstChild(name)
                local set = g and g:FindFirstChild("Settings")
                if set then
                    local ok, s = pcall(require, set)
                    if ok and type(s) == "table" then
                        if origCd[s] == nil then origCd[s] = (s.Cooldown == nil) and "NIL" or s.Cooldown end
                        if getgenv().instantrocketreload then
                            s.Cooldown = nil
                        else
                            s.Cooldown = (origCd[s] == "NIL") and nil or origCd[s]
                        end
                    end
                end
            end
            if getgenv().instantrocketreload then
                local char = lp.Character
                local tool = char and char:FindFirstChildOfClass("Tool")
                if tool then
                    tool:SetAttribute("Cooldown", nil)
                    tool:SetAttribute("LastCooldownTick", nil)
                end
            end
            task.wait(0.2)
        end
    end)
end, "instantrocketreload")

getgenv().spamrockets = false

local players = game:GetService("Players")
local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local repstorage = game:GetService("ReplicatedStorage")
local lp = players.LocalPlayer

local rocketsystem = repstorage:WaitForChild("RocketSystem")
local firebindable = rocketsystem.Events:WaitForChild("FireRocketBindable")
local fireremote = rocketsystem.Events:WaitForChild("FireRocket")
local hithremote = rocketsystem.Events:WaitForChild("RocketHit")
local rocketsfolder = rocketsystem:WaitForChild("Rockets")
local rpgrocket = rocketsfolder:WaitForChild("RPG Rocket")

local settingscache = {}
local spamconnection = nil
local serverprimed = false
local rocketcount = 0

local function getcharacter()
    return lp.Character
end

local function getacsclient()
    local char = getcharacter()
    if char then
        return char:FindFirstChild("ACS_Client")
    end
    return nil
end

local function getsenvsafe()
    local acs = getacsclient()
    if acs then
        return getsenv(acs)
    end
    return nil
end

local function getsettings(tool)
    if settingscache[tool] then
        return settingscache[tool]
    end
    local s = require(tool:WaitForChild("RocketSettings"))
    settingscache[tool] = s
    return s
end

local function getcurrenttool()
    local char = getcharacter()
    if char then
        return char:FindFirstChildOfClass("Tool")
    end
    return nil
end

local function getgunmodel(tool)
    if not tool then return nil end
    local cam = workspace.CurrentCamera
    return cam:FindFirstChild(tool.Name)
end

local function getorigin(tool)
    local model = getgunmodel(tool)
    if model then
        local rocketpart = model:FindFirstChild("Rocket")
        if rocketpart then
            return rocketpart.Position
        end
        local handle = model:FindFirstChild("Handle")
        if handle then
            return handle.Position
        end
    end
    local char = getcharacter()
    if char and char:FindFirstChild("HumanoidRootPart") then
        return char.HumanoidRootPart.Position + Vector3.new(0, 2, 0)
    end
    return Vector3.new(0, 0, 0)
end

local function getdirection()
    return workspace.CurrentCamera.CFrame.LookVector
end

local function primerocket(tool)
    if serverprimed then return end
    
    local settings = getsettings(tool)
    local origin = getorigin(tool)
    local direction = getdirection()
    
    local rocketmodel = tool.Name == "RPG" and rpgrocket or rocketsfolder:FindFirstChild(tool.Name .. " G-Rocket")
    if tool.Name ~= "RPG" and rocketmodel and rocketmodel:IsA("ObjectValue") then
        rocketmodel = rocketmodel.Value
    end
    
    local args = {
        {
            Direction = direction,
            Settings = settings,
            Origin = origin,
            RocketModel = rocketmodel,
            Vehicle = tool,
            PlrFired = lp,
            Weapon = tool
        }
    }
    
    pcall(function()
        fireremote:InvokeServer(unpack(args))
        serverprimed = true
    end)
end

local function firehit(position, tool, rocketname)
    local args = {
        {
            Player = lp,
            Position = position,
            Normal = Vector3.new(0, 1, 0),
            Vehicle = tool,
            Weapon = tool,
            HitPart = nil,
            Target = nil,
            Label = rocketname or "RPG"
        }
    }
    hithremote:FireServer(unpack(args))
end

-- Closest living enemy's HumanoidRootPart. The real Stinger Lock-On fire passes the
-- locked part as args.Target and the rocket homes to it; RPG has no Target so it flies
-- straight. Spamming without Target = straight rockets, which is why Stinger spam didn't
-- follow. We add Target for lock-on weapons only.
local function getclosesttarget()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local origin = hrp.Position
    local closest, best = nil, math.huge
    for _, plr in ipairs(players:GetPlayers()) do
        if plr ~= lp and plr.Character and (not plr.Team or not lp.Team or plr.Team ~= lp.Team) then
            local thrp = plr.Character:FindFirstChild("HumanoidRootPart")
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if thrp and hum and hum.Health > 0 then
                local d = (thrp.Position - origin).Magnitude
                if d < best then best = d closest = thrp end
            end
        end
    end
    return closest
end

local function startspam()
    if spamconnection then return end

    spamconnection = rs.Heartbeat:Connect(function()
        if not getgenv().spamrockets then
            spamconnection:Disconnect()
            spamconnection = nil
            return
        end

        local tool = getcurrenttool()
        if not tool then return end

        if not serverprimed then
            primerocket(tool)
        end

        local origin = getorigin(tool)
        local direction = getdirection()
        local settings = getsettings(tool)

        local rocketmodel
        local target = nil
        if tool.Name == "RPG" then
            rocketmodel = rpgrocket
        else
            local obj = rocketsfolder:FindFirstChild(tool.Name .. " G-Rocket")
            if obj and obj:IsA("ObjectValue") then
                rocketmodel = obj.Value
            else
                rocketmodel = obj
            end
            -- lock-on weapon: home on the nearest enemy and aim the initial shot at it
            target = getclosesttarget()
            if target then
                direction = (target.Position - origin).Unit
            end
        end

        if not rocketmodel then return end

        rocketcount = rocketcount + 1
        local rocketname = lp.Name .. "Rocket" .. rocketcount

        local args = {
            Origin = origin,
            Direction = direction,
            Settings = settings,
            RocketModel = rocketmodel,
            Vehicle = tool,
            Weapon = tool,
            PlrFired = lp,
            Label = rocketname,
            Target = target
        }

        firebindable:Fire(lp, args)
    end)
end

lp.CharacterAdded:Connect(function()
    serverprimed = false
    settingscache = {}
end)

spawn(function()
    while true do
        if getgenv().spamrockets and not spamconnection then
            startspam()
        elseif not getgenv().spamrockets and spamconnection then
            spamconnection:Disconnect()
            spamconnection = nil
        end
        task.wait(0.1)
    end
end)

    getgenv().rpginstanthit = false

    local players = game:GetService("Players")
    local uis = game:GetService("UserInputService")
    local workspace = game:GetService("Workspace")
    local repstorage = game:GetService("ReplicatedStorage")

    local lp = players.LocalPlayer

    local rocketsystem = repstorage:WaitForChild("RocketSystem")
    local firebindable = rocketsystem.Events:WaitForChild("FireRocketBindable")
    local hithremote = rocketsystem.Events:WaitForChild("RocketHit")

    local visualrockets = workspace:WaitForChild("VisualRockets")

    local function getcharacter()
        return lp.Character
    end

    local function getcurrenttool()
        local char = getcharacter()
        if not char then return nil end
        return char:FindFirstChildOfClass("Tool")
    end

    local function getclosestplayer()
        local char = getcharacter()
        if not char then return nil end
            
        local cam = workspace.CurrentCamera
        local campos = cam.CFrame.Position
        local camlook = cam.CFrame.LookVector
            
        local closest = nil
        local bestdist = math.huge
            
        for _, plr in pairs(players:GetPlayers()) do
            if plr ~= lp and plr.Character then
                local targethrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if targethrp and plr.Character:FindFirstChildOfClass("Humanoid") then
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if hum.Health > 0 then
                        local dist = (targethrp.Position - campos).Magnitude
                        if dist < bestdist and dist < 2000 then
                            bestdist = dist
                            closest = targethrp
                        end
                    end
                end
            end
        end
            
        return closest
    end

    local function teleportrocket(rocketname, targetpos, tool)
        task.wait(0.03)
            
        local rocket = visualrockets:FindFirstChild(rocketname)
        if not rocket then
            for _, r in pairs(visualrockets:GetChildren()) do
                if r:GetAttribute("Owner") == lp.Name and r.Name:find("Rocket") then
                    rocket = r
                    break
                end
            end
        end
            
        if rocket then
            local mainpart = rocket:FindFirstChild("MainPart")
            if mainpart then
                mainpart.CFrame = CFrame.new(targetpos)
                    
                task.wait(0.05)
                    
                local args = {
                    {
                        Player = lp,
                        Position = targetpos,
                        Normal = Vector3.new(0, 1, 0),
                        Vehicle = tool,
                        Weapon = tool,
                        HitPart = nil,
                        Target = nil,
                        Label = rocket.Name
                    }
                }
                hithremote:FireServer(unpack(args))
            end
        end
    end

    local oldnamecall
    oldnamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
            
        if method == "Fire" and self == firebindable and rpginstanthit then
            local plr = args[1]
            local fireargs = args[2]
                
            if plr == lp then
                local tool = getcurrenttool()
                if tool and tool.Name == "RPG" then
                    local target = getclosestplayer()
                    if target then
                        local targetpos = target.Position + Vector3.new(0, 2, 0)
                        local label = fireargs.Label or lp.Name .. "Rocket" .. tick()
                        fireargs.Label = label
                            
                        task.spawn(function()
                            teleportrocket(label, targetpos, tool)
                        end)
                    end
                end
            end
                
            setnamecallmethod(method)
            return oldnamecall(self, unpack(args))
        end
            
        setnamecallmethod(method)
        return oldnamecall(self, ...)
    end)

    local otherSection = silentTab:Section("Others")

    local gunSection = silentTab:Section("Gun Mod")

    getgenv().gm_norecoil = false
    getgenv().gm_nospread = false

    if not getgenv()._gm_init then
        getgenv()._gm_init = true

        local acsguns = game:GetService("ReplicatedStorage").Configurations.ACS_Guns
        local orig = {}
        local recoilnums = {"RecoilPunch", "VPunchBase", "HPunchBase", "DPunchBase"}
        local spreadnums = {"MinSpread", "AimInaccuracyStepAmount", "WalkMultiplier", "HipfireSpreadMuitpler", "SwayBase"}

        local function setarr(t, a, b)
            if type(t) == "table" then t[1] = a t[2] = b end
        end

        local function snapshot(s)
            if orig[s] then return end
            local o = {}
            for _, k in ipairs(recoilnums) do o[k] = s[k] end
            for _, k in ipairs(spreadnums) do o[k] = s[k] end
            o.VRecoil = type(s.VRecoil) == "table" and {s.VRecoil[1], s.VRecoil[2]} or nil
            o.HRecoil = type(s.HRecoil) == "table" and {s.HRecoil[1], s.HRecoil[2]} or nil
            orig[s] = o
        end

        local function applyone(s)
            snapshot(s)
            local o = orig[s]

            if getgenv().gm_norecoil then
                setarr(s.VRecoil, 0, 0)
                setarr(s.HRecoil, 0, 0)
                for _, k in ipairs(recoilnums) do if o[k] ~= nil then s[k] = 0 end end
            else
                if o.VRecoil then setarr(s.VRecoil, o.VRecoil[1], o.VRecoil[2]) end
                if o.HRecoil then setarr(s.HRecoil, o.HRecoil[1], o.HRecoil[2]) end
                for _, k in ipairs(recoilnums) do s[k] = o[k] end
            end

            for _, k in ipairs(spreadnums) do
                if getgenv().gm_nospread then
                    if o[k] ~= nil then s[k] = 0 end
                else
                    s[k] = o[k]
                end
            end
        end

        local function restoreall()
            for s, o in pairs(orig) do
                if o.VRecoil then setarr(s.VRecoil, o.VRecoil[1], o.VRecoil[2]) end
                if o.HRecoil then setarr(s.HRecoil, o.HRecoil[1], o.HRecoil[2]) end
                for _, k in ipairs(recoilnums) do s[k] = o[k] end
                for _, k in ipairs(spreadnums) do s[k] = o[k] end
            end
        end

        local wason = false
        task.spawn(function()
            while true do
                if getgenv().gm_norecoil or getgenv().gm_nospread then
                    wason = true
                    for _, g in ipairs(acsguns:GetChildren()) do
                        local set = g:FindFirstChild("Settings")
                        if set then
                            local ok, s = pcall(require, set)
                            if ok and type(s) == "table" then
                                pcall(applyone, s)
                            end
                        end
                    end
                elseif wason then
                    wason = false
                    restoreall()
                end
                task.wait(0.4)
            end
        end)
    end

    gunSection:Toggle("No Recoil", function(state)
        getgenv().gm_norecoil = state
    end, "gm_norecoil")

    gunSection:Toggle("No Spread", function(state)
        getgenv().gm_nospread = state
    end, "gm_nospread")

local ckientmemoryspoof = otherSection:Toggle("Spoof Memory Stats", function(state)
    getgenv().spoofMemory = state
    
    local stats = game:GetService("Stats")
    
    if not getgenv()._originalGetTotal then
        getgenv()._originalGetTotal = stats.GetTotalMemoryUsageMb
    end
    if not getgenv()._originalGetTag then
        getgenv()._originalGetTag = stats.GetMemoryUsageMbForTag
    end
    
    if state then
        hookfunction(stats.GetTotalMemoryUsageMb, function(self, ...)
            if checkcaller() then return getgenv()._originalGetTotal(self, ...) end
            return 800 + math.random(-50, 50)
        end)
        
        hookfunction(stats.GetMemoryUsageMbForTag, function(self, tag, ...)
            if checkcaller() then return getgenv()._originalGetTag(self, tag, ...) end
            local fakeValues = {
                ["LuaHeap"] = 120,
                ["Script"] = 80,
                ["GraphicsTexture"] = 200,
                ["PhysicsParts"] = 100,
                ["Instances"] = 90,
                ["Signals"] = 40,
                ["Sounds"] = 60
            }
            return fakeValues[tostring(tag)] or math.random(50, 150)
        end)
    else
        hookfunction(stats.GetTotalMemoryUsageMb, getgenv()._originalGetTotal)
        hookfunction(stats.GetMemoryUsageMbForTag, getgenv()._originalGetTag)
    end
end, "spoofmemorytoggle")

local atmosphericToggle = otherSection:Toggle("Cool Atmospher", function(state)
getgenv().atmosphere = state

local lighting = game:GetService("Lighting")

if not getgenv()._originalLighting then
    getgenv()._originalLighting = {
        Ambient = lighting.Ambient,
        Brightness = lighting.Brightness,
        ColorShift_Bottom = lighting.ColorShift_Bottom,
        ColorShift_Top = lighting.ColorShift_Top,
        OutdoorAmbient = lighting.OutdoorAmbient,
        ClockTime = lighting.ClockTime,
        Children = {}
    }
    
    for _, child in pairs(lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") then
            table.insert(getgenv()._originalLighting.Children, child:Clone())
        end
    end
end

if getgenv().atmosphere then
    for _, child in pairs(lighting:GetChildren()) do
        if child:IsA("Sky") or child.Name == "CoolSky" then
            child:Destroy()
        end
    end
    
    lighting.Ambient = Color3.fromRGB(70, 70, 85)
    lighting.Brightness = 1.2
    lighting.ColorShift_Bottom = Color3.fromRGB(20, 20, 30)
    lighting.ColorShift_Top = Color3.fromRGB(60, 60, 80)
    lighting.OutdoorAmbient = Color3.fromRGB(50, 50, 65)
    lighting.ClockTime = 20
    
    local sky = Instance.new("Sky")
    sky.Name = "CoolSky"
    sky.SkyboxBk = "rbxassetid://6008304463"
    sky.SkyboxDn = "rbxassetid://6008316157"
    sky.SkyboxFt = "rbxassetid://6008304463"
    sky.SkyboxLf = "rbxassetid://6008304463"
    sky.SkyboxRt = "rbxassetid://6008304463"
    sky.SkyboxUp = "rbxassetid://6008324222"
    sky.StarCount = 3000
    sky.Parent = lighting
    
    local atm = lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
    atm.Name = "CoolAtmosphere"
    atm.Density = 0.25
    atm.Offset = 0
    atm.Color = Color3.fromRGB(120, 120, 150)
    atm.Decay = Color3.fromRGB(60, 60, 80)
    atm.Glare = 0.3
    atm.Haze = 0.2
    atm.Parent = lighting
    
    local cc = lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
    cc.Name = "CoolCorrection"
    cc.Brightness = 0.1
    cc.Contrast = 0.1
    cc.Saturation = 0.1
    cc.TintColor = Color3.fromRGB(220, 220, 255)
    cc.Parent = lighting
    
    local bl = lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
    bl.Name = "CoolBloom"
    bl.Intensity = 0.4
    bl.Size = 24
    bl.Threshold = 0.75
    bl.Parent = lighting
    
else
    lighting.Ambient = getgenv()._originalLighting.Ambient
    lighting.Brightness = getgenv()._originalLighting.Brightness
    lighting.ColorShift_Bottom = getgenv()._originalLighting.ColorShift_Bottom
    lighting.ColorShift_Top = getgenv()._originalLighting.ColorShift_Top
    lighting.OutdoorAmbient = getgenv()._originalLighting.OutdoorAmbient
    lighting.ClockTime = getgenv()._originalLighting.ClockTime
    
    for _, child in pairs(lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") then
            child:Destroy()
        end
    end
    
    for _, child in pairs(getgenv()._originalLighting.Children) do
        child:Clone().Parent = lighting
    end
end
end, "atmosphericToggle")

    local tptobulletstoggle = otherSection:Toggle("Teleport To Bullet", function(state)
    local rs = game:GetService("ReplicatedStorage")
    local players = game:GetService("Players")
    local lp = players.LocalPlayer
    local bulletEvent = rs.BulletFireSystem.BulletHit
    getgenv().teleportToBullet = state

    -- hook once; re-toggling only flips the flag (was stacking a global __namecall hook
    -- every toggle, which taxes EVERY remote call in the game)
    if getgenv()._tpbullet_init then return end
    getgenv()._tpbullet_init = true

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if getgenv().teleportToBullet and method == "FireServer" and self == bulletEvent then
            local hitPosition = args[3]
            if hitPosition then
                lp.Character.HumanoidRootPart.CFrame = CFrame.new(hitPosition)
            end
        end

        return oldNamecall(self, ...)
    end))
    end, "tptobulletstoggle")
--[[
    local label = otherSection:Label("GetMoney using crates")

    local antiaimtoggle = otherSection:Toggle("rejoin after getting kicked", function(state)
    getgenv().autocrate = state

    local plr = game:GetService("Players").LocalPlayer
    local collsrv = game:GetService("CollectionService")
    local cratesrv = game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("PartCrateService"):WaitForChild("RE")

    local cachedcollector = nil

    local function getcollector()
        if cachedcollector and cachedcollector:IsDescendantOf(workspace) then
            return cachedcollector
        end
        
        if not plr.Team then return nil end
        local tycoon = workspace:WaitForChild("Tycoon"):WaitForChild("Tycoons"):FindFirstChild(plr.Team.Name)
        if not tycoon then return nil end
        
        local oil = tycoon:FindFirstChild("Essentials") and tycoon.Essentials:FindFirstChild("Oil Collector")
        cachedcollector = oil and oil:FindFirstChild("Persistant")
        return cachedcollector
    end

    task.spawn(function()
        while true do
            if getgenv().autocrate then
                local collector = getcollector()
                if collector then
                    for _, crate in ipairs(collsrv:GetTagged("PartCrate")) do
                        if crate:IsDescendantOf(workspace) then
                            cratesrv.ExtractCrate:FireServer(crate, collector)
                        end
                    end
                end
            end
            task.wait()
        end
    end)
    end, "autocratetoggle")
    --]]

    local silentHit = silentTab:Section("Rage Settings")

local killauratoggle = silentHit:Toggle("Kill Aura", function(state)
getgenv().enabled3 = state
getgenv().targetpart = "Head"

-- setup once; re-toggling only flips enabled3 (was spawning a new fire-loop each toggle)
if getgenv()._killaura_init then return end
getgenv()._killaura_init = true

local players = game:GetService("Players")
local repstorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local lp = players.LocalPlayer
local cam = workspace.CurrentCamera

local firegunremote = repstorage:WaitForChild("BulletFireSystem"):WaitForChild("FireGun")
local bullethit = repstorage:WaitForChild("BulletFireSystem"):WaitForChild("BulletHit")
local equipremote = repstorage:WaitForChild("ACS_Engine"):WaitForChild("Events"):WaitForChild("Equip")
local firerocket = repstorage:WaitForChild("RocketSystem"):WaitForChild("Events"):WaitForChild("FireRocket")
local rockethit = repstorage:WaitForChild("RocketSystem"):WaitForChild("Events"):WaitForChild("RocketHit")

local currentgun = nil
local currentgundata = nil
local maxdist = 1000
local isrpg = false
local rocketcount = 0

-- Gun data is read LIVE from ACS_Guns each loop (see getgundata below). The old
-- Equip __namecall capture only ran when Equip:FireServer fired, so enabling the aura
-- while already holding a gun left currentgundata nil until a manual re-equip -- that
-- was the "sometimes fires / must re-equip" bug.

local function getequippedgun()
    local char = lp.Character
    if not char then return nil end
    
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            return child
        end
    end
    return nil
end

local function getscreencenterdist(pos)
    local screenpos, visible = cam:WorldToViewportPoint(pos)
    if not visible then return math.huge end
    
    local center = cam.ViewportSize / 2
    local dist = (Vector2.new(screenpos.X, screenpos.Y) - center).Magnitude
    return dist
end

local function isvisible(targetpart)
    if not wallcheck then return true end
    local origin = cam.CFrame.Position
    local direction = (targetpart.Position - origin).Unit * (targetpart.Position - origin).Magnitude
    local raycastparams = RaycastParams.new()
    raycastparams.FilterDescendantsInstances = {lp.Character}
    raycastparams.FilterType = Enum.RaycastFilterType.Blacklist
    local result = workspace:Raycast(origin, direction, raycastparams)
    if result then
        return result.Instance:IsDescendantOf(targetpart.Parent)
    end
    return true
end

local function gettargets()
    local char = lp.Character
    if not char then return {} end
    
    local validtargets = {}
    
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= lp and p.Character then
            local targetchar = p.Character
            local targetpart = targetchar:FindFirstChild(getgenv().targetpart)
            local humanoid = targetchar:FindFirstChild("Humanoid")
            
            if targetpart and humanoid and humanoid.Health > 0 then
                if getgenv().ignoreforcefield and targetchar:FindFirstChildOfClass("ForceField") then
                    continue
                end
                
                if not isvisible(targetpart) then
                    continue
                end
                
                local screendist = getscreencenterdist(targetpart.Position)
                local worlddist = (cam.CFrame.Position - targetpart.Position).Magnitude
                
                if worlddist <= maxdist then
                    table.insert(validtargets, {
                        player = p,
                        character = targetchar,
                        part = targetpart,
                        pos = targetpart.Position,
                        screendist = screendist
                    })
                end
            end
        end
    end
    
    table.sort(validtargets, function(a, b)
        return a.screendist < b.screendist
    end)
    
    local result = {}
    local maxtargets = math.min(getgenv().targetsallowed, #validtargets)
    for i = 1, maxtargets do
        table.insert(result, validtargets[i])
    end
    
    return result
end

local function firenormal(target)
    local gun = getequippedgun()
    if not gun or not currentgundata then return end
    
    local char = lp.Character
    if not char then return end
    
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local secondaryname = "S" .. gun.Name
    local secondary = char:FindFirstChild(secondaryname)
    
    local origin = hrp.Position + Vector3.new(0, 1.5, 0)
    local targetpos = target.pos
    local direction = (targetpos - origin).Unit
    local dist = (targetpos - origin).Magnitude
    local traveltime = dist / currentgundata.BSpeed
    
    local firegunargs = {
        {vector.create(direction.X, direction.Y, direction.Z)},
        gun,
        secondary,
        vector.create(origin.X, origin.Y, origin.Z),
        false
    }
    firegunremote:FireServer(unpack(firegunargs))
    
    local casts = {
        {vector.create(origin.X, origin.Y, origin.Z), vector.create(direction.X, direction.Y, direction.Z), 0},
        {vector.create(targetpos.X, targetpos.Y, targetpos.Z), vector.create(direction.X, direction.Y, direction.Z), traveltime}
    }
    
    local clientvalues = {
        FireRate = currentgundata.FireRate,
        MaxSpread = currentgundata.MaxSpread,
        Mode = currentgundata.Mode,
        MaxRecoilPower = currentgundata.MaxRecoilPower,
        Distance = currentgundata.Distance,
        BSpeed = currentgundata.BSpeed
    }
    
    local bullethitargs = {
        gun,
        target.part,
        vector.create(targetpos.X, targetpos.Y, targetpos.Z),
        casts,
        vector.create(0, 1, 0),
        clientvalues
    }
    
    bullethit:FireServer(unpack(bullethitargs))
end

local function firerpg(target)
    local gun = getequippedgun()
    if not gun or not currentgundata then return end
    
    rocketcount = rocketcount + 1
    local label = lp.Name .. "Rocket" .. rocketcount
    
    local origin = cam.CFrame.Position
    local targetpos = target.pos
    local direction = (targetpos - origin).Unit
    
    local rocketargs = {
        {
            Direction = vector.create(direction.X, direction.Y, direction.Z),
            Settings = {
                expShake = {
                    fadeInTime = 0.05,
                    magnitude = 3,
                    rotInfluence = vector.create(0.4, 0, 0.4),
                    fadeOutTime = 0.5,
                    roughness = 3,
                    posInfluence = vector.create(1, 1, 0)
                },
                gravity = vector.create(0, -20, 0),
                HelicopterDamage = 450,
                FireRate = 15,
                VehicleDamage = 350,
                ExpName = "RPG",
                RocketAmount = 1,
                ExpRadius = 12,
                BoatDamage = 300,
                TankDamage = 300,
                Acceleration = 8,
                ShieldDamage = 170,
                Distance = 4000,
                PlaneDamage = 500,
                GunshipDamage = 170,
                velocity = 200,
                ExplosionDamage = 120
            },
            Origin = vector.create(origin.X, origin.Y, origin.Z),
            RocketModel = repstorage:WaitForChild("RocketSystem"):WaitForChild("Rockets"):WaitForChild("RPG Rocket"),
            Vehicle = gun,
            PlrFired = lp,
            Weapon = gun
        }
    }
    
    firerocket:InvokeServer(unpack(rocketargs))
    
    local hitargs = {
        {
            Normal = vector.create(0, -1, 0),
            Player = lp,
            Label = label,
            HitPart = target.part,
            Vehicle = gun,
            Position = vector.create(targetpos.X, targetpos.Y, targetpos.Z),
            Weapon = gun
        }
    }
    
    rockethit:FireServer(unpack(hitargs))
end

local acsguns = repstorage.Configurations.ACS_Guns
local settingscache = {}

local function getgundata()
    local gun = getequippedgun()
    if not gun then return nil, nil end
    local cfg = acsguns:FindFirstChild(gun.Name)
    local set = cfg and cfg:FindFirstChild("Settings")
    if not set then return gun, nil end
    local data = settingscache[set]
    if not data then
        local ok, s = pcall(require, set)
        if not ok or type(s) ~= "table" then return gun, nil end
        data = s
        settingscache[set] = s
    end
    return gun, data
end

while true do
    if getgenv().enabled3 then
        local gun, data = getgundata()
        if gun and data then
            currentgun = gun
            currentgundata = data
            maxdist = gun:GetAttribute("Distance") or data.Distance or 1000
            isrpg = data.Mode == "RPG"
            local targets = gettargets()
            for _, target in ipairs(targets) do
                if isrpg then
                    firerpg(target)
                else
                    firenormal(target)
                end
            end
        end
    end
    task.wait()
end
end, "killauratoggle")

local wallchecktoggle = silentHit:Toggle("Wall Check", function(state)
getgenv().wallcheck = state
end, "wallchecktoggle")

getgenv().targetsallowed = 1
local allowedtargets = silentHit:Slider("Target Limit", function(value)
getgenv().targetsallowed = value
end, 6, 1, "targetsallowed")

local ignorefieldtoggle = silentHit:Toggle("Ignore Forcefield", function(state)
getgenv().ignoreforcefield = state
end, "ignorefieldtoggle")

local bypassSection = silentTab:Section("Bypasses")

-- Shoot/reload while sprinting: ACS blocks firing when the "Correndo" (running) stance
-- flag is true. That flag does NOT drive walkspeed (verified), so forcing it false lets
-- you shoot/reload mid-sprint without losing sprint speed.
bypassSection:Toggle("Shoot While Sprinting", function(state)
    getgenv().sprintbypass = state
    if getgenv()._sprintbypass_init then return end
    getgenv()._sprintbypass_init = true

    local conns = {}
    local function bind(char)
        for _, c in ipairs(conns) do c:Disconnect() end
        conns = {}
        local stances = char:FindFirstChild("Saude") and char.Saude:FindFirstChild("Stances")
        local correndo = stances and stances:FindFirstChild("Correndo")
        if not correndo then return end
        conns[#conns + 1] = correndo:GetPropertyChangedSignal("Value"):Connect(function()
            if getgenv().sprintbypass and correndo.Value == true then correndo.Value = false end
        end)
        if getgenv().sprintbypass and correndo.Value then correndo.Value = false end
    end

    if lp.Character then bind(lp.Character) end
    lp.CharacterAdded:Connect(function(c) task.wait(0.5) pcall(bind, c) end)
end, "sprintbypass")

-- Keep gun in water: ACS unequips your gun on water entry when the gun's AllowedInWater
-- setting is false (only 1/77 guns allow it). Flip that setting true on every gun.
bypassSection:Toggle("Keep Gun In Water", function(state)
    getgenv().keepguninwater = state
    local acsguns = game:GetService("ReplicatedStorage").Configurations.ACS_Guns
    if not getgenv()._giw_orig then getgenv()._giw_orig = {} end
    for _, g in ipairs(acsguns:GetChildren()) do
        local set = g:FindFirstChild("Settings")
        if set then
            local ok, s = pcall(require, set)
            if ok and type(s) == "table" then
                if getgenv()._giw_orig[s] == nil then getgenv()._giw_orig[s] = s.AllowedInWater end
                s.AllowedInWater = state and true or getgenv()._giw_orig[s]
            end
        end
    end
end, "keepguninwater")

-- No oxygen drain: the OxygenBar client view computes suffocation damage and fires it to
-- the server via OxygenService.SuffocatePlayer:Fire(dmg) (client-authoritative). No-op it.
bypassSection:Toggle("No Oxygen Drain", function(state)
    getgenv().nooxygen = state
    if getgenv()._oxy_init then return end
    getgenv()._oxy_init = true
    pcall(function()
        local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
        local svc = Knit.GetService("OxygenService")
        if svc and svc.SuffocatePlayer and svc.SuffocatePlayer.Fire then
            local orig = svc.SuffocatePlayer.Fire
            svc.SuffocatePlayer.Fire = function(self, ...)
                if getgenv().nooxygen then return end
                return orig(self, ...)
            end
        end
    end)
end, "nooxygen")

local basetab = window:Tab("Base", "rbxassetid://124500005755075")

local miscsection = basetab:Section("Tycoon")

local autocratetoggle = miscsection:Toggle("Auto Build", function(state)
getgenv().autobuy = state

local players = game:GetService("Players")
local lp = players.LocalPlayer
local workspace = game:GetService("Workspace")

local function getTycoonName()
    local team = lp.Team
    if not team then return nil end
    return team.Name
end

local function getTycoonPath()
    local tycoonName = getTycoonName()
    if not tycoonName then return nil end
    local path = workspace:FindFirstChild("Tycoon")
    if not path then return nil end
    path = path:FindFirstChild("Tycoons")
    if not path then return nil end
    path = path:FindFirstChild(tycoonName)
    if not path then return nil end
    path = path:FindFirstChild("UnpurchasedButtons")
    return path
end

    local function getStats()
        local leaderstats = lp:FindFirstChild("leaderstats")
        if not leaderstats then return 0, 0 end
        local cash = leaderstats:FindFirstChild("Cash")
        local rebirths = leaderstats:FindFirstChild("Rebirths")
        local cashVal = tonumber(cash and cash.Value or 0)
        local rebirthVal = tonumber(rebirths and rebirths.Value or 0)
        return cashVal or 0, rebirthVal or 0
    end

    local function getNeonPart(model)
        return model:FindFirstChild("Neon") or model:FindFirstChildWhichIsA("BasePart")
    end

    local function getButtons()
        local tycoonPath = getTycoonPath()
        if not tycoonPath then return {} end
        
        local buttons = {}
        for _, model in ipairs(tycoonPath:GetChildren()) do
            if not model:IsA("Model") then continue end
            local buttonType = model:GetAttribute("ButtonType")
            if not buttonType then continue end
            
            local neon = getNeonPart(model)
            if not neon then continue end
            
            local priceAttr = model:GetAttribute("Price") or 0
            local rebirthAttr = model:GetAttribute("RebirthRequirement") or 0
            
            local data = {
                model = model,
                type = tostring(buttonType),
                neon = neon,
                price = tonumber(priceAttr) or 0,
                rebirthReq = tonumber(rebirthAttr) or 0
            }
            table.insert(buttons, data)
        end
        return buttons
    end

    local function tpTo(pos)
        local char = lp.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        hrp.CFrame = CFrame.new(pos - Vector3.new(0, 0.1, 0))
    end

    task.spawn(function()
        while getgenv().autobuy do
            local cash, rebirths = getStats()
            local buttons = getButtons()
            
            if #buttons == 0 then
                task.wait(0.5)
                continue
            end
            
            local cashButtons = {}
            local rebirthButtons = {}
            
            for _, btn in ipairs(buttons) do
                if btn.type == "Money" or btn.type == "Cash" then
                    if cash >= btn.price then
                        table.insert(cashButtons, btn)
                    end
                elseif btn.type == "Rebirth" then
                    if getgenv().targetrebirth and rebirths >= btn.rebirthReq then
                        table.insert(rebirthButtons, btn)
                    end
                end
            end
            
            if getgenv().targetlowest then
                table.sort(cashButtons, function(a, b) return a.price < b.price end)
            end
            
            for _, btn in ipairs(cashButtons) do
                if not getgenv().autobuy then break end
                while btn.model.Parent and getgenv().autobuy do
                    tpTo(btn.neon.Position)
                    task.wait(0.05)
                end
            end
            
            for _, btn in ipairs(rebirthButtons) do
                if not getgenv().autobuy then break end
                while btn.model.Parent and getgenv().autobuy do
                    tpTo(btn.neon.Position)
                    task.wait(0.05)
                end
            end
            
            task.wait(0.3)
        end
    end)
    end, "autobuildtoggle")

    local targetlowesttoggle = miscsection:Toggle("Target Lowest Price", function(state)
        getgenv().targetlowest = state
    end, "targetlowesttoggle")

    local targetrebirthtoggle = miscsection:Toggle("Target Rebirth Buttons", function(state)
        getgenv().targetrebirth = state
    end, "targetrebirthtoggle")

    local cramsection = basetab:Section("CRAM kill aura")

local cramkillauratoggle = cramsection:Toggle("Enable CRAM Kill Aura", function(state)
getgenv().killAuraEnabled = state

-- notify CRAM ownership status each time it's enabled
if state then
    task.spawn(function()
        local ws = game:GetService("Workspace")
        local lp = game:GetService("Players").LocalPlayer
        local tycoon = lp.Team and ws.Tycoon.Tycoons:FindFirstChild(lp.Team.Name)
        local cf = tycoon and tycoon:FindFirstChild("PurchasedObjects") and tycoon.PurchasedObjects:FindFirstChild("CRAM")
        if cf and cf:FindFirstChild("CRAM") then
            if _G.Notify then _G.Notify("CRAM found for " .. lp.Team.Name .. "success", 4) end
        elseif _G.Notify then
            _G.Notify("You don't own a CRAM", "warning", 4)
        end
    end)
end

if getgenv()._cram_init then return end
getgenv()._cram_init = true

local ws = game:GetService("Workspace")
local rs = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local turretEvent = rs.BulletFireSystem.RegisterTurretHit
local lp = players.LocalPlayer

getgenv().targetHelicopters = false
getgenv().targetVehicles = false
getgenv().targetPlanes = false
getgenv().targetTank = false
getgenv().targetBoats = false
getgenv().targetDrones = false
getgenv().targetPlayers = false
getgenv().ignoreLpVehicles = false
getgenv().cramtracers = false
getgenv().maxdistance = 3200
getgenv().fireCooldown = 0.01
getgenv().shotsPerTarget = 6

local tracerP0, tracerP1, tracerBeam
local function ensureTracer()
    if tracerP0 and tracerP0.Parent then return end
    tracerP0 = Instance.new("Part")
    tracerP0.Anchored = true tracerP0.CanCollide = false tracerP0.Transparency = 1
    tracerP0.Size = Vector3.new(0.2, 0.2, 0.2) tracerP0.Parent = ws.Camera
    tracerP1 = tracerP0:Clone() tracerP1.Parent = ws.Camera
    local a0 = Instance.new("Attachment", tracerP0)
    local a1 = Instance.new("Attachment", tracerP1)
    tracerBeam = Instance.new("Beam")
    tracerBeam.Attachment0 = a0 tracerBeam.Attachment1 = a1
    tracerBeam.FaceCamera = true tracerBeam.Width0 = 0.35 tracerBeam.Width1 = 0.35
    tracerBeam.LightEmission = 1 tracerBeam.LightInfluence = 0
    tracerBeam.Color = ColorSequence.new(Color3.fromRGB(255, 70, 70))
    tracerBeam.Parent = tracerP0
end
local function showTracer(fromPos, toPos)
    ensureTracer()
    tracerP0.Position = fromPos
    tracerP1.Position = toPos
    tracerBeam.Enabled = true
end
local function hideTracer()
    if tracerBeam then tracerBeam.Enabled = false end
end

local function targetName(t)
    local plr = players:GetPlayerFromCharacter(t)
    if plr then return plr.Name end
    local owner = t:GetAttribute("Owner")
    return t.Name .. (owner and (" (" .. owner .. ")") or "")
end

local lastFired = {}
local cachedCram = nil
local cachedSmokePart = nil
local cachedTargetObj = nil

local function getCram()
    if cachedCram and cachedCram:IsDescendantOf(ws) then
        return cachedCram, cachedSmokePart, cachedTargetObj
    end
    local tycoon = ws.Tycoon.Tycoons:FindFirstChild(lp.Team.Name)
    if not tycoon then return nil, nil, nil end
    local cram = tycoon:FindFirstChild("PurchasedObjects") and tycoon.PurchasedObjects:FindFirstChild("CRAM")
    if not cram or not cram:FindFirstChild("CRAM") then return nil, nil, nil end
    cachedCram = cram.CRAM
    cachedSmokePart = cachedCram:FindFirstChild("SmokePart")
    cachedTargetObj = cachedCram:FindFirstChild("Target")
    return cachedCram, cachedSmokePart, cachedTargetObj
end

local function getDistance(pos)
    if lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") and pos then
        return (lp.Character.HumanoidRootPart.Position - pos).Magnitude
    end
    return math.huge
end

local function getClosestTarget()
    local closest = nil
    local closestDist = getgenv().maxdistance
    
    if getgenv().targetPlayers then
        for _, player in ipairs(players:GetPlayers()) do
            if player == lp then continue end
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
                local dist = getDistance(char.HumanoidRootPart.Position)
                if dist < closestDist then
                    closestDist = dist
                    closest = char
                end
            end
        end
    end
    
    if getgenv().targetHelicopters then
        for _, heli in ipairs(ws["Game Systems"]["Helicopter Workspace"]:GetChildren()) do
            if getgenv().ignoreLpVehicles and heli:GetAttribute("Owner") == lp.Name then continue end
            local pos = heli:IsA("Model") and (heli.PrimaryPart and heli.PrimaryPart.Position or heli:GetPivot().Position) or heli.Position
            local dist = getDistance(pos)
            if dist < closestDist then
                closestDist = dist
                closest = heli
            end
        end
    end
    
    if getgenv().targetPlanes then
        for _, plane in ipairs(ws["Game Systems"]["Plane Workspace"]:GetChildren()) do
            if getgenv().ignoreLpVehicles and plane:GetAttribute("Owner") == lp.Name then continue end
            local pos = plane:IsA("Model") and (plane.PrimaryPart and plane.PrimaryPart.Position or plane:GetPivot().Position) or plane.Position
            local dist = getDistance(pos)
            if dist < closestDist then
                closestDist = dist
                closest = plane
            end
        end
    end
    
    if getgenv().targetVehicles then
        for _, veh in ipairs(ws["Game Systems"]["Vehicle Workspace"]:GetChildren()) do
            if getgenv().ignoreLpVehicles and veh:GetAttribute("Owner") == lp.Name then continue end
            local pos = veh:IsA("Model") and (veh.PrimaryPart and veh.PrimaryPart.Position or veh:GetPivot().Position) or veh.Position
            local dist = getDistance(pos)
            if dist < closestDist then
                closestDist = dist
                closest = veh
            end
        end
    end
    
    if getgenv().targetTank then
        for _, tank in ipairs(ws["Game Systems"]["Tank Workspace"]:GetChildren()) do
            if getgenv().ignoreLpVehicles and tank:GetAttribute("Owner") == lp.Name then continue end
            local pos = tank:IsA("Model") and (tank.PrimaryPart and tank.PrimaryPart.Position or tank:GetPivot().Position) or tank.Position
            local dist = getDistance(pos)
            if dist < closestDist then
                closestDist = dist
                closest = tank
            end
        end
    end
    
    if getgenv().targetBoats then
        for _, boat in ipairs(ws["Game Systems"]["Boat Workspace"]:GetChildren()) do
            if getgenv().ignoreLpVehicles and boat:GetAttribute("Owner") == lp.Name then continue end
            local pos = boat:IsA("Model") and (boat.PrimaryPart and boat.PrimaryPart.Position or boat:GetPivot().Position) or boat.Position
            local dist = getDistance(pos)
            if dist < closestDist then
                closestDist = dist
                closest = boat
            end
        end
    end
    
    if getgenv().targetDrones then
        for _, drone in ipairs(ws["Game Systems"]["Drone Workspace"]:GetChildren()) do
            if getgenv().ignoreLpVehicles and drone:GetAttribute("Owner") == lp.Name then continue end
            local pos = drone:IsA("Model") and (drone.PrimaryPart and drone.PrimaryPart.Position or drone:GetPivot().Position) or drone.Position
            local dist = getDistance(pos)
            if dist < closestDist then
                closestDist = dist
                closest = drone
            end
        end
    end
    
    return closest
end

local function setupCramTarget(targetModel)
    local cram, smoke, targetObj = getCram()
    if not cram or not smoke or not targetObj then return false end
    
    cram:SetAttribute("SmokePartPos", smoke.Position)
    cram:SetAttribute("firing", true)
    
    if not cram:GetAttribute("BulletCount") then
        cram:SetAttribute("BulletCount", 1)
    end
    if not cram:GetAttribute("CamDistance") then
        cram:SetAttribute("CamDistance", 40.509)
    end
    if not cram:GetAttribute("CanDeplete") then
        cram:SetAttribute("CanDeplete", true)
    end
    if not cram:GetAttribute("DepressionLimit") then
        cram:SetAttribute("DepressionLimit", 15)
    end
    if not cram:GetAttribute("LookDir") then
        cram:SetAttribute("LookDir", Vector3.new(0, 0, 0))
    end
    if not cram:GetAttribute("Owner") then
        cram:SetAttribute("Owner", lp.Name)
    end
    if not cram:GetAttribute("Spin") then
        cram:SetAttribute("Spin", 0.145)
    end
    
    targetObj.Value = targetModel
    
    if targetModel and targetModel:IsA("Model") and targetModel:FindFirstChild("Humanoid") then
        targetObj:SetAttribute("Targetting", targetModel.Name)
    else
        local ownerName = targetModel and targetModel:GetAttribute("Owner") or "None"
        targetObj:SetAttribute("Targetting", ownerName)
    end
    
    return true
end

local function getHitParts(model, maxParts)
    local parts = {}
    local count = 0
    
    local collision = model:FindFirstChild("Parts") and model.Parts:FindFirstChild("Collision") 
        or model:FindFirstChild("Body") and model.Body:FindFirstChild("Collision")
        or model:FindFirstChild("Collision")
    
    if collision then
        for _, part in ipairs(collision:GetChildren()) do
            if part:IsA("BasePart") then
                table.insert(parts, part)
                count = count + 1
                if count >= maxParts then return parts end
            end
        end
    end
    
    if model:IsA("Model") and model.PrimaryPart and count < maxParts then
        if not table.find(parts, model.PrimaryPart) then
            table.insert(parts, model.PrimaryPart)
        end
    end
    
    return parts
end

local function fireAtTarget(hitPart, smokePart)
    if not hitPart or not smokePart then return end
    local targetPos = hitPart.Position
    local origin = smokePart.Position
    
    local args = {
        [1] = cachedCram,
        [2] = smokePart,
        [3] = cachedCram,
        [4] = {
            ["normal"] = Vector3.new(0, 1, 0),
            ["hitPart"] = hitPart,
            ["origin"] = origin,
            ["hitPoint"] = targetPos,
            ["direction"] = (targetPos - origin).Unit,
        },
        [5] = {
            ["OverheatCount"] = 150,
            ["CooldownTime"] = 4,
            ["BulletSpread"] = 0.8,
            ["FireRate"] = 1000,
        },
    }
    turretEvent:FireServer(unpack(args))
end

local lastNotifiedTarget = nil
task.spawn(function()
    while task.wait(0.1) do
        if not getgenv().killAuraEnabled then
            hideTracer()
            lastNotifiedTarget = nil
            continue
        end

        local cram, smoke, targetObj = getCram()
        if not cram or not smoke or not targetObj then hideTracer() continue end

        local target = getClosestTarget()
        if not target then
            hideTracer()
            lastNotifiedTarget = nil
            continue
        end

        if target ~= lastNotifiedTarget then
            lastNotifiedTarget = target
            if _G.Notify then _G.Notify("CRAM targeting " .. targetName(target), "success", 2) end
        end

        if not setupCramTarget(target) then hideTracer() continue end

        local hitParts = getHitParts(target, getgenv().shotsPerTarget)
        if #hitParts == 0 then
            if target:IsA("Model") and target:FindFirstChild("HumanoidRootPart") then
                hitParts = {target.HumanoidRootPart}
            elseif target:IsA("BasePart") then
                hitParts = {target}
            end
        end

        if getgenv().cramtracers and hitParts[1] then
            showTracer(smoke.Position, hitParts[1].Position)
        else
            hideTracer()
        end

        local now = tick()
        if now - (lastFired[target] or 0) >= getgenv().fireCooldown then
            for _, part in ipairs(hitParts) do
                fireAtTarget(part, smoke)
            end
            lastFired[target] = now
        end
    end
end)
    end, "cramkillauratoggle")

    cramsection:Label("Click Setup once - REQUIRED for kill aura to work", 13, Color3.fromRGB(255, 200, 80))

    cramsection:Button("Setup", function()
        task.spawn(function()
            local ws = game:GetService("Workspace")
            local rs = game:GetService("ReplicatedStorage")
            local lp = game:GetService("Players").LocalPlayer
            local char = lp.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then return end

            local tycoon = lp.Team and ws.Tycoon.Tycoons:FindFirstChild(lp.Team.Name)
            local cf = tycoon and tycoon:FindFirstChild("PurchasedObjects") and tycoon.PurchasedObjects:FindFirstChild("CRAM")
            local cram = cf and cf:FindFirstChild("CRAM")
            if not cram then
                if _G.Notify then _G.Notify("You don't own a CRAM", "warning", 4) end
                return
            end
            local smoke = cram:FindFirstChild("SmokePart")
            local seat = cram:FindFirstChild("Gunner Seat")
            local prompt = seat and seat:FindFirstChildWhichIsA("ProximityPrompt")
            if not (smoke and seat and prompt) then
                if _G.Notify then _G.Notify("CRAM seat not found", "warning", 4) end
                return
            end

            local RTH = rs.BulletFireSystem.RegisterTurretHit
            local ShootLoop = rs.TurretSystem.ShootLoop
            local saved = hrp.CFrame

            -- teleport onto the seat and sit RELIABLY. A single fireproximityprompt
            -- fails (the "Use" prompt has a 0.5s hold and can be disabled) -> hold it,
            -- then fall back to Seat:Sit. Sitting fires the server's SetupTurret to us,
            -- which initializes the turret (the real "arming").
            hrp.CFrame = seat.CFrame + Vector3.new(0, 3, 0)
            task.wait(0.4)
            local st = tick()
            repeat fireproximityprompt(prompt) task.wait(0.1) until hum.SeatPart == seat or tick() - st > 2.5
            if hum.SeatPart ~= seat then
                pcall(function() seat.Disabled = false seat:Sit(hum) end)
                task.wait(0.4)
            end

            if hum.SeatPart == seat then
                -- A simulated M1 was landing on the BSMT panel (so it never fired). Hide the
                -- hub during the click so it reaches the GAME, do a real M1, then restore it.
                -- Also fire the turret remotes as a fallback while we're the seated operator.
                local hub
                pcall(function() hub = (gethui and gethui() or game:GetService("CoreGui")):FindFirstChild("BSMT") end)
                local hubOn = hub and hub.Enabled
                if hub then hub.Enabled = false end

                local vim = game:GetService("VirtualInputManager")
                local vp = ws.CurrentCamera.ViewportSize
                pcall(function() vim:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 0) end)

                ShootLoop:FireServer(smoke, true)
                task.wait(0.2)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { cram, char }
                local dir = smoke.CFrame.LookVector
                local res = workspace:Raycast(smoke.Position, dir * 2000, rp)
                local hitPart = res and res.Instance or workspace.Terrain
                local hitPoint = res and res.Position or (smoke.Position + dir * 800)
                for _ = 1, 4 do
                    RTH:FireServer(cram, smoke, cram, {
                        normal = Vector3.new(0, 1, 0), hitPart = hitPart, origin = smoke.Position,
                        hitPoint = hitPoint, direction = dir,
                    }, { OverheatCount = 150, CooldownTime = 4, BulletSpread = 0.8, FireRate = 1000 })
                    task.wait(0.12)
                end
                task.wait(0.2)
                pcall(function() vim:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 0) end)
                pcall(function() ShootLoop:FireServer(smoke, false) end)
                if hub then hub.Enabled = hubOn end

                hum.Sit = false
                hum.Jump = true
                task.wait(0.5)
                hrp.CFrame = saved
                if _G.Notify then _G.Notify("CRAM Kill Aura armed", "success", 3) end
            else
                hrp.CFrame = saved
                if _G.Notify then _G.Notify("Failed to seat in CRAM - try again", "warning", 4) end
            end
        end)
    end)

    cramsection:Toggle("Bullet Tracers", function(state)
        getgenv().cramtracers = state
    end, "cramtracertoggle")

    local targetPlayerToggle = cramsection:Toggle("Target Players", function(state)
        getgenv().targetPlayers = state
    end, "targetPlayerToggle")

    local targetHelicoptersToggle = cramsection:Toggle("Target Helicopters", function(state)
        getgenv().targetHelicopters = state
    end, "targetHelicoptersToggle")

    local targetVehiclesToggle = cramsection:Toggle("Target Vehicles", function(state)
        getgenv().targetVehicles = state
    end, "targetVehiclesToggle")

    local targetPlanesToggle = cramsection:Toggle("Target Planes", function(state)
        getgenv().targetPlanes = state
    end, "targetPlanesToggle")

    local targetTankToggle = cramsection:Toggle("Target Tanks", function(state)
        getgenv().targetTank = state
    end, "targetTankToggle")

    local targetBoatsToggle = cramsection:Toggle("Target Boats", function(state)
        getgenv().targetBoats = state
    end, "targetBoatsToggle")

    local targetDronesToggle = cramsection:Toggle("Target Drones", function(state)
        getgenv().targetDrones = state
    end, "targetDronesToggle")

    local ignoreLpVehiclesToggle = cramsection:Toggle("Ignore LP Vehicles", function(state)
        getgenv().ignoreLpVehicles = state
    end, "ignoreLpVehiclesToggle")

    local worldtab = window:Tab("World", "rbxassetid://140129746926995")

    local shitshection = worldtab:Section("Allerts")

    local grenadetoggle = shitshection:Toggle("Grenade Alert", function(state)
    getgenv().grenadealert = state

    local players = game:GetService("Players")
    local validGrenades = {
        ["Smoke Grenade"] = true,
        ["Frag Grenade"] = true,
        ["Impact Grenade"] = true,
        ["Gas Grenade"] = true
    }

    local function setupCharacter(char)
        local player = players:GetPlayerFromCharacter(char)
        if not player then return end
        
        char.DescendantRemoving:Connect(function(desc)
            if not getgenv().grenadealert then return end 
            if desc:IsA("RemoteEvent") and desc.Name == "GrenadeThrow" then
                local tool = desc.Parent
                if tool and tool:IsA("Tool") and validGrenades[tool.Name] then
                    task.delay(0.1, function()
                        if not tool.Parent then
                            _G.Notify(player.Name .. " throwed a " .. tool.Name, "success", 3)
                        end
                    end)
                end
            end
        end)
    end

    for _, player in ipairs(players:GetPlayers()) do
        if player.Character then
            setupCharacter(player.Character)
        end
        player.CharacterAdded:Connect(setupCharacter)
    end

    players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(setupCharacter)
    end)
    end, "grenadetoggle")

local airdroptoggle = shitshection:Toggle("Airdrop Alert", function(state)
getgenv().airdropNotifier = state

local rs = game:GetService("ReplicatedStorage")
local mapService = rs.Packages.Knit.Services.MapService.RE.CreateMapObject

mapService.OnClientEvent:Connect(function(icon, data)
    if not getgenv().airdropNotifier then return end
    if type(data) == "table" and data.imageId == "Airdrop" then
        _G.Notify("An airdrop has been spawned ID = " .. tostring(data.objectId), "success", 5)
    end
end)
end, "airdroptoggle")

local obstacletoggle = shitshection:Toggle("Obstacle Hit Alert", function(state)
getgenv().obstacleNotifier = state

game:GetService("ReplicatedStorage").Remotes.ObstacleRemotes.HitObstacleRemote.OnClientEvent:Connect(function(...)
    if not getgenv().obstacleNotifier then return end
    local args = {...}
    local player = args[1]
    if type(player) == "userdata" and player:IsA("Player") then
        _G.Notify(player.Name .. " hit an obstacle", "warning", 2)
    end
end)
end, "obstacletoggle")

local cratesection = worldtab:Section("Crates")

local autostealtoggle = cratesection:Toggle("Auto Farm", function(state)
getgenv().autofarm = state
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

-- Crates/airdrops were relocated in the update: they are now Models under
-- Workspace["Game Systems"]["Collectibles Workspace"].PartCrate / .AirDrop
-- (each has MainPart + PromptPart[ProximityPrompt "Pick Up"] + a Disabled attribute;
-- crates also carry an Owner attribute). Carrying one welds Character.CrateWeld, and
-- selling at the Oil Collector's CratePromptPart flips the item's Disabled -> true.
if not getgenv()._autofarm_init then
getgenv()._autofarm_init = true

local function collectibles()
    return Workspace["Game Systems"]:FindFirstChild("Collectibles Workspace")
end

local function tp(pos)
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CFrame = CFrame.new(pos) end
end

local function carrying()
    local char = lp.Character
    return char ~= nil and char:FindFirstChild("CrateWeld") ~= nil
end

local function itemPart(item)
    return item:FindFirstChild("MainPart") or item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
end

local function collectorPrompt()
    if not lp.Team then return nil, nil end
    local tycoon = Workspace.Tycoon.Tycoons:FindFirstChild(lp.Team.Name)
    local ess = tycoon and tycoon:FindFirstChild("Essentials")
    local oil = ess and ess:FindFirstChild("Oil Collector")
    local per = oil and oil:FindFirstChild("Persistant")
    local part = per and per:FindFirstChild("CratePromptPart")
    if not part then return nil, nil end
    return part:FindFirstChildWhichIsA("ProximityPrompt", true), part
end

local function nearest()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local col = collectibles()
    if not col then return nil end
    local folders = {}
    if getgenv().crate then local f = col:FindFirstChild("PartCrate") if f then folders[#folders+1] = f end end
    if getgenv().airdrop then local f = col:FindFirstChild("AirDrop") if f then folders[#folders+1] = f end end
    local best, target = math.huge, nil
    for _, folder in ipairs(folders) do
        for _, item in ipairs(folder:GetChildren()) do
            if item:IsA("Model") and not item:GetAttribute("Disabled") and item:GetAttribute("Owner") ~= lp.Name then
                local part = itemPart(item)
                if part then
                    local d = (part.Position - hrp.Position).Magnitude
                    if d < best then best = d target = item end
                end
            end
        end
    end
    return target
end

local notified = false

task.spawn(function()
    while true do
        if getgenv().autofarm and (getgenv().crate or getgenv().airdrop) then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if char and hum and hum.Health > 0 then
                if carrying() then
                    -- carried the crate: TP to the extract point and hold there 7s
                    -- (the collector needs the crate present a moment before it will sell), then extract
                    local prompt, part = collectorPrompt()
                    if prompt and part then
                        local waited = 0
                        while waited < 7 and carrying() and getgenv().autofarm do
                            tp(part.Position + Vector3.new(0, 3, 0))
                            task.wait(0.5)
                            waited = waited + 0.5
                        end
                        if carrying() then
                            local t = tick()
                            repeat fireproximityprompt(prompt) task.wait(0.1) until not carrying() or tick() - t > 3
                        end
                    else
                        task.wait(0.5)
                    end
                else
                    -- pick up nearest available item
                    local target = nearest()
                    if target then
                        notified = false
                        local part = itemPart(target)
                        local pp = target:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if part and pp then
                            tp(part.Position + Vector3.new(0, 3, 0))
                            task.wait(0.25)
                            local t = tick()
                            repeat fireproximityprompt(pp) task.wait(0.1)
                            until carrying() or not target.Parent or target:GetAttribute("Disabled") or tick() - t > 3
                        end
                    elseif not notified then
                        notified = true
                        if _G.Notify then _G.Notify("no crates/airdrops available", "warning", 3) end
                    end
                end
            end
        end
        task.wait(0.15)
    end
end)
end
end, "autostealtoggle")

local cratefarm = cratesection:Toggle("target Crates", function(value)
getgenv().crate = value
end, "cratefarm")

local airdropfarm = cratesection:Toggle("target Airdrops", function(value)
getgenv().airdrop = value
end, "airdropfarm")

local espsectionworld = worldtab:Section("ESP")

local crateesptoggle = espsectionworld:Toggle("Crate ESP", function(state)
getgenv().crateespenabled = state

if getgenv()._crateesp_init then return end
getgenv()._crateesp_init = true

local rs = game:GetService("RunService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local lp = players.LocalPlayer
local cam = workspace.CurrentCamera

-- crates relocated: Models under Collectibles Workspace.PartCrate (was MeshParts under
-- Crate Workspace). Position from MainPart; "Stolen" is gone -> Disabled==true = taken.
local function cratefolder()
    local col = workspace["Game Systems"]:FindFirstChild("Collectibles Workspace")
    return col and col:FindFirstChild("PartCrate")
end

local function cratePart(crate)
    return crate:FindFirstChild("MainPart") or crate.PrimaryPart or crate:FindFirstChild("CrateMesh")
end

local esps = {}

local function createesp(crate)
    local name = Drawing.new("Text")
    name.Visible = false
    name.Size = 14
    name.Center = true
    name.Outline = true

    local dist = Drawing.new("Text")
    dist.Visible = false
    dist.Size = 13
    dist.Center = true
    dist.Outline = true

    local stolen = Drawing.new("Text")
    stolen.Visible = false
    stolen.Size = 13
    stolen.Center = true
    stolen.Outline = true

    return {name = name, dist = dist, stolen = stolen, crate = crate}
end

local function updateesp(data)
    local crate = data.crate
    if not crate or not crate.Parent then return false end
    local part = cratePart(crate)
    if not part then return false end

    local pos = part.Position
    local screenpos, visible = cam:WorldToViewportPoint(pos)

    if not visible or screenpos.Z < 0 then
        data.name.Visible = false
        data.dist.Visible = false
        data.stolen.Visible = false
        return true
    end

    local taken = crate:GetAttribute("Disabled") == true
    local color = taken and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(125, 120, 255)

    local yoffset = screenpos.Y - 30

    if getgenv().cratename then
        data.name.Text = crate.Name:gsub("_%d+$", "")
        data.name.Position = Vector2.new(screenpos.X, yoffset)
        data.name.Color = color
        data.name.Visible = true
        yoffset = yoffset - 16
    else
        data.name.Visible = false
    end

    if getgenv().isstolen then
        data.stolen.Text = taken and "Taken" or "Available"
        data.stolen.Position = Vector2.new(screenpos.X, yoffset)
        data.stolen.Color = taken and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(150, 255, 150)
        data.stolen.Visible = true
        yoffset = yoffset - 16
    else
        data.stolen.Visible = false
    end

    if getgenv().cratedistance then
        local distance = math.floor((cam.CFrame.Position - pos).Magnitude)
        data.dist.Text = tostring(distance) .. "m"
        data.dist.Position = Vector2.new(screenpos.X, screenpos.Y + 15)
        data.dist.Color = color
        data.dist.Visible = true
    else
        data.dist.Visible = false
    end

    return true
end

local function cleanesp(data)
    data.name:Remove()
    data.dist:Remove()
    data.stolen:Remove()
end

rs.RenderStepped:Connect(function()
    local folder = cratefolder()
    if not getgenv().crateespenabled or not folder then
        for _, data in pairs(esps) do
            data.name.Visible = false
            data.dist.Visible = false
            data.stolen.Visible = false
        end
        if not folder then
            for crate, data in pairs(esps) do cleanesp(data) esps[crate] = nil end
        end
        return
    end

    local currentcrates = {}
    for _, crate in ipairs(folder:GetChildren()) do
        if crate:IsA("Model") and cratePart(crate) then
            if not (getgenv().ignorelpscrates and crate:GetAttribute("Owner") == lp.Name) then
                currentcrates[crate] = true
                if not esps[crate] then
                    esps[crate] = createesp(crate)
                end
            end
        end
    end

    for crate, data in pairs(esps) do
        if not currentcrates[crate] then
            cleanesp(data)
            esps[crate] = nil
        else
            if not updateesp(data) then
                cleanesp(data)
                esps[crate] = nil
            end
        end
    end
end)
end, "crateesptoggle")

local crateespname = espsectionworld:Toggle("Show Name", function(state)
getgenv().cratename = state
end, "crateespname")

local crateespdist = espsectionworld:Toggle("Show Distance", function(state)
getgenv().cratedistance = state
end, "crateespdist")

local crateespstolen = espsectionworld:Toggle("Show Stolen Status", function(state)
getgenv().isstolen = state
end, "crateespstolen")

local ignorelpscratestoggle = espsectionworld:Toggle("Ignore LP Crates", function(state)
getgenv().ignorelpscrates = state
end, "ignorelpscratestoggle")

local espTab = window:Tab("Visuals", "rbxassetid://138133764615657")
local espSection = espTab:Section("ESP")

espSection:Toggle("Enable ESP", function(v)
getgenv().enableesp = v

if getgenv()._esp_init then return end
getgenv()._esp_init = true

getgenv().esp_name = false
getgenv().esp_box = false
getgenv().esp_boxstyle = "Full"
getgenv().esp_health = false
getgenv().esp_skeleton = false
getgenv().esp_tracers = false
getgenv().esp_distance = false
getgenv().esp_tracerOrigin = "Bottom"
getgenv().esp_tracercolor = Color3.fromRGB(255, 255, 255)
getgenv().esp_traceroutlinecolor = Color3.fromRGB(0, 0, 0)

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer
local Camera           = Workspace.CurrentCamera

local ESPObjects = {}

local R15_BONES = {
    {"Head",          "UpperTorso"},
    {"UpperTorso",    "LowerTorso"},
    {"LowerTorso",    "LeftUpperLeg"},
    {"LeftUpperLeg",  "LeftLowerLeg"},
    {"LeftLowerLeg",  "LeftFoot"},
    {"LowerTorso",    "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"},
    {"UpperTorso",    "LeftUpperArm"},
    {"LeftUpperArm",  "LeftLowerArm"},
    {"LeftLowerArm",  "LeftHand"},
    {"UpperTorso",    "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
}

local R6_BONES_FN = {
    function(c) 
        local h = c:FindFirstChild("Head")
        local t = c:FindFirstChild("Torso")
        if not h or not t then return nil end
        return (h.CFrame * CFrame.new(0, -h.Size.Y/2, 0)).Position,
               (t.CFrame * CFrame.new(0,  t.Size.Y/2, 0)).Position
    end,
    function(c) 
        local t = c:FindFirstChild("Torso")
        if not t then return nil end
        return (t.CFrame * CFrame.new(0,  t.Size.Y/2, 0)).Position,
               (t.CFrame * CFrame.new(0, -t.Size.Y/2, 0)).Position
    end,
    function(c) 
        local t  = c:FindFirstChild("Torso")
        local la = c:FindFirstChild("Left Arm")
        if not t or not la then return nil end
        return (t.CFrame  * CFrame.new(-t.Size.X/2,  t.Size.Y/2 - 0.5, 0)).Position,
               (la.CFrame * CFrame.new(0, -la.Size.Y/2, 0)).Position
    end,
    function(c) 
        local t  = c:FindFirstChild("Torso")
        local ra = c:FindFirstChild("Right Arm")
        if not t or not ra then return nil end
        return (t.CFrame  * CFrame.new( t.Size.X/2,  t.Size.Y/2 - 0.5, 0)).Position,
               (ra.CFrame * CFrame.new(0, -ra.Size.Y/2, 0)).Position
    end,
    function(c) 
        local t  = c:FindFirstChild("Torso")
        local ll = c:FindFirstChild("Left Leg")
        if not t or not ll then return nil end
        return (t.CFrame  * CFrame.new(-t.Size.X/4, -t.Size.Y/2, 0)).Position,
               (ll.CFrame * CFrame.new(0, -ll.Size.Y/2, 0)).Position
    end,
    function(c) 
        local t  = c:FindFirstChild("Torso")
        local rl = c:FindFirstChild("Right Leg")
        if not t or not rl then return nil end
        return (t.CFrame  * CFrame.new( t.Size.X/4, -t.Size.Y/2, 0)).Position,
               (rl.CFrame * CFrame.new(0, -rl.Size.Y/2, 0)).Position
    end,
}

local MAX_BONES = math.max(#R15_BONES, #R6_BONES_FN)

local function CreateDrawing(Type, Properties)
    local obj = Drawing.new(Type)
    for k, v in pairs(Properties) do obj[k] = v end
    return obj
end

local function newLine(thick, zindex)
    return CreateDrawing("Line", {Thickness=thick, Color=Color3.new(1,1,1), Visible=false, ZIndex=zindex or 2})
end

local function newSkelPair()
    return {
        Main    = CreateDrawing("Line", {Thickness=1.5, Color=Color3.new(1,1,1),        Visible=false, ZIndex=3}),
        Outline = CreateDrawing("Line", {Thickness=3,   Color=Color3.fromRGB(15,15,15), Visible=false, ZIndex=2}),
        _from = Vector2.new(0,0),
        _to   = Vector2.new(0,0),
        _init = false,
    }
end

local function IsPlayerValid(Player)
    if not Player or not Player.Parent then return false end
    if Player == LocalPlayer then return false end
    return true
end

local function IsCharacterValid(Character)
    if not Character or not Character.Parent then return false end
    local hum = Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function GetTracerOrigin()
    local o = getgenv().esp_tracerOrigin
    if     o == "Bottom" then return Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
    elseif o == "Top"    then return Vector2.new(Camera.ViewportSize.X/2, 0)
    elseif o == "Mouse"  then return UserInputService:GetMouseLocation()
    else                      return Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2) end
end

local function WorldToScreen(pos)
    local sp, on = Camera:WorldToViewportPoint(pos)
    if not on or sp.Z <= 0 then return nil end
    return Vector2.new(sp.X, sp.Y), sp.Z
end

local function setLine(line, from, to, color)
    line.From = from
    line.To   = to
    if color then line.Color = color end
    line.Visible = true
end

local function makeBoxLines(thick, zindex)
    local t = {}
    for _, k in ipairs({"Top","Bottom","Left","Right","TopLeft","TopRight","BottomLeft","BottomRight"}) do
        t[k] = CreateDrawing("Line", {Thickness=thick, Color=Color3.new(1,1,1), Visible=false, ZIndex=zindex})
    end
    return t
end

local function CreateESPObject(Player)
    if not IsPlayerValid(Player) then return end

    local skelLines = {}
    for i = 1, MAX_BONES do skelLines[i] = newSkelPair() end

    ESPObjects[Player] = {
        BoxLines        = makeBoxLines(1.2, 3),
        BoxOutlines     = makeBoxLines(2.4, 2),
        Box3DBack       = {Top=newLine(1,3), Bottom=newLine(1,3), Left=newLine(1,3), Right=newLine(1,3)},
        Box3DBackOut    = {Top=newLine(2,2), Bottom=newLine(2,2), Left=newLine(2,2), Right=newLine(2,2)},
        Box3DConnectors = {TL=newLine(1,3), TR=newLine(1,3), BL=newLine(1,3), BR=newLine(1,3)},
        Box3DConnOut    = {TL=newLine(2,2), TR=newLine(2,2), BL=newLine(2,2), BR=newLine(2,2)},
        Tracer        = CreateDrawing("Line",   {Thickness=1.2, Color=Color3.new(1,1,1), Visible=false, ZIndex=3}),
        TracerOutline = CreateDrawing("Line",   {Thickness=2.4, Color=Color3.new(0,0,0), Visible=false, ZIndex=2}),
        NameText      = CreateDrawing("Text",   {Text=Player.Name, Size=14, Center=true, Outline=true, OutlineColor=Color3.fromRGB(15,15,15), Color=Color3.new(1,1,1), Visible=false, ZIndex=4}),
        DistanceText  = CreateDrawing("Text",   {Text="0m", Size=12, Center=true, Outline=true, OutlineColor=Color3.fromRGB(15,15,15), Color=Color3.fromRGB(200,200,200), Visible=false, ZIndex=4}),
        HealthBarBg   = CreateDrawing("Square", {Thickness=1, Filled=true, Color=Color3.fromRGB(20,20,20), Visible=false, ZIndex=2}),
        HealthBar     = CreateDrawing("Square", {Thickness=1, Filled=true, Color=Color3.fromRGB(0,255,0),  Visible=false, ZIndex=3}),
        HeadCircle    = CreateDrawing("Circle", {Thickness=1.2, Color=Color3.new(1,1,1),        Visible=false, ZIndex=3, Filled=false, NumSides=32}),
        HeadCircleOut = CreateDrawing("Circle", {Thickness=2.4, Color=Color3.fromRGB(15,15,15), Visible=false, ZIndex=2, Filled=false, NumSides=32}),
        SkeletonLines = skelLines,
    }
end

local function RemoveESPObject(Player)
    local d = ESPObjects[Player]
    if not d then return end
    for _, l in pairs(d.BoxLines)        do l:Remove() end
    for _, l in pairs(d.BoxOutlines)     do l:Remove() end
    for _, l in pairs(d.Box3DBack)       do l:Remove() end
    for _, l in pairs(d.Box3DBackOut)    do l:Remove() end
    for _, l in pairs(d.Box3DConnectors) do l:Remove() end
    for _, l in pairs(d.Box3DConnOut)    do l:Remove() end
    d.Tracer:Remove()      d.TracerOutline:Remove()
    d.NameText:Remove()    d.DistanceText:Remove()
    d.HealthBarBg:Remove() d.HealthBar:Remove()
    d.HeadCircle:Remove()  d.HeadCircleOut:Remove()
    for _, pair in ipairs(d.SkeletonLines) do pair.Outline:Remove() pair.Main:Remove() end
    ESPObjects[Player] = nil
end

local function HideAll(d)
    for _, l in pairs(d.BoxLines)        do l.Visible = false end
    for _, l in pairs(d.BoxOutlines)     do l.Visible = false end
    for _, l in pairs(d.Box3DBack)       do l.Visible = false end
    for _, l in pairs(d.Box3DBackOut)    do l.Visible = false end
    for _, l in pairs(d.Box3DConnectors) do l.Visible = false end
    for _, l in pairs(d.Box3DConnOut)    do l.Visible = false end
    d.Tracer.Visible = false      d.TracerOutline.Visible = false
    d.NameText.Visible = false    d.DistanceText.Visible = false
    d.HealthBarBg.Visible = false d.HealthBar.Visible = false
    d.HeadCircle.Visible = false  d.HeadCircleOut.Visible = false
    for _, pair in ipairs(d.SkeletonLines) do
        pair.Outline.Visible = false
        pair.Main.Visible    = false
    end
end

local function GetBodyBounds(char)
    local parts = {
        "Head","UpperTorso","LowerTorso",
        "LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm","LeftHand","RightHand",
        "LeftUpperLeg","RightUpperLeg","LeftLowerLeg","RightLowerLeg","LeftFoot","RightFoot",
        "Torso","Left Arm","Right Arm","Left Leg","Right Leg",
    }
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local found = false
    for _, name in ipairs(parts) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            local pcf = p.CFrame
            local hs  = p.Size * 0.5
            for _, ox in ipairs({-1,1}) do for _, oy in ipairs({-1,1}) do for _, oz in ipairs({-1,1}) do
                local sp = WorldToScreen(pcf:PointToWorldSpace(Vector3.new(ox*hs.X, oy*hs.Y, oz*hs.Z)))
                if sp then
                    found = true
                    if sp.X < minX then minX = sp.X end if sp.Y < minY then minY = sp.Y end
                    if sp.X > maxX then maxX = sp.X end if sp.Y > maxY then maxY = sp.Y end
                end
            end end end
        end
    end
    if not found then return nil end
    return minX-2, minY-2, (maxX-minX)+4, (maxY-minY)+4
end

local function DrawBone(pair, posA, posB, thick, alpha, LERP)
    local spA = WorldToScreen(posA)
    local spB = WorldToScreen(posB)
    if not spA or not spB then
        pair.Outline.Visible = false
        pair.Main.Visible    = false
        return
    end
    if not pair._init then
        pair._from = spA
        pair._to   = spB
        pair._init = true
    else
        pair._from = pair._from:Lerp(spA, LERP)
        pair._to   = pair._to:Lerp(spB, LERP)
    end
    pair.Outline.From = pair._from  pair.Outline.To = pair._to
    pair.Outline.Color = Color3.fromRGB(15,15,15)
    pair.Outline.Thickness = math.clamp(thick*2, 1.2, 5)
    pair.Outline.Transparency = alpha
    pair.Outline.Visible = true
    pair.Main.From = pair._from  pair.Main.To = pair._to
    pair.Main.Color = Color3.new(1,1,1)
    pair.Main.Thickness = thick
    pair.Main.Transparency = alpha
    pair.Main.Visible = true
end

local function UpdateSkeleton(d, char, Distance)
    local hum       = char:FindFirstChildOfClass("Humanoid")
    local isR6      = hum and hum.RigType == Enum.HumanoidRigType.R6
    local distScale = math.clamp(1 / (Distance * 0.018), 0.4, 2)
    local alpha     = math.clamp(1 - (Distance / 900), 0.15, 1)
    local thick     = math.clamp(1.5 * distScale, 0.6, 3)
    local LERP      = 0.35

    if isR6 then
        for i, boneFn in ipairs(R6_BONES_FN) do
            local pair = d.SkeletonLines[i]
            local posA, posB = boneFn(char)
            if posA and posB then
                DrawBone(pair, posA, posB, thick, alpha, LERP)
            else
                pair.Outline.Visible = false
                pair.Main.Visible    = false
            end
        end
        for i = #R6_BONES_FN + 1, MAX_BONES do
            d.SkeletonLines[i].Outline.Visible = false
            d.SkeletonLines[i].Main.Visible    = false
        end
    else
        for i, bone in ipairs(R15_BONES) do
            local pair = d.SkeletonLines[i]
            local pA   = char:FindFirstChild(bone[1])
            local pB   = char:FindFirstChild(bone[2])
            if pA and pB and pA:IsA("BasePart") and pB:IsA("BasePart") then
                DrawBone(pair, pA.Position, pB.Position, thick, alpha, LERP)
            else
                pair.Outline.Visible = false
                pair.Main.Visible    = false
            end
        end
        -- hide unused R6 slots
        for i = #R15_BONES + 1, MAX_BONES do
            d.SkeletonLines[i].Outline.Visible = false
            d.SkeletonLines[i].Main.Visible    = false
        end
    end

    -- Head circle
    local head = char:FindFirstChild("Head")
    if head then
        local spH, depth = WorldToScreen(head.Position)
        if spH and depth then
            local worldRadius  = (head.Size.X + head.Size.Y + head.Size.Z) / 6
            local fov          = math.rad(Camera.FieldOfView)
            local screenRadius = math.clamp(
                (worldRadius / (depth * math.tan(fov/2))) * (Camera.ViewportSize.Y/2),
                2, 60
            )
            d.HeadCircleOut.Position     = spH
            d.HeadCircleOut.Radius       = screenRadius + 1.2
            d.HeadCircleOut.Color        = Color3.fromRGB(15,15,15)
            d.HeadCircleOut.Transparency = alpha
            d.HeadCircleOut.Visible      = true
            d.HeadCircle.Position     = spH
            d.HeadCircle.Radius       = screenRadius
            d.HeadCircle.Color        = Color3.new(1,1,1)
            d.HeadCircle.Transparency = alpha
            d.HeadCircle.Visible      = true
        else
            d.HeadCircle.Visible = false d.HeadCircleOut.Visible = false
        end
    else
        d.HeadCircle.Visible = false d.HeadCircleOut.Visible = false
    end
end

RunService.RenderStepped:Connect(function()
    for Player, d in pairs(ESPObjects) do
        if not getgenv().enableesp or not IsPlayerValid(Player) then
            HideAll(d) continue
        end

        local char = Player.Character
        if not IsCharacterValid(char) then HideAll(d) continue end

        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        if not hrp then HideAll(d) continue end

        local bx, by, bw, bh = GetBodyBounds(char)
        if not bx then HideAll(d) continue end

        if not WorldToScreen(hrp.Position) then HideAll(d) continue end

        local Distance = (Camera.CFrame.Position - hrp.Position).Magnitude

        for _, l in pairs(d.BoxLines)        do l.Visible = false end
        for _, l in pairs(d.BoxOutlines)     do l.Visible = false end
        for _, l in pairs(d.Box3DBack)       do l.Visible = false end
        for _, l in pairs(d.Box3DBackOut)    do l.Visible = false end
        for _, l in pairs(d.Box3DConnectors) do l.Visible = false end
        for _, l in pairs(d.Box3DConnOut)    do l.Visible = false end

        if getgenv().esp_box then
            local style = getgenv().esp_boxstyle
            local tl = Vector2.new(bx,    by)
            local tr = Vector2.new(bx+bw, by)
            local bl = Vector2.new(bx,    by+bh)
            local br = Vector2.new(bx+bw, by+bh)

            if style == "Full" then
                setLine(d.BoxOutlines.Top,    tl,tr) setLine(d.BoxLines.Top,    tl,tr,Color3.new(1,1,1))
                setLine(d.BoxOutlines.Bottom, bl,br) setLine(d.BoxLines.Bottom, bl,br,Color3.new(1,1,1))
                setLine(d.BoxOutlines.Left,   tl,bl) setLine(d.BoxLines.Left,   tl,bl,Color3.new(1,1,1))
                setLine(d.BoxOutlines.Right,  tr,br) setLine(d.BoxLines.Right,  tr,br,Color3.new(1,1,1))

            elseif style == "Corner" then
                local cx = bw * 0.22
                local cy = bh * 0.22
                setLine(d.BoxOutlines.TopLeft,     tl, tl+Vector2.new(cx,0))  setLine(d.BoxLines.TopLeft,     tl, tl+Vector2.new(cx,0),  Color3.new(1,1,1))
                setLine(d.BoxOutlines.Left,        tl, tl+Vector2.new(0,cy))  setLine(d.BoxLines.Left,        tl, tl+Vector2.new(0,cy),  Color3.new(1,1,1))
                setLine(d.BoxOutlines.TopRight,    tr, tr+Vector2.new(-cx,0)) setLine(d.BoxLines.TopRight,    tr, tr+Vector2.new(-cx,0), Color3.new(1,1,1))
                setLine(d.BoxOutlines.Right,       tr, tr+Vector2.new(0,cy))  setLine(d.BoxLines.Right,       tr, tr+Vector2.new(0,cy),  Color3.new(1,1,1))
                setLine(d.BoxOutlines.BottomLeft,  bl, bl+Vector2.new(cx,0))  setLine(d.BoxLines.BottomLeft,  bl, bl+Vector2.new(cx,0),  Color3.new(1,1,1))
                setLine(d.BoxOutlines.Top,         bl, bl+Vector2.new(0,-cy)) setLine(d.BoxLines.Top,         bl, bl+Vector2.new(0,-cy), Color3.new(1,1,1))
                setLine(d.BoxOutlines.BottomRight, br, br+Vector2.new(-cx,0)) setLine(d.BoxLines.BottomRight, br, br+Vector2.new(-cx,0), Color3.new(1,1,1))
                setLine(d.BoxOutlines.Bottom,      br, br+Vector2.new(0,-cy)) setLine(d.BoxLines.Bottom,      br, br+Vector2.new(0,-cy), Color3.new(1,1,1))

            elseif style == "ThreeD" then
                local Size = char:GetExtentsSize()
                local CF   = hrp.CFrame
                local hw,hh,hd = Size.X/2, Size.Y/2, Size.Z/2
                local function proj(ox,oy,oz) return WorldToScreen((CF*CFrame.new(ox,oy,oz)).Position) end
                local ftl=proj(-hw,hh,-hd)  local ftr=proj(hw,hh,-hd)
                local fbl=proj(-hw,-hh,-hd) local fbr=proj(hw,-hh,-hd)
                local btl=proj(-hw,hh,hd)   local btr=proj(hw,hh,hd)
                local bbl=proj(-hw,-hh,hd)  local bbr=proj(hw,-hh,hd)
                if ftl and ftr and fbl and fbr and btl and btr and bbl and bbr then
                    setLine(d.BoxOutlines.Top,     ftl,ftr) setLine(d.BoxLines.Top,     ftl,ftr,Color3.new(1,1,1))
                    setLine(d.BoxOutlines.Bottom,  fbl,fbr) setLine(d.BoxLines.Bottom,  fbl,fbr,Color3.new(1,1,1))
                    setLine(d.BoxOutlines.Left,    ftl,fbl) setLine(d.BoxLines.Left,    ftl,fbl,Color3.new(1,1,1))
                    setLine(d.BoxOutlines.Right,   ftr,fbr) setLine(d.BoxLines.Right,   ftr,fbr,Color3.new(1,1,1))
                    setLine(d.Box3DBackOut.Top,    btl,btr) setLine(d.Box3DBack.Top,    btl,btr,Color3.new(1,1,1))
                    setLine(d.Box3DBackOut.Bottom, bbl,bbr) setLine(d.Box3DBack.Bottom, bbl,bbr,Color3.new(1,1,1))
                    setLine(d.Box3DBackOut.Left,   btl,bbl) setLine(d.Box3DBack.Left,   btl,bbl,Color3.new(1,1,1))
                    setLine(d.Box3DBackOut.Right,  btr,bbr) setLine(d.Box3DBack.Right,  btr,bbr,Color3.new(1,1,1))
                    setLine(d.Box3DConnOut.TL,ftl,btl) setLine(d.Box3DConnectors.TL,ftl,btl,Color3.new(1,1,1))
                    setLine(d.Box3DConnOut.TR,ftr,btr) setLine(d.Box3DConnectors.TR,ftr,btr,Color3.new(1,1,1))
                    setLine(d.Box3DConnOut.BL,fbl,bbl) setLine(d.Box3DConnectors.BL,fbl,bbl,Color3.new(1,1,1))
                    setLine(d.Box3DConnOut.BR,fbr,bbr) setLine(d.Box3DConnectors.BR,fbr,bbr,Color3.new(1,1,1))
                end
            end
        end

        if getgenv().esp_tracers then
            local origin = GetTracerOrigin()
            local dest   = Vector2.new(bx + bw/2, by + bh)
            setLine(d.TracerOutline, origin, dest, getgenv().esp_traceroutlinecolor)
            setLine(d.Tracer,        origin, dest, getgenv().esp_tracercolor)
        else
            d.Tracer.Visible = false d.TracerOutline.Visible = false
        end

        if getgenv().esp_name then
            d.NameText.Position = Vector2.new(bx + bw/2, by - 20)
            d.NameText.Color    = Color3.new(1,1,1)
            d.NameText.Visible  = true
        else
            d.NameText.Visible = false
        end

        if getgenv().esp_distance then
            d.DistanceText.Text     = math.floor(Distance) .. "m"
            d.DistanceText.Position = Vector2.new(bx + bw/2, by + bh + 5)
            d.DistanceText.Visible  = true
        else
            d.DistanceText.Visible = false
        end

        if getgenv().esp_health then
            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local barW  = 4
            local barH  = bh * 0.8
            local barX  = bx - barW - 2
            local barY  = by + (bh - barH) / 2
            local fillH = barH * ratio
            d.HealthBarBg.Size     = Vector2.new(barW, barH)
            d.HealthBarBg.Position = Vector2.new(barX, barY)
            d.HealthBarBg.Visible  = true
            d.HealthBar.Size       = Vector2.new(barW-2, math.max(fillH,1))
            d.HealthBar.Position   = Vector2.new(barX+1, barY+(barH-fillH))
            d.HealthBar.Color      = Color3.fromRGB(math.floor(255*(1-ratio)), math.floor(255*ratio), 0)
            d.HealthBar.Visible    = true
        else
            d.HealthBarBg.Visible = false d.HealthBar.Visible = false
        end

        if getgenv().esp_skeleton then
            UpdateSkeleton(d, char, Distance)
        else
            for _, pair in ipairs(d.SkeletonLines) do
                pair.Outline.Visible = false pair.Main.Visible = false
            end
            d.HeadCircle.Visible = false d.HeadCircleOut.Visible = false
        end
    end
end)

for _, Player in ipairs(Players:GetPlayers()) do
    if Player ~= LocalPlayer then CreateESPObject(Player) end
end
Players.PlayerAdded:Connect(function(Player)
    if Player ~= LocalPlayer then CreateESPObject(Player) end
end)
Players.PlayerRemoving:Connect(RemoveESPObject)
end, "enableesp")

espSection:Toggle("Name", function(v)
getgenv().esp_name = v
end, "name")

espSection:Toggle("Box", function(v)
    getgenv().esp_box = v
end, "box")

espSection:Toggle("Health Bar", function(v)
    getgenv().esp_health = v
end, "health")

espSection:Toggle("Backpack Items", function(v)
    getgenv().esp_backpack = v
end, "backpack")

espSection:Toggle("Skeleton", function(v)
    getgenv().esp_skeleton = v
end, "skeleton")

espSection:Toggle("Tracers", function(v)
    getgenv().esp_tracers = v
end, "tracers")


local boxStyleDrop = espSection:Dropdown("Box Style")

boxStyleDrop:Toggle("Full", function(v)
    if v then getgenv().esp_boxstyle = "Full" end
end, "boxstylefull")

boxStyleDrop:Toggle("Corner", function(v)
    if v then getgenv().esp_boxstyle = "Corner" end
end, "boxstylecorner")

boxStyleDrop:Toggle("ThreeD", function(v)
    if v then getgenv().esp_boxstyle = "ThreeD" end
end, "boxstyle3d")

local tracerDrop = espSection:Dropdown("Tracer Origin")

tracerDrop:Toggle("Bottom", function(v)
    if v then getgenv().esp_tracerOrigin = "Bottom" end
end, "traceroriginbottom")

tracerDrop:Toggle("Top", function(v)
    if v then getgenv().esp_tracerOrigin = "Top" end
end, "tracerorigintop")

tracerDrop:Toggle("Mouse", function(v)
    if v then getgenv().esp_tracerOrigin = "Mouse" end
end, "traceroriginmouse")

tracerDrop:Toggle("Center", function(v)
    if v then getgenv().esp_tracerOrigin = "Center" end
end, "tracerorigincenter")

espSection:ColorWheel("Tracer Color", function(c)
    getgenv().esp_traceroutlinecolor = c
end, "esp_traceroutlinecolor")

local chams = espTab:Section("chams")

local chamsToggle = chams:Toggle("Enable Chams", function(v)
    getgenv().chamsenabled = v
end, "chamsenabled")

chams:ColorWheel("Fill Color", function(c)
    getgenv().chamsfillcolor = c
end, "chamsfillcolor")

chams:ColorWheel("Outline Color", function(c)
    getgenv().chamsoutlinecolor = c
end, "chamsoutlinecolor")

chams:ColorWheel("Occluded Color", function(c)
    getgenv().chamsoccludedcolor = c
end, "chamsoccludedcolor")

chams:Slider("Fill Transparency", function(v)
    getgenv().chamstransparency = v
end, 1, 0.5, "chamstransparency")

chams:Slider("Outline Transparency", function(v)
    getgenv().chamsoutlinetransparency = v
end, 1, 0, "chamsoutlinetransparency")

getgenv().chamsenabled = false
getgenv().chamsfillcolor = Color3.fromRGB(255, 0, 0)
getgenv().chamsoutlinecolor = Color3.fromRGB(255, 255, 255)
getgenv().chamsoccludedcolor = Color3.fromRGB(150, 0, 0)
getgenv().chamstransparency = 0.5
getgenv().chamsoutlinetransparency = 0
local Players = game:GetService("Players")
local Highlights = {}

local function IsValidForChams(Player)
    if not Player or not Player.Parent then return false end
    if Player == LocalPlayer then return false end
    if getgenv().ignoreteam and Player.Team and LocalPlayer.Team and Player.Team == LocalPlayer.Team then return false end
    return true
end

local function IsCharValidForChams(Character)
    if not Character or not Character.Parent then return false end
    local h = Character:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function CreateHighlight(Player)
    if not IsValidForChams(Player) then return end
    if Highlights[Player] then Highlights[Player]:Destroy() end
    local h = Instance.new("Highlight")
    h.Name = "ESP_Highlight"
    h.FillColor = getgenv().chamsfillcolor
    h.OutlineColor = getgenv().chamsoutlinecolor
    h.FillTransparency = getgenv().chamstransparency
    h.OutlineTransparency = getgenv().chamsoutlinetransparency
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Enabled = getgenv().chamsenabled
    Highlights[Player] = h
end

local function RemoveHighlight(Player)
    if Highlights[Player] then Highlights[Player]:Destroy() Highlights[Player] = nil end
end

local function AttachHighlight(Player, Character)
    if not IsValidForChams(Player) then return end
    if Highlights[Player] then
        Highlights[Player].Parent = Character
    end
end

game:GetService("RunService").RenderStepped:Connect(function()
    for Player, Highlight in pairs(Highlights) do
        if not getgenv().chamsenabled then Highlight.Enabled = false continue end
        if not IsValidForChams(Player) then Highlight.Enabled = false continue end
        local char = Player.Character
        if not IsCharValidForChams(char) then Highlight.Enabled = false continue end
        if Highlight.Parent ~= char then Highlight.Parent = char end
        Highlight.FillColor = getgenv().chamsfillcolor
        Highlight.OutlineColor = getgenv().chamsoutlinecolor
        Highlight.FillTransparency = getgenv().chamstransparency
        Highlight.OutlineTransparency = getgenv().chamsoutlinetransparency
        Highlight.Enabled = true
    end
end)

for _, Player in ipairs(Players:GetPlayers()) do
    if Player ~= LocalPlayer then
        CreateHighlight(Player)
        if Player.Character then AttachHighlight(Player, Player.Character) end
        Player.CharacterAdded:Connect(function(char) AttachHighlight(Player, char) end)
    end
end

Players.PlayerAdded:Connect(function(Player)
    if Player ~= LocalPlayer then
        CreateHighlight(Player)
        Player.CharacterAdded:Connect(function(char) AttachHighlight(Player, char) end)
    end
end)

Players.PlayerRemoving:Connect(RemoveHighlight)

local minimapSection = espTab:Section("Minimap")

getgenv().minimapdots = false
getgenv().minimapenemyonly = false

minimapSection:Toggle("Player Dots", function(state)
getgenv().minimapdots = state

if getgenv()._minimap_init then return end
getgenv()._minimap_init = true

local players = game:GetService("Players")
local rs = game:GetService("RunService")
local repfirst = game:GetService("ReplicatedFirst")
local lp = players.LocalPlayer

local render = require(repfirst.Client.Controllers.InterfaceController.Views.HUD.Map.MapConfig).Rendering
local function worldToScale(pos)
    local nx = math.clamp(pos.X / render.XMapRenderSize + render.XMapRenderCenter, render.NormalizedClampMin, render.NormalizedClampMax)
    local nz = math.clamp(pos.Z / render.ZMapRenderSize + render.ZMapRenderCenter, render.NormalizedClampMin, render.NormalizedClampMax)
    return nx, nz
end

local function minimapContent()
    local pg = lp:FindFirstChild("PlayerGui")
    local ui = pg and pg:FindFirstChild("UI")
    if not ui then return nil end
    local mm = ui.Container.HUD.Map.Container:FindFirstChild("Minimap")
    return mm and mm:FindFirstChild("Content")
end

local function extmapContent()
    local pg = lp:FindFirstChild("PlayerGui")
    local ui = pg and pg:FindFirstChild("UI")
    local screen = ui and ui.Container:FindFirstChild("Screen")
    local node = screen and screen:FindFirstChild("Map")
    for _, name in ipairs({ "Main", "MapPanel", "MapStroke", "Map", "Content" }) do
        node = node and node:FindFirstChild(name)
    end
    return node
end

local dots = {} 

local function makedot(size)
    local d = Instance.new("Frame")
    d.Size = UDim2FromOffset(size, size)
    d.AnchorPoint = Vector2.new(0.5, 0.5)
    d.BorderSizePixel = 0
    d.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
    d.ZIndex = 20
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = d
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(0, 0, 0)
    s.Thickness = 1
    s.Parent = d
    return d
end

local function renderPanel(content, size)
    local pool = dots[content]
    if not content or not content:FindFirstChild("MapImage") or not getgenv().minimapdots then
        if pool then for _, d in pairs(pool) do d.Visible = false end end
        return
    end
    if not pool then pool = {} dots[content] = pool end

    for _, p in ipairs(players:GetPlayers()) do
        if p ~= lp then
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local enemy = p.Team ~= lp.Team
            if hrp and hum and hum.Health > 0 and (not getgenv().minimapenemyonly or enemy) then
                local dot = pool[p]
                if not dot or dot.Parent ~= content then
                    if dot then dot:Destroy() end
                    dot = makedot(size)
                    dot.Parent = content
                    pool[p] = dot
                end
                local nx, nz = worldToScale(hrp.Position)
                dot.Position = UDim2FromScale(nx, nz)
                dot.BackgroundColor3 = enemy and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(60, 170, 255)
                dot.Visible = true
            elseif pool[p] then
                pool[p].Visible = false
            end
        end
    end

    for p, d in pairs(pool) do
        if not p.Parent then d:Destroy() pool[p] = nil end
    end
end

rs.RenderStepped:Connect(function()
    renderPanel(minimapContent(), 4)
    renderPanel(extmapContent(), 9)
end)

players.PlayerRemoving:Connect(function(p)
    for _, pool in pairs(dots) do
        if pool[p] then pool[p]:Destroy() pool[p] = nil end
    end
end)
end, "minimapdots")

minimapSection:Toggle("Enemies Only", function(state)
getgenv().minimapenemyonly = state
end, "minimapenemyonly")

local antilagSection = espTab:Section("Anti-Lag / FPS")

getgenv().al_noparticles = false
getgenv().al_noexplosions = false
getgenv().al_notextures = false
getgenv().al_lowgraphics = false

if not getgenv()._antilag_init then
    getgenv()._antilag_init = true
    local Lighting = game:GetService("Lighting")

    local function killEffect(d)
        if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Smoke") or d:IsA("Fire") or d:IsA("Sparkles") then
            if getgenv().al_noparticles then d.Enabled = false end
        elseif d:IsA("Decal") or d:IsA("Texture") then
            if getgenv().al_notextures then d.Transparency = 1 end
        end
    end
    getgenv()._antilag_sweep = function()
        for _, d in ipairs(workspace:GetDescendants()) do pcall(killEffect, d) end
    end

    workspace.DescendantAdded:Connect(function(d)
        if getgenv().al_noparticles or getgenv().al_notextures then
            pcall(killEffect, d)
        end
        if getgenv().al_noexplosions then
            if d:IsA("Explosion") then
                d.Visible = false
            elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") then
                local exp = d:FindFirstAncestor("Explosions")
                if exp then d.Enabled = false end
            end
        end
    end)

    local gs = workspace:FindFirstChild("Game Systems")
    local expFolder = gs and gs:FindFirstChild("Explosions")
    if expFolder then
        expFolder.DescendantAdded:Connect(function(d)
            if not getgenv().al_noexplosions then return end
            if d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Beam") then
                d.Enabled = false
            elseif d:IsA("BasePart") then
                d.Transparency = 1
            end
        end)
    end
end

antilagSection:Toggle("Low Graphics (FPS Boost)", function(state)
    getgenv().al_lowgraphics = state
    local Lighting = game:GetService("Lighting")
    local Terrain = workspace.Terrain

    if not getgenv()._al_gfx_saved then
        getgenv()._al_gfx_saved = {
            q = settings().Rendering.QualityLevel,
            shadows = Lighting.GlobalShadows,
            fog = Lighting.FogEnd,
            wws = Terrain.WaterWaveSize, wwsp = Terrain.WaterWaveSpeed,
            wr = Terrain.WaterReflectance, wt = Terrain.WaterTransparency,
        }
    end
    local s = getgenv()._al_gfx_saved

    if state then
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 1
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("BloomEffect") or e:IsA("BlurEffect") or e:IsA("DepthOfFieldEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") then
                e.Enabled = false
            end
        end
    else
        pcall(function() settings().Rendering.QualityLevel = s.q end)
        Lighting.GlobalShadows = s.shadows
        Lighting.FogEnd = s.fog
        Terrain.WaterWaveSize = s.wws
        Terrain.WaterWaveSpeed = s.wwsp
        Terrain.WaterReflectance = s.wr
        Terrain.WaterTransparency = s.wt
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("BloomEffect") or e:IsA("BlurEffect") or e:IsA("DepthOfFieldEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") then
                e.Enabled = true
            end
        end
    end
end, "al_lowgraphics")

antilagSection:Toggle("No Particles / Trails", function(state)
    getgenv().al_noparticles = state
    if state and getgenv()._antilag_sweep then getgenv()._antilag_sweep() end
end, "al_noparticles")

antilagSection:Toggle("No Explosions", function(state)
    getgenv().al_noexplosions = state
end, "al_noexplosions")

antilagSection:Toggle("No Textures / Decals", function(state)
    getgenv().al_notextures = state
    if state and getgenv()._antilag_sweep then getgenv()._antilag_sweep() end
end, "al_notextures")

local lptab = window:Tab("LocalPlayer", "rbxassetid://134806693472248")

local lp = lptab:Section("smt")

local flytoggle = lp:Toggle("Fly", function(state)
getgenv().fly = state

if getgenv()._fly_init then return end
getgenv()._fly_init = true

local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local lp = players.LocalPlayer
local cam = workspace.CurrentCamera

local flying = false
local vel, gyro
local keys = {w = false, a = false, s = false, d = false, space = false, shift = false}

local function startFly()
    if flying then return end
    flying = true
    
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    vel = Instance.new("BodyVelocity")
    vel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    vel.Velocity = Vector3.zero
    vel.Parent = hrp
    
    gyro = Instance.new("BodyGyro")
    gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    gyro.P = 10000
    gyro.CFrame = hrp.CFrame
    gyro.Parent = hrp
end

local function stopFly()
    flying = false
    if vel then vel:Destroy() end
    if gyro then gyro:Destroy() end
    vel, gyro = nil, nil
end

rs.RenderStepped:Connect(function()
    if not flying or not vel or not gyro then return end
    
    local dir = Vector3.zero
    
    if keys.w then dir = dir + cam.CFrame.LookVector end
    if keys.s then dir = dir - cam.CFrame.LookVector end
    if keys.a then dir = dir - cam.CFrame.RightVector end
    if keys.d then dir = dir + cam.CFrame.RightVector end
    if keys.space then dir = dir + Vector3.new(0, 1, 0) end
    if keys.shift then dir = dir - Vector3.new(0, 1, 0) end
    
    if dir.Magnitude > 0 then
        dir = dir.Unit * getgenv().flyspeed
    end
    
    vel.Velocity = dir
    gyro.CFrame = cam.CFrame
end)

uis.InputBegan:Connect(function(key, gp)
    if gp then return end
    if key.KeyCode == Enum.KeyCode.W then keys.w = true end
    if key.KeyCode == Enum.KeyCode.A then keys.a = true end
    if key.KeyCode == Enum.KeyCode.S then keys.s = true end
    if key.KeyCode == Enum.KeyCode.D then keys.d = true end
    if key.KeyCode == Enum.KeyCode.Space then keys.space = true end
    if key.KeyCode == Enum.KeyCode.LeftShift then keys.shift = true end
end)

uis.InputEnded:Connect(function(key)
    if key.KeyCode == Enum.KeyCode.W then keys.w = false end
    if key.KeyCode == Enum.KeyCode.A then keys.a = false end
    if key.KeyCode == Enum.KeyCode.S then keys.s = false end
    if key.KeyCode == Enum.KeyCode.D then keys.d = false end
    if key.KeyCode == Enum.KeyCode.Space then keys.space = false end
    if key.KeyCode == Enum.KeyCode.LeftShift then keys.shift = false end
end)

uis.TouchMoved:Connect(function(touch, gp)
    if gp or not getgenv().fly then return end
    local delta = touch.Delta
    if math.abs(delta.Y) > math.abs(delta.X) then
        if delta.Y < 0 then keys.space = true keys.shift = false
        else keys.shift = true keys.space = false end
    else
        if delta.X > 0 then keys.d = true keys.a = false
        else keys.a = true keys.d = false end
    end
end)

uis.TouchEnded:Connect(function()
    keys.w, keys.a, keys.s, keys.d, keys.space, keys.shift = false, false, false, false, false, false
end)

task.spawn(function()
    while task.wait() do
        if getgenv().fly and not flying then
            startFly()
        elseif not getgenv().fly and flying then
            stopFly()
        end
    end
end)
end, "flytoggle")

flytoggle:BindKey()

getgenv().flyspeed = 50
local flySpeedSlider = lp:Slider("Fly Speed", function(value)
getgenv().flyspeed = value
end, 300, 50, "flyspeed")

local nofalldamageToggle = lp:Toggle("No Fall Damage", function(state)
getgenv().antifall = state

if getgenv()._antifall_init then return end
getgenv()._antifall_init = true

local players = game:GetService("Players")
local lp = players.LocalPlayer

local fdmg = game:GetService("ReplicatedStorage").ACS_Engine.Events:WaitForChild("FDMG")
local oldnc
oldnc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if getgenv().antifall and not checkcaller() and self == fdmg and getnamecallmethod() == "FireServer" then
        return
    end
    return oldnc(self, ...)
end))

local function suppress()
    local char = lp.Character
    local be = char and char:FindFirstChild("PreventFallDamageBindableEvent")
    if be then be:Fire(20) end
end

lp.CharacterAdded:Connect(function()
    task.wait(0.5)
    if getgenv().antifall then pcall(suppress) end
end)

task.spawn(function()
    while true do
        if getgenv().antifall then pcall(suppress) end
        task.wait(4)
    end
end)
end, "nofalldamageToggle")

local noclipToggle = lp:Toggle("Noclip", function(state)
getgenv().noclip = state

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
local noclipConnection

local function startNoclip(char)
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end

    noclipConnection = RunService.Stepped:Connect(function()
        if not getgenv().noclip then return end

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

local function stopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end

    if lp.Character then
        for _, part in ipairs(lp.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

lp.CharacterAdded:Connect(function(char)
    if getgenv().noclip then
        task.wait()
        startNoclip(char)
    end
end)

lp.CharacterRemoving:Connect(stopNoclip)

if lp.Character and getgenv().noclip then
    startNoclip(lp.Character)
end
end, "noclips")

local spinbot = lp:Toggle("Spin Bot", function(state)
getgenv().spinbot = state

local rs = game:GetService("RunService")
local players = game:GetService("Players")
local lp = players.LocalPlayer

local spinangle = 0
local jitteroffset = 0

rs.Heartbeat:Connect(function()
    if not getgenv().spinbot then return end
    if not lp.Character then return end
    local hrp = lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local speed = getgenv().spinspeed or 50
    spinangle = spinangle + (speed * 0.016)
    
    if spinangle >= 6.28318 then
        spinangle = 0
    end
    
    jitteroffset = math.sin(spinangle * 8) * 0.3
    local finalangle = spinangle + jitteroffset
    
    hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, finalangle, 0)
end)
end, "spinbot")

getgenv().spinspeed = 1
local spinSpeedSlider = lp:Slider("Spin Speed", function(value)
    getgenv().spinspeed = value
end, 70, 1, "spinspeed")

local maniptab = window:Tab("Manipulation", "rbxassetid://114064468478647")
local rocketSec = maniptab:Section("Guided Rockets (Stinger / Javelin / etc.)")

getgenv().rocketmods = false
getgenv().rm_turnspeed = 0
getgenv().rm_velocity = 0
getgenv().rm_expradius = 0
getgenv().rm_accel = 0
getgenv().rm_nogravity = false
getgenv().rm_instanthoming = false
getgenv().rm_trackdist = 0
getgenv().rm_trackangle = 0
getgenv().rm_battery = 0
getgenv().rm_proxfuse = 0

rocketSec:Toggle("Enable Rocket Mods", function(state)
    getgenv().rocketmods = state
    if getgenv()._rocketmods_init then return end
    getgenv()._rocketmods_init = true

    local firebindable = game:GetService("ReplicatedStorage").RocketSystem.Events:WaitForChild("FireRocketBindable")
    local oldnc
    oldnc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getgenv().rocketmods and self == firebindable and getnamecallmethod() == "Fire" then
            local a = { ... }
            local rargs = a[2]
            if type(rargs) == "table" and type(rargs.Settings) == "table" then
                local s = {}
                for k, v in pairs(rargs.Settings) do s[k] = v end 
                if getgenv().rm_instanthoming then
                    if s.TurnSpeed ~= nil then s.TurnSpeed = 1 end
                    if s.WireTurnSpeed ~= nil then s.WireTurnSpeed = 1 end
                    if s.ActivateDistance ~= nil then s.ActivateDistance = 0 end
                elseif getgenv().rm_turnspeed > 0 then
                    local ts = getgenv().rm_turnspeed / 100
                    if s.TurnSpeed ~= nil then s.TurnSpeed = ts end
                    if s.WireTurnSpeed ~= nil then s.WireTurnSpeed = ts end
                end
                if getgenv().rm_velocity > 0 then
                    if s.velocity ~= nil then s.velocity = getgenv().rm_velocity end
                    if s.CloseVelocity ~= nil then s.CloseVelocity = getgenv().rm_velocity end
                end
                if getgenv().rm_accel > 0 and s.Acceleration ~= nil then s.Acceleration = getgenv().rm_accel end
                if getgenv().rm_expradius > 0 and s.ExpRadius ~= nil then s.ExpRadius = getgenv().rm_expradius end
                if getgenv().rm_nogravity and s.gravity ~= nil then s.gravity = Vector3.new(0, 0, 0) end
                if getgenv().rm_trackdist > 0 and s.TrackingDistance ~= nil then s.TrackingDistance = getgenv().rm_trackdist end
                if getgenv().rm_trackangle > 0 and s.TrackingAngle ~= nil then s.TrackingAngle = getgenv().rm_trackangle end
                if getgenv().rm_battery > 0 and s.BatteryLife ~= nil then s.BatteryLife = getgenv().rm_battery end
                if getgenv().rm_proxfuse > 0 and s.ProximityFuseRadius ~= nil then s.ProximityFuseRadius = getgenv().rm_proxfuse end
                rargs.Settings = s
            end
            setnamecallmethod("Fire")
            return oldnc(self, unpack(a))
        end
        return oldnc(self, ...)
    end))
end, "rocketmods")

rocketSec:Toggle("Instant Homing (snap to target)", function(v)
    getgenv().rm_instanthoming = v
end, "rm_instanthoming")

rocketSec:Slider("Homing / Turn Speed % (0=off)", function(v)
    getgenv().rm_turnspeed = v
end, 100, 0, "rm_turnspeed")

rocketSec:Slider("Rocket Speed (0=off)", function(v)
    getgenv().rm_velocity = v
end, 2000, 0, "rm_velocity")

rocketSec:Slider("Acceleration (0=off)", function(v)
    getgenv().rm_accel = v
end, 200, 0, "rm_accel")

rocketSec:Slider("Explosion Radius (0=off)", function(v)
    getgenv().rm_expradius = v
end, 150, 0, "rm_expradius")

rocketSec:Toggle("No Gravity (flat flight)", function(v)
    getgenv().rm_nogravity = v
end, "rm_nogravity")

rocketSec:Slider("Tracking Distance (0=off)", function(v)
    getgenv().rm_trackdist = v
end, 10000, 0, "rm_trackdist")

rocketSec:Slider("Tracking Angle / lock cone (0=off)", function(v)
    getgenv().rm_trackangle = v
end, 180, 0, "rm_trackangle")

rocketSec:Slider("Battery Life / track time (0=off)", function(v)
    getgenv().rm_battery = v
end, 60, 0, "rm_battery")

rocketSec:Slider("Proximity Fuse Radius (0=off)", function(v)
    getgenv().rm_proxfuse = v
end, 100, 0, "rm_proxfuse")

getgenv().rm_ignorewalls = false

rocketSec:Toggle("Rockets Ignore Walls (hit locked target)", function(state)
    getgenv().rm_ignorewalls = state
    if getgenv()._rm_ignorewalls_init then return end
    getgenv()._rm_ignorewalls_init = true

    local rockethit = game:GetService("ReplicatedStorage").RocketSystem.Events:WaitForChild("RocketHit")
    local oldnc
    oldnc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getgenv().rm_ignorewalls and self == rockethit and getnamecallmethod() == "FireServer" then
            local a = { ... }
            local t = a[1]
            if type(t) == "table" and typeof(t.Target) == "Instance" then
                local tgt, pos = t.Target, nil
                if tgt:IsA("BasePart") then
                    pos = tgt.Position
                elseif tgt:IsA("Model") then
                    local part = tgt:FindFirstChild("HumanoidRootPart") or tgt.PrimaryPart
                    pos = part and part.Position or tgt:GetPivot().Position
                end
                if pos then t.Position = pos end
            end
            setnamecallmethod("FireServer")
            return oldnc(self, unpack(a))
        end
        return oldnc(self, ...)
    end))
end, "rm_ignorewalls")

local orbitSec = maniptab:Section("Rocket Orbit")

getgenv().stingerorbit = false
getgenv().so_radius = 45
getgenv().so_hitplayers = true
getgenv().so_hitvehicles = false

orbitSec:Toggle("Stinger Orbit (real rocket, no lock, thru walls)", function(state)
    getgenv().stingerorbit = state
    if getgenv()._stingerorbit_init then return end
    getgenv()._stingerorbit_init = true

    local rep = game:GetService("ReplicatedStorage")
    local runs = game:GetService("RunService")
    local playersS = game:GetService("Players")
    local lp = playersS.LocalPlayer
    local firebindable = rep.RocketSystem.Events:WaitForChild("FireRocketBindable")
    local rocketguns = { ["Stinger"] = true, ["RPG"] = true, ["Javelin"] = true }
    local vehFolders = { "Helicopter Workspace", "Plane Workspace", "Vehicle Workspace", "Tank Workspace", "Boat Workspace", "Drone Workspace" }

    local bait = Instance.new("Part")
    bait.Name = "BSMT_OrbitBait"
    bait.Anchored = true bait.CanCollide = false bait.Transparency = 1
    bait.Size = Vector3.new(2, 2, 2) bait.Parent = workspace
    local ang = 0
    local activeRocket = nil

    local function whitelist()
        local list = {}
        if getgenv().so_hitplayers then
            for _, p in ipairs(playersS:GetPlayers()) do
                if p ~= lp and p.Character then table.insert(list, p.Character) end
            end
        end
        if getgenv().so_hitvehicles then
            local gs = workspace:FindFirstChild("Game Systems")
            if gs then
                for _, wsn in ipairs(vehFolders) do
                    local f = gs:FindFirstChild(wsn)
                    if f then for _, v in ipairs(f:GetChildren()) do table.insert(list, v) end end
                end
            end
        end
        return list
    end

    pcall(function()
        local FastCastRedux = require(rep.BulletFireSystem:WaitForChild("FastCastRedux"))
        local realFire
        realFire = hookfunction(FastCastRedux.Fire, newcclosure(function(self, o, d, v, behavior)
            if getgenv().stingerorbit and type(behavior) == "table" and behavior.RaycastParams then
                local char = lp.Character
                local tool = char and char:FindFirstChildOfClass("Tool")
                if tool and rocketguns[tool.Name] then
                    pcall(function()
                        behavior.RaycastParams.FilterType = Enum.RaycastFilterType.Include
                        behavior.RaycastParams.FilterDescendantsInstances = whitelist()
                    end)
                end
            end
            return realFire(self, o, d, v, behavior)
        end))
    end)

    runs.Heartbeat:Connect(function(dt)
        if not getgenv().stingerorbit then return end
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local r = math.max(getgenv().so_radius or 45, 30)
        local center = hrp.Position + Vector3.new(0, 5, 0)
        local rk = activeRocket and activeRocket.Parent and (activeRocket:FindFirstChild("MainPart") or activeRocket.PrimaryPart)
        if rk then
            local rel = rk.Position - center
            ang = math.atan2(rel.Z, rel.X) + 1.4 
        else
            ang = ang + dt * 2
        end
        bait.Position = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
        local tool = char:FindFirstChildOfClass("Tool")
        if tool and tool:FindFirstChild("Target") and tool.Target:IsA("ObjectValue") then
            tool.Target.Value = bait
        end
    end)

    local oldnc
    oldnc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getgenv().stingerorbit and not checkcaller() and self == firebindable and getnamecallmethod() == "Fire" then
            local a = { ... }
            local rargs = a[2]
            if type(rargs) == "table" then
                rargs.Target = bait
                if type(rargs.Settings) == "table" then
                    local s = {}
                    for k, v in pairs(rargs.Settings) do s[k] = v end
                    if s.TurnSpeed ~= nil then s.TurnSpeed = 0.35 end
                    if s.WireTurnSpeed ~= nil then s.WireTurnSpeed = 0.35 end
                    rargs.Settings = s
                end
            end
            setnamecallmethod("Fire")
            task.delay(0.1, function()
                local vr = workspace:FindFirstChild("VisualRockets")
                if vr then
                    local newest
                    for _, mm in ipairs(vr:GetChildren()) do newest = mm end
                    activeRocket = newest
                end
            end)
            return oldnc(self, unpack(a))
        end
        return oldnc(self, ...)
    end))
end, "stingerorbit")

orbitSec:Slider("Orbit Radius (safe distance)", function(v)
    getgenv().so_radius = v
end, 100, 30, "so_radius")

orbitSec:Toggle("Explode on Players", function(v)
    getgenv().so_hitplayers = v
end, "so_hitplayers")

orbitSec:Toggle("Explode on Vehicles", function(v)
    getgenv().so_hitvehicles = v
end, "so_hitvehicles")

local funtab = window:Tab("Fun", "rbxassetid://11435586663")
local funsec = funtab:Section("Movement")
local funsec2 = funtab:Section("Visual / Misc")

getgenv().rocketorbit = false
getgenv().orbitspeed = 3
getgenv().orbitradius = 15

funsec2:Toggle("Rocket Orbit (troll)", function(state)
    getgenv().rocketorbit = state
    if getgenv()._orbit_init then return end
    getgenv()._orbit_init = true

    local rep = game:GetService("ReplicatedStorage")
    local rs = game:GetService("RunService")
    local lp = game:GetService("Players").LocalPlayer
    local firebindable = rep.RocketSystem.Events:WaitForChild("FireRocketBindable")
    local fireremote = rep.RocketSystem.Events:WaitForChild("FireRocket")
    local orbiters = {}

    local oldnc
    oldnc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getgenv().rocketorbit and not checkcaller() then
            local m = getnamecallmethod()
            if self == firebindable and m == "Fire" then
                local a = { ... }
                local rargs = a[2]
                if type(rargs) == "table" and typeof(rargs.RocketModel) == "Instance" then
                    task.spawn(function()
                        local ok, clone = pcall(function() return rargs.RocketModel:Clone() end)
                        if ok and clone then
                            local mp = clone:FindFirstChild("MainPart") or clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
                            if mp then
                                clone.PrimaryPart = mp
                                for _, d in ipairs(clone:GetDescendants()) do
                                    if d:IsA("BasePart") then d.Anchored = true d.CanCollide = false
                                    elseif d:IsA("Script") or d:IsA("LocalScript") then d:Destroy() end
                                end
                                clone.Parent = workspace
                                table.insert(orbiters, { model = clone, angle = math.random() * 6.283 })
                                while #orbiters > 8 do
                                    local old = table.remove(orbiters, 1)
                                    if old.model then old.model:Destroy() end
                                end
                            end
                        end
                    end)
                end
                return 
            elseif self == fireremote and m == "InvokeServer" then
                return 
            end
        end
        return oldnc(self, ...)
    end))

    rs.RenderStepped:Connect(function(dt)
        if #orbiters == 0 then return end
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        for i = #orbiters, 1, -1 do
            local o = orbiters[i]
            if not (o.model and o.model.Parent and hrp) then
                if o.model then o.model:Destroy() end
                table.remove(orbiters, i)
            else
                o.angle = o.angle + dt * (getgenv().orbitspeed or 3)
                local r = getgenv().orbitradius or 15
                local center = hrp.Position + Vector3.new(0, 2, 0)
                local pos = center + Vector3.new(math.cos(o.angle) * r, 0, math.sin(o.angle) * r)
                local ahead = center + Vector3.new(math.cos(o.angle + 0.2) * r, 0, math.sin(o.angle + 0.2) * r)
                pcall(function() o.model:PivotTo(CFrame.lookAt(pos, ahead)) end)
            end
        end
    end)
end, "rocketorbit")

funsec2:Slider("Orbit Speed", function(v)
    getgenv().orbitspeed = v
end, 20, 1, "orbitspeed")

funsec2:Slider("Orbit Radius", function(v)
    getgenv().orbitradius = v
end, 60, 5, "orbitradius")

getgenv().moongrav = false
getgenv().gravamount = 40
funsec:Toggle("Moon Gravity", function(state)
getgenv().moongrav = state
if not getgenv()._grav_orig then getgenv()._grav_orig = workspace.Gravity end
workspace.Gravity = state and getgenv().gravamount or getgenv()._grav_orig
end, "moongrav")

funsec:Slider("Gravity", function(value)
getgenv().gravamount = value
if getgenv().moongrav then workspace.Gravity = value end
end, 196, 5, "gravamount")

getgenv().superjump = false
getgenv().jumppower2 = 120
funsec:Toggle("Super Jump", function(state)
getgenv().superjump = state
if getgenv()._sj_init then return end
getgenv()._sj_init = true
local uis = game:GetService("UserInputService")
local lp = game:GetService("Players").LocalPlayer
uis.JumpRequest:Connect(function()
    if not getgenv().superjump then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.FloorMaterial ~= Enum.Material.Air then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(v.X, getgenv().jumppower2, v.Z)
    end
end)
end, "superjump")

funsec:Slider("Jump Power", function(value)
getgenv().jumppower2 = value
end, 300, 50, "jumppower2")

getgenv().selftrail = false
funsec2:Toggle("Rainbow Trail", function(state)
getgenv().selftrail = state
if getgenv()._trail_init then return end
getgenv()._trail_init = true
local rs = game:GetService("RunService")
local lp = game:GetService("Players").LocalPlayer
task.spawn(function()
    local trail, a0, a1
    local hue = 0
    while true do
        rs.Heartbeat:Wait()
        if getgenv().selftrail then
            local char = lp.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                if not trail or trail.Parent ~= hrp then
                    if a0 then a0:Destroy() end
                    if a1 then a1:Destroy() end
                    a0 = Instance.new("Attachment") a0.Position = Vector3.new(0, 1.4, 0) a0.Parent = hrp
                    a1 = Instance.new("Attachment") a1.Position = Vector3.new(0, -1.4, 0) a1.Parent = hrp
                    trail = Instance.new("Trail")
                    trail.Attachment0 = a0
                    trail.Attachment1 = a1
                    trail.Lifetime = 0.9
                    trail.WidthScale = NumberSequence.new(1, 0)
                    trail.FaceCamera = true
                    trail.Parent = hrp
                end
                hue = (hue + 0.008) % 1
                trail.Color = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
            end
        elseif trail then
            trail:Destroy() trail = nil
            if a0 then a0:Destroy() a0 = nil end
            if a1 then a1:Destroy() a1 = nil end
        end
    end
end)
end, "selftrail")

getgenv().antiafk = false
funsec2:Toggle("Anti AFK", function(state)
getgenv().antiafk = state
if getgenv()._antiafk_init then return end
getgenv()._antiafk_init = true
local vu = game:GetService("VirtualUser")
local lp = game:GetService("Players").LocalPlayer
lp.Idled:Connect(function()
    if not getgenv().antiafk then return end
    vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)
end, "antiafk")

getgenv().infjump = false
funsec:Toggle("Infinite Jump", function(state)
getgenv().infjump = state
if getgenv()._infjump_init then return end
getgenv()._infjump_init = true
local uis = game:GetService("UserInputService")
local lp = game:GetService("Players").LocalPlayer
uis.JumpRequest:Connect(function()
    if not getgenv().infjump then return end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
end, "infjump")

getgenv().wsenabled = false
getgenv().walkspeed = 16
funsec:Toggle("Custom WalkSpeed", function(state)
getgenv().wsenabled = state
if getgenv()._ws_init then return end
getgenv()._ws_init = true
local rs = game:GetService("RunService")
local lp = game:GetService("Players").LocalPlayer
rs.Heartbeat:Connect(function()
    if not getgenv().wsenabled then return end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed ~= getgenv().walkspeed then hum.WalkSpeed = getgenv().walkspeed end
end)
end, "wsenabled")

funsec:Slider("WalkSpeed", function(value)
getgenv().walkspeed = value
end, 200, 16, "walkspeed")

getgenv().freecam = false
getgenv().freecamspeed = 60
funsec:Toggle("Freecam", function(state)
getgenv().freecam = state
if getgenv()._freecam_init then return end
getgenv()._freecam_init = true
local uis = game:GetService("UserInputService")
local rs = game:GetService("RunService")
local cam = workspace.CurrentCamera
local keys = {}
local pos, yaw, pitch
local active = false
uis.InputBegan:Connect(function(i, gp) if not gp then keys[i.KeyCode] = true end end)
uis.InputEnded:Connect(function(i) keys[i.KeyCode] = false end)
rs.RenderStepped:Connect(function(dt)
    if getgenv().freecam and not active then
        active = true
        local cf = cam.CFrame
        pos = cf.Position
        pitch, yaw = cf:ToOrientation()
        cam.CameraType = Enum.CameraType.Scriptable
    elseif not getgenv().freecam and active then
        active = false
        cam.CameraType = Enum.CameraType.Custom
        uis.MouseBehavior = Enum.MouseBehavior.Default
    end
    if not active then return end
    if uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        uis.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        local d = uis:GetMouseDelta()
        yaw = yaw - d.X * 0.005
        pitch = math.clamp(pitch - d.Y * 0.005, -1.4, 1.4)
    else
        uis.MouseBehavior = Enum.MouseBehavior.Default
    end
    local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
    local move = Vector3.zero
    if keys[Enum.KeyCode.W] then move = move + rot.LookVector end
    if keys[Enum.KeyCode.S] then move = move - rot.LookVector end
    if keys[Enum.KeyCode.A] then move = move - rot.RightVector end
    if keys[Enum.KeyCode.D] then move = move + rot.RightVector end
    if keys[Enum.KeyCode.E] then move = move + Vector3.new(0, 1, 0) end
    if keys[Enum.KeyCode.Q] then move = move - Vector3.new(0, 1, 0) end
    pos = pos + move * (getgenv().freecamspeed * dt)
    cam.CFrame = CFrame.new(pos) * rot
end)
end, "freecam")

funsec:Slider("Freecam Speed", function(value)
getgenv().freecamspeed = value
end, 300, 20, "freecamspeed")

funsec2:TextBox("Teleport To Player", function(text)
local players = game:GetService("Players")
local lp = players.LocalPlayer
if text == "" then return end
local target
for _, p in ipairs(players:GetPlayers()) do
    if p ~= lp and p.Character and p.Name:lower():sub(1, #text) == text:lower() then
        target = p break
    end
end
local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
local mhrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
if thrp and mhrp then
    mhrp.CFrame = thrp.CFrame + Vector3.new(0, 4, 0)
    _G.Notify("Teleported to " .. target.Name, "success", 2)
else
    _G.Notify("Player not found", "error", 2)
end
end)

local maniptab = window:Tab("Manipulation", "rbxassetid://114064468478647")
local rocketsec = maniptab:Section("Manual Rocket Control")

getgenv().mr_active = false

rocketsec:Toggle("Manual Rocket Control", function(state)
    getgenv().mr_active = state
    _G.Notify(state and "ON: Fire RPG/Stinger to control" or "OFF", state and "success" or "info", 2)
end, "mr_toggle")

rocketsec:Slider("Rocket Speed", function(v)
    getgenv().mr_velocity = v
end, 1500, 100, "mr_velocity")

rocketsec:Slider("Sensitivity", function(v)
    getgenv().mr_sens = v / 100
end, 100, 10, "mr_sens")

do
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local RS = game:GetService("ReplicatedStorage")
    local lp = Players.LocalPlayer
    local cam = workspace.CurrentCamera

    local rocketHit = RS.RocketSystem.Events:WaitForChild("RocketHit")
    local fireBind = RS.RocketSystem.Events:WaitForChild("FireRocketBindable")

    getgenv().mr_velocity = 200
    getgenv().mr_sens = 0.5

    local controlConn = nil
    local inputConn = nil
    local yaw, pitch = 0, 0
    local currentRocket = nil
    local currentMP = nil
    local flash = nil
    local targetPart = nil
    local behaviorHooked = false
    local fireHooked = false

    local function cleanup()
        if controlConn then controlConn:Disconnect() controlConn = nil end
        if inputConn then inputConn:Disconnect() inputConn = nil end
        if flash and flash.Parent then flash:Destroy() end
        flash = nil
        if targetPart and targetPart.Parent then targetPart:Destroy() end
        targetPart = nil
        currentRocket = nil
        currentMP = nil
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        cam.CameraType = Enum.CameraType.Custom
        local tg = lp.PlayerGui:FindFirstChild("TurretGui")
        if tg then tg.Enabled = true end
        local ci = lp.PlayerGui:FindFirstChild("ChassisInterface")
        if ci then ci.Enabled = true end
        local pi = lp.PlayerGui:FindFirstChild("PlaneInterface")
        if pi then pi.Enabled = true end
    end

    local function detonate()
        if not currentRocket or not currentMP then cleanup() return end
        pcall(function()
            rocketHit:FireServer({
                Origin = currentMP.Position,
                Player = lp,
                Position = currentMP.Position,
                Normal = Vector3.new(0, 1, 0),
                Vehicle = nil,
                Weapon = nil,
                HitPart = nil,
                Target = nil,
                Label = currentRocket.Name
            })
        end)
        cleanup()
    end

    local function hookBehavior()
        if behaviorHooked then return end
        behaviorHooked = true

        pcall(function()
            local RB = require(RS.RocketSystem.RocketFireVisuals.RocketBehavior)

            local oldGuided = RB.GuidedRocket
            RB.GuidedRocket = function(cast, dir, ...)
                oldGuided(cast, dir, ...)
                if not getgenv().mr_active or not currentRocket then return end

                local d = UIS:GetMouseDelta()
                local s = getgenv().mr_sens * 0.04
                yaw = yaw + math.clamp(-d.X, -5, 5) * s
                pitch = math.clamp(pitch + math.clamp(-d.Y, -5, 5) * s, -1.5, 1.5)

                local look = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
                cast:SetVelocity(look * getgenv().mr_velocity)
            end

            local oldWire = RB.WireGuided
            RB.WireGuided = function(cast, pos)
                if not getgenv().mr_active or not currentRocket then
                    return oldWire(cast, pos)
                end

                local d = UIS:GetMouseDelta()
                local s = getgenv().mr_sens * 0.04
                yaw = yaw + math.clamp(-d.X, -5, 5) * s
                pitch = math.clamp(pitch + math.clamp(-d.Y, -5, 5) * s, -1.5, 1.5)

                local look = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
                cast:SetVelocity(look * getgenv().mr_velocity)
            end
        end)
    end

    local function hookFire()
        if fireHooked then return end
        fireHooked = true

        local oldnc
        oldnc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if not checkcaller() and self == fireBind and getnamecallmethod() == "Fire" then
                local args = { ... }
                local rargs = args[2]
                if getgenv().mr_active and type(rargs) == "table" then
                    if not rargs.Target then
                        local tp = Instance.new("Part")
                        tp.Anchored = true
                        tp.CanCollide = false
                        tp.Transparency = 1
                        tp.Size = Vector3.new(1, 1, 1)
                        tp.Position = cam.CFrame.Position + cam.CFrame.LookVector * 500
                        tp.Parent = workspace
                        rargs.Target = tp

                        task.delay(0.15, function()
                            targetPart = tp
                        end)
                    end
                end
            end
            return oldnc(self, ...)
        end))
    end

    local function startControl(rocket)
        if currentRocket then return end
        local mp = rocket:FindFirstChild("MainPart")
        if not mp then return end

        currentRocket = rocket
        currentMP = mp
        yaw = math.atan2(mp.CFrame.LookVector.Z, mp.CFrame.LookVector.X)
        pitch = math.asin(math.clamp(mp.CFrame.LookVector.Y, -1, 1))

        flash = Instance.new("ColorCorrectionEffect")
        flash.Saturation = -0.3
        flash.Parent = cam

        UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        cam.CameraType = Enum.CameraType.Scriptable

        local tg = lp.PlayerGui:FindFirstChild("TurretGui")
        if tg then tg.Enabled = false end
        local ci = lp.PlayerGui:FindFirstChild("ChassisInterface")
        if ci then ci.Enabled = false end
        local pi = lp.PlayerGui:FindFirstChild("PlaneInterface")
        if pi then pi.Enabled = false end

        _G.Notify("FLIGHT MODE - mouse to steer, X = detonate", "success", 2)

        hookBehavior()

        controlConn = RunService.RenderStepped:Connect(function(dt)
            if not getgenv().mr_active or not rocket or not rocket.Parent then
                cleanup()
                return
            end
            local mp = rocket:FindFirstChild("MainPart")
            if not mp then cleanup() return end
            currentMP = mp

            if targetPart and targetPart.Parent then
                local look = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
                targetPart.Position = mp.Position + look * 500
            end

            cam.CFrame = CFrame.new(mp.Position + mp.CFrame.LookVector * 3) * mp.CFrame.Rotation
        end)
    end

    local function watchRocket()
        local vr = workspace:WaitForChild("VisualRockets", 10)
        if not vr then return end

        vr.ChildAdded:Connect(function(child)
            if not getgenv().mr_active then return end
            if child:GetAttribute("Owner") ~= lp.Name then return end
            if currentRocket then return end

            task.wait(0.1)
            startControl(child)
        end)
    end
    watchRocket()
    hookFire()

    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not getgenv().mr_active then return end
        if input.KeyCode == Enum.KeyCode.X and currentRocket then
            detonate()
        end
    end)
end

window:ConfigTab()
