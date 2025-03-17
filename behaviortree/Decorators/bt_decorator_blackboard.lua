local BTDecorator = require("behaviortree.bt_decorator")
local BTDecorator_BlackboardBase = require("bt_decorator_blackboardbase")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")
local BlackboardKeyType = require("behaviortree.blackboard.blackboard_keytype")

local EBTBlackboardRestart = {
	ValueChange	= 0,	
	ResultChange = 1,
}

local BTDecorator_Blackboard = {
    Value = nil,
    OperationType = 0,
    NotifyObserver = EBTBlackboardRestart.ResultChange
}

function BTDecorator_Blackboard:constructor(args)
	BTDecorator_BlackboardBase.constructor(self, args)

	self.Value = args.Value
	self.OperationType = args.OperationType
	self.NotifyObserver = args.NotifyObserver
end

function BTDecorator_Blackboard:CalculateRawConditionValue(OwnerComp, NodeMemory)
	local BlackboardComp = OwnerComp:GetBlackboardComponent();

	return BlackboardComp and self:EvaluateOnBlackboard(BlackboardComp)
end

function BTDecorator_Blackboard:EvaluateOnBlackboard(BlackboardComp)
	local bResult = false;
	if (self.BlackboardKey.SelectedKeyType) then
		local KeyCDO = self.BlackboardKey.SelectedKeyType;
        local KeyID = self.BlackboardKey:GetSelectedKeyID()
		local KeyMemory = BlackboardComp.ValueMemory

		if (KeyCDO and KeyMemory) then
			local Op = KeyCDO:GetTestOperation();
            if Op == BlackboardKeyType.EBlackboardKeyOperation.Basic then
                bResult = KeyCDO:WrappedTestBasicOperation(BlackboardComp, KeyMemory, KeyID, self.OperationType);
            elseif Op == BlackboardKeyType.EBlackboardKeyOperation.Arithmetic then
                bResult = KeyCDO:WrappedTestArithmeticOperation(BlackboardComp, KeyMemory, KeyID, self.OperationType, self.Value);
            elseif Op == BlackboardKeyType.EBlackboardKeyOperation.Text then
                bResult = KeyCDO:WrappedTestTextOperation(BlackboardComp, KeyMemory, KeyID, self.OperationType, self.Value);
            end
		end
	end

	return bResult;
end

function BTDecorator_Blackboard:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID)
	local BehaviorComp = Blackboard:GetBrainComponent();
	if (BehaviorComp == nil) then
		return BehaviorTreeTypes.EBlackboardNotificationResult.RemoveObserver;
	end

	if (self.BlackboardKey:GetSelectedKeyID() == ChangedKeyID) then
		local RequestMode = (self.NotifyObserver == EBTBlackboardRestart.ValueChange) and BTDecorator.EBTDecoratorAbortRequest.ConditionPassing or BTDecorator.EBTDecoratorAbortRequest.ConditionResultChanged;
		self:ConditionalFlowAbort(BehaviorComp, RequestMode);
	end

	return BehaviorTreeTypes.EBlackboardNotificationResult.ContinueObserving;
end


return class(BTDecorator_Blackboard, {EBTBlackboardRestart = EBTBlackboardRestart}, BTDecorator_BlackboardBase)