--[[
	Auctioneer
	Version: 1.13.6664 (SwimmingSeadragon)
	Revision: $Id: CoreResources.lua 6664 2021-01-30 13:42:33Z none $
	URL: http://auctioneeraddon.com/

	This is an addon for World of Warcraft that adds statistical history to the auction data that is collected
	when the auction is scanned, so that you can easily determine what price
	you will be able to sell an item for at auction or at a vendor whenever you
	mouse-over an item in the game

	License:
		This program is free software; you can redistribute it and/or
		modify it under the terms of the GNU General Public License
		as published by the Free Software Foundation; either version 2
		of the License, or (at your option) any later version.

		This program is distributed in the hope that it will be useful,
		but WITHOUT ANY WARRANTY; without even the implied warranty of
		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
		GNU General Public License for more details.

		You should have received a copy of the GNU General Public License
		along with this program(see GPL.txt); if not, write to the Free Software
		Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

	Note:
		This AddOn's source code is specifically designed to work with
		World of Warcraft's interpreted AddOn system.
		You have an implicit license to use this AddOn with these facilities
		since that is its designated purpose as per:
		http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
--]]

--[[
	Dynamic Resource support module

	Maintain a table of commonly used values that may change during play,
	for use in a similar manner to the Const table.
	Other modules or AddOns may read from the Resources table at any time, but must not modify it!

	Includes:
	Status flags for AuctionHouse, Mailbox
	Faction information
	Pre-formed serverKeys

	Additionally, Processor event messages will be generated when certain values change
--]]

local AucAdvanced = AucAdvanced
if not AucAdvanced then return end
AucAdvanced.CoreFileCheckIn("CoreResources")
local coremodule, internalResources, _, internal = AucAdvanced.GetCoreModule("CoreResources", "Resources", nil, nil, "CoreResources")
if not (coremodule and internalResources and internal) then return end
local Const = AucAdvanced.Const

-- internal constants
--local PLAYER_REALM = Const.PlayerRealm
local CUT_HOME = 0.05
local CUT_NEUTRAL = 0.15

-- internal variables
local EventFrame


--[[ Setup AucAdvanced.Resources table ]]--
local lib = AucAdvanced.Resources
lib.Active = false
lib.AuctionHouseOpen = false
lib.MailboxOpen = false
lib.IsNeutralZone = false
lib.ZoneMapID = 0
lib.ZoneMapName = "Unknown"

--[[ Faction handlers ]]--

local function InitFaction()
	InitFaction = nil
	local playerFaction = UnitFactionGroup("player") -- returns reliable results from PLAYER_ENTERING_WORLD event onward
	local opposingFaction
	if playerFaction == "Alliance" then
		opposingFaction = "Horde"
	elseif playerFaction == "Horde" then
		opposingFaction = "Alliance"
	else
		-- Should not be possible
		local msg = "CoreResources faction initialization failed: faction was "..tostring(playerFaction)
		error(msg)
	end

	lib.PlayerFaction = playerFaction
	lib.OpposingFaction = opposingFaction

end

-- Map zone helper function
local function FindMapZone()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil, "No MapID" end
	-- mapID is now the "best" map for the current player location, but we want the Zone mapID
	repeat
		local info = C_Map.GetMapInfo(mapID)
		if not (info and info.mapType) then return nil, "No map info" end
		if info.mapType <= 3 then
			-- for the Zone map we want info.mapType == 3
			-- if info.mapType < 3 there is no Zone map, so use current map as a fallback
			return mapID, info.name or "Unknown"
		else
			local parent = info.parentMapID -- provides the mapID one level up from the current map
			if not parent or parent == 0 or mapID == parent then
				return nil, "No Parent"
			else
				mapID = parent
			end
		end
	until false
end

-- Reference https://wow.gamepedia.com/UiMapID/Classic
local lookupNeutralZones = {
	[1434] = true, -- Stranglethorn Vale
	[1452] = true, -- Winterspring
	[1446] = true, -- Tanaris
}
local prevMapID, prevServerKey, prevServerKeyDisplay -- store these values so we can detect when they change
local function UpdateZoneFaction(forceUpdate)
	local mapID, mapName = FindMapZone()
	if not mapID then
		-- This can occur when entering an instance. We shall assign a value of "Unknown". The code below will treat this as "Home"
		mapID, mapName = 0, "Unknown"
	end
	if mapID ~= prevMapID or forceUpdate then
		prevMapID = mapID
		lib.ZoneMapID, lib.ZoneMapName = mapID, mapName

		if lookupNeutralZones[mapID] then -- In a Neutral AuctionHouse zone
			lib.IsNeutralZone = true
			lib.CurrentFaction = "Neutral"
			lib.AHCutRate = CUT_NEUTRAL
			lib.AHCutAdjust = 1 - CUT_NEUTRAL
			if AucAdvanced.Settings.GetSetting("core.tooltip.alwayshomefaction") and not lib.AuctionHouseOpen then
				lib.DisplayFaction = lib.PlayerFaction -- display home faction in neutral areas, but not when AH is open
			else
				lib.DisplayFaction = "Neutral"
			end
		else
			lib.IsNeutralZone = false
			lib.CurrentFaction = lib.PlayerFaction
			lib.AHCutRate = CUT_HOME
			lib.AHCutAdjust = 1 - CUT_HOME
			lib.DisplayFaction = lib.PlayerFaction
		end
		internal.Servers.UpdateCurrentServerKey() -- set ServerKey and ServerKeyDisplay
		if lib.ServerKey ~= prevServerKey or lib.ServerKeyDisplay ~= prevServerKeyDisplay then
			prevServerKey, prevServerKeyDisplay = lib.ServerKey, lib.ServerKeyDisplay
			AucAdvanced.SendProcessorMessage("serverkey", prevServerKey, prevServerKeyDisplay)
			-- AucAdvanced.Print("Auctioneer is using serverKey "..lib.ServerKey.." ("..lib.ServerKeyDisplay.." in tooltips)") -- ### debug
		end
	end
end

--[[ Event handlers and other entry points ]]--
local function OnEvent(self, event, ...)
	if event == "AUCTION_HOUSE_SHOW" then
		lib.AuctionHouseOpen = true
		AucAdvanced.Scan.LoadScanData()
		UpdateZoneFaction(true) -- may change ServerKeyDisplay
		AucAdvanced.SendProcessorMessage("auctionopen")
	elseif event == "AUCTION_HOUSE_CLOSED" then
		-- AUCTION_HOUSE_CLOSED usually fires twice; only send message for the first one
		if lib.AuctionHouseOpen then
			lib.AuctionHouseOpen = false
			UpdateZoneFaction(true) -- may change ServerKeyDisplay
			AucAdvanced.SendProcessorMessage("auctionclose")
		end
	elseif event == "MAIL_SHOW" then
		lib.MailboxOpen = true
		AucAdvanced.SendProcessorMessage("mailopen")
	elseif event == "MAIL_CLOSED" then
		-- MAIL_CLOSED usually fires twice; only send message for the first one
		if lib.MailboxOpen then
			lib.MailboxOpen = false
			AucAdvanced.SendProcessorMessage("mailclose")
		end
	elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event =="ZONE_CHANGED_NEW_AREA" then
		-- do we really need all three events?
		UpdateZoneFaction()
	end
end

coremodule.Processors = {
	configchanged = function(callbackType, fullsetting, value, subsetting, modulename, base)
		if fullsetting == "core.tooltip.alwayshomefaction" or base == "profile" then
			UpdateZoneFaction(true) -- may change ServerKeyDisplay
		end
	end,
}

-- Activate: called by CoreMain near the end of the load process
-- (expected to be during PLAYER_ENTERING_WORLD or later)
internalResources.Activate = function()
	internalResources.Activate = nil -- only run once
	lib.Active = true

	-- Setup Event handler
	EventFrame = CreateFrame("Frame")
	EventFrame:SetScript("OnEvent", OnEvent)
	EventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
	EventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
	EventFrame:RegisterEvent("MAIL_SHOW")
	EventFrame:RegisterEvent("MAIL_CLOSED")
	EventFrame:RegisterEvent("ZONE_CHANGED")
	EventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
	EventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

	-- Faction resources are handled by both CoreResources and CoreServers
	-- Must be initialized in the correct order
	InitFaction() -- set PlayerFaction, OpposingFaction
	internal.Servers.InitFaction() -- set serverKeys ServerKeyHome, ServerKeyOpposing, ServerKeyNeutral
	internal.Servers.InitServers()
	UpdateZoneFaction() -- set map zone info and flag according to Neutral AH zones;
					-- also calls UpdateCurrentServerKey to update ServerKey and ServerKeyDisplay
					-- sends initial "serverkey" processor message
end

-- SetResource: permits other Core files to set a resource
-- Other Cores/Modules must never modify AucAdvanced.Resources directly (or I may make it a read-only table in future!)
-- CoreServers will set ServerKey resources
internalResources.SetResource = function(key, value)
	lib[key] = value
end

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/CoreResources.lua $", "$Rev: 6664 $")
AucAdvanced.CoreFileCheckOut("CoreResources")
