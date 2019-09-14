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
--# Globals and utilities
--#########################################

-- Get a local reference to speed up execution.
local string = string
local print = print
local select = select
local type = type
local pairs = pairs

-- Define a global for our namespace
local Driller = {}


--#########################################
--# Frame for event handling
--#########################################

-- Create the frame to hold our event catcher, and the list of events.
Driller.Frame, Driller.Events = CreateFrame("Frame"), {}


--#########################################
--# Constants
--#########################################

-- The strings that define the addon
Driller.ADDON_NAME = "Driller" -- the internal addon name for LibStub and other addons
Driller.USER_ADDON_NAME = "Drill Sergeant" -- the name displayed to the user

-- The version of this add-on
Driller.Version = "@project-version@"

local CHAT_GREEN = "|cff" .. "00ff00"
local CHAT_BLUE = "|cff" .. "0066ff"
local CHAT_RED = "|cff" .. "a00000"


-- The mobs and locs identified by each drill rig
Driller.Projects = {
	["DR-CC61"] = {Mob = "Gorged Gear-Cruncher", Loc = "73.0, 54.2"}, -- loc confirmed
	["DR-CC73"] = {Mob = "Caustic Mechaslime", Loc = "66.5, 58.8"}, -- loc confirmed
	["DR-CC88"] = {Mob = "The Kleptoboss", Loc = "68.4, 48.1"},

	["DR-JD41"] = {Mob = "Boilburn", Loc = "51.1, 50.3"}, -- loc confirmed
	["DR-JD99"] = {Mob = "Gemicide", Loc = "59.7, 67.2"},

	["DR-TR28"] = {Mob = "Ol' Big Tusk", Loc = "56.2, 36.3"},
	["DR-TR35"] = {Mob = "Earthbreaker Gulroc", Loc = "63.2, 25.4"}, -- loc confirmed

	--@alpha@
	-- testing only
	["DR-Fake872"] = {Mob = "Automated flame turret (?? from 872)", Loc = "123, 456"},
	["DR-Fake951"] = {Mob = "Automated flame turret (?? from 951)", Loc = "123, 456"},
	["DR-Fake952"] = {Mob = "Automated flame turret (149879 from 952)", Loc = "123, 456"},
	["DR-Fake955"] = {Mob = "Automated flame turret (149879 from 955)", Loc = "123, 456"},
	["DR-Fake456"] = {Mob = "Auria Irondreamer", Loc = "123, 456"},
	--["DR-Fake789"] = {Mob = "Izzy Hollyfizzle", Loc = "123, 456"},
	--@end-alpha@
} -- Driller.Projects


Driller.MobIDs = {
	-- @TODO: Get the right IDs

	-- @TODO: Problem! the same ID is used for all three.
	[154695] = "DR-CC61", -- "Gorged Gear-Cruncher"
	[154695] = "DR-CC73", -- "Caustic Mechaslime"
	[154695] = "DR-CC88", -- "The Kleptoboss"

	[154933] = "DR-JD41", -- "Boilburn"
	[154933] = "DR-JD99", -- "Gemicide"

	-- @TODO: Problem! the same ID is used for both.
	[150277] = "DR-TR28", -- "Ol' Big Tusk"
	[150277] = "DR-TR35", -- "Earthbreaker Gulroc"

	--@alpha@
	-- testing only
	[149872] = "DR-Fake872", -- Broken flame turret
	[154951] = "DR-Fake951", -- Broken flame turret
	[154952] = "DR-Fake952", -- Automated flame turret (149879)
	[154955] = "DR-Fake955", -- Automated flame turret (149879)
	[77359] = "DR-Fake456",
	[96362] = "DR-Fake789",
	--@end-alpha@

--[===[
150306 - gemicide, Gemicide, gulorc, caustic mechaslime after complete

150277 - gulorc - BOTH Big Tusk and Gulroc. Problem.

154933 - Gemicide -- also boilburn?! double check
154695 - caustic mechaslime -- also gorged gearcruncher?!

This drill rig becomes DR-CC73, which opens the path to [url=https://www.wowhead.com/npc=154739/caustic-mechaslime]Caustic Mechaslime[/url].
-- ]===]

} -- Driller.MobIDs


--#########################################
--# Utility Functions
--#########################################

-- Dumps a table into chat. Not intended for production use.
function Driller:DumpTable(tab, indent)
	if not Driller.DebugMode then return end

	if not indent then indent = 0 end
	if indent > 10 then
		Driller:DebugPrint("Recursion is at 11 already; aborting.")
		return
	end
	for k, v in pairs(tab) do
		local s = ""
		if indent > 0 then
			for i = 0, indent do
				s = s .. "    "
			end
		end
		if "table" == type(v) then
			s = s .. "Item " .. k .. " is sub-table."
			Driller:DebugPrint(s)
			indent = indent + 1
			Driller:DumpTable(v, indent)
			indent = indent - 1
		else
			s = s .. "Item " .. k .. " is " .. tostring(v)
			Driller:DebugPrint(s)
		end
	end
end -- Driller:DumpTable()


--#########################################
--# Debugging setup
--#########################################

-- Debug settings
-- This is needed to debug stuff before the addon loads. After the addon loads, the permanent value is stored in Driller.DB.DebugMode
Driller.DebugMode = false

--@alpha@
Driller.DebugMode = true
--@end-alpha@


-- Print debug output to the chat frame.
function Driller:DebugPrint(msg)
	if not Driller.DebugMode then return end

	DEFAULT_CHAT_FRAME:AddMessage(CHAT_RED .. Driller.USER_ADDON_NAME .. " Debug: " .. FONT_COLOR_CODE_CLOSE .. msg)
end -- Driller:DebugPrint


-- Print regular output to the chat frame.
function Driller:ChatPrint(msg)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_BLUE .. Driller.USER_ADDON_NAME .. ": " .. FONT_COLOR_CODE_CLOSE .. msg)
end -- Driller:ChatPrint


-- Sets the debug mode and writes the setting to the DB
function Driller:SetDebugMode(setting)
	Driller.DebugMode = setting
	Driller.DB.DebugMode = setting
end


--#########################################
--# Tooltip detection and management
--#########################################

-- Code in this section adapted from idTip (public domain) by silv3rwind on Curse

-- Get the ID of an NPC being moused over
GameTooltip:HookScript("OnTooltipSetUnit", function(self)
	if not isClassicWow then
		if C_PetBattles.IsInBattle() then return end
	end

	-- Find out what unit is being moused over
	local unit = select(2, self:GetUnit())
	if not unit then return end

	-- get details on the unit, and make sure it's not a player.
	local guid = UnitGUID(unit) or ""
	local NPCID = tonumber(guid:match("-(%d+)-%x+$"), 10)
	local IsPlayer = guid:match("%a+") == "Player"
	if IsPlayer or not NPCID then return end

	if type(NPCID) == "table" then
		-- This branch should normally never happen.
		-- The original version of the function had to be adaptable to many different tooltip types,
		--   some of which could return multiple values.
		-- But NPCs should only ever have a single ID.
		-- Just in case it does, make sure we don't corrupt the tooltip.

		Driller:DebugPrint("found ID that's a table, dumping")
		Driller:DumpTable(NPCID)

		if #NPCID == 1 then
			Driller:DebugPrint("Converting single-element NPCID table to a simple value")
			NPCID = NPCID[1]
		else

			Driller:DebugPrint("Found multi-elemental table for NPCID. Bailing out.")
			return
		end
	end

	--Driller:DebugPrint("found ID " .. NPCID)

	local ProjectID = Driller.MobIDs[NPCID]
	if not ProjectID then
		--Driller:DebugPrint("no Project ID found in MobIDs for NPCID ".. NPCID)
		return
	end

	Driller:DebugPrint("NPCID is " .. NPCID ..", ProjectID is " .. ProjectID)

	local Project = Driller.Projects[ProjectID]
	if not Project then
		Driller:ChatPrint("No matching project for mob ID " .. NPCID .. ". Bad programmer, no cookie! Please inform the addon author to fix this error.")
		return
	end

	local Mob = Project.Mob

	Driller:DebugPrint("match found in MobIDs: " .. Mob)
	GameTooltip:AddLine(ProjectID .. " opens a path to " .. CHAT_GREEN .. Mob .. FONT_COLOR_CODE_CLOSE)
	GameTooltip:Show()

end) -- HookScript("OnTooltipSetUnit")


--#########################################
--# Events to register and handle
--#########################################

-- This triggers when someone joins or leaves a group, or changes their spec or role in the group.
function Driller.Events:CHAT_MSG_MONSTER_EMOTE(...)
	local message, sender = ...
	Driller:DebugPrint("Got CHAT_MSG_MONSTER_EMOTE")
	Driller:DebugPrint("message is >>" .. message .. "<<")
	Driller:DebugPrint("sender is >>" .. sender .. "<<")

	local DrillID = string.match(message, "Drill Rig (.*) has been activated! It will finish excavating in 1 minute.")

	if DrillID then
		Driller:DebugPrint("Identified DrillID " .. DrillID)
		if Driller.Projects[DrillID] then
			Driller:DebugPrint("mob is >>" .. Driller.Projects[DrillID].Mob .. "<<")
			Driller:DebugPrint("loc is >>" .. Driller.Projects[DrillID].Loc .. "<<")

			-- Found a proper drill message. Notify the user.
			Driller:ChatPrint(CHAT_GREEN .. Driller.Projects[DrillID].Mob .. FONT_COLOR_CODE_CLOSE .. " is about to spawn at location " .. Driller.Projects[DrillID].Loc .. " in one minute.")
		else
			Driller:ChatPrint("Unknown Drill ID " .. DrillID .. ". Please report this message and the Drill Rig message right above (or below) it to the addon author for investigation.")
		end
	else
		Driller:DebugPrint("Not a drill message.")
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
	Driller:DebugPrint("Registering event " .. k)
	Driller.Frame:RegisterEvent(k)
end
