--[[
	Auctioneer
	Version: 1.13.6664 (SwimmingSeadragon)
	Revision: $Id: CoreServers.lua 6664 2021-01-30 13:42:33Z none $
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
	Maintain a database of known servers and serverKeys

	Realm names can be in a compact form, with certain characters (currently spaces and dashes) stripped out.
	(Standard Realm names can easily be converted to compact form by gsub("[ %-]", "") -- note the space character after the first square bracket)

	Maintain a lookup table to allow Compact form to be converted to Standard form

	Saved variable: AucAdvancedServers
		ExpandedNames {CompactName = ExpandedName}, entries only exist where ExpandedName is different from CompactName
		KnownRealms {CompactName = {login = timestamp, serverKey = timestamp, ...}}

	Should the user deletes the AucAdvanced save file (including all serverKey data) but not the Stat save files,
	we should attempt to match serverKey with the Stat files, so as to avoid leaving orphaned data in the Stat save files.

--]]

local AucAdvanced = AucAdvanced
if not AucAdvanced then return end
AucAdvanced.CoreFileCheckIn("CoreServers")
local coremodule, internalLib, _, internal = AucAdvanced.GetCoreModule("CoreServers", "Servers", nil, nil, "CoreServers") -- needs access to the base internal table
if not (coremodule and internal) then return end

local Const = AucAdvanced.Const
local Resources = AucAdvanced.Resources

local strsplit = strsplit

local FullRealmName = Const.PlayerRealm
local CompactRealmName -- to be filled in below using MakeCompact()

local ExpandedNames, KnownRealms -- local references to saved variables

local SessionRealms = {} -- Table containing various data related to each realm
local SessionServerKeys = {} -- lookup to validate known serverKeys; provides CompactRealmName for use in SessionRealms
local SessionResolveRealms = {} -- lookup cache to convert various strings into valid CompactRealmNames (for use in SessionRealms)

local localizedfactions = {
	-- the following entries are placeholders
	["Alliance"] = "Alliance",
	["Horde"] = "Horde",
	["Neutral"] = "Neutral",
}
local lookupfactionkeys = {
	["Home"] = "Home",
	["Opposing"] = "Opposing",
	["Neutral"] = "Neutral",
	-- Alliance and Horde entries to be filled in by InitFaction, when known
}

-- Generate compact name
-- Current version: strip out all space and hyphen characters
local function MakeCompact(realm)
	-- for now assume realm is a valid realm name
	return realm:gsub("[ %-]", "")
end
CompactRealmName = MakeCompact(FullRealmName)
Const.CompactRealm = CompactRealmName -- install into Const table

-- Generate serverKey
local function MakeServerKey(realm, faction)
	-- for now assume realm is compact and faction is one of "Alliance", "Horde" or "Neutral"
	return realm.."_"..faction
end

-- notify modules (primarily Stats) that a serverKey has been renamed
-- modules should move oldKey to newKey in their database; if newKey is nil, modules should just delete oldKey
-- if a module has data for both oldKey and newKey it should either merge them, or archive or discard one set
local function SendServerKeyChange(oldKey, newKey)
	local modules = AucAdvanced.GetAllModules("ChangeServerKey")
	for _, module in ipairs(modules) do
		module.ChangeServerKey(oldKey, newKey)
	end
end

-- helper function: compile a lookup table of serverKeys known to other modules
local function GetModuleServerKeys()
	local modules = AucAdvanced.GetAllModules("GetServerKeyList")
	local compile = {}
	for _, module in ipairs(modules) do
		local modulelist = module.GetServerKeyList()
		if modulelist then
			for _, key in ipairs(modulelist) do
				compile[key] = (compile[key] or 0) + 1
			end
		end
	end
	return compile
end


-- Install session serverKeys into Resources table
-- Called internally by CoreResources after faction Resources have been generated
function internalLib.InitFaction()
	internalLib.InitFaction = nil
	internal.Resources.SetResource("ServerKeyHome", MakeServerKey(CompactRealmName, Resources.PlayerFaction))
	internal.Resources.SetResource("ServerKeyOpposing", MakeServerKey(CompactRealmName, Resources.OpposingFaction))
	internal.Resources.SetResource("ServerKeyNeutral", MakeServerKey(CompactRealmName, "Neutral"))

	lookupfactionkeys[Resources.PlayerFaction] = "Home"
	lookupfactionkeys[Resources.OpposingFaction] = "Opposing"
end

-- Update current serverKey in the Resources table
-- This is called internally by CoreResources
-- This is intended to handle serverKey switching when at a Neutral AH, such as Booty Bay
function internalLib.UpdateCurrentServerKey()
	-- Resources.ServerKey is used by CoreScan and other modules to determine which serverKey to write new data to
	if Resources.IsNeutralZone then
		internal.Resources.SetResource("ServerKey", Resources.ServerKeyNeutral)

		-- Ensure Neutral serverKey is recorded in the Session tables
		SessionRealms[CompactRealmName].Neutral = Resources.ServerKeyNeutral
		SessionServerKeys[Resources.ServerKeyNeutral] = CompactRealmName
	else
		internal.Resources.SetResource("ServerKey", Resources.ServerKeyHome)
	end

	-- Resources.ServerKeyDisplay may be used by tooltips
	-- ### todo: recreate setting to show home serverKey in tooltip when in neutral zones - only showing neutral serverKey when Neutral AH is open
	if Resources.DisplayFaction == "Neutral" then
		internal.Resources.SetResource("ServerKeyDisplay", Resources.ServerKeyNeutral)
	else
		internal.Resources.SetResource("ServerKeyDisplay", Resources.ServerKeyHome)
	end

	-- ### todo: ServerKeyCurrent has been deprecated, hunt for any remaining instances and convert to ServerKey or ServerKeyDisplay as appropriate
	internal.Resources.SetResource("ServerKeyCurrent", Resources.ServerKey)
end

-- ### todo: expand to check all old serverKeys, and to delete AucAdvancedServers.OldServerKeys when no longer needed
local function CheckOldServerKeys(realm)
	-- realm is CompactRealmName
	local OldServerKeys = AucAdvancedServers.OldServerKeys
	if not OldServerKeys then return end
	local timestamp = OldServerKeys[realm]
	if not timestamp then return end
	-- timestamp exists for this realmname
	local data = KnownRealms[realm]
	if not data then
		data = {}
		KnownRealms[realm] = data
	end
	data.Login = timestamp
	-- we shall assume this is also a timestamp for 'Home' (old version did not record AH Open timestamps so we need to fake one)
	data[Resources.PlayerFaction] = timestamp

	-- we shall also assume there are Stats associated with this old-style serverKey
	local newKey = MakeServerKey(realm, Resources.PlayerFaction)
	SendServerKeyChange(realm, newKey) -- instruct all Stat modules to change to the new serverKey, if the old key exists
	OldServerKeys[realm] = nil
end

-- Called during Resources.Activate (during or after "PLAYER_ENTERING_WORLD")
-- Note we require faction info to be available
function internalLib.InitServers()
	internalLib.InitServers = nil -- no longer needed after activation

	-- Check and update saved variables

	if FullRealmName ~= CompactRealmName then
		ExpandedNames[CompactRealmName] = FullRealmName
		AucAdvancedServers.ExpandedNames = ExpandedNames -- attach to save structure, if not already attached
	end

	local realmdata = KnownRealms[CompactRealmName]
	if not realmdata then
		realmdata = {}
		KnownRealms[CompactRealmName] = realmdata

		CheckOldServerKeys(CompactRealmName)
	end
	realmdata.Login = time()

	local moduleKeys = GetModuleServerKeys() -- may be empty table
	-- ### todo: install moduleKeys into SessionRealms below, (HomeData, OpposingData, NeutralData ?)
	-- ### caution: be aware moduleKeys may contain old-style (or otherwise invalid) serverKeys

	-- Build SessionRealms and SessionServerKeys tables
	local homefaction, oppfaction = Resources.PlayerFaction, Resources.OpposingFaction
	for realmname, realmsavedata in pairs(KnownRealms) do
		local realmdata = {}
		for keydata in pairs(realmsavedata) do
			if keydata == homefaction then
				local serverKey = MakeServerKey(realmname, "Home")
				realmdata.Home = serverKey
				SessionServerKeys[serverKey] = realmname
			elseif keydata == oppfaction then
				local serverKey = MakeServerKey(realmname, "Opposing")
				realmdata.Opposing = serverKey
				SessionServerKeys[serverKey] = realmname
			elseif keydata == "Neutral" then
				local serverKey = MakeServerKey(realmname, "Neutral")
				realmdata.Neutral = serverKey
				SessionServerKeys[serverKey] = realmname
			elseif keydata ~= "Login" then
				error("Unknown key "..tostring(keydata))
			end
		end
		SessionRealms[realmname] = realmdata
	end

	-- Force current realm Home serverKey to always be in session tables
	SessionRealms[CompactRealmName].Home = Resources.ServerKeyHome
	SessionServerKeys[Resources.ServerKeyHome] = CompactRealmName

	-- Build SessionResolveRealms - this will drive ResolveServerKey (below)
	-- Install all known realms and serverKeys
	for realmname in pairs(SessionRealms) do
		SessionResolveRealms[realmname] = realmname
		SessionResolveRealms[realmname:lower()] = realmname
	end
	for serverKey, realmname in pairs(SessionServerKeys) do
		SessionResolveRealms[serverKey] = realmname
	end
	for realmname, expandedname in pairs(ExpandedNames) do
		SessionResolveRealms[expandedname] = realmname
	end
end


local function OnLoadRunOnce()
	OnLoadRunOnce = nil

	-- Saved Variables
	local saved = AucAdvancedServers
	if not saved or saved.Version ~= 2 then
		local old = saved
		saved = {
			KnownRealms = {},
			Version = 2,
			Timestamp = time(),
		}
		if old and old.Version == 1 then
			saved.ExpandedNames = old.ExpandedNames -- ExpandedNames works the same in Version 2 as in Version 1
			saved.OldServerKeys = old.KnownServerKeys -- Used to help convert stats from old serverKey to new
		end
		AucAdvancedServers = saved
	end

	ExpandedNames = saved.ExpandedNames or {}
	KnownRealms = saved.KnownRealms

	local L = AucAdvanced.localizations
	localizedfactions.Alliance = L"ADV_Interface_FactionAlliance"
	localizedfactions.Horde = L"ADV_Interface_FactionHorde"
	localizedfactions.Neutral = L"ADV_Interface_FactionNeutral"

end
function coremodule.OnLoad(addon)
	if addon == "auc-advanced" and OnLoadRunOnce then
		OnLoadRunOnce()
	end
end

coremodule.Processors = {
	auctionopen = function()
		-- record timestamp for current serverKey
		KnownRealms[CompactRealmName][Resources.CurrentFaction] = time()
	end,
}

--[[ Export functions ]]--

local function ResolveServerKey(realm, faction)
	local factionkey, realmdata
	if not (realm or faction) then
		return Resources.ServerKey -- default
	end

	if faction then
		factionkey = lookupfactionkeys[faction] -- convert to one of "Home", "Opposing", "Neutral"
		if not factionkey then
			return nil, "InvalidFaction"
		end
	else
		-- special case: see if realm is a valid serverKey, in which case just return it
		if SessionServerKeys[realm] then
			return realm
		end

		factionkey = Resources.IsNeutralZone and "Neutral" or "Home" -- default faction
	end

	if not realm then
		-- use current realm
		return SessionRealms[CompactRealmName][factionkey] -- may be nil
	end

	local realmkey = SessionResolveRealms[realm]
	if realmkey then
		realmdata = SessionRealms[realmkey]
		if realmdata then -- ### this should always exist, consider reporting if this fails...
			return realmdata[factionkey] -- may be nil
		end
	end

	-- try string modifications on realm to see if we can resolve a previously known realmname
	local tryrealm = MakeCompact(realm)
	realmkey = SessionResolveRealms[tryrealm]
	if realmkey then
		SessionResolveRealms[realm] = tryrealm
		realmdata = SessionRealms[realmkey]
		if realmdata then
			return realmdata[factionkey]
		end
	end
	tryrealm = tryrealm:lower()
	realmkey = SessionResolveRealms[tryrealm]
	if realmkey then
		SessionResolveRealms[realm] = tryrealm
		realmdata = SessionRealms[realmkey]
		if realmdata then
			return realmdata[factionkey]
		end
	end

end

local function GetServerKeyList(useTable)
	local list
	if useTable then
		list = useTable
		wipe(list)
	else
		list = {}
	end

	for key in pairs(SessionServerKeys) do
		tinsert(list, key)
	end

	list:sort()

	return list
end

local function IsKnownServerKey(testKey)
	if SessionServerKeys[testKey] then
		return true
	else
		return false
	end
end

local cacheNeutralServerKeys = {}
local function IsNeutralServerKey(testKey)
	local test = cacheNeutralServerKeys[testKey]
	if test ~= nil then return test end

	if type(testKey) ~= "string" then return end
	local realm, faction = strsplit("_", testKey, 2)
	test = localizedfactions[faction]
	if not test then return end

	test = faction == "Neutral"
	cacheNeutralServerKeys[testKey] = test
	return test
end

local function GetRealmList()
	-- ### not implemented
end

local function GetExpandedRealmName(realmName)
	return ExpandedNames[realmName] or realmName
end

local function GetLocalFactionName(factionName)
	return localizedfactions[factionName]
end

local function SplitServerKey(serverKey)
	if type(serverKey) ~= "string" then return end
	local realm, faction = strsplit("_", serverKey, 2)
	local locfaction = localizedfactions[faction]
	-- very basic validation - we see if it looks like a serverKey, but do not check if it is actually Known
	if realm == "" or not locfaction then
		return
	end
	local exprealm = GetExpandedRealmName(realm) or realm

	return realm, faction, exprealm, locfaction
end

local function GetServerKeyText(serverKey)
	local _, _, realmname, factionname = SplitServerKey(serverKey)
	if not factionname then return end
	return realmname.." - "..factionname
end



--[[ Exports ]]--

-- serverKey = AucAdvanced.ResolveServerKey(realm, faction)
-- attempt to find a valid serverKey from provided realm and faction. Returns nil if not known
-- calling with:
--	nil, nil - returns current serverKey
--	realm, nil - returns serverKey based on specified realm and current map zone (neutral or home)
--	nil, faction - returns serverKey based on current realm and specified faction
--	serverKey, nil - returns that serverKey, if it is a known one
-- Valid realm is the name of any known server (i.e. has been previously logged into), or a string which can be resolved to a valid name
-- Valid faction can be nil, "Alliance", "Horde", "Neutral", "Home", "Opposing"
AucAdvanced.ResolveServerKey = ResolveServerKey

-- list = AucAdvanced.GetServerKeyList([useTable])
-- returns list of serverKeys known by the CoreServers
-- if useTable is provided it will be wiped and then populated with the list
-- if useTable is not provided, caller must not store or modify the returned table object
AucAdvanced.GetServerKeyList = GetServerKeyList

-- boolean = AucAdvanced.IsKnownServerKey(serverKey)
AucAdvanced.IsKnownServerKey = IsKnownServerKey

-- boolean = AucAdvanced.IsNeutralServerKey(serverKey)
-- Intended to be used with AucAdvanced.Post.GetDepositCost, which is called very frequently in Auctioneer modules,
-- Therefore it caches results for faster response after the first
AucAdvanced.IsNeutralServerKey = IsNeutralServerKey

-- list = AucAdvanced.GetRealmList()
-- ### not implemented
AucAdvanced.GetRealmList = GetRealmList

-- text = AucAdvanced.GetExpandedRealmName(realmName)
-- attempt to find expanded realm name from a compact realm name. If not found, just returns realmName
AucAdvanced.GetExpandedRealmName = GetExpandedRealmName

-- text = AucAdvanced.GetLocalFactionName(faction)
-- faction may be "Alliance", "Horde" or "Neutral"
-- returns localized strings for these values (note the localizer defaults to enUS if the localization is missing)
AucAdvanced.GetLocalFactionName = GetLocalFactionName


-- compactrealm, faction, expandedrealm, localizedfaction = AucAdvanced.SplitServerKey(serverKey)
-- splits a serverKey into realm and faction parts, also provides expanded realm name and localized faction name
-- caution: does not confirm the serverKey is 'known', just that it has the format of a serverKey
AucAdvanced.SplitServerKey = SplitServerKey

-- text = AucAdvanced.GetServerKeyText(serverKey)
-- return printable text version of serverKey, or nil if not a valid serverKey
-- caution: does not confirm the serverKey is 'known', just that it has the format of a serverKey
AucAdvanced.GetServerKeyText = GetServerKeyText

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/CoreServers.lua $", "$Rev: 6664 $")
AucAdvanced.CoreFileCheckOut("CoreServers")
