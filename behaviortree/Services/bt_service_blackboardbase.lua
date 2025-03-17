local BTService = require("behaviortree.bt_service")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTService_BlackboardBase = {
    BlackboardKey = nil,
}

function BTService_BlackboardBase:constructor(args)
    self.BlackboardKey = BehaviorTreeTypes.FBlackboardKeySelector()
    self.BlackboardKey.SelectedKeyName = args.SelectedKeyName
end

function BTService_BlackboardBase:GetSelectedBlackboardKey()
	return self.BlackboardKey.SelectedKeyName;
end

function BTService_BlackboardBase:InitializeFromAsset(Asset)
	BTService.InitializeFromAsset(self, Asset);

	local BBAsset = self:GetBlackboardAsset();
	if (BBAsset) then
		self.BlackboardKey:ResolveSelectedKey(BBAsset);
    end
end

return class(BTService_BlackboardBase, {}, BTService)