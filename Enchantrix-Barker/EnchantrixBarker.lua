﻿--[[
	Enchantrix:Barker Addon for World of Warcraft(tm).
	Version: 1.13.6611 (SwimmingSeadragon)
	Revision: $Id: EnchantrixBarker.lua 6611 2021-01-30 13:42:33Z none $
	URL: http://enchantrix.org/

	This is an addon for World of Warcraft that adds the ability to advertise
	your enchants to other players via the Trade channel.

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

]]
EnchantrixBarker_RegisterRevision("$URL: Enchantrix-Barker/EnchantrixBarker.lua $", "$Rev: 6611 $")


-- need to know early if we're using Classic or Modern version
local MINIMUM_CLASSIC = 11300
local MAXIMUM_CLASSIC = 19999
-- version, build, date, tocversion = GetBuildInfo()
local _,_,_,tocVersion = GetBuildInfo()
local isClassic = (tocVersion > MINIMUM_CLASSIC and tocVersion < MAXIMUM_CLASSIC)



local priorityList = {};

	-- this is used to search the trade categories
	-- the key is our internal value
	-- search is the string to look for in the enchant name
	-- print is what we print for the output
local categories = {
	['factor_item.bracer'] = {search = 'bracer', print = _BARKLOC('Bracer') },
	['factor_item.gloves'] = {search = 'gloves', print = _BARKLOC('Gloves') },
	['factor_item.boots'] = {search = 'boots', print = _BARKLOC('Boots') },
	['factor_item.shield'] = {search = 'shield', print = _BARKLOC('Shield') },
	['factor_item.chest'] = {search = 'chest', print = _BARKLOC('Chest') },
	['factor_item.cloak'] = {search = 'cloak', print = _BARKLOC('Cloak') },
	['factor_item.2hweap'] = {search = 'two handed weapon', print = _BARKLOC('TwoHandWeapon')},
	['factor_item.weapon'] = {search = 'weapon', print = _BARKLOC('AnyWeapon') },
	['factor_item.ring'] = {search = 'ring', print = _BARKLOC('Ring') },
	['factor_item.neck'] = {search = 'neck', print = 'Neck' },
	['factor_item.other'] = {search = 'other', print = _BARKLOC('Other') },
	['Unknown'] = {search = 'other', print = _BARKLOC('Other') },
};


if isClassic then
    categories[ 'factor_item.2hweap' ].search = "2h weapon";
end


	-- this is used internally only, to determine the order of enchants shown
local print_order = {
	'factor_item.bracer',
	'factor_item.gloves',
	'factor_item.boots',
	'factor_item.chest',
	'factor_item.cloak',
	'factor_item.shield',
	'factor_item.2hweap',
	'factor_item.weapon',
	'factor_item.ring',
	'factor_item.neck',
	'factor_item.other',
	'Unknown',
};


	-- these are used to search the craft listing
	-- the order of items is important to get the longest match (ie: "resistance to shadow" before "resistance")
	--  	BUT that may not work with locallized strings!   Try to get longer string matches!
	-- search is what we use to search the enchant description text
	--		all strings are reduced to lower case
	-- key is how we lookup percentanges from the settings (internal only)
	-- print is what we print for the output
 -- TODO: check for mistakes and mis-classifications/exceptions, need high level enchanters to check output!
local attributes = {

	{ search = _BARKLOC("EnchSearchCrusader"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("Crusader") },	-- incorrectly matched strength
	{ search = _BARKLOC("EnchSearchIntellect"), key = 'factor_stat.intellect', print = _BARKLOC("INT") },
	{ search = _BARKLOC("EnchSearchBoarSpeed"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortBoarSpeed") },		-- INCORRECTLY matches stamina?
	{ search = _BARKLOC("EnchSearchStamina"), key = "factor_stat.stamina", print = _BARKLOC("STA") },
	{ search = _BARKLOC("EnchSearchSpirit"), key = "factor_stat.spirit", print = _BARKLOC("SPI") },
	{ search = _BARKLOC("EnchSearchStrength"), key = "factor_stat.strength", print = _BARKLOC("STR") },
	{ search = _BARKLOC("EnchSearchCatSwiftness"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortCatSwiftness") },	-- INCORRECTLY matches agility?
	{ search = _BARKLOC("EnchSearchMongoose"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortMongoose") },			-- INCORRECTLY matches agility?
	{ search = _BARKLOC("EnchSearchAgility"), key = "factor_stat.agility", print = _BARKLOC("AGI") },
	{ search = _BARKLOC("EnchSearchFireRes"), key = "factor_stat.fireRes", print = _BARKLOC("FireRes") },
	{ search = _BARKLOC("EnchSearchResFire"), key = "factor_stat.fireRes", print = _BARKLOC("FireRes") },
	{ search = _BARKLOC("EnchSearchFrostRes"), key = "factor_stat.frostRes", print = _BARKLOC("FrostRes") },
	{ search = _BARKLOC("EnchSearchNatureRes"), key = "factor_stat.natureRes", print = _BARKLOC("NatureRes") },
	{ search = _BARKLOC("EnchSearchResShadow"), key = "factor_stat.shadowRes", print = _BARKLOC("ShadowRes") },
	{ search = _BARKLOC("EnchSearchAllStats"), key = "factor_stat.all", print = _BARKLOC("AllStats") },
	{ search = _BARKLOC("EnchSearchSpellsurge"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortSpellSurge") },		-- INCORRECTLY matches mana?
	{ search = _BARKLOC("EnchSearchVitality"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortVitality") },			-- INCORRECTLY matches health and mana?
	{ search = _BARKLOC("EnchSearchManaPerFive"), key = "factor_stat.other", print = _BARKLOC("ShortManaPerFive") },						-- INCORRECTLY matches mana
	{ search = _BARKLOC("EnchSearchMana"), key = "factor_stat.mana", print = _BARKLOC("ShortMana") },
	{ search = _BARKLOC("EnchSearchBattlemaster"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortBattlemaster") },	-- INCORRECTLY matches health?
	{ search = _BARKLOC("EnchSearchHealth"), key = "factor_stat.health", print = _BARKLOC("ShortHealth") },
	{ search = _BARKLOC("EnchSearchSunfire"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortSunfire") },			-- INCORRECTLY matches damage?
	{ search = _BARKLOC("EnchSearchSoulfrost"), key = "factor_stat.other", ignoreValues = true, print = _BARKLOC("ShortSoulfrost") },		-- INCORRECTLY matches damage?
	{ search = _BARKLOC("EnchSearchBeastslayer"), key = "factor_stat.other", print = _BARKLOC("ShortBeastslayer") },						-- INCORRECTLY matches damage?
	{ search = _BARKLOC("EnchSearchSpellPower1"), key = "factor_stat.other", print = _BARKLOC("ShortSpellPower") },							-- INCORRECTLY matches damage?		weapon "spell power"
	{ search = _BARKLOC("EnchSearchSpellPower2"), key = "factor_stat.other", print = _BARKLOC("ShortSpellPower") },							-- INCORRECTLY matches damage?		weapon "major spell power"
	{ search = _BARKLOC("EnchSearchSpellPower3"), key = "factor_stat.other", print = _BARKLOC("ShortSpellPower") },							-- INCORRECTLY matches damage?		bracer, ring, gloves "spell power"
	{ search = _BARKLOC("EnchSearchHealing"), key = "factor_stat.other", print = _BARKLOC("ShortHealing") },								-- INCORRECTLY matches spell power after Blizzard changed the strings
	{ search = _BARKLOC("EnchSearchDMGAbsorption"), key = "factor_stat.damageAbsorb", print = _BARKLOC("DMGAbsorb") },			-- must come before armor and damage
	{ search = _BARKLOC("EnchSearchDamage1"), key = "factor_stat.damage", print = _BARKLOC("DMG") },
	{ search = _BARKLOC("EnchSearchDamage2"), key = "factor_stat.damage", print = _BARKLOC("DMG") },
	{ search = _BARKLOC("EnchSearchDefense"),  key = "factor_stat.defense", print = _BARKLOC("DEF") },
	{ search = _BARKLOC("EnchSearchAllResistance1"), key = "factor_stat.allRes", print = _BARKLOC("ShortAllRes") },
	{ search = _BARKLOC("EnchSearchAllResistance2"), key = "factor_stat.allRes", print = _BARKLOC("ShortAllRes") },
	{ search = _BARKLOC("EnchSearchAllResistance3"), key = "factor_stat.allRes", print = _BARKLOC("ShortAllRes") },
	{ search = _BARKLOC("EnchSearchArmor"), key = "factor_stat.armor", print = _BARKLOC("ShortArmor") },						-- too general, has to come near last
	{ search = _BARKLOC("EnchSearchResilience"), key = "factor_stat.resilience", print = _BARKLOC("RESIL") },				-- too general, has to come near last

-- TODO - need new stat factors!
	{ search = "mastery", key = "factor_stat.other", print = "Mast" },
	{ search = "haste", key = "factor_stat.other", print = "Haste" },
	{ search = "critical strike", key = "factor_stat.other", print = "Crit" },
	{ search = "versatility", key = "factor_stat.other", print = "Vers" },
};

--[[
Other possible exceptions or additions

	{ search = 'damage against elementals', key = "factor_stat.other", print = "Elemental" },		-- probably safe
	{ search = 'damage to demons', key = "factor_stat.other", print = "Demon" },					-- probably safe
	{ search = 'frost spells', key = "factor_stat.other", print = "frost" },						-- probably safe
	{ search = 'frost damage', key = "factor_stat.other", print = "frost" },						-- probably safe
	{ search = 'shadow damage', key = "factor_stat.other", print = "shadow" },						-- probably safe
	{ search = "increase fire damage", key = "factor_stat.other", print = "fire" },					-- probably safe
	{ search = 'block rating', key = "factor_stat.other", print = "block" },						-- probably safe
	{ search = 'block value', key = "factor_stat.other", print = "block" },							-- probably safe

Other... (these should be ok as-is)
surefooted "snare and root resistance"
spell strike "spell hit rating"
spell penetration  "spell penetration"
blasting  "spell critical strike rating"
savagery 	"attack power"
haste "attack speed bonus"
stealth  "increase to stealth"
dodge  "dodge rating"
assult  "increase attack power"
enchanted leather "Enchanted Leather"
enchanted thorium "Enchanted Thorium Bar"
brawn  "increase Strength"										-- correctly matches strength

]]


	-- this is used to match up trade zone game names with short strings for the output
local short_location = {
	[_BARKLOC('Orgrimmar')] = _BARKLOC('ShortOrgrimmar'),
	[_BARKLOC('ThunderBluff')] = _BARKLOC('ShortThunderBluff'),
	[_BARKLOC('Undercity')] = _BARKLOC('ShortUndercity'),
	[_BARKLOC('StormwindCity')] = _BARKLOC('ShortStormwind'),
	[_BARKLOC('Darnassus')] = _BARKLOC('ShortDarnassus'),
	[_BARKLOC('Ironforge')] = _BARKLOC('ShortIronForge'),
	[_BARKLOC('Shattrath')] = _BARKLOC('ShortShattrath'),
	[_BARKLOC('SilvermoonCity')] = _BARKLOC('ShortSilvermoon'),
	[_BARKLOC('TheExodar')] = _BARKLOC('ShortExodar'),
	[_BARKLOC('Dalaran')] = _BARKLOC('ShortDalaran'),
};


local relevelFrame;
local relevelFrames;

local addonName = "Enchantrix Barker"

-- UI code

local function getGSC(money)
	money = math.floor(tonumber(money) or 0)
	local g = math.floor(money / 10000)
	local s = math.floor(money % 10000 / 100)
	local c = money % 100
	return g,s,c
end

function EnchantrixBarker_OnEvent(event,...)
	--Returns "Enchanting" for enchantwindow

	local tradeSkillID, craftName, _rank, _maxRank, _skillLineModifier

    if isClassic then
        craftName, _rank, _maxRank = GetCraftDisplaySkillLine();
    else
        tradeSkillID, craftName, _rank, _maxRank, _skillLineModifier = _G.C_TradeSkillUI.GetTradeSkillLine();
    end

    --Barker.Util.DebugPrintQuick("CraftName ", craftName, event )
    --print("CraftEvent", craftName, event )

	if craftName and craftName == _BARKLOC('Enchanting') then
		if( event == "CRAFT_SHOW" or event == "TRADE_SKILL_SHOW") then
			if( Barker.Settings.GetSetting('barker') ) then
				Enchantrix_BarkerOptions_TradeTab:Show();
				Enchantrix_BarkerOptions_TradeTab.tooltipText = _BARKLOC('OpenBarkerWindow');
			else
				Enchantrix_BarkerOptions_TradeTab:Hide();
			end
		end
	elseif (event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" ) then
		-- we are closing, or it's a different craft/trade, hide the button and frame
		Enchantrix_BarkerOptions_TradeTab:Hide();
	end

end

function Enchantrix_BarkerOptions_OnShow()
	Enchantrix_BarkerOptions_ShowFrame(1);
end

function Enchantrix_BarkerOnClick(self)

	local barker = Enchantrix_CreateBarker(false);
	local id = GetChannelName( _BARKLOC("TradeChannel") ) ;
	--Barker.Util.DebugPrintQuick("Attempting to send barker ", barker, " Trade Channel ID ", id)

	if (id and (not(id == 0))) then
		if (barker) then
			SendChatMessage(barker,"CHANNEL", GetDefaultLanguage("player"), id);
		end
    else
        Barker.Util.ChatPrint( _BARKLOC("BarkerNotTradeZone") );
	end
end

function Barker.Barker.AddonLoaded()
	Barker.Util.ChatPrint( _BARKLOC("BarkerLoaded") );
end

function relevelFrame(frame)
	return relevelFrames(frame:GetFrameLevel() + 2, frame:GetChildren())
end

function relevelFrames(myLevel, ...)
	for i = 1, select("#", ...) do
		local child = select(i, ...)
		child:SetFrameLevel(myLevel)
		relevelFrame(child)
	end
end

local function craftUILoaded()

	Stubby.UnregisterAddOnHook("Blizzard_CraftUI", "Enchantrix")
	Stubby.UnregisterAddOnHook("Blizzard_TradeSkillUI", "Enchantrix")

	-- ccox - CraftFrame pre LK / 3.0, TradeSkillFrame after (where CraftFrame is nil)
	local useFrame = CraftFrame or TradeSkillFrame;

	if (ATSWFrame ~= nil) then
		Stubby.UnregisterAddOnHook("ATSWFrame", "Enchantrix")
		useFrame = ATSWFrame;
	end

	Enchantrix_BarkerOptions_TradeTab:SetParent(useFrame);
	if (ATSWFrame ~= nil) then
		-- this works for ATSW
		Enchantrix_BarkerOptions_TradeTab:SetPoint("TOPLEFT", useFrame, "BOTTOMLEFT", 10, 15 );
	else
		-- and this works for the WoW 4.0 trade Window
        if isClassic then
		    Enchantrix_BarkerOptions_TradeTab:SetPoint("TOPLEFT", useFrame, "BOTTOMLEFT", 20, 73 ); -- was 10, 75
        else
		    Enchantrix_BarkerOptions_TradeTab:SetPoint("TOPLEFT", useFrame, "BOTTOMLEFT", 10, 2 );
        end
	end

	-- skillet has an API to add buttons
	if SkilletFrame then
	    local frame = Skillet:AddButtonToTradeskillWindow(Enchantrix_BarkerDisplayButton)
	    useFrame = frame;
	end

	Enchantrix_BarkerOptions_Frame:SetParent(useFrame);
	Enchantrix_BarkerOptions_Frame:SetPoint("TOPLEFT", useFrame, "TOPRIGHT");
	relevelFrame(Enchantrix_BarkerOptions_Frame)

end

function EnchantrixBarker_OnLoad()

    if (not EnchantrixBarkerSavedInfo) then EnchantrixBarkerSavedInfo = {} end

	if (ATSWFrame ~= nil) then
		Stubby.RegisterAddOnHook("ATSWFrame", "Enchantrix", craftUILoaded)
	end
	Stubby.RegisterAddOnHook("Blizzard_CraftUI", "Enchantrix", craftUILoaded)			-- pre 3.0
	Stubby.RegisterAddOnHook("Blizzard_TradeSkillUI", "Enchantrix", craftUILoaded)		-- post 3.0

    if isClassic then
        -- these events don't exist in retail, and generate an error
        EnchantrixBarker:RegisterEvent("CRAFT_SHOW")
        EnchantrixBarker:RegisterEvent("CRAFT_CLOSE")
    end

    EnchantrixBarker:RegisterEvent("TRADE_SKILL_SHOW")
    EnchantrixBarker:RegisterEvent("TRADE_SKILL_CLOSE")
end

function Enchantrix_BarkerGetConfig( key )
	return Barker.Settings.GetSetting("barker."..key)
end

function Enchantrix_BarkerSetConfig( key, value )
	Barker.Settings.SetSetting("barker."..key, value)
end

function Enchantrix_BarkerOptions_SetDefaults()
	-- currently, we have no settings other than what's in the dialog
	-- resetting the WHOLE profile will reset everything

	Barker.Settings.SetSetting("barker.reset_all", nil)

	if Enchantrix_BarkerOptions_Frame:IsVisible() then
		Enchantrix_BarkerOptions_Refresh()
	end
end

function Enchantrix_BarkerOptions_ResetButton_OnClick(self)
	-- reset all slider values
	Enchantrix_BarkerOptions_SetDefaults();
end

function Enchantrix_BarkerOptions_SkillupCheck_OnClick(self)
	-- flip boolean state
    local current = Barker.Settings.GetSetting("barker.skillup_mode")
	Barker.Settings.SetSetting("barker.skillup_mode", not current )
end

local saveStringData = false

function Enchantrix_BarkerOptions_TestButton_OnClick(self)

    local a = IsAltKeyDown()
    local s = IsShiftKeyDown()
    --local c = IsControlKeyDown()

    if (a and s) then
        saveStringData = true
        EnchantrixBarkerSavedInfo = {}
    end

	local barker = Enchantrix_CreateBarker( true );

    if saveStringData then
        Barker.Util.ChatPrint("Saved enchant debug data to SV!");
    else
        if (barker) then
            Barker.Util.ChatPrint(barker);
        end
    end

    saveStringData = false;
end

function Enchantrix_BarkerOptions_Factors_Slider_GetValue(id)
	return Enchantrix_BarkerGetConfig(Enchantrix_BarkerOptions_TabFrames[Enchantrix_BarkerOptions_ActiveTab].options[id].key);
end

function Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged(self)
	Enchantrix_BarkerSetConfig(Enchantrix_BarkerOptions_TabFrames[Enchantrix_BarkerOptions_ActiveTab].options[self:GetID()].key, self:GetValue());
end

Enchantrix_BarkerOptions_ActiveTab = -1;


Enchantrix_BarkerOptions_TabFrames = {
	{
		title = _BARKLOC('BarkerOptionsTab1Title'),
		options = {
			{
				name = _BARKLOC('BarkerOptionsProfitMarginTitle'),
				tooltip = _BARKLOC('BarkerOptionsProfitMarginTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'profit_margin',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsHighestProfitTitle'),
				tooltip = _BARKLOC('BarkerOptionsHighestProfitTooltip'),
				units = 'money',
				min = 0,
				max = 250000,
				step = 500,
				key = 'highest_profit',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsLowestPriceTitle'),
				tooltip = _BARKLOC('BarkerOptionsLowestPriceTooltip'),
				units = 'money',
				min = 0,
				max = 50000,
				step = 500,
				key = 'lowest_price',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsPricePriorityTitle'),
				tooltip = _BARKLOC('BarkerOptionsPricePriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_price',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsPriceSweetspotTitle'),
				tooltip = _BARKLOC('BarkerOptionsPriceSweetspotTooltip'),
				units = 'money',
				min = 0,
				max = 500000,
				step = 5000,
				key = 'sweet_price',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsHighestPriceForFactorTitle'),
				tooltip = _BARKLOC('BarkerOptionsHighestPriceForFactorTooltip'),
				units = 'money',
				min = 0,
				max = 1000000,
				step = 50000,
				key = 'high_price',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsRandomFactorTitle'),
				tooltip = _BARKLOC('BarkerOptionsRandomFactorTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'randomise',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
		}
	},
	{
		title = 'Item Priorities',
		options = {
			{
				name = _BARKLOC('BarkerOptionsItemsPriority'),
				tooltip = _BARKLOC('BarkerOptionsItemsPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('TwoHandWeapon'),
				tooltip = _BARKLOC('BarkerOptions2HWeaponPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.2hweap',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('AnyWeapon'),
				tooltip = _BARKLOC('BarkerOptionsAnyWeaponPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.weapon',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('Bracer'),
				tooltip = _BARKLOC('BarkerOptionsBracerPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.bracer',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('Gloves'),
				tooltip = _BARKLOC('BarkerOptionsGlovesPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.gloves',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('Boots'),
				tooltip = _BARKLOC('BarkerOptionsBootsPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.boots',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('Chest'),
				tooltip = _BARKLOC('BarkerOptionsChestPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.chest',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('Cloak'),
				tooltip = _BARKLOC('BarkerOptionsCloakPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.cloak',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('Shield'),
				tooltip = _BARKLOC('BarkerOptionsShieldPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.shield',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = 'Ring',
				tooltip = "The priority score for ring enchants.",
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.ring',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = 'Neck',
				tooltip = "The priority score for neck enchants.",
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_item.neck',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
		}
	},
	{
		title = 'Stats 1',
		options = {
			{
				name = _BARKLOC('BarkerOptionsStatsPriority'),
				tooltip = _BARKLOC('BarkerOptionsStatsPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsIntellectPriority'),
				tooltip = _BARKLOC('BarkerOptionsIntellectPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.intellect',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsStrengthPriority'),
				tooltip = _BARKLOC('BarkerOptionsStrengthPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.strength',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsAgilityPriority'),
				tooltip = _BARKLOC('BarkerOptionsAgilityPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.agility',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsStaminaPriority'),
				tooltip = _BARKLOC('BarkerOptionsStaminaPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.stamina',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsSpiritPriority'),
				tooltip = _BARKLOC('BarkerOptionsSpiritPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.spirit',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsArmorPriority'),
				tooltip = _BARKLOC('BarkerOptionsArmorPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.armor',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsResiliencePriority'),
				tooltip = _BARKLOC('BarkerOptionsResiliencePriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.resilience',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsAllStatsPriority'),
				tooltip = _BARKLOC('BarkerOptionsAllStatsPriorityTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.all',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
		}
	},
	{
		title = 'Stats 2',
		options = {
			{
				name = _BARKLOC('BarkerOptionsAllResistances'),
				tooltip = _BARKLOC('BarkerOptionsAllResistancesTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.allRes',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsFireResistance'),
				tooltip = _BARKLOC('BarkerOptionsFireResistanceTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.fireRes',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsFrostResistance'),
				tooltip = _BARKLOC('BarkerOptionsFrostResistanceTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.frostRes',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsNatureResistance'),
				tooltip = _BARKLOC('BarkerOptionsNatureResistanceTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.natureRes',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsShadowResistance'),
				tooltip = _BARKLOC('BarkerOptionsShadowResistanceTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.shadowRes',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsMana'),
				tooltip = _BARKLOC('BarkerOptionsManaTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.mana',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsHealth'),
				tooltip = _BARKLOC('BarkerOptionsHealthTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.health',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsDamage'),
				tooltip = _BARKLOC('BarkerOptionsDamageTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.damage',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsDefense'),
				tooltip = _BARKLOC('BarkerOptionsDefenseTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.defense',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
			{
				name = _BARKLOC('BarkerOptionsOther'),
				tooltip = _BARKLOC('BarkerOptionsOtherTooltip'),
				units = 'percentage',
				min = 0,
				max = 100,
				step = 1,
				key = 'factor_stat.other',
				getvalue = Enchantrix_BarkerOptions_Factors_Slider_GetValue,
				valuechanged = Enchantrix_BarkerOptions_Factors_Slider_OnValueChanged
			},
		}
	}
};

function EnchantrixBarker_OptionsSlider_OnValueChanged(self)
	if Enchantrix_BarkerOptions_ActiveTab ~= -1 then
		--Barker.Util.ChatPrint( "Tab - Slider changed: "..Enchantrix_BarkerOptions_ActiveTab..' - '..self:GetID() );
		Enchantrix_BarkerOptions_TabFrames[Enchantrix_BarkerOptions_ActiveTab].options[self:GetID()].valuechanged(self);
		value = self:GetValue();
		--Enchantrix_BarkerOptions_TabFrames[Enchantrix_BarkerOptions_ActiveTab].options[self:GetID()].getvalue();

		valuestr = EnchantrixBarker_OptionsSlider_GetTextFromValue( value, Enchantrix_BarkerOptions_TabFrames[Enchantrix_BarkerOptions_ActiveTab].options[self:GetID()].units );

		_G[self:GetName().."Text"]:SetText(Enchantrix_BarkerOptions_TabFrames[Enchantrix_BarkerOptions_ActiveTab].options[self:GetID()].name.." - "..valuestr );
	end
end

function EnchantrixBarker_OptionsSlider_GetTextFromValue( value, units )

	local valuestr = ''

	if units == 'percentage' then
		valuestr = value..'%'
	elseif units == 'money' then
		local p_gold,p_silver,p_copper = getGSC(value);

		if( p_gold > 0 ) then
			valuestr = p_gold.."g";
		end
		if( p_silver > 0 ) then
			valuestr = valuestr..p_silver.."s";
		end
	end
	return valuestr;
end

function Enchantrix_BarkerOptions_Tab_OnClick(self)
	--Barker.Util.ChatPrint( "Clicked Tab: "..self:GetID() );
	Enchantrix_BarkerOptions_ShowFrame( self:GetID() )
end

function Enchantrix_BarkerOptions_Refresh()
	local cur = Enchantrix_BarkerOptions_ActiveTab
	if (cur and cur > 0) then
		Enchantrix_BarkerOptions_ShowFrame(cur)
	end
    Enchantrix_BarkerOptionsSkillup_Check:SetChecked( Barker.Settings.GetSetting("barker.skillup_mode") )
end

function Enchantrix_BarkerOptions_ShowFrame( frame_index )
	Enchantrix_BarkerOptions_ActiveTab = -1
	for index, frame in pairs(Enchantrix_BarkerOptions_TabFrames) do
		if ( index == frame_index ) then
			--Barker.Util.ChatPrint( "Showing Frame: "..index );
			for i = 1,11 do
				local slider = _G['EnchantrixBarker_OptionsSlider_'..i];
				slider:Hide();
			end
			for i, opt in pairs(frame.options) do
				local slidername = 'EnchantrixBarker_OptionsSlider_'..i
				local slider = _G[slidername];
				slider:SetMinMaxValues(opt.min, opt.max);
				slider:SetValueStep(opt.step);
				slider.tooltipText = opt.tooltip;
				_G[slidername.."High"]:SetText();
				_G[slidername.."Low"]:SetText();
				slider:Show();
			end
			Enchantrix_BarkerOptions_ActiveTab = index
			for i, opt in pairs(frame.options) do
				local slidername = 'EnchantrixBarker_OptionsSlider_'..i
				local slider = _G[slidername];
				local newValue = opt.getvalue(i);
				slider:SetValue(newValue);
				_G[slidername.."Text"]:SetText(opt.name..' - '..EnchantrixBarker_OptionsSlider_GetTextFromValue(slider:GetValue(),opt.units));
			end
		end
	end
end

function Enchantrix_BarkerOptions_OnClick(self)
	--Barker.Util.ChatPrint("You pressed the options button." );
	--showUIPanel(Enchantrix_BarkerOptions_Frame);
	if not Enchantrix_BarkerOptions_Frame:IsShown() then
		Enchantrix_BarkerOptions_Frame:Show();
	else
		Enchantrix_BarkerOptions_Frame:Hide();
	end
end

function Enchantrix_CheckButton_OnShow()
end
function Enchantrix_CheckButton_OnClick()
end
function Enchantrix_CheckButton_OnEnter()
end
function Enchantrix_CheckButton_OnLeave()
end



local CraftTypeWeights = {
    ["optimal"] = 3,
    ["medium"] = 2,
    ["easy"] = 1,
    ["trivial"] = 0,
};


function Enchantrix_CreateBarker( isTest )

	--Barker.Util.DebugPrintQuick("CreateBarker started");

	local zoneString = EnchantrixBarker_BarkerGetZoneText();
	if (not isTest and not zoneString) then
		-- not in a recognized trade zone
        Barker.Util.ChatPrint( _BARKLOC("BarkerNotTradeZone") );
        return nil;
	end

    local temp
    if isClassic then
        temp = GetCraftDisplaySkillLine();
    else
	    temp = _G.C_TradeSkillUI.GetTradeSkillLine();
    end

	if (not temp) then
		-- trade skill window isn't open (how did this happen?)
		Barker.Util.ChatPrint(_BARKLOC('BarkerEnxWindowNotOpen'));
		return nil;
	end

	local availableEnchants = {};
	local numAvailable = 0;

	EnchantrixBarker_ResetBarkerString();
	EnchantrixBarker_ResetPriorityList();

	local highestProfit = Enchantrix_BarkerGetConfig("highest_profit");
	local profitMargin = Enchantrix_BarkerGetConfig("profit_margin");
    local isSkillUpMode = Enchantrix_BarkerGetConfig("skillup_mode");

    if isClassic then
        local craftCount = GetNumCrafts()
        --Barker.Util.DebugPrintQuick("CraftCount", craftCount )

        for index=1, craftCount do

            local craftName, craftSubSpellName, craftType, numEnchantsAvailable, isExpanded = GetCraftInfo(index)

            --Barker.Util.DebugPrintQuick("craft index", index, craftName, numEnchantsAvailable )

            if ( numEnchantsAvailable > 0 ) or isSkillUpMode or saveStringData then -- user has reagents, or customer supplies own reagents

                -- does this skill produce an enchant, or a trade good?
                --local itemLink = GetCraftItemLink(index);

                -- ALL results are nil, because we get enchant links, not item links
                --local itemName, newItemLink, _rarity, _level, _minLevel, _itemType, _itemSubType, _itemStackCount, _itemEquipLoc, _itemIcon, _itemSell, _itemClassID, _itemSubClassID, itemBindType, _xpac, _setID, isCraftReagent = GetItemInfo(itemLink);
                --local itemName, newItemLink = GetItemInfo(itemLink);

                -- We really don't want to list rods or wands among our enchants for sale
                -- in Classic, enchants have hypens, item creation does not
                local isItem = craftName:match("-") == nil

                local skillWeight = CraftTypeWeights[ craftType ] or 0;
                skillWeight = tonumber(skillWeight)

                -- item name and link are nil for enchants, and valid for produced items (which we want to ignore)
                if (not isItem and (saveStringData or (skillWeight > 0) or (not isSkillUpMode)) ) then
                    --print("enchant", craftName, skillWeight)

                    local cost = 0;
                    local profit = 0;
                    local price = 0;

                    if not isSkillUpMode or not saveStringData then
                        for j=1,GetCraftNumReagents(index),1 do
                            local reagentName,_,countRequired = GetCraftReagentInfo(index,j);
                            local reagent = GetCraftReagentItemLink(index,j);
                            cost = cost + (Enchantrix_GetReagentHSP(reagent)*countRequired);
                            --print("reagent:", reagentName )
                        end

                        profit = cost * profitMargin*0.01;
                        if( profit > highestProfit ) then
                            profit = highestProfit;
                        end
                        price = EnchantrixBarker_RoundPrice(cost + profit);
                    else
                        numEnchantsAvailable = 1;
                    end

                    local enchant = {
                        index = index,
                        name = craftName,
                        difficulty = skillWeight,
                        --type = craftType,
                        --available = numEnchantsAvailable,
                        cost = cost,
                        price = price,
                        profit = price - cost,
                    };
                    availableEnchants[ numAvailable] = enchant;

                    --Barker.Util.DebugPrintQuick("Adding enchant ", enchant )
                    --local p_gold,p_silver,p_copper = getGSC(enchant.price);
                    --local pr_gold,pr_silver,pr_copper = getGSC(enchant.profit);

                    EnchantrixBarker_AddEnchantToPriorityList( enchant )
                    numAvailable = numAvailable + 1;
                end
            end
        end
    else
        -- retail
	    local recipes = _G.C_TradeSkillUI.GetAllRecipeIDs()

        if recipes and (#recipes > 0) then
            for i = 1, #recipes do

            -- see http://wow.gamepedia.com/API_C_TradeSkillUI.GetRecipeInfo
            local recipe_info = _G.C_TradeSkillUI.GetRecipeInfo(recipes[i])
            local craftName = recipe_info.name
            local craftType = recipe_info.type
            local numEnchantsAvailable = recipe_info.numAvailable

            if ( recipe_info.learned and recipe_info.craftable and ((numEnchantsAvailable > 0) or isSkillUpMode) ) then -- user can craft this

                -- does this skill produce an enchant, or a trade good?
                --local itemLink = _G.C_TradeSkillUI.GetRecipeItemLink(recipes[i]);

                -- usually returns nils for everything, because we get enchant links instead of item links
                --local itemName, newItemLink = GetItemInfo(itemLink);

                --Barker.Util.DebugPrintQuick("Can Craft ", i, " info: ", recipe_info )

                -- We really don't want to list rods or wands among our enchants for sale
                -- but retail enchant strings are not as well organize4d
                local isRod = craftName:match("Rod") ~= nil or craftName:match("Wand") ~= nil

                local skillWeight = CraftTypeWeights[ recipe_info.difficulty ] or 0;

                -- item name and link are nil for enchants, and valid for produced items (which we want to ignore)
                if (not isRod and (saveStringData or skillWeight > 0 or (not isSkillUpMode)) ) then
                    --print(craftName, skillWeight)

                    local cost = 0;
                    local profit = 0;
                    local price = 0;

                    if not isSkillUpMode then
                        local reagentCount = _G.C_TradeSkillUI.GetRecipeNumReagents(recipes[i])
                        for j=1,reagentCount,1 do
                            local _reagentName, _reagentTexture, reagentCountRequired, _playerReagentCount = _G.C_TradeSkillUI.GetRecipeReagentInfo(recipes[i], j)
                            local reagent = _G.C_TradeSkillUI.GetRecipeReagentItemLink(recipes[i], j)
                            cost = cost + (Enchantrix_GetReagentHSP(reagent)*reagentCountRequired);
                            --print("reagent:", _reagentName )
                        end

                        profit = cost * profitMargin*0.01;
                        if( profit > highestProfit ) then
                            profit = highestProfit;
                        end
                        price = EnchantrixBarker_RoundPrice(cost + profit);
                    else
                        numEnchantsAvailable = 1;
                    end

                    local enchant = {
                        index = i,
                        recipe = recipes[i],
                        name = craftName,
                        difficulty = skillWeight,
                        --type = craftType,
                        --available = numEnchantsAvailable,
                        cost = cost,
                        price = price,
                        profit = price - cost,
                    };
                    availableEnchants[ numAvailable] = enchant;

                    --Barker.Util.DebugPrintQuick("Adding enchant ", enchant )
                    --local p_gold,p_silver,p_copper = getGSC(enchant.price);
                    --local pr_gold,pr_silver,pr_copper = getGSC(enchant.profit);

                    EnchantrixBarker_AddEnchantToPriorityList( enchant )
                    numAvailable = numAvailable + 1;
                end
            end
        end
	end

    end

	if numAvailable == 0 then
		Barker.Util.ChatPrint(_BARKLOC('BarkerNoEnchantsAvail'));
		return nil
	end

    -- save debugging info
    if saveStringData then
        EnchantrixBarkerSavedInfo[ "isClassic" ] = isClassic
	    for i,element in ipairs(priorityList) do
	        local descString = Enchantrix_GetShortDescriptor(element.enchant)
            local long_str = EnchantrixBarker_GetCraftDescription(element.enchant):lower();
            local entry = {
                    difficulty = element.enchant.difficulty,
                    long_str = long_str,
                    desc = descString,
            }
            EnchantrixBarkerSavedInfo[ element.enchant.name ] = entry
        end
    end

	for i,element in ipairs(priorityList) do
		EnchantrixBarker_AddEnchantToBarker( element.enchant );
	end

	--Barker.Util.DebugPrintQuick("Barker string created");
	return EnchantrixBarker_GetBarkerString();

end

function EnchantrixBarker_ScoreEnchantPriority( enchant )

	local score_item = 0;

	if Enchantrix_BarkerGetConfig( EnchantrixBarker_GetItemCategoryKey(enchant) ) then
		score_item = Enchantrix_BarkerGetConfig( EnchantrixBarker_GetItemCategoryKey(enchant) );
		score_item = score_item * Enchantrix_BarkerGetConfig( 'factor_item' )*0.01;
	end

	local score_stat = Enchantrix_BarkerGetConfig( EnchantrixBarker_GetEnchantStat(enchant) );
	if not score_stat then
		score_stat = Enchantrix_BarkerGetConfig( 'factor_stat.other' );
	end

	score_stat = score_stat * Enchantrix_BarkerGetConfig( 'factor_stat' )*0.01;

	local score_price = 0;
	local price_score_floor = Enchantrix_BarkerGetConfig("sweet_price");
	local price_score_ceiling = Enchantrix_BarkerGetConfig("high_price");
    local score_difficulty = 1 + enchant.difficulty * 30;

	if enchant.price < price_score_floor then
		score_price = (price_score_floor - (price_score_floor - enchant.price))/price_score_floor * 100;
	elseif enchant.price < price_score_ceiling then
		range = (price_score_ceiling - price_score_floor);
		score_price = (range - (enchant.price - price_score_floor))/range * 100;
	end

	score_price = score_price * Enchantrix_BarkerGetConfig( 'factor_price' )*0.01;
	score_total = (score_item + score_stat + score_price + score_difficulty);
    --print("score", enchant.name, score_item, score_stat, score_price, score_difficulty )

	local randomize_factor = 0.01 * Enchantrix_BarkerGetConfig("randomise")
	return score_total * (1 - randomize_factor) + math.random(300) * randomize_factor;
end

function EnchantrixBarker_ResetPriorityList()
	priorityList = {};
end

function EnchantrixBarker_AddEnchantToPriorityList(enchant)

	local enchant_score = EnchantrixBarker_ScoreEnchantPriority( enchant );

	for i,priorityentry in ipairs(priorityList) do
		if( priorityentry.score < enchant_score ) then
			--Barker.Util.DebugPrintQuick("Adding item to priority list ", i, enchant_score, enchant )
			table.insert( priorityList, i, {score = enchant_score, enchant = enchant} );
			return;
		end
	end

	--Barker.Util.DebugPrintQuick("Adding item to priority list ", 0, enchant_score, enchant )
	table.insert( priorityList, {score = enchant_score, enchant = enchant} );
end

function EnchantrixBarker_RoundPrice( price )

	local round

	if( price < 5000 ) then
		round = 1000;
	elseif ( price < 20000 ) then
		round = 2500;
	elseif (price < 100000) then
		round = 5000;
	else
		round = 10000;
	end

	odd = math.fmod(price,round);

	price = price + (round - odd);

	if( price < Enchantrix_BarkerGetConfig("lowest_price") ) then
		price = Enchantrix_BarkerGetConfig("lowest_price");
	end

	return price
end

function Enchantrix_GetReagentHSP( itemLink )

	if ((not Enchantrix) or (not Enchantrix.Util)) then
		Barker.Util.ChatPrint(_BARKLOC("MesgNotloaded"));
		return 0;
	end

	local hsp, median, baseline, price5 = Enchantrix.Util.GetReagentPrice( itemLink );

	if hsp == nil then
		hsp = 0;
	end

	-- if auc4 is missing, and auc5 has a price, use the auc5 price
	if (hsp == 0 and AucAdvanced and price5) then
		hsp = price5;
	end

	return hsp;
end

local barkerString = '';
local barkerCategories = {};

function EnchantrixBarker_ResetBarkerString()
    local opening

    if Enchantrix_BarkerGetConfig("skillup_mode")  then
        opening = "Enchants free with your mats!"
    else
        opening = _BARKLOC('BarkerOpening')
    end

	barkerString = "("..EnchantrixBarker_BarkerGetZoneText()..") "..opening;
	barkerCategories = {};
end

function EnchantrixBarker_BarkerGetZoneText()
	local zoneText = GetZoneText();
	local result = short_location[zoneText];
	if (not result) then
        result = zoneText
        Barker.Util.DebugPrintQuick("Attempting to use barker in non-trade zone ", zoneText )
	end
	return result;
end

function EnchantrixBarker_AddEnchantToBarker( enchant )

	local currBarker = EnchantrixBarker_GetBarkerString();

	local category_key = EnchantrixBarker_GetItemCategoryKey( enchant )

	-- see if this category (self enchants) should be excluded from barking
	if (categories[category_key] and categories[category_key].exclude) then
		--Barker.Util.DebugPrintQuick("excluding category key ", category_key, enchant )
		return false;
	end

	local category_string = "";
	local test_category = {};
	if barkerCategories[ category_key ] then
		for i,element in ipairs(barkerCategories[category_key]) do
			--Barker.Util.ChatPrint("Inserting: "..i..", elem: "..element.index );
			table.insert(test_category, element);
		end
	end

	table.insert(test_category, enchant);

	category_string = EnchantrixBarker_GetBarkerCategoryString( test_category );

	if #currBarker + #category_string > 255 then
		--Barker.Util.DebugPrintQuick("string too long", #currBarker, #category_string, enchant )
		return false;
	end

	if not barkerCategories[ category_key ] then
		barkerCategories[ category_key ] = {};
	end

	--Barker.Util.DebugPrintQuick("inserting new ", category_key, enchant )
	table.insert( barkerCategories[ category_key ], enchant );

	return true;
end

function EnchantrixBarker_GetBarkerString()
	if not barkerString then EnchantrixBarker_ResetBarkerString() end

	local barker = ""..barkerString;

	for index, key in ipairs(print_order) do
		if( barkerCategories[key] ) then
			barker = barker..EnchantrixBarker_GetBarkerCategoryString( barkerCategories[key] )
		end
	end

	return barker;
end

function EnchantrixBarker_GetBarkerCategoryString( barkerCategory )
	local barkercat = ""
	--Barker.Util.DebugPrintQuick("setting up ", barkerCategory[1].index, EnchantrixBarker_GetItemCategoryString(barkerCategory[1]) );
	barkercat = barkercat.." ["..EnchantrixBarker_GetItemCategoryString(barkerCategory[1])..": ";
	for j,enchant in ipairs(barkerCategory) do
		if( j > 1) then
			barkercat = barkercat..", "
		end
		barkercat = barkercat..EnchantrixBarker_GetBarkerEnchantString(enchant);
	end
	barkercat = barkercat.."]"

	return barkercat
end

function EnchantrixBarker_GetBarkerEnchantString( enchant )
	local descString = Enchantrix_GetShortDescriptor(enchant)

	-- remove unnecessary substrings
	descString = descString:gsub(_BARKLOC("BarkerCannotBeAppliedHigher"), "")
	descString = descString:gsub(_BARKLOC("BarkerAddionalPointsOf"), "")

    if Enchantrix_BarkerGetConfig("skillup_mode") then
        enchant_barker = descString;
    else
        enchant_barker = descString.." - ";
        local p_gold,p_silver,p_copper = getGSC(enchant.price);
        if( p_gold > 0 ) then
            enchant_barker = enchant_barker..p_gold.._BARKLOC('OneLetterGold');
        end
        if( p_silver > 0 ) then
            enchant_barker = enchant_barker..p_silver.._BARKLOC('OneLetterSilver');
        end
    end

	--enchant_barker = enchant_barker..", ";
	return enchant_barker
end

local function GetCraftInfoName(enchant)
    if isClassic then
        return GetCraftInfo(enchant.index)
    else
        local recipe = _G.C_TradeSkillUI.GetRecipeInfo(enchant.recipe);
        if recipe then
            return recipe.name;
        else
            --print("recipe unfound ", enchant)
            return "unknown"
        end
    end
end

local function GetCraftInfoDescription(enchant)
    if isClassic then
        return GetCraftInfo(enchant.index)
    else
        return _G.C_TradeSkillUI.GetRecipeDescription(enchant.recipe) or "";
    end
end

function EnchantrixBarker_GetItemCategoryString( enchant )
	local enchant_string = GetCraftInfoDescription( enchant ):lower();
    ---print("Scat searching ", enchant_string );

	for key,category in pairs(categories) do
        --print( "Scat key: ", key, category.search );
		if( enchant_string:find(category.search ) ~= nil ) then
            --print( "Scat key matched: ", key, ", name: ", category.print, ", enchant: ", enchant.name );
			return category.print;
		end
	end

    --print("Unknown Scategory for", enchant.name, enchant_string )
	return 'Unknown';
end

function EnchantrixBarker_GetItemCategoryKey( enchant )
	local enchant_string = GetCraftInfoDescription( enchant ):lower();

	for key,category in pairs(categories) do
        --print( "Kcat key: ", key, ", name: ", category );
		if( enchant_string:find(category.search ) ~= nil ) then
            --print( "Kcat key matched: ", key, ", name: ", category.print, ", enchant: ", enchant.name );
			return key;
		end
	end

    --print("Unknown Kcategory for", enchant.name, enchant_string )
	return 'Unknown';
end

function EnchantrixBarker_GetCraftDescription( enchant )
    --Barker.Util.DebugPrintQuick("GetCraftDescription", enchant.index )
	if not isClassic then
		return _G.C_TradeSkillUI.GetRecipeDescription(enchant.recipe) or "";
	else
		return GetCraftDescription(enchant.index) or "";
	end
end

function Enchantrix_GetShortDescriptor( enchant )
	local long_str = EnchantrixBarker_GetCraftDescription(enchant):lower();
    --print("description = ", long_str )

	if (long_str == NIL) then
		Barker.Util.DebugPrintQuick("Failed enchant name for: ", enchant.index, enchant.name );		-- should not fail
		return "unknown";
	end

	for kk,attribute in ipairs(attributes) do
		if( long_str:find(attribute.search ) ~= nil ) then
            --print("Matched attribute: ", attribute.search, attribute.print, " in: ", long_str);	-- DEBUGGING

			local print_string = attribute.print;
			if (print_string == nil) then
				print("Failed print lookup for: ", long_str);		-- should not fail
				print_string = "unknown";
			end

			if (not attribute.ignoreValues) then
				local foundFirst = long_str:find('[0-9]+[^%%]')		-- this can fail for illusions and items without stats
                --print("first = ", foundFirst )
				if (foundFirst) then
					statvalue = long_str:sub(foundFirst);
                    local moveSpeed = statvalue:find(" and movement speed by");        -- ignore the "and movement speed" bit
                    if moveSpeed then
                        statvalue = statvalue:sub( 1, moveSpeed-1 );
                    end

                    if not statvalue then
                        --print("Failed number parsing1 for: ", long_str, "using :", print_string);
                        return print_string;
                    end

                    local period = statvalue:find("%.");        -- ignore second sentence and beyond ". Cannot be applied..."
                    if period then
                        statvalue = statvalue:sub( 1, period-1 );
                    end
                    --print("first stat = ", statvalue )

                    if not statvalue then
                        --print("Failed number parsing2 for: ", long_str, "using :", print_string);
                        return print_string;
                    end

                    -- remove all extra spaces and text
                    statvalue = statvalue:gsub("[ a-zA-Z]", "")
                    --print("cleaned stat = ", statvalue )

                    local foundSecond = statvalue:find('[0-9]+')
                    --print("second = ", foundSecond )
                    if foundSecond then
                        statvalue = statvalue:sub(foundSecond);
                    end
                    --print("second stat = ", statvalue )

                    return "+"..statvalue..' '..print_string;
				else
                    --print("Failed number lookup for: ", long_str, "using :", print_string);
					return print_string;
				end
			else
				return print_string;
			end
		end
	end


	-- this happens for any enchant we don't have a special case for, which is relatively often
	local enchant_str = GetCraftInfoName(enchant);
    local enchant_split = Barker.Util.Split(enchant_str, "-");  -- returns a table, not a string!

	if (enchant_split == nil) then
        --print("Failed enchant split for: ", enchant_str, long_str );		-- should not fail
		return "unknown";
	end

	return enchant_split[#enchant_split];
end

function EnchantrixBarker_GetEnchantStat( enchant )
	local long_str = EnchantrixBarker_GetCraftDescription(enchant):lower();

	for kk,attribute in ipairs(attributes) do

		--if (not attribute.search or not attribute.key) then
		--	Barker.Util.DebugPrintQuick("bad attribute: ", kk, attribute  );
		--end

		if( long_str:find(attribute.search) ~= nil ) then
			return attribute.key;
		end
	end

	local enchant_str = GetCraftInfoName(enchant);
    enchant_str = Barker.Util.Split(enchant_str, "-");

	return enchant_str[#enchant_str];
end
