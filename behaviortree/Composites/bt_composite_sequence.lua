local BTCompositeNode = require("behaviortree.bt_composite_node")
local BehaviorTreeTypes = require("behavior_tree_types")


local BTComposite_Sequence = {

}

function BTComposite_Sequence:GetNextChildHandler(SearchData, PrevChild, LastResult)
	
	local NextChildIdx = BehaviorTreeTypes.BTSpecialChild.ReturnToParent;

	if (PrevChild == BehaviorTreeTypes.BTSpecialChild.NotInitialized) then
		NextChildIdx = 1;
	elseif (LastResult == BehaviorTreeTypes.EBTNodeResult.Succeeded and PrevChild < self:GetChildrenNum()) then
		NextChildIdx = PrevChild + 1;
    end

	return NextChildIdx;
end

return class(BTComposite_Sequence, {}, BTCompositeNode)