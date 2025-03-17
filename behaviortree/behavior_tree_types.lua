local Utils = require("library.Utils")
local BTAuxiliaryNode = require("bt_auxiliary_node")
local BTService = require("bt_service")

local BehaviorTreeTypes = {
    INDEX_NONE = -1,

    FBlackboard = {
        KeySelf = "SelfActor",
        InvalidKey = 0xff
    },
    
    EBlackboardNotificationResult = {
        RemoveObserver = 0,
        ContinueObserving = 1
    },
    
    BTSpecialChild = {
        NotInitialized = -1,
        ReturnToParent = -2,
        OwnedByComposite = 0xff
    },
    
    EBTNodeResult = {
        Succeeded = 0,
        Failed = 1,
        Aborted = 2,
        InProgress = 3
    },
    
    EBTExecutionMode = {
        SingleRun = 0,
        Looped = 1
    },
    
    EBTStopMode = {
        Safe = 0,
        Forced = 1
    },
    
    EBTMemoryInit = {
        Initialize = 0,
        RestoreSubtree = 1
    },
    
    EBTMemoryClear = {
        Destroy = 0,
        StoreSubtree = 1
    },
    
    EBTFlowAbortMode = {
        None = 0,
        LowerPriority = 1,
        Self = 2,
        Both = 3
    },
    
    EBTActiveNode = {
        Composite = 0,
        ActiveTask = 1,
        AbortingTask = 2,
        InactiveTask = 3
    },
    
    EBTTaskStatus = {
        Active = 0,
        Aborting = 1,
        Inactive = 2
    },
    
    EBTNodeUpdateMode = {
        Unknown = 0,
        Add = 1,
        Remove = 2
    },

    EBTExecutionSnap = {
        Regular = 0,
        OutOfNodes = 1
    },
    
    EBTDescriptionVerbosity = {
        Basic = 0,
        Detailed = 1
    },
    
    EBTNodeRelativePriority = {
        Lower = 0,
        Same = 1,
        Higher = 2
    },
}


local FBehaviorTreeParallelTask = {
    TaskNode = nil,
    Status = BehaviorTreeTypes.EBTTaskStatus.Active
}

function FBehaviorTreeParallelTask:constructor(InTaskNode, InStatus)

    if InTaskNode then
        self.TaskNode = InTaskNode
    end

    if InStatus then
        self.Status = InStatus
    end

    local mt = getmetatable(self)
    mt.__eq = function(a, b)
        if b.TaskNode then
            return a.TaskNode == b.TaskNode
        else
            return a.TaskNode == b
        end
    end
end

BehaviorTreeTypes.FBehaviorTreeParallelTask = class(FBehaviorTreeParallelTask)

local FBehaviorTreeInstanceId = {
    TreeAsset = nil,
    RootNode = nil,
    Path = {},
    InstanceMemory = {},
    FirstNodeInstance = -1,
}

function FBehaviorTreeInstanceId:constructor()

    local mt = getmetatable(self)
    mt.__eq = function(a, b)
        if a.TreeAsset ~= b.TreeAsset then
            return false
        end

        return a.TreeAsset == b.TreeAsset and Utils.array.isEqual(a, b)
    end

end

BehaviorTreeTypes.FBehaviorTreeInstanceId = class(FBehaviorTreeInstanceId)

local FBehaviorTreeInstance = {
    RootNode = nil,
    ActiveNode = nil,
    ActiveAuxNodes = {},
    ParallelTasks = {},
    InstanceMemory = {},
    InstanceIdIndex = 0,
    ActiveNodeType = BehaviorTreeTypes.EBTActiveNode.AbortingTask
}

--InstancedIndex table-ref
function FBehaviorTreeInstance:Initialize(OwnerComp, Node, InstancedIndex, InitType)
    for i = 1, #Node.Services, 1 do
        Node.Services[i]:InitializeInSubtree(OwnerComp, Node.Services:GetNodeMemory(self), InstancedIndex, InitType)
    end

    local NodeMemory = Node:GetNodeMemory(self)
    Node:InitializeInSubtree(OwnerComp, NodeMemory, InstancedIndex, InitType)

    local InstancedComposite = Node:GetNodeInstance(OwnerComp, NodeMemory)
    if InstancedComposite then
        InstancedComposite:InitializeComposite(Node:GetLastExecutionIndex());
    end

    for ChildIndex = 1, #Node.Children, 1 do
        local ChildInfo = Node.Children[ChildIndex]

        for DecoratorIndex = 1, #ChildInfo.Decorators, 1 do
            local DecoratorOb = ChildInfo.Decorators[DecoratorIndex];
            local DecoratorMemory = DecoratorOb:GetNodeMemory(self);
            DecoratorOb:InitializeInSubtree(OwnerComp, DecoratorMemory, InstancedIndex, InitType);

            local InstancedDecoratorOb = DecoratorOb:GetNodeInstance(OwnerComp, DecoratorMemory)
            if InstancedDecoratorOb then
                InstancedDecoratorOb:InitializeParentLink(DecoratorOb:GetChildIndex())
            end
        end

        if ChildInfo.ChildComposite then
            self:Initialize(OwnerComp, ChildInfo.ChildComposite, InstancedIndex, InitType);
        elseif ChildInfo.ChildTask then
            for ServiceIndex = 1, #ChildInfo.ChildTask.Services, 1 do
                local ServiceOb = ChildInfo.ChildTask.Services[ServiceIndex];
                local ServiceMemory = ServiceOb:GetNodeMemory(self);
                ServiceOb:InitializeInSubtree(OwnerComp, ServiceMemory, InstancedIndex, InitType);

                local InstancedServiceOb = ServiceOb:GetNodeInstance(OwnerComp, ServiceMemory);
                if InstancedServiceOb then
                    InstancedServiceOb:InitializeParentLink(ServiceOb:GetChildIndex());
                end
            end

            ChildInfo.ChildTask:InitializeInSubtree(OwnerComp, ChildInfo.ChildTask:GetNodeMemory(self), InstancedIndex,
                InitType);
        end
    end
end

function FBehaviorTreeInstance:Cleanup(OwnerComp, CleanupType)
    local Info = OwnerComp.KnownInstances[self.InstanceIdIndex];
    if Info.FirstNodeInstance >= 0 then
        local MaxAllowedIdx = #OwnerComp.NodeInstances;

        local LastNodeIdx = OwnerComp.KnownInstances[self.InstanceIdIndex + 1] and
                                math.min(OwnerComp.KnownInstances[self.InstanceIdIndex + 1].FirstNodeInstance,
                MaxAllowedIdx) or MaxAllowedIdx

        for Idx = Info.FirstNodeInstance, LastNodeIdx, 1 do
            OwnerComp.NodeInstances[Idx]:OnInstanceDestroyed(OwnerComp);
        end
    end

    self:CleanupNodes(OwnerComp, self.RootNode, CleanupType);

    if CleanupType == BehaviorTreeTypes.EBTMemoryClear.Destroy then
        Info.InstanceMemory = {};
    else
        Utils.CopyTable(self.InstanceMemory, Info.InstanceMemory)
    end
end

function FBehaviorTreeInstance:CleanupNodes(OwnerComp, Node, CleanupType)
    for ServiceIndex = 1, #Node.Services, 1 do
        Node.Services[ServiceIndex]:CleanupInSubtree(OwnerComp, Node.Services[ServiceIndex]:GetNodeMemory(self),
            CleanupType);
    end

    Node:CleanupInSubtree(OwnerComp, Node:GetNodeMemory(self), CleanupType);

    for ChildIndex = 1, #Node.Children, 1 do
        local ChildInfo = Node.Children[ChildIndex];

        for DecoratorIndex = 1, #ChildInfo.Decorators, 1 do
            ChildInfo.Decorators[DecoratorIndex]:CleanupInSubtree(OwnerComp,
                ChildInfo.Decorators[DecoratorIndex]:GetNodeMemory(self), CleanupType);
        end

        if ChildInfo.ChildComposite then
            self:CleanupNodes(OwnerComp, ChildInfo.ChildComposite, CleanupType);
        elseif ChildInfo.ChildTask then
            for ServiceIndex = 1, #ChildInfo.ChildTask.Services, 1 do
                ChildInfo.ChildTask.Services[ServiceIndex]:CleanupInSubtree(OwnerComp,
                    ChildInfo.ChildTask.Services[ServiceIndex]:GetNodeMemory(self), CleanupType);
            end

            ChildInfo.ChildTask:CleanupInSubtree(OwnerComp, ChildInfo.ChildTask:GetNodeMemory(self), CleanupType);
        end
    end
end

function FBehaviorTreeInstance:AddToActiveAuxNodes(AuxNode)
    table.insert(self.ActiveAuxNodes, AuxNode)
end

function FBehaviorTreeInstance:RemoveFromActiveAuxNodes(AuxNode)
    Utils.array.remove(self.ActiveAuxNodes, AuxNode)
end

function FBehaviorTreeInstance:ResetActiveAuxNodes()
    self.ActiveAuxNodes = {}
end

function FBehaviorTreeInstance:AddToParallelTasks(ParallelTask)
    table.insert(self.ParallelTasks, ParallelTask);
end

function FBehaviorTreeInstance:RemoveParallelTaskAt(TaskIndex)
    table.remove(self.ParallelTasks, TaskIndex)
end

function FBehaviorTreeInstance:MarkParallelTaskAsAbortingAt(TaskIndex)
    self.ParallelTasks[TaskIndex].Status = BehaviorTreeTypes.EBTTaskStatus.Aborting;
end

function FBehaviorTreeInstance:SetInstanceMemory(Memory)
    self.InstanceMemory = Utils.table.deepcopy(Memory)
end

function FBehaviorTreeInstance:ExecuteOnEachAuxNode(ExecFunc)
    for i = 1, #self.ActiveAuxNodes, 1 do
        local AuxNode = self.ActiveAuxNodes[i]
        ExecFunc(AuxNode);
    end
end

function FBehaviorTreeInstance:ExecuteOnEachParallelTask(ExecFunc)
    for Index = 1, #self.ParallelTasks, 1 do

        -- calling ExecFunc might unregister parallel task, modifying array we're iterating on - iterator needs to be moved one step back in that case
        if Index > #self.ParallelTasks then
            return
        end

        local ParallelTaskInfo = self.ParallelTasks[Index];
        local CachedParallelTask = ParallelTaskInfo.TaskNode;
        local CachedNumTasks = #self.ParallelTasks;

        ExecFunc(ParallelTaskInfo, Index);

        local bIsStillValid = self.ParallelTasks[Index] and (ParallelTaskInfo.TaskNode == CachedParallelTask);
        if not bIsStillValid then
            Index = Index - 1
        end
    end
end

function FBehaviorTreeInstance:HasActiveNode(TestExecutionIndex)
    if self.ActiveNode and self.ActiveNode:GetExecutionIndex() == TestExecutionIndex then
        return self.ActiveNodeType == BehaviorTreeTypes.EBTActiveNode.ActiveTask
    end

    for Idx = 1, #self.ParallelTasks, 1 do
        local ParallelTask = self.ParallelTasks[Idx];
        if ParallelTask.TaskNode and ParallelTask.TaskNode:GetExecutionIndex() == TestExecutionIndex then
            return (ParallelTask.Status == BehaviorTreeTypes.EBTTaskStatus.Active);
        end
    end

    for Idx = 1, #self.ActiveAuxNodes, 1 do
        if (self.ActiveAuxNodes[Idx] and self.ActiveAuxNodes[Idx]:GetExecutionIndex() == TestExecutionIndex) then
            return true;
        end
    end

    return false;
end

function FBehaviorTreeInstance:DeactivateNodes(SearchData, InstanceIndex)
    for Idx = #SearchData.PendingUpdates, 1, -1 do
        local UpdateInfo = SearchData.PendingUpdates[Idx];
        if (UpdateInfo.InstanceIndex == InstanceIndex and UpdateInfo.Mode == BehaviorTreeTypes.EBTNodeUpdateMode.Add) then
            table.remove(SearchData.PendingUpdates, Idx)
        end
    end

    for Idx = 1, #self.ParallelTasks, 1 do
        local ParallelTask = self.ParallelTasks[Idx];
        if (ParallelTask.TaskNode and ParallelTask.Status == BehaviorTreeTypes.EBTTaskStatus.Active) then
            SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(ParallelTask.TaskNode, InstanceIndex,
            BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
        end
    end

    for Idx = 1, #self.ActiveAuxNodes, 1 do
        if (self.ActiveAuxNodes[Idx]) then
            SearchData:AddUniqueUpdate(BehaviorTreeTypes.FBehaviorTreeSearchUpdate(self.ActiveAuxNodes[Idx], InstanceIndex,
            BehaviorTreeTypes.EBTNodeUpdateMode.Remove));
        end
    end
end

function FBehaviorTreeInstance:GetActiveAuxNodes()
    return self.ActiveAuxNodes
end

function FBehaviorTreeInstance:GetParallelTasks()
    return self.ParallelTasks
end

function FBehaviorTreeInstance:IsValidParallelTaskIndex(Index)
    return self.ParallelTasks[Index] ~= nil
end

function FBehaviorTreeInstance:GetInstanceMemory()
    return self.InstanceMemory
end

BehaviorTreeTypes.FBehaviorTreeInstance = class(FBehaviorTreeInstance)

local FBTNodeIndex = {
    InstanceIndex = 0xffff,
    ExecutionIndex = 0xffff,
}

function FBTNodeIndex:constructor(InInstanceIndex, InExecutionIndex)

    if InInstanceIndex then
        self.InstanceIndex = InInstanceIndex
    end

    if InExecutionIndex then
        self.ExecutionIndex = InExecutionIndex
    end

    local mt = getmetatable(self)
    mt.__eq = function(a, b)
        return a.ExecutionIndex == b.ExecutionIndex and a.InstanceIndex == b.InstanceIndex
    end
end

function FBTNodeIndex:TakesPriorityOver(Other)
    if self.InstanceIndex ~= Other.InstanceIndex then
        return self.InstanceIndex < Other.InstanceIndex
    end

    return self.ExecutionIndex < Other.ExecutionIndex;
end

function FBTNodeIndex:IsSet()
    return self.InstanceIndex < 0xffff
end

BehaviorTreeTypes.FBTNodeIndex = class(FBTNodeIndex)

local FBTNodeIndexRange = {
    FromIndex = nil,
    ToIndex = nil, 
}

function FBTNodeIndexRange:constructor(From, To)

    if From then
        self.FromIndex = From
    end

    if To then
        self.ToIndex = To
    end

    local mt = getmetatable(self)
    mt.__eq = function(a, b)
        return a.FromIndex == b.FromIndex and a.ToIndex == b.ToIndex;
    end
end

function FBTNodeIndexRange:IsSet()
    return self.FromIndex.IsSet() and self.ToIndex.IsSet();
end

function FBTNodeIndexRange:Contains(Index)
    return Index.InstanceIndex == self.FromIndex.InstanceIndex and self.FromIndex.ExecutionIndex <= Index.ExecutionIndex and Index.ExecutionIndex <= self.ToIndex.ExecutionIndex;
end

BehaviorTreeTypes.FBTNodeIndexRange = class(FBTNodeIndexRange)

local FBehaviorTreeSearchUpdate = {
    AuxNode = nil,
    TaskNode = nil,
    InstanceIndex = 0,
    Mode = FBTNodeIndexRange.EBTNodeUpdateMode.Add,
    bPostUpdate = false
}

function FBehaviorTreeSearchUpdate:constructor(InNode, InInstanceIndex, InMode)

    if InNode then
        if instanceof(InNode, BTAuxiliaryNode) then
            self.AuxNode = InNode
        else
            self.TaskNode = InNode
        end
    end

    if InInstanceIndex then
        self.InstanceIndex = InInstanceIndex
    end

    if InMode then
        self.Mode = InMode
    end

end

BehaviorTreeTypes.FBehaviorTreeSearchUpdate = class(FBehaviorTreeSearchUpdate)

local FBehaviorTreeSearchUpdateNotify = {
    InstanceIndex = 0,
    NodeResult = BehaviorTreeTypes.EBTNodeResult.Succeeded,
}

function FBehaviorTreeSearchUpdateNotify:constructor(InInstanceIndex, InNodeResult)

    if InInstanceIndex then
        self.InstanceIndex = InInstanceIndex
    end

    if InNodeResult then
        self.NodeResult = InNodeResult
    end

end

BehaviorTreeTypes.FBehaviorTreeSearchUpdateNotify = class(FBehaviorTreeSearchUpdateNotify)

local FBehaviorTreeSearchData = {
    OwnerComp = nil,
    PendingUpdates = {},
    PendingNotifies = {},
    SearchRootNode = {},
    SearchStart = {},
    SearchEnd = {},
    SearchId = 0,
    RollbackInstanceIdx = 0,
    DeactivatedBranchStart = {},
    DeactivatedBranchEnd = {},
    RollbackDeactivatedBranchStart = {},
    RollbackDeactivatedBranchEnd = {},
    bFilterOutRequestFromDeactivatedBranch = false,
    bPostponeSearch = false,
    bSearchInProgress = false,
    bPreserveActiveNodeMemoryOnRollback = false,
}

function FBehaviorTreeSearchData:constructor(InOwnerComp)
    self.OwnerComp = InOwnerComp
end

function FBehaviorTreeSearchData:AddUniqueUpdate(UpdateInfo)
    local bSkipAdding = false;
	for UpdateIndex = 1, #self.PendingUpdates, 1 do
		local Info = self.PendingUpdates[UpdateIndex];
		if (Info.AuxNode == UpdateInfo.AuxNode and Info.TaskNode == UpdateInfo.TaskNode) then
			if (Info.Mode == UpdateInfo.Mode) then
				bSkipAdding = true;
				break;
            end

			bSkipAdding = (Info.Mode == BehaviorTreeTypes.EBTNodeUpdateMode.Remove) or (UpdateInfo.Mode == BehaviorTreeTypes.EBTNodeUpdateMode.Remove);

            table.remove(self.PendingUpdates, UpdateIndex)
		end
	end

    if (not bSkipAdding) and UpdateInfo.Mode == BehaviorTreeTypes.EBTNodeUpdateMode.Remove and UpdateInfo.AuxNode then
		local bIsActive = self.OwnerComp:IsAuxNodeActive(UpdateInfo.AuxNode, UpdateInfo.InstanceIndex);
		bSkipAdding = not bIsActive;
	end

    if (not bSkipAdding) then
        table.insert(self.PendingUpdates, UpdateInfo)
		local Idx = #self.PendingUpdates
		self.PendingUpdates[Idx].bPostUpdate = (UpdateInfo.Mode == BehaviorTreeTypes.EBTNodeUpdateMode.Add) and (instanceof(UpdateInfo.AuxNode, BTService));
	end
end

function FBehaviorTreeSearchData:AssignSearchId()
	self.SearchId = self.NextSearchId;
	self.NextSearchId = self.NextSearchId + 1
end

function FBehaviorTreeSearchData:Reset()
	self.PendingUpdates = {};
	self.PendingNotifies = {};
	self.SearchRootNode = BehaviorTreeTypes.FBTNodeIndex();
	self.SearchStart = BehaviorTreeTypes.FBTNodeIndex();
	self.SearchEnd = BehaviorTreeTypes.FBTNodeIndex();
	self.RollbackInstanceIdx = BehaviorTreeTypes.INDEX_NONE;
	self.DeactivatedBranchStart = BehaviorTreeTypes.FBTNodeIndex();
	self.DeactivatedBranchEnd = BehaviorTreeTypes.FBTNodeIndex();
	self.bFilterOutRequestFromDeactivatedBranch = false;
	self.bSearchInProgress = false;
	self.bPostponeSearch = false;
	self.bPreserveActiveNodeMemoryOnRollback = false;
end

BehaviorTreeTypes.FBehaviorTreeSearchData = class(FBehaviorTreeSearchData, { NextSearchId = 0 })

local FBlackboardKeySelector = {
    SelectedKeyID = BehaviorTreeTypes.FBlackboard.InvalidKey,
    SelectedKeyName = "",
    SelectedKeyType = {}
}

function FBlackboardKeySelector:ResolveSelectedKey(BlackboardAsset)
    self.SelectedKeyID = BlackboardAsset:GetKeyID(self.SelectedKeyName);
	self.SelectedKeyType = BlackboardAsset:GetKeyType(self.SelectedKeyID);
end

function FBlackboardKeySelector:GetSelectedKeyID()
    return self.SelectedKeyID
end

BehaviorTreeTypes.FBlackboardKeySelector = class(FBlackboardKeySelector)

return BehaviorTreeTypes