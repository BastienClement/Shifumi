--
-- Shifumi !
--

--[[ Constants ]]--

SHIFUMI_ROCK = "Rock"
SHIFUMI_PAPER = "Paper"
SHIFUMI_SCISSORS = "Scissors"

local SHIFUMI_ROCK_ICON = "Interface\\ICONS\\Ability_Warrior_SecondWind"
local SHIFUMI_PAPER_ICON = "Interface\\ICONS\\Ability_Hunter_BeastSoothe"
local SHIFUMI_SCISSORS_ICON = "Interface\\ICONS\\Spell_Holy_UnyieldingFaith"

local SHIFUMI_ICONS = {
	[SHIFUMI_ROCK] = SHIFUMI_ROCK_ICON,
	[SHIFUMI_PAPER] = SHIFUMI_PAPER_ICON,
	[SHIFUMI_SCISSORS] = SHIFUMI_SCISSORS_ICON
}

SHIFUMI_STATE_DEFAULT = 0
SHIFUMI_STATE_REQUEST = 1
SHIFUMI_STATE_SYNCING = 2
SHIFUMI_STATE_SELECT  = 3
SHIFUMI_STATE_WAITING = 4
SHIFUMI_STATE_RESULTS = 5

local SHIFUMI_PROTOCOL_VERSION = 1

--[[ Strings ]]--

local SHIFUMI_DUEL_REQUESTED = "%s has challenged you to a Shifumi duel."
local SHIFUMI_DUEL = "Shifumi Duel"
local SHIFUMI_PREFIX_ERROR = "An error occurred when registering the message prefix for Shifumi duels. You may need to disable some addons."
local SHIFUMI_SELECT_MOVE = "Select your move:"

local SHIFUMI_WIN_ROCK = "The rock blunts the scissors!"
local SHIFUMI_WIN_PAPER = "The paper covers the rock!"
local SHIFUMI_WIN_SCISSORS = "The scissors cut the paper!"
local SHIFUMI_WIN_TIE = "It's a tie!"
local SHIFUMI_WIN_OPPONENT = "%s is the winner"
local SHIFUMI_WIN_SELF = "You are the winner"
local SHIFUMI_WIN_EMOTE = "has defeated %s in a Shifumi duel"

local SHIFUMI_ERROR_VERSION_MISMATCH = "Your opponent is using a different version of Shifumi and thus cannot be dueled."
local SHIFUMI_ERROR_DECLINE = "Shifumi duel cancelled."
local SHIFUMI_ERROR_INVALID_DUEL = "This Shifumi duel is no longer valid."
local SHIFUMI_ERROR_UNAVAILABLE = "%s is not available for a Shifumi duel." 
local SHIFUMI_ERROR_CANCEL = "Shifumi duel cancelled."
local SHIFUMI_ERROR_NOADDON = "%s doesn't seem to have Shifumi installed."
local SHIFUMI_ERROR_STATE = "You cannot start a Shifumi duel now."

--[[ Local vars ]]--

local hasShifumi = {}
local checkThrottle = {}
local checkCurrent = nil

local rules = {
	[SHIFUMI_ROCK] = {
		[SHIFUMI_ROCK] = {winner = 0, text = SHIFUMI_WIN_TIE},
		[SHIFUMI_PAPER] = {winner = 2, text = SHIFUMI_WIN_PAPER},
		[SHIFUMI_SCISSORS] = {winner = 1, text = SHIFUMI_WIN_ROCK}
	},
	[SHIFUMI_PAPER] = {
		[SHIFUMI_ROCK] = {winner = 1, text = SHIFUMI_WIN_PAPER},
		[SHIFUMI_PAPER] = {winner = 0, text = SHIFUMI_WIN_TIE},
		[SHIFUMI_SCISSORS] = {winner = 2, text = SHIFUMI_WIN_SCISSORS}
	},
	[SHIFUMI_SCISSORS] = {
		[SHIFUMI_ROCK] = {winner = 2, text = SHIFUMI_WIN_ROCK},
		[SHIFUMI_PAPER] = {winner = 1, text = SHIFUMI_WIN_SCISSORS},
		[SHIFUMI_SCISSORS] = {winner = 0, text = SHIFUMI_WIN_TIE}
	}
}

local gameState = SHIFUMI_STATE_DEFAULT
local gameMove = nil
local opponentName = nil
local opponentMove = nil
local gameResult = nil

--[[ Timeout Stuff ]]--

local timeRemaining = 0
local timeoutFrame = CreateFrame("Frame")

local function FireShifumiTimeout()
	CancelShifumiDuel()
end

local function CancelShifumiTimeout()
	timeoutFrame:SetScript("OnUpdate", nil);
end

local function TickShifumiTimeout(self, elapsed)
	timeRemaining = timeRemaining - elapsed
	if timeRemaining < 0 then
		CancelShifumiTimeout()
		FireShifumiTimeout()
	end
end

function InitShifumiTimeout(t)
	timeRemaining = t
	timeoutFrame:SetScript("OnUpdate", TickShifumiTimeout);
end

--[[ API ]]--

function SendShifumiMessage(msg, target)
	SendAddonMessage("Shifumi", msg, "WHISPER",  target)
end

function UnitIsShifumiValid(unit)
	return UnitIsPlayer(unit) and UnitCanCooperate("player", unit) and UnitIsSameServer("player", unit)
end

function UnitHasShifumi(unit)
	return hasShifumi[UnitName(unit)]
end

function PlayerShifumiAvailable()
	return gameState == SHIFUMI_STATE_DEFAULT and not UnitAffectingCombat("player")
end

function UnitCanShifumi(unit)
	return UnitHasShifumi(unit) and PlayerShifumiAvailable()
end

function DisplayShifumiError(unit)
	local err
	local name = UnitName(unit)
	
	if not hasShifumi[name] then
		err = SHIFUMI_ERROR_NOADDON:format(name)
	elseif not PlayerShifumiAvailable() then
		err = SHIFUMI_ERROR_STATE
	else
		return
	end
	
	UIErrorsFrame:AddMessage(err, 1, 0, 0, nil, 5)
end

function UnitCheckCanShifumi(unit)
	SendShifumiMessage("CHECK_CAN_SHIFUMI;" .. SHIFUMI_PROTOCOL_VERSION, UnitName(unit))
end

function StartShifumiDuel(unit)
	if not UnitCanShifumi(unit) then DisplayShifumiError(unit) return end
	local unitName = UnitName(unit)
	SendShifumiMessage("START_DUEL", unitName)
	opponentName = unitName
end

function AcceptShifumiDuel()
	if gameState ~= SHIFUMI_STATE_REQUEST then return end
	SendShifumiMessage("ACCEPT_DUEL", opponentName)
	gameState = SHIFUMI_STATE_SYNCING
	InitShifumiTimeout(3)
end

function DeclineShifumiDuel()
	if gameState ~= SHIFUMI_STATE_REQUEST then return end
	SendShifumiMessage("DECLINE_DUEL", opponentName)
	gameState = SHIFUMI_STATE_DEFAULT
end

local function _ResetShifumi()
	CancelShifumiTimeout()
	gameState = SHIFUMI_STATE_DEFAULT
	gameMove = nil
	opponentName = nil
	opponentMove = nil
	gameResult = nil
end

function ResetShifumi()
	if gameState ~= SHIFUMI_STATE_RESULTS then return end
	_ResetShifumi()
end

function CancelShifumiDuel()
	if gameState == SHIFUMI_STATE_REQUEST then
		StaticPopup_Hide("SHIFUMI_DUEL_REQUESTED")
	elseif gameState == SHIFUMI_STATE_SYNCING then
		-- Nothing
	elseif gameState == SHIFUMI_STATE_SELECT then
		ShifumiPlayFrame.FadeOutNoDelay:Play()
	elseif gameState == SHIFUMI_STATE_WAITING then
		ShifumiPlayFrame.FadeOutNoDelay:Play()
	else
		return
	end
	
	PlaySoundFile("Sound\\INTERFACE\\UI_Pet_Levelup_01.OGG")
	SendShifumiMessage("CANCEL_DUEL", opponentName)
	UIErrorsFrame:AddMessage(SHIFUMI_ERROR_CANCEL, 1, 1, 0, nil, 5)
	
	_ResetShifumi()
end

function ShifumiSelectMove(move)
	if gameState ~= SHIFUMI_STATE_SELECT then return end
	if move ~= SHIFUMI_ROCK and move ~= SHIFUMI_PAPER and move ~= SHIFUMI_SCISSORS then return end
	
	gameMove = move
	gameState = SHIFUMI_STATE_WAITING
	
	SendShifumiMessage("MOVE_SELECTED;" .. move, opponentName)
	PlaySoundFile("Sound\\INTERFACE\\UI_PetBattle_InitiateBattle.OGG")
	
	if move == SHIFUMI_ROCK then
		ShifumiPlayFrame.SelectRock:Play()
	elseif move == SHIFUMI_PAPER then
		ShifumiPlayFrame.SelectPaper:Play()
	elseif move == SHIFUMI_SCISSORS then
		ShifumiPlayFrame.SelectScissors:Play()
	end
	
	DisplayShifumiResults()
end

function GetShifumiState()
	return gameState
end

function DisplayShifumiResults()
	if gameState ~= SHIFUMI_STATE_SELECT and gameState ~= SHIFUMI_STATE_WAITING then return end
	if not gameMove or not opponentMove then return end
	
	local rule = rules[gameMove][opponentMove]
	
	gameState = SHIFUMI_STATE_RESULTS
	gameResult = rule.winner
	
	ShifumiResultsFrame.SelfName:SetText(UnitName("player"))
	ShifumiResultsFrame.OpponentName:SetText(opponentName)
	ShifumiResultsFrame.SelfMove:SetTexture(SHIFUMI_ICONS[gameMove])
	ShifumiResultsFrame.OpponentMove:SetTexture(SHIFUMI_ICONS[opponentMove])
	ShifumiResultsFrame.Text1:SetText(rule.text)
	
	if gameResult ~= 0 then
		ShifumiResultsFrame.Text2:SetText(gameResult == 1 and SHIFUMI_WIN_SELF or SHIFUMI_WIN_OPPONENT:format(opponentName))
	else
		ShifumiResultsFrame.Text2:SetText("")
	end
	
	ShifumiPlayFrame.FadeOut:Play()
end

function DoShifumiEmote()
	if gameState ~= SHIFUMI_STATE_RESULTS or not UnitIsVisible(opponentName) then return end
	SendChatMessage(SHIFUMI_WIN_EMOTE:format(opponentName), "EMOTE")
end

function GetShifumiResult()
	return gameResult
end

--[[ Static Popups ]]--

StaticPopupDialogs["SHIFUMI_PREFIX_ERROR"] = {
	text = SHIFUMI_PREFIX_ERROR,
	button1 = OKAY
}

if not RegisterAddonMessagePrefix("Shifumi") then
	StaticPopup_Show("SHIFUMI_PREFIX_ERROR")
	return
end

StaticPopupDialogs["SHIFUMI_DUEL_REQUESTED"] = {
	text = SHIFUMI_DUEL_REQUESTED,
	button1 = ACCEPT,
	button2 = DECLINE,
	sound = "igPlayerInvite",
	OnAccept = AcceptShifumiDuel,
	OnCancel = DeclineShifumiDuel,
	timeout = STATICPOPUP_TIMEOUT,
	hideOnEscape = 1
}

--[[ Unit menu button ]]--

UnitPopupButtons["SHIFUMI_DUEL"] = { text = SHIFUMI_DUEL, dist = 0 }

for menu, items in pairs(UnitPopupMenus) do
	for i = 0, #items do
		if items[i] == "DUEL" then
			table.insert(items, i + 1, "SHIFUMI_DUEL")
			break
		end
	end
end

hooksecurefunc("UnitPopup_HideButtons", function()
	local dropdownMenu = UIDROPDOWNMENU_INIT_MENU;
	local which = dropdownMenu.which
	local unit = dropdownMenu.unit
	if which and not UnitIsShifumiValid(unit) then
		for index, value in ipairs(UnitPopupMenus[which]) do
			if UnitPopupShown[1][index] == 1 and value == "SHIFUMI_DUEL" then
				UnitPopupShown[1][index] = 0
				break
			end
		end
	end
end)

hooksecurefunc("UnitPopup_OnUpdate", function(elapsed)
	if not DropDownList1:IsShown() then
        return
    end
	
	local currentDropDown = UIDROPDOWNMENU_OPEN_MENU;
	local unit = currentDropDown.unit

	if not unit then
		return
	end
	
	local unitName = currentDropDown.unit, UnitName(currentDropDown.unit)
	
	if not UnitHasShifumi(unit) and UnitIsShifumiValid(unit) then
		if not checkThrottle[unitName] or checkCurrent ~= unitName then
			checkThrottle[unitName] = -1
		end
		checkCurrent = unitName
		if checkThrottle[unitName] < 0 then
			SendShifumiMessage("CHECK_CAN_SHIFUMI;" .. SHIFUMI_PROTOCOL_VERSION, UnitName(unit))
			checkThrottle[unitName] = 10
		else
			checkThrottle[unitName] = checkThrottle[unitName] - elapsed
		end
	end
	
	for level, dropdownFrame in pairs(OPEN_DROPDOWNMENUS) do
		if dropdownFrame then
            local count = 0
			for index, value in ipairs(UnitPopupMenus[dropdownFrame.which]) do
				if UnitPopupShown[level][index] == 1 then
					count = count + 1
					if value == "SHIFUMI_DUEL" then
						if level <= 1 then
							count = count + 1
						end
						if UnitCanShifumi(unit) then
							UIDropDownMenu_EnableButton(level, count)
						else
							UIDropDownMenu_DisableButton(level, count)
						end
						return
					end
				end
			end
		end
	end
end)

hooksecurefunc("UnitPopup_OnClick", function(self)
	local dropdownFrame = UIDROPDOWNMENU_INIT_MENU;
	local button = self.value;
    local unit = dropdownFrame.unit;
	if button == "SHIFUMI_DUEL" then
		StartShifumiDuel(unit)
	end
end)

--[[ Messages ]]--

local function SplitMessage(msg)
	local parts = {}
	for part in msg:gmatch("([^;]+)") do
		parts[#parts + 1] = part
	end
	return unpack(parts)
end

local function AddonMsgListener(self, _, prefix, msg, channel, sender)
	if prefix ~= "Shifumi" then
		return
	end
	local action, arg1, arg2 = SplitMessage(msg)
	if action == "CHECK_CAN_SHIFUMI" then
		if tonumber(arg1) == SHIFUMI_PROTOCOL_VERSION then
			SendShifumiMessage("CAN_SHIFUMI", sender)
		else
			SendShifumiMessage("VERSION_MISMATCH", sender)
		end
	elseif action == "START_DUEL" then
		if PlayerShifumiAvailable() then
			gameState = SHIFUMI_STATE_REQUEST
			opponentName = sender
			StaticPopup_Show("SHIFUMI_DUEL_REQUESTED", sender)
		else
			SendShifumiMessage("UNAVAILABLE", sender)
		end
	elseif action == "ACCEPT_DUEL" then
		if gameState == SHIFUMI_STATE_DEFAULT then
			if sender == opponentName then
				gameState = SHIFUMI_STATE_SELECT
				ShifumiPlayFrame:Show()
				SendShifumiMessage("SYNC_DUEL", opponentName)
				InitShifumiTimeout(10)
			else
				SendShifumiMessage("INVALID_DUEL", sender)
			end
		end
	elseif action == "SYNC_DUEL" then
		if sender == opponentName and gameState == SHIFUMI_STATE_SYNCING then
			CancelShifumiTimeout()
			gameState = SHIFUMI_STATE_SELECT
			ShifumiPlayFrame:Show()
		end
	elseif action == "MOVE_SELECTED" then
		if sender == opponentName and (gameState == SHIFUMI_STATE_SELECT or gameState == SHIFUMI_STATE_WAITING) then
			if arg1 == SHIFUMI_ROCK or arg1 == SHIFUMI_PAPER or arg1 == SHIFUMI_SCISSORS then
				CancelShifumiTimeout()
				opponentMove = arg1
				DisplayShifumiResults()
			end
		end
	elseif action == "DECLINE_DUEL" then
		if sender == opponentName and gameState == SHIFUMI_STATE_DEFAULT then
			UIErrorsFrame:AddMessage(SHIFUMI_ERROR_DECLINE, 1, 1, 0, nil, 5)
			opponentName = nil
		end
	elseif action == "UNAVAILABLE" then
		if sender == opponentName and gameState == SHIFUMI_STATE_DEFAULT then
			UIErrorsFrame:AddMessage(SHIFUMI_ERROR_UNAVAILABLE:format(opponentName), 1, 0, 0, nil, 5)
			opponentName = nil
		end
	elseif action == "CAN_SHIFUMI" then
		hasShifumi[sender] = true
	elseif action == "CANCEL_DUEL" then
		if sender == opponentName then
			CancelShifumiDuel()
		end
	elseif action == "INVALID_DUEL" then
		if sender == opponentName and gameState == SHIFUMI_STATE_SYNCING then
			CancelShifumiTimeout()
			UIErrorsFrame:AddMessage(SHIFUMI_ERROR_INVALID_DUEL, 1, 0, 0, nil, 5)
			gameState = SHIFUMI_STATE_DEFAULT
			opponentName = nil
		end
	elseif action == "VERSION_MISMATCH" then
		UIErrorsFrame:AddMessage(SHIFUMI_ERROR_VERSION_MISMATCH, 1, 0, 0, nil, 5)
	end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:SetScript("OnEvent", AddonMsgListener);

--[[ UI ]]--

ShifumiPlayFrame.TitleText:SetText(SHIFUMI_SELECT_MOVE)
ShifumiPlayFrame.Rock.Icon:SetTexture(SHIFUMI_ROCK_ICON)
ShifumiPlayFrame.Paper.Icon:SetTexture(SHIFUMI_PAPER_ICON)
ShifumiPlayFrame.Scissors.Icon:SetTexture(SHIFUMI_SCISSORS_ICON)
