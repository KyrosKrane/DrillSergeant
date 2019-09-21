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

-- Mechagon doesn't exist on WoW Classic, so if a user runs this on Classic, just return at once.
local IsClassic = select(4, GetBuildInfo()) < 20000
if IsClassic then return end


--#########################################
--# Globals and utilities
--#########################################

-- Get a local reference to speed up execution.
local string = string
local print = print
local select = select
local type = type
local pairs = pairs
local tostring = tostring
local tonumber = tonumber


-- Define a global for our namespace
local Driller = {}


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
--# Constants
--#########################################

-- The strings that define the addon
Driller.ADDON_NAME = "Driller" -- the internal addon name for LibStub and other addons
Driller.USER_ADDON_NAME = "Drill Sergeant" -- the name displayed to the user

-- The version of this add-on
Driller.Version = "@project-version@"

-- Colors for printing in chat.
local CHAT_GREEN = "|cff" .. "00ff00"
local CHAT_BLUE = "|cff" .. "0066ff"
local CHAT_RED = "|cff" .. "a00000"

-- Map ID for Mechagon, used for ensuring we're in the right zone and for calculating distances on the world map.
local MECHAGON_MAPID = 1462


-- The mobs and locs identified by each drill rig
Driller.Projects = {
	["DR-CC61"] = {Mob = "Gorged Gear-Cruncher", Loc = {x = 73.0, y = 54.2}},
	["DR-CC73"] = {Mob = "Caustic Mechaslime", Loc = {x = 66.5, y = 58.8}},
	["DR-CC88"] = {Mob = "The Kleptoboss", Loc = {x = 68.4, y = 48.1}},

	["DR-JD41"] = {Mob = "Boilburn", Loc = {x = 51.1, y = 50.3}},
	["DR-JD99"] = {Mob = "Gemicide", Loc = {x = 59.7, y = 67.2}},

	["DR-TR28"] = {Mob = "Ol' Big Tusk", Loc = {x = 56.2, y = 36.3}},
	["DR-TR35"] = {Mob = "Earthbreaker Gulroc", Loc = {x = 63.2, y = 25.4}},
} -- Driller.Projects


-- For reference only, not actually used in code any more.
Driller.MobIDs = {
	[154695] = "DR-CC61", -- "Gorged Gear-Cruncher"
	[154695] = "DR-CC73", -- "Caustic Mechaslime"
	[154695] = "DR-CC88", -- "The Kleptoboss"

	[154933] = "DR-JD41", -- "Boilburn"
	[154933] = "DR-JD99", -- "Gemicide"

	[150277] = "DR-TR28", -- "Ol' Big Tusk"
	[150277] = "DR-TR35", -- "Earthbreaker Gulroc"
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


-- This function determines whether a point S is inside a triangle described by points A, B, and C.
-- Returns true (inside) or false (outside)
-- Adapted from the answer by John Bananas here: https://stackoverflow.com/questions/2049582/how-to-determine-if-a-point-is-in-a-2d-triangle
-- s, a, b, and c must all be objects (tables) with two elements named x and y.
function IsInsideTriangle(s, a, b, c)
    local as_x = s.x-a.x
    local as_y = s.y-a.y

    local s_ab = (b.x-a.x)*as_y-(b.y-a.y)*as_x > 0

	if (c.x-a.x)*as_y-(c.y-a.y)*as_x > 0 == s_ab then return false end

	if (c.x-b.x)*(s.y-b.y)-(c.y-b.y)*(s.x-b.x) > 0 ~= s_ab then return false end

    return true
end -- IsInsideTriangle()

--[===[
-- Test case
Gorged  = {x = 73.0, y = 54.2}
Caustic = {x = 66.5, y = 58.8}
Klepto  = {x = 68.4, y = 48.1}

outside = {x = 1, y = 1}
inside = {x = 68, y = 54}

if IsInsideTriangle(inside, Gorged, Caustic, Klepto) then print "inside reports true - PASS" else print "inside reports false - FAIL" end
if IsInsideTriangle(outside, Gorged, Caustic, Klepto) then print "outside reports true - FAIL" else print "outside reports false - PASS" end
-- ]===]


--#########################################
--# Debugging setup
--#########################################

-- Debug settings. True turns on debugging output, which users shouldn't normally need to see.
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


--#########################################
--# Tooltip detection and management
--#########################################

-- Code in this section adapted from idTip (public domain) by silv3rwind on Curse

-- Get the ID of an NPC being moused over
GameTooltip:HookScript("OnTooltipSetUnit", function(self)
	if C_PetBattles.IsInBattle() then return end

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

			Driller:DebugPrint("Found multi-element table for NPCID. Bailing out.")
			return
		end
	end

		-- not a tracked ID
		--Driller:DebugPrint("Not a tracked NPC.")
		return
	end

	-- Get player coordinates
	local PlayerX, PlayerY, PinstanceID = HBD:GetPlayerWorldPosition()
	Driller:DebugPrint("PlayerX is " .. PlayerX or "nil")
	Driller:DebugPrint("PlayerY is " .. PlayerY or "nil")
	Driller:DebugPrint("PinstanceID is " .. PinstanceID or "nil") -- not actually used right now.
	-- if HBD returns invalid X or Y values (usually because the client is too busy), bail out so we don't throw user errors.
	if not PlayerX or not PlayerY then return end

	local ProjectID, MobX, MobY-- used for finding the range

	if 154695 == NPCID then
		-- could be:
		-- "DR-CC61", -- "Gorged Gear-Cruncher"
		-- "DR-CC73", -- "Caustic Mechaslime"
		-- "DR-CC88", -- "The Kleptoboss"
		Driller:DebugPrint("In CC block.")

		-- Find out which mob is closest
		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-CC61"].Loc.x/100, Driller.Projects["DR-CC61"].Loc.y/100, MECHAGON_MAPID)
		local RangeToGearCruncher = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToGearCruncher is " .. MobX .. ", " .. MobY .. ", " .. RangeToGearCruncher)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-CC73"].Loc.x/100, Driller.Projects["DR-CC73"].Loc.y/100, MECHAGON_MAPID)
		local RangeToMechaslime = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToMechaslime is " .. MobX .. ", " .. MobY .. ", " .. RangeToMechaslime)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-CC88"].Loc.x/100, Driller.Projects["DR-CC88"].Loc.y/100, MECHAGON_MAPID)
		local RangeToKleptoboss = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToKleptoboss is " .. MobX .. ", " .. MobY .. ", " .. RangeToKleptoboss)

		if RangeToGearCruncher <= RangeToMechaslime and RangeToGearCruncher <= RangeToKleptoboss then
			Driller:DebugPrint("Picking DR-CC61 Gorged Gear-Cruncher")
			ProjectID = "DR-CC61" -- "Gorged Gear-Cruncher"
		elseif RangeToMechaslime <= RangeToGearCruncher and RangeToMechaslime <= RangeToKleptoboss then
			Driller:DebugPrint("Picking DR-CC73 Caustic Mechaslime")
			ProjectID = "DR-CC73" -- "Caustic Mechaslime"
		else
			Driller:DebugPrint("Picking DR-CC88 Kleptoboss")
			ProjectID = "DR-CC88" -- "Kleptoboss"
		end

	elseif 154933 == NPCID then
		-- could be:
		-- "DR-JD41", -- "Boilburn"
		-- "DR-JD99", -- "Gemicide"
		Driller:DebugPrint("In JD block.")

		-- Find out which is closer
		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-JD41"].Loc.x/100, Driller.Projects["DR-JD41"].Loc.y/100, MECHAGON_MAPID)
		local RangeToBoilburn = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToBoilburn is " .. MobX .. ", " .. MobY .. ", " .. RangeToBoilburn)

		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-JD99"].Loc.x/100, Driller.Projects["DR-JD99"].Loc.y/100, MECHAGON_MAPID)
		local RangeToGemicide = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToGemicide is " .. MobX .. ", " .. MobY .. ", " .. RangeToGemicide)

		if RangeToBoilburn < RangeToGemicide then
			Driller:DebugPrint("Picking DR-JD41 Boilburn")
			ProjectID = "DR-JD41" -- "Boilburn"
		else
			Driller:DebugPrint("Picking DR-JD99 Gemicide")
			ProjectID = "DR-JD99" -- "Gemicide"
		end
	elseif 150277 == NPCID then
		-- could be:
		-- "DR-TR28", -- "Ol' Big Tusk"
		-- "DR-TR35", -- "Earthbreaker Gulroc"
		Driller:DebugPrint("In TR block.")

		-- Find out which is closer
		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-TR28"].Loc.x/100, Driller.Projects["DR-TR28"].Loc.y/100, MECHAGON_MAPID)
		local RangeToBigTusk = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToBigTusk is " .. MobX .. ", " .. MobY .. ", " .. RangeToBigTusk)


		MobX, MobY = HBD:GetWorldCoordinatesFromZone(Driller.Projects["DR-TR35"].Loc.x/100, Driller.Projects["DR-TR35"].Loc.y/100, MECHAGON_MAPID)
		local RangeToGulroc = HBD:GetWorldDistance(MECHAGON_MAPID, PlayerX, PlayerY, MobX, MobY)
		Driller:DebugPrint("MobX, MobY, RangeToGulroc is " .. MobX .. ", " .. MobY .. ", " .. RangeToGulroc)

		if RangeToBigTusk < RangeToGulroc then
			Driller:DebugPrint("Picking DR-TR28 Ol' Big Tusk")
			ProjectID = "DR-TR28" -- "Ol' Big Tusk"
		else
			Driller:DebugPrint("Picking DR-TR35 Earthbreaker Gulroc")
			ProjectID = "DR-TR35" -- "Earthbreaker Gulroc"
		end
	else
		-- not a tracked ID
		--Driller:DebugPrint("Not a tracked NPC.")
		return
	end

	-- Make sure we got a valid project. If somehow we didn't, bail out.
	if not ProjectID then	return	end

	Driller:DebugPrint("NPCID is " .. NPCID ..", ProjectID is " .. ProjectID)

	local Project = Driller.Projects[ProjectID]
	if not Project then
		Driller:ChatPrint("No matching project for mob ID " .. NPCID .. " with project ID " .. ProjectID .. ". Bad programmer, no cookie! Please inform the addon author to fix this error.")
		return
	end

	Driller:DebugPrint("match found in MobIDs: " .. Project.Mob)
	GameTooltip:AddLine(ProjectID .. " opens a path to " .. CHAT_GREEN .. Project.Mob .. FONT_COLOR_CODE_CLOSE)
	GameTooltip:Show()

end) -- HookScript("OnTooltipSetUnit")


--#########################################
--# Events to register and handle
--#########################################

-- This triggers when an NPC gives an emote.
function Driller.Events:CHAT_MSG_MONSTER_EMOTE(...)
	local message, sender = ...
	Driller:DebugPrint("Got CHAT_MSG_MONSTER_EMOTE")
	Driller:DebugPrint("message is >>" .. message .. "<<")
	Driller:DebugPrint("sender is >>" .. sender .. "<<")

	-- Parse the message to see whether it is a drill rig announcement.
	-- #TODO: This needs localization!
	local DrillID = string.match(message, "Drill Rig (.*) has been activated! It will finish excavating in 1 minute.")

	if DrillID then
		Driller:DebugPrint("Identified DrillID " .. DrillID)
		if Driller.Projects[DrillID] then
			Driller:DebugPrint("mob is >>" .. Driller.Projects[DrillID].Mob .. "<<")
			local Loc = Driller.Projects[DrillID].Loc.x .. ", " .. Driller.Projects[DrillID].Loc.y
			Driller:DebugPrint("loc is >>" .. Loc .. "<<")

			-- Found a proper drill message. Notify the user.
			Driller:ChatPrint(CHAT_GREEN .. Driller.Projects[DrillID].Mob .. FONT_COLOR_CODE_CLOSE .. " is about to spawn at location " .. Loc .. " in one minute.")
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


--#########################################
--# Create command line for debug mode toggling
--#########################################


-- Toggle debug mode if asked
function Driller.CommandLine(arg, ...)
	if "DEBUG" == arg:upper() then
		Driller.DebugMode = not Driller.DebugMode
		if Driller.DebugMode then
			Driller:ChatPrint("Debug mode is now " .. CHAT_GREEN .. "on" .. FONT_COLOR_CODE_CLOSE .. ".")
		else
			Driller:ChatPrint("Debug mode is now " .. CHAT_RED .. "off" .. FONT_COLOR_CODE_CLOSE .. ".")
		end
	else
		Driller:ChatPrint("Unrecognized command: " .. arg)
	end
end -- Driller.CommandLine()


-- Set the default slash command.
SLASH_DS1 = "/ds"
SlashCmdList.DS = function (...) Driller.CommandLine(...) end
