local BTNode = require("bt_node")

local BTService = {
    bNotifyTick = true,
	bNotifyOnSearch = true,
	bTickIntervals = true,
	bCallTickOnSearchStart = false,
	bRestartTimerOnEachActivation = false,

	Interval = 0.5,
	RandomDeviation = 0.1,
}

function BTService:TickNode(OwnerComp, NodeMemory, DeltaSeconds)
	self:ScheduleNextTick(OwnerComp, NodeMemory);
end

function BTService:OnSearchStart(SearchData)

end

function BTService:NotifyParentActivation(SearchData)
	if (self.bNotifyOnSearch or self.bNotifyTick) then
		local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(SearchData) or self;
		if (NodeOb) then
			local ServiceNodeOb = NodeOb;
			local NodeMemory = self:GetNodeMemory(SearchData);

			if (self.bNotifyTick) then
				local RemainingTime = self.bRestartTimerOnEachActivation and 0.0 or self:GetNextTickRemainingTime(NodeMemory);
				if (RemainingTime <= 0.0) then
					ServiceNodeOb:ScheduleNextTick(SearchData.OwnerComp, NodeMemory);
				end
			end

			if (self.bNotifyOnSearch) then
				ServiceNodeOb:OnSearchStart(SearchData);
			end

			if (self.bCallTickOnSearchStart) then
				ServiceNodeOb:TickNode(SearchData.OwnerComp, NodeMemory, 0.0);
			end
		end
	end
end

function BTService:ScheduleNextTick(OwnerComp, NodeMemory)
	local NextTickTime = math.random(math.max(0.0, self.Interval - self.RandomDeviation), (self.Interval + self.RandomDeviation));
	self:SetNextTickTime(NodeMemory, NextTickTime);
end

return class(BTService, nil, BTNode)