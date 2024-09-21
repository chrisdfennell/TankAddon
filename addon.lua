local title = ...
local version = C_AddOns.GetAddOnMetadata(title, "Version")

-- sbd:set_debug()

-- local debug variable:
local DEBUG = sbd:get_debug()
local debugUnitCount = 10

-- local variables:
local screenWidth, screenHeight
local playerRole
local threatPercentDivisor = 100
local classNameLocalized, class, classIndex
local specIndex, spec
local tauntSpellId, tauntSpellName
local inParty, inRaid
local maxUnitFrames = 40
local groupGuidList = {}
local lastAggroMessages = {}


-- addon:
local addon = CreateFrame("Frame", title, UIParent) -- instead of UIParent, try using the health bar under character
addon.version = version

-- slash commands:
SLASH_TANKADDON1, SLASH_TANKADDON2 = "/tankaddon", "/ta"

function addon:HandleSlashCommand(msg)
    local _, _, cmd, argsString = string.find(msg, "%s?(%w+)%s?(.*)")
    
    cmd = cmd or "help"
    argsString = argsString or ""

    local slashCmd = "HandleSlashCommand_" .. cmd
    local args = {strsplit(" ", argsString)}

    sbd:log_debug("HandleSlashCommand: ", cmd, argsString)

    if cmd == "help" then
        sbd:log_info("TankAddon v" .. version .. " slash command help")
        sbd:log_info("syntax: /tankaddon (or /ta) command arg1 arg2")
        sbd:log_info("command: 'help': this message")
        sbd:log_info(
            "command: 'get', arg1: OPTION_NAME or 'all': show the value of the OPTION_NAME or values of all options")
        sbd:log_info("command: 'set', arg1: OPTION_NAME, arg2: VALUE: set the OPTION_NAME to the VALUE")
        sbd:log_info("command: 'reset': sets all options to the default values")
    elseif cmd == "get" then
        if sbd:contains(db, args[1]) then
            sbd:log_info(args[1] .. " = ", db[args[1]])
        elseif args[1] == "all" then
            table.foreach(db, function(k, v)
                sbd:log_info(k .. " = ", v)
            end)
        else
            sbd:log_error("unknown property: ", args[1])
        end
    elseif cmd == "set" then
        if sbd:contains(data.Options, args[1]) then
            local val

            if data.Options[args[1]].type == "boolean" then
                val = args[2] == "true" or false
            elseif data.Options[args[1]].type == "number" then
                val = tonumber(args[2])

                if sbd:contains(data.Options[args[1]], "step") then
                    val = val - (val % data.Options[args[1]].step)
                end

                if sbd:contains(data.Options[args[1]], "min") then
                    if val < data.Options[args[1]].min then
                        val = data.Options[args[1]].min
                    end
                end

                if sbd:contains(data.Options[args[1]], "max") then
                    if val > data.Options[args[1]].max then
                        val = data.Options[args[1]].max
                    end
                end
            else
                val = args[2]
            end

            db[args[1]] = val

            sbd:log_info(args[1] .. " = ", db[args[1]])

            self:OnOptionsUpdated()
        else
            sbd:log_error("unknown setting: " .. args[1])
        end
    elseif cmd == "reset" then
        self:ResetToDefaults()

        table.foreach(db, function(k, v)
            sbd:log_info(k .. " = ", v)
        end)

        self:OnOptionsUpdated()
    elseif cmd == "locals" then
        sbd:log_debug("class = ", class)
        sbd:log_debug("classIndex = ", classIndex)
        sbd:log_debug("classNameLocalized = ", classNameLocalized)
        sbd:log_debug("inParty = ", inParty)
        sbd:log_debug("inRaid = ", inRaid)
        sbd:log_debug("maxUnitFrames = ", maxUnitFrames)
        sbd:log_debug("playerRole = ", playerRole)
        sbd:log_debug("spec = ", spec)
        sbd:log_debug("specIndex = ", specIndex)
        sbd:log_debug("tauntSpellId = ", tauntSpellId)
        sbd:log_debug("tauntSpellName = ", tauntSpellName)
        sbd:log_debug("threatPercentDivisor = ", threatPercentDivisor)

        sbd:log_debug("groupGuidList:")
        sbd:log_debug_table(groupGuidList)

        sbd:log_debug("db:")
        sbd:log_debug_table(db)
    else
        sbd:log_error("command does not exist:", cmd)
        sbd:log_info("try '/tankaddon help' for help with slash commands")
    end
end

function addon:ResetToDefaults()
    for k, v in pairs(sbd:GetOptionDefaults(data.Options)) do
        db[k] = v
    end
end

SlashCmdList["TANKADDON"] = function(msg)
    addon:HandleSlashCommand(msg)
end

-- registered events:
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGOUT")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
addon:RegisterEvent("GROUP_ROSTER_UPDATE")
addon:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
addon:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
addon:RegisterEvent("PLAYER_LEAVE_COMBAT")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("PLAYER_REGEN_DISABLED")

addon:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

-- addon functions:
function addon:CreateFrames()
    sbd:log_debug("CreateFrames")
    
    screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale()
    screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale()
    
    local maxWidth = (db.unit_width * db.unit_columns) + (db.unit_padding * (db.unit_columns - 1))
    
    if self.GroupFrame then
        self.GroupFrame:Hide() -- Better to hide than destroy
        self.GroupFrame = nil
    end

    self.GroupFrame = CreateFrame("Frame", "TankAddonGroupFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    self.GroupFrame:SetFrameStrata("MEDIUM")
    self.GroupFrame:SetMovable(true)
    self.GroupFrame:EnableMouse(true)
    self.GroupFrame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    self.GroupFrame:SetBackdropColor(0, 0, 0, 0.8)
    self.GroupFrame:ClearAllPoints()
    self.GroupFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", screenWidth / 2, screenHeight / 2)

    if not db.always_show then
        self.GroupFrame:Hide()
    end

    self.GroupFrame:RegisterForDrag("LeftButton")

    self.GroupFrame:SetScript("OnDragStart", function(self)
        if not db.locked then
            self:StartMoving()
        end
    end)

    self.GroupFrame:SetScript("OnDragStop", function(self)
        if not db.locked then
            self:StopMovingOrSizing()
        end
    end)

    -- Define GetUnitFrame method for GroupFrame here
    function self.GroupFrame:GetUnitFrame(name)
        for _, child in ipairs({self:GetChildren()}) do
            if child:GetName() == name then
                return child
            end
        end
        return nil
    end

    -- Define ResetUnitFrames inside CreateFrames and attach it to GroupFrame
    function self.GroupFrame:ResetUnitFrames()
        for _, child in ipairs({self:GetChildren()}) do
            child.unit = nil
            child.text:SetText(nil)
            child.texture:SetColorTexture(0, 0, 0, 1) -- Reset background color
            child:Hide()
        end
    end

    -- Define ResetUnitFramesThreat inside CreateFrames and attach it to GroupFrame
    function self.GroupFrame:ResetUnitFramesThreat()
        for _, child in ipairs({self:GetChildren()}) do
            if child.texture then
                child.texture:SetColorTexture(0, 0, 0, 1)  -- Reset to black (no aggro)
            end
        end
    end

    local currentUnitOffsetX = db.frame_padding
    local currentUnitOffsetY = db.frame_padding

    for i = 1, maxUnitFrames do
        local button = CreateFrame("Button", format("UnitFrame%d", i), self.GroupFrame, BackdropTemplateMixin and "BackdropTemplate, SecureActionButtonTemplate")

        button:SetWidth(db.unit_width)
        button:SetHeight(db.unit_height)
        button:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
        button:SetPoint("BOTTOMLEFT", self.GroupFrame, currentUnitOffsetX, currentUnitOffsetY)

        button.unit = nil

        -- Using solid color texture
        button.texture = button:CreateTexture(nil, "ARTWORK")
        button.texture:SetColorTexture(1, 0, 0, 1)  -- Solid red (default for aggro)
        button.texture:SetAllPoints(button)

        button.text = button:CreateFontString(nil, "ARTWORK")
        button.text:SetFont(data.Font, db.font_size)
        button.text:SetPoint("CENTER", button, "CENTER")

        if DEBUG then
            button.text:SetText(tostring(i))
        end

        button.badge = button:CreateTexture(nil, "ARTWORK")
        button.badge:SetSize(20, 20)
        button.badge:SetTexture(2202478)
        button.badge:SetPoint("TOPLEFT", -5, 5)

        button:Hide()

        function button:SetThreatPercent(alpha)
            -- Ensure alpha is between 0.0 and 1.0
            alpha = math.min(1, math.max(0, alpha))
            button.texture:SetAlpha(alpha)
        end

        function button:SetRole(role)
            if role == "TANK" then
                button.badge:SetTexCoord(.523, .757, 0, 1)
            elseif role == "HEALER" then
                button.badge:SetTexCoord(.265, .492, 0, 1)
            elseif role == "DAMAGER" then
                button.badge:SetTexCoord(.007, .242, 0, 1)
            else
                button.badge:SetTexCoord(.76, 1, 0, 1)
            end
        end

        currentUnitOffsetX = currentUnitOffsetX + (db.unit_width + db.unit_padding)
        
        if currentUnitOffsetX > maxWidth then
            currentUnitOffsetX = db.frame_padding
            currentUnitOffsetY = currentUnitOffsetY + (db.unit_height + db.unit_padding)
        end
    end

    self:OnOptionsUpdated()
end

function addon:OnOptionsUpdated()
    sbd:log_debug("OnOptionsUpdated")
    
    local maxWidth = (db.unit_width * db.unit_columns) + (db.unit_padding * (db.unit_columns - 1))
    
    local unitCount = sbd:count_table_pairs(groupGuidList)
    local columns = unitCount <= db.unit_columns and unitCount or db.unit_columns
    local rows = columns <= db.unit_columns and 1 or math.ceil(unitCount / db.unit_columns)
    local groupFrameWidth = (db.unit_width * columns) + (db.unit_padding * (columns - 1))
    local groupFrameHeight = (db.unit_height * rows) + (db.unit_padding * (rows - 1))

    groupFrameWidth = groupFrameWidth + (db.frame_padding * 2)
    groupFrameHeight = groupFrameHeight + (db.frame_padding * 2)

    self.GroupFrame:SetWidth(groupFrameWidth)
    self.GroupFrame:SetHeight(groupFrameHeight)

    if not db.always_show or not db.enabled then
        self.GroupFrame:Hide()
    elseif db.always_show and db.enabled then
        self.GroupFrame:Show()
    end

    local offsetX = db.frame_padding
    local offsetY = db.frame_padding

    for _, child in ipairs({self.GroupFrame:GetChildren()}) do
        child:SetWidth(db.unit_width)
        child:SetHeight(db.unit_height)
        child.text:SetFont(data.Font, db.font_size)

        local unitName = child:GetName()

        child.text:SetFont(data.Font, db.font_size)
        child:SetPoint("BOTTOMLEFT", self.GroupFrame, offsetX, offsetY)

        offsetX = offsetX + (db.unit_width + db.unit_padding)

        if offsetX > maxWidth then
            offsetX = db.frame_padding
            offsetY = offsetY + (db.unit_height + db.unit_padding)
        end
    end

    self:UpdateGroupFrameUnits()
end

function addon:UpdatePlayerSpec()
    sbd:log_debug("UpdatePlayerSpec")

    specIndex = GetSpecialization()
    spec = specIndex and select(2, GetSpecializationInfo(specIndex)) or "None"

    if data.ClassData[class] and data.ClassData[class]["spec"] == spec then
        tauntSpellId, tauntSpellName = data.ClassData[class]["tauntSpellId"], data.ClassData[class]["tauntSpellName"]
    end
end

function addon:UpdatePlayerGroupState()
    sbd:log_debug("UpdatePlayerGroupState")

    inParty = IsInGroup()
    inRaid = IsInRaid()
    playerRole = UnitGroupRolesAssigned("player")
end

function addon:UpdateGroupGuidList()
    sbd:log_debug("UpdateGroupGuidList")

    -- Clear the current group list
    wipe(groupGuidList)

    -- Check if the player is in a raid
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) then
                groupGuidList[unit] = { name = UnitName(unit), target = unit .. "target" }
            end
        end
    -- Check if the player is in a party
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then
                groupGuidList[unit] = { name = UnitName(unit), target = unit .. "target" }
            end
        end
    end

    -- Always add the player to the group list
    groupGuidList["player"] = { name = UnitName("player"), target = "target" }
end

-- Utility function to truncate the name
local function TruncateName(name, maxLength)
    if string.len(name) > maxLength then
        return string.sub(name, 1, maxLength) .. "..."
    else
        return name
    end
end


function addon:UpdateGroupFrameUnits()
    sbd:log_debug("UpdateGroupFrameUnits")

    if groupGuidList then
        local unitCount = sbd:count_table_pairs(groupGuidList)
        local columns = unitCount <= db.unit_columns and unitCount or db.unit_columns
        local rows = math.ceil(unitCount / db.unit_columns)
        local groupFrameWidth = (db.unit_width * columns) + (db.unit_padding * (columns - 1))
        local groupFrameHeight = (db.unit_height * rows) + (db.unit_padding * (rows - 1))

        groupFrameWidth = groupFrameWidth + (db.frame_padding * 2)
        groupFrameHeight = groupFrameHeight + (db.frame_padding * 2)

        self.GroupFrame:SetWidth(groupFrameWidth)
        self.GroupFrame:SetHeight(groupFrameHeight)
        self.GroupFrame:ResetUnitFrames()

        -- Set local player to first unit frame
        local unitFrame = self.GroupFrame:GetUnitFrame("UnitFrame1")
        unitFrame:SetBackdropColor(0, 0, 0, 1)
        unitFrame.unit = "player"
        unitFrame:SetRole(UnitGroupRolesAssigned("player"))
        
        -- Truncate the player's name
        unitFrame.text:SetText(TruncateName(UnitName("player"), 8))  -- Truncate to 8 characters, for example
        unitFrame:Show()

        local unitFrameIndex = 2 -- starting with 2 since local player takes 1

        -- Loop through group members and assign actions based on role
        for unit, data in pairs(groupGuidList) do
            if unit ~= "player" then
                local unitName = data["name"]
                unitFrame = self.GroupFrame:GetUnitFrame(format("UnitFrame%d", unitFrameIndex))

                if unitFrame then
                    unitFrame:SetBackdropColor(0, 0, 0, 1)
                    if unitName ~= UnitName("player") then
                        -- Determine action based on player role
                        if playerRole == "TANK" and tauntSpellName then
                            -- Tank: Cast taunt on the unit's target
                            unitFrame:SetAttribute("type", "spell")
                            unitFrame:SetAttribute("spell", tauntSpellName)
                            unitFrame:SetAttribute("unit", data["target"])
                        else
                            -- Healer/DPS: Assist (target the target)
                            unitFrame:SetAttribute("type", "assist")
                            unitFrame:SetAttribute("unit", data["target"])
                        end
                    end

                    unitFrame.unit = unit
                    unitFrame:SetRole(UnitGroupRolesAssigned(unit))

                    -- Truncate unit name
                    unitFrame.text:SetText(TruncateName(unitName, 8))  -- Truncate to 8 characters, for example

                    unitFrame:Show()
                else
                    sbd:log_debug("UpdateGroupFrameUnits nil unitFrame for unit:", unit)
                end

                unitFrameIndex = unitFrameIndex + 1
            end
        end
    end
end


function addon:GetGroupUnit(unit)
sbd:log_debug("GetGroupUnit: ", unit)

if groupGuidList then
    if groupGuidList[unit] or groupGuidList[UnitGUID(unit)] then
        return unit
    else
        for u, d in pairs(groupGuidList) do
            if d["name"] == unit or d["name"] == UnitName(unit) then
                return u
            end
        end
    end
end

return nil
end

function addon:InGroup(unit)
    sbd:log_debug("InGroup: ", unit)

    if self:GetGroupUnit(unit) then
        return true
    else
        return false
    end
end

local lastAggroMessages = {}

function addon:UpdateUnitFramesThreat()
    -- Ensure GroupFrame exists
    if not self.GroupFrame then
        if sbd:get_debug() then sbd:log_debug("GroupFrame is nil, cannot update threat.") end
        return
    end

    -- Update threat for the player
    if UnitExists("target") then
        local playerIsTanking, playerThreatStatus, playerThreatPct = UnitDetailedThreatSituation("player", "target")
        local playerFrame = self.GroupFrame:GetUnitFrame("UnitFrame1")
        
        if playerFrame and playerThreatPct then
            playerFrame:SetThreatPercent(playerThreatPct / 100)

            if playerIsTanking then
                playerFrame.texture:SetColorTexture(1, 0, 0, 1) -- Red for aggro
                if sbd:get_debug() then sbd:log_debug("Player has aggro.") end
            else
                playerFrame.texture:SetColorTexture(0, 0, 0, 1) -- Black for no aggro
                if sbd:get_debug() then sbd:log_debug("Player does NOT have aggro.") end
            end
        end
    end

    -- Update threat for other group members
    if groupGuidList then
        local unitIndex = 2
        for unit, data in pairs(groupGuidList) do
            if unit ~= "player" and UnitExists(unit) then
                local unitTarget = data["target"]
                local isTanking, threatStatus, threatPct = UnitDetailedThreatSituation(unit, unitTarget)
                local unitFrame = self.GroupFrame:GetUnitFrame(format("UnitFrame%d", unitIndex))

                if unitFrame and threatPct then
                    unitFrame:SetThreatPercent(threatPct / 100)

                    if isTanking then
                        unitFrame.texture:SetColorTexture(1, 0, 0, 1) -- Red for aggro
                        if sbd:get_debug() then sbd:log_debug(UnitName(unit) .. " has aggro.") end
                    elseif threatStatus and threatStatus >= 1 then
                        unitFrame.texture:SetColorTexture(1, 1, 0, 1) -- Yellow for high threat
                        if sbd:get_debug() then sbd:log_debug(UnitName(unit) .. " has high threat.") end
                    else
                        unitFrame.texture:SetColorTexture(0, 0, 0, 1) -- Black for no threat
                        if sbd:get_debug() then sbd:log_debug(UnitName(unit) .. " does NOT have aggro.") end
                    end
                end
                unitIndex = unitIndex + 1
            end
        end
    end
end

-- event functions:
function addon:ADDON_LOADED(addOnName)
    if addOnName == title then
        sbd:log_debug("ADDON_LOADED")
        sbd:log_info(title .. " v" .. version .. " loaded.")

        db = sbd:GetOptionDefaults(data.Options)

        if TankAddonVars then
            for k, v in pairs(TankAddonVars) do
                db[k] = v
            end
        end

        self:CreateFrames()  -- Ensure GroupFrame is created early here

        screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale()
        sbd:log_debug("screenWidth: ", screenWidth)

        screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale()
        sbd:log_debug("screenHeight: ", screenHeight)

        sbd:GenerateOptionsInterface(self, data.Options, db, function()
            self:OnOptionsUpdated()
        end)
    end
end


function addon:PLAYER_LOGOUT()
    TankAddonVars = db
end

function addon:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    sbd:log_debug("PLAYER_ENTERING_WORLD")

    classNameLocalized, class, classIndex = UnitClass("player")

    self:UpdatePlayerSpec()
    self:UpdatePlayerGroupState()
    self:UpdateGroupGuidList()
    self:UpdateGroupFrameUnits()

    -- self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function addon:ACTIVE_TALENT_GROUP_CHANGED()
    sbd:log_debug("ACTIVE_TALENT_GROUP_CHANGED")
    self:UpdatePlayerSpec()
end

function addon:GROUP_ROSTER_UPDATE()
    sbd:log_debug("GROUP_ROSTER_UPDATE")
    self:UpdatePlayerSpec()
    self:UpdatePlayerGroupState()
    self:UpdateGroupGuidList()
    self:UpdateGroupFrameUnits()
end

function addon:UNIT_THREAT_LIST_UPDATE(_, target)
    sbd:log_debug("UNIT_THREAT_LIST_UPDATE")
    self:UpdateUnitFramesThreat()
end

function addon:UNIT_THREAT_SITUATION_UPDATE(_, target)
    sbd:log_debug("UNIT_THREAT_SITUATION_UPDATE")
    self:UpdateUnitFramesThreat()
end

function addon:PLAYER_LEAVE_COMBAT()
    sbd:log_debug("PLAYER_LEAVE_COMBAT")
    self.GroupFrame:ResetUnitFramesThreat()
end

function addon:PLAYER_REGEN_ENABLED()
    sbd:log_debug("PLAYER_REGEN_ENABLED")
    self.GroupFrame:ResetUnitFramesThreat()

    if not db.always_show or not db.enabled then
        self.GroupFrame:Hide()
    end
end

function addon:PLAYER_REGEN_DISABLED()
    sbd:log_debug("PLAYER_REGEN_DISABLED")
    self.GroupFrame:ResetUnitFramesThreat()

    if db.enabled and not self.GroupFrame:IsVisible() then
        self.GroupFrame:Show()
    end
end