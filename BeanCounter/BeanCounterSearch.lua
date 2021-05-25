--[[
	Auctioneer Addon for World of Warcraft(tm).
	Version: 1.13.6609 (SwimmingSeadragon)
	Revision: $Id: BeanCounterSearch.lua 6609 2021-01-30 13:42:33Z none $

	BeanCounterSearch - Search routines for BeanCounter data
	URL: http://auctioneeraddon.com/

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
		since that is it's designated purpose as per:
		http://www.fsf.org/licensing/licenses/gpl-faq.html#InterpreterIncompat
]]
LibStub("LibRevision"):Set("$URL: BeanCounter/BeanCounterSearch.lua $","$Rev: 6609 $","5.1.DEV.", 'auctioneer', 'libs')

local lib = BeanCounter
local private, print, get, set, _BC = lib.getLocals()

local ipairs,pairs,select,type,next = ipairs,pairs,select,type,next
local tinsert = tinsert
local tonumber,tostring = tonumber,tostring
local abs = abs
local strsplit = strsplit

local function debugPrint(...)
    if get("util.beancounter.debugSearch") then
        private.debugPrint("BeanCounterSearch",...)
    end
end


local data = {}
local style = {}
local temp ={}
local tbl = {}


--This is all handled by ITEMIDS need to remove/rename this to be a utility to convert text searches to itemID searches
function private.startSearch(itemName, settings, queryReturn, count, itemTexture) --queryReturn is passed by the externalsearch routine, when an addon wants to see what data BeanCounter knows
	--Run the compression function once per session, use first search as trigger

	if not itemName then return end
	if not settings then settings = private.getCheckboxSettings() end

	tbl = {}
	for itemKey, data in pairs(BeanCounterDBNames) do
		if data:lower():find(itemName:lower(), 1, true)  then
			if settings.exact and private.frame.searchBox:GetText() ~= "" then --if the search field is blank do not exact check
				local _, name = strsplit(";", data)
				if itemName:lower() == name:lower() then
					local itemID, suffix = strsplit(":", itemKey)--Create a list of itemIDs that match the search text
					settings.suffix = suffix -- Store Suffix used to later filter unwated results from the itemID search
					tbl[itemID] = itemID --Since its possible to have the same itemID returned multiple times this will only allow one instance to be recorded
					break
				end
			else
				local itemID = strsplit(":", itemKey)--Create a list of itemIDs that match the search text
				tbl[itemID] = itemID --Since its possible to have the same itemID returned multiple times this will only allow one instance to be recorded
			end
		end
	end

	if queryReturn then --need to return the ItemID results to calling function
		return private.searchByItemID(tbl, settings, queryReturn, count, itemTexture, itemName)
	else
		--get the itemTexture for display in the drop box
		for i, data in pairs(BeanCounterDBNames) do
			local _, name = strsplit(";", data)
			if name:lower() == itemName:lower() then
				local itemID = strsplit(":", i) or ""
				_, itemTexture = private.getItemInfo(itemID, "name")
				break
			end
		end
		private.searchByItemID(tbl, settings, queryReturn, count, itemTexture, itemName)
	end
end


function private.searchByItemID(id, settings, queryReturn, count, itemTexture, classic)
	if not id then return end
	if not settings then settings = private.getCheckboxSettings() end
	if not count then count = get("numberofdisplayedsearchs") end --count determines how many results we show or display High # ~to display all

	tbl = {}
	if type(id) == "table" then --we can search for a sinlge itemID or an array of itemIDs
		for i,v in pairs(id)do
			tinsert(tbl, tostring(v))
		end
	else
		tbl[1] = tostring(id)
	end

	data = {}
	style = {}

	local profit, low, high, serverName, playerName
	--serverName and playerName are used as part of our cache ID string
	if settings.servers and settings.servers[1] then
		serverName = settings.servers[1]
	else
		serverName = GetRealmName()
	end
	if settings.selectbox and settings.selectbox[2] then
		playerName = settings.selectbox[2]
	else
		playerName = "server"
	end

	--check if we have a cache of this search
	--[[ temporarily disabled
	local cached = private.checkSearchCache(classic or tbl[1], serverName, playerName)
	if cached then
		data = cached
	else
		data = private.searchServerData(serverName, data, tbl, settings)
		--format raw into displayed data, the cached version is already in this format
		data = private.formatServerData(data, settings)
	end

	--add item to cache
	if not cached then
		private.addSearchCache(classic or tbl[1], data, serverName, playerName)
	end
	--]] -- end temp disabled code, replacement below
	data = private.searchServerData(serverName, data, tbl, settings)
	data = private.formatServerData(data, settings)
	-- end replacement


	--If query return
	if queryReturn then --this lets us know it was not an external addon asking for beancounter data
		return data --All results are now returned, calling addons can filter
	end

	--if BeanCounters frame is not visible then store till we are and cease processing
	if not private.frame:IsVisible() then
		private.storedQuery = id
		return
	end

	--store profit for this item, need to do this before we reduce number of results for display
	local player = private.frame.SelectBoxSetting[2]
	if get("util.beancounter.ButtonuseDateCheck") and (settings.dateFilterLow or settings.dateFilterHigh) then
		profit, low, high = lib.API.getAHProfit(player, data, settings.dateFilterLow, settings.dateFilterHigh)
	else
		profit, low, high = lib.API.getAHProfit(player, data)
	end

	--filter by dates
	if settings.dateFilterLow or settings.dateFilterHigh then
		data = private.filterbyDate(data, settings.dateFilterLow, settings.dateFilterHigh)
	end
	--reduce results to the latest XXXX ammount based on how many user wants displayed
	if #data > count then
		data = private.reduceSize(data, count)
	end

	style = private.styleServerData(data) --create a style sheet for this data

	--Adds itemtexture to display box and if possible the gain/loss on the item
	if itemTexture then
		private.frame.icon:SetNormalTexture(itemTexture)
	else
		private.frame.icon:SetNormalTexture(nil)
	end

	--display profit for the search term
	if profit then
		local change = "|CFF33FF33Gained"
		if profit < 0 then change = "|CFFFF3333Lost" profit = abs(profit) end-- if profit negative  ABS to keep tiplib from missrepresenting #
		profit = private.tooltip:Coins(profit)
		private.frame.slot.help:SetTextColor(.8, .5, 1)
		private.frame.slot.help:SetText(change..(" %s from %s to %s"):format(profit or "", date("%x", low) or "", date("%x", high) or ""))
		--set date filter box only if user is not using date filtering
		if not get("util.beancounter.ButtonuseDateCheck") then
			private.lowerDateBox:SetDate(low)
			private.upperDateBox:SetDate(high)
		end
	else
		private.frame.slot.help:SetTextColor(1, 0.8, 0)
		private.frame.slot.help:SetText(_BC('HelpGuiItemBox')) --"Drop item into box to search."
	end

	private.frame.resultlist.sheet:SetData(data, style) --Set the GUI scrollsheet
	return data, style
end

--Helper functions for the Search
function private.searchServerData(serverName, data, tbl, settings)
	local server = BeanCounterDB[serverName]
	if not server then return data end -- return data table unchanged

	--Retrives all matching results
	for i in pairs(server) do
		--get faction for player i out of the BeanCounterDBSettings table
		local faction = BeanCounterDBSettings[serverName][i]["faction"] or "unknown"
		if settings.selectbox[2] == "alliance" and faction:lower() ~= settings.selectbox[2] then
			--If looking for alliance and player is not alliance fall into this null
		elseif settings.selectbox[2] == "horde" and faction:lower() ~= settings.selectbox[2] then
			--If looking for horde and player is not horde fall into this null
		elseif (settings.selectbox[2] ~= "server" and settings.selectbox[2] ~= "alliance" and settings.selectbox[2] ~= "horde" and settings.selectbox[2] ~= "neutral") and i ~= settings.selectbox[2] then
			--If we are not doing a whole server search and the chosen search player is not "i" then we fall into this null
			--otherwise we search the server or toon as normal
		else
			--flag on how we handle neutral AH    nil = no filter  1 = remove neutral AH   2 = remove NON neutral
			local filterNeutral = 1 --by default HIDE neutral trxns
			if settings.neutral then filterNeutral = nil end --GUI check to display neutral trxn over ridden by select box
			if settings.selectbox[2] == "neutral" then filterNeutral = 2 end
			for _, id in pairs(tbl) do
				if settings.auction and server[i]["completedAuctions"][id] and filterNeutral ~= 2 then
					data = private.searchDB(data, server, i, "completedAuctions", id)
				end
				if settings.failedauction and server[i]["failedAuctions"][id] and filterNeutral ~= 2 then
					data = private.searchDB(data, server, i, "failedAuctions", id)
				end
				if settings.bid and server[i]["completedBidsBuyouts"][id] and filterNeutral ~= 2 then
					data =  private.searchDB(data, server, i, "completedBidsBuyouts", id)
				end
				if settings.failedbid and server[i]["failedBids"][id] and filterNeutral ~= 2 then
					data = private.searchDB(data, server, i, "failedBids", id)
				end
				--neutral AH handling
				if settings.auction and server[i]["completedAuctionsNeutral"][id] and filterNeutral ~= 1 then
					data = private.searchDB(data, server, i, "completedAuctionsNeutral", id)
				end
				if settings.failedauction and server[i]["failedAuctionsNeutral"][id] and filterNeutral ~= 1 then
					data = private.searchDB(data, server, i, "failedAuctionsNeutral", id)
				end
				if settings.bid and  server[i]["completedBidsBuyoutsNeutral"][id] and filterNeutral ~= 1 then
					data =  private.searchDB(data, server, i, "completedBidsBuyoutsNeutral", id)
				end
				if settings.failedbid and server[i]["failedBidsNeutral"][id] and filterNeutral ~= 1 then
					data = private.searchDB(data, server, i, "failedBidsNeutral", id)
				end
			end
		end
	end
	return data
end

function private.searchDB(data, server, player, DB, itemID)
	for index, itemKey in pairs(server[player][DB][itemID]) do
		DB = DB:gsub("Neutral", "")--remove the Neutral part so we send it to the proper function
		for _, text in ipairs(itemKey) do
			tinsert(data, {DB:upper(), itemID, index, text})
		end
	end
	return data
end

function private.formatServerData(data, settings)
	local formatedData = {}
	--Format Data for display via scroll private.frame
	for i,v in pairs(data) do
		local match = true
		--to provide exact match filtering for of the tems we compare names to the itemKey on API searches
		if settings.exact and settings.suffix then
			local _, suffix = lib.API.decodeLink(v[3])
			if suffix == settings.suffix then
				-- do nothing and add item to data table
			else
				match = false --we want exact matches and this is not one
			end
		end
		if match and v[1] then
			local database = v[1]
			--just a wrapper to call the correct function for the database we are wanting to format. Example function private.FAILEDBIDS(...)  ==  private["FAILEDBIDS"](...)
			local store = private[database]
			local entry = store(v[2], v[3], v[4], settings)
			tinsert(formatedData, entry)
		end
	end

	return formatedData
end

--take collected data and format
local  function styleColors(database) --helper takes formated data table and looks to what colors we use for style
	-- style colors for the various databases
	if database == _BC('UiAucSuccessful') then
		return 0.3, 0.9, 0.8
	elseif database == _BC('UiAucExpired') then
		return 1, 0, 0
	elseif database == _BC('UiAucCancelled') then
		return 1, 0.6, 0
	elseif database == _BC('UiWononBuyout') or database == _BC('UiWononBid') then
		return 1, 1, 0
	elseif database == _BC('UiOutbid') then
		return 1, 1, 1
	else --return default
		return  1, .5, .1
	end
end

function private.styleServerData(data)
	--create style data for entries that are going to be displayed, created seperatly to allow us to reduce the data table entries
	local dateString = get("dateString") or "%c"
	for i,v in pairs(data) do
		local database = v[2]
		local r, g, b = styleColors(database)
		style[i] = {}
		if get("colorizeSearch") then style[i][1] = {["rowColor"] = {r, g, b, 0, get("colorizeSearchopacity") or 0, "Horizontal"}} end
		style[i][12] = {["date"] = dateString}
		style[i][2] = {["textColor"] = {r, g, b}}
		style[i][8] ={["textColor"] = {r, g, b}}
	end
	return style
end

local function sorton12(a, b)
	return a[12] > b[12]
end

function private.reduceSize(tbl, count)
	--The data provided is from multiple toons tables, so we need to resort the merged data back into sequential time order
	sort(tbl, sorton12)
	local data = {} -- this will be a new table, this prevents chages from being propagated back to the cached "data" refrence
	for i = 1, count do
		tinsert(data, tbl[i])
	end
	return data
end

--Filter out dates older than we are interested in
function private.filterbyDate(tbl, lowDate, highDate)
	if not lowDate then lowDate = 1 end
	if not highDate then highData = 2051283600 end -- wow's date system errors when you go to far into the future 2035

	local data = {} -- this will be a new table, this prevents chages from being propagated back to the cached "data" refrence
	for i,v in ipairs(tbl) do
		if v[12] > lowDate and v[12] < highDate then
			tinsert(data, v)
		end
	end
	return data
end

--To simplify having two seperate search routines, the Data creation of each table has been made a local function
function private.COMPLETEDAUCTIONS(id, itemKey, text)
	local uStack, uMoney, uDeposit, uFee, uBuyout, uBid, uSeller, uTime, uReason, uMeta = private.unpackString(text)
	if uSeller == "0" then uSeller = "..." end
	if uReason == "0" then uReason = "..." end
	local bid = tonumber(uBid) or 0
	local buyout = tonumber(uBuyout) or 0
	local money = tonumber(uMoney) or 0
	local stack = tonumber(uStack) or 0
	local deposit = tonumber(uDeposit) or 0
	local fee = tonumber(uFee) or 0
	local datestamp = tonumber(uTime) or 0

	local profit = money - deposit
	local pricePer = profit + fee
	if stack > 1 then pricePer = pricePer / stack end

	local itemID, suffix, uniqueID = lib.API.decodeLink(itemKey)
	local itemLink =  lib.API.createItemLinkFromArray(itemID..":"..suffix, uniqueID)
		or private.getItemInfo(id, "name") -- if not in our DB ask the server
		or "Unknown"

	return {
		itemLink, --itemname
		_BC('UiAucSuccessful'), --Transaction status

		bid,
		buyout,
		money, --money received in mail (Net)
		stack,
		pricePer,

		uSeller, --seller/buyer - buyer in this case

		deposit,
		fee,
		uReason, --usually blank in this case
		datestamp, --time, --Make this a user choosable option.
		profit,
		uMeta or "",
	}
end

function private.FAILEDAUCTIONS(id, itemKey, text)
	local status
	local uStack, uMoney, uDeposit, uFee, uBuyout, uBid, uSeller, uTime, uReason, uMeta = private.unpackString(text)
	if uSeller == "0" then uSeller = "..." end
	if uReason == "0" then uReason = "..." end
	local bid = tonumber(uBid) or 0
	local buyout = tonumber(uBuyout) or 0
	local stack = tonumber(uStack) or 0
	local deposit = tonumber(uDeposit) or 0
	local datestamp = tonumber(uTime) or 0
	-- uMoney, uFee should be "0" in this case

	if uReason == _BC('Cancelled') then
		status = _BC('UiAucCancelled') --if its a cancel rather than true expired auction
	else
		status =_BC('UiAucExpired')
	end

	local itemID, suffix, uniqueID = lib.API.decodeLink(itemKey)
	local itemLink =  lib.API.createItemLinkFromArray(itemID..":"..suffix, uniqueID)
		or private.getItemInfo(id, "name") -- if not in our DB ask the server
		or "Unknown"

	return {
		itemLink,
		status, --Transaction status

		bid,
		buyout,
		0, --money (Net)
		stack,
		0, --Price/per

		uSeller, --seller/buyer - should be blank in this case

		deposit,
		0, --fee
		uReason, --reason for return, e.g. cancelled
		datestamp, --time, --Make this a user choosable option.
		-deposit, --Profit - lost deposit
		uMeta or "",
	}
end

function private.COMPLETEDBIDSBUYOUTS(id, itemKey, text)
	local status
	local uStack, uMoney, uDeposit, uFee, uBuyout, uBid, uSeller, uTime, uReason, uMeta = private.unpackString(text)
	if uSeller == "0" then uSeller = "..." end
	if uReason == "0" then uReason = "..." end
	if not uMeta then uMeta = "" end
	local price = tonumber(uBid) or 0 -- how much we paid
	local stack = tonumber(uStack) or 0
	local buyout = tonumber(uBuyout) or 0
	local datestamp = tonumber(uTime) or 0
	-- uMoney, uDeposit, uFee should all be "0" in this case

	if uBuyout ~= uBid then
		status = _BC('UiWononBid')
	else
		status = _BC('UiWononBuyout')
	end

	local pricePer = price
	if stack > 1 then pricePer = pricePer / stack end

	--replace reason with DE info
	local mat, count, value = uMeta:match("DE:(%d-):(%d-):(%d-)|")
	if mat and count and value then
		local _, link = GetItemInfo(mat)
		if link then
			uReason = link.." X "..count
			--change the profit to be the diff between bought and what we DE into
			--profit = count*value - profit -- disabled: we don't yet know how much these mats will really sell for
		end
	end

	local itemID, suffix, uniqueID = lib.API.decodeLink(itemKey)
	local itemLink =  lib.API.createItemLinkFromArray(itemID..":"..suffix, uniqueID)
		or private.getItemInfo(id, "name") -- if not in our DB ask the server
		or "Unknown"

	return {
		itemLink,
		status, --Transaction status

		price, --bid
		buyout,
		0, --money (Net)
		stack,
		pricePer,

		uSeller, --seller/buyer - seller in this case

		0, --deposit
		0, --fee
		uReason, --reason bought
		datestamp, --time, --Make this a user choosable option.
		-price, --Profit - how much we paid (negative value)
		uMeta or "",
	}
end

function private.FAILEDBIDS(id, itemKey, text)
	local uStack, uMoney, uDeposit, uFee, uBuyout, uBid, uSeller, uTime, uReason, uMeta = private.unpackString(text)
	if uSeller == "0" then uSeller = "..." end
	if uReason == "0" then uReason = "..." end
	-- uMoney, uDeposit, uFee, uBuyout expected to all be "0" in this case
	-- BeanCounterMail records money received with the mail in uBid
	local stack = tonumber(uStack) or 0
	local money = tonumber(uBid) or 0
	local timestamp = tonumber(uTime) or 0

	local pricePer = money
	if stack > 1 then pricePer = pricePer / stack end

	local itemID, suffix, uniqueID = lib.API.decodeLink(itemKey)
	local itemLink =  lib.API.createItemLinkFromArray(itemID..":"..suffix, uniqueID)
		or private.getItemInfo(id, "name") -- if not in our DB ask the server
		or "Unknown"

	return {
		itemLink,
		_BC('UiOutbid'), --Transaction status

		money, --bid
		0, --buyout
		money, --money received in mail (Net)
		stack,
		pricePer,

		uSeller, --seller/buyer - seller in this case

		0, --deposit
		0, --fee
		uReason, --reason for bid
		timestamp, --time, --Make this a user choosable option.
		0, --Profit
		uMeta or "",
	}
end
