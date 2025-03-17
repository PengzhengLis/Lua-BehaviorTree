local BTTaskNode = require("behaviortree.bt_task_node")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTTask_BlackboardBase = {
	BlackboardKey = nil,
}

function BTTask_BlackboardBase:constructor(args)
	self.BlackboardKey = BehaviorTreeTypes.FBlackboardKeySelector()
    self.BlackboardKey.SelectedKeyName = args.SelectedKeyName
end

function BTTask_BlackboardBase:GetSelectedBlackboardKey()
	return self.BlackboardKey.SelectedKeyName;
end

function BTTask_BlackboardBase:InitializeFromAsset(Asset)
	BTTaskNode.InitializeFromAsset(self, Asset);

	local BBAsset = self:GetBlackboardAsset();
	if (BBAsset) then
		self.BlackboardKey:ResolveSelectedKey(BBAsset);
	end
end

return class(BTTask_BlackboardBase, {}, BTTaskNode)