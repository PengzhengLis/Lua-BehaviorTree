local BehaviorTreeTypes = require("behavior_tree_types")


local BTNode = {
    TreeAsset = nil,
    ParentNode = nil,

    ExecutionIndex = 0,
    MemoryOffset = 0,
    TreeDepth = 0,
    bIsInstanced = false,
    bIsInjected = false,
    bCreateNodeInstance = false,
}

function BTNode:Clone()
    local class = getclass(self)
    local newinstance = class()

    self:CloneTo(newinstance)
end

function BTNode:CloneTo(NewInstance)
    for k, v in pairs(self) do
        if type(k) ~= "function" then
            NewInstance[k] = v
        end
    end
end

function BTNode:GetMemoryOffset()
    return self.MemoryOffset
end

function BTNode:GetNodeMemory(SearchDataOrBTInstance)
    local BTInstance = SearchDataOrBTInstance
    if not BTInstance.InstanceMemory then
        local SearchData = SearchDataOrBTInstance
        BTInstance = SearchData.OwnerComp.InstanceStack[SearchData.OwnerComp:GetActiveInstanceIdx()]
    end

    return BTInstance.InstanceMemory[self.MemoryOffset]
end

function BTNode:InitializeNode(InParentNode, InExecutionIndex, InMemoryOffset, InTreeDepth)
    self.ParentNode = InParentNode;
    self.ExecutionIndex = InExecutionIndex;
    self.MemoryOffset = InMemoryOffset;
    self.TreeDepth = InTreeDepth;
end

function BTNode:InitializeMemory(OwnerComp, NodeMemory, InitType)

end

function BTNode:CleanupMemory(OwnerComp, NodeMemory, CleanupType)
    
end

function BTNode:OnInstanceCreated(OwnerComp)
    
end

function BTNode:OnInstanceDestroyed(OwnerComp)
    
end

function BTNode:InitializeInSubtree(OwnerComp, NodeMemory, ref, InitType)
    local SpecialMemory = NodeMemory
    if SpecialMemory then
        SpecialMemory.NodeIdx = BehaviorTreeTypes.INDEX_NONE
    end

    if self.bCreateNodeInstance then
        local NodeInstance = OwnerComp.NodeInstances[ref.NextInstancedIndex]
        if not NodeInstance then
            NodeInstance = self:Clone()
            NodeInstance:InitializeNode(self.ParentNode, self.ExecutionIndex, self.MemoryOffset, self.TreeDepth)
            NodeInstance.bIsInstanced = true

            table.insert(OwnerComp.NodeInstances, NodeInstance)
        end

        SpecialMemory.NodeIdx = ref.NextInstancedIndex

        NodeInstance:SetOwner(OwnerComp:GetOwner())
        NodeInstance:InitializeMemory(OwnerComp, NodeMemory, InitType);

        NodeInstance:InitializeFromAsset(self.TreeAsset);
		NodeInstance:OnInstanceCreated(OwnerComp);
		ref.NextInstancedIndex = ref.NextInstancedIndex + 1;
    else
        self:InitializeMemory(OwnerComp, NodeMemory, InitType)
    end
end

function BTNode:CleanupInSubtree(OwnerComp, NodeMemory, CleanupType)
    local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(OwnerComp, NodeMemory) or self
    if NodeOb then
        NodeOb:CleanupMemory(OwnerComp, NodeMemory, CleanupType)
    end
end

function BTNode:InitializeFromAsset(Asset)
	self.TreeAsset = Asset
end

function BTNode:GetBlackboardAsset()
	return self.TreeAsset and self.TreeAsset.BlackboardAsset or nil
end

function BTNode:GetNodeInstance(OwnerCompOrSearchData, NodeMemory)
    local OwnerComp = OwnerCompOrSearchData
    if not NodeMemory then
        OwnerComp = OwnerCompOrSearchData.OwnerComp
        NodeMemory = self:GetNodeMemory(OwnerCompOrSearchData)
    end
	
    local SpecialMemory = NodeMemory
    return SpecialMemory and OwnerComp.NodeInstances[SpecialMemory.NodeIdx] or nil
end

function BTNode:HasInstance()
    return self.bCreateNodeInstance
end

function BTNode:IsInstanced()
    return self.bIsInstanced
end

return class(BTNode)