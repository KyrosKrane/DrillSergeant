-- Utilities.lua
-- Written by KyrosKrane Sylvanblade (kyros@kyros.info)
-- Copyright (c) 2019 KyrosKrane Sylvanblade
-- Licensed under the MIT License, as per the included file.

-- File revision: @file-abbreviated-hash@
-- File last updated: @file-date-iso@

-- This file creates a bunch of utility functions, stored in the addon-specific table provided by WoW.

local addonName, addon = ...
if not addon.Utilities then addon.Utilities = {} end


--#########################################
--# Chat output setup
--#########################################

-- Colors for printing in chat.
local CHAT_GREEN = "|cff" .. "00ff00"
local CHAT_BLUE = "|cff" .. "0066ff"
local CHAT_RED = "|cff" .. "a00000"


-- Print regular output to the chat frame.
function addon.Utilities:ChatPrint(msg)
	-- I considered changing this to use WrapTextInColorCode(msg, colorcode), but it kills readability and requires changing the chat constants everywhere.
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_BLUE .. addon.USER_ADDON_NAME .. ": " .. FONT_COLOR_CODE_CLOSE .. msg)
end -- addon.Utilities:ChatPrint


--#########################################
--# Debugging setup
--#########################################

-- Debug settings. True turns on debugging output, which users shouldn't normally need to see.
addon.DebugMode = false

--@alpha@
addon.DebugMode = true
--@end-alpha@


-- Print debug output to the chat frame.
function addon.Utilities:DebugPrint(msg)
	if not addon.DebugMode then return end

	DEFAULT_CHAT_FRAME:AddMessage(CHAT_RED .. addonName .. " Debug: " .. FONT_COLOR_CODE_CLOSE .. msg)
end -- addon.Utilities:DebugPrint


-- Dumps a table into chat. Not intended for production use.
local MAX_RECURSION_DEPTH = 10
function addon.Utilities:DumpTable(TableToDump, indent)
	if not addon.DebugMode then return end

	if not indent then indent = 0 end
	if indent > MAX_RECURSION_DEPTH then
		addon.Utilities:DebugPrint("Recursion is at" .. (MAX_RECURSION_DEPTH + 1) .. " already; aborting.")
		return
	end

	for k, v in pairs(TableToDump) do
		local s = ""
		if indent > 0 then
			for i = 0, indent do
				s = s .. "    "
			end
		end
		if "table" == type(v) then
			s = s .. "Item " .. k .. " is sub-table."
			addon.Utilities:DebugPrint(s)
			indent = indent + 1
			addon.Utilities:DumpTable(v, indent)
			indent = indent - 1
		else
			s = s .. "Item " .. k .. " is " .. tostring(v)
			addon.Utilities:DebugPrint(s)
		end
	end
end -- addon.Utilities:DumpTable()


--#########################################
--# General utilities
--#########################################


-- This function determines whether a point S is inside a triangle described by points A, B, and C.
-- Returns true (inside) or false (outside)
-- Adapted from the answer by John Bananas here: https://stackoverflow.com/questions/2049582/how-to-determine-if-a-point-is-in-a-2d-triangle
-- s, a, b, and c must all be objects (tables) with two elements named x and y.
function addon.Utilities:IsInsideTriangle(s, a, b, c)
    local as_x = s.x-a.x
    local as_y = s.y-a.y

    local s_ab = (b.x-a.x)*as_y-(b.y-a.y)*as_x > 0

	if (c.x-a.x)*as_y-(c.y-a.y)*as_x > 0 == s_ab then return false end

	if (c.x-b.x)*(s.y-b.y)-(c.y-b.y)*(s.x-b.x) > 0 ~= s_ab then return false end

    return true
end -- addon.Utilities:IsInsideTriangle()

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
