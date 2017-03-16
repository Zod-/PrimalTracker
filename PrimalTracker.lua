require "Window"

local PrimalTracker = {}
local Version = "0.1.2"

local knExtraSortBaseValue = 100

local keExtraSort = {
  Content = 1,
  TimeRemaining = 2,
  Multiplier = knExtraSortBaseValue + 0,
  Color = knExtraSortBaseValue + 1,
}

function PrimalTracker:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  self.isXMLLoaded = false
  self.saveData = {
    rewards = {},
    saveVersion = Version,
    sort = keExtraSort.Content,
  }
  self.customSortFunctions = {
    [keExtraSort.Content] = self.SortByContentType,
    [keExtraSort.TimeRemaining] = self.SortByTimeRemaining,
    [keExtraSort.Multiplier] = self.SortByMultiplier,
    [keExtraSort.Color] = self.SortByColor
  }
  return o
end

function PrimalTracker:Init()
  Apollo.RegisterAddon(self, false, "")
end

function PrimalTracker:IsLoaded()
  return self.isXMLLoaded
end

function PrimalTracker:OnLoad()
  self:LoadXML()
end

function PrimalTracker:LoadXML()
  self.xmlDoc = XmlDoc.CreateFromFile("PrimalTracker.xml")
  self.xmlDoc:RegisterCallback("OnDocumentLoaded", self)
end

function PrimalTracker:OnDocumentLoaded(args)
  self.isXMLLoaded = true
  self:SetupEssenceDisplay()
  self:LoadMatchMaker()
  self:BindHooks()
end

function PrimalTracker:SetupEssenceDisplay()
  self.arrEssenceLootLog = {}
  self.wndEssenceDisplay = Apollo.LoadForm(self.xmlDoc, "EssenceDisplay", nil, self)
  local monRed = GameLib.GetPlayerCurrency(Money.CodeEnumCurrencyType.RedEssence)
  local monBlue = GameLib.GetPlayerCurrency(Money.CodeEnumCurrencyType.BlueEssence)
  local monGreen = GameLib.GetPlayerCurrency(Money.CodeEnumCurrencyType.GreenEssence)
  local monPurple = GameLib.GetPlayerCurrency(Money.CodeEnumCurrencyType.PurpleEssence)
  monRed:SetAmount(0)
  monBlue:SetAmount(0)
  monGreen:SetAmount(0)
  monPurple:SetAmount(0)
  self.wndEssenceDisplay:FindChild("Currencies:Red"):SetAmount(monRed, true)
  self.wndEssenceDisplay:FindChild("Currencies:Blue"):SetAmount(monBlue, true)
  self.wndEssenceDisplay:FindChild("Currencies:Green"):SetAmount(monGreen, true)
  self.wndEssenceDisplay:FindChild("Currencies:Purple"):SetAmount(monPurple, true)
  self.timerEssenceDisplayTimeout = ApolloTimer.Create(5, false, "OnEssenceDisplayTimeout", self)
  Apollo.RegisterEventHandler("ChannelUpdate_Loot", "OnChannelUpdate_Loot", self)
  Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)
  Apollo.RegisterEventHandler("WindowManagementUpdate", "OnWindowManagementUpdate", self)
  self:OnWindowManagementReady()
end

function PrimalTracker:LoadMatchMaker()
  self.addonMatchMaker = Apollo.GetAddon("MatchMaker")
end

function PrimalTracker:BindHooks()
  if not self.addonMatchMaker then return false end

  local originalBuildFeaturedList = self.addonMatchMaker.BuildFeaturedList
  self.addonMatchMaker.BuildFeaturedList = function(...)
    originalBuildFeaturedList(...)
    if self:IsLoaded() then
      self:PlaceOverlays()
    end
  end

  local originalHelperCreateFeaturedSort = self.addonMatchMaker.HelperCreateFeaturedSort
  self.addonMatchMaker.HelperCreateFeaturedSort = function(...)
    originalHelperCreateFeaturedSort(...)
    self:AddAdditionalSortOptions()
  end

  local originalGetSortedRewardList = self.addonMatchMaker.GetSortedRewardList
  self.addonMatchMaker.GetSortedRewardList = function(ref, arRewardList, ...)
    if self:IsLoaded() then
      self.saveData.sort = self.addonMatchMaker.tWndRefs.wndFeaturedSort:GetData()
      return self:GetSortedRewardList(self.saveData.sort, arRewardList, originalGetSortedRewardList, ref, ...)
    else
      return originalGetSortedRewardList(ref, arRewardList, ...)
    end
  end
end

function PrimalTracker:PlaceOverlays()
  local currentSeconds = self:GetCurrentSeconds()
  local rewardWindows = self:GetRewardWindows()
  for i = 1, #rewardWindows do
    local rewardWindow = rewardWindows[i]
    local rewardData = self:GetRewardData(rewardWindow, currentSeconds)
    self:BuildOverlay(rewardWindow, rewardData)
  end
end

function PrimalTracker:AddAdditionalSortOptions()
  local wndSort = self:GetSortWindow()
  if not wndSort then return end
  local wndSortDropdown = wndSort:FindChild("FeaturedFilterDropdown")
  if not wndSortDropdown then return end
  local wndSortContainer = wndSortDropdown:FindChild("Container")

  local refXmlDoc = self.addonMatchMaker.xmlDoc
  local strSortOptionForm = "FeaturedContentFilterBtn"

  local wndSortMultiplier = Apollo.LoadForm(refXmlDoc, strSortOptionForm, wndSortContainer, self.addonMatchMaker)
  wndSortMultiplier:SetData(keExtraSort.Multiplier)
  wndSortMultiplier:SetText("Multiplier")
  if wndSort:GetData() == keExtraSort.Multiplier then
    wndSortMultiplier:SetCheck(true)
  end

  local wndSortColor = Apollo.LoadForm(refXmlDoc, strSortOptionForm, wndSortContainer, self.addonMatchMaker)
  wndSortColor:SetData(keExtraSort.Color)
  wndSortColor:SetText("Essence Color")

  local sortContainerChildren = wndSortContainer:GetChildren()
  local nLeft, nTop, nRight = wndSortDropdown:GetOriginalLocation():GetOffsets()
  local nBottom = nTop + (#sortContainerChildren * wndSortMultiplier:GetHeight()) + 11
  wndSortDropdown:SetAnchorOffsets(nLeft, nTop, nRight, nBottom)
  wndSortContainer:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop)

  for i = 1, #sortContainerChildren do
    local sortButton = sortContainerChildren[i]
    if self.saveData.sort == sortButton:GetData() then
      wndSort:SetData(sortButton:GetData())
      wndSort:SetText(sortButton:GetText())
      sortButton:SetCheck(true)
    else
      sortButton:SetCheck(false)
    end
  end
end

function PrimalTracker:GetSortedRewardList(eSort, arRewardList, funcOrig, ref, ...)
  if self.customSortFunctions[eSort] then
    table.sort(arRewardList,
      function (tA, tB)
        return self.customSortFunctions[eSort](self, tA, tB)
      end
    )
  else
    funcOrig(ref, arRewardList, ...)
  end

  return arRewardList
end

function PrimalTracker:SortByContentType(tA, tB)
  local nCompare = self:CompareCompletedStatus(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  nCompare = self:CompareByContentType(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  return self:CompareByMultiplier(tA, tB) > 0
end

function PrimalTracker:SortByTimeRemaining(tA, tB)
  local nCompare = self:CompareCompletedStatus(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  nCompare = self:CompareByTimeRemaining(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  return self:CompareByMultiplier(tA, tB) > 0
end

function PrimalTracker:SortByMultiplier(tA, tB)
  local nCompare = self:CompareCompletedStatus(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  nCompare = self:CompareByMultiplier(tA, tB)
  if nCompare ~= 0 then return nCompare > 0 end
  return self:CompareByTimeRemaining(tA, tB) < 0
end

function PrimalTracker:SortByColor(tA, tB)
  local nCompare = self:CompareCompletedStatus(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  nCompare = self:CompareByColor(tA, tB)
  if nCompare ~= 0 then return nCompare < 0 end
  return self:CompareByMultiplier(tA, tB) > 0
end

function PrimalTracker:CompareByContentType(tA, tB)
  local nA = tA.nContentType or 0
  local nB = tB.nContentType or 0
  return nA - nB
end

function PrimalTracker:CompareByTimeRemaining(tA, tB)
  local nA = tA.nSecondsRemaining or 0
  local nB = tB.nSecondsRemaining or 0
  return nA - nB
end

function PrimalTracker:CompareByMultiplier(tA, tB)
  local nA = tA.tRewardInfo and tA.tRewardInfo.nMultiplier or 0
  local nB = tB.tRewardInfo and tB.tRewardInfo.nMultiplier or 0
  return nA - nB
end

function PrimalTracker:CompareByColor(tA, tB)
  local nA = tA.tRewardInfo and tA.tRewardInfo.monReward and tA.tRewardInfo.monReward:GetAccountCurrencyType() or 0
  local nB = tB.tRewardInfo and tB.tRewardInfo.monReward and tB.tRewardInfo.monReward:GetAccountCurrencyType() or 0
  return nA - nB
end

function PrimalTracker:CompareCompletedStatus(tA, tB)
  local currentSeconds = self:GetCurrentSeconds()
  local bAIsActive = self:IsRewardActive(self:ConvertRewardData(tA, currentSeconds))
  local bBIsActive = self:IsRewardActive(self:ConvertRewardData(tB, currentSeconds))
  if bAIsActive and not bBIsActive then return -1 end
  if not bAIsActive and bBIsActive then return 1 end
  return 0
end

function PrimalTracker:GetCurrentSeconds()
  local currentTime = GameLib.GetServerTime()
  return os.time({
      ["year"] = currentTime.nYear,
      ["month"] = currentTime.nMonth,
      ["day"] = currentTime.nDay,
      ["hour"] = currentTime.nHour,
      ["min"] = currentTime.nMinute,
      ["sec"] = currentTime.nSecond,
    }
  )
end

function PrimalTracker:GetRewardWindows()
  --self.addonMatchMaker.tWndRefs.wndMain:FindChild("TabContent:RewardContent"):GetChildren()
  local rewards = self.addonMatchMaker
  rewards = rewards and rewards.tWndRefs
  rewards = rewards and rewards.wndMain
  rewards = rewards and rewards:FindChild("TabContent:RewardContent")
  rewards = rewards and rewards:GetChildren() or {}
  return rewards
end

function PrimalTracker:GetSortWindow()
  --self.addonMatchMaker.tWndRefs.wndFeaturedSort:FindChild("FeaturedFilterDropdown:Container")
  local sort = self.addonMatchMaker
  sort = sort and sort.tWndRefs
  sort = sort and sort.wndFeaturedSort
  return sort
end

function PrimalTracker:BuildOverlay(rewardWindow, rewardData)
  local overlay = Apollo.LoadForm(self.xmlDoc, "Overlay", rewardWindow, self)
  overlay:FindChild("Completed"):SetData(rewardData)
  if self:IsRewardActive(rewardData) then
    overlay:FindChild("Shader"):Show(false)
  else
    overlay:FindChild("Completed"):SetCheck(true)
  end
end

function PrimalTracker:IsRewardActive(rewardData)
  for i = 1, #self.saveData.rewards do
    if self:IsSameReward(rewardData, self.saveData.rewards[i]) then
      return false
    end
  end
  return true
end

function PrimalTracker:IsSameReward(tA, tB)
  if tA.multiplier ~= tB.multiplier then return false end
  local endDiff = math.abs(tA.endTime - tB.endTime)
  if endDiff > 60 then return false end
  if tA.contentName ~= tB.contentName then return false end
  return true
end

function PrimalTracker:OnCompletedCheck(handler, control)
  table.insert(self.saveData.rewards, control:GetData())
  control:GetParent():FindChild("Shader"):Show(true)
end

function PrimalTracker:OnCompletedUncheck(handler, control)
  local rewardData = control:GetData()
  for i = 1, #self.saveData.rewards do
    if self:IsSameReward(rewardData, self.saveData.rewards[i]) then
      table.remove(self.saveData.rewards, i)
      break
    end
  end
  control:GetParent():FindChild("Shader"):Show(false)
end

function PrimalTracker:GetRewardData(rewardWindow, currentSeconds)
  local rawData = rewardWindow:FindChild("InfoButton"):GetData()
  return self:ConvertRewardData(rawData, currentSeconds)
end

function PrimalTracker:ConvertRewardData(rawData, currentSeconds)
  return {
    contentName = rawData.strContentName,
    endTime = currentSeconds + rawData.nSecondsRemaining,
    multiplier = rawData.tRewardInfo.nMultiplier,
  }
end

function PrimalTracker:OnChannelUpdate_Loot(eType, tEventArgs)
  if eType ~= GameLib.ChannelUpdateLootType.Currency then return end
  if not tEventArgs.monNew then return end
  if self:IsEssenceType(tEventArgs.monNew) then
    --TODO remove debug stuff
    table.insert(self.arrEssenceLootLog, {
      eType = eType,
      tEventArgs = tEventArgs,
      monNew = {
        GetAccountCurrencyType = tEventArgs.monNew:GetAccountCurrencyType(),
        GetAltType = tEventArgs.monNew:GetAltType(),
        GetAmount = tEventArgs.monNew:GetAmount(),
        GetDenomAmounts = tEventArgs.monNew:GetDenomAmounts(),
        GetDenomInfo = tEventArgs.monNew:GetDenomInfo(),
        GetExchangeItem = tEventArgs.monNew:GetExchangeItem(),
        GetMoneyString = tEventArgs.monNew:GetMoneyString(),
        GetMoneyType = tEventArgs.monNew:GetMoneyType(),
        GetTypeString = tEventArgs.monNew:GetTypeString(),
      },
      monSignatureBonus = {
        GetAccountCurrencyType = tEventArgs.monSignatureBonus:GetAccountCurrencyType(),
        GetAltType = tEventArgs.monSignatureBonus:GetAltType(),
        GetAmount = tEventArgs.monSignatureBonus:GetAmount(),
        GetDenomAmounts = tEventArgs.monSignatureBonus:GetDenomAmounts(),
        GetDenomInfo = tEventArgs.monSignatureBonus:GetDenomInfo(),
        GetExchangeItem = tEventArgs.monSignatureBonus:GetExchangeItem(),
        GetMoneyString = tEventArgs.monSignatureBonus:GetMoneyString(),
        GetMoneyType = tEventArgs.monSignatureBonus:GetMoneyType(),
        GetTypeString = tEventArgs.monSignatureBonus:GetTypeString(),
      },
      monEssenceBonus = {
        GetAccountCurrencyType = tEventArgs.monEssenceBonus:GetAccountCurrencyType(),
        GetAltType = tEventArgs.monEssenceBonus:GetAltType(),
        GetAmount = tEventArgs.monEssenceBonus:GetAmount(),
        GetDenomAmounts = tEventArgs.monEssenceBonus:GetDenomAmounts(),
        GetDenomInfo = tEventArgs.monEssenceBonus:GetDenomInfo(),
        GetExchangeItem = tEventArgs.monEssenceBonus:GetExchangeItem(),
        GetMoneyString = tEventArgs.monEssenceBonus:GetMoneyString(),
        GetMoneyType = tEventArgs.monEssenceBonus:GetMoneyType(),
        GetTypeString = tEventArgs.monEssenceBonus:GetTypeString(),
      },
    })
    local strColor = tEventArgs.monNew:GetTypeString()
    local nTotalAmount = tEventArgs.monNew:GetAmount()
    local nSignatureBonus = tEventArgs.monSignatureBonus:GetAmount()
    local nMultiplier = tEventArgs.monEssenceBonus:GetAmount()
    Print(strColor..": "..nTotalAmount.." (+"..nSignatureBonus..") [x"..nMultiplier.."]")
    self:AddToEssenceDisplay(tEventArgs.monNew)
  end
end

function PrimalTracker:IsEssenceType(mon)
  local eMoneyType = mon:GetMoneyType()
  if self:IsMoneyTypeEssence(eMoneyType) then
    return true
  end
  if eMoneyType ~= Money.CodeEnumCurrencyType.GroupCurrency then
    return false
  end
  local eAccountCurrencyType = mon:GetAccountCurrencyType()
  if self:IsAccountCurrencyTypeEssence(eAccountCurrencyType) then
    return true
  end
end

function PrimalTracker:IsMoneyTypeEssence(eMoneyType)
  local bIsEssenceType = false
  bIsEssenceType = bIsEssenceType or eMoneyType == Money.CodeEnumCurrencyType.RedEssence
  bIsEssenceType = bIsEssenceType or eMoneyType == Money.CodeEnumCurrencyType.BlueEssence
  bIsEssenceType = bIsEssenceType or eMoneyType == Money.CodeEnumCurrencyType.GreenEssence
  bIsEssenceType = bIsEssenceType or eMoneyType == Money.CodeEnumCurrencyType.PurpleEssence
  return bIsEssenceType
end

function PrimalTracker:IsAccountCurrencyTypeEssence(eAccountCurrencyType)
  local bIsEssenceType = false
  bIsEssenceType = bIsEssenceType or eAccountCurrencyType == AccountItemLib.CodeEnumAccountCurrency.RedEssence
  bIsEssenceType = bIsEssenceType or eAccountCurrencyType == AccountItemLib.CodeEnumAccountCurrency.BlueEssence
  bIsEssenceType = bIsEssenceType or eAccountCurrencyType == AccountItemLib.CodeEnumAccountCurrency.GreenEssence
  bIsEssenceType = bIsEssenceType or eAccountCurrencyType == AccountItemLib.CodeEnumAccountCurrency.PurpleEssence
  return bIsEssenceType
end

function PrimalTracker:AddToEssenceDisplay(mon)
  self.timerEssenceDisplayTimeout:Stop()
  self.timerEssenceDisplayTimeout:Start()
  local strColor = mon:GetTypeString()
  local nNew = mon:GetAmount()
  local arrEssences = self.wndEssenceDisplay:FindChild("Currencies"):GetChildren()
  for idx, wndEssence in ipairs(arrEssences) do
    local monCurrent = wndEssence:GetCurrency()
    if strColor == monCurrent:GetTypeString() then
      wndEssence:Show(true, true)
      local nCurrent = monCurrent:GetAmount()
      monCurrent:SetAmount(nCurrent + nNew)
      wndEssence:SetAmount(monCurrent)
    end
  end
end

function PrimalTracker:OnEssenceDisplayTimeout()
  local arrEssences = self.wndEssenceDisplay:FindChild("Currencies"):GetChildren()
  for idx, wndEssence in ipairs(arrEssences) do
    wndEssence:Show(false)
    local monCurrent = wndEssence:GetCurrency()
    monCurrent:SetAmount(0)
    wndEssence:SetAmount(monCurrent)
  end
end

function PrimalTracker:OnWindowManagementReady()
  Event_FireGenericEvent("WindowManagementRegister", {
    strName = "PrimalTracker: Essence Display",
    nSaveVersion = 1
  })
  Event_FireGenericEvent("WindowManagementAdd", {
    wnd = self.wndEssenceDisplay,
    strName = "PrimalTracker: Essence Display",
    nSaveVersion = 1
  })
end

function PrimalTracker:OnWindowManagementUpdate(tSettings)
  if tSettings and tSettings.wnd and tSettings.wnd == self.wndEssenceDisplay then
    local bMoveable = self.wndEssenceDisplay:IsStyleOn("Moveable")
    local bHasMoved = tSettings.bHasMoved
    self.wndEssenceDisplay:FindChild("Background"):Show(bMoveable)
    self.wndEssenceDisplay:SetStyle("Sizable", bMoveable and bHasMoved)
    self.wndEssenceDisplay:SetStyle("IgnoreMouse", not bMoveable)
  end
end

function PrimalTracker:OnSave(saveLevel)
  if saveLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return end
  self:RemoveExpiredRewards()
  self.saveData.saveVersion = Version
  return self.saveData
end

function PrimalTracker:OnRestore(saveLevel, saveData)
  if saveLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return end
  saveData.sort = saveData.sort or self.saveData.sort
  self.saveData = saveData
  self:RemoveExpiredRewards()
end

function PrimalTracker:RemoveExpiredRewards()
  local currentSeconds = self:GetCurrentSeconds()
  for i = #self.saveData.rewards, 1, -1 do
    local rewardData = self.saveData.rewards[i]
    if currentSeconds > rewardData.endTime then
      table.remove(self.saveData.rewards, i)
    end
  end
end

local PrimalTrackerInst = PrimalTracker:new()
PrimalTrackerInst:Init()
