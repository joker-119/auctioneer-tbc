--[[
	Auctioneer - Basic Auction Posting
	Version: 1.13.6643 (SwimmingSeadragon)
	Revision: $Id: AucSimple.lua 6643 2021-01-30 13:42:33Z none $
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

local libType, libName = "Util", "SimpleAuction"
local lib,parent,private = AucAdvanced.NewModule(libType, libName)
if not lib then return end
local aucPrint,decode,_,_,replicate,empty,get,set,default,debugPrint,fill = AucAdvanced.GetModuleLocals()
local Const = AucAdvanced.Const
local Resources = AucAdvanced.Resources
local GetSigFromLink = AucAdvanced.API.GetSigFromLink
local GetMarketValue = AucAdvanced.API.GetMarketValue

local WHITEOFFSETA = "  " -- 2 spaces: standard tooltip offset
local WHITEOFFSETB = "      " -- 6 spaces: deep tooltip offset

local data, _
local ownResults = {}
local ownCounts = {}

lib.Processors = {}
function lib.Processors.itemtooltip(callbackType, ...)
	lib.ProcessTooltip(...)
end
lib.Processors.battlepettooltip = lib.Processors.itemtooltip

function lib.Processors.auctionui(callbackType, ...)
	private.CreateFrames(...)
end

function lib.Processors.config(callbackType, ...)
	private.SetupConfigGui(...)
end

function lib.Processors.configchanged(callbackType, ...)
	private.UpdateConfig(...)
end

function lib.Processors.scanstats(callbackType, ...)
	private.clearcache()
	private.delayedUpdatePricing = true -- Note: calling private.UpdatePricing is unsafe inside "scanstats"
end

function lib.Processors.postresult(callbackType, ...)
	private.clearcache()
end
lib.Processors.auctionclose = lib.Processors.postresult
lib.Processors.serverkey = lib.Processors.postresult

-- Fetch settingstr for the specified id
-- Temporary function used during our process of conversion to connected realms and new-style serverKey
-- This will slowly convert settings using the old-style serverKey to new-style as they are used
-- However this will likely never completely remove all old-style strings, we will have to do some extra work at a later date to deal with them
-- There is no equivalent to set this setting: should always use set("util.simpleauc."..Resources.ServerKey.."."..id, settingstr)
local function GetSettingStr(id)
	local settingstr = get("util.simpleauc."..Resources.ServerKey.."."..id)
	if settingstr then return settingstr end
	-- see if it's stored under old-style serverKey
	settingstr = get("util.simpleauc."..Const.CompactRealm.."."..id)
	if settingstr then
		set("util.simpleauc."..Resources.ServerKey.."."..id, settingstr, true) -- silent (3rd param 'true' inhibits "configchanged" messages)
		set("util.simpleauc."..Const.CompactRealm.."."..id, nil, true)
		return settingstr
	end
end
private.GetSettingStr = GetSettingStr -- SimpFrame.lua needs this function too

function lib.ProcessTooltip(tooltip, link, serverKey, quantity, decoded, additional, order)
	if not get("util.simpleauc.tooltip") then return end
	if serverKey ~= Resources.ServerKey then return end -- SimpleAuction can only handle pricing for current ServerKey
	local id = GetSigFromLink(link)
	local settingstr = GetSettingStr(id)
	local market, seen, fixbuy, fixbid, stack
	local imgseen, image, matchBid, matchBuy, lowBid, lowBuy, aSeen, aveBuy = private.GetItems(link)
	local reason = "Market"

	tooltip:SetColor(0.4, 1.0, 0.9)

	market, seen = GetMarketValue(link)
	if (not market) or (market <= 0) or (not (seen > 5 or aSeen < 3)) then
		market = aveBuy
		reason = "Current"
	end
	if (not market or market <= 0) and GetSellValue then
		local vendor = GetSellValue(link)
		if vendor and vendor > 0 then
			market = vendor * 3
			reason = "Vendor markup"
		end
	end
	if not market or market <= 0 then
		market = 0
		reason = "No data"
	end

	local coinsBid, coinsBuy, coinsBidEa, coinsBuyEa = "no","no","no","no"
	if market > 0 then
		coinsBid = private.coins(market*0.8*quantity)
		coinsBidEa = private.coins(market*0.8)
		coinsBuy = private.coins(market*quantity)
		coinsBuyEa = private.coins(market)
	end
	if quantity == 1 then
		local text = format("%s: %s bid/%s buyout", libName, coinsBid, coinsBuy)
		tooltip:AddLine(text)
	else
		local text = format("%s x%d: %s bid/%s buyout", libName, quantity, coinsBid, coinsBuy)
		local textea =  format("%sOr individually: %s/%s", WHITEOFFSETB, coinsBidEa, coinsBuyEa)
		tooltip:AddLine(text)
		tooltip:AddLine(textea, 0.3, 0.8, 0.7)
	end
	if settingstr then
		fixbid, fixbuy, _, _, stack = strsplit(":", settingstr)
		fixbid, fixbuy, stack = tonumber(fixbid), tonumber(fixbuy), tonumber(stack)
		fixbid = ceil(fixbid/stack)
		fixbuy = ceil(fixbuy/stack)
	end

	if fixbid then
		coinsBuy = "no"
		coinsBid = private.coins(fixbid*quantity)
		if fixbuy then
			coinsBuy = private.coins(fixbuy*quantity)
		end
		if quantity == 1 then
			local text = format("%sFixed: %s bid/%s buyout", WHITEOFFSETB, coinsBid, coinsBuy)
			tooltip:AddLine(text)
		else
			local text = format("%sFixed x%d: %s bid/%s buyout", WHITEOFFSETB, quantity, coinsBid, coinsBuy)
			tooltip:AddLine(text)
		end
	end
	if get("util.simpleauc.tooltip.undercut") then
		if lowBid and lowBid > 0 then
			coinsBuy = "no"
			coinsBid = private.coins(lowBid*quantity)
			if lowBuy and lowBuy > 0 then
				coinsBuy = private.coins(lowBuy*quantity)
			end
			if quantity == 1 then
				local text = format("%sUndercut: %s bid/%s buyout", WHITEOFFSETA, coinsBid, coinsBuy)
				tooltip:AddLine(text)
			else
				local text = format("%sUndercut x%d: %s bid/%s buyout", WHITEOFFSETA, quantity, coinsBid, coinsBuy)
				tooltip:AddLine(text)
			end
		else
			tooltip:AddLine("  No Competition")
		end
	end
end

function lib.OnLoad()
	--Default sizes for the scrollframe column widths
	default("util.simpleauc.columnwidth.Seller", 89)
	default("util.simpleauc.columnwidth.Left", 32)
	default("util.simpleauc.columnwidth.Stk", 32 )
	default("util.simpleauc.columnwidth.Min/ea", 65)
	default("util.simpleauc.columnwidth.Cur/ea", 65)
	default("util.simpleauc.columnwidth.Buy/ea", 65)
	default("util.simpleauc.columnwidth.MinBid", 76)
	default("util.simpleauc.columnwidth.CurBid", 76)
	default("util.simpleauc.columnwidth.Buyout", 80)
	default("util.simpleauc.columnwidth.BLANK", 0.05)
	--Default options
	default("util.simpleauc.clickhook", true)
	default("util.simpleauc.clickhook.doubleclick", false)
	default("util.simpleauc.scanbutton", true)
	default("util.simpleauc.tooltip", true)
	default("util.simpleauc.tooltip.undercut", true)
	if AucAdvanced.Classic then
		default("util.simpleauc.auto.duration", 24)
	else
		default("util.simpleauc.auto.duration", 48)
	end
	default("util.simpleauc.auto.match", true)
	default("util.simpleauc.auto.undercut", true)
	default("util.simpleauc.undercut", "percent")
	default("util.simpleauc.undercut.fixed", 1)
	default("util.simpleauc.undercut.percent", 2.5)
	default("util.simpleauc.displayauctiontab", true)

	-- Removed setting
	set("util.simpleauc.scanbutton.disable.wowecon", nil, true)
end

function private.UpdateConfig(setting, value)
	if private.frame then
		local frame = private.frame
		if get("util.simpleauc.scanbutton") then
			frame.scanbutton:Show()
		else
			frame.scanbutton:Hide()
		end
		if setting == "util.simpleauc.displayauctiontab" then
			if value then
				AucAdvanced.AddTab(private.frame.tab, private.frame)
			else
				AucAdvanced.RemoveTab(private.frame.tab, private.frame)
			end
		end
	end
end

local timeLeftList = { {12, "12 hour"}, {24, "24 hour"}, {48, "48 hour"} }

if AucAdvanced.Classic then
    timeLeftList = { {2, "2 hour"}, {8, "8 hour"}, {24, "24 hour"} }
end

function private.SetupConfigGui(gui)
	local id = gui:AddTab(lib.libName, lib.libType.." Modules")
	gui:MakeScrollable(id)
	private.gui = gui
	private.guiId = id

	gui:AddHelp(id, "what simpleauc",
		"What is SimpleAuction?",
		"Simple Auction is a simplified, more automated way of posting items. It focuses it's emphasis on easy pricing and maximum sale speed with a minimum of configuration options and learning curve.\n"..
		"It won't get you maximium profit, or ultimate configurability, but the values it provides are reasonable in most circumstances and it is primarily very easy to use.\n")

	gui:AddControl(id, "Header",       0,    lib.libName.." options")

	gui:AddControl(id, "Subhead",      0,    "")
	gui:AddControl(id, "Checkbox",     0, 1, "util.simpleauc.displayauctiontab", "Show Post tab at the Auction House")
	gui:AddTip(id, "Shows simple post tab on the auction house")

	gui:AddControl(id, "Subhead",      0,    "Tooltip")
	gui:AddControl(id, "Checkbox",     0, 1, "util.simpleauc.tooltip", "Show prices in tooltip")
	gui:AddTip(id, "Shows market price for the current item in the tooltip")
	gui:AddControl(id, "Checkbox",     0, 2, "util.simpleauc.tooltip.undercut", "Show undercut prices in tooltip")
	gui:AddTip(id, "Shows potential undercut price for the current item in the tooltip")

	gui:AddControl(id, "Subhead",      0,    "Shortcuts")
	gui:AddControl(id, "Checkbox",     0, 1, "util.simpleauc.clickhook", "Allow alt-click item in bag instead of drag")
	gui:AddTip(id, "Enables an alt-click mouse-hook so you can alt-click your inventory items into the SimpleAuction post frame")
	gui:AddControl(id, "Checkbox",     0, 2, "util.simpleauc.clickhook.doubleclick", "Allow double-alt-clicking to auto-post the item")
	gui:AddTip(id, "If you alt-click twice in succession, the item will be posted automatically at the current price")

	gui:AddControl(id, "Subhead",      0,    "Defaults")
	gui:AddControl(id, "Checkbox",     0, 1, "util.simpleauc.auto.match", "Automatically match your current price if not remembering item price")
	gui:AddTip(id, "When items are posted, if there is no remembered price, and you currently have auctioning items, your current price will be matched")
	gui:AddControl(id, "Checkbox",     0, 1, "util.simpleauc.auto.undercut", "Automatically undercut the current price if not matching or remembering")
	gui:AddTip(id, "When items are posted, if there is no remembered price and the item is not automatching, the competition will be undercut")
	gui:AddControl(id, "Label",        0, 1, nil, "Automatically set the duration for an item unless remembering:")
	gui:AddControl(id, "Selectbox",    0, 2, timeLeftList, "util.simpleauc.auto.duration")
	gui:AddTip(id, "When items are posted, if there is no remembered price, the duration will default to this value")

	gui:AddControl(id, "Subhead",      0,    "Defaults")
	gui:AddControl(id, "Label",        0, 1, nil, "Undercut basis:")
	gui:AddControl(id, "Selectbox",    0, 2, {{"fixed", "Fixed value"}, {"percent", "Percentage"}}, "util.simpleauc.undercut")
	gui:AddTip(id, "When the auction is to be undercut, specify how you want the lowest price to be undercut")
	gui:AddControl(id, "Label",        0, 1, nil, "Fixed undercut value amount:")
	gui:AddControl(id, "MoneyFramePinned", 0, 2, "util.simpleauc.undercut.fixed", 0, AucAdvanced.Const.MAXBIDPRICE)
	gui:AddTip(id, "This is the fixed amount to undercut the lowest auction by")
	gui:AddControl(id, "Label",        0, 1, nil, "Percentage undercut amount:")
	gui:AddControl(id, "NumeriWide", 0, 3, "util.simpleauc.undercut.percent", 0,100, 0.5, "Percentage: %s%%")
	gui:AddTip(id, "This is the percentage to undercut the lowest auction by")

	gui:AddControl(id, "Subhead",      0,    "Scan button")
	gui:AddControl(id, "Checkbox",     0, 1, "util.simpleauc.scanbutton", "Show big red scan button at bottom of browse window")
	gui:AddTip(id, "Displays the old-style \"Scan\" button at the bottom of the browse window.")
end

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/Modules/Auc-Util-SimpleAuction/AucSimple.lua $", "$Rev: 6643 $")
