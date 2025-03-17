local BTDecorator_BlackboardBase = require("bt_decorator_blackboardbase")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTDecorator_IsBBEntryOfClass = {
    TestClass = nil,
}

function BTDecorator_IsBBEntryOfClass:constructor(args)
    self.TestClass = args.TestClass
end

function BTDecorator_IsBBEntryOfClass:CalculateRawConditionValue(OwnerComp, NodeMemory)
	local MyBlackboard = OwnerComp:GetBlackboardComponent();

	if (MyBlackboard) then
		local KeyValue = MyBlackboard:GetValue(self.BlackboardKey:GetSelectedKeyID());

		return KeyValue ~= nil and instanceof(KeyValue, self.TestClass);
	end

	return false;
end

function BTDecorator_IsBBEntryOfClass:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID)

	if (self:CalculateRawConditionValue(Blackboard:GetBrainComponent()) ~= self:IsInversed()) then
		Blackboard:GetBrainComponent():RequestExecution(self);
    end

	return BehaviorTreeTypes.EBlackboardNotificationResult.ContinueObserving;
end

return class(BTDecorator_IsBBEntryOfClass, {}, BTDecorator_BlackboardBase)