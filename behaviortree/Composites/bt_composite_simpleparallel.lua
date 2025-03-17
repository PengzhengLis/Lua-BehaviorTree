local BTCompositeNode = require("behaviortree.bt_composite_node")
local BehaviorTreeTypes = require("behavior_tree_types")


local EBTParallelChild = {
	MainTask = 1,
	BackgroundTree = 2
}

local EBTParallelMode = {
	AbortBackground = 0,
    WaitForBackground = 1,
}

local BTComposite_SimpleParallel = {
    FinishMode = EBTParallelMode.AbortBackground,
    bUseChildExecutionNotify = true,
	bUseNodeDeactivationNotify = true,
	bUseDecoratorsDeactivationCheck = true,
	bApplyDecoratorScope = true,
}

function BTComposite_SimpleParallel:GetNextChildHandler(SearchData, PrevChild, LastResult)
	local MyMemory = self:GetNodeMemory(SearchData);
	local NextChildIdx = BehaviorTreeTypes.BTSpecialChild.ReturnToParent;

	if (PrevChild == BehaviorTreeTypes.BTSpecialChild.NotInitialized) then
		NextChildIdx = EBTParallelChild.MainTask;
		MyMemory.MainTaskResult = BehaviorTreeTypes.EBTNodeResult.Failed;
		MyMemory.bRepeatMainTask = false;
	elseif ((MyMemory.bMainTaskIsActive or MyMemory.bForceBackgroundTree) and not SearchData.OwnerComp:IsRestartPending()) then
		NextChildIdx = EBTParallelChild.BackgroundTree;
		MyMemory.bForceBackgroundTree = false;
	elseif (MyMemory.bRepeatMainTask) then
	    NextChildIdx = EBTParallelChild.MainTask;
		MyMemory.bRepeatMainTask = false;
    end

	if ((PrevChild == NextChildIdx) and (MyMemory.LastSearchId == SearchData.SearchId)) then
	    SearchData.bPostponeSearch = true;
    end

	MyMemory.LastSearchId = SearchData.SearchId;
	return NextChildIdx;
end

function BTComposite_SimpleParallel:NotifyChildExecution(OwnerComp, NodeMemory, ChildIdx, NodeResult)
	local MyMemory = NodeMemory;
	if (ChildIdx == EBTParallelChild.MainTask) then
		MyMemory.MainTaskResult = NodeResult;

		if (NodeResult[1] == BehaviorTreeTypes.EBTNodeResult.InProgress) then
			local Status = OwnerComp:GetTaskStatus(self.Children[EBTParallelChild.MainTask].ChildTask);
			if (Status == BehaviorTreeTypes.EBTTaskStatus.Active) then
				MyMemory.bMainTaskIsActive = true;
				MyMemory.bForceBackgroundTree = false;
				
				OwnerComp:RegisterParallelTask(self.Children[EBTParallelChild.MainTask].ChildTask);
				self:RequestDelayedExecution(OwnerComp, BehaviorTreeTypes.EBTNodeResult.Succeeded);
            end
		elseif (MyMemory.bMainTaskIsActive) then
			MyMemory.bMainTaskIsActive = false;
			
			local FakeSearchData = BehaviorTreeTypes.FBehaviorTreeSearchData(OwnerComp);
			self:NotifyDecoratorsOnDeactivation(FakeSearchData, ChildIdx, NodeResult);

			local MyInstanceIdx = OwnerComp:FindInstanceContainingNode(self);

			OwnerComp:UnregisterParallelTask(self.Children[EBTParallelChild.MainTask].ChildTask, MyInstanceIdx);
			if (NodeResult[1] ~= BehaviorTreeTypes.EBTNodeResult.Aborted and not MyMemory.bRepeatMainTask) then
				if (self.FinishMode == EBTParallelMode.AbortBackground) then
					OwnerComp:RequestExecution(self, MyInstanceIdx,
						self.Children[EBTParallelChild.MainTask].ChildTask, EBTParallelChild.MainTask, NodeResult);
                end
			end
		elseif (NodeResult[1] == BehaviorTreeTypes.EBTNodeResult.Succeeded and self.FinishMode == EBTParallelMode.WaitForBackground) then
			MyMemory.bForceBackgroundTree = true;

			self:RequestDelayedExecution(OwnerComp, BehaviorTreeTypes.EBTNodeResult.Succeeded);
        end
	end
end

function BTComposite_SimpleParallel:NotifyNodeDeactivation(SearchData, NodeResult)
	local MyMemory = self:GetNodeMemory(SearchData);
	local ActiveInstanceIdx = SearchData.OwnerComp:GetActiveInstanceIdx();

	if ( not MyMemory.bMainTaskIsActive) then
		NodeResult[1] = MyMemory.MainTaskResult;
    end

	if (self.Children[EBTParallelChild.MainTask]) then
		SearchData.AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(self.Children[EBTParallelChild.MainTask].ChildTask, ActiveInstanceIdx, BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
    end
end

function BTComposite_SimpleParallel:CanNotifyDecoratorsOnDeactivation(SearchData, ChildIdx, NodeResult)
	if (ChildIdx == EBTParallelChild.MainTask) then
		local MyMemory = self:GetNodeMemory(SearchData);
		if (MyMemory.bMainTaskIsActive) then
			return false;
        end
	end

	return true;
end

function BTComposite_SimpleParallel:CanPushSubtree(OwnerComp, NodeMemory, ChildIdx)
	return (ChildIdx ~= EBTParallelChild.MainTask);
end

function BTComposite_SimpleParallel:SetChildOverride(SearchData, Index)
	if (Index == EBTParallelChild.MainTask) then
		local MyMemory = self:GetNodeMemory(SearchData);
		MyMemory.bRepeatMainTask = true;

    end
end

return class(BTComposite_SimpleParallel, {}, BTCompositeNode)