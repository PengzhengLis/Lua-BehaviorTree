local BTDecorator = require("behaviortree.bt_decorator")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")


local BTDecorator_ForceSuccess = {
    bNotifyProcessed = true,
}

function BTDecorator_ForceSuccess:OnNodeProcessed(SearchData, NodeResult)
	NodeResult[1] = BehaviorTreeTypes.EBTNodeResult.Succeeded;
end

return class(BTDecorator_ForceSuccess, {}, BTDecorator)