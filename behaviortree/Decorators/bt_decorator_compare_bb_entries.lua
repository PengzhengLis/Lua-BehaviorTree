local BTDecorator = require("behaviortree.bt_decorator")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")
local BlackboardKeyType = require("behaviortree.blackboard.blackboard_keytype")

local EBlackBoardEntryComparison = 
{
	Equal = 0,
	NotEqual = 1,
}

local BTDecorator_CompareBBEntries = {
    Operator = EBlackBoardEntryComparison.Equal,
    BlackboardKeyA = nil,
    BlackboardKeyB = nil,
    bNotifyBecomeRelevant = true,
	bNotifyCeaseRelevant = true,
}


function BTDecorator_CompareBBEntries:constructor(args)
    self.BlackboardKeyA = BehaviorTreeTypes.FBlackboardKeySelector()
    self.BlackboardKeyB = BehaviorTreeTypes.FBlackboardKeySelector()
	self.BlackboardKeyA.SelectedKeyName = args.SelectedKeyNameA
	self.BlackboardKeyB.SelectedKeyName = args.SelectedKeyNameB
end


function BTDecorator_CompareBBEntries:InitializeFromAsset(Asset)
	BTDecorator.InitializeFromAsset(self, Asset);

	local BBAsset = self:GetBlackboardAsset();
	if (BBAsset) then
		self.BlackboardKeyA:ResolveSelectedKey(BBAsset);
		self.BlackboardKeyB:ResolveSelectedKey(BBAsset);
    end
end

function BTDecorator_CompareBBEntries:CalculateRawConditionValue(OwnerComp, NodeMemory)

	if (self.BlackboardKeyA.SelectedKeyType ~= self.BlackboardKeyB.SelectedKeyType) then
		return false;
    end
	
	local BlackboardComp = OwnerComp:GetBlackboardComponent();
	if (BlackboardComp) then
		local Result = BlackboardComp:CompareKeyValues(self.BlackboardKeyA.SelectedKeyType, self.BlackboardKeyA:GetSelectedKeyID(), self.BlackboardKeyB:GetSelectedKeyID());

		return ((Result == BlackboardKeyType.EBlackboardCompare.Equal) == (self.Operator == EBlackBoardEntryComparison.Equal));
	end

	return false;
end

function BTDecorator_CompareBBEntries:OnBecomeRelevant(OwnerComp, NodeMemory)
	local BlackboardComp = OwnerComp:GetBlackboardComponent();
	if (BlackboardComp) then
		BlackboardComp:RegisterObserver(self.BlackboardKeyA.GetSelectedKeyID(), self, function(Blackboard, ChangedKeyID) return self:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID) end)
		BlackboardComp:RegisterObserver(self.BlackboardKeyB.GetSelectedKeyID(), self, function(Blackboard, ChangedKeyID) return self:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID) end)
	end
end

function BTDecorator_CompareBBEntries:OnCeaseRelevant(OwnerComp, NodeMemory)
	local BlackboardComp = OwnerComp:GetBlackboardComponent();
	if (BlackboardComp) then
		BlackboardComp:UnregisterObserversFrom(self);
	end
end

function BTDecorator_CompareBBEntries:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID)
	local BehaviorComp = Blackboard:GetBrainComponent()
	if (BehaviorComp == nil) then
		return BehaviorTreeTypes.EBlackboardNotificationResult.RemoveObserver;
	elseif (self.BlackboardKeyA:GetSelectedKeyID() == ChangedKeyID or self.BlackboardKeyB:GetSelectedKeyID() == ChangedKeyID) then
		BehaviorComp:RequestExecution(self);		
	end

	return BehaviorTreeTypes.EBlackboardNotificationResult.ContinueObserving;
end

return class(BTDecorator_CompareBBEntries, {}, BTDecorator)