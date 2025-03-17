local BehaviorTreeTypes = require("behavior_tree_types")
local BrainComponent = require("ai.brain_component")
local BehaviorTreeManager = require("behavior_tree_mamager")
local Utils = require("library.Utils")
local BTDecorator = require("bt_decorator")
local BTService = require("bt_service")
local BTTaskNode = require("bt_task_node")
local AITypes = require("ai.ai_types")

local FBTNodeExecutionInfo = {
	SearchStart = BehaviorTreeTypes.FBTNodeIndex(),
	SearchEnd = BehaviorTreeTypes.FBTNodeIndex(),

	ExecuteNode = nil,

	ExecuteInstanceIdx = 1,
	ContinueWithResult = BehaviorTreeTypes.EBTNodeResult.Succeeded,

	bTryNextChild = false,
	bIsRestart = false,
}

local FBTPendingExecutionInfo = {
	NextTask = nil,
	bOutOfNodes = false,
	bLocked = false,
}

function FBTPendingExecutionInfo:IsSet()
	return (self.NextTask ~= nil or self.bOutOfNodes) and not self.bLocked
end

function FBTPendingExecutionInfo:IsLocked()
	return self.bLocked
end

function FBTPendingExecutionInfo:Lock()
	self.bLocked = true
end

function FBTPendingExecutionInfo:Unlock()
	self.bLocked = false
end

local FBTPendingAuxNodesUnregisterInfo = {
	Ranges = {},
}

local FBTTreeStartInfo = {
	Asset = nil,
	ExecuteMode = BehaviorTreeTypes.EBTExecutionMode.Looped,
	bPendingInitialize = false,
}

function FBTTreeStartInfo:IsSet()
	return self.Asset ~= nil
end

function FBTTreeStartInfo:HasPendingInitialize()
	return self.bPendingInitialize and self:IsSet()
end

local FScopedBehaviorTreeLock = {
	LockTick = 1,
	LockReentry = 2,

	OwnerComp = nil,
	LockFlag = 0,
}

function FScopedBehaviorTreeLock:constructor(InOwnerComp, InLockFlag)
	self.OwnerComp = InOwnerComp
	self.LockFlag = InLockFlag

	self.OwnerComp.StopTreeLock = Utils.Or(self.OwnerComp.StopTreeLock, self.LockFlag)
end

function FScopedBehaviorTreeLock:dtor()
	self.OwnerComp.StopTreeLock = Utils.And(self.OwnerComp.StopTreeLock, Utils.Not(self.LockFlag))
end

local statics = {
	FBTNodeExecutionInfo = class(FBTNodeExecutionInfo),
	FBTPendingExecutionInfo = class(FBTPendingExecutionInfo),
	FBTPendingAuxNodesUnregisterInfo = class(FBTPendingAuxNodesUnregisterInfo),
	FBTTreeStartInfo = class(FBTTreeStartInfo),
	FScopedBehaviorTreeLock = class(FScopedBehaviorTreeLock),
}

local BehaviorTreeComponent = {
	InstanceStack = {},
	KnownInstances = {},
	NodeInstances = {},
	
	SearchData = nil,
	ExecutionRequest = statics.FBTNodeExecutionInfo(),
	PendingExecution = statics.FBTPendingExecutionInfo(),
	PendingUnregisterAuxNodesRequests = statics.FBTPendingAuxNodesUnregisterInfo,
	TreeStartInfo = statics.FBTTreeStartInfo(),
	
	TaskMessageObservers = {},

	ActiveInstanceIdx = 1,

	StopTreeLock = false,
	bDeferredStopTree = false,
	bLoopExecution = false,
	bWaitingForAbortingTasks = false,
	bRequestedFlowUpdate = false,
	bRequestedStop = false,
	bIsRunning = false,
	bIsPaused = false,
	bTickEnable = true,
	bTickedOnce = false,
	NextTickDeltaTime = 0.0,
	AccumulatedTickDeltaTime = 0.0,
}

function BehaviorTreeComponent:constructor()
	self.SearchData = BehaviorTreeTypes.FBehaviorTreeself.SearchData(self)
end

function BehaviorTreeComponent:GetCurrentTree()
	return #self.InstanceStack > 0 and self.KnownInstances[self.InstanceStack[self.ActiveInstanceIdx].InstanceIdIndex].TreeAsset or nil;
end

function BehaviorTreeComponent:GetRootTree()
	return #self.InstanceStack > 0 and self.KnownInstances[self.InstanceStack[1].InstanceIdIndex].TreeAsset or nil;
end

function BehaviorTreeComponent:GetActiveNode()
	return #self.InstanceStack > 0 and self.InstanceStack[self.ActiveInstanceIdx].ActiveNode or nil;
end

function BehaviorTreeComponent:GetActiveInstanceIdx()
	return self.ActiveInstanceIdx;
end

function BehaviorTreeComponent:IsRestartPending()
	return self.ExecutionRequest.ExecuteNode and not self.ExecutionRequest.bTryNextChild;
end

function BehaviorTreeComponent:IsAbortPending()
	return self.bWaitingForAbortingTasks or self.PendingExecution:IsSet();
end


function BehaviorTreeComponent:UninitializeComponent()
	local BTManager = BehaviorTreeManager;
	if (BTManager) then
		BTManager:RemoveActiveComponent(self);
	end

	self:RemoveAllInstances();
end

function BehaviorTreeComponent:IsComponentTickEnabled()
	return self.bTickEnable
end

function BehaviorTreeComponent:SetComponentTickEnabled(bEnabled)
	local bWasEnabled = self.bTickEnable
	self.bTickEnable = true

	if (not bWasEnabled) then
		self.bTickedOnce = false;
		self:ScheduleNextTick(0.0);
	end
end

function BehaviorTreeComponent:TreeHasBeenStarted()
	return self.bIsRunning and #self.InstanceStack > 0;
end

function BehaviorTreeComponent:IsRunning()
	return self.bIsPaused == false and self:TreeHasBeenStarted() == true;
end

function BehaviorTreeComponent:IsPaused()
	return self.bIsPaused;
end

function BehaviorTreeComponent:StartTree(Asset, ExecuteMode)

	local CurrentRoot = self:GetRootTree();
	
	if (CurrentRoot == Asset and self:TreeHasBeenStarted()) then
		return;
	elseif (CurrentRoot) then

	end

	self:StopTree(BehaviorTreeTypes.EBTStopMode.Safe);

	self.TreeStartInfo.Asset = Asset;
	self.TreeStartInfo.ExecuteMode = ExecuteMode;
	self.TreeStartInfo.bPendingInitialize = true;

	self:ProcessPendingInitialize();
end

function BehaviorTreeComponent:ProcessPendingInitialize()

	self:StopTree(BehaviorTreeTypes.EBTStopMode.Safe);
	if (self.bWaitingForAbortingTasks) then
		return;
	end

	self:RemoveAllInstances();

	self.bLoopExecution = (self.TreeStartInfo.ExecuteMode == BehaviorTreeTypes.EBTExecutionMode.Looped);
	self.bIsRunning = true;

	local BTManager = BehaviorTreeManager
	if (BTManager) then
		BTManager:AddActiveComponent(self);
	end

	local bPushed = self:PushInstance(self.TreeStartInfo.Asset);
	self.TreeStartInfo.bPendingInitialize = false;
end

function BehaviorTreeComponent:StopTree(StopMode)

	if (self.StopTreeLock) then
		self.bDeferredStopTree = true;
		self:ScheduleNextTick(0.0);
		return;
	end

	local ScopedLock = statics.FScopedBehaviorTreeLock(self, FScopedBehaviorTreeLock.LockReentry);
	if (not self.bRequestedStop) then
		self.bRequestedStop = true;

		for InstanceIndex = #self.InstanceStack, 1, -1 do
			local InstanceInfo = self.InstanceStack[InstanceIndex];

			InstanceInfo:ExecuteOnEachAuxNode(function (AuxNode) 
				local NodeMemory = AuxNode:GetNodeMemory(InstanceInfo)
				AuxNode:WrappedOnCeaseRelevant(self, NodeMemory);
				end);
			InstanceInfo:ResetActiveAuxNodes();

			InstanceInfo:ExecuteOnEachParallelTask(function(ParallelTaskInfo, ParallelIndex)
					if (ParallelTaskInfo.Status ~= BehaviorTreeTypes.EBTTaskStatus.Active) then
						return;
					end

					local CachedTaskNode = ParallelTaskInfo.TaskNode;
					if (not CachedTaskNode) then
						return;
					end

					self:UnregisterMessageObserversFrom(CachedTaskNode);

					local NodeMemory = CachedTaskNode:GetNodeMemory(InstanceInfo);
					local NodeResult = CachedTaskNode:WrappedAbortTask(self, NodeMemory);

					if (NodeResult == BehaviorTreeTypes.EBTNodeResult.InProgress) then
						local bIsValidForStatus = InstanceInfo:IsValidParallelTaskIndex(ParallelIndex) and (ParallelTaskInfo.TaskNode == CachedTaskNode);
						if (bIsValidForStatus) then
							InstanceInfo:MarkParallelTaskAsAbortingAt(ParallelIndex);
							self.bWaitingForAbortingTasks = true;
						end
					end

					self:OnTaskFinished(CachedTaskNode, NodeResult);
				end);

			if (InstanceInfo.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.ActiveTask) then
				local TaskNode = InstanceInfo.ActiveNode;

				self:UnregisterMessageObserversFrom(TaskNode);
				InstanceInfo.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.AbortingTask;

				local NodeMemory = TaskNode:GetNodeMemory(InstanceInfo);
				local TaskResult = TaskNode:WrappedAbortTask(self, NodeMemory);

				if (InstanceInfo.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask) then
					self:OnTaskFinished(TaskNode, TaskResult);
				end
			end
		end
	end

	if (self.bWaitingForAbortingTasks) then
		if (StopMode == BehaviorTreeTypes.EBTStopMode.Safe) then
			ScopedLock:dtor()
			return;
		end
	end

	if (self.InstanceStack.Num()) then
		local DeactivatedChildIndex = BehaviorTreeTypes.INDEX_NONE;
		local AbortedResult = BehaviorTreeTypes.EBTNodeResult.Aborted;
		self:DeactivateUpTo(self.InstanceStack[1].RootNode, 1, AbortedResult, DeactivatedChildIndex);
	end

	for InstanceIndex = 1, #self.InstanceStack do
		local InstanceInfo = self.InstanceStack[InstanceIndex];
		self.InstanceStack[InstanceIndex].Cleanup(self, BehaviorTreeTypes.EBTMemoryClear.Destroy);
	end

	self.InstanceStack = {};
	self.TaskMessageObservers = {};
	self.SearchData = {};
	self.ExecutionRequest = statics.FBTNodeExecutionInfo();
	self.PendingExecution = statics.FBTPendingExecutionInfo();
	self.ActiveInstanceIdx = 1;

	self.bRequestedFlowUpdate = false;
	self.bRequestedStop = false;
	self.bIsRunning = false;
	self.bWaitingForAbortingTasks = false;
	self.bDeferredStopTree = false;

	ScopedLock:dtor()
end

function BehaviorTreeComponent:RestartTree()
	
	if (not self.bIsRunning) then
		if (self.TreeStartInfo:IsSet()) then
			self.TreeStartInfo.bPendingInitialize = true;
			self:ProcessPendingInitialize();
		end
	elseif (self.bRequestedStop) then
		self.TreeStartInfo.bPendingInitialize = true;
	elseif (#self.InstanceStack > 0) then
		local TopInstance = self.InstanceStack[1];
		self:RequestExecution(TopInstance.RootNode, 1, TopInstance.RootNode, 1, BehaviorTreeTypes.EBTNodeResult.Aborted);
	end
end

function BehaviorTreeComponent:Cleanup()
	self:StopTree(BehaviorTreeTypes.EBTStopMode.Forced);
	self:RemoveAllInstances();

	self.KnownInstances = {};
	self.InstanceStack = {};
	self.NodeInstances = {};
end

function BehaviorTreeComponent:HandleMessage(Message)
	BrainComponent.HandleMessage(self, Message);
	self:ScheduleNextTick(0.0);
end

function BehaviorTreeComponent:OnTaskFinished(TaskNode, TaskResult)

	if (TaskNode == nil or #self.InstanceStack == 0) then
		return;
	end

	local ParentNode = TaskNode:GetParentNode();
	local TaskInstanceIdx = self:FindInstanceContainingNode(TaskNode);
	if not self.InstanceStack[TaskInstanceIdx] then
		return;
	end

	local ParentMemory = ParentNode:GetNodeMemory(self.InstanceStack[TaskInstanceIdx]);

	local bWasWaitingForAbort = self.bWaitingForAbortingTasks;
	ParentNode:ConditionalNotifyChildExecution(self, ParentMemory, TaskNode, TaskResult);
	
	if (TaskResult ~= BehaviorTreeTypes.EBTNodeResult.InProgress) then

		self:UnregisterMessageObserversFrom(TaskNode);

		local TaskMemory = TaskNode:GetNodeMemory(self.InstanceStack[TaskInstanceIdx]);
		TaskNode:WrappedOnTaskFinished(self, TaskMemory, TaskResult);

		if (self.InstanceStack[self.ActiveInstanceIdx] and self.InstanceStack[self.ActiveInstanceIdx].ActiveNode == TaskNode) then
			local ActiveInstance = self.InstanceStack[self.ActiveInstanceIdx];
			local bWasAborting = (ActiveInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask);
			ActiveInstance.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.InactiveTask;

			if (not bWasAborting) then
				self:RequestExecution(TaskResult);
			end
		elseif (TaskResult == BehaviorTreeTypes.EBTNodeResult.Aborted and self.InstanceStack[TaskInstanceIdx] and self.InstanceStack[TaskInstanceIdx].ActiveNode == TaskNode) then

			self.InstanceStack[TaskInstanceIdx].ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.InactiveTask;
		end

		self:UpdateAbortingTasks();

		if (not self.bWaitingForAbortingTasks and bWasWaitingForAbort) then
			if (self.bRequestedStop) then
				self:StopTree(BehaviorTreeTypes.EBTStopMode.Safe);
			else
				if (self.ExecutionRequest.ExecuteNode) then
					self.PendingExecution:Lock();

					if (self.ExecutionRequest.SearchEnd:IsSet()) then
						self.ExecutionRequest.SearchEnd = BehaviorTreeTypes.FBTNodeIndex();
					end
				end

				self:ScheduleExecutionUpdate();
			end
		end
	else
		self:UpdateAbortingTasks();
	end

	if (self.TreeStartInfo.HasPendingInitialize()) then
		self:ProcessPendingInitialize();
	end
end

function BehaviorTreeComponent:OnTreeFinished()

	self.ActiveInstanceIdx = 1;

	if (self.bLoopExecution and self.InstanceStack.Num()) then
		local TopInstance = self.InstanceStack[1];
		TopInstance.ActiveNode = nil;
		TopInstance.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.Composite;

		self:UnregisterAuxNodesUpTo(BehaviorTreeTypes.FBTNodeIndex(0, 0));

		self:RequestExecution(TopInstance.RootNode, 1, TopInstance.RootNode, 1, BehaviorTreeTypes.EBTNodeResult.InProgress);
	else
		self:StopTree(BehaviorTreeTypes.EBTStopMode.Safe);
	end
end

function BehaviorTreeComponent:IsExecutingBranch(Node, ChildIndex)

	local TestInstanceIdx = self:FindInstanceContainingNode(Node);
	if not self.InstanceStack[TestInstanceIdx] or self.InstanceStack[TestInstanceIdx].ActiveNode == nil then
		return false;
	end

	local TestInstance = self.InstanceStack[TestInstanceIdx];
	if (Node == TestInstance.RootNode or Node == TestInstance.ActiveNode) then
		return true;
	end

	local ActiveExecutionIndex = TestInstance.ActiveNode:GetExecutionIndex();
	local NextChildExecutionIndex = Node:GetParentNode():GetChildExecutionIndex(ChildIndex + 1);
	return (ActiveExecutionIndex >= Node:GetExecutionIndex()) and (ActiveExecutionIndex < NextChildExecutionIndex);
end

function BehaviorTreeComponent:IsAuxNodeActive(AuxNode)

	if (AuxNode == nil) then
		return false;
	end

	local AuxExecutionIndex = AuxNode:GetExecutionIndex();
	for InstanceIndex = 0, #self.InstanceStack do
		local InstanceInfo = self.InstanceStack[InstanceIndex];
		for _, TestAuxNode in ipairs(InstanceInfo.GetActiveAuxNodes()) do
			if (TestAuxNode == AuxNode) then
				return true;
			end

			if (AuxNode:IsInstanced() and TestAuxNode and TestAuxNode:GetExecutionIndex() == AuxExecutionIndex) then
				local NodeMemory = TestAuxNode:GetNodeMemory(InstanceInfo);
				local NodeInstance = TestAuxNode:GetNodeInstance(self, NodeMemory);

				if (NodeInstance == AuxNode) then
					return true;
				end
			end
		end
	end

	return false;
end

function BehaviorTreeComponent:IsAuxNodeActive(AuxNodeTemplate, InstanceIdx)

	return self.InstanceStack[InstanceIdx] and Utils.array.find(self.InstanceStack[InstanceIdx]:GetActiveAuxNodes(), AuxNodeTemplate);
end

function BehaviorTreeComponent:GetTaskStatus(TaskNode)

	local Status = BehaviorTreeTypes.EBTTaskStatus.Inactive;
	local InstanceIdx = self:FindInstanceContainingNode(TaskNode);

	if self.InstanceStack[InstanceIdx] then
		local ExecutionIndex = TaskNode:GetExecutionIndex();
		local InstanceInfo = self.InstanceStack[InstanceIdx];

		for _, ParallelInfo in ipairs(InstanceInfo.GetParallelTasks()) do
			if (ParallelInfo.TaskNode == TaskNode or
				(TaskNode:IsInstanced() and ParallelInfo.TaskNode and 
				ParallelInfo.TaskNode:GetExecutionIndex() == ExecutionIndex)) then
				Status = ParallelInfo.Status;
				break;
			end
		end

		if (Status == BehaviorTreeTypes.EBTTaskStatus.Inactive) then
			if (InstanceInfo.ActiveNode == TaskNode or 
				(TaskNode:IsInstanced() and InstanceInfo.ActiveNode and 
				InstanceInfo.ActiveNode:GetExecutionIndex() == ExecutionIndex)) then
				Status =
					(InstanceInfo.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.ActiveTask) and BehaviorTreeTypes.EBTTaskStatus.Active or
					(InstanceInfo.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask) and BehaviorTreeTypes.EBTTaskStatus.Aborting or
					BehaviorTreeTypes.EBTTaskStatus.Inactive;
			end
		end
	end

	return Status;
end

function BehaviorTreeComponent:RequestUnregisterAuxNodesInBranch(Node)

	local InstanceIdx = self:FindInstanceContainingNode(Node);
	if (InstanceIdx ~= BehaviorTreeTypes.INDEX_NONE) then
		self.PendingUnregisterAuxNodesRequests.Ranges[BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, Node:GetExecutionIndex())] =
			BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, Node:GetLastExecutionIndex());

		self:ScheduleNextTick(0.0);
	end
end

function BehaviorTreeComponent:RequestExecution(RequestedBy)

	local AbortMode = RequestedBy:GetFlowAbortMode();
	if (AbortMode == BehaviorTreeTypes.EBTFlowAbortMode.None) then
		return;
	end

	local InstanceIdx = self:FindInstanceContainingNode(RequestedBy:GetParentNode());
	if (InstanceIdx == BehaviorTreeTypes.INDEX_NONE) then
		return;
	end


	if (AbortMode == BehaviorTreeTypes.EBTFlowAbortMode.Both) then
		local bIsExecutingChildNodes = self:IsExecutingBranch(RequestedBy, RequestedBy:GetChildIndex());
		AbortMode = bIsExecutingChildNodes and BehaviorTreeTypes.EBTFlowAbortMode.Self or BehaviorTreeTypes.EBTFlowAbortMode.LowerPriority;
	end

	local ContinueResult = (AbortMode == BehaviorTreeTypes.EBTFlowAbortMode.Self) and BehaviorTreeTypes.EBTNodeResult.Failed or BehaviorTreeTypes.EBTNodeResult.Aborted;
	self:RequestExecution(RequestedBy:GetParentNode(), InstanceIdx, RequestedBy, RequestedBy:GetChildIndex(), ContinueResult);
end

function BehaviorTreeComponent:CalculateRelativePriority(NodeA, NodeB)

	local RelativePriority = BehaviorTreeTypes.EBTNodeRelativePriority.Same;

	if (NodeA ~= NodeB) then
		local InstanceIndexA = self:FindInstanceContainingNode(NodeA);
		local InstanceIndexB = self:FindInstanceContainingNode(NodeB);
		if (InstanceIndexA == InstanceIndexB) then
			RelativePriority = NodeA:GetExecutionIndex() < NodeB:GetExecutionIndex() and BehaviorTreeTypes.EBTNodeRelativePriority.Higher or BehaviorTreeTypes.EBTNodeRelativePriority.Lower;
		else
			RelativePriority = (InstanceIndexA ~= BehaviorTreeTypes.INDEX_NONE and InstanceIndexB ~= BehaviorTreeTypes.INDEX_NONE) and (InstanceIndexA < InstanceIndexB and BehaviorTreeTypes.EBTNodeRelativePriority.Higher or BehaviorTreeTypes.EBTNodeRelativePriority.Lower)
				or (InstanceIndexA ~= BehaviorTreeTypes.INDEX_NONE and BehaviorTreeTypes.EBTNodeRelativePriority.Higher or BehaviorTreeTypes.EBTNodeRelativePriority.Lower);
		end
	end

	return RelativePriority;
end

function BehaviorTreeComponent:RequestExecution(LastResult)

	if (LastResult ~= BehaviorTreeTypes.EBTNodeResult.Aborted and LastResult ~= BehaviorTreeTypes.EBTNodeResult.InProgress and self.InstanceStack[self.ActiveInstanceIdx]) then
		local ActiveInstance = self.InstanceStack[self.ActiveInstanceIdx];
		local ExecuteParent = (ActiveInstance.ActiveNode == nil) and ActiveInstance.RootNode or
			((ActiveInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.Composite) and ActiveInstance.ActiveNode or
			ActiveInstance.ActiveNode:GetParentNode());

		self:RequestExecution(ExecuteParent, #self.InstanceStack,
			ActiveInstance.ActiveNode and ActiveInstance.ActiveNode or ActiveInstance.RootNode, 1,
			LastResult);
	end
end

local function FindCommonParent(Instances, InNodeA, InstanceIdxA, InNodeB, InstanceIdxB, ref)

	ref.CommonInstanceIdx = (InstanceIdxA <= InstanceIdxB) and InstanceIdxA or InstanceIdxB;

	local NodeA = (ref.CommonInstanceIdx == InstanceIdxA) and InNodeA or Instances[ref.CommonInstanceIdx].ActiveNode:GetParentNode();
	local NodeB = (ref.CommonInstanceIdx == InstanceIdxB) and InNodeB or Instances[ref.CommonInstanceIdx].ActiveNode:GetParentNode();

	if (not NodeA and ref.CommonInstanceIdx ~= InstanceIdxA) then
		NodeA = Instances[ref.CommonInstanceIdx].RootNode;
	end
	if (not NodeB and ref.CommonInstanceIdx ~= InstanceIdxB) then
		NodeB = Instances[ref.CommonInstanceIdx].RootNode;
	end

	if (not NodeA or not NodeB) then
		return;
	end

	local NodeADepth = NodeA:GetTreeDepth();
	local NodeBDepth = NodeB:GetTreeDepth();

	while (NodeADepth > NodeBDepth) do
		NodeA = NodeA:GetParentNode();
		NodeADepth = NodeA:GetTreeDepth();
	end

	while (NodeBDepth > NodeADepth) do
		NodeB = NodeB:GetParentNode();
		NodeBDepth = NodeB:GetTreeDepth();
	end

	while (NodeA ~= NodeB) do
		NodeA = NodeA:GetParentNode();
		NodeB = NodeB:GetParentNode();
	end

	ref.CommonParentNode = NodeA;
end

function BehaviorTreeComponent:ScheduleExecutionUpdate()

	self:ScheduleNextTick(0.0);
	self.bRequestedFlowUpdate = true;
end

function BehaviorTreeComponent:RequestExecution(RequestedOn, InstanceIdx, RequestedBy, RequestedByChildIndex, ContinueWithResult)

	if not self.bIsRunning or not self.InstanceStack[self.ActiveInstanceIdx] then
		return;
	end

	local bOutOfNodesPending = self.PendingExecution:IsSet() and self.PendingExecution.bOutOfNodes;
	if (bOutOfNodesPending) then
		return;
	end

	local bSwitchToHigherPriority = (ContinueWithResult == BehaviorTreeTypes.EBTNodeResult.Aborted);
	local bAlreadyHasRequest = (self.ExecutionRequest.ExecuteNode ~= nil);

	local ExecutionIdx = BehaviorTreeTypes.FBTNodeIndex();
	ExecutionIdx.InstanceIndex = InstanceIdx;
	ExecutionIdx.ExecutionIndex = RequestedBy:GetExecutionIndex();
	local LastExecutionIndex = 0xffff;

	for _, Range in ipairs(self.PendingUnregisterAuxNodesRequests.Ranges) do
		if (Utils.array.find(Range, ExecutionIdx)) then
			return;
		end
	end

	if (bSwitchToHigherPriority and RequestedByChildIndex > 0) then
		ExecutionIdx.ExecutionIndex = RequestedOn:GetChildExecutionIndex(RequestedByChildIndex, BehaviorTreeTypes.EBTChildIndex.FirstNode);
		
		LastExecutionIndex = RequestedOn:GetChildExecutionIndex(RequestedByChildIndex + 1, BehaviorTreeTypes.EBTChildIndex.FirstNode);
	end

	local SearchEnd = BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, LastExecutionIndex);

	if (bAlreadyHasRequest and self.ExecutionRequest.SearchStart:TakesPriorityOver(ExecutionIdx)) then

		if (bSwitchToHigherPriority) then
			if (self.ExecutionRequest.SearchEnd:IsSet() and self.ExecutionRequest.SearchEnd:TakesPriorityOver(SearchEnd)) then
				self.ExecutionRequest.SearchEnd = SearchEnd;
			end
		else
			if (self.ExecutionRequest.SearchEnd:IsSet()) then
				self.ExecutionRequest.SearchEnd = BehaviorTreeTypes.FBTNodeIndex();
			end
		end

		return;
	end

	if (self.SearchData.bFilterOutRequestFromDeactivatedBranch or self.bWaitingForAbortingTasks) then
		if (self.SearchData.SearchRootNode ~= ExecutionIdx and self.SearchData.SearchRootNode:TakesPriorityOver(ExecutionIdx) and self.SearchData.DeactivatedBranchStart:IsSet()) then
			if (ExecutionIdx.InstanceIndex > self.SearchData.DeactivatedBranchStart.InstanceIndex) then
				return;
			elseif (ExecutionIdx.InstanceIndex == self.SearchData.DeactivatedBranchStart.InstanceIndex and
					ExecutionIdx.ExecutionIndex >= self.SearchData.DeactivatedBranchStart.ExecutionIndex and
					ExecutionIdx.ExecutionIndex < self.SearchData.DeactivatedBranchEnd.ExecutionIndex) then
				return;
			end
		end
	end

	if (bSwitchToHigherPriority) then
		local bShouldCheckDecorators = (RequestedByChildIndex > 0) and not self:IsExecutingBranch(RequestedBy, RequestedByChildIndex);
		local bCanExecute = not bShouldCheckDecorators or RequestedOn:DoDecoratorsAllowExecution(self, InstanceIdx, RequestedByChildIndex);
		if (not bCanExecute) then
			return;
		end

		local CurrentNode = self.ExecutionRequest.ExecuteNode;
		local CurrentInstanceIdx = self.ExecutionRequest.ExecuteInstanceIdx;
		if (self.ExecutionRequest.ExecuteNode == nil) then
			local ActiveInstance = self.InstanceStack[self.ActiveInstanceIdx];
			CurrentNode = (ActiveInstance.ActiveNode == nil) and ActiveInstance.RootNode or
				(ActiveInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.Composite) and ActiveInstance.ActiveNode or
				ActiveInstance.ActiveNode:GetParentNode();

			CurrentInstanceIdx = self.ActiveInstanceIdx;
		end

		if (self.ExecutionRequest.ExecuteNode ~= RequestedOn) then
			local CommonParent = nil;
			local CommonInstanceIdx = 0xffff;
			local ref = {}

			FindCommonParent(self.InstanceStack, RequestedOn, InstanceIdx, CurrentNode, CurrentInstanceIdx, ref, CommonParent, CommonInstanceIdx);
			CommonParent = ref.CommonParentNode
			CommonInstanceIdx = ref.CommonInstanceIdx
			
			local ItInstanceIdx = InstanceIdx;
			local It = RequestedOn
			while ( It and It ~= CommonParent) do
				local ParentNode = It:GetParentNode();
				local ChildIdx = BehaviorTreeTypes.INDEX_NONE;

				if (ParentNode == nil) then
					if (ItInstanceIdx > 1) then
						ItInstanceIdx = ItInstanceIdx - 1;
						local SubtreeTaskNode = self.InstanceStack[ItInstanceIdx].ActiveNode;
						ParentNode = SubtreeTaskNode:GetParentNode();
						ChildIdx = ParentNode:GetChildIndex(SubtreeTaskNode);
					else
						break;
					end
				else
					ChildIdx = ParentNode:GetChildIndex(It);
				end

				local bCanExecuteTest = ParentNode:DoDecoratorsAllowExecution(self, ItInstanceIdx, ChildIdx);
				if (not bCanExecuteTest) then
					return;
				end

				It = ParentNode;
			end

			self.ExecutionRequest.ExecuteNode = CommonParent;
			self.ExecutionRequest.ExecuteInstanceIdx = CommonInstanceIdx;
		end
	else
		local bShouldCheckDecorators = RequestedOn.Children[RequestedByChildIndex] and
			(#RequestedOn.Children[RequestedByChildIndex].DecoratorOps > 0) and
			instanceof(RequestedBy, BTDecorator)

		local bCanExecute = bShouldCheckDecorators and RequestedOn:DoDecoratorsAllowExecution(self, InstanceIdx, RequestedByChildIndex);
		if (bCanExecute) then
			return;
		end

		self.ExecutionRequest.ExecuteNode = RequestedOn;
		self.ExecutionRequest.ExecuteInstanceIdx = InstanceIdx;
	end

	if ((not bAlreadyHasRequest and bSwitchToHigherPriority) or 
		(self.ExecutionRequest.SearchEnd:IsSet() and self.ExecutionRequest.SearchEnd:TakesPriorityOver(SearchEnd))) then
		self.ExecutionRequest.SearchEnd = SearchEnd;
	end

	self.ExecutionRequest.SearchStart = ExecutionIdx;
	self.ExecutionRequest.ContinueWithResult = ContinueWithResult;
	self.ExecutionRequest.bTryNextChild = not bSwitchToHigherPriority;
	self.ExecutionRequest.bIsRestart = (RequestedBy ~= self:GetActiveNode());
	self.PendingExecution:Lock();
	
	if (self.SearchData.bSearchInProgress) then
		self.SearchData.bPostponeSearch = true;
	end

	local bIsActiveNodeAborting = #self.InstanceStack > 0 and self.InstanceStack[#self.InstanceStack].ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask;
	local bInvalidateCurrentSearch = self.bWaitingForAbortingTasks or bIsActiveNodeAborting;
	local bScheduleNewSearch = not self.bWaitingForAbortingTasks;

	if (bInvalidateCurrentSearch) then
        if (self.ExecutionRequest.SearchEnd:IsSet()) then
			self.ExecutionRequest.SearchEnd = BehaviorTreeTypes.FBTNodeIndex();
		end
		self:RollbackSearchChanges();
	end
	
	if (bScheduleNewSearch) then
		self:ScheduleExecutionUpdate();
	end
end

function BehaviorTreeComponent:ApplySearchUpdates(UpdateList, NewNodeExecutionIndex, bPostUpdate)
	bPostUpdate = bPostUpdate or false
	for Index = 1, #UpdateList do
		local UpdateInfo = UpdateList[Index];
		if not self.InstanceStack[UpdateInfo.InstanceIndex] then
			goto continue;
		end

		local UpdateInstance = self.InstanceStack[UpdateInfo.InstanceIndex];
		local ParallelTaskIdx = BehaviorTreeTypes.INDEX_NONE;
		local bIsComponentActive = false;

		if (UpdateInfo.AuxNode) then
			bIsComponentActive = UpdateInstance.GetActiveAuxNodes().Contains(UpdateInfo.AuxNode);
		elseif (UpdateInfo.TaskNode) then
			ParallelTaskIdx = UpdateInstance.GetParallelTasks().IndexOfByKey(UpdateInfo.TaskNode);
			bIsComponentActive = (ParallelTaskIdx ~= BehaviorTreeTypes.INDEX_NONE and UpdateInstance.GetParallelTasks()[ParallelTaskIdx].Status == BehaviorTreeTypes.EBTTaskStatus.Active);
		end

		local UpdateNode = UpdateInfo.AuxNode and UpdateInfo.AuxNode or UpdateInfo.TaskNode;

		if ((UpdateInfo.Mode ==  BehaviorTreeTypes.EBTNodeUpdateMode.Remove and not bIsComponentActive) or
			(UpdateInfo.Mode ==  BehaviorTreeTypes.EBTNodeUpdateMode.Add and (bIsComponentActive or UpdateNode:GetExecutionIndex() > NewNodeExecutionIndex)) or
			(UpdateInfo.bPostUpdate ~= bPostUpdate)) then
			goto continue;
		end

		if (UpdateInfo.AuxNode) then
			if (self.bLoopExecution and UpdateInfo.AuxNode:GetMyNode() == self.InstanceStack[0].RootNode and
				instanceof(UpdateInfo.AuxNode, BTService)) then

				if (UpdateInfo.Mode ==  BehaviorTreeTypes.EBTNodeUpdateMode.Remove or 
					Utils.array.find(self.InstanceStack[1]:GetActiveAuxNodes(), UpdateInfo.AuxNode)) then
					goto continue;
				end
			end

			local NodeMemory = UpdateNode:GetNodeMemory(UpdateInstance);
			if (UpdateInfo.Mode ==  BehaviorTreeTypes.EBTNodeUpdateMode.Remove) then
				UpdateInstance.RemoveFromActiveAuxNodes(UpdateInfo.AuxNode);
				UpdateInfo.AuxNode:WrappedOnCeaseRelevant(self, NodeMemory);
			else
				UpdateInstance.AddToActiveAuxNodes(UpdateInfo.AuxNode);
				UpdateInfo.AuxNode:WrappedOnBecomeRelevant(self, NodeMemory);
			end
		elseif (UpdateInfo.TaskNode) then
			if (UpdateInfo.Mode ==  BehaviorTreeTypes.EBTNodeUpdateMode.Remove) then
				self:UnregisterMessageObserversFrom(UpdateInfo.TaskNode);

				local NodeMemory = UpdateNode:GetNodeMemory(UpdateInstance);
				local NodeResult = UpdateInfo.TaskNode:WrappedAbortTask(self, NodeMemory);

				local bStillValid = self.InstanceStack[UpdateInfo.InstanceIndex] and
					self.InstanceStack[UpdateInfo.InstanceIndex].GetParallelTasks()[ParallelTaskIdx] and
					self.InstanceStack[UpdateInfo.InstanceIndex].GetParallelTasks()[ParallelTaskIdx] == UpdateInfo.TaskNode;
				
				if (bStillValid) then
					if (NodeResult == BehaviorTreeTypes.EBTNodeResult.InProgress) then
						UpdateInstance.MarkParallelTaskAsAbortingAt(ParallelTaskIdx);
						self.bWaitingForAbortingTasks = true;
					end

					self:OnTaskFinished(UpdateInfo.TaskNode, NodeResult);
				end
			else
				UpdateInstance.AddToParallelTasks(BehaviorTreeTypes.FBehaviorTreeParallelTask(UpdateInfo.TaskNode, BehaviorTreeTypes.EBTTaskStatus.Active));
			end
		end

		::continue::
	end
end

function BehaviorTreeComponent:ApplySearchData(NewActiveNode)

	self.SearchData.RollbackInstanceIdx = BehaviorTreeTypes.INDEX_NONE;
	self.SearchData.RollbackDeactivatedBranchStart = BehaviorTreeTypes.FBTNodeIndex();
	self.SearchData.RollbackDeactivatedBranchEnd = BehaviorTreeTypes.FBTNodeIndex();

	for Idx = 1, #self.SearchData.PendingNotifies do
		local NotifyInfo = self.SearchData.PendingNotifies[Idx];
		if self.InstanceStack[NotifyInfo.InstanceIndex] then
			if self.InstanceStack[NotifyInfo.InstanceIndex].DeactivationNotify then
				self.InstanceStack[NotifyInfo.InstanceIndex].DeactivationNotify(self, NotifyInfo.NodeResult)
			end
		end	
	end

	local NewNodeExecutionIndex = NewActiveNode and NewActiveNode:GetExecutionIndex() or 0;

	self.SearchData.bFilterOutRequestFromDeactivatedBranch = true;

	self:ApplySearchUpdates(self.SearchData.PendingUpdates, NewNodeExecutionIndex);
	self:ApplySearchUpdates(self.SearchData.PendingUpdates, NewNodeExecutionIndex, true);
	
	self.SearchData.bFilterOutRequestFromDeactivatedBranch = false;

	local CurrentFrameDeltaSeconds = 0.03

	for Idx = 1, #self.SearchData.PendingUpdates do
		local UpdateInfo = self.SearchData.PendingUpdates[Idx];
		if UpdateInfo.Mode ==  BehaviorTreeTypes.EBTNodeUpdateMode.Add and UpdateInfo.AuxNode and self.InstanceStack[UpdateInfo.InstanceIndex] then
			local InstanceInfo = self.InstanceStack[UpdateInfo.InstanceIndex];
			local NodeMemory = UpdateInfo.AuxNode:GetNodeMemory(InstanceInfo);


			local NextNeededDeltaTime = 0.0;
			UpdateInfo.AuxNode:WrappedTickNode(self, NodeMemory, CurrentFrameDeltaSeconds, NextNeededDeltaTime);
		end
	end

	self.SearchData.PendingUpdates = {};
	self.SearchData.PendingNotifies = {};
	self.SearchData.DeactivatedBranchStart = BehaviorTreeTypes.FBTNodeIndex();
	self.SearchData.DeactivatedBranchEnd = BehaviorTreeTypes.FBTNodeIndex();
end

function BehaviorTreeComponent:ApplyDiscardedSearch()
	self.SearchData.PendingUpdates = {};
	self.SearchData.PendingNotifies = {};
end

function BehaviorTreeComponent:TickComponent(DeltaTime, TickType, selfTickFunction)

	if not self:IsComponentTickEnabled() then
		return
	end

	self.NextTickDeltaTime = self.NextTickDeltaTime - DeltaTime;
	if (self.NextTickDeltaTime > 0.0) then
		self.AccumulatedTickDeltaTime = self.AccumulatedTickDeltaTime + DeltaTime;
		self:ScheduleNextTick(self.NextTickDeltaTime);
		return;
	end

	DeltaTime = DeltaTime + self.AccumulatedTickDeltaTime;
	self.AccumulatedTickDeltaTime = 0.0;

	local bWasTickedOnce = self.bTickedOnce;
	self.bTickedOnce = true;

	local bDoneSomething = #self.MessagesToProcess > 0;
	BrainComponent.TickComponent(self, DeltaTime);


	local NextNeededDeltaTime = AITypes.FLT_MAX;

	bDoneSomething = bDoneSomething or self:ProcessPendingUnregister();
	local ref = { NextNeededDeltaTime = NextNeededDeltaTime }

	for InstanceIndex = 1, #self.InstanceStack do
		local InstanceInfo = self.InstanceStack[InstanceIndex];
		InstanceInfo:ExecuteOnEachAuxNode(function (AuxNode)
				local NodeMemory = AuxNode:GetNodeMemory(InstanceInfo);
				bDoneSomething = AuxNode:WrappedTickNode(self, NodeMemory, DeltaTime, ref) or bDoneSomething;
			end);
	end

	local bActiveAuxiliaryNodeDTDirty = false;
	if (self.bRequestedFlowUpdate) then
		self:ProcessExecutionRequest();
		bDoneSomething = true;

        bActiveAuxiliaryNodeDTDirty = true;
		NextNeededDeltaTime = AITypes.FLT_MAX;
	end

	if (#self.InstanceStack > 0 and self.bIsRunning and not self.bIsPaused) then
		if true then
		
			local ScopedLock = statics.FScopedBehaviorTreeLock(self, FScopedBehaviorTreeLock.LockTick);

			for InstanceIndex = 1, #self.InstanceStack do
				local InstanceInfo = self.InstanceStack[InstanceIndex];
				InstanceInfo:ExecuteOnEachParallelTask(function (ParallelTaskInfo, Index)
						local ParallelTask = ParallelTaskInfo.TaskNode;
						local NodeMemory = ParallelTask:GetNodeMemory(InstanceInfo);
						bDoneSomething = ParallelTask:WrappedTickTask(self, NodeMemory, DeltaTime, ref) or bDoneSomething;
					end);
			end

			if self.InstanceStack[self.ActiveInstanceIdx] then
				local ActiveInstance = self.InstanceStack[self.ActiveInstanceIdx];
				if (ActiveInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.ActiveTask or 
					ActiveInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask) then
					local ActiveTask = ActiveInstance.ActiveNode;
					local NodeMemory = ActiveTask:GetNodeMemory(ActiveInstance);
					bDoneSomething = ActiveTask:WrappedTickTask(self, NodeMemory, DeltaTime, ref) or bDoneSomething;
				end
			end

			if self.InstanceStack[self.ActiveInstanceIdx + 1] then
				local LastInstance = self.InstanceStack[#self.InstanceStack];
				if (LastInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask) then
					local ActiveTask = LastInstance.ActiveNode;
					local NodeMemory = ActiveTask:GetNodeMemory(LastInstance);
					bDoneSomething = ActiveTask:WrappedTickTask(self, NodeMemory, DeltaTime, ref) or bDoneSomething;
				end
			end

			ScopedLock:dtor()
		end

		if (self.bDeferredStopTree) then
			self:StopTree(BehaviorTreeTypes.EBTStopMode.Safe);
			bDoneSomething = true;
		end
	end

	NextNeededDeltaTime = ref.NextNeededDeltaTime

	if (bActiveAuxiliaryNodeDTDirty) then
		for InstanceIndex = 1, #self.InstanceStack do
			if NextNeededDeltaTime <= 0.0 then
				break
			end

			local InstanceInfo = self.InstanceStack[InstanceIndex];
			for _, AuxNode in ipairs(InstanceInfo:GetActiveAuxNodes()) do
				local NodeMemory = AuxNode:GetNodeMemory(InstanceInfo);
				local NextNodeNeededDeltaTime = AuxNode:GetNextNeededDeltaTime(self, NodeMemory);
				if (NextNeededDeltaTime > NextNodeNeededDeltaTime) then
					NextNeededDeltaTime = NextNodeNeededDeltaTime;
				end
			end
		end
	end

	if (bWasTickedOnce and not bDoneSomething) then
	end

	self:ScheduleNextTick(NextNeededDeltaTime);
end

function BehaviorTreeComponent:ScheduleNextTick(NextNeededDeltaTime)

	self.NextTickDeltaTime = NextNeededDeltaTime;
	if (self.bRequestedFlowUpdate) then
		self.NextTickDeltaTime = 0.0;
	end

	if (self.NextTickDeltaTime == AITypes.FLT_MAX) then
		if (self:IsComponentTickEnabled()) then
			self:SetComponentTickEnabled(false);
		end
	else
		if (not self:IsComponentTickEnabled()) then
			self:SetComponentTickEnabled(true);
		end

	end
end

function BehaviorTreeComponent:ProcessExecutionRequest()

	self.bRequestedFlowUpdate = false;
	if not self.InstanceStack[self.ActiveInstanceIdx] then
		return;
	end

	if (self.bIsPaused) then
		return;
	end

	if (self.bWaitingForAbortingTasks) then
		return;
	end

	if (self.PendingExecution:IsSet()) then
		self:ProcessPendingExecution();
		return;
	end

	local bIsSearchValid = true;
	self.SearchData.RollbackInstanceIdx = self.ActiveInstanceIdx;
	self.SearchData.RollbackDeactivatedBranchStart = self.SearchData.DeactivatedBranchStart;
	self.SearchData.RollbackDeactivatedBranchEnd = self.SearchData.DeactivatedBranchEnd;

	local NodeResult = self.ExecutionRequest.ContinueWithResult;
	local NextTask = nil;


	if true then
		self:CopyInstanceMemoryToPersistent();

		if (self.InstanceStack[self.ActiveInstanceIdx].ActiveNode ~= self.ExecutionRequest.ExecuteNode) then
			local LastDeactivatedChildIndex = BehaviorTreeTypes.INDEX_NONE;
			local ref = {LastDeactivatedChildIndex = LastDeactivatedChildIndex}
			local bDeactivated = self:DeactivateUpTo(self.ExecutionRequest.ExecuteNode, self.ExecutionRequest.ExecuteInstanceIdx, NodeResult, LastDeactivatedChildIndex);
			LastDeactivatedChildIndex = ref.LastDeactivatedChildIndex
			if (not bDeactivated) then

				self.SearchData.PendingUpdates = {};
				return;
			elseif (LastDeactivatedChildIndex ~= BehaviorTreeTypes.INDEX_NONE) then
				local NewDeactivatedBranchStart = BehaviorTreeTypes.FBTNodeIndex(self.ExecutionRequest.ExecuteInstanceIdx, self.ExecutionRequest.ExecuteNode:GetChildExecutionIndex(LastDeactivatedChildIndex, BehaviorTreeTypes.EBTChildIndex.FirstNode));
				local NewDeactivatedBranchEnd = BehaviorTreeTypes.FBTNodeIndex(self.ExecutionRequest.ExecuteInstanceIdx, self.ExecutionRequest.ExecuteNode:GetChildExecutionIndex(LastDeactivatedChildIndex + 1, BehaviorTreeTypes.EBTChildIndex.FirstNode));

				self.SearchData.DeactivatedBranchStart = NewDeactivatedBranchStart;
				self.SearchData.DeactivatedBranchEnd = NewDeactivatedBranchEnd;
			end
		end

		local ActiveInstance = self.InstanceStack[self.ActiveInstanceIdx];
		local TestNode = self.ExecutionRequest.ExecuteNode;
		self.SearchData:AssignSearchId();
		self.SearchData.bPostponeSearch = false;
		self.SearchData.bSearchInProgress = true;
		self.SearchData.SearchRootNode = BehaviorTreeTypes.FBTNodeIndex(self.ExecutionRequest.ExecuteInstanceIdx, self.ExecutionRequest.ExecuteNode:GetExecutionIndex());

		if (ActiveInstance.ActiveNode == nil) then
			ActiveInstance.ActiveNode = self.InstanceStack[self.ActiveInstanceIdx].RootNode;
			ActiveInstance.RootNode:OnNodeActivation(self.SearchData);
		end

		if (not self.ExecutionRequest.bTryNextChild) then
			local DeactivateIdx = BehaviorTreeTypes.FBTNodeIndex(self.ExecutionRequest.SearchStart.InstanceIndex, self.ExecutionRequest.SearchStart.ExecutionIndex - 1);
			self:UnregisterAuxNodesUpTo(self.ExecutionRequest.SearchStart.ExecutionIndex and DeactivateIdx or self.ExecutionRequest.SearchStart);

			self.ExecutionRequest.ExecuteNode:OnNodeRestart(self.SearchData);

			self.SearchData.SearchStart = self.ExecutionRequest.SearchStart;
			self.SearchData.SearchEnd = self.ExecutionRequest.SearchEnd;

		else
			if (self.ExecutionRequest.ContinueWithResult == BehaviorTreeTypes.EBTNodeResult.Failed) then
				self:UnregisterAuxNodesUpTo(self.ExecutionRequest.SearchStart);
			end

			self.SearchData.SearchStart = BehaviorTreeTypes.FBTNodeIndex();
			self.SearchData.SearchEnd = BehaviorTreeTypes.FBTNodeIndex();
		end


		while (TestNode and NextTask == nil) do
			local ChildBranchIdx = TestNode:FindChildToExecute(self.SearchData, NodeResult);
			local StoreNode = TestNode;

			if (self.SearchData.bPostponeSearch) then
				TestNode = nil;
				bIsSearchValid = false;
			elseif (ChildBranchIdx == BehaviorTreeTypes.BTSpecialChild.ReturnToParent) then
				local ChildNode = TestNode;
				TestNode = TestNode:GetParentNode();

				if (TestNode == nil) then
					ChildNode:OnNodeDeactivation(self.SearchData, NodeResult);

					if (self.ActiveInstanceIdx > 0) then

						self.InstanceStack[self.ActiveInstanceIdx]:DeactivateNodes(self.SearchData, self.ActiveInstanceIdx);
						self.SearchData.PendingNotifies.Add(BehaviorTreeTypes.FBehaviorTreeSearchUpdateNotify(self.ActiveInstanceIdx, NodeResult));

						self.ActiveInstanceIdx = self.ActiveInstanceIdx - 1;

						TestNode = self.InstanceStack[self.ActiveInstanceIdx].ActiveNode:GetParentNode();
					end
				end

				if (TestNode) then
					TestNode:OnChildDeactivation(self.SearchData, ChildNode, NodeResult);
				end
			elseif TestNode.Children[ChildBranchIdx] then
				NextTask = TestNode.Children[ChildBranchIdx].ChildTask;

				TestNode = TestNode.Children[ChildBranchIdx].ChildComposite;
			end

		end

		if (NextTask) then
			local NextTaskIdx = BehaviorTreeTypes.FBTNodeIndex(self.ActiveInstanceIdx, NextTask:GetExecutionIndex());
			bIsSearchValid = NextTaskIdx:TakesPriorityOver(self.ExecutionRequest.SearchEnd);
			
			if (bIsSearchValid and NextTask:ShouldIgnoreRestartSelf()) then
				local bIsTaskRunning = self.InstanceStack[self.ActiveInstanceIdx]:HasActiveNode(NextTaskIdx.ExecutionIndex);
				if (bIsTaskRunning) then
					bIsSearchValid = false;
				end
			end
		end


		if (not bIsSearchValid or self.SearchData.bPostponeSearch) then
			self:RollbackSearchChanges();
		end

		self.SearchData.bSearchInProgress = false;
	end

	if (not self.SearchData.bPostponeSearch) then
		self.ExecutionRequest = statics.FBTNodeExecutionInfo();

		self.PendingExecution.Unlock();

		if (bIsSearchValid) then
			if (self.InstanceStack[#self.InstanceStack].ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.ActiveTask) then
				self.SearchData.bFilterOutRequestFromDeactivatedBranch = true;

				self:AbortCurrentTask();

				self.SearchData.bFilterOutRequestFromDeactivatedBranch = false;
			end

			if (not self.PendingExecution:IsLocked()) then
				self.PendingExecution.NextTask = NextTask;
				self.PendingExecution.bOutOfNodes = (NextTask == nil);
			end
		end

		self:ProcessPendingExecution();
	else
		self:ScheduleExecutionUpdate();
	end
end

function BehaviorTreeComponent:ProcessPendingExecution()

	if (self.bWaitingForAbortingTasks or not self.PendingExecution:IsSet()) then
		return;
	end

	local SavedInfo = self.PendingExecution;
	self.PendingExecution = statics.FBTPendingExecutionInfo();

	local NextTaskIdx = SavedInfo.NextTask and BehaviorTreeTypes.FBTNodeIndex(self.ActiveInstanceIdx, SavedInfo.NextTask:GetExecutionIndex()) or BehaviorTreeTypes.FBTNodeIndex(0, 0);
	self:UnregisterAuxNodesUpTo(NextTaskIdx);

	self:ApplySearchData(SavedInfo.NextTask);

	if (#self.InstanceStack > (self.ActiveInstanceIdx + 1)) then
		for InstanceIndex = self.ActiveInstanceIdx + 1, #self.InstanceStack do
			self.InstanceStack[InstanceIndex]:Cleanup(self, BehaviorTreeTypes.EBTMemoryClear.StoreSubtree);
		end

		Utils.array.resize(self.InstanceStack, self.ActiveInstanceIdx + 1)
	end

	if SavedInfo.NextTask and self.InstanceStack[self.ActiveInstanceIdx] then
		self:ExecuteTask(SavedInfo.NextTask);
	else
		self:OnTreeFinished();
	end
end

function BehaviorTreeComponent:RollbackSearchChanges()

	if (self.SearchData.RollbackInstanceIdx > 0) then
		self.ActiveInstanceIdx = self.SearchData.RollbackInstanceIdx;
		self.SearchData.DeactivatedBranchStart = self.SearchData.RollbackDeactivatedBranchStart;
		self.SearchData.DeactivatedBranchEnd = self.SearchData.RollbackDeactivatedBranchEnd;

		self.SearchData.RollbackInstanceIdx = BehaviorTreeTypes.INDEX_NONE;
		self.SearchData.RollbackDeactivatedBranchStart = BehaviorTreeTypes.FBTNodeIndex();
		self.SearchData.RollbackDeactivatedBranchEnd = BehaviorTreeTypes.FBTNodeIndex();

		if (self.SearchData.bPreserveActiveNodeMemoryOnRollback) then
			for Idx = 1, #self.InstanceStack do
				local InstanceData = self.InstanceStack[Idx];
				local InstanceInfo = self.KnownInstances[InstanceData.InstanceIdIndex];

				local NodeMemorySize = InstanceData.ActiveNode and InstanceData.ActiveNode:GetInstanceMemorySize() or 0;
				if (NodeMemorySize) then
					local NodeMemory = InstanceData.ActiveNode:GetNodeMemory(InstanceData);
					local DestMemory = InstanceInfo.InstanceMemory[InstanceData.ActiveNode:GetMemoryOffset()];

					Utils.table.deepcopy(NodeMemory, DestMemory)
				end

				InstanceData:SetInstanceMemory(InstanceInfo.InstanceMemory);
			end
		else
			self:CopyInstanceMemoryFromPersistent();
		end

		self:ApplyDiscardedSearch();
	end
end

function BehaviorTreeComponent:DeactivateUpTo(Node, NodeInstanceIdx, ref)

	local DeactivatedChild = self.InstanceStack[self.ActiveInstanceIdx].ActiveNode;
	local bDeactivateRoot = true;

	if (DeactivatedChild == nil and self.ActiveInstanceIdx > NodeInstanceIdx) then
		DeactivatedChild = self.InstanceStack[self.ActiveInstanceIdx].RootNode;
		bDeactivateRoot = false;
	end

	while (DeactivatedChild) do
		local NotifyParent = DeactivatedChild:GetParentNode();
		if (NotifyParent) then
			ref.OutLastDeactivatedChildIndex = NotifyParent:GetChildIndex(self.SearchData, DeactivatedChild);
			NotifyParent:OnChildDeactivation(self.SearchData, ref.OutLastDeactivatedChildIndex, ref);

			DeactivatedChild = NotifyParent;
		else
			if (bDeactivateRoot) then
				self.InstanceStack[self.ActiveInstanceIdx].RootNode:OnNodeDeactivation(self.SearchData, ref);
			end

			bDeactivateRoot = true;

			if (self.ActiveInstanceIdx == 1) then
				self:RestartTree();
				return false;
			end

			self.SearchData.PendingNotifies.Add(BehaviorTreeTypes.FBehaviorTreeSearchUpdateNotify(self.ActiveInstanceIdx, ref.NodeResult));

			self.ActiveInstanceIdx = self.ActiveInstanceIdx - 1;
			DeactivatedChild = self.InstanceStack[self.ActiveInstanceIdx].ActiveNode;
		end

		if (DeactivatedChild == Node) then
			break;
		end
	end

	return true;
end

function BehaviorTreeComponent:UnregisterAuxNodesUpTo(Index)

	for InstanceIndex = 1, #self.InstanceStack do
		local InstanceInfo = self.InstanceStack[InstanceIndex];
		for _, AuxNode in ipairs(InstanceInfo:GetActiveAuxNodes()) do
			local AuxIdx = BehaviorTreeTypes.FBTNodeIndex(InstanceIndex, AuxNode:GetExecutionIndex());
			if (Index:TakesPriorityOver(AuxIdx)) then
				self.SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(AuxNode, InstanceIndex, BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
			end
		end
	end
end

function BehaviorTreeComponent:UnregisterAuxNodesInRange(FromIndex, ToIndex)

	for InstanceIndex =1, #self.InstanceStack do
		local InstanceInfo = self.InstanceStack[InstanceIndex];
		for _, AuxNode in ipairas(InstanceInfo.GetActiveAuxNodes()) do
			local AuxIdx = BehaviorTreeTypes.FBTNodeIndex(InstanceIndex, AuxNode:GetExecutionIndex());
			if (FromIndex:TakesPriorityOver(AuxIdx) and AuxIdx:TakesPriorityOver(ToIndex)) then
				self.SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(AuxNode, InstanceIndex, BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
			end
		end
	end
end

function BehaviorTreeComponent:UnregisterAuxNodesInBranch(Node, bApplyImmediately)

	local InstanceIdx = self:FindInstanceContainingNode(Node);
	if (InstanceIdx ~= BehaviorTreeTypes.INDEX_NONE) then

		local UpdateListCopy = {};
		if (bApplyImmediately) then
			UpdateListCopy = self.SearchData.PendingUpdates;
			self.SearchData.PendingUpdates = {};
		end

		local FromIndex = BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, Node:GetExecutionIndex());
		local ToIndex = BehaviorTreeTypes.FBTNodeIndex(InstanceIdx, Node:GetLastExecutionIndex());
		self:UnregisterAuxNodesInRange(FromIndex, ToIndex);

		if (bApplyImmediately) then
			self:ApplySearchUpdates(self.SearchData.PendingUpdates, 1);
			self.SearchData.PendingUpdates = UpdateListCopy;
		end
	end
end

function BehaviorTreeComponent:ProcessPendingUnregister()

	if (#self.PendingUnregisterAuxNodesRequests.Ranges == 0) then
		return false;
	end

	local tmp = self.SearchData.PendingUpdates
	self.SearchData.PendingUpdates = {}

	for _, Range in ipairs(self.PendingUnregisterAuxNodesRequests.Ranges) do
		self:UnregisterAuxNodesInRange(Range.FromIndex, Range.ToIndex);
	end
	self.PendingUnregisterAuxNodesRequests = {};

	self:ApplySearchUpdates(self.SearchData.PendingUpdates, 1);

	self.SearchData.PendingUpdates = tmp
	return true;
end

function BehaviorTreeComponent:ExecuteTask(TaskNode)

	if not self.InstanceStack[self.ActiveInstanceIdx] then
		return;
	end

	local ActiveInstance = self.InstanceStack[self.ActiveInstanceIdx];

	for ServiceIndex = 1, #TaskNode.Services do
		local ServiceNode = TaskNode.Services[ServiceIndex];
		local NodeMemory = ServiceNode:GetNodeMemory(ActiveInstance);

		ActiveInstance:AddToActiveAuxNodes(ServiceNode);

		ServiceNode:WrappedOnBecomeRelevant(self, NodeMemory);
	end

	ActiveInstance.ActiveNode = TaskNode;
	ActiveInstance.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.ActiveTask;

	local InstanceIdx = self.ActiveInstanceIdx;

	local TaskResult;
	if true then
		local NodeMemory = (TaskNode:GetNodeMemory(ActiveInstance));
		TaskResult = TaskNode:WrappedExecuteTask(self, NodeMemory);
	end

	local ActiveNodeAfterExecution = self:GetActiveNode();
	if (ActiveNodeAfterExecution == TaskNode) then
		self:OnTaskFinished(TaskNode, TaskResult);
	end
end

function BehaviorTreeComponent:AbortCurrentTask()

	local CurrentInstanceIdx = #self.InstanceStack;
	local CurrentInstance = self.InstanceStack[CurrentInstanceIdx];
	CurrentInstance.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.AbortingTask;

	local CurrentTask = CurrentInstance.ActiveNode;

	self:UnregisterMessageObserversFrom(CurrentTask);

	self.SearchData.bPreserveActiveNodeMemoryOnRollback = true;

	local NodeMemory = (CurrentTask:GetNodeMemory(CurrentInstance));
	local TaskResult = CurrentTask:WrappedAbortTask(self, NodeMemory);

	if (CurrentInstance.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask and
		CurrentInstanceIdx == #self.InstanceStack) then
		self:OnTaskFinished(CurrentTask, TaskResult);
	end
end

function BehaviorTreeComponent:RegisterMessageObserver(TaskNode, MessageType)

	if (TaskNode) then
		local NodeIdx = BehaviorTreeTypes.FBTNodeIndex();
		NodeIdx.ExecutionIndex = TaskNode:GetExecutionIndex();
		NodeIdx.InstanceIndex = #self.InstanceStack;

		for k, v in pairs(self.TaskMessageObservers) do
			if k == NodeIdx then
				table.insert(v, BrainComponent.FAIMessageObserver(self, MessageType, 
					function(OwnerComp, InMessageType) TaskNode:ReceivedMessage(OwnerComp, InMessageType) end))
				return
			end
		end

		self.TaskMessageObservers[NodeIdx] = {}
		table.insert(self.TaskMessageObservers[NodeIdx], BrainComponent.FAIMessageObserver(self, MessageType, 
					function(OwnerComp, InMessageType) TaskNode:ReceivedMessage(OwnerComp, InMessageType) end))
	end
end

function BehaviorTreeComponent:UnregisterMessageObserversFrom(TaskNodeOrIdx)
	local TaskNode = instanceof(TaskNodeOrIdx, BTTaskNode) and TaskNodeOrIdx or nil

	if (TaskNode and #self.InstanceStack > 0) then
		local ActiveInstance = self.InstanceStack[#self.InstanceStack]

		local NodeIdx = BehaviorTreeTypes.FBTNodeIndex();
		NodeIdx.ExecutionIndex = TaskNode:GetExecutionIndex();
		NodeIdx.InstanceIndex = self:FindInstanceContainingNode(TaskNode);
		
		self:UnregisterMessageObserversFrom(NodeIdx);
	else
		local NodeIdx = TaskNodeOrIdx
		for k, v in pairs(self.TaskMessageObservers) do
			if k == NodeIdx then
				for _, ob in ipairs(v) do
					ob:dtor()
				end

				self.TaskMessageObservers[k] = nil
				return
			end
		end
	end
end

function BehaviorTreeComponent:RegisterParallelTask(TaskNode)

	if self.InstanceStack[self.ActiveInstanceIdx] then
		local InstanceInfo = self.InstanceStack[self.ActiveInstanceIdx];
		InstanceInfo:AddToParallelTasks(BehaviorTreeTypes.FBehaviorTreeParallelTask(TaskNode, BehaviorTreeTypes.EBTTaskStatus.Active));

		if (InstanceInfo.ActiveNode == TaskNode) then
			InstanceInfo.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.InactiveTask;
		end
	end
end

function BehaviorTreeComponent:UnregisterParallelTask(TaskNode, InstanceIdx)

	local bShouldUpdate = false;
	if self.InstanceStack[InstanceIdx] then
		local InstanceInfo = self.InstanceStack[InstanceIdx];
		for TaskIndex = #InstanceInfo:GetParallelTasks(), 1 do
			if (InstanceInfo:GetParallelTasks()[TaskIndex].TaskNode == TaskNode) then

				InstanceInfo:RemoveParallelTaskAt(TaskIndex);
				bShouldUpdate = true;
				break;
			end
		end
	end

	if (bShouldUpdate) then
		self:UpdateAbortingTasks();
	end
end

function BehaviorTreeComponent:UpdateAbortingTasks()

	self.bWaitingForAbortingTasks = #self.InstanceStack > 0 and (self.InstanceStack[#self.InstanceStack].ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.AbortingTask) or false;

	for InstanceIndex = 1, #self.InstanceStack do
		if self.bWaitingForAbortingTasks then
			break
		end

		local InstanceInfo = self.InstanceStack[InstanceIndex];
		for _, ParallelInfo in ipairs(InstanceInfo:GetParallelTasks()) do
			if (ParallelInfo.Status == BehaviorTreeTypes.EBTTaskStatus.Aborting) then
				self.bWaitingForAbortingTasks = true;
				break;
			end
		end
	end
end

function BehaviorTreeComponent:PushInstance(TreeAsset)

	if (TreeAsset.BlackboardAsset and self.BlackboardComp and not self.BlackboardComp:IsCompatibleWith(TreeAsset.BlackboardAsset)) then
		return false;
	end

	local BTManager = BehaviorTreeManager
	if (BTManager == nil) then
		return false;
	end

	local ActiveNode = self:GetActiveNode();
	local ActiveParent = ActiveNode and ActiveNode:GetParentNode() or nil;
	if (ActiveParent) then
		local ParentMemory = self:GetNodeMemory(ActiveParent, #self.InstanceStack);
		local ChildIdx = ActiveNode and ActiveParent:GetChildIndex(ActiveNode) or BehaviorTreeTypes.INDEX_NONE;

		local bIsAllowed = ActiveParent:CanPushSubtree(self, ParentMemory, ChildIdx);
		if (not bIsAllowed) then
			return false;
		end
	end

	local RootNode, InstanceMemorySize = BTManager:LoadTree(TreeAsset);
	if (RootNode) then
		local NewInstance = BehaviorTreeTypes.FBehaviorTreeInstance();
		NewInstance.InstanceIdIndex = self:UpdateInstanceId(TreeAsset, ActiveNode, #self.InstanceStack);
		NewInstance.RootNode = RootNode;
		NewInstance.ActiveNode = nil;
		NewInstance.ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.Composite;

		local InstanceInfo = self.KnownInstances[NewInstance.InstanceIdIndex];
		local NodeInstanceIndex = InstanceInfo.FirstNodeInstance;
		local bFirstTime = (#InstanceInfo.InstanceMemory ~= InstanceMemorySize);
		if (bFirstTime) then
			Utils.array.resize(InstanceInfo.InstanceMemory, InstanceMemorySize, {})
			InstanceInfo.InstanceMemory.AddZeroed(InstanceMemorySize);
			InstanceInfo.RootNode = RootNode;
		end

		NewInstance:SetInstanceMemory(InstanceInfo.InstanceMemory);
		NewInstance:Initialize(self, RootNode, NodeInstanceIndex, bFirstTime and BehaviorTreeTypes.EBTMemoryInit.Initialize or BehaviorTreeTypes.EBTMemoryInit.RestoreSubtree);

		table.insert(self.InstanceStack, NewInstance)
		self.ActiveInstanceIdx = #self.InstanceStack

		for ServiceIndex = 1, #RootNode.Services do
			local ServiceNode = RootNode.Services[ServiceIndex];
			local NodeMemory = ServiceNode:GetNodeMemory(self.InstanceStack[self.ActiveInstanceIdx]);

			ServiceNode:NotifyParentActivation(self.SearchData);

			self.InstanceStack[self.ActiveInstanceIdx]:AddToActiveAuxNodes(ServiceNode);
			ServiceNode:WrappedOnBecomeRelevant(self, NodeMemory);
		end

		self:RequestExecution(RootNode, self.ActiveInstanceIdx, RootNode, 1, BehaviorTreeTypes.EBTNodeResult.InProgress);
		return true;
	end

	return false;
end

function BehaviorTreeComponent:UpdateInstanceId(TreeAsset, OriginNode, OriginInstanceIdx)

	local InstanceId = BehaviorTreeTypes.FBehaviorTreeInstanceId();
	InstanceId.TreeAsset = TreeAsset;

	if true then
		local ExecutionIndex = OriginNode and OriginNode:GetExecutionIndex() or 0xffff;
		table.insert(InstanceId.Path, ExecutionIndex)
	end

	for InstanceIndex = OriginInstanceIdx, 1 do
		local ExecutionIndex = self.InstanceStack[InstanceIndex].ActiveNode and self.InstanceStack[InstanceIndex].ActiveNode:GetExecutionIndex() or 0xffff;
		table.insert(InstanceId.Path, ExecutionIndex)
	end

	for InstanceIndex = 1, #self.KnownInstances do
		if (self.KnownInstances[InstanceIndex] == InstanceId) then
			return InstanceIndex;
		end
	end

	InstanceId.FirstNodeInstance = #self.NodeInstances;
	table.insert(self.KnownInstances, InstanceId)

	return #self.KnownInstances;
end

function BehaviorTreeComponent:FindInstanceContainingNode(Node)

	local InstanceIdx = BehaviorTreeTypes.INDEX_NONE;

	local TemplateNode = self:FindTemplateNode(Node);
	if (TemplateNode and #self.InstanceStack > 0) then
		if (self.InstanceStack[self.ActiveInstanceIdx].ActiveNode ~= TemplateNode) then
			local RootNode = TemplateNode;
			while (RootNode:GetParentNode()) do
				RootNode = RootNode:GetParentNode();
			end

			for InstanceIndex = 1, #self.InstanceStack do
				if (self.InstanceStack[InstanceIndex].RootNode == RootNode) then
					InstanceIdx = InstanceIndex;
					break;
				end
			end
		else
			InstanceIdx = self.ActiveInstanceIdx;
		end
	end

	return InstanceIdx;
end

function BehaviorTreeComponent:FindTemplateNode( Node)

	if (Node == nil or not Node:IsInstanced() or Node:GetParentNode() == nil) then
		return Node;
	end

	local ParentNode = Node:GetParentNode();
	for ChildIndex = 1, #ParentNode.Children do
		local ChildInfo = ParentNode.Children[ChildIndex];

		if (ChildInfo.ChildTask) then
			if (ChildInfo.ChildTask:GetExecutionIndex() == Node:GetExecutionIndex()) then
				return ChildInfo.ChildTask;
			end

			for ServiceIndex = 1, #ChildInfo.ChildTask.Services do
				if (ChildInfo.ChildTask.Services[ServiceIndex]:GetExecutionIndex() == Node:GetExecutionIndex()) then
					return ChildInfo.ChildTask.Services[ServiceIndex];
				end
			end
		end

		for DecoratorIndex = 1, #ChildInfo.Decorators do
			if (ChildInfo.Decorators[DecoratorIndex]:GetExecutionIndex() == Node:GetExecutionIndex()) then
				return ChildInfo.Decorators[DecoratorIndex];
			end
		end
	end

	for ServiceIndex = 1, #ParentNode.Services do
		if (ParentNode.Services[ServiceIndex]:GetExecutionIndex() == Node:GetExecutionIndex()) then
			return ParentNode.Services[ServiceIndex];
		end
	end

	return nil;
end

function BehaviorTreeComponent:GetNodeMemory(Node, InstanceIdx)
	return self.InstanceStack[InstanceIdx] and Node:GetNodeMemory(self.InstanceStack[InstanceIdx]) or nil;
end

function BehaviorTreeComponent:RemoveAllInstances()

	if (#self.InstanceStack > 0) then
		self:StopTree(BehaviorTreeTypes.EBTStopMode.Forced);
	end

	local DummyInstance = BehaviorTreeTypes.FBehaviorTreeInstance();
	for Idx = 1, #self.KnownInstances do
		local Info = self.KnownInstances[Idx];
		if (#Info.InstanceMemory > 0) then
			DummyInstance:SetInstanceMemory(Info.InstanceMemory);
			DummyInstance.InstanceIdIndex = Idx;
			DummyInstance.RootNode = Info.RootNode;

			DummyInstance:Cleanup(self, BehaviorTreeTypes.EBTMemoryClear.Destroy);
		end
	end

	self.KnownInstances = {};
	self.NodeInstances = {};
end

function BehaviorTreeComponent:CopyInstanceMemoryToPersistent()

	for InstanceIndex = 1, #self.InstanceStack do
		local InstanceData = self.InstanceStack[InstanceIndex];
		local InstanceInfo = self.KnownInstances[InstanceData.InstanceIdIndex];

		Utils.table.deepcopy(InstanceData:GetInstanceMemory(), InstanceInfo.InstanceMemory)
	end
end

function BehaviorTreeComponent:CopyInstanceMemoryFromPersistent()

	for InstanceIndex = 1, #self.InstanceStack do
		local InstanceData = self.InstanceStack[InstanceIndex];
		local InstanceInfo = self.KnownInstances[InstanceData.InstanceIdIndex];

		InstanceData:SetInstanceMemory(InstanceInfo.InstanceMemory);
	end
end


return class(Uself.BlackboardComponent, statics, BrainComponent)