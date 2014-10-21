require "Apollo"
require "Window"
require "Money"

--------------------------------------------------------------------------------
-- VikingBank Module Definition
--------------------------------------------------------------------------------
local VikingBank = {
  _VERSION = 'VikingBank.lua 0.0.1',
  _URL     = 'https://github.com/vikinghug/VikingBank',
  _DESCRIPTION = '',
  _LICENSE = [[
      MIT LICENSE

      Copyright (c) 2014 Kevin Altman

      Permission is hereby granted, free of charge, to any person obtaining a
      copy of this software and associated documentation files (the
      "Software"), to deal in the Software without restriction, including
      without limitation the rights to use, copy, modify, merge, publish,
      distribute, sublicense, and/or sell copies of the Software, and to
      permit persons to whom the Software is furnished to do so, subject to
      the following conditions:

      The above copyright notice and this permission notice shall be included
      in all copies or substantial portions of the Software.

      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
      OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
      MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
      IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
      CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
      TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
      SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
          ]]
}

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

  Apollo.RegisterEventHandler("WindowManagementReady"        , "OnWindowManagementReady"      , self)
  Apollo.RegisterEventHandler("WindowManagementUpdate"       , "OnWindowManagementUpdate"     , self)
  Apollo.RegisterEventHandler("HideBank"                     , "HideBank"                     , self)
  Apollo.RegisterEventHandler("ShowBank"                     , "Initialize"                   , self)
  Apollo.RegisterEventHandler("ToggleBank"                   , "Initialize"                   , self)
  Apollo.RegisterEventHandler("CloseVendorWindow"            , "OnCloseVendorWindow"          , self)
  Apollo.RegisterEventHandler("PlayerCurrencyChanged"        , "ComputeCashLimits"            , self)
  Apollo.RegisterEventHandler("BankSlotPurchased"            , "OnBankSlotPurchased"          , self)
  Apollo.RegisterEventHandler("PersonaUpdateCharacterStats"  , "RefreshBagCount"              , self)

  -- No longer needed with conversion to ApolloTimer.Create()
  -- Apollo.RegisterTimerHandler("VikingBank_NewBagPurchasedAlert", "OnVikingBank_NewBagPurchasedAlert", self)

  self.wndMain = nil -- TODO RESIZE CODE
end


-->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- START: Register VikingBank Windows with Windows Management
-->>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

-- TODO: Not fully implemented yet. Need to connect to Viking DB so that window can be reset to default position.

function VikingBank:OnWindowManagementReady()
  Event_FireGenericEvent("WindowManagementAdd", { wnd = self.wndMain,      strName = "Viking Bank" })
end

function VikingBank:OnWindowManagementUpdate(tWindow)
  if tWindow and tWindow.wnd and (tWindow.wnd == self.wndMain) then
    local bMoveable = tWindow.wnd:IsStyleOn("Moveable")

    tWindow.wnd:SetStyle("Sizable", bMoveable)
    tWindow.wnd:SetStyle("RequireMetaKeyToMove", bMoveable)
    tWindow.wnd:SetStyle("IgnoreMouse", not bMoveable)
  end
end
--<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
-- END: Register VikingBank Windows with Windows Management
--<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<


function VikingBank:Initialize()
  if self.wndMain and self.wndMain:IsValid() then
    self.wndMain:Close()
    self.wndMain:Destroy()
    self.wndMain = nil
  end

  self.wndMain = Apollo.LoadForm("VikingBank.xml", "VikingBankForm", nil, self)
  self.wndMain:FindChild("BankBuySlotBtn"):AttachWindow(self.wndMain:FindChild("BankBuySlotConfirm"))
  --Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = Apollo.GetString("Bank_Header")})

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
    -- Sets Bank Window Title to "Bank"
    self.wndMain:FindChild("BankTitleText"):SetText(Apollo.GetString("Bank_Header"))
  end
end

function VikingBank:OnBankSlotPurchased()
  -- Sets Bank Window Title to "New Bag Slot Purchased!"
  self.wndMain:FindChild("BankTitleText"):SetText(Apollo.GetString("Bank_BuySuccess"))
  -- TO DO: CreatTimer depreciated. Need to convert to ApolloTimer -> http://wiki.wildstarnasa.com/index.php?title=Category:ApolloTimer
  -- Apollo.CreateTimer("VikingBank_NewBagPurchasedAlert", 12, false)
  local tTimer
  tTimer = ApolloTimer.Create(12, false, "OnVikingBank_NewBagPurchasedAlert", self)
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
