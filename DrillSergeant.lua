-- Driller.lua
-- Written by KyrosKrane Sylvanblade (kyros@kyros.info)
-- Copyright (c) 2019 KyrosKrane Sylvanblade
-- Licensed under the MIT License, as per the included file.

-- File revision: @file-abbreviated-hash@
-- File last updated: @file-date-iso@


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
Driller.Version = "@project-version@"


-- The mobs and locs identified by each drill rig
Driller.Projects = {
   ["DR-CC61"] = {Mob = "Gorged Gear-Cruncher", Loc = "72.63 53.85"},
   ["DR-CC73"] = {Mob = "Caustic Mechaslime", Loc = "66.40 58.84"},
   ["DR-CC88"] = {Mob = "The Kleptoboss", Loc = "68.38 48.14"},
   ["DR-JD41"] = {Mob = "Boilburn", Loc = "51.44 50.25"},
   ["DR-JD99"] = {Mob = "Gemicide", Loc = "59.65 67.20"},
   ["DR-TR28"] = {Mob = "Ol' Big Tusk", Loc = "56.15 36.32"},
   ["DR-TR35"] = {Mob = "Earthbreaker Gulroc", Loc = "63.53 25.00"},
}



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
			Driller:ChatPrint("Unknown Drill ID " .. DrillID .. ". Please report this message and the Drill Rig message right above it to the addon author for investigation.")
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
