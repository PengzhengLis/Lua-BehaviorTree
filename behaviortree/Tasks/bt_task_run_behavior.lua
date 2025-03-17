local BTTaskNode = require("behaviortree.bt_task_node")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")


local BTTask_RunBehavior = {
    BehaviorAsset = nil,
};

function BTTask_RunBehavior:GetSubtreeAsset()
	return self.BehaviorAsset;
end

function BTTask_RunBehavior:GetInjectedNodesCount()
	return self.BehaviorAsset and #self.BehaviorAsset.RootDecorators or 0;
end

function BTTask_RunBehavior:ExecuteTask(OwnerComp, NodeMemory)
	local bPushed = self.BehaviorAsset and OwnerComp:PushInstance(self.BehaviorAsset);
	if (bPushed and #OwnerComp.InstanceStack > 0) then
		local MyInstance = OwnerComp.InstanceStack[#OwnerComp.InstanceStack];
		MyInstance.DeactivationNotify = function(OwnerComp, Result) self:OnSubtreeDeactivated(OwnerComp, Result) end

		return BehaviorTreeTypes.EBTNodeResult.InProgress;
	end

	return BehaviorTreeTypes.EBTNodeResult.Failed;
end

function BTTask_RunBehavior:OnSubtreeDeactivated(OwnerComp, NodeResult)
	local MyInstanceIdx = OwnerComp:FindInstanceContainingNode(self);
	local NodeMemory = OwnerComp:GetNodeMemory(self, MyInstanceIdx);

	self:OnTaskFinished(OwnerComp, NodeMemory, NodeResult);
end

return class(BTTask_RunBehavior, {}, BTTaskNode)