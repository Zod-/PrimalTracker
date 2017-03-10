require "Window"

local PrimalTracker = {}

function PrimalTracker:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self

  return o
end

function PrimalTracker:Init()
  Apollo.RegisterAddon(self, false, "")
end

local PrimalTrackerInst = PrimalTracker:new()
PrimalTrackerInst:Init()
