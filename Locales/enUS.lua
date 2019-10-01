-- enUS.lua
-- Written by KyrosKrane Sylvanblade (kyros@kyros.info)
-- Copyright (c) 2019 KyrosKrane Sylvanblade
-- Licensed under the MIT License, as per the included file.

-- File revision: @file-abbreviated-hash@
-- File last updated: @file-date-iso@


--#########################################
--# Description
--#########################################

-- This file includes the master localization setup for Drill Sergeant in English.

--#########################################
--# Bail out on WoW Classic
--#########################################

-- Mechagon doesn't exist on WoW Classic, so if a user runs this on Classic, just exit at once.
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then return end

-- Get the addon info
local addonName, Driller = ...

-- Set the locale
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true)

-- Get the locale strings
if L then

	------------------------------------
	-- START CURSE LOCALIZATIONS
	------------------------------------

	-- The addon name
	L["Drill Sergeant"] = "Drill Sergeant"

	-- This is the Drill Rig announcement message. We use it to capture the drill rig ID to figure out what mob will spawn.
	L["DRILL_RIG_MSG_CAPTURE"] = "Drill Rig (.*) has been activated! It will finish excavating in 1 minute."

	-- This is the message the user gets when mousing over something too far away.
	L["TOO_FAR"] = "Too far to identify, move closer"


	-- These translations convert the local-language drill rig names to the English equivalents so they can be correctly mapped.
	-- These are of the form L["English"] = "Foreign"
	L["DR-CC61"] = "DR-CC61"
	L["DR-CC73"] = "DR-CC73"
	L["DR-CC88"] = "DR-CC88"
	L["DR-JD41"] = "DR-JD41"
	L["DR-JD99"] = "DR-JD99"
	L["DR-TR28"] = "DR-TR28"
	L["DR-TR35"] = "DR-TR35"


	-- These are the names of the rare NPCs that can spawn from the drill rigs
	L["Gorged Gear-Cruncher"] = "Gorged Gear-Cruncher"
	L["Caustic Mechaslime"] = "Caustic Mechaslime"
	L["The Kleptoboss"] = "The Kleptoboss"
	L["Boilburn"] = "Boilburn"
	L["Gemicide"] = "Gemicide"
	L["Ol' Big Tusk"] = "Ol' Big Tusk"
	L["Earthbreaker Gulroc"] = "Earthbreaker Gulroc"

	-- Bonus NPC
	L["Fungarian Furor"] = "Fungarian Furor"


	-- These are phrases that require substitutions
	L["OPENS_A_PATH"] = "%1$s opens a path to %2$s"
	L["ABOUT_TO_SPAWN"] = "%1$s is about to spawn at location %2$s in one minute."

	L["FUROR"] = "Spawns %1$s when activated"
	L["NOT_FUROR"] = "Does not spawn %1$s when activated"

	L["PROJECT_ERROR"] = "No matching project for mob ID %1$s with project ID %2$s . Bad programmer, no cookie! Please inform the addon author to fix this error."
	L["UNKNOWN_DRILL_ID"] = "Unknown Drill ID %1$s. Please report this message and the Drill Rig message right above (or below) it to the addon author for investigation."

	------------------------------------
	-- END CURSE LOCALIZATIONS
	------------------------------------

end
