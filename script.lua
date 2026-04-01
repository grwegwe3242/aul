--[[
    Mommy Dice Roller v3.0 - Session-Persistent, Accurate Roll Counting
    Features: Separate character display window, persistent stats, accurate roll counter
    UI: Rayfield Interface Suite
    Game: Roblox Mommy Gacha Idle
]]

-- Load Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Wait for essential services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Wait for RemoteEvents
local RequestRoll = ReplicatedStorage:WaitForChild("RequestRoll")
local RollResult = ReplicatedStorage:WaitForChild("RollResult")
local BuyDice = ReplicatedStorage:WaitForChild("BuyDice")
local PlaceMommy = ReplicatedStorage:WaitForChild("PlaceMommy")
local RemoveMommy = ReplicatedStorage:WaitForChild("RemoveMommy")
local ClaimPadCash = ReplicatedStorage:WaitForChild("ClaimPadCash")
local GetPadState = ReplicatedStorage:WaitForChild("GetPadState")
local GetDiceStock = ReplicatedStorage:WaitForChild("GetDiceStock")
local DiceStockUpdate = ReplicatedStorage:WaitForChild("DiceStockUpdate")
local GetUpgrades = ReplicatedStorage:WaitForChild("GetUpgrades")
local GetBoosts = ReplicatedStorage:WaitForChild("GetBoosts")
local BuyUpgrade = ReplicatedStorage:WaitForChild("BuyUpgrade")
local BuyBoost = ReplicatedStorage:WaitForChild("BuyBoost")
local EquipBest = ReplicatedStorage:WaitForChild("EquipBest")
local ForceNextRoll = ReplicatedStorage:WaitForChild("ForceNextRoll")
local SyncInventory = ReplicatedStorage:WaitForChild("SyncInventory")
local SyncBackpack = ReplicatedStorage:WaitForChild("SyncBackpack")

-- Mommy Data (cached from server)
local MommyData = require(ReplicatedStorage:WaitForChild("MommyData"))

-- ============================================
-- SESSION-PERSISTENT STATISTICS (survives reloads)
-- ============================================
-- Use _G to persist stats across script reloads within the same game session
local function InitSessionStats()
    if not _G.MommyBotSession then
        _G.MommyBotSession = {
            -- Roll counting (accurate: tracks dice count changes)
            TotalRolls = 0,
            SessionStart = os.time(),
            LastDiceCounts = {},
            
            -- Current pull display
            CurrentPull = nil,
            CurrentPullTime = nil,
            CurrentPullRarity = nil,
            CurrentPullCashPerSec = nil,
            
            -- Session-persistent pull history
            AllPulls = {},           -- All pulls this session
            BestPulls = {},          -- Legendary+ pulls
            RarityCounts = {},       -- Count per rarity
            
            -- Dice-specific counts
            DiceRollCounts = {},     -- Rolls per dice type
            
            -- Cash tracking
            StartingCash = 0,
            TotalCashEarned = 0,
            
            -- Exploit status
            CashMultiplierApplied = false,
        }
    else
        -- Restore from previous session
        local session = _G.MommyBotSession
        if not session.LastDiceCounts then
            session.LastDiceCounts = {}
        end
        if not session.AllPulls then session.AllPulls = {} end
        if not session.BestPulls then session.BestPulls = {} end
        if not session.RarityCounts then session.RarityCounts = {} end
        if not session.DiceRollCounts then session.DiceRollCounts = {} end
    end
    return _G.MommyBotSession
end

local Session = InitSessionStats()

-- ============================================
-- SHOP RESTOCK TRACKING
-- Dice shop restocks every 5 minutes (server-side)
-- DiceStockUpdate fires from server when restock happens
-- ============================================
local ShopRestockTime = 300 -- 5 minutes
local LastRestockCheck = 0
local NextRestockAt = 0

-- Listen for DiceStockUpdate from server
DiceStockUpdate.OnClientEvent:Connect(function(stock, restockIn, isRestock)
    if isRestock then
        LastRestockCheck = os.time()
        NextRestockAt = os.time() + (restockIn or ShopRestockTime)
        -- Auto-buy on restock if enabled
        if State.AutoBuyEnabled then
            task.wait(0.5)
            AutoBuyDice()
        end
    end
end)

-- Initialize restock tracking
task.delay(3, function()
    local success, stockInfo = pcall(function()
        return GetDiceStock:InvokeServer()
    end)
    if success and stockInfo and stockInfo.restockIn then
        LastRestockCheck = os.time()
        NextRestockAt = os.time() + stockInfo.restockIn
    end
end)

-- Forward declarations
local OnRollResult
local TrackPull
local CurrentPullWindow
local StatsParagraph
local DetailedStatsParagraph
local PullsParagraph
local RecentPullsParagraph
local StatusLabel

-- ============================================
-- ACCURATE ROLL COUNTING
-- Uses dice count changes to detect actual rolls
-- ============================================
local function GetDiceCounts()
    local Currency = LocalPlayer:FindFirstChild("Currency")
    if not Currency then return {} end
    
    local counts = {}
    local diceTypes = {"NormalDice", "GoldDice", "DiamondDice", "CrystalIceDice", "CelestialDice", "VoidDice", "LoveDice", "ToxicDice", "LavaDice", "ScaryDice"}
    for _, diceId in ipairs(diceTypes) do
        local val = Currency:FindFirstChild(diceId)
        counts[diceId] = val and val.Value or 0
    end
    return counts
end

-- Count rolls by detecting dice count changes
local function CountNewRolls()
    local currentCounts = GetDiceCounts()
    local newRolls = 0
    local rolledDice = nil
    
    for diceId, count in pairs(currentCounts) do
        local lastCount = Session.LastDiceCounts[diceId] or count
        if count < lastCount then
            newRolls = newRolls + (lastCount - count)
            rolledDice = diceId
        end
    end
    
    -- Update stored counts
    Session.LastDiceCounts = currentCounts
    
    return newRolls, rolledDice
end

-- ============================================
-- HIDE ROLL ANIMATION GUI (keep script running)
-- ============================================
local function HideRollGUI()
    pcall(function()
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
        if not PlayerGui then return end
        
        -- Primary: disable the DiceRollGui ScreenGui entirely
        local DiceRollGui = PlayerGui:FindFirstChild("DiceRollGui")
        if DiceRollGui then
            DiceRollGui.Enabled = false
        end
        
        -- Nuke any GUI with "dice" or "roll" in the name
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            local name = gui.Name:lower()
            if name:find("dice") or name:find("roll") then
                if gui:IsA("ScreenGui") then
                    gui.Enabled = false
                end
            end
        end
    end)
end

-- Aggressive loop: every 0.05 seconds to beat the game's rollAnimation timing
task.spawn(function()
    while true do
        task.wait(0.05)
        HideRollGUI()
    end
end)

-- Also hook RollResult to hide instantly when a roll fires
task.spawn(function()
    RollResult.OnClientEvent:Connect(function()
        HideRollGUI()
    end)
end)

-- ============================================
-- HELPER FUNCTIONS
-- ============================================
local function FormatNumber(num)
    if not num or num == 0 then return "0" end
    if num < 1000 then return tostring(math.floor(num)) end
    if num < 1000000 then return string.format("%.1fK", num / 1000) end
    if num < 1000000000 then return string.format("%.1fM", num / 1000000) end
    if num < 1000000000000 then return string.format("%.1fB", num / 1000000000) end
    return string.format("%.1fT", num / 1000000000000)
end

local function GetCash()
    local Currency = LocalPlayer:FindFirstChild("Currency")
    if Currency then
        local Cash = Currency:FindFirstChild("Cash")
        if Cash then return Cash.Value end
    end
    return 0
end

local function GetOres()
    local Currency = LocalPlayer:FindFirstChild("Currency")
    if Currency then
        local Ores = Currency:FindFirstChild("Ores")
        if Ores then return Ores.Value end
    end
    return 0
end

local function GetDiceCount(diceId)
    local Currency = LocalPlayer:FindFirstChild("Currency")
    if Currency then
        local Dice = Currency:FindFirstChild(diceId)
        if Dice then return Dice.Value end
    end
    return 0
end

local function GetInventory()
    return _G.PlayerInventory
end

local function GetInventoryItems()
    local inv = GetInventory()
    if not inv then return {} end
    local items = {}
    for i = 1, 10 do
        local slot = inv:GetSlot(i)
        if slot and slot.id then
            items[i] = slot
        end
    end
    return items
end

-- ============================================
-- PAD & CASH FUNCTIONS
-- ============================================
local function RefreshPadState()
    local success, result = pcall(function()
        return GetPadState:InvokeServer()
    end)
    if success and result then
        return result
    end
    return {}
end

local function AutoClaimCash()
    -- ClaimPadCash is server→client only. Cash is collected via ProximityPrompt on pads.
    -- We fire the ProximityPrompt directly on each pad that has unclaimed cash.
    local padState = RefreshPadState()
    local claimed = false
    
    -- Method 1: Try to find and fire ProximityPrompts on pads
    pcall(function()
        local workspace = game:GetService("Workspace")
        local plots = workspace:FindFirstChild("Plots") or workspace:FindFirstChild("Plot")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                for _, child in ipairs(plot:GetDescendants()) do
                    if child:IsA("ProximityPrompt") then
                        local promptParent = child.Parent
                        if promptParent and promptParent.Name:lower():find("pad") then
                            local padNum = promptParent.Name:match("(%d+)")
                            if padNum then
                                local padInfo = padState[tostring(padNum)]
                                if padInfo and padInfo.unclaimedCash and padInfo.unclaimedCash > 0 then
                                    fireproximityprompt(child)
                                    claimed = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    
    -- Method 2: Fallback - try to find green-claim-button in PlayerGui and simulate click
    if not claimed then
        pcall(function()
            local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
            if PlayerGui then
                for _, gui in ipairs(PlayerGui:GetDescendants()) do
                    if gui.Name == "green-claim-button" and gui:IsA("TextButton") or gui:IsA("ImageButton") then
                        local cashDisplay = gui:FindFirstChild("CashDisplay")
                        if cashDisplay then
                            local cashLabel = cashDisplay:FindFirstChild("CashLabel")
                            if cashLabel and cashLabel.Text ~= "$0" and cashLabel.Text ~= "0" then
                                fireclickdetector(gui)
                                claimed = true
                            end
                        end
                    end
                end
            end
        end)
    end
    
    return claimed
end

-- ============================================
-- EXPLOITS (confirmed working from test suite)
-- ============================================
local function ApplyCashMultiplier(multiplier)
    _G.ClientCashMultiplier = multiplier or 999
    Session.CashMultiplierApplied = true
    return _G.ClientCashMultiplier == (multiplier or 999)
end

local function ForceNextRollMommy(mommyName)
    return pcall(function()
        ForceNextRoll:FireServer(mommyName)
    end)
end

local function EquipBestRapid(count)
    count = count or 3
    for i = 1, count do
        pcall(function()
            EquipBest:FireServer()
        end)
    end
end

local function AutoPlaceBestMommy()
    EquipBestRapid(3)
    return true
end

-- ============================================
-- AUTO-BUY FUNCTIONS (buys ALL dice)
-- ============================================
local DiceDefs = {
    {id = "NormalDice", name = "Normal Dice", luck = 1, tier = 1, price = 0},
    {id = "GoldDice", name = "Gold Dice", luck = 3, tier = 2, price = 500},
    {id = "DiamondDice", name = "Diamond Dice", luck = 8, tier = 3, price = 5000},
    {id = "CrystalIceDice", name = "Crystal Ice Dice", luck = 15, tier = 4, price = 25000},
    {id = "CelestialDice", name = "Celestial Dice", luck = 45, tier = 5, price = 100000},
    {id = "VoidDice", name = "Void Dice", luck = 113, tier = 6, price = 500000},
    {id = "LoveDice", name = "Love Dice", luck = 255, tier = 7, price = 2500000},
    {id = "ToxicDice", name = "Toxic Dice", luck = 563, tier = 8, price = 10000000},
    {id = "LavaDice", name = "Lava Dice", luck = 1275, tier = 9, price = 50000000},
    {id = "ScaryDice", name = "Scary Dice", luck = 3000, tier = 10, price = 250000000}
}

local DiceIdToName = {}
for _, d in ipairs(DiceDefs) do
    DiceIdToName[d.id] = d.name
end

-- Auto-buy: buys ALL dice in shop, highest tier first
local function AutoBuyDice()
    local cash = GetCash()
    if cash <= 0 then return false end
    
    local stockInfo
    local success = pcall(function()
        stockInfo = GetDiceStock:InvokeServer()
    end)
    if not success or not stockInfo then return false end
    
    local bought = false
    
    -- Buy ALL dice in stock, prioritizing highest luck first
    -- Sort by luck descending
    local sortedDice = {}
    for _, def in ipairs(stockInfo.defs or {}) do
        table.insert(sortedDice, def)
    end
    table.sort(sortedDice, function(a, b) return a.luck > b.luck end)
    
    for _, def in ipairs(sortedDice) do
        local stock = stockInfo.stock[def.id] or 0
        if stock > 0 and cash >= def.price then
            local affordable = math.min(stock, math.floor(cash / def.price))
            if affordable > 0 then
                BuyDice:FireServer(def.id, affordable)
                cash = cash - (def.price * affordable)
                bought = true
            end
        end
    end
    
    return bought
end

-- ============================================
-- AUTO-UPGRADE & AUTO-BOOST
-- ============================================
local function AutoUpgrade()
    local success, upgrades = pcall(function()
        return GetUpgrades:InvokeServer()
    end)
    if not success or not upgrades or not upgrades.defs then return false end
    
    local cash = GetCash()
    local ores = GetOres()
    local upgradeOrder = {"luck", "rollSpeed", "cash", "speed", "oreGen"}
    
    for _, upgradeId in ipairs(upgradeOrder) do
        for _, def in ipairs(upgrades.defs) do
            if def.id == upgradeId then
                local currentLevel = upgrades.levels[upgradeId] or 0
                if currentLevel < def.maxLevel then
                    local cost = def.costType == "ores" and ores or cash
                    local price = def.costType == "ores" and def.oreCost or (upgradeId == "rollSpeed" and (currentLevel + 1) * 2 or math.floor(def.baseCost * def.costMult ^ currentLevel))
                    if cost >= price then
                        BuyUpgrade:FireServer(upgradeId)
                        return true
                    end
                end
                break
            end
        end
    end
    return false
end

local function AutoBoost()
    local success, boosts = pcall(function()
        return GetBoosts:InvokeServer()
    end)
    if not success or not boosts or not boosts.defs then return false end
    
    local ores = GetOres()
    if ores <= 0 then return false end
    
    local activeBoosts = {}
    if boosts.boosts then
        for _, active in ipairs(boosts.boosts) do
            if active.remaining and active.remaining > 0 then
                activeBoosts[active.id] = true
            end
        end
    end
    
    for _, boostId in ipairs({"luck5x", "luck2x", "cash2x"}) do
        for _, def in ipairs(boosts.defs) do
            if def.id == boostId and not activeBoosts[boostId] and ores >= def.oreCost then
                BuyBoost:FireServer(boostId, 1)
                return true
            end
        end
    end
    return false
end

-- ============================================
-- ROLL FUNCTIONS
-- ============================================
local State = {
    IsRolling = false,
    AutoRollEnabled = false,
    AutoBuyEnabled = false,
    AutoPlaceEnabled = false,
    AutoClaimEnabled = false,
    AutoUpgradeEnabled = false,
    AutoBoostEnabled = false,
    SelectedDice = "NormalDice",
    RollDelay = 0.5,
    LastRolledDice = nil,
}

local function GetOwnedDice()
    local owned = {}
    for _, d in ipairs(DiceDefs) do
        if GetDiceCount(d.id) > 0 then
            table.insert(owned, d.id)
        end
    end
    return owned
end

local function GetNextDiceForRollAll()
    local owned = GetOwnedDice()
    if #owned == 0 then return nil end
    Session.RollAllIndex = (Session.RollAllIndex or 0) % #owned + 1
    return owned[Session.RollAllIndex]
end

local function RollDice(diceId)
    if State.IsRolling then return false end
    if GetDiceCount(diceId) <= 0 then return false end
    
    State.IsRolling = true
    State.LastRolledDice = diceId
    Session.LastRolledDice = diceId
    
    task.defer(function()
        RequestRoll:FireServer(diceId)
    end)
    
    return true
end

-- ============================================
-- PULL TRACKING
-- ============================================
local RarityPriority = {
    ["???"] = 11, Cartoon = 10, Shiny = 9, Divine = 8, Secret = 7,
    Mythical = 6, Legendary = 5, Epic = 4, Rare = 3, Uncommon = 2, Common = 1
}

local RarityColors = {
    Common = Color3.fromRGB(200, 200, 210), Uncommon = Color3.fromRGB(80, 200, 95),
    Rare = Color3.fromRGB(55, 150, 240), Epic = Color3.fromRGB(165, 80, 225),
    Legendary = Color3.fromRGB(255, 200, 50), Mythical = Color3.fromRGB(255, 80, 180),
    Secret = Color3.fromRGB(180, 170, 200), Divine = Color3.fromRGB(255, 220, 50),
    Shiny = Color3.fromRGB(210, 220, 230), Cartoon = Color3.fromRGB(255, 150, 60),
    ["???"] = Color3.fromRGB(255, 255, 255)
}

function TrackPull(mommyId)
    local data = MommyData[mommyId]
    if not data then return end
    
    local rarity = data.rarity
    local priority = RarityPriority[rarity] or 0
    local now = os.date("%H:%M:%S")
    
    -- Update rarity counts (session-persistent)
    Session.RarityCounts[rarity] = (Session.RarityCounts[rarity] or 0) + 1
    
    -- Track all pulls (session-persistent, last 100)
    table.insert(Session.AllPulls, {
        name = data.displayName,
        rarity = rarity,
        cashPerSecond = data.cashPerSecond,
        time = now,
        diceId = Session.LastRolledDice or "Unknown"
    })
    if #Session.AllPulls > 100 then table.remove(Session.AllPulls, 1) end
    
    -- Track best pulls (Legendary+, session-persistent, last 50)
    if priority >= 5 then
        table.insert(Session.BestPulls, {
            name = data.displayName,
            rarity = rarity,
            cashPerSecond = data.cashPerSecond,
            time = now,
            diceId = Session.LastRolledDice or "Unknown"
        })
        if #Session.BestPulls > 50 then table.remove(Session.BestPulls, 1) end
    end
    
    -- Update dice roll counts
    local diceId = Session.LastRolledDice or "Unknown"
    Session.DiceRollCounts[diceId] = (Session.DiceRollCounts[diceId] or 0) + 1
    
    -- Update current pull display (session-persistent)
    Session.CurrentPull = data.displayName
    Session.CurrentPullTime = now
    Session.CurrentPullRarity = rarity
    Session.CurrentPullCashPerSec = data.cashPerSecond
end

-- ============================================
-- ROLL RESULT HANDLER
-- ============================================
OnRollResult = function(mommyId, extraData)
    if mommyId == "__REJECTED__" then
        State.IsRolling = false
        return
    end
    
    if mommyId == "__ANNOUNCEMENT__" then
        return
    end
    
    State.IsRolling = false
    
    -- ACCURATE ROLL COUNTING: detect actual dice consumed
    local newRolls, rolledDice = CountNewRolls()
    if newRolls > 0 then
        Session.TotalRolls = Session.TotalRolls + newRolls
        if rolledDice then
            Session.LastRolledDice = rolledDice
            State.LastRolledDice = rolledDice
        end
    else
        -- Fallback: count from RollResult event
        Session.TotalRolls = Session.TotalRolls + 1
    end
    
    -- Track the pull
    TrackPull(mommyId)
    
    -- Update current pull display
    local data = MommyData[mommyId]
    if data then
        local color = RarityColors[data.rarity] or Color3.fromRGB(255, 255, 255)
        
        -- Update current pull window
        if CurrentPullWindow then
            CurrentPullWindow:Set({
                Title = "Current Pull",
                Content = string.format(
                    "Name: %s\nRarity: %s\nCash/s: %s\nTime: %s\nDice: %s",
                    data.displayName,
                    data.rarity,
                    FormatNumber(data.cashPerSecond),
                    Session.CurrentPullTime or os.date("%H:%M:%S"),
                    DiceIdToName[Session.LastRolledDice] or Session.LastRolledDice or "Unknown"
                )
            })
            CurrentPullWindow.Color = color
        end
        
        -- Update pull result label
        if PullResultLabel then
            PullResultLabel:Set(
                string.format("[%s] %s (%s) - %s/s", 
                    Session.CurrentPullTime or os.date("%H:%M:%S"),
                    data.displayName,
                    data.rarity,
                    FormatNumber(data.cashPerSecond)
                ),
                "success",
                color
            )
        end
    end
    
    -- Auto-place after roll
    if State.AutoPlaceEnabled then
        task.wait(0.1)
        AutoPlaceBestMommy()
    end
    
    -- Auto-claim after roll
    if State.AutoClaimEnabled then
        task.wait(0.2)
        AutoClaimCash()
    end
end

-- ============================================
-- SETUP ROLL HANDLER
-- ============================================
local function SetupRollHandler()
    HideRollGUI()
    RollResult.OnClientEvent:Connect(OnRollResult)
    
    -- Initialize dice counts for accurate roll counting
    Session.LastDiceCounts = GetDiceCounts()
end

task.delay(2, SetupRollHandler)
task.delay(5, SetupRollHandler)

-- ============================================
-- RAYFIELD UI
-- ============================================
local Window = Rayfield:CreateWindow({
    Name = "Mommy Auto Bot v3.0",
    Icon = "dice-5",
    LoadingTitle = "Loading Bot...",
    LoadingSubtitle = "Session-Persistent Auto Roller",
    ShowText = "MommyBot",
    Theme = "Default",
    ToggleUIKeybind = Enum.KeyCode.K,
    DisableRayfieldPrompts = true,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "MommyBot",
        FileName = "MommyAutoBot_v3"
    }
})

-- ============================================
-- MAIN TAB
-- ============================================
local MainTab = Window:CreateTab("Main", "play")

local ControlsSection = MainTab:CreateSection("Controls")

-- Auto Roll Toggle
local AutoRollToggle = MainTab:CreateToggle({
    Name = "Auto Roll",
    CurrentValue = false,
    Flag = "AutoRoll",
    Callback = function(Value)
        State.AutoRollEnabled = Value
        if Value then
            Session.LastDiceCounts = GetDiceCounts()
        end
    end
})

-- Auto Buy Toggle
local AutoBuyToggle = MainTab:CreateToggle({
    Name = "Auto Buy Dice (buys ALL)",
    CurrentValue = false,
    Flag = "AutoBuy",
    Callback = function(Value)
        State.AutoBuyEnabled = Value
    end
})

-- Auto Place Toggle
local AutoPlaceToggle = MainTab:CreateToggle({
    Name = "Auto Place Best Units (EquipBest x3)",
    CurrentValue = false,
    Flag = "AutoPlace",
    Callback = function(Value)
        State.AutoPlaceEnabled = Value
    end
})

-- Auto Claim Toggle
local AutoClaimToggle = MainTab:CreateToggle({
    Name = "Auto Claim Cash",
    CurrentValue = false,
    Flag = "AutoClaim",
    Callback = function(Value)
        State.AutoClaimEnabled = Value
    end
})

-- Auto Upgrade Toggle
local AutoUpgradeToggle = MainTab:CreateToggle({
    Name = "Auto Upgrade Stats",
    CurrentValue = false,
    Flag = "AutoUpgrade",
    Callback = function(Value)
        State.AutoUpgradeEnabled = Value
    end
})

-- Auto Boost Toggle
local AutoBoostToggle = MainTab:CreateToggle({
    Name = "Auto Buy Boosts (Ores)",
    CurrentValue = false,
    Flag = "AutoBoost",
    Callback = function(Value)
        State.AutoBoostEnabled = Value
    end
})

-- Dice Selection
local DiceDropdown = MainTab:CreateDropdown({
    Name = "Selected Dice",
    Options = {"Normal Dice", "Gold Dice", "Diamond Dice", "Crystal Ice Dice", "Celestial Dice", "Void Dice", "Love Dice", "Toxic Dice", "Lava Dice", "Scary Dice"},
    CurrentOption = {"Normal Dice"},
    MultipleOptions = false,
    Flag = "DiceSelect",
    Callback = function(Options)
        local diceMap = {
            ["Normal Dice"] = "NormalDice", ["Gold Dice"] = "GoldDice",
            ["Diamond Dice"] = "DiamondDice", ["Crystal Ice Dice"] = "CrystalIceDice",
            ["Celestial Dice"] = "CelestialDice", ["Void Dice"] = "VoidDice",
            ["Love Dice"] = "LoveDice", ["Toxic Dice"] = "ToxicDice",
            ["Lava Dice"] = "LavaDice", ["Scary Dice"] = "ScaryDice"
        }
        State.SelectedDice = diceMap[Options[1]] or "NormalDice"
    end
})

-- Roll Speed Slider
local RollSpeedSlider = MainTab:CreateSlider({
    Name = "Roll Delay (seconds)",
    Range = {0.1, 5},
    Increment = 0.1,
    Suffix = "s",
    CurrentValue = 0.5,
    Flag = "RollDelay",
    Callback = function(Value)
        State.RollDelay = Value
    end
})

-- Action Buttons
local RollButton = MainTab:CreateButton({
    Name = "Roll Once",
    Callback = function()
        RollDice(State.SelectedDice)
    end
})

local RollAllButton = MainTab:CreateButton({
    Name = "Roll All Owned Dice",
    Callback = function()
        local owned = GetOwnedDice()
        if #owned == 0 then
            Rayfield:Notify({Title = "No Dice", Content = "You don't own any dice!", Duration = 3, Image = "alert-circle"})
            return
        end
        task.spawn(function()
            for _, diceId in ipairs(owned) do
                while State.IsRolling do task.wait(0.1) end
                RollDice(diceId)
                task.wait(State.RollDelay or 0.5)
            end
        end)
    end
})

local ClaimButton = MainTab:CreateButton({
    Name = "Claim All Cash",
    Callback = function()
        AutoClaimCash()
    end
})

local PlaceButton = MainTab:CreateButton({
    Name = "Place Best Units",
    Callback = function()
        AutoPlaceBestMommy()
    end
})

local BuyDiceButton = MainTab:CreateButton({
    Name = "Buy All Dice in Shop",
    Callback = function()
        AutoBuyDice()
    end
})

-- ============================================
-- EXPLOITS SECTION
-- ============================================
local ExploitsSection = MainTab:CreateSection("Exploits (Test Suite Verified)")

local CashMultToggle = MainTab:CreateToggle({
    Name = "999x Cash Multiplier",
    CurrentValue = true,
    Flag = "CashMultiplier",
    Callback = function(Value)
        if Value then
            ApplyCashMultiplier(999)
        else
            _G.ClientCashMultiplier = 1
            Session.CashMultiplierApplied = false
        end
    end
})

local ForceRollToggle = MainTab:CreateToggle({
    Name = "Force Next Roll",
    CurrentValue = false,
    Flag = "ForceRoll",
    Callback = function(Value)
        if Value then
            ForceNextRollMommy("Divine")
        end
    end
})

local ForceRollDropdown = MainTab:CreateDropdown({
    Name = "Force Roll Target",
    Options = {"Divine", "Cartoon", "Shiny", "Secret", "Mythical", "Legendary"},
    CurrentOption = {"Divine"},
    MultipleOptions = false,
    Flag = "ForceRollTarget",
    Callback = function(Options)
        ForceNextRollMommy(Options[1])
    end
})

local EquipBestRapidToggle = MainTab:CreateToggle({
    Name = "EquipBest Rapid-Fire (3x)",
    CurrentValue = false,
    Flag = "EquipBestRapid",
    Callback = function(Value)
        if Value then EquipBestRapid(3) end
    end
})

-- Status Labels
StatusLabel = MainTab:CreateLabel("Waiting to start...", "info", Color3.fromRGB(150, 150, 160))
PullResultLabel = MainTab:CreateLabel("No pulls yet", "info", Color3.fromRGB(150, 150, 160))

-- ============================================
-- CURRENT PULL TAB (separate window)
-- ============================================
local PullTab = Window:CreateTab("Current Pull", "eye")

CurrentPullWindow = PullTab:CreateParagraph({
    Title = "Current Pull",
    Content = "No pulls yet. Start rolling to see results here."
})

local PullsSection = PullTab:CreateSection("Session Statistics")

StatsParagraph = PullTab:CreateParagraph({
    Title = "Session Statistics",
    Content = "Loading..."
})

DetailedStatsParagraph = PullTab:CreateParagraph({
    Title = "Detailed Statistics",
    Content = "Loading..."
})

-- ============================================
-- BEST PULLS TAB
-- ============================================
local BestPullsTab = Window:CreateTab("Best Pulls", "star")

local BestPullsSection = BestPullsTab:CreateSection("Legendary+ Pulls (Session)")

PullsParagraph = BestPullsTab:CreateParagraph({
    Title = "Best Pulls This Session",
    Content = "No legendary+ pulls yet..."
})

RecentPullsParagraph = BestPullsTab:CreateParagraph({
    Title = "Recent Pulls (All Rarities)",
    Content = "No pulls yet..."
})

-- ============================================
-- SETTINGS TAB
-- ============================================
local SettingsTab = Window:CreateTab("Settings", "settings")

local SettingsSection = SettingsTab:CreateSection("Bot Settings")

local StopAllButton = SettingsTab:CreateButton({
    Name = "Stop All Automation",
    Callback = function()
        State.AutoRollEnabled = false
        State.AutoBuyEnabled = false
        State.AutoPlaceEnabled = false
        State.AutoClaimEnabled = false
        State.AutoUpgradeEnabled = false
        State.AutoBoostEnabled = false
        AutoRollToggle:Set(false)
        AutoBuyToggle:Set(false)
        AutoPlaceToggle:Set(false)
        AutoClaimToggle:Set(false)
        AutoUpgradeToggle:Set(false)
        AutoBoostToggle:Set(false)
    end
})

local ResetSessionButton = SettingsTab:CreateButton({
    Name = "Reset Session Stats",
    Callback = function()
        _G.MommyBotSession = nil
        Session = InitSessionStats()
        Session.LastDiceCounts = GetDiceCounts()
        Session.StartingCash = GetCash()
        Rayfield:Notify({Title = "Session Reset", Content = "Statistics cleared.", Duration = 3, Image = "rotate-ccw"})
    end
})

-- ============================================
-- STATISTICS UPDATE LOOP
-- ============================================
local function UpdateStats()
    local cash = GetCash()
    local ores = GetOres()
    local sessionTime = os.time() - Session.SessionStart
    local hours = math.floor(sessionTime / 3600)
    local minutes = math.floor((sessionTime % 3600) / 60)
    local seconds = sessionTime % 60
    local timeStr = string.format("%02d:%02d:%02d", hours, minutes, seconds)
    local rpm = Session.TotalRolls / math.max(1, sessionTime / 60)
    
    -- Calculate cash earned this session
    local startingCash = Session.StartingCash
    if startingCash == 0 then
        Session.StartingCash = cash
        startingCash = cash
    end
    local cashEarned = math.max(0, cash - startingCash)
    Session.TotalCashEarned = cashEarned
    
    -- Status bar
    local statusText = string.format(
        "Rolls: %d (%.1f/min) | Cash: $%s | Ores: %s | CashMult: %sx",
        Session.TotalRolls,
        rpm,
        FormatNumber(cash),
        FormatNumber(ores),
        _G.ClientCashMultiplier or 1
    )
    if StatusLabel then
        StatusLabel:Set(statusText, "activity", State.AutoRollEnabled and Color3.fromRGB(80, 220, 95) or Color3.fromRGB(150, 150, 160))
    end
    
    -- Stats paragraph
    if StatsParagraph then
        local raritySummary = ""
        for rarity, count in pairs(Session.RarityCounts) do
            if count > 0 then
                raritySummary = raritySummary .. string.format("  %s: %d\n", rarity, count)
            end
        end
        if raritySummary == "" then raritySummary = "  None yet\n" end
        
        StatsParagraph:Set({
            Title = "Session Statistics",
            Content = string.format(
                "Total Rolls: %d\nRolls/Min: %.1f\nSession Time: %s\nCash Earned: $%s\n\nRarity Breakdown:\n%s",
                Session.TotalRolls,
                rpm,
                timeStr,
                FormatNumber(cashEarned),
                raritySummary
            )
        })
    end
    
    -- Detailed stats
    if DetailedStatsParagraph then
        local diceBreakdown = ""
        for diceId, count in pairs(Session.DiceRollCounts) do
            diceBreakdown = diceBreakdown .. string.format("  %s: %d rolls\n", DiceIdToName[diceId] or diceId, count)
        end
        if diceBreakdown == "" then diceBreakdown = "  None yet\n" end
        
        DetailedStatsParagraph:Set({
            Title = "Detailed Statistics",
            Content = string.format(
                "Dice Breakdown:\n%s\nOwned Dice:\n%s",
                diceBreakdown,
                GetOwnedDiceSummary()
            )
        })
    end
    
    -- Best pulls
    if PullsParagraph then
        local content = ""
        if #Session.BestPulls == 0 then
            content = "No legendary+ pulls this session."
        else
            for i = #Session.BestPulls, 1, -1 do
                local pull = Session.BestPulls[i]
                content = content .. string.format("[%s] %s (%s) via %s - %s/s\n", pull.time, pull.name, pull.rarity, DiceIdToName[pull.diceId] or pull.diceId, FormatNumber(pull.cashPerSecond))
            end
        end
        PullsParagraph:Set({Title = "Best Pulls This Session", Content = content})
    end
    
    -- Recent pulls
    if RecentPullsParagraph then
        local content = ""
        if #Session.AllPulls == 0 then
            content = "No pulls yet."
        else
            for i = #Session.AllPulls, 1, -1 do
                local pull = Session.AllPulls[i]
                content = content .. string.format("[%s] %s (%s) via %s - %s/s\n", pull.time, pull.name, pull.rarity, DiceIdToName[pull.diceId] or pull.diceId, FormatNumber(pull.cashPerSecond))
            end
        end
        RecentPullsParagraph:Set({Title = "Recent Pulls (All Rarities)", Content = content})
    end
end

function GetOwnedDiceSummary()
    local owned = GetOwnedDice()
    if #owned == 0 then return "  None\n" end
    local summary = ""
    for _, diceId in ipairs(owned) do
        summary = summary .. string.format("  %s: x%d\n", DiceIdToName[diceId] or diceId, GetDiceCount(diceId))
    end
    return summary
end

-- ============================================
-- SERVER HOPPER MODE (autoexec compatible)
-- Joins different servers, buys all dice, rolls them
-- Repeats until target dice count is reached
-- ============================================
-- ENABLE THIS FLAG TO ACTIVATE SERVER HOPPER:
local SERVER_HOPPER_ENABLED = false  -- Set to true to enable
local SERVER_HOPPER_TARGET_SCARY = 200  -- Target ScaryDice count before stopping
local SERVER_HOPPER_MAX_SERVERS = 50    -- Max servers to try before giving up
local SERVER_HOPPER_MIN_DICE = 1000     -- Min total dice to buy per server

-- Server hopper state
local ServerHopperState = {
    IsRunning = false,
    ServersVisited = 0,
    TotalDiceBought = 0,
    TotalDiceRolled = 0,
    ScaryDiceCollected = 0,
    CurrentServerId = nil,
    LastHopTime = 0,
}

-- Get current server ID (jobId)
local function GetCurrentServerId()
    return game.JobId
end

-- Hop to a different server
local function HopToNewServer()
    local currentJobId = GetCurrentServerId()
    local gameId = game.PlaceId
    
    -- Get list of servers
    local success, servers = pcall(function()
        local response = request({
            Url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100", gameId),
            Method = "GET",
        })
        if response.Success then
            return game:GetService("HttpService"):JSONDecode(response.Body)
        end
        return nil
    end)
    
    if not success or not servers or not servers.data then
        -- Fallback: use Roblox's built-in server hop
        game:GetService("TeleportService"):TeleportToPlaceInstance(gameId, currentJobId, LocalPlayer)
        return false
    end
    
    -- Find a different server
    for _, server in ipairs(servers.data) do
        if server.id and server.id ~= currentJobId and server.playing and server.playing > 0 then
            -- Teleport to this server
            game:GetService("TeleportService"):TeleportToPlaceInstance(gameId, server.id, LocalPlayer)
            ServerHopperState.CurrentServerId = server.id
            return true
        end
    end
    
    -- Fallback: random server
    game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    return false
end

-- Buy all dice on current server
local function BuyAllDiceOnServer()
    local cash = GetCash()
    local totalBought = 0
    
    local stockInfo
    local success = pcall(function()
        stockInfo = GetDiceStock:InvokeServer()
    end)
    
    if not success or not stockInfo then return 0 end
    
    -- Sort by luck descending (buy best first)
    local sortedDice = {}
    for _, def in ipairs(stockInfo.defs or {}) do
        table.insert(sortedDice, def)
    end
    table.sort(sortedDice, function(a, b) return a.luck > b.luck end)
    
    for _, def in ipairs(sortedDice) do
        local stock = stockInfo.stock[def.id] or 0
        if stock > 0 and cash >= def.price then
            local affordable = math.min(stock, math.floor(cash / def.price))
            if affordable > 0 then
                BuyDice:FireServer(def.id, affordable)
                cash = cash - (def.price * affordable)
                totalBought = totalBought + affordable
            end
        end
    end
    
    return totalBought
end

-- Roll all owned dice
local function RollAllOwnedDice()
    local owned = GetOwnedDice()
    local totalRolled = 0
    
    for _, diceId in ipairs(owned) do
        local count = GetDiceCount(diceId)
        while count > 0 and not State.IsRolling do
            RollDice(diceId)
            -- Wait for roll to complete
            local timeout = 0
            while State.IsRolling and timeout < 10 do
                task.wait(0.1)
                timeout = timeout + 0.1
            end
            count = count - 1
            totalRolled = totalRolled + 1
        end
    end
    
    return totalRolled
end

-- Main server hopper loop
local function ServerHopperLoop()
    if not SERVER_HOPPER_ENABLED then return end
    
    ServerHopperState.IsRunning = true
    ServerHopperState.ServersVisited = 0
    ServerHopperState.TotalDiceBought = 0
    ServerHopperState.TotalDiceRolled = 0
    ServerHopperState.ScaryDiceCollected = GetDiceCount("ScaryDice")
    
    print("[ServerHopper] Starting server hopper...")
    print(string.format("[ServerHopper] Target: %d ScaryDice, Current: %d", 
        SERVER_HOPPER_TARGET_SCARY, ServerHopperState.ScaryDiceCollected))
    
    while ServerHopperState.ScaryDiceCollected < SERVER_HOPPER_TARGET_SCARY 
          and ServerHopperState.ServersVisited < SERVER_HOPPER_MAX_SERVERS do
        
        -- Wait for game to load after teleport
        task.wait(5)
        
        -- Check if we have enough cash
        local cash = GetCash()
        if cash < 1000 then
            print("[ServerHopper] Not enough cash to buy dice, farming...")
            -- Enable auto-roll to farm cash
            State.AutoRollEnabled = true
            task.wait(30) -- Farm for 30 seconds
            State.AutoRollEnabled = false
            -- Hop to next server anyway
        else
            -- Buy all dice
            local bought = BuyAllDiceOnServer()
            ServerHopperState.TotalDiceBought = ServerHopperState.TotalDiceBought + bought
            print(string.format("[ServerHopper] Bought %d dice on server %d", bought, ServerHopperState.ServersVisited + 1))
            
            -- Roll all dice
            local rolled = RollAllOwnedDice()
            ServerHopperState.TotalDiceRolled = ServerHopperState.TotalDiceRolled + rolled
            print(string.format("[ServerHopper] Rolled %d dice", rolled))
            
            -- Update ScaryDice count
            ServerHopperState.ScaryDiceCollected = GetDiceCount("ScaryDice")
        end
        
        -- Hop to next server
        ServerHopperState.ServersVisited = ServerHopperState.ServersVisited + 1
        print(string.format("[ServerHopper] Server %d/%d - ScaryDice: %d/%d",
            ServerHopperState.ServersVisited, SERVER_HOPPER_MAX_SERVERS,
            ServerHopperState.ScaryDiceCollected, SERVER_HOPPER_TARGET_SCARY))
        
        if ServerHopperState.ScaryDiceCollected >= SERVER_HOPPER_TARGET_SCARY then
            print("[ServerHopper] Target reached! Stopping.")
            break
        end
        
        -- Wait before hopping (avoid rate limits)
        task.wait(2)
        HopToNewServer()
    end
    
    ServerHopperState.IsRunning = false
    print("[ServerHopper] Finished!")
    print(string.format("[ServerHopper] Stats: %d servers, %d dice bought, %d dice rolled, %d ScaryDice",
        ServerHopperState.ServersVisited, ServerHopperState.TotalDiceBought,
        ServerHopperState.TotalDiceRolled, ServerHopperState.ScaryDiceCollected))
end

-- Start server hopper if enabled
if SERVER_HOPPER_ENABLED then
    task.delay(5, ServerHopperLoop)
end

-- ============================================
-- MAIN AUTOMATION LOOP
-- ============================================
task.spawn(function()
    -- Initialize
    task.wait(3)
    Session.LastDiceCounts = GetDiceCounts()
    Session.StartingCash = GetCash()
    
    -- Apply cash multiplier
    ApplyCashMultiplier(999)
    
    while true do
        task.wait(0.5)
        
        -- Update stats
        UpdateStats()
        
        -- Maintain cash multiplier
        if _G.ClientCashMultiplier ~= 999 then
            ApplyCashMultiplier(999)
        end
        
        -- Auto Roll
        if State.AutoRollEnabled and not State.IsRolling then
            local nextDice = GetNextDiceForRollAll()
            if nextDice then
                State.SelectedDice = nextDice
                RollDice(nextDice)
            elseif State.AutoBuyEnabled then
                AutoBuyDice()
            end
        end
        
        -- Auto Buy (works during rolling)
        if State.AutoBuyEnabled then
            AutoBuyDice()
        end
        
        -- Auto Upgrade (works during rolling)
        if State.AutoUpgradeEnabled and os.time() - (Session.LastUpgradeCheck or 0) >= 3 then
            AutoUpgrade()
            Session.LastUpgradeCheck = os.time()
        end
        
        -- Auto Boost (works during rolling)
        if State.AutoBoostEnabled and os.time() - (Session.LastBoostCheck or 0) >= 5 then
            AutoBoost()
            Session.LastBoostCheck = os.time()
        end
        
        -- Auto Claim (periodic)
        if State.AutoClaimEnabled then
            AutoClaimCash()
        end
        
        -- Auto Place (periodic)
        if State.AutoPlaceEnabled then
            AutoPlaceBestMommy()
        end
        
        -- Delay between rolls
        if State.AutoRollEnabled then
            task.wait(State.RollDelay or 0.5)
        end
    end
end)

-- Periodic UI refresh
task.spawn(function()
    while true do
        task.wait(5)
        UpdateStats()
    end
end)

-- Load config
Rayfield:LoadConfiguration()

Rayfield:Notify({
    Title = "Mommy Auto Bot v3.0",
    Content = "Session-persistent stats, accurate roll counting, separate pull display",
    Duration = 5,
    Image = "dice-5"
})
