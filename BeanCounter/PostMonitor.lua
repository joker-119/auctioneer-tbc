--[[
	Auctioneer Addon for World of Warcraft(tm).
	Version: 1.13.6609 (SwimmingSeadragon)
	Revision: $Id: PostMonitor.lua 6609 2021-01-30 13:42:33Z none $
	URL: http://auctioneeraddon.com/

	PostMonitor - Records items posted up for auction

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
LibStub("LibRevision"):Set("$URL: BeanCounter/PostMonitor.lua $","$Rev: 6609 $","5.1.DEV.", 'auctioneer', 'libs')

--[[Most of this code is from BC classic]]--
local libName = "BeanCounter"
local libType = "Util"
local lib = BeanCounter
local private, print, get, set, _BC = lib.getLocals()

local function debugPrint(...)
    if get("util.beancounter.debugPost") then
        private.debugPrint("PostMonitor",...)
    end
end

-- need to know if we're using Classic or Modern version
local MINIMUM_CLASSIC = 11300
local MAXIMUM_CLASSIC = 19999
-- version, build, date, tocversion = GetBuildInfo()
local _,_,_,tocVersion = GetBuildInfo()
lib.isClassic = (tocVersion > MINIMUM_CLASSIC and tocVersion < MAXIMUM_CLASSIC)


-------------------------------------------------------------------------------
-- Called before PostAuction()
-------------------------------------------------------------------------------
local nameMulti, countMulti, minBidMulti, buyoutPriceMulti, runTimeMulti, depositMulti --these store the last auction for the new Multi auction processor added in wow 3.3.3
function private.prePostAuctionHook(_, _, minBid, buyoutPrice, runTime, count, stackNumber)
	local name, texture, countSlotted, quality, canUse, price = GetAuctionSellItemInfo()
	--debugPrint("1",minBid, buyoutPrice,"Prehook Fired, starting auction creation", name, count)

	--For compatibility with auction addons that dont pass a count/not multisell aware
	if not count then count = countSlotted end

	if (name and count) then
		--Look in the bags find the locked item so we can get the itemlink, we also check if this is a multipost can this stack cover it
		local itemLink, selectedStackCount
		for bagID = 0, 4 do
			local bagSlots = GetContainerNumSlots(bagID)
			for  slot = 1, bagSlots do
				local  _, selectedStack, locked, _, _ = GetContainerItemInfo(bagID, slot)
				if locked then
					local link = GetContainerItemLink(bagID, slot)
					if link and strfind(link, name, 1, true) then
						itemLink = link
						selectedStackCount = selectedStack or 0
						break
					end
				end
			end
		end

		if not itemLink then
			debugPrint("Could not find matching locked item in bags for", name)
			return
		end

		local deposit = GetAuctionDeposit (runTime, minBid, buyoutPrice, count, 1)
		debugPrint(itemLink, "deposit", deposit, "for", count, "x", stackNumber, "duration", runTime)

		--TEMP PATCH to fix run time changes till I can change teh mail lua to work with new system
        if lib.isClassic then
            if runTime == 1 then runTime = 120 end
            if runTime == 2 then runTime = 480 end
            if runTime == 3 then runTime = 1440 end
        else
            if runTime == 1 then runTime = 720 end
            if runTime == 2 then runTime = 1440 end
            if runTime == 3 then runTime = 2880 end
        end

		nameMulti, countMulti, minBidMulti, buyoutPriceMulti, runTimeMulti, depositMulti = name, count, minBid, buyoutPrice, runTime, deposit
		--Multipost is used when more than 1 stack is posted or when the selected stack is too small to post the stacksize
		if stackNumber and (stackNumber > 1 or count > selectedStackCount) then
			debugPrint("Using the multipost route stackNumber=", stackNumber, "count=", count , "selectedStackCount=", selectedStackCount)
			private.multipostStart(itemLink, count, stackNumber, selectedStackCount)
		else
			private.addPendingPost(itemLink, name, count, minBid, buyoutPrice, runTime, deposit)
		end
	end
end

-------------------------------------------------------------------------------
-- Adds a pending post to the queue.
-------------------------------------------------------------------------------
function private.addPendingPost(itemLink, name, count, minBid, buyoutPrice, runTime, deposit)
	-- Add a pending post to the queue.
	local pendingPost = {}
	pendingPost.itemLink = itemLink
	pendingPost.name = name
	pendingPost.count = count
	pendingPost.minBid = minBid
	pendingPost.buyoutPrice = buyoutPrice
	pendingPost.runTime = runTime
	pendingPost.deposit = deposit
	table.insert(private.PendingPosts, pendingPost)
	--debugPrint("2",minBid, buyoutPrice, "private.addPendingPost() - Added pending post", itemLink)

	-- Register for the response events if this is the first pending post.
	if (#private.PendingPosts == 1) then
		private.postEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
		private.postEventFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

-------------------------------------------------------------------------------
-- Removes the pending post from the queue.
-------------------------------------------------------------------------------
function private.removePendingPost()
	if (#private.PendingPosts > 0) then
		-- Remove the first pending post.
		local post = private.PendingPosts[1]
		table.remove(private.PendingPosts, 1)

		-- Unregister for the response events if this is the last pending post.
		if (#private.PendingPosts == 0) then
			private.postEventFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
			private.postEventFrame:UnregisterEvent("UI_ERROR_MESSAGE")
		end

		return post
	end

	-- No pending post to remove!
	return nil
end

-------------------------------------------------------------------------------
-- Called when a post is accepted by the server.
-------------------------------------------------------------------------------
function private.onAuctionCreated()
	local post = private.removePendingPost()
	-- Add to sales database
	if post and post.itemLink then
		local itemID = lib.API.decodeLink(post.itemLink)
		local text = private.packString(post.count, post.minBid, post.buyoutPrice, post.runTime, post.deposit, time(),"")

		private.databaseAdd("postedAuctions", post.itemLink, nil, text)

		--debugPrint("3", post.minBid, post.buyoutPrice, #private.PendingPosts,  "Added", post.itemLink, "to the postedAuctions DB")
	elseif post and not post.itemLink then
		debugPrint("ItemLink failure for the following auction.")
		debugPrint(post.name, post.count, post.minBid, post.buyoutPrice, post.runTime, post.deposit)
	end
end

-------------------------------------------------------------------------------
-- Called when a post is rejected by the server.
-------------------------------------------------------------------------------
function private.onPostFailed()
	private.removePendingPost()
end
--------------------------------------------------------------------------------
-- Called when the Multi auction feature is used in patch 3.3.3
--------------------------------------------------------------------------------
function private.onMultiPost(current, total)
	if private.multipostScan2 and #private.multipostScan2 > 0 then
		local link = private.multipostScan2[1]
		debugPrint(#private.multipostScan2, "added", current, "of", total, link, nameMulti, countMulti, minBidMulti, buyoutPriceMulti, runTimeMulti, depositMulti)
		private.addPendingPost(link, nameMulti, countMulti, minBidMulti, buyoutPriceMulti, runTimeMulti, depositMulti)
		table.remove (private.multipostScan2, 1)
	end
end

-------------------------------------------------------------------------------
-- Use event scripts instead of function hooks to know when a auction has been accepted
-- OnEvent handler these are unhooked when not needed
-------------------------------------------------------------------------------
function private.postEvent(_, event, message, message2, ...)
	if event == "CHAT_MSG_SYSTEM" and message == ERR_AUCTION_STARTED and private.PendingPosts then
		private.onAuctionCreated()
	elseif event == "UI_ERROR_MESSAGE" and message2 == ERR_NOT_ENOUGH_MONEY then
		private.onPostFailed()
	elseif event =="AUCTION_MULTISELL_UPDATE" then
		private.onMultiPost(message, message2, ...)
	--elseif event =="AUCTION_MULTISELL_FAILURE" then
	--so far no need for this event, this can occur before the last posted item has cleared beancounter
	end
end
private.postEventFrame = CreateFrame("Frame", BackdropTemplateMixin and "BackdropTemplate")
private.postEventFrame:SetScript("OnEvent", private.postEvent)
--private.postEventFrame:RegisterEvent("AUCTION_MULTISELL_START")
private.postEventFrame:RegisterEvent("AUCTION_MULTISELL_UPDATE")
--private.postEventFrame:RegisterEvent("AUCTION_MULTISELL_FAILURE")

function private.multipostStart(itemLink, count, stack, selectedStackCount)
	--print(itemLink, count, stack, selectedStackCount)
	private.multipostScan2 = {}

	local itemID = lib.API.decodeLink(itemLink)
	local total = count * stack

	--check if user selected stack is large enough to post the item. Multipost will use the selected stack if possible or a bag scan if not
	if selectedStackCount >= total then
		private.multipostScan1 = { {count =  selectedStackCount, link = itemLink} }
		private.convertToStacks(count) --convert it into a stacks table
	else --ignore user selection and scan bags
		private.bagSnapshot( itemID, total)
		--for i,v in ipairs(private.multipostScan1) do
		--	print(v.count,v.link)
		--end
		private.convertToStacks(count)
		for i,v in ipairs(private.multipostScan2) do
			debugPrint("|CFFF0AA00",i,v)
		end
		--now we have a formatted table
		--If there is only 1 stack to post but the stack choosen is too small we need to force it throu No Multipost events for this situation
		if count > selectedStackCount and stack == 1 then
			--in this case multipost never fires a event
			private.onMultiPost(1, 1)
		end
	end
end
private.multipostScan1 = {}
private.multipostScan2 = {}
function private.convertToStacks(postsize)
	local currentStack = private.multipostScan1[1]
	--print(currentStack.count)
	local nextStack = private.multipostScan1[2]
	--if greater or equal we subtract from current stack
	if currentStack.count >= postsize then
		--print("--ok send out this itemlink")
		table.insert(private.multipostScan2, currentStack.link)
		--subtract count used
		currentStack.count = currentStack.count - postsize
		--is this 0 now
		if nextStack and currentStack.count == 0 then
			table.remove(private.multipostScan1, 1)
		end

	elseif nextStack then --count is too low so borrow from next stack
		local diff = postsize - currentStack.count --this is how many we need to get a stack
		--is next stack large enough?
		if nextStack.count - diff > 0 then
			nextStack.count = nextStack.count - diff --subtract from next
			currentStack.count = currentStack.count + diff --add to current stack
		else
			currentStack.count = currentStack.count + nextStack.count --add what we can
			table.remove(private.multipostScan1, 2) --this stack has been destroyed so remove
		end
	else--should only hit here when all data has proccessed
		--print("finsihed with dataset")
		return
	end
	--if we still have data then we need to process it
	private.convertToStacks(postsize)
end

function private.bagSnapshot( itemBeingPosted, totalQuanity)
	private.multipostScan1 = {}
	local counter = 0
	local  stop
	for bagID = 0, 4 do
		local slots = GetContainerNumSlots(bagID)
		for slot = 1, slots do
			local link = GetContainerItemLink(bagID, slot)
			local texture, itemCount, locked, quality, readable = GetContainerItemInfo(bagID, slot)
			local itemID, _, ID = lib.API.decodeLink(link)


			if link and itemID == itemBeingPosted then
				table.insert(private.multipostScan1, 1, {count =  itemCount, link = link})
				counter = counter + itemCount
				--print(link, "|CFFFFFAAA", ID, slot,  itemCount, totalQuanity, counter)
				if counter >= totalQuanity then
					BeanCounterAccountDB = private.multipostScan1
					break
				end
			end
		end
	end
end
