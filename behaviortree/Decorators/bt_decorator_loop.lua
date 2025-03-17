local BTDecorator = require("behaviortree.bt_decorator")
local BehaviorTreeTypes = require("behaviortree.behavior_tree_types")
local BTComposite_SimpleParallel = require("behaviortree.Composites.bt_composite_simpleparallel")
local Adapter = require("library.adapter")

local BTDecorator_Loop = {
    NumLoops = 3,
    bInfiniteLoop = false,
    InfiniteLoopTimeoutTime = -1.0,

    bNotifyActivation = true,
}

function BTDecorator_Loop:constructor(args)
    BTDecorator.constructor(self, args)

    self.NumLoops = args.NumLoops
    self.bInfiniteLoop = args.bInfiniteLoop
    self.InfiniteLoopTimeoutTime = args.InfiniteLoopTimeoutTime
end


function BTDecorator_Loop:OnNodeActivation(SearchData)
	local DecoratorMemory = self:GetNodeMemory(SearchData);
	local ParentMemory = self:GetParentNode():GetNodeMemory(SearchData);
	local bIsSpecialNode = instanceof(self:GetParentNode(), BTComposite_SimpleParallel)

	if ((bIsSpecialNode and ParentMemory.CurrentChild == BehaviorTreeTypes.BTSpecialChild.NotInitialized) or
		(not bIsSpecialNode and ParentMemory.CurrentChild ~= self.ChildIndex)) then

		DecoratorMemory.RemainingExecutions = self.NumLoops;
		DecoratorMemory.TimeStarted = Adapter.GetTimeSeconds();
    end

	local bShouldLoop = false;
	if (self.bInfiniteLoop) then
		
		if (SearchData.SearchId ~= DecoratorMemory.SearchId) then
			if ((self.InfiniteLoopTimeoutTime < 0.0) or ((DecoratorMemory.TimeStarted + self.InfiniteLoopTimeoutTime) > Adapter.GetTimeSeconds())) then
				bShouldLoop = true;
            end
		end

		DecoratorMemory.SearchId = SearchData.SearchId;
	else
		if (DecoratorMemory.RemainingExecutions > 0) then
			DecoratorMemory.RemainingExecutions = DecoratorMemory.RemainingExecutions - 1;
        end
		bShouldLoop = DecoratorMemory.RemainingExecutions > 0;
	end

	if (bShouldLoop) then
		self:GetParentNode():SetChildOverride(SearchData, self.ChildIndex);
	end
end

return class(BTDecorator_Loop, {}, BTDecorator)
