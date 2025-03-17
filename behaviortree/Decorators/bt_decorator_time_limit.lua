local BTDecorator = require("behaviortree.bt_decorator")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTDecorator_TimeLimit = {
    TimeLimit = 5.0,
    bNotifyActivation = true,
    bNotifyTick = true,
    bTickIntervals = true,
    FlowAbortMode = BehaviorTreeTypes.EBTFlowAbortMode.Self;
}


function BTDecorator_TimeLimit:OnNodeActivation(SearchData)
	local RawMemory = SearchData.OwnerComp:GetNodeMemory(self, SearchData.OwnerComp:FindInstanceContainingNode(self));
	if (RawMemory) then
		local DecoratorMemory = RawMemory
		DecoratorMemory.NextTickRemainingTime = self.TimeLimit;
		DecoratorMemory.AccumulatedDeltaTime = 0.0
	end
end

function BTDecorator_TimeLimit:TickNode(OwnerComp, NodeMemory, DeltaSeconds)
	OwnerComp:RequestExecution(self);
end

return 