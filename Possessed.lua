local addonName, addonTable = ...

local handler = CreateFrame("Frame", addonName .. "SecureHandler", nil, "SecureHandlerAttributeTemplate")

local prefix = addonName:lower()
local possessing = prefix .. "-possessing"

--Hybrid reimplementation of ActionButton.lua and PetActionBarFrame.lua

local function PossessedActionButton_UpdateState(button)
	assert(button);

	local action = button:GetAttribute("action")
	local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(action)
	local isChecked = isActive
	button:SetChecked(isChecked);
end

local function PossessedActionButton_UpdateUsable(self)
	local action = self:GetAttribute("action")
	local icon = self.icon;

	local isUsable = GetPetActionSlotUsable(action);
	if ( isUsable ) then
		icon:SetVertexColor(1.0, 1.0, 1.0);
	else
		icon:SetVertexColor(0.4, 0.4, 0.4);
	end
end

local function PossessedActionButton_UpdateCooldown(self)
	local action = self:GetAttribute("action")
	local charges, maxCharges, chargeStart, chargeDuration;
	local start, duration, enable = GetPetActionCooldown(action)
	local modRate = 1.0;
	local chargeModRate = 1.0;

	if ( self.cooldown.currentCooldownType ~= COOLDOWN_TYPE_NORMAL ) then
		self.cooldown:SetEdgeTexture("Interface\\Cooldown\\edge");
		self.cooldown:SetSwipeColor(0, 0, 0);
		self.cooldown:SetHideCountdownNumbers(false);
		self.cooldown.currentCooldownType = COOLDOWN_TYPE_NORMAL;
	end

	ClearChargeCooldown(self);

	CooldownFrame_Set(self.cooldown, start, duration, enable, false, modRate);
end

local function PossessedActionButton_StartFlash(self)
	-- Use our own flashing flag so that Blizzard's doesn't interefere
	self.possessed_flashing = 1;
	self.flashtime = 0;
	PossessedActionButton_UpdateState(self);
end

local function PossessedActionButton_StopFlash(self)
	self.possessed_flashing = 0;
	self.Flash:Hide();
	PossessedActionButton_UpdateState(self);
end

local function PossessedActionButton_IsFlashing(self)
	return self.possessed_flashing == 1
end

local function PossessedActionButton_UpdateFlash(self)
	local action = self:GetAttribute("action")
	local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(action)
	if IsPetAttackAction(action) and isActive then
		PossessedActionButton_StartFlash(self);
		
		self:GetCheckedTexture():SetAlpha(0.5);
	else
		PossessedActionButton_StopFlash(self);
	end
	
	if self.AutoCastable then
		self.AutoCastable:SetShown(autoCastEnabled);
		if autoCastEnabled then
			self.AutoCastShine:Show();
			AutoCastShine_AutoCastStart(self.AutoCastShine);
		else
			self.AutoCastShine:Hide();
			AutoCastShine_AutoCastStop(self.AutoCastShine);
		end
	end
end

local PetActionEvents = {
	-- PetActionBar
	["PET_BAR_HIDEGRID"] = true,
	["PET_BAR_SHOWGRID"] = true,
	["PET_BAR_UPDATE"] = true,
	["PET_BAR_UPDATE_COOLDOWN"] = true,
	["PET_BAR_UPDATE_USABLE"] = true,
	["PET_UI_UPDATE"] = true,
	["PLAYER_CONTROL_GAINED"] = true,
	["PLAYER_CONTROL_LOST"] = true,
	["PLAYER_FARSIGHT_FOCUS_CHANGED"] = true,
	["PLAYER_MOUNT_DISPLAY_CHANGED"] = true,
	["UNIT_FLAGS"] = true,
	["UNIT_PET"] = true,
	["UNIT_AURA"] = true,

	-- ActionBarButtonEventsFrame
	-- We can't unregister + reregister the button from this frame's event
	-- handler without causing taint, so we update on its events as well
	["PLAYER_ENTERING_WORLD"] = true,
	["ACTIONBAR_SHOWGRID"] = true,
	["ACTIONBAR_HIDEGRID"] = true,
	["ACTIONBAR_SLOT_CHANGED"] = true,
	["UPDATE_BINDINGS"] = true,
	["UPDATE_SHAPESHIFT_FORM"] = true,
	["ACTIONBAR_UPDATE_COOLDOWN"] = true,
}

-- Define these early so we can use them in the event handler
local PossessedActionButton_Update
local PetActionEvents_RegisterFrame
local PetActionEvents_UnregisterFrame
local PossessedActionButton_SetTooltip

local hookedFrames = {}
local function PetAction_OnEvent(self, event, ...)
	local action = self:GetAttribute("action")
	if event == "PET_BAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
		PossessedActionButton_UpdateCooldown(self)
	else
		PossessedActionButton_Update(self)
	end
end

PetActionEvents_RegisterFrame = function(self)
	for event, _ in pairs(PetActionEvents) do
		if event == "UNIT_AURA" or event == "UNIT_FLAGS" then
			self:RegisterUnitEvent(event, "pet")
		else
			self:RegisterEvent(event)
		end
	end

	ActionBarActionEventsFrame_UnregisterFrame(self)

	if not hookedFrames[self] then
		hookedFrames[self] = true
		self:HookScript("OnEvent", PetAction_OnEvent)
	end
end

PetActionEvents_UnregisterFrame = function(self)
	for event, _ in pairs(PetActionEvents) do
		self:UnregisterEvent(event)
	end

	ActionBarActionEventsFrame_RegisterFrame(self)
end

PossessedActionButton_Update = function(self)
	local action = self:GetAttribute("action")
	local icon = self.icon;
	local buttonCooldown = self.cooldown;

	local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(action)

	if name then
		if ( not self.petEventsRegistered ) then
			PetActionEvents_RegisterFrame(self)
			self.petEventsRegistered = true
		end

		PossessedActionButton_UpdateState(self);
		PossessedActionButton_UpdateUsable(self);
		PossessedActionButton_UpdateCooldown(self);
		PossessedActionButton_UpdateFlash(self);
		ActionButton_UpdateHighlightMark(self);
		ActionButton_UpdateSpellHighlightMark(self);
	else
		if ( self.petEventsRegistered ) then
			PetActionEvents_UnregisterFrame(self);
			self.petEventsRegistered = nil;
		end

		if ( self:GetAttribute("showgrid") ~= 0 ) then
			buttonCooldown:Hide();
		end

		ClearChargeCooldown(self);

		ActionButton_ClearFlash(self);
		self:SetChecked(false);
	end

	-- Hide border used by item actions
	local border = self.Border;
	if border then
		border:Hide();
	end

	-- Remove action text if there is any
	local actionName = self.Name;
	if actionName then
		actionName:SetText("");
	end

	-- Token is something unique to pet actions
	if isToken then
		texture = _G[texture]
		self.tooltipName = _G[name]
	end

	-- Update icon and hotkey text
	if ( texture ) then
		icon:SetTexture(texture);
		icon:Show();
		self.possessedRangeTimer = -1;
		ActionButton_UpdateCount(self);
	else
		self.Count:SetText("");
		icon:Hide();
		buttonCooldown:Hide();
		self.possessedRangeTimer = nil;
		local hotkey = self.HotKey;
		if ( hotkey:GetText() == RANGE_INDICATOR ) then
			hotkey:Hide();
		else
			hotkey:SetVertexColor(0.6, 0.6, 0.6);
		end
	end

	-- Update tooltip
	if ( GameTooltip:GetOwner() == self ) then
		PossessedActionButton_SetTooltip(self);
	end

	self.feedback_action = action;
end

local function PossessedActionButton_UpdateAction(self, name, value)
	local action = self:GetAttribute("action")
	if not action then return end
	PossessedActionButton_Update(self)
end

PossessedActionButton_SetTooltip = function(self)
	local action = self:GetAttribute("action")
	if ( GetCVar("UberTooltips") == "1" ) then
		GameTooltip_SetDefaultAnchor(GameTooltip, self);
	else
		local parent = self:GetParent();
		if ( parent == MultiBarBottomRight or parent == MultiBarRight or parent == MultiBarLeft ) then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT");
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		end
	end
	if ( GameTooltip:SetPetAction(action) ) then
		self.UpdateTooltip = PossessedActionButton_SetTooltip;
	else
		self.UpdateTooltip = nil;
	end
end

local function PossessedActionButton_OnUpdate(self, elapsed)
	local action = self:GetAttribute("action")

	if ( PossessedActionButton_IsFlashing(self) ) then
		local flashtime = self.flashtime;
		flashtime = flashtime - elapsed;

		if ( flashtime <= 0 ) then
			local overtime = -flashtime;
			if ( overtime >= ATTACK_BUTTON_FLASH_TIME ) then
				overtime = 0;
			end
			flashtime = ATTACK_BUTTON_FLASH_TIME - overtime;

			local flashTexture = self.Flash;
			if ( flashTexture:IsShown() ) then
				flashTexture:Hide();
			else
				flashTexture:Show();
			end
		end

		self.flashtime = flashtime;
	end

	-- Disable the regular action range indicator and use our own
	self.rangeTimer = nil
	local possessedRangeTimer = self.possessedRangeTimer;
	if ( possessedRangeTimer ) then
		possessedRangeTimer = possessedRangeTimer - elapsed;

		if ( possessedRangeTimer <= 0 ) then

			local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID, checksRange, inRange = GetPetActionInfo(action);
			ActionButton_UpdateRangeIndicator(self, checksRange, inRange);
			possessedRangeTimer = TOOLTIP_UPDATE_TIME;
		end

		self.possessedRangeTimer = possessedRangeTimer;
	end
end

-- Fully secure handling of specific channeled possession spells
local channels = {
	[GetSpellInfo(605)]   = true, -- Mind Control (Priest)
	[GetSpellInfo(1002)]  = true, -- Eyes of the Beast (Hunter)
	[GetSpellInfo(19832)] = true, -- Possess (Razorgore the Untamed)
	[GetSpellInfo(45839)] = true, -- Vengeance of the Blue Flight (Kil'jaeden)
}

local channel_opt = ""
local channels_enabled = false
for spell, enabled in pairs(channels) do
	if enabled then
		channels_enabled = true
		channel_opt = channel_opt .. string.format("[channeling:%s]", spell)
	end
end
if channels_enabled then
	channel_opt = channel_opt .. " true; false"
else
	channel_opt = "false"
end
local channeling = prefix .. "-channeling"

-- Karazhan Chess Event
handler:RegisterEvent("ENCOUNTER_START")
local chess = prefix .. "-chess"
local chess_opt = "[pet] true; false]"

-- Partially secure handling of possessions started
-- while not in combat. Falls back to regular action bars if the
-- pet dies or despawns while you are in combat.
-- This should handle most open-world quest items without
-- needing to maintain a list.
-- If something *else* happens to the pet and you remain in combat,
-- we can't securely reset the action bars until you leave combat.
local noncombat_opt = "[@pet,noexists][@pet,dead] false"
local noncombat = prefix .. "-noncombat"

handler:RegisterUnitEvent("UNIT_PET", "player")
handler:RegisterEvent("PLAYER_REGEN_DISABLED")
handler:SetScript("OnEvent", function(self, event, ...)
	if not InCombatLockdown() then
		if event == "UNIT_PET"
		or event == "PLAYER_REGEN_DISABLED" and handler:GetAttribute(possessing) == "true"
		then
			handler:SetAttribute(noncombat, tostring(UnitIsPossessed("pet")))
		elseif event == "ENCOUNTER_START" and (...) == 660 then
			RegisterAttributeDriver(handler, chess, chess_opt)
			self:RegisterEvent("PLAYER_REGEN_ENABLED")
		elseif event == "PLAYER_REGEN_ENABLED" then
			UnregisterAttributeDriver(handler, chess)
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		end
	end
end)

-- Fully secure handling of Teron Gorefiend's Shadow of Death
local teron_opt = "[@player,dead] true; false"
local teron = prefix .. "-teron"

if not InCombatLockdown() then
	for i = 1, NUM_PET_ACTION_SLOTS do
		local buttonName = "ActionButton" .. i
		local button = _G[buttonName]
		handler:SetFrameRef(buttonName, _G[buttonName])

		-- Post-hook most of the scripts in ActionBarFrame.xml,
		-- so that we run after they do
		button:HookScript("OnAttributeChanged", function(self, name, value)
			if handler:GetAttribute(possessing) ~= "true" then return end
			PossessedActionButton_UpdateAction(self, name, value)
		end)

		button:HookScript("OnEnter", function(self)
			if handler:GetAttribute(possessing) ~= "true" then return end
			PossessedActionButton_UpdateAction(self, true)
			PossessedActionButton_SetTooltip(self);
		end)

		button:HookScript("OnUpdate", function(self, elapsed)
			if handler:GetAttribute(possessing) ~= "true" then return end
			PossessedActionButton_OnUpdate(self, elapsed)
		end)
	end

	handler:HookScript("OnAttributeChanged", function(self, name, value)
		if name == possessing then
			for i = 1, NUM_PET_ACTION_SLOTS do
				local buttonName = "ActionButton" .. i
				local button = _G[buttonName]

				if value == "true" then
					PetActionEvents_RegisterFrame(button)
				elseif value == "false" then
					PetActionEvents_UnregisterFrame(button)
				end

				ActionButton_UpdateHotkeys(button, button.buttonType)
			end
		end
	end)

	handler:Execute([[
		defaults = newtable()
	]])

	handler:SetAttribute("_onattributechanged", ([[ -- self, name, value
		local possessing = "%s"
		local channeling = "%s"
		local noncombat = "%s"
		local teron = "%s"
		local chess = "%s"
		local NUM_PET_ACTION_SLOTS = %d

		if name == possessing then
			for i = 1, NUM_PET_ACTION_SLOTS do
				local button = self:GetFrameRef("ActionButton" .. i)
				if value == "true" then
					if not defaults[i] or not defaults[i].updated then
						defaults[i] = defaults[i] or newtable()
						defaults[i].type = button:GetAttribute("type")
						defaults[i].action = button:GetAttribute("action")
						defaults[i].unit = button:GetAttribute("unit")
						defaults[i].showgrid = button:GetAttribute("showgrid")
						defaults[i].updated = true
					end

					button:SetAttribute("type", "pet")
					button:SetAttribute("action", i)
					button:SetAttribute("unit", nil)
					button:SetAttribute("showgrid", 1)

					button:Show()
				elseif defaults[i] and defaults[i].updated then
					button:SetAttribute("type", defaults[i].type)
					button:SetAttribute("action", defaults[i].action)
					button:SetAttribute("unit", defaults[i].unit)
					button:SetAttribute("showgrid", defaults[i].showgrid)
					defaults[i].updated = false
				end
			end
		elseif name == channeling or name == noncombat then
			self:SetAttribute(possessing, value)
		elseif name == teron then
			-- We are dead but our pet is alive
			local isPossessing = tostring(value == "true" and not UnitIsDead("pet"))
			self:SetAttribute(possessing, isPossessing)
		elseif name == chess then
			-- Check that creatureFamily is nil to confirm that
			-- we have a chess piece instead of a hunter/lock pet
			local creatureFamily, name = PlayerPetSummary()
			local isPossessing = tostring(value == "true" and (not creatureFamily)))
			self:SetAttribute(possessing, isPossessing)
		end
	]]):format(possessing, channeling, noncombat, teron, chess, NUM_PET_ACTION_SLOTS))

	RegisterAttributeDriver(handler, channeling, channel_opt)
	RegisterAttributeDriver(handler, noncombat, noncombat_opt)
	RegisterAttributeDriver(handler, teron, teron_opt)
end
