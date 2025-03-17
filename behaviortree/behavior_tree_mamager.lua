local Utils = require("library.Utils")
local BTCompositeNode = require("bt_composite_node")
local BTTask_RunBehavior = require("Tasks.bt_task_runbehavior")

local FBehaviorTreeTemplateInfo = {
	Asset = nil,
	Template = nil,
}

local FNodeInitializationData = {
    Node = nil,
	ParentNode = nil,
	ExecutionIndex = 0,
	TreeDepth = 0,
}

function FNodeInitializationData:constructor(InNode, InParentNode, InExecutionIndex, InTreeDepth)
    self.Node = InNode
    self.ParentNode = InParentNode
    self.ExecutionIndex = InExecutionIndex
    self.TreeDepth = InTreeDepth
end

local statics = {
	FBehaviorTreeTemplateInfo = class(FBehaviorTreeTemplateInfo),
	FNodeInitializationData = class(FNodeInitializationData)
}

local function MergeDecoratorOpsHelper(LinkOps, InjectedOps, NumOriginalDecorators, NumInjectedDecorators)
    if #LinkOps == 0 and #InjectedOps == 0 then
        return
    end

    local NumOriginalOps = #LinkOps
    if NumOriginalDecorators > 0 then
        local MasterAndOp = BTCompositeNode.FBTDecoratorLogic(BTCompositeNode.BTCompositeNode.EBTDecoratorLogic.And, NumOriginalOps > 0 and 2 or NumOriginalDecorators + 1)
        table.insert(LinkOps, MasterAndOp, 1)

        if NumOriginalOps == 0 then
            for Idx = 1, NumOriginalDecorators, 1 do
                local TestOp = BTCompositeNode.FBTDecoratorLogic(BTCompositeNode.EBTDecoratorLogic.Test, Idx)
                table.insert(LinkOps, TestOp)
            end
        end
    end

    if #InjectedOps == 0 then
        local InjectedAndOp = BTCompositeNode.FBTDecoratorLogic(BTCompositeNode.EBTDecoratorLogic.And, NumInjectedDecorators);
        table.insert(LinkOps, InjectedAndOp)

		for Idx = 0, #NumInjectedDecorators, 1 do
			local TestOp = BTCompositeNode.FBTDecoratorLogic(BTCompositeNode.EBTDecoratorLogic.Test, NumOriginalDecorators + Idx);
            table.insert(LinkOps, TestOp)
        end
    else
        for Idx = 0, #InjectedOps, 1 do
			local InjectedOpCopy = InjectedOps[Idx];
			if (InjectedOpCopy.Operation == BTCompositeNode.EBTDecoratorLogic.Test) then
				InjectedOpCopy.Number = InjectedOpCopy.Number + NumOriginalDecorators;
            end

			table.insert(LinkOps, InjectedOpCopy);
		end
    end
end

local InitializeNodeHelper
InitializeNodeHelper = function(ParentNode, NodeOb, TreeDepth, ExecutionIndex, InitList, TreeAsset)
    table.insert(InitList, statics.FNodeInitializationData(NodeOb, ParentNode, ExecutionIndex, TreeDepth))
    NodeOb:InitializeFromAsset(TreeAsset);
    ExecutionIndex = ExecutionIndex + 1

    local CompositeOb = NodeOb
    if not instanceof(CompositeOb, BTCompositeNode) then
        return
    end

    for ServiceIndex = 1, #CompositeOb.Services, 1 do
		if ServiceIndex > #CompositeOb.Services then
			break;
		end

		if not CompositeOb.Services[ServiceIndex] then
            table.remove(CompositeOb.Services, ServiceIndex)
			ServiceIndex = ServiceIndex - 1
		else
			local Service = CompositeOb.Services[ServiceIndex]:Clone()
			CompositeOb.Services[ServiceIndex] = Service;
	
			table.insert(InitList, statics.FNodeInitializationData(Service, CompositeOb, ExecutionIndex, TreeDepth));
	
			Service:InitializeFromAsset(TreeAsset);
			ExecutionIndex = ExecutionIndex + 1
        end
	end

	for ChildIndex = 1, #CompositeOb.Children, 1 do
		local ChildInfo = CompositeOb.Children[ChildIndex];
		for DecoratorIndex = 1, #ChildInfo.Decorators do
			if DecoratorIndex > #ChildInfo.Decorators then
				break;
			end

			if (ChildInfo.Decorators[DecoratorIndex] == nil) then
				table.remove(ChildInfo.Decorators, DecoratorIndex)
				DecoratorIndex = DecoratorIndex - 1
			else
				local Decorator = ChildInfo.Decorators[DecoratorIndex]:Clone()
				ChildInfo.Decorators[DecoratorIndex] = Decorator;

				table.insert(InitList, statics.FNodeInitializationData(Decorator, CompositeOb, ExecutionIndex, TreeDepth))
				Decorator:InitializeFromAsset(TreeAsset);
				Decorator:InitializeParentLink(ChildIndex);
				ExecutionIndex = ExecutionIndex + 1
			end
		end

		local SubtreeTask = instanceof(ChildInfo.ChildTask, BTTask_RunBehavior) and ChildInfo.ChildTask or nil
		if (SubtreeTask and SubtreeTask:GetSubtreeAsset() and #SubtreeTask:GetSubtreeAsset().RootDecorators > 0) then
			local SubtreeAsset = SubtreeTask:GetSubtreeAsset();
			local NumOrgDecorators = #ChildInfo.Decorators;

			for DecoratorIndex = 1, #SubtreeAsset.RootDecorators do
				if (SubtreeAsset.RootDecorators[DecoratorIndex] == nil) then
					
				else
					
					local Decorator = SubtreeAsset.RootDecorators[DecoratorIndex]:Clone()
					table.insert(ChildInfo.Decorators, Decorator)

					table.insert(InitList, statics.FNodeInitializationData(Decorator, CompositeOb, ExecutionIndex, TreeDepth))

					Decorator:MarkInjectedNode();
					Decorator:InitializeFromAsset(TreeAsset);
					Decorator:InitializeParentLink(ChildIndex);
					ExecutionIndex = ExecutionIndex + 1
				end
			end
				
			local NumInjectedDecorators = #ChildInfo.Decorators - NumOrgDecorators;
			MergeDecoratorOpsHelper(ChildInfo.DecoratorOps, SubtreeAsset.RootDecoratorOps, NumOrgDecorators, NumInjectedDecorators);
		end

		local ChildNode = nil;

		if (ChildInfo.ChildComposite) then
			ChildInfo.ChildComposite =ChildInfo.ChildComposite:Clone()
			ChildNode = ChildInfo.ChildComposite;
		elseif (ChildInfo.ChildTask) then
			ChildInfo.ChildTask = ChildInfo.ChildTask:Clone()
			ChildNode = ChildInfo.ChildTask;

			for ServiceIndex = 1, #ChildInfo.ChildTask.Services do
				if ServiceIndex > #ChildInfo.ChildTask.Services then
					break
				end

				if (ChildInfo.ChildTask.Services[ServiceIndex] == nil) then
					table.remove(ChildInfo.ChildTask.Services, ServiceIndex)
					ServiceIndex = ServiceIndex - 1
				else
					local Service = ChildInfo.ChildTask.Services[ServiceIndex]:Clone()
					ChildInfo.ChildTask.Services[ServiceIndex] = Service;

					table.insert(InitList, statics.FNodeInitializationData(Service, CompositeOb, ExecutionIndex, TreeDepth))

					Service:InitializeFromAsset(TreeAsset);
					Service:InitializeParentLink(ChildIndex);
					ExecutionIndex = ExecutionIndex + 1
				end
			end
		end

		if (ChildNode) then
			InitializeNodeHelper(CompositeOb, ChildNode, TreeDepth + 1, ExecutionIndex, InitList, TreeAsset);
		end
	end

	CompositeOb:InitializeComposite(ExecutionIndex - 1);
end

local BehaviorTreeManager = {
    LoadedTemplates = {},
    ActiveComponents = {},
}

function BehaviorTreeManager:LoadTree(Asset)
	for TemplateIndex = 1, #self.LoadedTemplates do
		local TemplateInfo = self.LoadedTemplates[TemplateIndex];
		if (TemplateInfo.Asset == Asset) then
			return TemplateInfo.Template, TemplateInfo.InstanceMemorySize;
		end
	end

	if (Asset.RootNode) then
		local TemplateInfo = statics.FBehaviorTreeTemplateInfo();
		TemplateInfo.Asset = Asset;
		TemplateInfo.Template = Asset.RootNode:Clone()

		local InitList = {};
		local ExecutionIndex = 0;
		InitializeNodeHelper(nil, TemplateInfo.Template, 0, ExecutionIndex, InitList, Asset);

		for Index = 1, #InitList do
			InitList[Index].Node:InitializeNode(InitList[Index].ParentNode, InitList[Index].ExecutionIndex, MemoryOffset, InitList[Index].TreeDepth);
		end
		
		TemplateInfo.InstanceMemorySize = #InitList
		table.insert(self.LoadedTemplates, TemplateInfo)

		return TemplateInfo.Template, TemplateInfo.InstanceMemorySize;
	end

end

function BehaviorTreeManager:FinishDestroy()
    for i = 1, #self.ActiveComponents, 1 do
        if self.ActiveComponents[i] then
            self.ActiveComponents[i]:Cleanup();
        end
    end

    self.ActiveComponents = {}
end

function BehaviorTreeManager:AddActiveComponent(Component)
    table.insert(self.ActiveComponents, Component)
end

function BehaviorTreeManager:RemoveActiveComponent(Component)
    Utils.array.remove(self.ActiveComponents, Component)
end


return BehaviorTreeManager