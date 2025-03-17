local BTNode = require("bt_node")
local BehaviorTreeTypes = require("behavior_tree_types")
local AITypes = require("ai.ai_types")

local BTAuxiliaryNode = {
    bNotifyBecomeRelevant = false,
    bNotifyCeaseRelevant = false,
    bNotifyTick = false,
    bTickIntervals = false,
    ChildIndex = BehaviorTreeTypes.BTSpecialChild.OwnedByComposite;
}

function BTAuxiliaryNode:WrappedOnBecomeRelevant(OwnerComp, NodeMemory)
	if (self.bNotifyBecomeRelevant) then
		local NodeOb = self:HasInstance() and self:GetNodeInstance(OwnerComp, NodeMemory) or self;
		if (NodeOb) then
			NodeOb:OnBecomeRelevant(OwnerComp, NodeMemory);
		end
	end
end

function BTAuxiliaryNode:WrappedOnCeaseRelevant(OwnerComp, NodeMemory)
	if (self.bNotifyCeaseRelevant) then
		local NodeOb = self:HasInstance() and self:GetNodeInstance(OwnerComp, NodeMemory) or self;
		if (NodeOb) then
			NodeOb:OnCeaseRelevant(OwnerComp, NodeMemory);
		end
	end
end

function BTAuxiliaryNode:WrappedTickNode(OwnerComp, NodeMemory, DeltaSeconds, ref)
	if (self.bNotifyTick or self:HasInstance()) then
		local NodeOb = self:HasInstance() and self:GetNodeInstance(OwnerComp, NodeMemory) or self;

		if (NodeOb and NodeOb.bNotifyTick) then
			local UseDeltaTime = DeltaSeconds;

			if (NodeOb.bTickIntervals) then
				NodeMemory.NextTickRemainingTime = NodeMemory.NextTickRemainingTime - DeltaSeconds;
				NodeMemory.AccumulatedDeltaTime = NodeMemory.AccumulatedDeltaTime + DeltaSeconds;

				local bTick = NodeMemory.NextTickRemainingTime <= 0.0;
				if (bTick) then
				    UseDeltaTime = NodeMemory.AccumulatedDeltaTime;
				    NodeMemory.AccumulatedDeltaTime = 0.0;
    
				    NodeOb:TickNode(OwnerComp, NodeMemory, UseDeltaTime);
				end

				if (NodeMemory.NextTickRemainingTime < ref.NextNeededDeltaTime) then
					ref.NextNeededDeltaTime = NodeMemory.NextTickRemainingTime;
				end

				return bTick;
			else
				NodeOb:TickNode(OwnerComp, NodeMemory, UseDeltaTime);
				ref.NextNeededDeltaTime = 0.0;
				return true;
			end
		end
	end

	return false;
end

function BTAuxiliaryNode:SetNextTickTime(NodeMemory, RemainingTime)
	if (self.bTickIntervals) then
		NodeMemory.NextTickRemainingTime = RemainingTime;
	end
end

function BTAuxiliaryNode:GetNextTickRemainingTime(NodeMemory)
	if (self.bTickIntervals) then
		return math.max(0.0, NodeMemory.NextTickRemainingTime);
	end

	return 0.0;
end

function BTAuxiliaryNode:OnBecomeRelevant(OwnerComp, NodeMemory)

end

function BTAuxiliaryNode:OnCeaseRelevant(OwnerComp, NodeMemory)

end

function BTAuxiliaryNode:TickNode(OwnerComp, NodeMemory, DeltaSeconds)

end

function BTAuxiliaryNode:InitializeParentLink(MyChildIndex)
	self.ChildIndex = MyChildIndex;
end

function BTAuxiliaryNode:GetMyNode()
	return (self.ChildIndex == BehaviorTreeTypes.BTSpecialChild.OwnedByComposite) and self:GetParentNode() or (self:GetParentNode() and self:GetParentNode():GetChildNode(self.ChildIndex) or nil);
end

function BTAuxiliaryNode:GetNextNeededDeltaTime(OwnerComp, NodeMemory)
	if (self.bNotifyTick or self:HasInstance()) then
		local NodeOb = self:HasInstance() and self:GetNodeInstance(OwnerComp, NodeMemory) or self;

		if (NodeOb and NodeOb.bNotifyTick) then
			if (self.bTickIntervals)  then
				return NodeMemory.NextTickRemainingTime;
			else
				return 0.0;
			end
		end
	end

	return AITypes.FLT_MAX
end

return class(BTAuxiliaryNode, nil, BTNode)