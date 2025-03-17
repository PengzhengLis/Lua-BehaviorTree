local BehaviorTreeTypes = require("behavior_tree_types")
local BTNode = require("bt_node")

local statics = {
	EBTChildIndex = {
		FirstNode = 0,
		TaskNode = 1,
	},

	EBTDecoratorLogic = {
		Invalid = 0,
		Test = 1,
		And = 2,
		Or = 3,
		Not = 4,
	},
}


local FBTDecoratorLogic = {
    Operation = statics.EBTDecoratorLogic.Invalid,
    Number = 0,
}

function FBTDecoratorLogic:constructor(InOperation, InNumber)
    if InOperation then
        self.Operation = InOperation
    end

    if InNumber then
        self.Number = InNumber
    end
end

statics.FBTDecoratorLogic = class(FBTDecoratorLogic)

local FBTCompositeChild = {
    ChildComposite = nil,
    ChildTask = nil,
    Decorators = {},
    DecoratorOps = {},
}

statics.FBTCompositeChild = class(FBTCompositeChild)

local function IsLogicOp(Info)
    return (Info.Operation ~= statics.EBTDecoratorLogic.Test) and (Info.Operation ~= statics.EBTDecoratorLogic.Invalid);
end

local FOperationStackInfo = {
    NumLeft = 0,
	Op = statics.EBTDecoratorLogic.And,
	bHasForcedResult = false,
	bForcedResult = false,
}

function FOperationStackInfo:constructor(DecoratorOp)
    if DecoratorOp then
        self.NumLeft = DecoratorOp.Number
        self.Op = DecoratorOp.Operation
    end
end

statics.FOperationStackInfo = class(FOperationStackInfo)

local UpdateOperationStack
UpdateOperationStack = function(OwnerComp, Stack, bTestResult, ref)
	if (#Stack == 0) then
		return bTestResult;
    end

	local CurrentOp = Stack[#Stack];
	CurrentOp.NumLeft = CurrentOp.NumLeft - 1

	if (CurrentOp.Op == statics.EBTDecoratorLogic.And) then
		if ( not CurrentOp.bHasForcedResult and not bTestResult) then
			CurrentOp.bHasForcedResult = true;
			CurrentOp.bForcedResult = bTestResult;
		end
	elseif (CurrentOp.Op == statics.EBTDecoratorLogic.Or) then
		if (not CurrentOp.bHasForcedResult and bTestResult) then
			CurrentOp.bHasForcedResult = true;
			CurrentOp.bForcedResult = bTestResult;
		end	
	elseif (CurrentOp.Op == statics.EBTDecoratorLogic.Not) then
		bTestResult = not bTestResult;
	end

	if (#Stack == 1) then
		ref.bShouldStoreNodeIndex = true;
		if (not bTestResult and ref.FailedDecoratorIdx == BehaviorTreeTypes.BehaviorTreeTypes.INDEX_NONE) then
			ref.FailedDecoratorIdx = ref.NodeDecoratorIdx;
		end
	end

	if (CurrentOp.bHasForcedResult) then
		bTestResult = CurrentOp.bForcedResult;
	end

	if (CurrentOp.NumLeft == 0) then
		table.remove(Stack, #Stack)
		return UpdateOperationStack(OwnerComp, Stack, bTestResult, ref);
	end

	return bTestResult;
end 

local BTCompositeNode = {
    Children = {},
    Services = {},
    bApplyDecoratorScope = false,
    bUseChildExecutionNotify = false,
    bUseNodeActivationNotify = false,
	bUseNodeDeactivationNotify = false,
	bUseDecoratorsActivationCheck = false,
	bUseDecoratorsDeactivationCheck = false,
    bUseDecoratorsFailedActivationCheck = false,
	LastExecutionIndex = 0,
}

function BTCompositeNode:CloneTo(NewInstance)

	for k, v in pairs(self) do
        if type(k) ~= "function" then
            NewInstance[k] = v
        end
    end

	NewInstance.Children = {}
	for i = 1, #self.Children do
		local Child = statics.FBTCompositeChild()
		Child.ChildComposite = self.Children[i].ChildComposite;
		Child.ChildTask = self.Children[i].ChildTask;

		for j = 1, #self.Children[i].Decorators do
			table.insert(Child.Decorators, self.Children[i].Decorators[j])
		end

		for j = 1, #self.Children[i].DecoratorOps do
			table.insert(Child.DecoratorOps, self.Children[i].DecoratorOps[j])
		end

		table.insert(NewInstance.Children, Child)
	end

	NewInstance.Services = {}
	for i = 1, #self.Services do
		table.insert(NewInstance.Services, self.Services[i])
	end
end

function BTCompositeNode:InitializeComposite(InLastExecutionIndex)
    self.LastExecutionIndex = InLastExecutionIndex;
end

function BTCompositeNode:FindChildToExecute(SearchData, LastResult)
    local NodeMemory = self:GetNodeMemory(SearchData);
	local RetIdx = BehaviorTreeTypes.BTSpecialChild.ReturnToParent;

	if #self.Children > 0 then
		local ChildIdx = self:GetNextChild(SearchData, NodeMemory.CurrentChild, LastResult);
		while (self.Children[ChildIdx] and not SearchData.bPostponeSearch) do
			if (self:DoDecoratorsAllowExecution(SearchData.OwnerComp, SearchData.OwnerComp.ActiveInstanceIdx, ChildIdx)) then
				self:OnChildActivation(SearchData, ChildIdx);
				RetIdx = ChildIdx;
				break;
			else
				LastResult.LastResult = BehaviorTreeTypes.EBTNodeResult.Failed;

				local bCanNotify = (not self.bUseDecoratorsFailedActivationCheck) or self:CanNotifyDecoratorsOnFailedActivation(SearchData, ChildIdx, LastResult);
				if (bCanNotify) then
					self:NotifyDecoratorsOnFailedActivation(SearchData, ChildIdx, LastResult);
				end
			end

			ChildIdx = self:GetNextChild(SearchData, ChildIdx, LastResult);
		end
	end

	return RetIdx;
end

function BTCompositeNode:GetChildIndex(SearchData, ChildNode)
    if not ChildNode then 
        ChildNode = SearchData
        for ChildIndex = 1, #self.Children, 1 do
		    if (self.Children[ChildIndex].ChildComposite == ChildNode or self.Children[ChildIndex].ChildTask == ChildNode) then
			    return ChildIndex;
            end
        end

	    return BehaviorTreeTypes.BTSpecialChild.ReturnToParent;
    else
        if (ChildNode:GetParentNode() ~= self) then
            local NodeMemory = self:GetNodeMemory(SearchData);
            return NodeMemory.CurrentChild;		
        end

        return self:GetChildIndex(ChildNode)
    end
end

function BTCompositeNode:OnChildActivation(SearchData, ChildIndex)
    if type(ChildIndex) == "table" then
        local ChildNode = ChildIndex
        return self:OnChildActivation(SearchData, self:GetChildIndex(SearchData, ChildNode))
    end

    local ChildInfo = self.Children[ChildIndex];
	local NodeMemory = self:GetNodeMemory(SearchData);

	local bCanNotify = not self.bUseDecoratorsActivationCheck or self:CanNotifyDecoratorsOnActivation(SearchData, ChildIndex);
	if (bCanNotify) then
		self:NotifyDecoratorsOnActivation(SearchData, ChildIndex);
    end

	if (ChildInfo.ChildComposite) then
		ChildInfo.ChildComposite:OnNodeActivation(SearchData);
    end

	NodeMemory.CurrentChild = ChildIndex;
end

function BTCompositeNode:OnChildDeactivation(SearchData, ChildIndex, NodeResult)
    if type(ChildIndex) == "table" then
        local ChildNode = ChildIndex
        return self:OnChildDeactivation(SearchData, self:GetChildIndex(SearchData, ChildNode), NodeResult);    
    end

    local ChildInfo = self.Children[ChildIndex];

	if (ChildInfo.ChildTask) then
		for ServiceIndex = 1, #self.ChildInfo.ChildTask.Services, 1 do
			SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(ChildInfo.ChildTask.Services[ServiceIndex], SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
        end
	elseif (ChildInfo.ChildComposite) then
		ChildInfo.ChildComposite:OnNodeDeactivation(SearchData, NodeResult);
    end

	local bCanNotify = (not self.bUseDecoratorsDeactivationCheck) or self:CanNotifyDecoratorsOnDeactivation(SearchData, ChildIndex, NodeResult);
	if (bCanNotify) then
		self:NotifyDecoratorsOnDeactivation(SearchData, ChildIndex, NodeResult);
    end
end

function BTCompositeNode:OnNodeActivation(SearchData)
    self:OnNodeRestart(SearchData);

	if (self.bUseNodeActivationNotify) then
		self:NotifyNodeActivation(SearchData);
    end

	for ServiceIndex = 1, #self.Services do
		SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(self.Services[ServiceIndex], SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Add));

		self.Services[ServiceIndex]:NotifyParentActivation(SearchData);
    end
end

function BTCompositeNode:OnNodeDeactivation(SearchData, NodeResult)
	if (self.bUseNodeDeactivationNotify) then
		self:NotifyNodeDeactivation(SearchData, NodeResult);
    end

	for ServiceIndex = 1, #self.Services do
		SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(self.Services[ServiceIndex], SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
    end

	if (self.bApplyDecoratorScope) then
		local InstanceIdx = SearchData.OwnerComp.GetActiveInstanceIdx();
		local FromIndex = BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, self:GetExecutionIndex());
		local ToIndex = BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, self:GetLastExecutionIndex());

		SearchData.OwnerComp:UnregisterAuxNodesInRange(FromIndex, ToIndex);

		for Idx = #SearchData.PendingUpdates, 1, -1 do
			local UpdateInfo = SearchData.PendingUpdates[Idx];
			if (UpdateInfo.Mode == BehaviorTreeTypes.EBTNodeUpdateMode.Add) then
				local UpdateNodeIdx = UpdateInfo.AuxNode and UpdateInfo.AuxNode:GetExecutionIndex() or UpdateInfo.TaskNode:GetExecutionIndex();
				local UpdateIdx = BehaviorTreeTypes.FBTNodeIndex(UpdateInfo.InstanceIndex, UpdateNodeIdx);

				if (FromIndex:TakesPriorityOver(UpdateIdx) and UpdateIdx:TakesPriorityOver(ToIndex)) then
                    table.remove(SearchData.PendingUpdates, Idx)
                end
			end
		end
	end
end

function BTCompositeNode:OnNodeRestart(SearchData)
    local NodeMemory = self:GetNodeMemory(SearchData);
	NodeMemory.CurrentChild = BehaviorTreeTypes.BTSpecialChild.NotInitialized;
	NodeMemory.OverrideChild = BehaviorTreeTypes.BTSpecialChild.NotInitialized;
end

function BTCompositeNode:ConditionalNotifyChildExecution(OwnerComp, NodeMemory, ChildNode, NodeResult)
    if (self.bUseChildExecutionNotify) then
		for ChildIndex = 1, #self.Children do
			if (self.Children[ChildIndex].ChildComposite == ChildNode or self.Children[ChildIndex].ChildTask == ChildNode) then
				self:NotifyChildExecution(OwnerComp, NodeMemory, ChildIndex, NodeResult);
				break;
            end
		end
	end
end

function BTCompositeNode:GetChildNode(Index)
    return self.Children[Index] and self.Children[Index].ChildComposite or self.Children[Index].ChildTask
end

function BTCompositeNode:GetChildrenNum()
    return #self.Children
end

function BTCompositeNode:GetChildExecutionIndex(Index, ChildMode)
    local ChildNode = self:GetChildNode(Index);
	if (ChildNode) then
		local Offset = 0;

		if (ChildMode == statics.EBTChildIndex.FirstNode) then
			Offset = Offset + #self.Children[Index].Decorators

			if (self.Children[Index].ChildTask) then
				Offset = Offset + #self.Children[Index].ChildTask.Services;
            end
		end

		return ChildNode:GetExecutionIndex() - Offset;
	end

	return (self.LastExecutionIndex + 1);
end

function BTCompositeNode:GetLastExecutionIndex()
    return self.LastExecutionIndex;
end

function BTCompositeNode:SetChildOverride(SearchData, Index)
    if (self.Children[Index] or Index == BehaviorTreeTypes.BTSpecialChild.ReturnToParent) then
		local MyMemory = self:GetNodeMemory(SearchData);
		MyMemory.OverrideChild = Index;
    end
end

function BTCompositeNode:CanPushSubtree(OwnerComp, NodeMemory, ChildIdx)
    return true;
end

function BTCompositeNode:GetMatchingChildIndex(ActiveInstanceIdx, NodeIdx)
    local OutsideRange = BehaviorTreeTypes.BTSpecialChild.ReturnToParent;
	local UnlimitedRange = #self.Children;

	if (ActiveInstanceIdx == NodeIdx.InstanceIndex) then
		if (self:GetExecutionIndex() > NodeIdx.ExecutionIndex) then
			return OutsideRange;
        end

		for ChildIndex = 1, #self.Children do
			local FirstIndexInBranch = self:GetChildExecutionIndex(ChildIndex, statics.EBTChildIndex.FirstNode);
			if (FirstIndexInBranch > NodeIdx.ExecutionIndex) then
				return ChildIndex > 1 and (ChildIndex - 1) or 1;
            end
		end

		return UnlimitedRange;
	end

	return (ActiveInstanceIdx > NodeIdx.InstanceIndex) and UnlimitedRange or OutsideRange;
end

function BTCompositeNode:GetBranchExecutionIndex(NodeInBranchIdx)
    local PrevBranchStartIdx = self:GetExecutionIndex();
	for ChildIndex = 1, #self.Children do
		local BranchStartIdx = self:GetChildExecutionIndex(ChildIndex, statics.EBTChildIndex.FirstNode);
		if (BranchStartIdx > NodeInBranchIdx) then
			break;
        end

		PrevBranchStartIdx = BranchStartIdx;
	end

	return PrevBranchStartIdx;
end

function BTCompositeNode:DoDecoratorsAllowExecution(OwnerComp, InstanceIdx, ChildIdx)
    if (not self.Children[ChildIdx]) then
		return false;
    end

	local ChildInfo = self.Children[ChildIdx];
	local bResult = true;

	if (#ChildInfo.Decorators == 0) then
		return bResult;
    end

	local MyInstance = OwnerComp.InstanceStack[InstanceIdx];

	if (#ChildInfo.DecoratorOps == 0) then
		for DecoratorIndex = 1, #ChildInfo.Decorators do
			local TestDecorator = ChildInfo.Decorators[DecoratorIndex];
			local bIsAllowed = TestDecorator and TestDecorator:WrappedCanExecute(OwnerComp, TestDecorator:GetNodeMemory(MyInstance)) or false;

			local ChildNode = self:GetChildNode(ChildIdx);

			if (not bIsAllowed) then
				bResult = false;
				break;
            end
		end
	else
		local OperationStack = {};
		local ref = {
			NodeDecoratorIdx = BehaviorTreeTypes.INDEX_NONE,
			FailedDecoratorIdx = BehaviorTreeTypes.INDEX_NONE,
			bShouldStoreNodeIndex = true,
		}

		for OperationIndex = 1, #ChildInfo.DecoratorOps do
			local DecoratorOp = ChildInfo.DecoratorOps[OperationIndex];
			if (IsLogicOp(DecoratorOp)) then
                table.insert(OperationStack, statics.FOperationStackInfo(DecoratorOp))
			elseif DecoratorOp.Operation == BehaviorTreeTypes.EBTDecoratorLogic.Test then

				local bHasOverride = #OperationStack > 0 and OperationStack[#OperationStack].bHasForcedResult or false;
				local bCurrentOverride = #OperationStack > 0 and OperationStack[#OperationStack].bForcedResult or false;

				if (ref.bShouldStoreNodeIndex) then
					ref.bShouldStoreNodeIndex = false;
					ref.NodeDecoratorIdx = DecoratorOp.Number;
                end

				local TestDecorator = ChildInfo.Decorators[DecoratorOp.Number];
				local bIsAllowed = bHasOverride and bCurrentOverride or TestDecorator:WrappedCanExecute(OwnerComp, TestDecorator:GetNodeMemory(MyInstance));

				bResult = UpdateOperationStack(OwnerComp, OperationStack, bIsAllowed, ref);
				if (#OperationStack == 0) then
					break;
				end
			end
		end
	end

	return bResult;
end

function BTCompositeNode:IsApplyingDecoratorScope()
    return self.bApplyDecoratorScope;
end

function BTCompositeNode:NotifyChildExecution(OwnerComp, NodeMemory, ChildIdx, NodeResult)

end

function BTCompositeNode:NotifyNodeActivation(SearchData)

end

function BTCompositeNode:NotifyNodeDeactivation(SearchData, NodeResult)

end

function BTCompositeNode:CanNotifyDecoratorsOnActivation(SearchData, ChildIdx)
    return true;
end

function BTCompositeNode:CanNotifyDecoratorsOnDeactivation(SearchData, ChildIdx, NodeResult)
    return true;
end

function BTCompositeNode:CanNotifyDecoratorsOnFailedActivation(SearchData, ChildIdx, NodeResult)
    return true;
end

function BTCompositeNode:NotifyDecoratorsOnActivation(SearchData, ChildIdx)
    local ChildInfo = self.Children[ChildIdx];
	for DecoratorIndex = 1, #ChildInfo.Decorators do
		local DecoratorOb = ChildInfo.Decorators[DecoratorIndex];
		DecoratorOb:WrappedOnNodeActivation(SearchData);

        local FlowAbortMode = DecoratorOb:GetFlowAbortMode()
        if FlowAbortMode == BehaviorTreeTypes.EBTFlowAbortMode.LowerPriority then
            SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(DecoratorOb, SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
        elseif FlowAbortMode == BehaviorTreeTypes.EBTFlowAbortMode.Self or FlowAbortMode == BehaviorTreeTypes.EBTFlowAbortMode.Both then
            SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(DecoratorOb, SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Add));
        end
	end
end

function BTCompositeNode:NotifyDecoratorsOnDeactivation(SearchData, ChildIdx, NodeResult)
    local ChildInfo = self.Children[ChildIdx];
	if (NodeResult[1] == BehaviorTreeTypes.EBTNodeResult.Aborted) then
		for DecoratorIndex = 1, #ChildInfo.Decorators do
			local DecoratorOb = ChildInfo.Decorators[DecoratorIndex];
			DecoratorOb:WrappedOnNodeDeactivation(SearchData, NodeResult);
        end
	else
		for DecoratorIndex = 1, #ChildInfo.Decorators do
		    local DecoratorOb = ChildInfo.Decorators[DecoratorIndex];
			DecoratorOb:WrappedOnNodeProcessed(SearchData, NodeResult);
			DecoratorOb:WrappedOnNodeDeactivation(SearchData, NodeResult);

			if (DecoratorOb:GetFlowAbortMode() == BehaviorTreeTypes.EBTFlowAbortMode.Self) then
				SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(DecoratorOb, SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
			elseif (DecoratorOb:GetFlowAbortMode() == BehaviorTreeTypes.EBTFlowAbortMode.LowerPriority) then
			    SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(DecoratorOb, SearchData.OwnerComp:GetActiveInstanceIdx(), BehaviorTreeTypes.EBTNodeUpdateMode.Add));
			end
		end
	end
end

function BTCompositeNode:NotifyDecoratorsOnFailedActivation(SearchData, ChildIdx, NodeResult)
    local ChildInfo = self.Children[ChildIdx];
	local ActiveInstanceIdx = SearchData.OwnerComp:GetActiveInstanceIdx();

	for DecoratorIndex = 1, #ChildInfo.Decorators do
		local DecoratorOb = ChildInfo.Decorators[DecoratorIndex];
		DecoratorOb:WrappedOnNodeProcessed(SearchData, NodeResult);

		if (DecoratorOb:GetFlowAbortMode() == BehaviorTreeTypes.EBTFlowAbortMode.LowerPriority or
			DecoratorOb:GetFlowAbortMode() == BehaviorTreeTypes.EBTFlowAbortMode.Both) then

			SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(DecoratorOb, ActiveInstanceIdx, BehaviorTreeTypes.EBTNodeUpdateMode.Add));
		end
	end
            
end

function BTCompositeNode:GetNextChild(SearchData, LastChildIdx, LastResult)
    local NodeMemory = self:GetNodeMemory(SearchData);
	local NextChildIndex = BehaviorTreeTypes.BTSpecialChild.ReturnToParent;
	local ActiveInstanceIdx = SearchData.OwnerComp:GetActiveInstanceIdx();

	if (LastChildIdx == BehaviorTreeTypes.BTSpecialChild.NotInitialized and SearchData.SearchStart:IsSet() and
		BehaviorTreeTypes.FBTNodeIndex(ActiveInstanceIdx, self:GetExecutionIndex()):TakesPriorityOver(SearchData.SearchStart)) then

		NextChildIndex = self:GetMatchingChildIndex(ActiveInstanceIdx, SearchData.SearchStart);
	elseif (NodeMemory.OverrideChild ~= BehaviorTreeTypes.BTSpecialChild.NotInitialized and not SearchData.OwnerComp:IsRestartPending()) then

		NextChildIndex = NodeMemory.OverrideChild;
		NodeMemory.OverrideChild = BehaviorTreeTypes.BTSpecialChild.NotInitialized;
	else
		NextChildIndex = self:GetNextChildHandler(SearchData, LastChildIdx, LastResult);
    end

	return NextChildIndex;
end

function BTCompositeNode:RequestDelayedExecution(OwnerComp, LastResult)
    OwnerComp:RequestExecution(LastResult);
end

function BTCompositeNode:GetNextChildHandler(SearchData, PrevChild, LastResult)
    return BehaviorTreeTypes.BTSpecialChild.ReturnToParent
end

return class(BTCompositeNode, statics, BTNode)