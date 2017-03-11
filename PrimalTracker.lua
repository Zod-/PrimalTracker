require "Window"

local PrimalTracker = {}
local Version = "0.1.0"

function PrimalTracker:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  self.isXMLLoaded = false
  self.saveData = {
    rewards = {},
    saveVersion = Version
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
  self:LoadMatchMaker()
  self:BindHooks()
  self:LoadXML()
end

function PrimalTracker:LoadXML()
  self.xmlDoc = XmlDoc.CreateFromFile("PrimalTracker.xml")
  self.xmlDoc:RegisterCallback("OnDocumentLoaded", self)
end

function PrimalTracker:OnDocumentLoaded(args)
  self.isXMLLoaded = true
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
  return {
    contentName = rawData.strContentName,
    endTime = currentSeconds + rawData.nSecondsRemaining,
    multiplier = rawData.tRewardInfo.nMultiplier,
  }
end

function PrimalTracker:OnSave(saveLevel)
  if saveLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return end
  self:RemoveExpiredRewards()
  self.saveData.saveVersion = Version
  return self.saveData
end

function PrimalTracker:OnRestore(saveLevel, saveData)
  if saveLevel ~= GameLib.CodeEnumAddonSaveLevel.Realm then return end
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
