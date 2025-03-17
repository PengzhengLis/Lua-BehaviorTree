local BTTaskNode = require("behaviortree.bt_task_node")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")


local BTTask_Wait = {

	WaitTime = 5.0,
	RandomDeviation = 0.0,
    bNotifyTick = true,
}

function BTTask_Wait:ExecuteTask(OwnerComp, NodeMemory)
	local MyMemory = NodeMemory;
    local random = math.random() * self.RandomDeviation * 2 - self.RandomDeviation
	MyMemory.RemainingWaitTime = self.WaitTime + random
	
	return BehaviorTreeTypes.EBTNodeResult.InProgress;
end

function BTTask_Wait:TickTask(OwnerComp, NodeMemory, DeltaSeconds)
	local MyMemory = NodeMemory;
	MyMemory.RemainingWaitTime = MyMemory.RemainingWaitTime - DeltaSeconds;

	if (MyMemory.RemainingWaitTime <= 0.0) then
		self:FinishLatentTask(OwnerComp, BehaviorTreeTypes.EBTNodeResult.Succeeded);
    end
end