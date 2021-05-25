--[[
	Auctioneer - iLevel Standard Deviation Statistics module
	Version: 1.13.6636 (SwimmingSeadragon)
	Revision: $Id: iLevel.lua 6636 2021-01-30 13:42:33Z none $
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
if not AucAdvanced then return end

local libType, libName = "Stat", "iLevel"
local lib,parent,private = AucAdvanced.NewModule(libType, libName)
if not lib then return end
local aucPrint,decode,_,_,replicate,_,get,set,default,debugPrint,fill, _TRANS = AucAdvanced.GetModuleLocals()

local select,next,pairs,ipairs,type,unpack,wipe = select,next,pairs,ipairs,type,unpack,wipe
local tonumber,tostring,strsplit,strjoin = tonumber,tostring,strsplit,strjoin
local floor,abs,max = floor,abs,max
local concat = table.concat
local strmatch = strmatch

local Resources = AucAdvanced.Resources
local EquipEncode = AucAdvanced.Const.EquipEncode
local ResolveServerKey = AucAdvanced.ResolveServerKey
local GetServerKeyText = AucAdvanced.GetServerKeyText

local KEEP_NUM_POINTS = 250
local DATABASE_VERSION = 3

-- Constants used when creating a PDF:
local BASE_WEIGHT = 0.2 -- iLevel starts with a lower weight than most other Stat modules
-- Clamping limits for stddev relative to mean
local CLAMP_STDDEV_LOWER = 0.01
local CLAMP_STDDEV_UPPER = 1
-- Adjustments when seen count is very low (in this case, auctionscount)
local LOWSEEN_MINIMUM = 1 -- lowest possible count for a valid PDF
-- Weight taper for low seen count
local TAPER_THRESHOLD = 10 -- seen count at which we stop making adjustments
local TAPER_WEIGHT = .1 -- weight multiplier at LOWSEEN_MINIMUM
local TAPER_SLOPE = (1 - TAPER_WEIGHT) / (TAPER_THRESHOLD - LOWSEEN_MINIMUM)
local TAPER_OFFSET = TAPER_WEIGHT - LOWSEEN_MINIMUM * TAPER_SLOPE
-- StdDev Estimate for low seen count
local ESTIMATE_THRESHOLD = 10
local ESTIMATE_FACTOR = 0.33

local WEAKVALUEMETA = {__mode="v"}
local ZValues = {.063, .126, .189, .253, .319, .385, .454, .525, .598, .675, .756, .842, .935, 1.037, 1.151, 1.282, 1.441, 1.646, 1.962, 20, 20000}

function lib.CommandHandler(command, ...)
	local serverKey = Resources.ServerKey
	local keyText = GetServerKeyText(serverKey)
	if (command == "help") then
		aucPrint(_TRANS('ILVL_Help_SlashHelp1') )--Help for Auctioneer Advanced - iLevel
		local line = AucAdvanced.Config.GetCommandLead(libType, libName)
		aucPrint(line, "help}} - ".._TRANS('ILVL_Help_SlashHelp2') ) -- this iLevel help
		aucPrint(line, "clear}} - ".._TRANS('ILVL_Help_SlashHelp3'):format(keyText) ) --clear current %s iLevel price database
	elseif (command ==_TRANS( 'clear') ) then
		lib.ClearData(serverKey)
	end
end

lib.Processors = {}
function lib.Processors.itemtooltip(callbackType, ...)
	private.ProcessTooltip(...)
end
function lib.Processors.config(callbackType, gui)
	if private.SetupConfigGui then -- only call it once
		private.SetupConfigGui(gui)
	end
end
function lib.Processors.scanstats()
	private.ResetCache()
	private.RepackStats()
end

lib.ScanProcessors = {}
function lib.ScanProcessors.create(operation, itemData, oldData)
	if not get("stat.ilevel.enable") then return end

	-- We're only interested in items with buyouts, and with stack size 1
	local buyout = itemData.buyoutPrice
	if not buyout or buyout == 0 or itemData.stackSize ~= 1 then return end

	-- Get the signature of this item and find it's stats.
	local iLevel, quality, equipPos = itemData.itemLevel, itemData.quality, itemData.equipPos
	if not equipPos then return end
	if equipPos < 1 then return end
	if quality < 1 then return end
	local itemSig = ("%d:%d"):format(equipPos, quality)

	local stats = private.GetUnpackedStats(Resources.ServerKey, itemSig, true) -- read/write
	if not stats[iLevel] then stats[iLevel] = {} end
    local sz = #stats[iLevel]
	stats[iLevel][sz+1] = buyout
end

local BellCurve = AucAdvanced.API.GenerateBellCurve()
-----------------------------------------------------------------------------------
-- The PDF for standard deviation data, standard bell curve
-----------------------------------------------------------------------------------
function lib.GetItemPDF(hyperlink, serverKey)
	local average, mean, _, stddev, variance, count, confidence = lib.GetPrice(hyperlink, serverKey)
	if not (average and stddev and count) or average == 0 or count < LOWSEEN_MINIMUM then
		return nil -- No data, cannot determine pricing
	end

	-- The area of the BellCurve can be used to adjust its weight vs other Stat modules
	-- iLevel is a fallback stat, intended for when other modules have no data
	-- we will start with a reduced weight, so it has less influence than other stats
	local area = BASE_WEIGHT
	if count < TAPER_THRESHOLD then
		-- when seen count is very low, reduce weight
		area = area * (count * TAPER_SLOPE + TAPER_OFFSET)
	end

	-- Extremely large or small values of stddev can cause problems with GetMarketValue
	-- we shall apply limits relative to the mean of the bellcurve (local 'average')
	local clamplower, clampupper = average * CLAMP_STDDEV_LOWER, average * CLAMP_STDDEV_UPPER
	if count < ESTIMATE_THRESHOLD then
		-- We assume that calculated stddev is unreliable at very low seen counts, so we apply a minimum value based on average and count
		-- in particular fixes up the case where count is 1, and stddev is therefore 0
		clamplower = ESTIMATE_FACTOR * average / count
	end
	if stddev < clamplower then
		stddev = clamplower
	elseif stddev > clampupper then
		-- iLevel is particularly prone to producing a very large stddev, due to the diversity of the items in each category
		-- Note that even with this adjustment, 'lower' can still be significantly negative!
		area = area * clampupper / stddev -- as we're hard capping the stddev, reduce weight to compensate
		stddev = clampupper
	end

	local lower, upper = average - 3 * stddev, average + 3 * stddev

	BellCurve:SetParameters(average, stddev, area)
	return BellCurve, lower, upper, area   -- This has a __call metamethod so it's ok
end

-----------------------------------------------------------------------------------

function private.GetCfromZ(Z)
	--C = 0.05*i
	if (not Z) then
		return .05
	end
	if (Z > 10) then
		return .99
	end
	local i = 1
	while Z > ZValues[i] do
		i = i + 1
	end
	if i == 1 then
		return .05
	else
		i = i - 1 + ((Z - ZValues[i-1]) / (ZValues[i] - ZValues[i-1]))
		return i*0.05
	end
end

local pricecache = setmetatable({}, WEAKVALUEMETA)
function private.ResetCache()
	wipe(pricecache)
end

local datapoints_price = {}   -- used temporarily in .GetPrice() to avoid unpacking strings multiple times
local datapoints_stack = {}

function lib.GetPrice(hyperlink, serverKey)
	local average, mean, stdev, variance, count, confidence

	if not get("stat.ilevel.enable") then return end
	local itemSig, iLevel = private.GetItemDetail(hyperlink)
	if not itemSig then return end
	serverKey = ResolveServerKey(serverKey)
	if not serverKey then return end

	local cacheSig = serverKey..itemSig..";"..iLevel
	if pricecache[cacheSig] then
		average, mean, stdev, variance, count, confidence = unpack(pricecache[cacheSig], 1, 6)
		return average, mean, false, stdev, variance, count, confidence
	end

	local stats = private.GetUnpackedStats(serverKey, itemSig) -- read only
	if not stats[iLevel] then return end

	count = #stats[iLevel]
	if (count < 1) then return end

	local total, number = 0, 0
	for i = 1, count do
		local price, stack = strsplit("/", stats[iLevel][i])
		price = tonumber(price) or 0
		stack = tonumber(stack) or 1
		if (stack < 1) then stack = 1 end
		datapoints_price[i] = price
		datapoints_stack[i] = stack
		total = total + price
		number = number + stack
	end
	mean = total / number

	if (count < 2) then return 0,0,0, mean, count end

	variance = 0
	for i = 1, count do
		variance = variance + ((mean - datapoints_price[i]/datapoints_stack[i]) ^ 2);
	end

	variance = variance / count;
	stdev = variance ^ 0.5

	local deviation = 1.5 * stdev
	total = 0	-- recomputing with only data within deviation
	number = 0

	for i = 1, count do
		local price,stack = datapoints_price[i], datapoints_stack[i]
		if abs((price/stack) - mean) < deviation then
			total = total + price
			number = number + stack
		end
	end

	confidence = .01
	if (number > 0) then	-- number<1  will happen if we have e.g. two big clusters: one at 1g and one at 10g
		average = total / number
		confidence = (.15*average)*(number^0.5)/(stdev)
		confidence = private.GetCfromZ(confidence)
	end
	pricecache[cacheSig] = {average, mean, stdev, variance, count, confidence}
	return average, mean, false, stdev, variance, count, confidence
end

function lib.GetPriceColumns()
	return "Average", "Mean", false, "Std Deviation", "Variance", "Count", "Confidence"
end

local array = {}
function lib.GetPriceArray(hyperlink, serverKey)
	if not get("stat.ilevel.enable") then return end
	-- Clean out the old array
	wipe(array)

	-- Get our statistics
	local average, mean, _, stdev, variance, count, confidence = lib.GetPrice(hyperlink, serverKey)

	-- These 3 are the ones that most algorithms will look for
	array.price = average or mean
	array.seen = 0
	array.confidence = confidence
	-- This is additional data
	array.normalized = average
	array.mean = mean
	array.deviation = stdev
	array.variance = variance
	array.processed = count

	-- Return a temporary array. Data in this array is
	-- only valid until this function is called again.
	return array
end

function private.SetupConfigGui(gui)
	private.SetupConfigGui = nil
	local id = gui:AddTab(lib.libName, lib.libType.." Modules")
	--gui:MakeScrollable(id)

	gui:AddHelp(id, "what ilevel stats",
		_TRANS('ILVL_Help_WhatIlevelStats') ,--What are ilevel stats?
		_TRANS('ILVL_Help_WhatIlevelStatsAnswer') )--ilevel stats are the numbers that are generated by the iLevel module consisting of a filtered Standard Deviation calculation of item cost.

	gui:AddHelp(id, "filtered ilevel",
		_TRANS('ILVL_Help_WhatFiltered') ,--What do you mean filtered?
		_TRANS('ILVL_Help_WhatFilteredAnswer') )--Items outside a (1.5*Standard) variance are ignored and assumed to be wrongly priced when calculating the deviation.

	--all options in here will be duplicated in the tooltip frame
	local function addTooltipControls(id)
		gui:AddHelp(id, "what standard deviation",
			_TRANS('ILVL_Help_WhatStdDev') ,--What is a Standard Deviation calculation?
			_TRANS('ILVL_Help_WhatStdDevAnswer') )--In short terms, it is a distance to mean average calculation.

		gui:AddHelp(id, "what normalized",
			_TRANS('ILVL_Help_WhatNormalized') ,--What is the Normalized calculation?
			_TRANS('ILVL_Help_WhatNormalizedAnswer') )--In short terms again, it is the average of those values determined within the standard deviation variance calculation.

		gui:AddHelp(id, "what confidence",
			_TRANS('ILVL_Help_WhatConfidence') ,--What does confidence mean?
			_TRANS('ILVL_Help_WhatConfidenceAnswer') )--Confidence is a value between 0 and 1 that determines the strength of the calculations (higher the better).

		gui:AddHelp(id, "why multiply stack size ilevel",
			_TRANS('ILVL_Help_WhyStackSize') ,--Why have the option to multiply by stack size?
			_TRANS('ILVL_Help_WhyStackSizeAnswer') )--The original Stat-ilevel multiplied by the stack size of the item, but some like dealing on a per-item basis.

		gui:AddControl(id, "Header",     0,   _TRANS('ILVL_Interface_IlevelOptions') )--ilevel options
		gui:AddControl(id, "Note",       0, 1, nil, nil, " ")
		gui:AddControl(id, "Checkbox",   0, 1, "stat.ilevel.enable", _TRANS('ILVL_Interface_EnableILevelStats') )--Enable iLevel Stats
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_EnableILevelStats') )--Allow iLevel to gather and return price data
		gui:AddControl(id, "Note",       0, 1, nil, nil, " ")

		gui:AddControl(id, "Checkbox",   0, 4, "stat.ilevel.tooltip", _TRANS('ILVL_Interface_ShowiLevel') )--Show iLevel stats in the tooltips?
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_ShowiLevel') )--Toggle display of stats from the iLevel module on or off
		gui:AddControl(id, "Checkbox",   0, 6, "stat.ilevel.mean", _TRANS('ILVL_Interface_DisplayMean') )--Display Mean
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_DisplayMean') )--Toggle display of 'Mean' calculation in tooltips on or off
		gui:AddControl(id, "Checkbox",   0, 6, "stat.ilevel.normal", _TRANS('ILVL_Interface_DisplayNormalized') )--Display Normalized'
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_DisplayNormalized') )--Toggle display of \'Normalized\' calculation in tooltips on or off
		gui:AddControl(id, "Checkbox",   0, 6, "stat.ilevel.stdev", _TRANS('ILVL_Interface_DisplayStdDeviation') )--Display Standard Deviation
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_DisplayStdDeviation') )--Toggle display of \'Standard Deviation\' calculation in tooltips on or off
		gui:AddControl(id, "Checkbox",   0, 6, "stat.ilevel.confid", _TRANS('ILVL_Interface_DisplayConfidence') )--Display Confidence
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_DisplayConfidence') )--Toggle display of \'Confidence\' calculation in tooltips on or off
		gui:AddControl(id, "Note",       0, 1, nil, nil, " ")
		gui:AddControl(id, "Checkbox",   0, 4, "stat.ilevel.quantmul", _TRANS('ILVL_Interface_MultiplyStack') )--Multiply by Stack Size
		gui:AddTip(id, _TRANS('ILVL_HelpTooltip_MultiplyStack') )--Multiplies by current stack size if on
		gui:AddControl(id, "Note",       0, 1, nil, nil, " ")
	end
	--This is the Tooltip tab provided by Auctioneer so all tooltip configuration is in one place
	local tooltipID = AucAdvanced.Settings.Gui.tooltipID

	--now we create a duplicate of these in the tooltip frame
	addTooltipControls(id)
	if tooltipID then addTooltipControls(tooltipID) end
end

function private.ProcessTooltip(tooltip, hyperlink, serverKey, quantity, decoded, additional, order)
	if not get("stat.ilevel.tooltip") then return end

	if not quantity or quantity < 1 then quantity = 1 end
	if not get("stat.ilevel.quantmul") then quantity = 1 end
	local average, mean, _, stdev, var, count, confidence = lib.GetPrice(hyperlink, serverKey)

	if (mean and mean > 0) then
		tooltip:SetColor(0.3, 0.9, 0.8)

		tooltip:AddLine(_TRANS('ILVL_Tooltip_iLevelPrices'):format(count) )--iLevel prices (%s points):

		if get("stat.ilevel.mean") then
			tooltip:AddLine("  ".._TRANS('ILVL_Tooltip_MeanPrice') , mean*quantity)--Mean price
		end
		if (average and average > 0) then
			if get("stat.ilevel.normal") then
				tooltip:AddLine("  ".._TRANS('ILVL_Tooltip_Normalized') , average*quantity)--Normalized
				if (quantity > 1) then
					tooltip:AddLine("  ".._TRANS('ILVL_Tooltip_Individually') , average)--(or individually)
				end
			end
			if get("stat.ilevel.stdev") then
				tooltip:AddLine("  ".._TRANS('ILVL_Tooltip_StdDeviation') , stdev*quantity)--Std Deviation
                if (quantity > 1) then
                    tooltip:AddLine("  ".._TRANS('ILVL_Tooltip_Individually') , stdev)--(or individually)
                end

			end
			if get("stat.ilevel.confid") then
				tooltip:AddLine("  ".._TRANS('ILVL_Tooltip_Confidence'):format((floor(confidence*1000))/1000) )--Confidence: %s
			end
		end
	end
end

function lib.OnLoad(addon)
	default("stat.ilevel.tooltip", false)
	default("stat.ilevel.mean", false)
	default("stat.ilevel.normal", false)
	default("stat.ilevel.stdev", true)
	default("stat.ilevel.confid", true)
	default("stat.ilevel.quantmul", true)
	default("stat.ilevel.enable", true)
	if private.InitData then private.InitData() end
end

function lib.OnUnload()
	private.OnLogout()
end

function lib.ClearItem(hyperlink, serverKey)
	serverKey = ResolveServerKey(serverKey)
	if not serverKey then return end
	local itemSig, iLevel, equipPos, quality = private.GetItemDetail(hyperlink)
	if not itemSig then return end

	local stats = private.GetUnpackedStats(serverKey, itemSig, true)
	if stats[iLevel] then
		stats[iLevel] = nil
		private.RepackStats()
		private.ResetCache()
		local keyText = GetServerKeyText(serverKey)
		aucPrint(_TRANS('ILVL_Interface_ClearingItems'):format(iLevel, quality, equipPos, keyText))--Stat-iLevel: clearing data for iLevel=%d/quality=%d/equip=%d items for {{%s}}
		return
	end
	aucPrint(_TRANS('ILVL_Interface_ItemNotFound') )--Stat-iLevel: item is not in database
end

--[[ Database Management functions ]]--

local ILRealmData
local unpacked, updated = {}, {}

function private.InitData()
	private.InitData = nil
	if private.UpgradeDB then private.UpgradeDB() end
	ILRealmData = AucAdvancedStat_iLevelData.RealmData
end

function private.OnLogout()
	private.RepackStats()
	for serverKey, data in pairs(ILRealmData) do
		if not next(data) then
			ILRealmData[serverKey] = nil
		end
	end
end

function private.UpgradeDB()
	private.UpgradeDB = nil

	local saved = AucAdvancedStat_iLevelData
	if type(saved) == "table" and type(saved.RealmData) == "table" and saved.Version == DATABASE_VERSION then
		saved.OldRealmData = nil -- delete any obsolete data - this line can be removed after some time
		return
	end

	AucAdvancedStat_iLevelData = {
		Version = DATABASE_VERSION,
		RealmData = {}
	}
end

function lib.ClearData(serverKey)
	private.ResetCache()
	if AucAdvanced.API.IsKeyword(serverKey, "ALL") then
		wipe(ILRealmData)
		wipe(unpacked)
		wipe(updated)
		aucPrint(_TRANS('ILVL_Help_SlashHelp5').." {{".._TRANS("ADV_Interface_AllRealms").."}}") --Clearing iLevel stats for // All realms
	else
		serverKey = ResolveServerKey(serverKey)
		if ILRealmData[serverKey] then
			ILRealmData[serverKey] = nil
			unpacked[serverKey] = nil
			-- 'updated' may contain orphaned entries - these will be cleaned up in next RepackStats
			local keyText = GetServerKeyText(serverKey)
			aucPrint(_TRANS('ILVL_Help_SlashHelp5').." {{"..keyText.."}}") --Clearing iLevel stats for
		end
	end
end

--[[
itemSig, iLevel, equipPos, quality = GetItemDetail(hyperlink)
--]]
function private.GetItemDetail(hyperlink)
	if type(hyperlink) ~= "string" then return end
	if not hyperlink:match("item:%d") then return end

	local _,_, quality, iLevel, _,_,_,_, equipPos = GetItemInfo(hyperlink)
	if not quality or quality < 1 then return end
	equipPos = EquipEncode[equipPos]
	if not equipPos then return end
	local itemSig = ("%d:%d"):format(equipPos, quality)

	return itemSig, iLevel, equipPos, quality
end

--[[
stats = GetUnpackedStats (serverKey, itemSig, writing)
Obtain a cached data table for itemSig in serverKey's data.
From DataBase Version 2.0, serverKey should be new style, and should have been validated by caller
Set writing to true if you intend to change the data
Caution: if you set 'writing' to true, RepackStats() must be called before the end of the session to save the changes
--]]
function private.GetUnpackedStats(serverKey, itemSig, writing)
	local stats = unpacked[serverKey] and unpacked[serverKey][itemSig]
	if stats then
		if writing then
			updated[stats] = true
		end
		return stats
	end

	local realmdata = ILRealmData[serverKey]
	if not realmdata then
		realmdata = {}
		ILRealmData[serverKey] = realmdata
	end

	stats = private.UnpackStats(realmdata, itemSig)

	if not unpacked[serverKey] then unpacked[serverKey] = setmetatable({}, WEAKVALUEMETA) end
	unpacked[serverKey][itemSig] = stats
	if writing then
		updated[stats] = true
	end

	return stats
end

--[[
RepackStats()
Write any changed tables in the unpacked cache back to ILRealmData
--]]
function private.RepackStats()
	if not next(updated) then return end -- bail out if no updated entries
	for serverKey, realmData in pairs(unpacked) do
		for item, stats in pairs(realmData) do
			if updated[stats] then
				local packed = private.PackStats(stats)
				if packed == "" then
					ILRealmData[serverKey][item] = nil -- delete empty entries from the database
				else
					ILRealmData[serverKey][item] = packed
				end
			end
		end
	end
	wipe(updated)
end

-- GetServerKeyList
function lib.GetServerKeyList()
	if not ILRealmData then return end
	local list = {}
	for serverKey in pairs(ILRealmData) do
		tinsert(list, serverKey)
	end
	return list
end

-- ChangeServerKey
function lib.ChangeServerKey(oldKey, newKey)
	if not ILRealmData then return end
	local oldData = ILRealmData[oldKey]
	ILRealmData[oldKey] = nil
	if oldData and newKey then
		ILRealmData[newKey] = oldData
		-- if there was data for newKey then it will be discarded (simplest implementation)
	end
end

--[[ Subfunctions ]]--

function private.UnpackStatIter(data, ...)
	local c = select("#", ...)
	local v
	for i = 1, c do
		v = select(i, ...)
		local property, info = strsplit(":", v)
		property = tonumber(property) or property
		if (property and info) then
			local t= {strsplit(";", info)}
			for k,v in ipairs(t) do
				t[k] = tonumber(v) or v
			end
			data[property] = t
		end
	end
end
function private.UnpackStats(data, item)
	local stats = {}
	if (data and data[item]) then
		private.UnpackStatIter(stats, strsplit(",", data[item]))
	end
	return stats
end
local tmp={}
function private.PackStats(data)
	local ntmp=0
	for property, info in pairs(data) do
		ntmp=ntmp+1
		local n = max(1, #info - KEEP_NUM_POINTS + 1)
        tmp[ntmp] = property..":"..concat(info, ";", n)
	end
	return concat(tmp, ",", 1, ntmp)
end

AucAdvanced.RegisterRevision("$URL: Auc-Stat-iLevel/iLevel.lua $", "$Rev: 6636 $")
