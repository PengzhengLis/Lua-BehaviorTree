local BTDecorator = require("behaviortree.bt_decorator")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")
local BlackboardKeyType = require("behaviortree.blackboard.blackboard_keytype")
local AITypes = require("ai.ai_types")
local Adapter = require("library.adapter")

local BTDecorator_Cooldown = {
	CoolDownTime = 5.0,

	bNotifyTick = false,
	bNotifyDeactivation = true,
}

function BTDecorator_Cooldown:constructor(args)
	BTDecorator.constructor(self, args)

	self.FlowAbortMode = args.FlowAbortMode
	self.CoolDownTime = args.CoolDownTime
	self.bNotifyTick = (self.FlowAbortMode ~= BehaviorTreeTypes.EBTFlowAbortMode.None)
end

function BTDecorator_Cooldown:CalculateRawConditionValue(OwnerComp, NodeMemory)
	local DecoratorMemory = self.NodeMemory
	local TimePassed = (Adapter.GetTimeSeconds() - DecoratorMemory.LastUseTimestamp);
	return TimePassed >= self.CoolDownTime;
end

function BTDecorator_Cooldown:InitializeMemory(OwnerComp, NodeMemory, InitType)
	local DecoratorMemory = NodeMemory;
	if (InitType == BehaviorTreeTypes.EBTMemoryInit.Initialize) then
		DecoratorMemory.LastUseTimestamp = -AITypes.FLT_MAX;
	end

	DecoratorMemory.bRequestedRestart = false;
end

function BTDecorator_Cooldown:OnNodeDeactivation(SearchData, NodeResult)
	local DecoratorMemory = self:GetNodeMemory(SearchData);
	DecoratorMemory.LastUseTimestamp = Adapter.GetTimeSeconds();
	DecoratorMemory.bRequestedRestart = false;
end

function BTDecorator_Cooldown:TickNode(OwnerComp, NodeMemory, DeltaSeconds)
	local DecoratorMemory = NodeMemory
	if (not DecoratorMemory.bRequestedRestart) then
		local TimePassed = (Adapter.GetTimeSeconds() - DecoratorMemory.LastUseTimestamp);
		if (TimePassed >= self.CoolDownTime) then
			DecoratorMemory.bRequestedRestart = true;
			OwnerComp:RequestExecution(self);
		end
	end
end


return class(BTDecorator_Cooldown, {}, BTDecorator)