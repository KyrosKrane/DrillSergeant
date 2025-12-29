-- DrillSergeant.lua
-- Written by KyrosKrane Sylvanblade (kyros@kyros.info)
-- Copyright (c) 2019-2024 KyrosKrane Sylvanblade
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
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end


--#########################################
--# Globals and utilities
--#########################################

-- Grab the WoW-defined addon folder name and storage table for our addon
local addonName, Driller = ...

--@alpha@
Driller.DebugMode = true
--@end-alpha@
local DebugPrint = Driller.Utilities.DebugPrint


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
Driller.USER_ADDON_SHORT_NAME = L["Drill Sergeant"]

-- The version of this add-on
Driller.Version = "@project-version@"

-- Map ID for Mechagon, used for ensuring we're in the right zone and for calculating distances on the world map.
local MECHAGON_MAPID = 1462

-- Mechagon sub-zone maps, used for figuring out if we're in a place where we should respond to emotes
local MECHAGON_SUB_MAP_IDS = {
	[1462] = "Mechagon Island",
	[1522] = "Crumbling Cavern",
}

-- Instance ID for Kul Tiras, returned by GetPlayerWorldPosition() and used in mob GUIDs.
-- local KUL_TIRAS_INSTANCEID = 1643

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

-- Pre-calculate the world X and Y coordinates for each mob
for k, v in pairs(Driller.Projects) do
	local x, y = HBD:GetWorldCoordinatesFromZone(v.Loc.x/100, v.Loc.y/100, MECHAGON_MAPID)
	v.WorldLoc = { x=x, y=y }
end


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
--# Waypoint link creation and click handling
--#########################################

-- Creates a clickable chat link based on the selected game mode.
-- map is the MapID
-- X and Y should be 0.00-100.00
-- Name is the name of the thing the waypoint is pointing to (only relevant for TomTom)
local function CreateWaypointLink(map, x, y, name)
	DebugPrint("In CreateWaypointLink")

	local DisplayLoc = x .. ", " .. y
	DebugPrint("DisplayLoc is >>" .. DisplayLoc .. "<<")
	local LocWithLink

	if "TomTom" == Driller.mode then
		DebugPrint("TomTom mode detected")

		LocWithLink = string.format("|cffffff00|Haddon:" .. addonName .. ":%s:%s:%s:%s|h[|A:bags-greenarrow:22:22|a%s]|h|r", map, x, y, name, DisplayLoc)
		DebugPrint("LocWithLink is >>" .. LocWithLink .. "<<")

	else
		DebugPrint("WoW mode detected")

		-- WoW links expect x and y to be 0-10000.
		LocWithLink = string.format("|cffffff00|Hworldmap:%s:%s:%s|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a %s]|h|r", map, x * 100, y * 100, DisplayLoc)
		DebugPrint("LocWithLink is >>" .. LocWithLink .. "<<")
	end

	return LocWithLink
end -- CreateWaypointLink()


-- Chat link click handling - only required for TomTom
local function HandleClickCallback(event, link, text, button, chatFrame)
	local linkType, linkAddonName, mapID, x, y, name = strsplit(":", link)
	--DebugPrint("Received callback for SetItemRef, linktype is ", linkType, ", linkAddonName is ", linkAddonName)

	-- Make sure it's our link, otherwise bail
	if linkType ~= "addon" or linkAddonName ~= addonName then return end

	-- HereBeDragons type-checks its parameters to be numbers, so coerce them to the right type.
	-- Both TomTom and WoW expect x and y to be 0-1, not 0-100
	mapID = 0 + mapID
	x = x / 100
	y = y / 100

	DebugPrint(format("DS link detected. mapID = %s, x = %s, y = %s, name = %s", mapID, x, y, name))

	if Driller.mode == "TomTom" then
		DebugPrint("Dispatching TomTom")
		TomTom:SetCustomWaypoint(mapID, x, y, { title = name, from = Driller.USER_ADDON_NAME })
	else
		-- This is an odd situation. The user has TomTom loaded and configued in DS, and a mob spawned, causing a link to be displayed. The user then swapped their config to WoW waypoints and clicked the link.
		-- So, we manually show the WoW link.
		DebugPrint("Dispatching WoW")
		local mappoint = UiMapPoint.CreateFromCoordinates(mapID, x, y)
		C_Map.SetUserWaypoint(mappoint)
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end

end -- HandleClickCallback()

EventRegistry:RegisterCallback("SetItemRef", HandleClickCallback)



--#########################################
--# Tooltip detection and management
--#########################################

-- This function is just a small wrapper that adds a given line of text to the game tooltip, with a prefix of our addon name.
function Driller:AddTooltipLine(line)
	GameTooltip:AddLine(Driller.Utilities.Color(Driller.USER_ADDON_NAME .. ": ", Driller.Utilities.CHAT_BLUE) .. line)
end


-- If the user mouses over a damaged drill rig, put the corresponding rare name in the tooltip.
-- Bonus: also identifies mushrooms that spawn Fungarian Furor
-- Code in this function is partially adapted from idTip (public domain) by silv3rwind on Curse
-- Dragonflight update: OnTooltipSetUnit is removed from the GameTooltip, and instead has to be written locally then linked.
-- Self in the parameter list corresponds to the tooltip (so the proper parameters would be (tooltip, data) ).
local function OnTooltipSetUnit(self, data)
	-- Only process GameTooltip
	if not self == GameTooltip then return end

	-- Don't process if we're in a pet battle
	if C_PetBattles.IsInBattle() then return end

	-- Bail out if we're not in Mechagon.
	local Map = C_Map.GetBestMapForUnit("player")
	if not Map or not MECHAGON_SUB_MAP_IDS[Map] then return end

	-- Get player world coordinates
	local PlayerX, PlayerY, PinstanceID = HBD:GetPlayerWorldPosition()
	-- if HBD returns invalid X or Y values (usually because the client is too busy), bail out so we don't throw user errors.
	if not PlayerX or not PlayerY then return end

	--DebugPrint("PlayerX is " .. (PlayerX or "nil") .. ", PlayerY is " .. (PlayerY or "nil") .. ", PinstanceID is " .. (PinstanceID or "nil"))

	-- Find out what unit is being moused over
	local unit = select(2, self:GetUnit())
	if not unit then return end

	-- get details on the unit, and make sure it's not a player.
	local guid = UnitGUID(unit) or ""
	--DebugPrint("guid is " .. (guid or "nil"))
	-- GUID format
	-- [Unit type]-0-[server ID]-[instance ID]-[zone UID]-[ID]-[spawn UID]
	-- (Example: "Creature-0-970-0-11-31146-000136DF91")

	local NPCID = tonumber(guid:match("-(%d+)-%x+$"), 10)
	local IsPlayer = guid:match("%a+") == "Player"
	if IsPlayer or not NPCID then return end

	local ProjectID -- used to identify the right project
	local InRange = true -- is the mob in ID range?

	if 154695 == NPCID then
		-- could be:
		-- "DR-CC61", -- "Gorged Gear-Cruncher"
		-- "DR-CC73", -- "Caustic Mechaslime"
		-- "DR-CC88", -- "The Kleptoboss"
		DebugPrint("In CC block.")

		-- Find out which mob is closest
		local RangeToGearCruncher = HBD:GetWorldDistance(PinstanceID, PlayerX, PlayerY, Driller.Projects["DR-CC61"].WorldLoc.x, Driller.Projects["DR-CC61"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToGearCruncher is " .. Driller.Projects["DR-CC61"].WorldLoc.x .. ", " .. Driller.Projects["DR-CC61"].WorldLoc.y .. ", " .. RangeToGearCruncher)

		local RangeToMechaslime = HBD:GetWorldDistance(PinstanceID, PlayerX, PlayerY, Driller.Projects["DR-CC73"].WorldLoc.x, Driller.Projects["DR-CC73"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToMechaslime is " .. Driller.Projects["DR-CC73"].WorldLoc.x .. ", " .. Driller.Projects["DR-CC73"].WorldLoc.y .. ", " .. RangeToMechaslime)

		local RangeToKleptoboss = HBD:GetWorldDistance(PinstanceID, PlayerX, PlayerY, Driller.Projects["DR-CC88"].WorldLoc.x, Driller.Projects["DR-CC88"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToKleptoboss is " .. Driller.Projects["DR-CC88"].WorldLoc.x .. ", " .. Driller.Projects["DR-CC88"].WorldLoc.y .. ", " .. RangeToKleptoboss)

		if RangeToGearCruncher <= RangeToMechaslime and RangeToGearCruncher <= RangeToKleptoboss then
			DebugPrint("Picking DR-CC61 Gorged Gear-Cruncher")
			ProjectID = "DR-CC61" -- "Gorged Gear-Cruncher"
			if RangeToGearCruncher >= MAX_RANGE_FOR_ID then InRange = false end
		elseif RangeToMechaslime <= RangeToGearCruncher and RangeToMechaslime <= RangeToKleptoboss then
			DebugPrint("Picking DR-CC73 Caustic Mechaslime")
			ProjectID = "DR-CC73" -- "Caustic Mechaslime"
			if RangeToMechaslime >= MAX_RANGE_FOR_ID then InRange = false end
		else
			DebugPrint("Picking DR-CC88 Kleptoboss")
			ProjectID = "DR-CC88" -- "Kleptoboss"
			if RangeToKleptoboss >= MAX_RANGE_FOR_ID then InRange = false end
		end

	elseif 154933 == NPCID then
		-- could be:
		-- "DR-JD41", -- "Boilburn"
		-- "DR-JD99", -- "Gemicide"
		DebugPrint("In JD block.")

		-- Find out which is closer
		local RangeToBoilburn = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, Driller.Projects["DR-JD41"].WorldLoc.x, Driller.Projects["DR-JD41"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToBoilburn is " .. Driller.Projects["DR-JD41"].WorldLoc.x .. ", " .. Driller.Projects["DR-JD41"].WorldLoc.y .. ", " .. RangeToBoilburn)

		local RangeToGemicide = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, Driller.Projects["DR-JD99"].WorldLoc.x, Driller.Projects["DR-JD99"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToGemicide is " .. Driller.Projects["DR-JD99"].WorldLoc.x .. ", " .. Driller.Projects["DR-JD99"].WorldLoc.y .. ", " .. RangeToGemicide)

		if RangeToBoilburn < RangeToGemicide then
			DebugPrint("Picking DR-JD41 Boilburn")
			ProjectID = "DR-JD41" -- "Boilburn"
			if RangeToBoilburn >= MAX_RANGE_FOR_ID then InRange = false end
		else
			DebugPrint("Picking DR-JD99 Gemicide")
			ProjectID = "DR-JD99" -- "Gemicide"
			if RangeToGemicide >= MAX_RANGE_FOR_ID then InRange = false end
		end

	elseif 150277 == NPCID then
		-- could be:
		-- "DR-TR28", -- "Ol' Big Tusk"
		-- "DR-TR35", -- "Earthbreaker Gulroc"
		DebugPrint("In TR block.")

		-- Find out which is closer
		local RangeToBigTusk = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, Driller.Projects["DR-TR28"].WorldLoc.x, Driller.Projects["DR-TR28"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToBigTusk is " .. Driller.Projects["DR-TR28"].WorldLoc.x .. ", " .. Driller.Projects["DR-TR28"].WorldLoc.y .. ", " .. RangeToBigTusk)

		local RangeToGulroc = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, Driller.Projects["DR-TR35"].WorldLoc.x, Driller.Projects["DR-TR35"].WorldLoc.y)
		DebugPrint("MobX, MobY, RangeToGulroc is " .. Driller.Projects["DR-TR35"].WorldLoc.x .. ", " .. Driller.Projects["DR-TR35"].WorldLoc.y .. ", " .. RangeToGulroc)

		if RangeToBigTusk < RangeToGulroc then
			DebugPrint("Picking DR-TR28 Ol' Big Tusk")
			ProjectID = "DR-TR28" -- "Ol' Big Tusk"
			if RangeToBigTusk >= MAX_RANGE_FOR_ID then InRange = false end
		else
			DebugPrint("Picking DR-TR35 Earthbreaker Gulroc")
			ProjectID = "DR-TR35" -- "Earthbreaker Gulroc"
			if RangeToGulroc >= MAX_RANGE_FOR_ID then InRange = false end
		end

	elseif 135497 == NPCID then
		-- real mushroom that spawns Fungarian Furor
		--DebugPrint("Found real mushroom.")
		Driller:AddTooltipLine(L["FUROR"]:format(Driller.Utilities.CHAT_GREEN .. L["Fungarian Furor"] .. FONT_COLOR_CODE_CLOSE))
		return

	elseif 151893 == NPCID then
		-- fake mushroom that spawns random trash
		--DebugPrint("Found fake mushroom.")
		Driller:AddTooltipLine(L["NOT_FUROR"]:format(Driller.Utilities.CHAT_RED .. L["Fungarian Furor"] .. FONT_COLOR_CODE_CLOSE))
		return

	else
		-- not a tracked ID
		--DebugPrint("Not a tracked NPC.")
		return
	end

	-- Make sure we got a valid project. If somehow we didn't, bail out.
	if not ProjectID then return end

	DebugPrint("NPCID is " .. NPCID ..", ProjectID is " .. ProjectID)

	-- Convert to a usable project object to get the mob name.
	local Project = Driller.Projects[ProjectID]
	if not Project then
		Driller.Utilities.ChatPrint(L["PROJECT_ERROR"]:format(NPCID, ProjectID))
		return
	end

	DebugPrint("match found in MobIDs: " .. Project.Mob)
	if InRange then
		Driller:AddTooltipLine(L["OPENS_A_PATH"]:format(ProjectID, Driller.Utilities.CHAT_GREEN .. Project.Mob .. FONT_COLOR_CODE_CLOSE))
	else
		Driller:AddTooltipLine(L["TOO_FAR"])
	end
	GameTooltip:Show()

end -- function OnTooltipSetUnit()

-- Hook into the tooltip itself
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)




--#########################################
--# Events to register and handle
--#########################################

-- Handle login and initialization stuff.
function Driller.Events:PLAYER_LOGIN(...)

	-- Initialize saved variables
	if not DrillSergeant_DB then DrillSergeant_DB = {} end
	if not DrillSergeant_DB.user_set then
		if TomTom then
			DrillSergeant_DB.mode = "TomTom"
		else
			DrillSergeant_DB.mode = "WoW"
		end
	end

	-- Determine waypoint mode
	if "TomTom" == DrillSergeant_DB.mode and TomTom then
		Driller.mode = "TomTom"
	else
		Driller.mode = "WoW"
	end
end -- Driller.Events:PLAYER_LOGIN()


-- This triggers when an NPC gives an emote.
function Driller.Events:CHAT_MSG_MONSTER_EMOTE(...)

	-- Bail out if we're not in Mechagon.
	local Map = C_Map.GetBestMapForUnit("player")
	if not Map or not MECHAGON_SUB_MAP_IDS[Map] then return end

	local message, sender = ...
	DebugPrint("Got CHAT_MSG_MONSTER_EMOTE")
	DebugPrint("message is >>" .. message .. "<<")
	DebugPrint("sender is >>" .. sender .. "<<")

	-- Parse the message to see whether it is a drill rig announcement.
	local LocalizedDrillID = string.match(message, L["DRILL_RIG_MSG_CAPTURE"])

	if LocalizedDrillID then
		DebugPrint("Identified localized language DrillID " .. LocalizedDrillID)

		-- Convert the Drill ID from its localized version to English
		local DrillID = DrillRigInEnglish[LocalizedDrillID]
		DebugPrint("Converted DrillID to English: " .. DrillID)

		if Driller.Projects[DrillID] then
			-- Found a proper drill message. Notify the user.
			DebugPrint("mob is >>" .. Driller.Projects[DrillID].Mob .. "<<")

			local LocWithLink = CreateWaypointLink(MECHAGON_MAPID, Driller.Projects[DrillID].Loc.x, Driller.Projects[DrillID].Loc.y, LocalizedDrillID)

			-- Print the notification with the link.
			Driller.Utilities.ChatPrint(L["ABOUT_TO_SPAWN"]:format(
				Driller.Utilities.CHAT_GREEN .. Driller.Projects[DrillID].Mob .. FONT_COLOR_CODE_CLOSE,
				LocWithLink
			))
		else
			Driller.Utilities.ChatPrint(L["UNKNOWN_DRILL_ID"]:format(DrillID))
		end
	else
		DebugPrint("Not a drill message.")
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
	DebugPrint("Registering event " .. k)
	Driller.Frame:RegisterEvent(k)
end


--#########################################
--# Create command line handler
--#########################################

local function PrintWaypointStatus()
	local ModeName

	if "TomTom" == Driller.mode then
		ModeName = L["TomTom's crazy arrow"]
	else
		ModeName = L["WoW's waypoints"]
	end
	Driller.Utilities.ChatPrint(L["LINK_FORMAT_CONFIRMATION"]:format(ModeName))
end -- PrintWaypointStatus()


-- Toggle debug mode if asked
function Driller.CommandLine(arg, ...)
	-- Ouptput messages are not localized because end users shouldn't be using this anwyay.
	if "DEBUG" == arg:upper() then
		Driller.DebugMode = not Driller.DebugMode
		if Driller.DebugMode then
			Driller.Utilities.ChatPrint("Debug mode is now " .. Driller.Utilities.CHAT_GREEN .. "on" .. FONT_COLOR_CODE_CLOSE .. ".")
		else
			Driller.Utilities.ChatPrint("Debug mode is now " .. Driller.Utilities.CHAT_RED .. "off" .. FONT_COLOR_CODE_CLOSE .. ".")
		end

	elseif "PRINTLINK" == arg:upper() then
		local LocWithLink = CreateWaypointLink(MECHAGON_MAPID, 68.4, 48.1, "Fake Kleptoboss")
		DebugPrint("Raw link: " .. LocWithLink:gsub("|", "||"))

		-- Print the notification with the link.
		Driller.Utilities.ChatPrint(L["ABOUT_TO_SPAWN"]:format(
			Driller.Utilities.CHAT_GREEN .. "Fake Kleptoboss" .. FONT_COLOR_CODE_CLOSE,
			LocWithLink
		))

	-- Enable TomTom support
	elseif "TOMTOM" == arg:upper() then
		if TomTom then
			DrillSergeant_DB.mode = "TomTom"
			DrillSergeant_DB.user_set = "true"
			Driller.mode = "TomTom"
			PrintWaypointStatus()
		else
			Driller.Utilities.ChatPrint("TomTom is not loaded, so it cannot be used.")
			PrintWaypointStatus()
		end

	-- enable WoW waypoint support
	elseif "WOW" == arg:upper() then
		DrillSergeant_DB.mode = "WoW"
		DrillSergeant_DB.user_set = "true"
		Driller.mode = "WoW"
		PrintWaypointStatus()

	-- Unknown argument
	elseif arg and arg ~= "" then
		Driller.Utilities.ChatPrint("Unrecognized command: " .. arg)

	-- If no argument, just print status
	else
		PrintWaypointStatus()
	end
end -- Driller.CommandLine()


-- Set the default slash command.
SLASH_DRILL1 = "/drill"
SlashCmdList.DRILL = function (...) Driller.CommandLine(...) end
