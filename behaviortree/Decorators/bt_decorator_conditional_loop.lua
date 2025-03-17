local BTDecorator_Blackboard = require("behaviortree.Decorators.bt_decorator_blackboard")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTDecorator_ConditionalLoop = {
    bNotifyDeactivation = true,
}

function BTDecorator_ConditionalLoop:CalculateRawConditionValue(OwnerComp, NodeMemory)
	return true;
end

function BTDecorator_ConditionalLoop:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID)
	return BehaviorTreeTypes.EBlackboardNotificationResult.RemoveObserver;
end

function BTDecorator_ConditionalLoop:OnNodeDeactivation(SearchData, NodeResult)
	if (NodeResult ~= BehaviorTreeTypes.EBTNodeResult.Aborted) then
		local BlackboardComp = SearchData.OwnerComp:GetBlackboardComponent();
		local bEvalResult = BlackboardComp and self:EvaluateOnBlackboard(BlackboardComp);

		if (bEvalResult ~= self:IsInversed()) then
			self:GetParentNode():SetChildOverride(SearchData, self:GetChildIndex());
		end
	end
end

return class(BTDecorator_ConditionalLoop, {}, BTDecorator_Blackboard)