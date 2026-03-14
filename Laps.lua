-------------------------------------------------------------------------------
-- Laps - Silvermoon City Lap Tracker
-- Tracks laps around the main building in Silvermoon City
-------------------------------------------------------------------------------

local ADDON_NAME        = "Laps"
local SILVERMOON_MAP_ID = 2393
local PROXIMITY_RADIUS  = 2.5   -- coordinate units (0-100 scale)
local MAX_TOP_LAPS      = 10

-------------------------------------------------------------------------------
-- Node definitions (map % coordinates)
-- Order: North → West → South → East (clockwise)
-------------------------------------------------------------------------------
local NODES = {
    { x = 45.72, y = 63.03 },  -- [1] North  (start/finish)
    { x = 40.63, y = 70.23 },  -- [2] West
    { x = 45.70, y = 78.20 },  -- [3] South
    { x = 50.59, y = 70.26 },  -- [4] East
}

-------------------------------------------------------------------------------
-- Tracker state
-------------------------------------------------------------------------------
local state = {
    -- position tracking
    node        = 0,     -- last confirmed node (1-based); 0 = haven't started circuit
    direction   = nil,   -- nil = undecided, 1 = CW, 2 = CCW

    -- session stats
    laps        = 0,
    totalTime   = 0,
    lapStartTime = nil,
    pauseOffset = 0,     -- elapsed seconds saved at the moment of pause

    -- run control
    running     = false,
    paused      = false,

    -- movement auto-control
    wasMoving   = false,
}

-------------------------------------------------------------------------------
-- Forward declarations
-------------------------------------------------------------------------------
local StartTracking, StopTracking, PauseTracking
local RefreshUI, frame

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function PlayerNearNode(node)
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID ~= SILVERMOON_MAP_ID then return false end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return false end
    local px, py = pos:GetXY()
    px, py = px * 100, py * 100
    local dx, dy = px - node.x, py - node.y
    return (dx * dx + dy * dy) < (PROXIMITY_RADIUS * PROXIMITY_RADIUS)
end

local function PlayerNearAnyNode()
    for _, node in ipairs(NODES) do
        if PlayerNearNode(node) then return true end
    end
    return false
end

local function IsPlayerMoving()
    return GetUnitSpeed("player") > 0
end

local function FormatTime(seconds)
    if not seconds then return "--:--.--" end
    local m  = math.floor(seconds / 60)
    local s  = math.floor(seconds % 60)
    local cs = math.floor((seconds % 1) * 100)
    return string.format("%02d:%02d.%02d", m, s, cs)
end

-------------------------------------------------------------------------------
-- Top-10 management
-------------------------------------------------------------------------------
local function InsertTopLap(t)
    if not t or t <= 0 then return end
    LapsDB.topLaps = LapsDB.topLaps or {}
    table.insert(LapsDB.topLaps, t)
    table.sort(LapsDB.topLaps)
    while #LapsDB.topLaps > MAX_TOP_LAPS do
        table.remove(LapsDB.topLaps, MAX_TOP_LAPS + 1)
    end
end

local function PrintTopLaps()
    local tops = LapsDB and LapsDB.topLaps
    if not tops or #tops == 0 then
        print("|cffFFD700Laps|r: No top laps recorded yet.")
        return
    end
    print("|cffFFD700Laps — Top " .. #tops .. " Best Laps:|r")
    for i, t in ipairs(tops) do
        local tag
        if     i == 1 then tag = "|cffFFD700#1|r"
        elseif i == 2 then tag = "|cffC0C0C0#2|r"
        elseif i == 3 then tag = "|cffCD7F32#3|r"
        else                tag = "|cffFFFFFF#" .. i .. "|r"
        end
        print(string.format("  %s  %s", tag, FormatTime(t)))
    end
end

-------------------------------------------------------------------------------
-- Persist session stats (top laps updated in-place by InsertTopLap)
-------------------------------------------------------------------------------
local function SaveDB()
    LapsDB = LapsDB or {}
    LapsDB.laps      = state.laps
    LapsDB.totalTime = state.totalTime
end

-------------------------------------------------------------------------------
-- Lap completed
-------------------------------------------------------------------------------
local function OnLapComplete()
    local now     = GetTime()
    local lapTime = (now - state.lapStartTime) - state.pauseOffset

    state.laps        = state.laps + 1
    state.totalTime   = state.totalTime + lapTime
    state.lapStartTime = now
    state.pauseOffset  = 0

    InsertTopLap(lapTime)
    SaveDB()

    PlaySound(888)  -- level-up ding
    RefreshUI()
    frame:Show()
end

-------------------------------------------------------------------------------
-- Run control
-------------------------------------------------------------------------------
StartTracking = function()
    if state.running and not state.paused then return end
    if state.paused then
        -- Resume: restore lapStartTime so elapsed looks continuous
        state.lapStartTime = GetTime() - state.pauseOffset
        state.pauseOffset  = 0
        state.paused       = false
    else
        -- Mark as running but waiting — lap timer won't start until
        -- the player physically reaches node 1 (North)
        state.running      = true
        state.paused       = false
        state.node         = 0
        state.direction    = nil
        state.lapStartTime = nil   -- nil = waiting for node 1
        state.pauseOffset  = 0
    end
    RefreshUI()
end

StopTracking = function()
    if not state.running and not state.paused then return end
    state.running      = false
    state.paused       = false
    state.node         = 0
    state.direction    = nil
    state.lapStartTime = nil
    state.pauseOffset  = 0
    SaveDB()
    RefreshUI()
end

PauseTracking = function()
    if not state.running or state.paused then return end
    state.paused      = true
    state.pauseOffset = GetTime() - state.lapStartTime
    RefreshUI()
end

-------------------------------------------------------------------------------
-- Frame / UI
-------------------------------------------------------------------------------
frame = CreateFrame("Frame", "LapsFrame", UIParent, "BackdropTemplate")
frame:SetSize(230, 158)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
frame:SetBackdropColor(0, 0, 0, 0.85)
frame:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
frame:Hide()

-- Title
local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleFS:SetPoint("TOP", frame, "TOP", 0, -10)
titleFS:SetText("|cffFFD700Laps — Silvermoon|r")

-- Stats
local lapText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lapText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -35)

local totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
totalText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -52)

local currentText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
currentText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -69)

local bestText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bestText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -86)

local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -103)

-- Close button
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

-- Start / Pause / Stop buttons
local function MakeButton(parent, label)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(60, 22)
    btn:SetText(label)
    return btn
end

local btnStart = MakeButton(frame, "Start")
local btnPause = MakeButton(frame, "Pause")
local btnStop  = MakeButton(frame, "Stop")

btnStart:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  14, 10)
btnPause:SetPoint("BOTTOM",      frame, "BOTTOM",       0, 10)
btnStop:SetPoint( "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)

btnStart:SetScript("OnClick", function() StartTracking() end)
btnPause:SetScript("OnClick", function() PauseTracking() end)
btnStop:SetScript( "OnClick", function() StopTracking()  end)

-------------------------------------------------------------------------------
-- RefreshUI
-------------------------------------------------------------------------------
RefreshUI = function()
    lapText:SetText(string.format("Laps: |cffFFFFFF%d|r", state.laps))
    totalText:SetText(string.format("Total Time: |cffFFFFFF%s|r", FormatTime(state.totalTime)))

    if state.running and not state.paused and not state.lapStartTime then
        currentText:SetText("Current Lap: |cffAAAAAA(go to any checkpoint)|r")
    elseif state.running and not state.paused and state.lapStartTime then
        local cur = GetTime() - state.lapStartTime
        currentText:SetText(string.format("Current Lap: |cffFFFF00%s|r", FormatTime(cur)))
    elseif state.paused then
        currentText:SetText(string.format("Current Lap: |cffFF8800%s (paused)|r", FormatTime(state.pauseOffset)))
    else
        currentText:SetText("Current Lap: |cffAAAAAA--:--.--|r")
    end

    local best = LapsDB and LapsDB.topLaps and LapsDB.topLaps[1]
    if best and best <= 0 then best = nil end
    bestText:SetText(string.format("Best Lap: |cff00FF00%s|r", FormatTime(best)))

    if state.running and not state.paused and not state.lapStartTime then
        statusText:SetText("|cffFFFF00>> Waiting for checkpoint...|r")
    elseif state.paused then
        statusText:SetText("|cffFF8800>> Paused|r")
    elseif state.running then
        statusText:SetText("|cff00FF00+++ Running|r")
    else
        statusText:SetText("|cffFF0000X Stopped|r")
    end

    btnStart:SetEnabled(not state.running or state.paused)
    btnPause:SetEnabled(state.running and not state.paused)
    btnStop:SetEnabled( state.running or state.paused)
end

-------------------------------------------------------------------------------
-- Core lap tracking
-------------------------------------------------------------------------------
local function UpdateTracking()
    if not state.running or state.paused then return end

    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID ~= SILVERMOON_MAP_ID then return end

    -- Waiting for the player to reach any node before timing begins
    if not state.lapStartTime then
        for i, node in ipairs(NODES) do
            if PlayerNearNode(node) then
                state.node         = i
                state.direction    = nil
                state.lapStartTime = GetTime()
                state.pauseOffset  = 0
                break
            end
        end
        return
    end

    local numNodes = #NODES
    local nextCW   = (state.node % numNodes) + 1
    local nextCCW  = ((state.node - 2 + numNodes) % numNodes) + 1

    if PlayerNearNode(NODES[nextCW]) and (state.direction == nil or state.direction == 1) then
        state.node      = nextCW
        state.direction = 1
        if state.node == 1 then OnLapComplete() end

    elseif PlayerNearNode(NODES[nextCCW]) and (state.direction == nil or state.direction == 2) then
        state.node      = nextCCW
        state.direction = 2
        if state.node == 1 then OnLapComplete() end
    end

    -- Drifted back to start mid-lap: reset direction but keep running
    if state.node ~= 1 and PlayerNearNode(NODES[1]) then
        state.node      = 1
        state.direction = nil
    end
end

-------------------------------------------------------------------------------
-- Auto-start / auto-pause based on player movement, only when frame is visible
-- and the player is near a node checkpoint
-------------------------------------------------------------------------------
local function CheckAutoMovement()
    if not frame:IsShown() then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID ~= SILVERMOON_MAP_ID then return end

    local moving   = IsPlayerMoving()
    local nearNode = PlayerNearAnyNode()

    if moving and not state.wasMoving then
        -- Just started moving near a node → auto-start or resume
        if nearNode and (not state.running or state.paused) then
            StartTracking()
        end
    elseif not moving and state.wasMoving then
        -- Just stopped moving near a node → auto-pause
        if nearNode and state.running and not state.paused then
            PauseTracking()
        end
    end

    state.wasMoving = moving
end

-------------------------------------------------------------------------------
-- Tick frame (~5 times/sec)
-------------------------------------------------------------------------------
local ticker  = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= 0.2 then
        elapsed = 0
        CheckAutoMovement()
        UpdateTracking()
        if frame:IsShown() then
            RefreshUI()
        end
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_LAPS1 = "/laps"
SlashCmdList["LAPS"] = function(msg)
    msg = strtrim(msg:lower())
    if msg == "show" then
        RefreshUI()
        frame:Show()
    elseif msg == "hide" then
        frame:Hide()
    elseif msg == "start" then
        StartTracking()
        frame:Show()
    elseif msg == "pause" then
        PauseTracking()
    elseif msg == "stop" then
        StopTracking()
    elseif msg == "top" then
        PrintTopLaps()
    elseif msg == "reset" then
        StopTracking()
        state.laps      = 0
        state.totalTime = 0
        LapsDB          = { topLaps = {} }
        RefreshUI()
        print("|cffFFD700Laps|r: All stats reset.")
    else
        print("|cffFFD700Laps|r commands:")
        print("  /laps show   — show the tracker window")
        print("  /laps hide   — hide the tracker window")
        print("  /laps start  — start / resume tracking")
        print("  /laps pause  — pause current lap")
        print("  /laps stop   — stop and discard current lap")
        print("  /laps top    — print top 10 best laps to chat")
        print("  /laps reset  — wipe all saved stats")
    end
end

-------------------------------------------------------------------------------
-- Addon loaded — restore saved data
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    LapsDB          = LapsDB or {}
    LapsDB.topLaps  = LapsDB.topLaps or {}
    state.laps      = LapsDB.laps      or 0
    state.totalTime = LapsDB.totalTime or 0
    RefreshUI()
    print("|cffFFD700Laps|r loaded! Type /laps for commands.")
end)
