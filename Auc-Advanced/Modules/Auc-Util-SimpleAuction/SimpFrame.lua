--[[
	Auctioneer - Simplified Auction Posting
	Version: 1.13.6643 (SwimmingSeadragon)
	Revision: $Id: SimpFrame.lua 6643 2021-01-30 13:42:33Z none $
	URL: http://auctioneeraddon.com/

	This is an addon for World of Warcraft that adds a simple dialog for
	easy posting of your auctionables when you are at the auction-house.

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

local lib = AucAdvanced.Modules.Util.SimpleAuction
if not lib then return end
local private = lib.Private
local aucPrint,decode,_,_,replicate,_,get,set,default,debugPrint,fill = AucAdvanced.GetModuleLocals()
local Const = AucAdvanced.Const
local Resources = AucAdvanced.Resources

local GetMarketValue = AucAdvanced.API.GetMarketValue
local SanitizeLink = AucAdvanced.SanitizeLink
local GetSigFromLink = AucAdvanced.API.GetSigFromLink
local GetStoreKeyFromLink = AucAdvanced.API.GetStoreKeyFromLink
local GetAuctionItem = AucAdvanced.Scan.GetAuctionItem
local QueryImage = AucAdvanced.API.QueryImage
local CountAvailableItems = AucAdvanced.Post.CountAvailableItems
local GetDepositCost = AucAdvanced.Post.GetDepositCost
local GetDurationCode = AucAdvanced.Post.GetDurationCode
local QueueBuy = AucAdvanced.Buy.QueueBuy
local StartScan = AucAdvanced.Scan.StartScan
local StartPushedScan = AucAdvanced.Scan.StartPushedScan
local PushScan = AucAdvanced.Scan.PushScan
local AucIsScanning = AucAdvanced.Scan.IsScanning
local PostAuctionClick = AucAdvanced.Post.PostAuctionClick
local ShowItemLink = AucAdvanced.ShowItemLink
local ShowPetLink = AucAdvanced.ShowPetLink

local GetSettingStr = private.GetSettingStr -- Note: see function definition in AucSimple.lua

local IsPlayerIgnored -- to be filled in when Auc-Filter-Basic loads
AucAdvanced.RegisterModuleCallback("basic", function(lib) IsPlayerIgnored = lib.IsPlayerIgnored end)
if not IsPlayerIgnored then IsPlayerIgnored = function() end end -- dummy function in case Filter-Basic never loads

local wipe = wipe

local pricecache = {}

local frame
local TAB_NAME = "Post"

function private.clearcache()
	wipe(pricecache)
end

function private.postPickupContainerItemHook(bag, slot)
	if (CursorHasItem()) then
		frame.CursorItemBag = bag
		frame.CursorItemSlot = slot
	else
		frame.CursorItemBag = nil
		frame.CursorItemSlot = nil
	end
end

function private.ShiftFocus(frame, ...)
	local dest
	if IsShiftKeyDown() then
		dest = frame.prevFrame
	else
		dest = frame.nextFrame
	end
	if dest and dest.SetFocus then
		dest:SetFocus()
	else
		frame:ClearFocus()
	end
end

function private.SetPrevNext(frame, prevFrame, nextFrame)
	frame.prevFrame = prevFrame
	frame.nextFrame = nextFrame
	frame:SetScript("OnTabPressed", private.ShiftFocus)
	frame:SetScript("OnEnterPressed", private.ShiftFocus)
end

function private.GetKey(link)
	-- for items this matches itemId, suffix and factor
	-- for pets this matches speciesId, level and quality
	local id, property = GetStoreKeyFromLink(link, 1)
	if id then -- only need to check id, property should also be non nil in this case
		return id..":"..property
	end
end
function private.IsMatchingKey(key, item)
	itemlink = item[Const.LINK]
	if not itemlink then return end
	return key == private.GetKey(itemlink)
end


function private.GetMyPrice(link, items)
	local uBid, uBuy
	if not link then return end
	local searchkey = private.GetKey(link)
	if not searchkey then return end
	local n = GetNumAuctionItems("owner")
	if n and n > 0 then
		for i = 1, n do
			local item = GetAuctionItem("owner", i)
			if item and private.IsMatchingKey(searchkey, item) then
				local stack = item[Const.COUNT]
				if stack and stack > 0 then
					-- stack may be 0 for a sold auction - only try to calculate bid or buy for auction with non-zero stack counts
					local bid, buy = item[Const.MINBID], item[Const.BUYOUT]
					if bid and bid > 0 then -- check for rare bug where you could get an invalid bid
						if items then tinsert(items, item) end -- only insert items with valid stack and bid values
						bid = bid / stack
						uBid = uBid and min(uBid, bid) or bid
						if buy and buy > 0 then -- buyout of 0 is valid, but don't include in our min buyout
							buy = buy / stack
							uBuy = uBuy and min(uBuy, buy) or buy
						end
					end
				end
			end
		end
	end
	return uBid, uBuy
end

--Returns:
--numitems: number of competing items
--items: table with competition
--uBid: bid matching your current auction
--uBuy: buy matching your current auction
--lBid: bid undercutting competition by 1c
--lBuy: buy undercutting competition by 1c
--aSeen: number of items in competing auctions
--aBuy: average price for current competing auctions
local query = {}
function private.GetItems(link)
	local sig = GetSigFromLink(link)
	if not sig then return end
	if pricecache[sig] then
		uBid, uBuy, lBid, lBuy, aSeen, aveBuy = strsplit(":", pricecache[sig][1])
		uBid, uBuy, lBid, lBuy, aSeen, aveBuy = tonumber(uBid), tonumber(uBuy), tonumber(lBid), tonumber(lBuy), tonumber(aSeen), tonumber(aveBuy)
		return #pricecache[sig][2], pricecache[sig][2], uBid, uBuy, lBid, lBuy, aSeen, aveBuy
	end
	local linkType, id, suffix, factor = decode(link)
	if linkType == "item" then
		query.itemId = id
		query.suffix = suffix
		query.factor = factor
		query.speciesID = nil
		query.quality = nil
		query.minItemLevel = nil
		query.maxItemLevel = nil
	elseif linkType == "battlepet" then
		query.speciesID = id
		query.quality = factor
		query.minItemLevel = suffix
		query.maxItemLevel = suffix
		query.itemId = 82800
		query.suffix = nil
		query.factor = nil
	else
		return
	end

	local aSeen, lBid, lBuy, uBid, uBuy, aBuy, aveBuy = 0
	local player = Const.PlayerName
	local items = {}
	local matching = QueryImage(query)

	local live = false
	if AuctionFrame and AuctionFrame:IsVisible() then
		live = true
		uBid, uBuy = private.GetMyPrice(link, items)
	end
	for pos, item in ipairs(matching) do
		local bid, buy, owner, stk = item[Const.MINBID], item[Const.BUYOUT], item[Const.SELLER], item[Const.COUNT]
		if stk and stk >= 1 then
			local bidea, buyea
			if bid and bid > 0 then
				bidea = bid/stk
			end
			if buy and buy > 0 then
				buyea = buy/stk
			end

			if owner and owner == player then
				if not live then
					if not uBid then uBid = bidea elseif bidea then uBid = min(uBid, bidea) end
					if not uBuy then uBuy = buyea elseif buyea then uBuy = min(uBuy, buyea) end
					tinsert(items, item)
				end
			else
				if not lBid then
					lBid = bidea
				elseif bidea then
					lBid = min(lBid, bidea)
				end
				if not lBuy then
					lBuy = buyea
				elseif buyea then
					lBuy = min(lBuy, buyea)
				end
				if buy then
					aBuy = (aBuy or 0) + buy
					aSeen = aSeen + stk
				end
				tinsert(items, item)
			end
		end
	end
	aveBuy = (aBuy and aSeen>=1) and aBuy/aSeen or 0
	pricecache[sig] = {}
	pricecache[sig][1] = strjoin(":", tostring(uBid), tostring(uBuy), tostring(lBid), tostring(lBuy), tostring(aSeen), tostring(aveBuy))
	pricecache[sig][2] = replicate(items)
	return #items, items, uBid, uBuy, lBid, lBuy, aSeen, aveBuy
end

local coins = AucAdvanced.Coins
private.coins = coins

function private.SetIconCount(itemCount)
	local size = 18
	if itemCount > 999 then
		local size = 14
	elseif itemCount > 99 then
		local size = 16
	elseif itemCount > 9 then
		local size = 17
	end
	frame.icon.count:SetFont(AucAdvSimpleNumberFontLarge.font, size, "OUTLINE")
	frame.icon.count:SetText(itemCount)
end

function private.UpdateDisplay()
	local link = frame.icon.itemLink
	if not link then return end
	local cBid, cBuy = MoneyInputFrame_GetCopper(frame.minprice), MoneyInputFrame_GetCopper(frame.buyout)
	frame.CurItem.buy, frame.CurItem.bid = cBuy, cBid
	local cStack = frame.stacks.size:GetNumber() or 1
	frame.CurItem.stack = cStack
	local cNum = frame.stacks.num:GetNumber() or 1
	frame.CurItem.number = cNum
	local oStack, oBid, oBuy, oReason, oLink = unpack(frame.detail)
	local lStack = frame.stacks.size.lastSize or oStack
	local duration = frame.duration.time.selected

	local sig = GetSigFromLink(link)
	if not sig then return private.LoadItemLink() end
	local _, total, unpostable, _, _, reason = CountAvailableItems(sig)
	total = total - unpostable
	if total < 1 then return private.LoadItemLink() end
	private.SetIconCount(total)

	local dBid = abs(cBid/lStack*oStack-oBid)
	local dBuy = abs(cBuy/lStack*oStack-oBuy)

	local priceType = "auto"
	if dBid >= 1 or dBuy >= 1 then
		priceType = "fixed"
		frame.err:SetText("Manual pricing on item")
	end

	if priceType == "auto" and cStack ~= oStack then
		return private.UpdatePricing()
	elseif priceType == "fixed" and cStack ~= lStack then
		cBid = cBid / lStack * cStack
		cBuy = cBuy / lStack * cStack
		cBid = ceil(cBid)
		cBuy = ceil(cBuy)
		MoneyInputFrame_ResetMoney(frame.minprice)
		MoneyInputFrame_SetCopper(frame.minprice, cBid)
		frame.CurItem.bid = cBid
		frame.CurItem.bidper = cBid/frame.CurItem.stack
		MoneyInputFrame_ResetMoney(frame.buyout)
		MoneyInputFrame_SetCopper(frame.buyout, cBuy)
		frame.CurItem.buy = cBuy
		frame.CurItem.buyper = cBuy/frame.CurItem.stack
		frame.err:SetText("Adjusted price to new stack size")
	end

	if GetSellValue then
		local vendor = GetSellValue(oLink) or 0
		if vendor > cBid / cStack then
			frame.err:SetText("Warning: Bid is below vendor price")
		end
	end

	local flagenable = true
	local coinsBid, coinsBuy, coinsBidEa, coinsBuyEa
	if cBid > 0 then
		coinsBid = coins(cBid)
		coinsBidEa = coins(cBid/cStack)
	else
		coinsBid = "no"
		coinsBidEa = "no"
		frame.err:SetText("Error: No bid price set")
		flagenable = false
	end
	if cBuy > 0 then
		coinsBuy = coins(cBuy)
		coinsBuyEa = coins(cBuy/cStack)
		if cBuy < cBid then
			frame.err:SetText("Error: Buyout cannot be less than bid price")
			flagenable = false
		end
	else
		coinsBuy = "no"
		coinsBuyEa = "no"
	end

	local lots = "lot"
	if cNum > 1 then lots = "lots" end

	local text
	if (cStack > 1) then
		text = format("Auctioning %d %s of %d sized stacks at %s bid/%s buyout per stack (%s/%s ea)", cNum, lots, cStack, coinsBid, coinsBuy, coinsBidEa, coinsBuyEa)
	else
		text = format("Auctioning %d %s of this item at %s bid/%s buyout each", cNum, lots, coinsBid, coinsBuy)
	end
	frame.info:SetText(text)

	duration = GetDurationCode(duration)
	local deposit = GetDepositCost(oLink, duration, Resources.IsNeutralZone, cStack, 1)
	if not deposit then
		frame.fees:SetText("Unknown deposit cost")
	elseif cNum > 1 then
		frame.fees:SetText(("Deposit: %s, %s/stack \n~%s/ea"):format(coins(deposit*cNum), coins(deposit), coins(ceil(deposit/cStack))))
	elseif cStack > 1 then
		frame.fees:SetText(("Deposit: %s/stack \n~%s/ea"):format(coins(deposit), coins(ceil(deposit/cStack))))
	else
		frame.fees:SetText(("Deposit: %s"):format(coins(deposit)))
	end
	frame.stacks.equals:SetText("= "..(cStack * cNum))
	if flagenable then
		frame.create:Enable()
	else
		frame.create:Disable()
	end
end

local timeLeftStrings = {
                [1] = "30m",
                [2] = "2h",
                [3] = "12h",
                [4] = "48h",
}
local auctionTimeMax = 24

if AucAdvanced.Classic then
    timeLeftStrings = {
                    [1] = "30m",
                    [2] = "2h",
                    [3] = "8h",
                    [4] = "24h",
    }
    auctionTimeMax = 48
end

function private.UpdateCompetition(image)
	local data = {}
	local style = {}
	if image then
		for i = 1, #image do
			local result = image[i]
			local tLeft = result[Const.TLEFT]
            tLeft = timeLeftStrings[ tLeft ]
            if not tLeft then tLeft = timeLeftStrings[4] end
			local count = result[Const.COUNT]
			if count < 1 then count = 1 end -- in case a 0 slips through
			data[i] = {
				result[Const.SELLER],
				tLeft,
				count,
				floor(0.5+result[Const.MINBID]/count),
				floor(0.5+result[Const.CURBID]/count),
				floor(0.5+result[Const.BUYOUT]/count),
				result[Const.MINBID],
				result[Const.CURBID],
				result[Const.BUYOUT],
				result[Const.LINK]
			}
			local curbid = result[Const.CURBID]
			if curbid == 0 then
				curbid = result[Const.MINBID]
			end
			--color ignored/self sellers
			local seller = result[Const.SELLER]
			if seller == Const.PlayerName then
				if not style[i] then style[i] = {} end
				style[i][1] = { textColor = {0,1,0} }
			elseif IsPlayerIgnored(seller) then
				if not style[i] then style[i] = {} end
				style[i][1] = { textColor = {1,0,0} }
			end
		end
	end
	frame.imageview.sheet:SetData(data, style)
end

function private.UpdatePricing()
	local link = frame.icon.itemLink
	if not link then
		private.UpdateCompetition() -- wipe
		return
	end
	local mid, seen = 0,0
	local stack = frame.stacks.size:GetNumber()
	local _,_,_,_,_,_,_,stx = GetItemInfo(link)
	if not stx or stx < 1 then
		stx = 1
	end

	local sig = GetSigFromLink(link)
	if not sig then return private.LoadItemLink() end
	local _, total, unpostable, _, _, reason = CountAvailableItems(sig)
	total = total - unpostable
	if total < 1 then return private.LoadItemLink() end
	private.SetIconCount(total)

	stx = min(stx, total)

	if not stack or stack == 0 or stack > stx then
		stack = stx
		frame.stacks.size:SetNumber(stack)
		frame.CurItem.stack = stack
	end

	local num = frame.stacks.num:GetNumber()
	if not num or num == 0 then
		num = 1
		frame.stacks.num:SetNumber(num)
		frame.CurItem.number = num
	end

	local buy, bid
	local reason = ""

	-- We need this out here because it fetches the items from the image
	local imgseen, image, matchBid, matchBuy, lowBid, lowBuy, aSeen, aveBuy = private.GetItems(link)
	private.UpdateCompetition(image)

	--check for fixed price
	if frame.CurItem.manual then
		buy = frame.CurItem.buyper
		bid = frame.CurItem.bidper
		reason = "Manual pricing on item"
	end
	if not buy then
		--Check for undercut first
		if frame.options.undercut:GetChecked() then
			if lowBuy and lowBuy > 0 then
				local underBuy, underBid, by = 1,1, "default 1c"

				local model = get("util.simpleauc.undercut")
				local fixed = get("util.simpleauc.undercut.fixed")
				local percent = get("util.simpleauc.undercut.percent")
				local pct = tonumber(percent)/100
				if model == "fixed" then
					underBuy = fixed
					underBid = fixed
					by = "fixed amount: "..coins(fixed)
				else
					underBuy = lowBuy*pct
					underBid = (lowBid or 0)*pct
					by = percent.."% ("..coins(underBuy)..")"
				end

				buy = lowBuy - underBuy
				if lowBid and lowBid > 0 and lowBid <= lowBuy then
					bid = lowBid - underBid
				else
					bid = buy * 0.8
				end
				reason = "Undercutting market by "..by
			end
		--then matching current
		elseif frame.options.matchmy:GetChecked() then
			if matchBuy and matchBuy > 0 then
				buy = matchBuy
				if matchBid and matchBid > 0 and matchBid <= matchBuy then
					bid = matchBid
				else
					bid = buy * 0.8
				end
				reason = "Matching your prices"
			end
		end
		--if no buy price yet, look for marketprice
		if not buy then
			local market, seen = GetMarketValue(link)
			if market and (market > 0) and (seen > 5 or aSeen < 3) then
				buy = market
				bid = market * 0.8
				reason = "Using market value"
			end
		end
		--look for average of current competition
		if not buy and aveBuy and aveBuy > 0 then
			buy = aveBuy
			bid = buy * 0.8
			reason = "Using current market data"
		end
		--Vendor markup
		if not buy and GetSellValue then
			local vendor = GetSellValue(link)
			if vendor and vendor > 0 then
				buy = vendor * 3
				bid = buy * 0.8
				reason = "Marking up vendor"
			end
		end
	end
	if not buy then
		buy = 0
	end
	if not bid then
		bid = buy * 0.8
	end
	--multiply by stacksize
	bid = bid * stack
	buy = buy * stack
	--We give up
	if bid == 0 then
		bid = 1
		buy = 0
		reason = "Unable to calculate price"
	end

	if (stack * num) > total then
		reason = "Error: You don't have that many"
	end
	bid, buy = ceil(tonumber(bid) or 1), ceil(tonumber(buy) or 0)

	MoneyInputFrame_ResetMoney(frame.minprice)
	MoneyInputFrame_SetCopper(frame.minprice, bid)
	frame.CurItem.bid = bid
	frame.CurItem.bidper = bid/stack

	MoneyInputFrame_ResetMoney(frame.buyout)
	MoneyInputFrame_SetCopper(frame.buyout, buy)
	frame.CurItem.buy = buy
	frame.CurItem.buyper = buy/stack

	frame.detail = { stack, bid, buy, reason, link }
	frame.err:SetText(reason)

	private.UpdateDisplay(reason)
end

--function runs when we're alerted to a possible change in one of the controls.
--we check if something is actually different, and if so, update.
--rather than changing ONLY one setting, changed function allow multiple settings to be modified in one round
--this solved issues with alt double click posting items before our onupdate could be called enough cycles to set all the changed values
function private.CheckUpdate()
	if not frame.CurItem.link then return end
	local updatepricing, updatedisplay = false, false

	local buy = MoneyInputFrame_GetCopper(frame.buyout)
	local bid = MoneyInputFrame_GetCopper(frame.minprice)
	local stack = frame.stacks.size:GetNumber()
	local number = frame.stacks.num:GetNumber()
	if frame.CurItem.buy ~= buy then --New Buyout manually entered
		frame.CurItem.buy = buy
		frame.CurItem.buyper = buy/(stack or 1)
		frame.CurItem.manual = true
		updatedisplay = true
	end
	if frame.CurItem.bid ~= bid then --New Bid manually entered
		frame.CurItem.bid = bid
		frame.CurItem.bidper = bid/(stack or 1)
		frame.CurItem.manual = true
		updatedisplay = true
	end
	if  stack and stack > 0 and frame.CurItem.stack ~= stack then --new stack size entered
		frame.CurItem.stack = stack
		updatepricing = true
	end
	if  number and number > 0 and frame.CurItem.number ~= number then --new number of stacks entered
		frame.CurItem.number = number
		updatepricing = true
	end

	local match = frame.options.matchmy:GetChecked()
	if frame.CurItem.match ~= match then
		frame.CurItem.match = match
		if match then --turn off other checkboxes
			frame.CurItem.manual = false
			frame.CurItem.undercut = false
			frame.options.undercut:SetChecked(false)
			frame.options.remember:SetChecked(false) -- frame.CurItem.remember gets updated below
		end
		updatepricing = true
	end
	local undercut = frame.options.undercut:GetChecked()
	if  frame.CurItem.undercut ~= undercut then
		frame.CurItem.undercut = undercut
		if undercut then --turn off other checkboxes
			frame.CurItem.manual = false
			frame.CurItem.match = false
			frame.options.matchmy:SetChecked(false)
			frame.options.remember:SetChecked(false) -- frame.CurItem.remember gets updated below
		end
		updatepricing = true
	end

	local remember = frame.options.remember:GetChecked()
	if  frame.CurItem.remember ~= remember then
		frame.CurItem.remember = remember
		if remember then
			frame.CurItem.match = false
			frame.options.matchmy:SetChecked(false)
			frame.CurItem.undercut = false
			frame.options.undercut:SetChecked(false)
			frame.CurItem.manual = true
		else
			private.RemoveConfig()
		end
		updatepricing = true

	end

	local duration = frame.duration.time.selected
	if  frame.CurItem.duration ~= duration then
		frame.CurItem.duration = duration
		updatepricing = true
	end

	if updatepricing then
		private.UpdatePricing() -- also calls private.UpdateDisplay()
	elseif updatedisplay then
		private.UpdateDisplay()
	end
	if (updatepricing or updatedisplay) and frame.CurItem.remember then
		private.SaveConfig()
	end

	frame.CurItem.valuechanged = nil
end

function private.IconClicked()
	local objType, _, itemLink = GetCursorInfo()
	local size
	if CursorHasItem() and frame.CursorItemBag and frame.CursorItemSlot then
		_, size = GetContainerItemInfo(frame.CursorItemBag, frame.CursorItemSlot)
	end
	frame.CursorItemBag = nil
	frame.CursorItemSlot = nil
	ClearCursor()
	if objType ~= "item" then itemLink = nil end
	private.LoadItemLink(itemLink, size)
end

function private.LoadItemLink(itemLink, size)
	local name, quality, texture
	wipe(frame.CurItem)
	if itemLink then
		local sig, linkType = GetSigFromLink(itemLink)
		if not sig then
			aucPrint(itemLink.." cannot be posted: Not an item")
			return private.LoadItemLink()
		end
		if linkType == "item" then
			local itemName, _, itemRarity, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
			name = itemName
			quality = itemRarity
			texture = itemTexture
			itemLink = SanitizeLink(itemLink)
		elseif linkType == "battlepet" then
			local _, speciesID, _, petQuality = strsplit(":", itemLink)
			speciesID = tonumber(speciesID)
			if speciesID then
				local petName, petIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
				name = petName
				texture = petIcon
				quality = tonumber(petQuality) or -1
			end
		end
		if not name then
			return private.LoadItemLink()
		end

		frame.CurItem.link = itemLink
		frame.CurItem.name = name
		frame.icon.itemLink = itemLink
		frame.icon:SetNormalTexture(texture)

		local _, total, unpostable, _, _, reason = CountAvailableItems(sig)
		local itemCount = total - unpostable
		if itemCount < 1 then
			if reason == "Damaged" then
				aucPrint(itemLink.." is damaged: you may be able to post it after repairing it")
			else
				aucPrint(itemLink.." cannot be posted: "..AucAdvanced.Post.GetErrorText(reason))
			end
			return private.LoadItemLink()
		end
		frame.CurItem.count = itemCount
		private.SetIconCount(itemCount)

		frame.name:SetText(name)
		local r, g, b = GetItemQualityColor(quality)
		frame.name:SetTextColor(r, g, b)
	else
		frame.icon.itemLink = nil
		frame.icon:SetNormalTexture(nil)
		frame.icon.count:SetText("")
		frame.name:SetText("Drop item onto slot")
		frame.create:Disable()
	end
	frame.info:SetText("To auction an item, drag it from your bag.")
	frame.fees:SetText("")
	frame.err:SetText("-- No item selected --")
	frame.stacks.equals:SetText("= 0")
	private.ClearSetting() -- calls private.UpdatePricing()
	private.LoadConfig() -- calls private.UpdatePricing() again if settings were loaded

	if itemLink and size then
		frame.stacks.size:SetNumber(size)
	end
end

function private.DoTooltip()
	local link = frame.CurItem.link
	if not link then return end
	if strmatch(link, "|Hitem:") then
		GameTooltip:SetOwner(frame.icon, "ANCHOR_NONE")
		ShowItemLink(GameTooltip, link, frame.CurItem.count)
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, 0)
	elseif strmatch(link, "|Hbattlepet:") then
		ShowPetLink(BattlePetTooltip, link, frame.CurItem.count)
		BattlePetTooltip:ClearAllPoints()
		BattlePetTooltip:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, 0)
	end
end

function private.UndoTooltip()
	GameTooltip:Hide()
	if BattlePetTooltip then
		BattlePetTooltip:Hide()
	end
end

function private.OnUpdate()
	-- check for valuechanged on update,  so that multiple controls changing at once will only yield one check
	if frame.CurItem.valuechanged then
		frame.CurItem.valuechanged = nil
		private.CheckUpdate()
	end
	-- delayed call to UpdatePricing triggered by "scanstats" (note: UpdatePricing is unsafe from within "scanstats")
	-- also avoids unnecessary processing while the frame is hidden
	if private.delayedUpdatePricing then
		private.delayedUpdatePricing = nil
		private.UpdatePricing()
	end
end

function private.LoadConfig()
	if not frame.CurItem.link then return end
	local id = GetSigFromLink(frame.CurItem.link)
	local settingstring = GetSettingStr(id)
	if not settingstring then return end
	local bid, buy, duration, number, stack = strsplit(":", settingstring)
	bid = tonumber(bid)
	buy = tonumber(buy)
	duration = tonumber(duration)
	number = tonumber(number)
	stack = tonumber(stack)
	MoneyInputFrame_ResetMoney(frame.minprice)
	MoneyInputFrame_SetCopper(frame.minprice, bid)
	MoneyInputFrame_ResetMoney(frame.buyout)
	MoneyInputFrame_SetCopper(frame.buyout, buy)
	frame.stacks.size:SetNumber(stack)
	frame.stacks.num:SetNumber(number)
	frame.options.undercut:SetChecked(false)
	frame.options.matchmy:SetChecked(false)
	frame.options.remember:SetChecked(true)
	frame.duration.time.selected = duration
	for i, j in pairs(frame.duration.time.intervals) do
		if duration == j then
			frame.duration.time[i]:SetChecked(true)
		else
			frame.duration.time[i]:SetChecked(false)
		end
	end
	frame.CurItem.bid = bid
	frame.CurItem.bidper = bid/stack
	frame.CurItem.buy = buy
	frame.CurItem.buyper = buy/stack
	frame.CurItem.duration = duration
	frame.CurItem.number = number
	frame.CurItem.stack = stack
	frame.CurItem.match = false
	frame.CurItem.undercut = false
	frame.CurItem.remember = true
	frame.CurItem.manual = true
	private.UpdatePricing()
end

function private.RemoveConfig()
	if not frame.CurItem.link then return end
	local id = GetSigFromLink(frame.CurItem.link)
	set("util.simpleauc."..Resources.ServerKey.."."..id, nil)
end

function private.SaveConfig()
	if not frame.CurItem.link then return end
	local id = GetSigFromLink(frame.CurItem.link)
	local settingstring = strjoin(":",
		tostring(frame.CurItem.bid),
		tostring(frame.CurItem.buy),
		tostring(frame.CurItem.duration),
		tostring(frame.CurItem.number),
		tostring(frame.CurItem.stack)
		)
	set("util.simpleauc."..Resources.ServerKey.."."..id, settingstring)
end

function private.ClearSetting()
	frame.CurItem.bid = nil
	frame.CurItem.bidper = nil
	frame.CurItem.buy = nil
	frame.CurItem.buyper = nil
	frame.CurItem.stack = nil
	frame.CurItem.number = nil
	frame.CurItem.manual = false
	MoneyInputFrame_ResetMoney(frame.minprice)
	MoneyInputFrame_ResetMoney(frame.buyout)
	frame.stacks.num:SetNumber(0)
	frame.stacks.size:SetNumber(0)

	local under, match, dur =
		get("util.simpleauc.auto.undercut"),
		get("util.simpleauc.auto.match"),
		get("util.simpleauc.auto.duration")
	if match then
		local uBid, uBuy = private.GetMyPrice(frame.CurItem.link)
		if uBid then
			under = false
		elseif under then
			match = false
		end
	end

	frame.options.matchmy:SetChecked(match)
	frame.CurItem.match = match
	frame.options.undercut:SetChecked(under)
	frame.CurItem.undercut = under
	frame.options.remember:SetChecked(false)
	frame.CurItem.remember = false

if AucAdvanced.Classic then
    if dur > 24 then dur = 24 end
	frame.duration.time[1]:SetChecked(dur == 2)
	frame.duration.time[2]:SetChecked(dur == 8)
	frame.duration.time[3]:SetChecked(dur == 24)
else
	frame.duration.time[1]:SetChecked(dur == 12)
	frame.duration.time[2]:SetChecked(dur == 24)
	frame.duration.time[3]:SetChecked(dur == 48)
end
	frame.duration.time.selected = dur
	frame.CurItem.duration = dur
	private.UpdatePricing()
end

function private.PostAuction()
	local link = frame.CurItem.link
	if not link then
		aucPrint("Posting Failed: No Item Selected")
		return
	end
	local sig = GetSigFromLink(link)
	local number = frame.CurItem.number
	local stack = frame.CurItem.stack
	local bid = frame.CurItem.bid
	local buy = frame.CurItem.buy
	local duration = frame.CurItem.duration
	duration = GetDurationCode(duration) or 3
	local success, reason = PostAuctionClick(sig, stack, bid, buy, duration, number)
	if success then
		aucPrint("Posting "..number.." stacks of "..stack.."x "..link.." at Bid:"..coins(bid)..", BO:"..coins(buy).." for "..duration.."h")
	else
		aucPrint("Posting Failed for "..link..": "..AucAdvanced.Post.GetErrorText(reason))
	end
end

function private.Refresh(background)
	local name, filterData
	local link = frame.CurItem.link
	if not link then return end
	local lType, itemID = strsplit(":", link)
	lType = lType:sub(-4)
	itemID = tonumber(itemID)
	if not itemID then
		-- link should always have an itemID, or speciesID for battlepets
		return
	elseif lType == "item" then
		local itemName, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(link)
		name = itemName
		filterData = AucAdvanced.Scan.QueryFilterFromID(classID, subClassID)
	elseif lType == "epet" then -- last 4 letters of "battlepet"
		-- all caged pets should have the default pet name (custom names are removed when caging)
		local petName, _, petType = C_PetJournal.GetPetInfoBySpeciesID(itemID) -- itemID is speciesID
		name = petName
		filterData = AucAdvanced.Scan.QueryFilterFromID(LE_ITEM_CLASS_BATTLEPET, Const.AC_PetType2SubClassID[petType])
	end
	if not name or name == "" then return end
	local exact = #name < 30 -- use exact match, except for very long names
	aucPrint(("Refreshing view of {{%s}}"):format(name))--Refreshing view of {{%s}}
	if background == true then
		StartPushedScan(name, nil, nil, nil, nil, exact, filterData)
	else
		PushScan()
		StartScan(name, nil, nil, nil, nil, nil, exact, filterData)
	end
end

function private.CreateFrames()
	if frame then return end

	local SelectBox = LibStub:GetLibrary("SelectBox")
	local ScrollSheet = LibStub:GetLibrary("ScrollSheet")

	frame = CreateFrame("Frame", "AucAdvSimpFrame", AuctionFrame, BackdropTemplateMixin and "BackdropTemplate")
	private.frame = frame
	local DiffFromModel = 0
	local MatchString = ""
	frame.list = {}
	frame.cache = {}
	frame.CurItem = {match = false, undercut = false, remember = false}
	frame.detail = {0,0,0,"",""}
	hooksecurefunc("PickupContainerItem", private.postPickupContainerItemHook)

	frame:SetParent(AuctionFrame)
	frame:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT")
	frame:SetPoint("BOTTOMRIGHT", AuctionFrame, "BOTTOMRIGHT")
	frame:SetScript("OnUpdate", private.OnUpdate)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", frame,  "TOP", 15, -20)
	frame.title:SetText("Simple Auction - Simplified auction posting interface")

	frame.slot = frame:CreateTexture(nil, "BORDER")
	frame.slot:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -45)
	frame.slot:SetWidth(50)
	frame.slot:SetHeight(50)
	frame.slot:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	frame.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")

	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.name:SetPoint("TOPLEFT", frame.slot, "TOPRIGHT", 10, -2)
	frame.name:SetJustifyV("TOP")
	frame.name:SetText("Drop item onto slot")

	frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.info:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -3)
	frame.info:SetJustifyV("TOP")
	frame.info:SetTextColor(0.0,1,1)
	frame.info:SetText("To auction an item, drag it from your bag.")

	frame.err = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.err:SetPoint("TOPLEFT", frame.info, "BOTTOMLEFT", 0, 0)
	frame.err:SetJustifyV("TOP")
	frame.err:SetTextColor(1,0.2,0,1)
	frame.err:SetText("-- No item selected --")

	frame.icon = CreateFrame("Button", nil, frame)
	frame.icon:SetPoint("TOPLEFT", frame.slot, "TOPLEFT", 3, -3)
	frame.icon:SetWidth(42)
	frame.icon:SetHeight(42)
	frame.icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square.blp")
	frame.icon:SetScript("OnClick", private.IconClicked)
	frame.icon:SetScript("OnReceiveDrag", private.IconClicked)
	frame.icon:SetScript("OnEnter", private.DoTooltip)
	frame.icon:SetScript("OnLeave", private.UndoTooltip)

	local numberFont = CreateFont("AucAdvSimpleNumberFontLarge")
	numberFont:CopyFontObject(GameFontHighlight)
	numberFont.font = numberFont:GetFont()
	numberFont:SetFont(numberFont.font, 12, "OUTLINE")
	numberFont:SetShadowColor(0,0,0)
	numberFont:SetShadowOffset(3,-2)

	frame.icon.count = frame.icon:CreateFontString(nil, "OVERLAY", "AucAdvSimpleNumberFontLarge")
	frame.icon.count:SetPoint("BOTTOMLEFT", frame.icon, "BOTTOMLEFT", 3, 5)

	frame.minprice = CreateFrame("Frame", "AucAdvSimpFrameStart", frame, BackdropTemplateMixin and "BackdropTemplate" and "MoneyInputFrameTemplate")
	frame.minprice.isMoneyFrame = true
	frame.minprice:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -120)
	MoneyInputFrame_SetOnValueChangedFunc(frame.minprice, function()
			frame.CurItem.valuechanged = true
		end)
	frame.minprice.label = frame.minprice:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.minprice.label:SetPoint("BOTTOMLEFT", frame.minprice, "TOPLEFT", 0, 0)
	frame.minprice.label:SetText("Starting price:")
	AucAdvSimpFrameStartGold:SetWidth(50)

	frame.buyout = CreateFrame("Frame", "AucAdvSimpFrameBuyout", frame, BackdropTemplateMixin and "BackdropTemplate" and "MoneyInputFrameTemplate")
	frame.buyout.isMoneyFrame = true
	frame.buyout:SetPoint("TOPLEFT", frame.minprice, "BOTTOMLEFT", 0, -20)
	MoneyInputFrame_SetOnValueChangedFunc(frame.buyout, function()
			frame.CurItem.valuechanged = true
		end)
	frame.buyout.label = frame.buyout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.buyout.label:SetPoint("BOTTOMLEFT", frame.buyout, "TOPLEFT", 0, 0)
	frame.buyout.label:SetText("Buyout price:")
	AucAdvSimpFrameBuyoutGold:SetWidth(50)

	frame.duration = CreateFrame("Frame", "AucAdvSimpFrameDuration", frame, BackdropTemplateMixin and "BackdropTemplate")
	frame.duration:SetPoint("TOPLEFT", frame.buyout, "BOTTOMLEFT", 0, -20)
	frame.duration:SetWidth(140)
	frame.duration:SetHeight(20)
	frame.duration.label = frame.duration:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.duration.label:SetPoint("BOTTOMLEFT", frame.duration, "TOPLEFT", 0, 0)
	frame.duration.label:SetText("Duration:");

	frame.duration.time = {
        intervals = {12, 24, 48},
        selected = auctionTimeMax,
		OnClick = function (obj, ...)
			frame.CurItem.valuechanged = true
			local self = frame.duration.time
			for pos, dur in ipairs(self.intervals) do
				if obj == self[pos] then
					self.selected = dur
					self[pos]:SetChecked(true)
				else
					self[pos]:SetChecked(false)
				end
			end
		end,
	}

    if AucAdvanced.Classic then
        frame.duration.time.intervals = {2, 8, 24}
    end

	local t = frame.duration.time
	for pos, dur in ipairs(t.intervals) do
		t[pos] = CreateFrame("CheckButton", "AucAdvSimpFrameDuration"..dur, frame.duration, "OptionsCheckButtonTemplate")
		t[pos]:SetPoint("TOPLEFT", frame.duration, "TOPLEFT", (pos-1)*53,0)
		t[pos]:SetHitRectInsets(-1, -25, -1, -1)
		t[pos].label = t[pos]:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t[pos].label:SetPoint("LEFT", t[pos], "RIGHT", 0, 0)
		t[pos].label:SetText(dur.."h")
		t[pos].dur = dur
		t[pos]:SetScript("OnClick", t.OnClick)
		if dur == t.selected then
			t[pos]:SetChecked(true)
		else
			t[pos]:SetChecked(false)
		end
	end

	frame.stacks = CreateFrame("Frame", "AucAdvSimpFrameStacks", frame, BackdropTemplateMixin and "BackdropTemplate")
	frame.stacks:SetPoint("TOPLEFT", frame.duration, "BOTTOMLEFT", 0, -20)
	frame.stacks:SetWidth(140)
	frame.stacks:SetHeight(20)
	frame.stacks.label = frame.duration:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.stacks.label:SetPoint("BOTTOMLEFT", frame.stacks, "TOPLEFT", 0, 0)
	frame.stacks.label:SetText("Stacks: (number x size)");

	frame.stacks.num = CreateFrame("EditBox", "AucAdvSimpFrameStackNum", frame.stacks, BackdropTemplateMixin and "BackdropTemplate" and "InputBoxTemplate")
	frame.stacks.num:SetPoint("TOPLEFT", frame.stacks, "TOPLEFT", 5, 0)
	frame.stacks.num:SetAutoFocus(false)
	frame.stacks.num:SetHeight(18)
	frame.stacks.num:SetWidth(40)
	frame.stacks.num:SetNumeric(true)
	frame.stacks.num:SetScript("OnTextChanged", function() frame.CurItem.valuechanged = true end)

	frame.stacks.mult = frame.duration:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.stacks.mult:SetPoint("BOTTOMLEFT", frame.stacks.num, "BOTTOMRIGHT", 5, 0)
	frame.stacks.mult:SetText("x")

	frame.stacks.size = CreateFrame("EditBox", "AucAdvSimpFrameStackSize", frame.stacks, BackdropTemplateMixin and "BackdropTemplate" and "InputBoxTemplate")
	frame.stacks.size:SetPoint("TOPLEFT", frame.stacks.num, "TOPRIGHT", 20, 0)
	frame.stacks.size:SetAutoFocus(false)
	frame.stacks.size:SetHeight(18)
	frame.stacks.size:SetWidth(30)
	frame.stacks.size:SetNumeric(true)
	frame.stacks.size:SetScript("OnTextChanged", function() frame.CurItem.valuechanged = true end)

	frame.stacks.equals = frame.duration:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.stacks.equals:SetPoint("BOTTOMLEFT", frame.stacks.size, "BOTTOMRIGHT", 5, 0)
	frame.stacks.equals:SetText("= 0")

	frame.fees = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.fees:SetPoint("TOP", frame.stacks, "BOTTOM", 10, -2)
	frame.fees:SetWidth(150)
	frame.fees:SetJustifyV("TOP")
	frame.fees:SetJustifyH("CENTER")
	frame.fees:SetText("")
	frame.fees:SetTextColor(0,1,1)

	frame.options = CreateFrame("Frame", "AucAdvSimpFrameOptions", frame, BackdropTemplateMixin and "BackdropTemplate")
	frame.options:SetPoint("TOPLEFT", frame.stacks, "BOTTOMLEFT", 0, -40)
	frame.options:SetWidth(140)
	frame.options:SetHeight(300)
	frame.options.label = frame.options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.options.label:SetPoint("BOTTOMLEFT", frame.options, "TOPLEFT", 0, 0)
	frame.options.label:SetText("Options:")

	frame.create = CreateFrame("Button", "AucAdvSimpFrameCreate", frame, "OptionsButtonTemplate")
	frame.create:SetPoint("BOTTOMRIGHT", AuctionFrameMoneyFrame, "TOPRIGHT", -1, 10)
	frame.create:SetWidth(160)
	frame.create:SetText("Create Auction")
	frame.create:SetScript("OnClick", private.PostAuction)
	frame.create:Disable()

	frame.clear = CreateFrame("Button", "AucAdvSimpFrameRemember", frame, "OptionsButtonTemplate")
	frame.clear:SetPoint("TOPLEFT", AuctionFrameMoneyFrame, "TOPRIGHT", -1, 3)
	frame.clear:SetWidth(110)
	frame.clear:SetText("Clear Settings")
	frame.clear:SetScript("OnClick", function() private.ClearSetting() private.RemoveConfig() end)

	MoneyInputFrame_SetPreviousFocus(frame.minprice, frame.stacks.size)
	MoneyInputFrame_SetNextFocus(frame.minprice, AucAdvSimpFrameBuyoutGold)
	MoneyInputFrame_SetPreviousFocus(frame.buyout, AucAdvSimpFrameStartCopper)
	MoneyInputFrame_SetNextFocus(frame.buyout, frame.stacks.num)
	private.SetPrevNext(frame.stacks.num, AucAdvSimpFrameBuyoutCopper, frame.stacks.size)
	private.SetPrevNext(frame.stacks.size, frame.stacks.num, AucAdvSimpFrameStartGold)

	function frame.options:AddOption(option, text)
		local item = CreateFrame("CheckButton", "AucAdvSimpFrameOption_"..option, self, "OptionsCheckButtonTemplate")
		if self.last then
			item:SetPoint("TOPLEFT", self.last, "BOTTOMLEFT", 0,7)
		else
			item:SetPoint("TOPLEFT", self, "TOPLEFT", 0,0)
		end
		self.last = item

		item:SetHitRectInsets(-1, -140, 3, 3)
		item:SetScript("OnClick", function() frame.CurItem.valuechanged = true end)


		item.label = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		item.label:SetPoint("LEFT", item, "RIGHT", 0, 0)
		item.label:SetText(text)

		self[option] = item
	end

	frame.options:AddOption("matchmy", "Match my current")
	frame.options:AddOption("undercut", "Undercut competitors")
	frame.options:AddOption("remember", "Remember fixed price")

	function frame.ClickBagHook(_,_,self,button)
		if not (frame:IsVisible() and get("util.simpleauc.clickhook")) then return end
		local bag = self:GetParent():GetID()
		local slot = self:GetID()
		local link = GetContainerItemLink(bag, slot)
		local _, size = GetContainerItemInfo(bag, slot)
		if link then
			if (button == "LeftButton") and (IsAltKeyDown()) then
				private.LoadItemLink(link, size)
				--see if double clicking to auto post is allowed
				if (not get("util.simpleauc.clickhook.doubleclick")) then return end

				if not private.clickdata then private.clickdata = {} end
				local last = private.clickdata
				local now = GetTime()
				if last[1] == bag and last[2] == slot and now - last[3] < 0.5 then
					-- Is a double click
					aucPrint("Auto auctioning double-alt-clicked item")
					if not frame.options.remember:GetChecked() then
						frame.options.undercut:SetChecked(true)
					end
					private.CheckUpdate()
					private.PostAuction()
				end
				last[1] = bag
				last[2] = slot
				last[3] = now
			end
		end
	end

	frame.tab = CreateFrame("Button", "AuctionFrameTabUtilSimple", AuctionFrame, "AuctionTabTemplate")
	frame.tab:SetText(TAB_NAME)
	frame.tab:Show()
	PanelTemplates_DeselectTab(frame.tab)
	if get("util.simpleauc.displayauctiontab") then
		AucAdvanced.AddTab(frame.tab, frame)
	end

	function frame.tab.OnClick(self, _, index)
		if not index then index = self:GetID() end
		local tab = _G["AuctionFrameTab"..index]
		if (tab and tab:GetName() == "AuctionFrameTabUtilSimple") then
			AuctionFrameTopLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft")
			AuctionFrameTop:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Top")
			AuctionFrameTopRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopRight")
			AuctionFrameBotLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotLeft")
			AuctionFrameBot:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Bot")
			AuctionFrameBotRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotRight")
			AuctionFrameMoneyFrame:Show()
			frame:Show()
			private.UpdateDisplay() -- update for any bag changes while frame was hidden
		else
			AuctionFrameMoneyFrame:Show()
			frame:Hide()
		end
	end

	frame.imageview = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate")
	frame.imageview:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})

	frame.imageview:SetBackdropColor(0, 0, 0, 1)
	frame.imageview:SetPoint("TOPLEFT", frame, "TOPLEFT", 185, -100)
	frame.imageview:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, 0)
	frame.imageview:SetPoint("BOTTOM", frame, "BOTTOM", 0, 35)
	--records the column width changes
	--store width by header name, that way if column reorginizing is added we apply size to proper column
	function private.onResize(self, column, width)
		if not width then
			set("util.simpleauc.columnwidth."..self.labels[column]:GetText(), "default") --reset column if no width is passed. We use CTRL+rightclick to reset column
			self.labels[column].button:SetWidth(get("util.simpleauc.columnwidth."..self.labels[column]:GetText()))
		else
			set("util.simpleauc.columnwidth."..self.labels[column]:GetText(), width)
		end
	end
	function private.onClick(button, row, index)

	end

	private.buyselection = {}
	function private.onSelect()
		if frame.imageview.sheet.prevselected ~= frame.imageview.sheet.selected then
			frame.imageview.sheet.prevselected = frame.imageview.sheet.selected
			local selected = frame.imageview.sheet:GetSelection()
			if (not selected) or (not selected[10]) then
				private.buyselection = {}
				frame.buy:Disable()
				frame.bid:Disable()
			else
				private.buyselection.link = selected[10]
				private.buyselection.seller = selected[1]
				private.buyselection.stack = selected[3]
				private.buyselection.minbid = selected[7]
				private.buyselection.curbid = selected[8]
				private.buyselection.buyout = selected[9]

				-- Make sure that it's not one of our auctions
				if (not AucAdvancedConfig["users."..Const.PlayerRealm.."."..private.buyselection.seller]) then
					if private.buyselection.buyout and (private.buyselection.buyout > 0) then
						frame.buy:Enable()
					else
						frame.buy:Disable()
					end

					if private.buyselection.minbid then
						frame.bid:Enable()
					else
						frame.bid:Disable()
					end
				else
					frame.buy:Disable()
					frame.bid:Disable()
				end
			end
		end
	end

	function private.BuyAuction()
		QueueBuy(private.buyselection.link, private.buyselection.seller, private.buyselection.stack, private.buyselection.minbid, private.buyselection.buyout, private.buyselection.buyout)
		frame.imageview.sheet.selected = nil
		private.onSelect()
	end

	function private.BidAuction()
		local bid = private.buyselection.minbid
		if private.buyselection.curbid and private.buyselection.curbid > 0 then
			bid = ceil(private.buyselection.curbid*1.05)
		end
		QueueBuy(private.buyselection.link, private.buyselection.seller, private.buyselection.stack, private.buyselection.minbid, private.buyselection.buyout, bid)
		frame.imageview.sheet.selected = nil
		private.onSelect()
	end


	frame.imageview.sheet = ScrollSheet:Create(frame.imageview, {
		{ "Seller", "TEXT", get("util.simpleauc.columnwidth.Seller")}, --89
		{ "Left",   "INT",  get("util.simpleauc.columnwidth.Left")}, --32
		{ "Stk",    "INT",  get("util.simpleauc.columnwidth.Stk")}, --32
		{ "Min/ea", "COIN", get("util.simpleauc.columnwidth.Min/ea"), { DESCENDING=true } }, --65
		{ "Cur/ea", "COIN", get("util.simpleauc.columnwidth.Cur/ea"), { DESCENDING=true } }, --65
		{ "Buy/ea", "COIN", get("util.simpleauc.columnwidth.Buy/ea"), { DESCENDING=true, DEFAULT=true } }, --65
		{ "MinBid", "COIN", get("util.simpleauc.columnwidth.MinBid"), { DESCENDING=true } }, --76
		{ "CurBid", "COIN", get("util.simpleauc.columnwidth.CurBid"), { DESCENDING=true } }, --76
		{ "Buyout", "COIN", get("util.simpleauc.columnwidth.Buyout"), { DESCENDING=true } }, --80
		{ "", "TEXT", get("util.simpleauc.columnwidth.BLANK")}, --Hidden column to carry the link --0
	}, nil, nil, private.onClick, private.onResize, private.onSelect)
	frame.imageview.sheet:EnableSelect(true)

	frame.config = CreateFrame("Button", nil, frame, "OptionsButtonTemplate")
	frame.config:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -13)
	frame.config:SetText("Configure")
	frame.config:SetScript("OnClick", function()
		AucAdvanced.Settings.Show()
		private.gui:ActivateTab(private.guiId)
	end)

	frame.scanbutton = CreateFrame("Button", "AucAdvScanButton", AuctionFrameBrowse, "OptionsButtonTemplate")
	frame.scanbutton:SetText("Scan")
	frame.scanbutton:SetParent("AuctionFrameBrowse")
	frame.scanbutton:SetPoint("LEFT", "AuctionFrameMoneyFrame", "RIGHT", 5,0)
	frame.scanbutton:SetScript("OnClick", function()
		if not AucIsScanning() then
			local filterData = AucAdvanced.Scan.QueryFilterFromIndex(AuctionFrameBrowse.selectedCategoryIndex, AuctionFrameBrowse.selectedSubCategoryIndex, AuctionFrameBrowse.selectedSubSubCategoryIndex)
			StartScan(nil, nil, nil, nil, nil, nil, nil, filterData)
		end
	end)

	frame.refresh = CreateFrame("Button", nil, frame, "OptionsButtonTemplate")
	frame.refresh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -167,15)
	frame.refresh:SetText("Refresh")
	frame.refresh:SetWidth(80)
	frame.refresh:SetScript("OnClick", private.Refresh)

	frame.bid = CreateFrame("Button", nil, frame, "OptionsButtonTemplate")
	frame.bid:SetPoint("TOPLEFT", frame.refresh, "TOPRIGHT", 1, 0)
	frame.bid:SetWidth(80)
	frame.bid:SetText("Bid")--Bid
	frame.bid:SetScript("OnClick", private.BidAuction)
	frame.bid:Disable()

	frame.buy = CreateFrame("Button", nil, frame, "OptionsButtonTemplate")
	frame.buy:SetPoint("TOPLEFT", frame.bid, "TOPRIGHT", 1, 0)
	frame.buy:SetWidth(80)
	frame.buy:SetText("Buy")--Buy
	frame.buy:SetScript("OnClick", private.BuyAuction)
	frame.buy:Disable()

	if get("util.simpleauc.scanbutton") then
		frame.scanbutton:Show()
	else
		frame.scanbutton:Hide()
	end

	Stubby.RegisterFunctionHook("ContainerFrameItemButton_OnModifiedClick", -300, frame.ClickBagHook)
	hooksecurefunc("AuctionFrameTab_OnClick", frame.tab.OnClick)

	hooksecurefunc("SetItemRef", function (shortlink, hyperlink, mousebutton, chatframe)
		if mousebutton == "LeftButton" and IsAltKeyDown() and frame:IsVisible() and get("util.simpleauc.clickhook") then
			local link = hyperlink or shortlink
			if link then
				private.LoadItemLink(link)
			end
		end
	end)

	function frame:OnEvent(event, ...)
		if event == "BAG_UPDATE" then
			if frame:IsVisible() then
				private.UpdateDisplay()
			end
		end
	end

	frame:SetScript("OnEvent", frame.OnEvent)
	frame:RegisterEvent("BAG_UPDATE")
end

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/Modules/Auc-Util-SimpleAuction/SimpFrame.lua $", "$Rev: 6643 $")
