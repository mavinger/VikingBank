-----------------------------------------------------------------------------------------------
-- Client Lua Script for VikingBank
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Apollo"
require "Window"
require "Money"

local VikingBank = {}
local knMaxBankBagSlots = 5
local knBagBoxSize = 50
local knSaveVersion = 1

function VikingBank:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function VikingBank:Init()
    Apollo.RegisterAddon(self)
end

function VikingBank:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("VikingBank.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self) 
end

function VikingBank:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end
	
	Apollo.RegisterEventHandler("HideBank", "HideBank", self)
	Apollo.RegisterEventHandler("ShowBank", "Initialize", self)
    Apollo.RegisterEventHandler("ToggleBank", "Initialize", self)
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCloseVendorWindow", self)
	Apollo.RegisterEventHandler("PlayerCurrencyChanged", "ComputeCashLimits", self)
	Apollo.RegisterEventHandler("BankSlotPurchased", "OnBankSlotPurchased", self)
	Apollo.RegisterEventHandler("PersonaUpdateCharacterStats", "RefreshBagCount", self)

	Apollo.RegisterTimerHandler("VikingBank_NewBagPurchasedAlert", "OnVikingBank_NewBagPurchasedAlert", self)

	self.wndMain = nil -- TODO RESIZE CODE
end

function VikingBank:Initialize()
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:Close()
		self.wndMain:Destroy()
		self.wndMain = nil
	end

	self.wndMain = Apollo.LoadForm("VikingBank.xml", "VikingBankForm", nil, self)
	self.wndMain:FindChild("BankBuySlotBtn"):AttachWindow(self.wndMain:FindChild("BankBuySlotConfirm"))
	Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = Apollo.GetString("Bank_Header")})
	
	self:Build()
end

function VikingBank:Build()
	local nNumBagSlots = GameLib.GetNumBankBagSlots()

	self.wndMain:FindChild("ConfigureBagsContainer"):DestroyChildren()

	-- Configure Screen
	for idx = 1, knMaxBankBagSlots do
		local idBag = idx + 20
		local wndCurr = Apollo.LoadForm(self.xmlDoc, "BankSlot", self.wndMain:FindChild("ConfigureBagsContainer"), self)
		local wndBagBtn = Apollo.LoadForm(self.xmlDoc, "BagBtn"..idBag, wndCurr:FindChild("BankSlotFrame"), self)
		if wndBagBtn:GetItem() then
			wndCurr:FindChild("BagCount"):SetText(wndBagBtn:GetItem():GetBagSlots())
		end
		wndCurr:FindChild("BagCount"):SetData(wndBagBtn)
		wndCurr:FindChild("BagLocked"):Show(idx > nNumBagSlots)
		wndCurr:FindChild("NewBagPurchasedAlert"):Show(false, true)
		wndBagBtn:Enable(idx <= nNumBagSlots)
	end
	self.wndMain:FindChild("ConfigureBagsContainer"):ArrangeChildrenHorz(1)

	-- Hide the bottom bar if at max
	if nNumBagSlots >= knMaxBankBagSlots then
		local nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("BankGridArt"):GetAnchorOffsets()
		self.wndMain:FindChild("BankGridArt"):SetAnchorOffsets(nLeft, nTop, nRight, nBottom + 65) -- todo hardcoded formatting

		nLeft, nTop, nRight, nBottom = self.wndMain:FindChild("BankBagArt"):GetAnchorOffsets()
		self.wndMain:FindChild("BankBagArt"):SetAnchorOffsets(nLeft, nTop + 65, nRight, nBottom + 65)
		self.wndMain:FindChild("BankBottomArt"):Show(false)
	else
		self:ComputeCashLimits()
	end

	-- Resize
	self:ResizeBankSlots()
end

function VikingBank:RefreshBagCount()
	if not self.wndMain or not self.wndMain:IsValid() or not self.wndMain:IsShown() then
		return
	end

	for key, wndCurr in pairs(self.wndMain:FindChild("ConfigureBagsContainer"):GetChildren()) do
		local wndBagBtn = wndCurr:FindChild("BagCount"):GetData()
		if wndBagBtn and wndBagBtn:GetItem() then
			wndCurr:FindChild("BagCount"):SetText(wndBagBtn:GetItem():GetBagSlots())
		elseif wndBagBtn then
			wndCurr:FindChild("BagCount"):SetText("")
		end
	end
end

function VikingBank:OnWindowClosed()
	Event_CancelBanking()
	
	self:HideBank()
end

function VikingBank:OnCloseVendorWindow()
	self:HideBank()
end

function VikingBank:HideBank()
	if self.wndMain and self.wndMain:IsValid() then
		local wndMain = self.wndMain
		self.wndMain = nil
		wndMain:Close()
		wndMain:Destroy()
	end
end

function VikingBank:ComputeCashLimits()
	if not self.wndMain or not self.wndMain:IsValid() or not self.wndMain:IsShown() then
		return
	end

	local nNextBankBagCost = GameLib.GetNextBankBagCost():GetAmount()
	local nPlayerCash = GameLib.GetPlayerCurrency():GetAmount()
	if nNextBankBagCost > nPlayerCash then
		self.wndMain:FindChild("BankBuyPrice"):SetTextColor(ApolloColor.new("red"))
		self.wndMain:FindChild("BankBuyPrice"):SetTooltip(Apollo.GetString("Bank_CanNotAfford"))
		self.wndMain:FindChild("BankBuySlotBtn"):Enable(false)
	else
		self.wndMain:FindChild("BankBuyPrice"):SetTextColor(ApolloColor.new("white"))
		self.wndMain:FindChild("BankBuyPrice"):SetTooltip(Apollo.GetString("Bank_SlotPriceTooltip"))
		self.wndMain:FindChild("BankBuySlotBtn"):Enable(true)
	end
	self.wndMain:FindChild("BankBuyPrice"):SetAmount(nNextBankBagCost, true)
	self.wndMain:FindChild("PlayerMoney"):SetAmount(nPlayerCash)
end

function VikingBank:ResizeBankSlots()
	if not self.wndMain or not self.wndMain:IsValid() or not self.wndMain:IsShown() then
		return
	end

	local nNumberOfBoxesPerRow = math.floor(self.wndMain:FindChild("MainBagWindow"):GetWidth() / knBagBoxSize)
	self.wndMain:FindChild("MainBagWindow"):SetBoxesPerRow(nNumberOfBoxesPerRow)

	-- Labels
	self:RefreshBagCount()

	-- Money
	local nNextBankBagCost = GameLib.GetNextBankBagCost():GetAmount()
	local nPlayerCash = GameLib.GetPlayerCurrency():GetAmount()
	self.wndMain:FindChild("PlayerMoney"):SetAmount(nPlayerCash)
	self.wndMain:FindChild("BankBuySlotBtn"):Enable(nNextBankBagCost <= nPlayerCash)
end

function VikingBank:OnBankViewerCloseBtn()
	self:HideBank()
end

function VikingBank:OnBankBuyConfirmClose()
	self.wndMain:FindChild("BankBuySlotBtn"):SetCheck(false)
end

function VikingBank:OnBankBuySlotConfirmYes()
	GameLib.BuyBankBagSlot()
	self.wndMain:FindChild("BankBuySlotBtn"):SetCheck(false)
	self:ResizeBankSlots()
end

function VikingBank:OnVikingBank_NewBagPurchasedAlert()
	if self.wndMain and self.wndMain:IsValid() then
		for idx, wndCurr in pairs(self.wndMain:FindChild("ConfigureBagsContainer"):GetChildren()) do
			wndCurr:FindChild("NewBagPurchasedAlert"):Show(false)
		end
		self.wndMain:FindChild("BankTitleText"):SetText(Apollo.GetString("Bank_Header"))
	end
end

function VikingBank:OnBankSlotPurchased()
	self.wndMain:FindChild("BankTitleText"):SetText(Apollo.GetString("Bank_BuySuccess"))
	Apollo.CreateTimer("VikingBank_NewBagPurchasedAlert", 12, false)
	self:Build()
end

function VikingBank:OnGenerateTooltip(wndControl, wndHandler, tType, item)
	if wndControl ~= wndHandler then return end
	wndControl:SetTooltipDoc(nil)
	if item ~= nil then
		local itemEquipped = item:GetEquippedItemForItemType()
		Tooltip.GetItemTooltipForm(self, wndControl, item, {bPrimary = true, bSelling = false, itemCompare = itemEquipped})
	end
end

local VikingBankInst = VikingBank:new()
VikingBankInst:Init()
