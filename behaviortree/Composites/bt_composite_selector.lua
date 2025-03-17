local BTCompositeNode = require("behaviortree.bt_composite_node")
local BehaviorTreeTypes = require("behavior_tree_types")


local BTComposite_Selector = {

}

function BTComposite_Selector:GetNextChildHandler(SearchData, PrevChild, LastResult)
	
	local NextChildIdx = BehaviorTreeTypes.BTSpecialChild.ReturnToParent;

	if (PrevChild == BehaviorTreeTypes.BTSpecialChild.NotInitialized) then
		NextChildIdx = 1;
	elseif (LastResult == BehaviorTreeTypes.EBTNodeResult.Failed and PrevChild < self:GetChildrenNum()) then
		NextChildIdx = PrevChild + 1;
    end

	return NextChildIdx;
end

return class(BTComposite_Selector, {}, BTCompositeNode)