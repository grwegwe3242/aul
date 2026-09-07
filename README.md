_G.BSMTExistingHooks = _G.BSMTExistingHooks or {}
if not _G.BSMTExistingHooks.GuiDetectionBypass then
    local CoreGui = game.CoreGui
    local ContentProvider = game.ContentProvider
    local RobloxGuis = {"RobloxGui", "TeleportGui", "RobloxPromptGui", "RobloxLoadingGui", "PlayerList", "RobloxNetworkPauseNotification", "PurchasePrompt", "HeadsetDisconnectedDialog", "ThemeProvider", "DevConsoleMaster"}

    local hookfunc = hookfunction or hookfunc or replaceclosure
    local hookmetamethod = hookmetamethod or hookmetamethods
    
    if not hookfunc then
        warn("Executor doesn't support function hooking - GUI detection bypass disabled")
        _G.BSMTExistingHooks.GuiDetectionBypass = true
        return
    end

    -- syn_context_* is Synapse-only; guard so this doesn't error on SUNC/other executors
    local hasSynContext = (syn_context_get ~= nil and syn_context_set ~= nil)

    local function FilterTable(tbl)
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
    
    _G.BSMTExistingHooks.GuiDetectionBypass = true
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer

for _, connection in pairs(getconnections(player.Idled)) do
	if connection.Enabled then
    	connection:Disable()
    end
end


local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local mouse = player:GetMouse()
local viewPortSize = workspace.CurrentCamera.ViewportSize

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

local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

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
		plus.Image = "http://www.roblox.com/asset/?id=11520007725"
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
		tabAccentGradient.Color = ColorSequence.new(Theme.Accent, Theme.AccentSecondary)
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
		leftScrollingFrame.CanvasSize = UDim2.fromScale(0, 0)
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
		rightScrollingFrame.CanvasSize = UDim2.fromScale(0, 0)
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
		resizeButton.Size = UDim2.fromScale(0.65, 0.65)
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
		toggleImage.Size = UDim2.fromScale(0, 0)
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
		buttonBgStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
		buttonCircle.Position = UDim2.fromScale(0.5,0.5)
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
		dropdownButtonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
		sliderBgStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
		sliderFillGradient.Color = ColorSequence.new(Theme.Accent, Theme.AccentSecondary)
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
		tagBorder.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
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
		boxBgStroke.ApplyStrokeMode  = Enum.ApplyStrokeMode.Border
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
		local vp = workspace.CurrentCamera.ViewportSize
		background.Position = UDim2.new(0, math.round(vp.X / 2), 0, math.round(vp.Y / 2))

		holder.Size     = UDim2.new(0, holder.AbsoluteSize.X, 0, holder.AbsoluteSize.Y)
		holder.Position = UDim2.new(0, 0, 0, heading.AbsoluteSize.Y)
		heading.Size    = UDim2.new(1, 0, 0, heading.AbsoluteSize.Y)
	else
		background.Size = UDim2.fromOffset(background.AbsoluteSize.X, background.AbsoluteSize.Y)
		if width then
			background.Size = UDim2.fromOffset(width, background.AbsoluteSize.Y)
		end
		if height then
			background.Size = UDim2.fromOffset(background.AbsoluteSize.X, height)
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
	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Text = titleName or "N/A"
	textParams.Font = titleInstance.TitleText.FontFace
	textParams.Size = 14
	textParams.Width = 10000

	local requiredTextSpace = TextService:GetTextBoundsAsync(textParams) + textSpaceOffset

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
	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Text = newText or "N/A"
	textParams.Font = self.Instance.TitleText.FontFace
	textParams.Size = 14
	textParams.Width = 10000
	
	local requiredTextSpace = TextService:GetTextBoundsAsync(textParams) + textSpaceOffset
	
	self.Instance.TitleText.Text = newText or "N/A"
	self.Instance.TitleText.Size = UDim2.new(0, requiredTextSpace.X, 1, 0)
end

function elementHandler:Label(labelInputtedText: string, textSize: number, textColor: Color3): table
	local label = setmetatable({}, labelHandler)
	local labelInstance = originalElements.Label:Clone()
	
	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Text = labelInputtedText or "N/A"
	textParams.Font = labelInstance.LabelBackground.LabelText.FontFace
	textParams.Size = textSize or 13

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
	textParams.Width = labelInstance.LabelBackground.LabelText.AbsoluteSize.X - labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingLeft.Offset - labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingRight.Offset
	labelInstance.Size = UDim2.new(1,0,0,TextService:GetTextBoundsAsync(textParams).Y + labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingTop.Offset + labelInstance.LabelBackground.LabelText.LabelTextPadding.PaddingBottom.Offset + labelInstance.LabelPadding.PaddingTop.Offset + labelInstance.LabelPadding.PaddingBottom.Offset + labelInstance.LabelBackground.LabelBackgroundPadding.PaddingTop.Offset + labelInstance.LabelBackground.LabelBackgroundPadding.PaddingBottom.Offset)
	
	return label
end

function labelHandler:ChangeText(newText: string, playAnimation: boolean): nil
	local textParams = Instance.new("GetTextBoundsParams") -- Add Tween here for text
	textParams.Text = newText or "N/A"
	textParams.Font = self.Instance.LabelBackground.LabelText.FontFace
	textParams.Size = 13
	textParams.Width = self.Instance.LabelBackground.LabelText.AbsoluteSize.X
	
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
	
	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Text = tostring(maximumValue) or "N/A"
	textParams.Font = sliderInstance.TextGrouping.NumberText.FontFace
	textParams.Size = 14
	textParams.Width = 10000
	
	local requiredNumberTextSpace = TextService:GetTextBoundsAsync(textParams)
	textParams.Text = "ERR"
	local requiredErrorTextSpace = TextService:GetTextBoundsAsync(textParams)

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

	local function onMouseDown()
		isMouseDown = true
		applyFromX(mouse.X)
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

	sliderInstance.SliderBackground.MouseButton1Down:Connect(onMouseDown)
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
	
	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Text = placeholderText
	textParams.Width = 10000
	textParams.Font = textBoxText.FontFace
	textParams.Size = 14
	
	local requiredPlaceholderTextSpace = TextService:GetTextBoundsAsync(textParams)
	
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
		textParams.Text = textBoxText.Text
		local requiredTextSize = TextService:GetTextBoundsAsync(textParams)
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
	
	local textParams = Instance.new("GetTextBoundsParams")
	textParams.Text = "255"
	textParams.Font = heading.ColorWheelName.FontFace
	textParams.Size = 14
	textParams.Width = 10000
	
	local requiredRgbTextSize = TextService:GetTextBoundsAsync(textParams)
	
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

	local function onSliderMouseDown()
		dragging = true
		applySliderFromX(mouse.X)

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

	local function onWheelMouseDown()
		dragging = true
		applyRingFromXY(mouse.X, mouse.Y)

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
	slider.MouseButton1Down:Connect(onSliderMouseDown)
	wheel.MouseButton1Down:Connect(onWheelMouseDown)
	
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
	pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
        TweenService:Create(img,    TweenInfo.new(t, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Accent}):Play()
        TweenService:Create(imgCorner, TweenInfo.new(t), {CornerRadius = UDim.new(0, 2)}):Play()
        inst.BoxBackground.BackgroundColor3 = Theme.Accent
    else
        -- Reset to dark
        TweenService:Create(inner,  TweenInfo.new(t, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Panel}):Play()
        TweenService:Create(center, TweenInfo.new(t, Enum.EasingStyle.Quad), {BackgroundColor3 = Theme.Panel}):Play()
        TweenService:Create(img,    TweenInfo.new(t, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(0, 0), BackgroundColor3 = Theme.Panel}):Play()
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
        toggleInstance.BoxBackground.Size = UDim2.fromOffset(boxSize, boxSize)
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
        img.Size                = UDim2.fromScale(1, 1)
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
    boxBackground.Size  = UDim2.fromOffset(boxSize.X, boxSize.Y)
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
        boxBackground.Size  = UDim2.fromOffset(origSize.X, origSize.Y)
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
        local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
        if not isMobile then
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
            local viewportSize = workspace.CurrentCamera.ViewportSize
            
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
    shellStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
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
