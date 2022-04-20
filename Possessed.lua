local addonName, addonTable = ...

local channels = {
	[GetSpellInfo(605)]   = true, -- Mind Control
	[GetSpellInfo(1002)]  = true, -- Eyes of the Beast
	[GetSpellInfo(45839)] = true, -- Vengeance of the Blue Flight
}

local channel_opt = ""
for spell, enabled in pairs(channels) do
	channel_opt = channel_opt .. string.format("[channeling:%s]", spell)
end
if channel_opt == "" then
	channel_opt = "false"
else
	channel_opt = channel_opt .. " true; false"
end

local handler = CreateFrame("Frame", nil, nil, "SecureHandlerAttributeTemplate")

if not InCombatLockdown() then
	local channel_state = addonName:lower() .. "-channel"

	for i = 1, NUM_PET_ACTION_SLOTS do
		local button = "ActionButton" .. i
		handler:SetFrameRef(button, _G[button])
	end

	handler:Execute(([[
		defaults = newtable()
		for i = 1, %d do
			local button = self:GetFrameRef("ActionButton" .. i)
			defaults[i] = defaults[i] or newtable()
			defaults[i].type = button:GetAttribute("type")
			defaults[i].action = button:GetAttribute("action")
			defaults[i].unit = button:GetAttribute("unit")
		end
	]]):format(NUM_PET_ACTION_SLOTS))

	handler:SetAttribute("_onattributechanged", ([[ -- self, name, value
		if name == "possessed-channel" then
			for i = 1, %d do
				local button = self:GetFrameRef("ActionButton" .. i)
				if value == "true" then
					defaults[i] = defaults[i] or newtable()
					defaults[i].type = button:GetAttribute("type")
					defaults[i].action = button:GetAttribute("action")
					defaults[i].unit = button:GetAttribute("unit")

					button:SetAttribute("type", "pet")
					button:SetAttribute("action", i)
					button:SetAttribute("unit", nil)
				else
					button:SetAttribute("type", defaults[i].type)
					button:SetAttribute("action", defaults[i].action)
					button:SetAttribute("unit", defaults[i].unit)
				end
			end
		end
	]]):format(NUM_PET_ACTION_SLOTS))

	RegisterAttributeDriver(handler, channel_state, channel_opt)
end
