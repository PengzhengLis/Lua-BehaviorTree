local BTTaskNode = require("behaviortree.bt_task_node")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTTask_FinishWithResult = {
    Result = BehaviorTreeTypes.EBTNodeResult.Succeeded
};

function BTTask_FinishWithResult:ExecuteTask(OwnerComp, NodeMemory)
	return self.Result;
end

return class(BTTask_FinishWithResult, {}, BTTaskNode)