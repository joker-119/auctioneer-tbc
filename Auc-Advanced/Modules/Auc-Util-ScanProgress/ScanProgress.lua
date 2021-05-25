--[[
	Auctioneer - Price Level Utility module
	Version: 1.13.6591 (SwimmingSeadragon)
	Revision: $Id: ScanProgress.lua 6591 2021-01-30 13:42:33Z none $
	URL: http://auctioneeraddon.com/

	This is an Auctioneer module that adds a textual scan progress
	indicator to the Auction House UI.

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

local libType, libName = "Util", "ScanProgress"
local lib,parent,private = AucAdvanced.NewModule(libType, libName)
if not lib then return end
local print,decode,_,_,replicate,empty,get,set,default,debugPrint,fill,_TRANS = AucAdvanced.GetModuleLocals()

function lib.Processor(callbackType, ...)
	if (callbackType == "scanprogress") then
		private.UpdateScanProgress(...)
	elseif (callbackType == "config") then
		private.SetupConfigGui(...)
	elseif (callbackType == "configchanged") then
		private.ConfigChanged(...)
	end
end

lib.Processors = {}
function lib.Processors.scanprogress(callbackType, ...)
	private.UpdateScanProgress(...)
end

function lib.Processors.config(callbackType, ...)
	private.SetupConfigGui(...)
end

function lib.Processors.configchanged(callbackType, ...)
	private.ConfigChanged(...)
end



function lib.OnLoad()
	--print("AucAdvanced: {{"..libType..":"..libName.."}} loaded!")
	AucAdvanced.Settings.SetDefault("util.scanprogress.activated", true)
	AucAdvanced.Settings.SetDefault("util.scanprogress.leaveshown", true)
end

----  Functions to manage the progress indicator ----
private.scanStartTime = time()
private.scanProgressFormat = "Auctioneer Advanced: %s\nScanning page %d of %d\n\nAuctions per second: %.2f\nAuctions expected: %d\nAuctions scanned thus far: %d (%3.1f%%)\n\nElapsed scan time: %s\nEstimated time left: %s\n%s"
private.scanCompleteFormat = "Auctioneer Advanced: %s\nScan Complete\n\nAuctions per second: %.2f\nAuctions expected: %d\nAuctions scanned: %d (%3.1f%%)\n\nElapsed scan time: %s\n%s"

function private.UpdateScanProgress(state, totalAuctions, scannedAuctions, elapsedTime, page, maxPages, query, scanCount)
	--Check that we're enabled before passing on the callback
	if not AucAdvanced.Settings.GetSetting("util.scanprogress.activated")

	--Check to see if browseoverride has been set, if so gracefully allow it to continue as is
	or AucAdvanced.Settings.GetSetting("util.browseoverride.activated") then
		state = false
	end

	--Change the state if we have not scanned any auctions yet.
	--This is done so that we don't start the timer too soon and thus get skewed numbers
	if (state == nil and (
		not scannedAuctions or
		scannedAuctions == 0 or
		not AucAdvanced.API.IsBlocked() or
		BrowseButton1:IsVisible()
	)) then
		state = true
	end

	--Distribute the callback according to the value of the state variable
	if (state == false) then
		if AucAdvanced.API.IsBlocked() then
			private.HideScanProgressUI()
		end
		return
	elseif (state == true) then
		private.ShowScanProgressUI(totalAuctions)
	end
	if scannedAuctions and scannedAuctions > 0 then
		private.UpdateScanProgressUI(totalAuctions, scannedAuctions, elapsedTime, page, maxPages, query, scanCount)
	end
end

local initShown = false
function private.ShowScanProgressUI(totalAuctions)
	if (nLog) then nLog.AddMessage("Auctioneer", "ScanProgress", N_INFO, "ShowScanProgressUI Called") end
	for i=1, NUM_BROWSE_TO_DISPLAY do
		_G["BrowseButton"..i]:Hide()
	end
	BrowseNoResultsText:Show()
	private.scanStartTime = time()
	local msg
	if totalAuctions and totalAuctions > 0 then
		msg = ("Scanning %d items..."):format(totalAuctions)
	else
		msg = "Scanning..."
	end
	BrowseNoResultsText:SetText(msg)
	initShown = msg.." DONE"
	AucAdvanced.API.BlockUpdate(true, true)
end

function private.HideScanProgressUI()
	if (nLog) then nLog.AddMessage("Auctioneer", "ScanProgress", N_INFO, "HideScanProgressUI Called") end

	if (AucAdvanced.Settings.GetSetting("util.scanprogress.leaveshown")) then
		if (initShown) then BrowseNoResultsText:SetText(initShown) end
		AucAdvanced.API.BlockUpdate(false, false)
	else
		BrowseNoResultsText:Hide()
		BrowseNoResultsText:SetText(SEARCHING_FOR_ITEMS)

		local numBatchAuctions, totalAuctions = GetNumAuctionItems("list")
		local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame)
		for i=1, NUM_BROWSE_TO_DISPLAY do
			index = offset + i + (NUM_AUCTION_ITEMS_PER_PAGE * AuctionFrameBrowse.page)
			if ( index > (numBatchAuctions + (NUM_AUCTION_ITEMS_PER_PAGE * AuctionFrameBrowse.page)) ) then
				_G["BrowseButton"..i]:Hide()
			else
				_G["BrowseButton"..i]:Show()
			end
		end
		AucAdvanced.API.BlockUpdate(false, true)
	end
	initShown = nil
end

function private.UpdateScanProgressUI(totalAuctions, scannedAuctions, elapsedTime, page, maxPages, query, scanCount)
	if (nLog) then nLog.AddMessage("Auctioneer", "ScanProgress", N_INFO, "UpdateScanProgressUI Called") end
	local numAuctionsPerPage = NUM_AUCTION_ITEMS_PER_PAGE
	local warningMessage = ""
	initShown = false
	-- Prefer the elapsed time which is provided by core and excludes paused time.
	local secondsElapsed = elapsedTime or (time() - private.scanStartTime)

	local auctionsToScan = totalAuctions - (page-1)*numAuctionsPerPage
	local missedAuctions = (page-1)*numAuctionsPerPage - scannedAuctions
	local currentPage = page
	local totalPages = maxPages

	if (currentPage <= totalPages) then
		if (missedAuctions > 10) then
			warningMessage = "Too many auctions have been missed.  This will be an incomplete scan."
		else
			if ((missedAuctions / page) * maxPages > 10) then
				warningMessage = "Missing auctions.  This is likely this will be an incomplete scan."
			end
		end
	else
		if (totalAuctions - scannedAuctions > 10) then
			warningMessage = "Too many auctions have been missed.  This will be an incomplete scan."
		end
	end

	local auctionsScannedPerSecond = scannedAuctions / secondsElapsed
	local secondsToScanCompletion = auctionsToScan / auctionsScannedPerSecond
	if (currentPage > totalPages) then 
		secondsToScanCompletion = "Done" 
	else 
		secondsToScanCompletion = SecondsToTime(secondsToScanCompletion) 
	end

	if (currentPage <= totalPages) then
	BrowseNoResultsText:SetText(
		private.scanProgressFormat:format(
			"Scanning auctions",
			currentPage, totalPages,
			auctionsScannedPerSecond,
			totalAuctions,
			scannedAuctions, (currentPage/totalPages)*100,
			SecondsToTime(secondsElapsed),
			secondsToScanCompletion,
			warningMessage
		)
	)
	else
	BrowseNoResultsText:SetText(
		private.scanCompleteFormat:format(
			"Scanning auctions",
			auctionsScannedPerSecond,
			totalAuctions,
			scannedAuctions, (scannedAuctions/totalAuctions)*100,
			SecondsToTime(secondsElapsed),
			warningMessage
		)
	)
	end	
end

--Config UI functions
function private.SetupConfigGui(gui)
	-- The defaults for the following settings are set in the lib.OnLoad function
	local id = gui:AddTab(libName, libType.." Modules")
	gui:AddControl(id, "Header",     0,    libName.." Options")

	gui:AddHelp(id, "what scanprogress",
		_TRANS('SPRG_Help_WhatScanProgress'), --"What is the Scan Progress indicator?"
		_TRANS('SPRG_Help_WhatScanProgressAnswer')) --"The Scan Progress indicator is the text that appears while scanning the Auction House. It displays:  the speed of the scan, current auctions and total number of auctions scanned, aswell as the current number of pages and total pages scanned."

--	Old answer, incase the new one is too short and/or vague.
--		"The Scan Progress indicator is the text that appears while scanning the Auction House, indicating "..
--		"how fast you are scanning, how many auctions you have scanned so far, how many total auctions there are, "..
--		"how many pages you have scanned so far, and how many total pages there are.")

	gui:AddControl(id, "Checkbox",   0, 1, "util.scanprogress.activated", _TRANS('SPRG_Interface_Activated')) --"Show a textual progress indicator when scanning"
	gui:AddTip(id, _TRANS('SPRG_HelpTooltip_Activated')) --"Toggles the display of the scan progress indicator\n\nNOTE: This setting is also affected by the CompactUI option to prevent other modules from changing the display of the browse tab while scanning."
	gui:AddControl(id, "Checkbox",   0, 1, "util.scanprogress.leaveshown", _TRANS('SPRG_Interface_LeaveShown')) --"Leave the scan progress text shown after scan completion"
	gui:AddTip(id, _TRANS('SPRG_HelpTooltip_LeaveShown')) --"If toggled, it will leave the scan progress indicator on the screen after scan has completed.\n\nIf disabled it will show the last scanned page."
end

function private.ConfigChanged()
	if (not AucAdvanced.Settings.GetSetting("util.scanprogress.activated")) then
		private.UpdateScanProgress(false)
	elseif (AucAdvanced.Scan.IsScanning()) then
		private.UpdateScanProgress(true)
	end
end

AucAdvanced.RegisterRevision("$URL: Auc-Advanced/Modules/Auc-Util-ScanProgress/ScanProgress.lua $", "$Rev: 6591 $")
