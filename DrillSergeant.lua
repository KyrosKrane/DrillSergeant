-- Driller.lua
-- Written by KyrosKrane Sylvanblade (kyros@kyros.info)
-- Copyright (c) 2019 KyrosKrane Sylvanblade
-- Licensed under the MIT License, as per the included file.

-- File revision: 5070f7d
-- File last updated: 2019-09-12T23:16:03Z


--#########################################
--# Description
--#########################################

-- This add-on intercepts drill rig announcements in Mechagon and updates them to include the name of the associated rare, and the drill location.
-- It also adds the name of the rare to the tooltip when mousing over them.


--#########################################
--# Globals and utilities
--#########################################

-- Get a local reference to speed up execution.
local _G = _G
local string = string
local print = print
local setmetatable = setmetatable
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
Driller.Version = "v0.2-alpha"


-- The mobs and locs identified by each drill rig
Driller.Projects = {
	["DR-CC61"] = {Mob = "Gorged Gear-Cruncher", Loc = "72.63, 53.85"},
	["DR-CC73"] = {Mob = "Caustic Mechaslime", Loc = "66.40, 58.84"},
	["DR-CC88"] = {Mob = "The Kleptoboss", Loc = "68.38, 48.14"},
	["DR-JD41"] = {Mob = "Boilburn", Loc = "51.44, 50.25"},
	["DR-JD99"] = {Mob = "Gemicide", Loc = "59.65, 67.20"},
	["DR-TR28"] = {Mob = "Ol' Big Tusk", Loc = "56.15, 36.32"},
	["DR-TR35"] = {Mob = "Earthbreaker Gulroc", Loc = "63.53, 25.00"},

	--@alpha@
	-- testing only
	["DR-Fake123"] = {Mob = "Automated flame turret", Loc = "123, 456"}, -- Broken flame turret
	["DR-Fake456"] = {Mob = "Auria Irondreamer", Loc = "123, 456"},
	--["DR-Fake789"] = {Mob = "Izzy Hollyfizzle", Loc = "123, 456"},
	--@end-alpha@



} -- Driller.Projects


Driller.MobIDs = {
	-- @TODO: Get the right IDs
	[9000123] = "DR-CC61", -- "Gorged Gear-Cruncher"
	[9000124] = "DR-CC73", -- "Caustic Mechaslime"
	[9000125] = "DR-CC88", -- "The Kleptoboss"
	[9000126] = "DR-JD41", -- "Boilburn"
	[9000127] = "DR-JD99", -- "Gemicide"
	[9000128] = "DR-TR28", -- "Ol' Big Tusk"
	[9000129] = "DR-TR35", -- "Earthbreaker Gulroc"

	--@alpha@
	-- testing only
	[154951] = "DR-Fake123", -- Broken flame turret
	[77359] = "DR-Fake456",
	[96362] = "DR-Fake789",
	--@end-alpha@

} -- Driller.MobIDs



--#########################################
--# Utility Functions
--#########################################


-- Dumps a table into chat. Not intended for production use.
function Driller:DumpTable(tab, indent)
	if not indent then indent = 0 end
	if indent > 10 then
		APR:DebugPrint("Recursion is at 11 already; aborting.")
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
			APR:DebugPrint(s)
			indent = indent + 1
			APR:DumpTable(v, indent)
			indent = indent - 1
		else
			s = s .. "Item " .. k .. " is " .. tostring(v)
			APR:DebugPrint(s)
		end
	end
end -- APR:DumpTable()



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
function Driller:DebugPrint(...)
	if not Driller.DebugMode then return end

	print ("|cff" .. "a00000" .. Driller.USER_ADDON_NAME .. " Debug:|r", ...)
end -- Driller:DebugPrint


-- Print regular output to the chat frame.
function Driller:ChatPrint(...)
	print ("|cff" .. "0066ff" .. Driller.USER_ADDON_NAME .. ":|r", ...)
end -- Driller:DebugPrint


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
		-- Just in case it does, return so we don't corrupt the tooltip.

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

	Driller:DebugPrint("found ID " .. NPCID)

	local ProjectID = Driller.MobIDs[NPCID]

	if ProjectID then
		Driller:DebugPrint("ProjectID is " .. ProjectID)

		local Project = Driller.Projects[ProjectID]
		if not Project then
			Driller:ChatPrint("No matching project for mob ID " .. NPCID .. ". Bad programmer, no cookie! Please inform the addon author to fix this error.")
			return
		end

		local Mob = Project.Mob

		Driller:DebugPrint("match found in MobIDs: " .. Mob)
		GameTooltip:AddLine(ProjectID .. " opens a path to " .. Mob)
		GameTooltip:Show()
	else
		Driller:DebugPrint("no match found in MobIDs")
	end

end) -- HookScript("OnTooltipSetUnit")

--[===[
Broken flame turret - xxx955
Automated flame turret - 149879

rec rig unbuilt - 150451
defended/built - 150448
-- ]===]

--#########################################
--# Events to register and handle
--#########################################

-- This event is only for debugging.
-- Note that PLAYER_LOGIN is triggered after all ADDON_LOADED events
function Driller.Events:PLAYER_LOGIN(...)
	Driller:DebugPrint("Got PLAYER_LOGIN event")
end -- Driller.Events:PLAYER_LOGIN()


-- This event is for loading our saved settings.
function Driller.Events:ADDON_LOADED(addon)
	Driller:DebugPrint("Got ADDON_LOADED for " .. addon)
	if addon ~= Driller.ADDON_NAME then return end

	Driller:DebugPrint("Recognized myself, ready for processing on-load settings!")
end -- Driller.Events:ADDON_LOADED()


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
			Driller:ChatPrint(Driller.Projects[DrillID].Mob .. " is about to spawn at location " .. Driller.Projects[DrillID].Loc .. " in one minute.")
		else
			Driller:ChatPrint("Unknown Drill ID " .. DrillID .. ". Please report this message and the Drill Rig message right above (or below) it to the addon author for investigation.")
		end
	else
		Driller:DebugPrint("Not a drill message.")
	end


end -- Driller.Events:CHAT_MSG_MONSTER_EMOTE()


-- On-load handler for addon initialization.
function Driller.Events:PLAYER_ENTERING_WORLD(...)
	-- Announce our load.
	Driller:DebugPrint("Got PLAYER_ENTERING_WORLD")

end -- Driller.Events:PLAYER_ENTERING_WORLD()



--#########################################
--# Implement the event handlers
--#########################################

-- Create the event handler function.
Driller.Frame:SetScript("OnEvent", function(self, event, ...)
	Driller.Events[event](self, ...) -- call one of the functions above
end)

-- Register all events for which handlers have been defined
for k, v in pairs(Driller.Events) do
	Driller:DebugPrint("Registering event ", k)
	Driller.Frame:RegisterEvent(k)
end
