local BTAuxiliaryNode = require("bt_auxiliary_node")
local BehaviorTreeTypes = require("behavior_tree_types")

local EBTDecoratorAbortRequest = {
    ConditionResultChanged = 0,
    ConditionPassing = 1,
}

local BTDecorator = {
    FlowAbortMode = BehaviorTreeTypes.EBTFlowAbortMode.None,
	bInverseCondition = false,
	
    bNotifyActivation = false,
    bNotifyDeactivation = false,
    bNotifyProcessed = false,
}

function BTDecorator:constructor(args)
	self.FlowAbortMode = args.FlowAbortMode
	self.bInverseCondition = args.bInverseCondition
end

function BTDecorator:GetFlowAbortMode()
	return self.FlowAbortMode;
end

function BTDecorator:IsInversed()
	return self.bInverseCondition;
end


function BTDecorator:CalculateRawConditionValue(OwnerComp, NodeMemory)
	return true;
end

function BTDecorator:SetIsInversed(bShouldBeInversed)
	self.bInverseCondition = bShouldBeInversed;
end

function BTDecorator:OnNodeActivation(SearchData)

end

function BTDecorator:OnNodeDeactivation(SearchData, NodeResult)

end

function BTDecorator:OnNodeProcessed(SearchData, NodeResult)

end

function BTDecorator:WrappedCanExecute(OwnerComp, NodeMemory)
	local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(OwnerComp, NodeMemory) or self;
	return NodeOb and (self:IsInversed() ~= NodeOb:CalculateRawConditionValue(OwnerComp, NodeMemory)) or false;
end

function BTDecorator:WrappedOnNodeActivation(SearchData)
	if (self.bNotifyActivation) then
		local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(SearchData) or self;
		if (NodeOb) then
			NodeOb:OnNodeActivation(SearchData);
		end		
	end
end;

function BTDecorator:WrappedOnNodeDeactivation(SearchData,NodeResult)
	if (self.bNotifyDeactivation) then
		local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(SearchData) or self;
		if (NodeOb) then
			NodeOb:OnNodeDeactivation(SearchData, NodeResult);
		end		
	end
end

function BTDecorator:WrappedOnNodeProcessed(SearchData, NodeResult)
	if (self.bNotifyProcessed) then
		local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(SearchData) or self;
		if (NodeOb) then
			NodeOb:OnNodeProcessed(SearchData, NodeResult);
		end		
	end
end

function BTDecorator:ConditionalFlowAbort(OwnerComp, RequestMode)
	if (self.FlowAbortMode == BehaviorTreeTypes.EBTFlowAbortMode.None) then
		return;
	end

	local InstanceIdx = OwnerComp.FindInstanceContainingNode(self:GetParentNode());
	if (InstanceIdx == BehaviorTreeTypes.INDEX_NONE) then
		return;
	end

	local NodeMemory = OwnerComp:GetNodeMemory(self, InstanceIdx);

	local bIsExecutingBranch = OwnerComp:IsExecutingBranch(self, self:GetChildIndex());
	local bPass = self:WrappedCanExecute(OwnerComp, NodeMemory);
	local bAbortPending = OwnerComp:IsAbortPending();
	local bAlwaysRequestWhenPassing = (RequestMode == EBTDecoratorAbortRequest.ConditionPassing);

	if (bIsExecutingBranch ~= bPass) then
		OwnerComp:RequestExecution(self);
	elseif (not bIsExecutingBranch and not bPass and self:GetParentNode() and self:GetParentNode().Children[self:GetChildIndex()]) then
		local BranchRoot = self:GetParentNode().Children[self:GetChildIndex()].ChildComposite;
		OwnerComp:RequestUnregisterAuxNodesInBranch(BranchRoot);
	elseif (bIsExecutingBranch and bPass and (bAlwaysRequestWhenPassing or bAbortPending)) then
		OwnerComp:RequestExecution(self:GetParentNode(), InstanceIdx, self, self:GetChildIndex(), BehaviorTreeTypes.EBTNodeResult.Aborted);
	end
end

function BTDecorator:IsFlowAbortModeValid()
	return true;
end

function BTDecorator:UpdateFlowAbortMode()

end

return class(BTDecorator, {EBTDecoratorAbortRequest = EBTDecoratorAbortRequest}, BTAuxiliaryNode)