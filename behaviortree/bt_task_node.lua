local BTNode = require("bt_node")
local BehaviorTreeTypes = require("behavior_tree_types")
local BrainComponent = require("ai/brain_component")

local BTTaskNode = {
    bNotifyTick = false,
	bNotifyTaskFinished = false,
	bIgnoreRestartSelf = false,
}


function BTTaskNode:ShouldIgnoreRestartSelf()
	return self.bIgnoreRestartSelf;
end


function BTTaskNode:ExecuteTask(OwnerComp, NodeMemory)
	return BehaviorTreeTypes.EBTNodeResult.Succeeded;
end

function BTTaskNode:AbortTask(OwnerComp, NodeMemory)
	return BehaviorTreeTypes.EBTNodeResult.Aborted;
end

function BTTaskNode:WrappedExecuteTask(OwnerComp, NodeMemory)
	local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(OwnerComp, NodeMemory) or self;
	return NodeOb and NodeOb:ExecuteTask(OwnerComp, NodeMemory) or BehaviorTreeTypes.EBTNodeResult.Failed;
end

function BTTaskNode:WrappedAbortTask(OwnerComp, NodeMemory)
	local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(OwnerComp, NodeMemory) or self;
	local TaskNodeOb = NodeOb
	local Result = TaskNodeOb and TaskNodeOb:AbortTask(OwnerComp, NodeMemory) or BehaviorTreeTypes.EBTNodeResult.Aborted;

	return Result;
end

function BTTaskNode:WrappedTickTask(OwnerComp, NodeMemory, DeltaSeconds, ref)
	if (self.bNotifyTick) then
		local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(OwnerComp, NodeMemory) or self;
		if (NodeOb) then
			NodeOb:TickTask(OwnerComp, NodeMemory, DeltaSeconds);
			ref.NextNeededDeltaTime = 0.0;
			return true;
		end
	end

	return false;
end

function BTTaskNode:WrappedOnTaskFinished(OwnerComp, NodeMemory, TaskResult)
	local NodeOb = self.bCreateNodeInstance and self:GetNodeInstance(OwnerComp, NodeMemory) or self

	if (NodeOb) then
		local TaskNodeOb = NodeOb
		if (TaskNodeOb.bNotifyTaskFinished) then
			TaskNodeOb:OnTaskFinished(OwnerComp, NodeMemory, TaskResult);
		end
	end
end

function BTTaskNode:ReceivedMessage(BrainComp, Message)
	local OwnerComp = BrainComp

	local InstanceIdx = OwnerComp:FindInstanceContainingNode(self);
	if (OwnerComp.InstanceStack[InstanceIdx]) then
		local NodeMemory = self:GetNodeMemory(OwnerComp.InstanceStack[InstanceIdx]);
		self:OnMessage(OwnerComp, NodeMemory, Message.MessageName, Message.RequestID, Message.Status == BrainComponent.FAIMessage.Success);
	else

	end
end

function BTTaskNode:TickTask(OwnerComp, NodeMemory, DeltaSeconds)

end

function BTTaskNode:OnTaskFinished(OwnerComp, NodeMemory, TaskResult)

end

function BTTaskNode:OnMessage(OwnerComp, NodeMemory, Message, RequestID, bSuccess)
	local Status = OwnerComp:GetTaskStatus(self);
	if (Status == BehaviorTreeTypes.EBTTaskStatus.Active) then
		self:FinishLatentTask(OwnerComp, bSuccess and BehaviorTreeTypes.EBTNodeResult.Succeeded or BehaviorTreeTypes.EBTNodeResult.Failed);
	elseif (Status == BehaviorTreeTypes.EBTTaskStatus.Aborting) then
		self:FinishLatentAbort(OwnerComp);
	end
end

function BTTaskNode:FinishLatentTask(OwnerComp, TaskResult)
	local TemplateNode = OwnerComp:FindTemplateNode(self);
	OwnerComp:OnTaskFinished(TemplateNode, TaskResult);
end

function BTTaskNode:FinishLatentAbort(OwnerComp)
	local TemplateNode = OwnerComp:FindTemplateNode(self);
	OwnerComp:OnTaskFinished(TemplateNode, BehaviorTreeTypes.EBTNodeResult.Aborted);
end

function BTTaskNode:WaitForMessage(OwnerComp, MessageType)
	OwnerComp:RegisterMessageObserver(self, MessageType);
end

function BTTaskNode:WaitForMessage(OwnerComp, MessageType, RequestID)
	OwnerComp:RegisterMessageObserver(self, MessageType, RequestID);
end
	
function BTTaskNode:StopWaitingForMessages(OwnerComp)
	OwnerComp:UnregisterMessageObserversFrom(self);
end


return class(BTTaskNode, nil, BTNode)