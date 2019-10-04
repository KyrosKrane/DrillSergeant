-- DrillSergeant.lua
-- Written by KyrosKrane Sylvanblade (kyros@kyros.info)
-- Copyright (c) 2019 KyrosKrane Sylvanblade
-- Licensed under the MIT License, as per the included file.

-- File revision: @file-abbreviated-hash@
-- File last updated: @file-date-iso@


--#########################################
--# Description
--#########################################

-- This add-on reads drill rig announcements in Mechagon and parses them to identify the name of the associated rare, and the drill location.
-- It also adds the name of the rare to the tooltip when mousing over a broken drill rig.


--#########################################
--# Bail out on WoW Classic
--#########################################

-- Mechagon doesn't exist on WoW Classic, so if a user runs this on Classic, just exit at once.
-- for Classic: local IsClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
-- For retail: local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then return end


--#########################################
--# Globals and utilities
--#########################################

-- Grab the WoW-defined addon folder name and storage table for our addon
local addonName, Driller = ...


--#########################################
--# Libraries
--#########################################

local HBD = LibStub("HereBeDragons-2.0")


--#########################################
--# Frame for event handling
--#########################################

-- Create the frame to hold our event catcher, and the list of events.
Driller.Frame, Driller.Events = CreateFrame("Frame"), {}


--#########################################
--# Set up localization
--#########################################

-- Get the localization data for our locale.
local L = LibStub("AceLocale-3.0"):GetLocale(addonName, true)


--#########################################
--# Constants
--#########################################

-- The addon name displayed to the user
Driller.USER_ADDON_NAME = L["Drill Sergeant"]

-- The version of this add-on
Driller.Version = "@project-version@"

-- Map ID for Mechagon, used for ensuring we're in the right zone and for calculating distances on the world map.
local MECHAGON_MAPID = 1462

-- Instance ID for Mechagon, returned by GetPlayerWorldPosition() and used in mob GUIDs.
local MECHAGON_INSTANCEID = 1643

-- This is the longest distance permitted for accurate detection. Shorter than this gets rejected.
local MAX_RANGE_FOR_ID = 50

-- The mobs and locs identified by each drill rig
-- The key must be the drill rig name in English
Driller.Projects = {
	["DR-CC61"] = {Mob = L["Gorged Gear-Cruncher"], DrillMobID = 154695, Loc = {x = 73.0, y = 54.2}},
	["DR-CC73"] = {Mob = L["Caustic Mechaslime"], DrillMobID = 154695, Loc = {x = 66.5, y = 58.8}},
	["DR-CC88"] = {Mob = L["The Kleptoboss"], DrillMobID = 154695, Loc = {x = 68.4, y = 48.1}},

	["DR-JD41"] = {Mob = L["Boilburn"], DrillMobID = 154933, Loc = {x = 51.1, y = 50.3}},
	["DR-JD99"] = {Mob = L["Gemicide"], DrillMobID = 154933, Loc = {x = 59.7, y = 67.2}},

	["DR-TR28"] = {Mob = L["Ol' Big Tusk"], DrillMobID = 150277, Loc = {x = 56.2, y = 36.3}},
	["DR-TR35"] = {Mob = L["Earthbreaker Gulroc"], DrillMobID = 150277, Loc = {x = 63.2, y = 25.4}},
} -- Driller.Projects


--#########################################
--# Get drill rig localized names
--#########################################

-- Now we do something stupid.
-- Localization is usually of the form L["English"] = "OtherLang".
-- This works when you want an output message in the foreign language and you don't know in advance what that language will be.
-- But for the drill rigs, I need to convert from the localized name back to English, so I can access the standardized data.
-- So, I have to invert the localization table to get what I need. Essentially, I need L_inverted["OtherLang"] = "English".
-- The easiest way to get that info is by using the Projects table.
local DrillRigInEnglish = {}

for k, v in pairs(Driller.Projects) do
	DrillRigInEnglish[L[k]] = k
end


--#########################################
--# Tooltip detection and management
--#########################################

-- This function is just a small wrapper that adds a given line of text to the game tooltip, with a prefix of our addon name.
function Driller:AddTooltipLine(line)
	GameTooltip:AddLine(Driller.Utilities:Color(Driller.USER_ADDON_NAME .. ": ", Driller.Utilities.CHAT_BLUE) .. line)
end


-- If the user mouses over a damaged drill rig, put the corresponding rare name in the tooltip.
-- Bonus: also identifies mushrooms that spawn Fungarian Furor
-- Code in this function is partially adapted from idTip (public domain) by silv3rwind on Curse
GameTooltip:HookScript("OnTooltipSetUnit", function(self)
	-- Don't process if we're in a pet battle
	if C_PetBattles.IsInBattle() then return end

	-- Bail out if we're not in Mechagon.
	local Map = C_Map.GetBestMapForUnit("player")
	if not Map or Map ~= MECHAGON_MAPID then return end

	-- Get player coordinates
	local PlayerX, PlayerY, PinstanceID = HBD:GetPlayerWorldPosition()
	-- PinstanceID is not used right now.
	-- if HBD returns invalid X or Y values (usually because the client is too busy), bail out so we don't throw user errors.
	if not PlayerX or not PlayerY then return end

	--Driller.Utilities:DebugPrint("PlayerX is " .. (PlayerX or "nil") .. ", PlayerY is " .. (PlayerY or "nil") .. ", PinstanceID is " .. (PinstanceID or "nil"))

	-- Find out what unit is being moused over
	local unit = select(2, self:GetUnit())
	if not unit then return end

	-- get details on the unit, and make sure it's not a player.
	local guid = UnitGUID(unit) or ""
	--Driller.Utilities:DebugPrint("guid is " .. (guid or "nil"))
	-- GUID format
	-- [Unit type]-0-[server ID]-[instance ID]-[zone UID]-[ID]-[spawn UID]
	-- (Example: "Creature-0-970-0-11-31146-000136DF91")

	local NPCID = tonumber(guid:match("-(%d+)-%x+$"), 10)
	local IsPlayer = guid:match("%a+") == "Player"
	if IsPlayer or not NPCID then return end

	local ProjectID, MobX, MobY  -- used for finding the range
	local InRange = true -- is the mob in ID range?

	if 154695 == NPCID then
		-- could be:
		-- "DR-CC61", -- "Gorged Gear-Cruncher"
		-- "DR-CC73", -- "Caustic Mechaslime"
		-- "DR-CC88", -- "The Kleptoboss"
		Driller.Utilities:DebugPrint("In CC block.")

		-- Find out which mob is closest
		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-CC61"].Loc.x/100, Driller.Projects["DR-CC61"].Loc.y/100, MECHAGON_MAPID)
		local RangeToGearCruncher = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToGearCruncher is " .. MobX .. ", " .. MobY .. ", " .. RangeToGearCruncher)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-CC73"].Loc.x/100, Driller.Projects["DR-CC73"].Loc.y/100, MECHAGON_MAPID)
		local RangeToMechaslime = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToMechaslime is " .. MobX .. ", " .. MobY .. ", " .. RangeToMechaslime)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-CC88"].Loc.x/100, Driller.Projects["DR-CC88"].Loc.y/100, MECHAGON_MAPID)
		local RangeToKleptoboss = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToKleptoboss is " .. MobX .. ", " .. MobY .. ", " .. RangeToKleptoboss)

		if RangeToGearCruncher <= RangeToMechaslime and RangeToGearCruncher <= RangeToKleptoboss then
			Driller.Utilities:DebugPrint("Picking DR-CC61 Gorged Gear-Cruncher")
			ProjectID = "DR-CC61" -- "Gorged Gear-Cruncher"
			if RangeToGearCruncher >= MAX_RANGE_FOR_ID then InRange = false end
		elseif RangeToMechaslime <= RangeToGearCruncher and RangeToMechaslime <= RangeToKleptoboss then
			Driller.Utilities:DebugPrint("Picking DR-CC73 Caustic Mechaslime")
			ProjectID = "DR-CC73" -- "Caustic Mechaslime"
			if RangeToMechaslime >= MAX_RANGE_FOR_ID then InRange = false end
		else
			Driller.Utilities:DebugPrint("Picking DR-CC88 Kleptoboss")
			ProjectID = "DR-CC88" -- "Kleptoboss"
			if RangeToKleptoboss >= MAX_RANGE_FOR_ID then InRange = false end
		end

	elseif 154933 == NPCID then
		-- could be:
		-- "DR-JD41", -- "Boilburn"
		-- "DR-JD99", -- "Gemicide"
		Driller.Utilities:DebugPrint("In JD block.")

		-- Find out which is closer
		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-JD41"].Loc.x/100, Driller.Projects["DR-JD41"].Loc.y/100, MECHAGON_MAPID)
		local RangeToBoilburn = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToBoilburn is " .. MobX .. ", " .. MobY .. ", " .. RangeToBoilburn)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-JD99"].Loc.x/100, Driller.Projects["DR-JD99"].Loc.y/100, MECHAGON_MAPID)
		local RangeToGemicide = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToGemicide is " .. MobX .. ", " .. MobY .. ", " .. RangeToGemicide)

		if RangeToBoilburn < RangeToGemicide then
			Driller.Utilities:DebugPrint("Picking DR-JD41 Boilburn")
			ProjectID = "DR-JD41" -- "Boilburn"
			if RangeToBoilburn >= MAX_RANGE_FOR_ID then InRange = false end
		else
			Driller.Utilities:DebugPrint("Picking DR-JD99 Gemicide")
			ProjectID = "DR-JD99" -- "Gemicide"
			if RangeToGemicide >= MAX_RANGE_FOR_ID then InRange = false end
		end

	elseif 150277 == NPCID then
		-- could be:
		-- "DR-TR28", -- "Ol' Big Tusk"
		-- "DR-TR35", -- "Earthbreaker Gulroc"
		Driller.Utilities:DebugPrint("In TR block.")

		-- Find out which is closer
		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-TR28"].Loc.x/100, Driller.Projects["DR-TR28"].Loc.y/100, MECHAGON_MAPID)
		local RangeToBigTusk = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToBigTusk is " .. MobX .. ", " .. MobY .. ", " .. RangeToBigTusk)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-TR35"].Loc.x/100, Driller.Projects["DR-TR35"].Loc.y/100, MECHAGON_MAPID)
		local RangeToGulroc = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller.Utilities:DebugPrint("MobX, MobY, RangeToGulroc is " .. MobX .. ", " .. MobY .. ", " .. RangeToGulroc)

		if RangeToBigTusk < RangeToGulroc then
			Driller.Utilities:DebugPrint("Picking DR-TR28 Ol' Big Tusk")
			ProjectID = "DR-TR28" -- "Ol' Big Tusk"
			if RangeToBigTusk >= MAX_RANGE_FOR_ID then InRange = false end
		else
			Driller.Utilities:DebugPrint("Picking DR-TR35 Earthbreaker Gulroc")
			ProjectID = "DR-TR35" -- "Earthbreaker Gulroc"
			if RangeToGulroc >= MAX_RANGE_FOR_ID then InRange = false end
		end

	elseif 135497 == NPCID then
		-- real mushroom that spawns Fungarian Furor
		--Driller.Utilities:DebugPrint("Found real mushroom.")
		Driller:AddTooltipLine(L["FUROR"]:format(Driller.Utilities.CHAT_GREEN .. L["Fungarian Furor"] .. FONT_COLOR_CODE_CLOSE))
		return

	elseif 151893 == NPCID then
		-- fake mushroom that spawns random trash
		--Driller.Utilities:DebugPrint("Found fake mushroom.")
		Driller:AddTooltipLine(L["NOT_FUROR"]:format(Driller.Utilities.CHAT_RED .. L["Fungarian Furor"] .. FONT_COLOR_CODE_CLOSE))
		return

	else
		-- not a tracked ID
		--Driller.Utilities:DebugPrint("Not a tracked NPC.")
		return
	end

	-- Make sure we got a valid project. If somehow we didn't, bail out.
	if not ProjectID then return end

	Driller.Utilities:DebugPrint("NPCID is " .. NPCID ..", ProjectID is " .. ProjectID)

	-- Convert to a usable project object to get the mob name.
	local Project = Driller.Projects[ProjectID]
	if not Project then
		Driller.Utilities:ChatPrint(L["PROJECT_ERROR"]:format(NPCID, ProjectID))
		return
	end

	Driller.Utilities:DebugPrint("match found in MobIDs: " .. Project.Mob)
	if InRange then
		Driller:AddTooltipLine(L["OPENS_A_PATH"]:format(ProjectID, Driller.Utilities.CHAT_GREEN .. Project.Mob .. FONT_COLOR_CODE_CLOSE))
	else
		Driller:AddTooltipLine(L["TOO_FAR"])
	end
	GameTooltip:Show()

end) -- HookScript("OnTooltipSetUnit")


--#########################################
--# Events to register and handle
--#########################################

-- This triggers when an NPC gives an emote.
function Driller.Events:CHAT_MSG_MONSTER_EMOTE(...)

	-- Bail out if we're not in Mechagon.
	local Map = C_Map.GetBestMapForUnit("player")
	if not Map or Map ~= MECHAGON_MAPID then return end

	local message, sender = ...
	Driller.Utilities:DebugPrint("Got CHAT_MSG_MONSTER_EMOTE")
	Driller.Utilities:DebugPrint("message is >>" .. message .. "<<")
	Driller.Utilities:DebugPrint("sender is >>" .. sender .. "<<")

	-- Parse the message to see whether it is a drill rig announcement.
	local DrillID = string.match(message, L["DRILL_RIG_MSG_CAPTURE"])

	if DrillID then
		Driller.Utilities:DebugPrint("Identified localized language DrillID " .. DrillID)

		-- Convert the Drill ID from its localized version to English
		DrillID = DrillRigInEnglish[DrillID]
		Driller.Utilities:DebugPrint("Converted DrillID to English: " .. DrillID)

		if Driller.Projects[DrillID] then
			Driller.Utilities:DebugPrint("mob is >>" .. Driller.Projects[DrillID].Mob .. "<<")
			local Loc = Driller.Projects[DrillID].Loc.x .. ", " .. Driller.Projects[DrillID].Loc.y
			Driller.Utilities:DebugPrint("loc is >>" .. Loc .. "<<")

			-- Found a proper drill message. Notify the user.
			Driller.Utilities:ChatPrint(L["ABOUT_TO_SPAWN"]:format(
					Driller.Utilities.CHAT_GREEN .. Driller.Projects[DrillID].Mob .. FONT_COLOR_CODE_CLOSE,
					Loc
			))
		else
			Driller.Utilities:ChatPrint(L["UNKNOWN_DRILL_ID"]:format(DrillID))
		end
	else
		Driller.Utilities:DebugPrint("Not a drill message.")
	end
end -- Driller.Events:CHAT_MSG_MONSTER_EMOTE()


--#########################################
--# Implement the event handlers
--#########################################

-- Create the event handler function.
Driller.Frame:SetScript("OnEvent", function(self, event, ...)
	Driller.Events[event](self, ...) -- call one of the functions above
end)

-- Register all events for which handlers have been defined
for k, v in pairs(Driller.Events) do
	Driller.Utilities:DebugPrint("Registering event " .. k)
	Driller.Frame:RegisterEvent(k)
end


--#########################################
--# Create command line for debug mode toggling
--#########################################

-- Toggle debug mode if asked
function Driller.CommandLine(arg, ...)
	-- Ouptput messages are not localized because end users shouldn't be using this anwyay.
	if "DEBUG" == arg:upper() then
		Driller.DebugMode = not Driller.DebugMode
		if Driller.DebugMode then
			Driller.Utilities:ChatPrint("Debug mode is now " .. Driller.Utilities.CHAT_GREEN .. "on" .. FONT_COLOR_CODE_CLOSE .. ".")
		else
			Driller.Utilities:ChatPrint("Debug mode is now " .. Driller.Utilities.CHAT_RED .. "off" .. FONT_COLOR_CODE_CLOSE .. ".")
		end
	else
		Driller.Utilities:ChatPrint("Unrecognized command: " .. arg)
	end
end -- Driller.CommandLine()


-- Set the default slash command.
SLASH_DRILLER1 = "/driller"
SlashCmdList.DRILLER = function (...) Driller.CommandLine(...) end
