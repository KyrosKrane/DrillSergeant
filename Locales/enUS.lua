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

--@localization(locale="enUS", format="lua_additive_table", handle-unlocalized="english")@

	------------------------------------
	-- END CURSE LOCALIZATIONS
	------------------------------------

end
