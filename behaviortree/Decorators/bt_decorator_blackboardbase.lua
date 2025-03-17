local BTDecorator = require("behaviortree.bt_decorator")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")

local BTDecorator_BlackboardBase = {
    bNotifyBecomeRelevant = true,
    bNotifyCeaseRelevant = true,
    BlackboardKey = nil
}

function BTDecorator_BlackboardBase:constructor(args)
    self.BlackboardKey = BehaviorTreeTypes.FBlackboardKeySelector()
	self.BlackboardKey.SelectedKeyName = args.SelectedKeyName
end

function BTDecorator_BlackboardBase:GetSelectedBlackboardKey()
	return self.BlackboardKey.SelectedKeyName;
end


function BTDecorator_BlackboardBase:InitializeFromAsset(Asset)
    BTDecorator.InitializeFromAsset(self, Asset)

	local BBAsset = self:GetBlackboardAsset();
	if (BBAsset) then
		self.BlackboardKey:ResolveSelectedKey(BBAsset);
	else

    end
end

function BTDecorator_BlackboardBase:OnBecomeRelevant(OwnerComp, NodeMemory)
	local BlackboardComp = OwnerComp:GetBlackboardComponent();
	if (BlackboardComp) then
		local KeyID = self.BlackboardKey:GetSelectedKeyID();
		BlackboardComp:RegisterObserver(KeyID, self, function(Blackboard, ChangedKeyID) self:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID) end)
	end
end

function BTDecorator_BlackboardBase:OnCeaseRelevant(OwnerComp, NodeMemory)
	local BlackboardComp = OwnerComp:GetBlackboardComponent();
	if (BlackboardComp) then
		BlackboardComp:UnregisterObserversFrom(self);
	end
end

function BTDecorator_BlackboardBase:OnBlackboardKeyValueChange(Blackboard, ChangedKeyID)
	local BehaviorComp = Blackboard:GetBrainComponent();
	if (BehaviorComp == nil) then
		return BehaviorTreeTypes.EBlackboardNotificationResult.RemoveObserver;
	end

	if (self.BlackboardKey:GetSelectedKeyID() == ChangedKeyID) then
		BehaviorComp:RequestExecution(self);		
	end
	return BehaviorTreeTypes.EBlackboardNotificationResult.ContinueObserving;
end

return class(BTDecorator_BlackboardBase, {}, BTDecorator)