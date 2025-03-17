local BlackboardComponent = require("behaviortree.blackboard_component")
local BehaviorTreeComponent = require("behaviortree.behavior_tree_component")
local BehaviorTreeTypes = require("behavior_tree_types")
local Adapter = require("library.adapter")

local AIController = {
    Pawn = nil,
    AIWorld = nil,
    BlackboardComp = nil,
    BrainComponent = nil,
}

function AIController:constructor(args)
	self.Pawn = args.Pawn
end

function AIController:dtor()
	self.BlackboardComp = nil
	self.BrainComponent = nil;
end

function AIController:SetAIWorld(World)
	self.AIWorld = World;
end

function AIController:GetAIWorld()
	return self.AIWorld;
end

function AIController:Possess(target)
	self.Pawn = target;
end

function AIController:GetTarget()
	return self.Pawn;
end

function AIController:UseBlackboard(BlackboardAsset)
	if (BlackboardAsset == nil) then
		return false;
	end

	if (self.BlackboardComp ~= nil) then
		return false;
	end

	self.BlackboardComp = BlackboardComponent()
	if (self.BlackboardComp ~= nil) then
		self.BlackboardComp:CacheBrainComponent(self.BrainComponent);
		self:InitalizeBlackboard(self.BlackboardComp, BlackboardAsset);
	end

	return true;
end

function AIController:ShouldSyncBlackboardWith(OtherBlackboardComponent)
	return self.BlackboardComp ~= nil
		and self.BlackboardComp:GetBlackboardAsset() ~= nil
		and OtherBlackboardComponent.GetBlackboardAsset() ~= nil
		and self.BlackboardComp:GetBlackboardAsset():IsRelatedTo(OtherBlackboardComponent:GetBlackboardAsset());
end

function AIController:RunBehaviorTree(BTAsset)
	if (BTAsset == nil) then
		return false;
	end

	local bSuccess = true;

	local BTComp = self.BrainComponent;
	if (BTComp == nil) then
		BTComp = BehaviorTreeComponent()
	end

	self.BrainComponent = BTComp
	self.BrainComponent:SetAIOwner(self)

	if (BTAsset.BlackboardAsset and self.BlackboardComp == nil) then
		bSuccess = self:UseBlackboard(BTAsset.BlackboardAsset);
	end

	if (bSuccess) then
		self.BrainComponent:CacheBlackboardComponent(self.BlackboardComp);

		BTComp:StartTree(BTAsset, BehaviorTreeTypes.BTExecutionMode.Looped);
	end

	return bSuccess;
end

function AIController:GetBrainComponent()
	return self.BrainComponent;
end

function AIController:Tick(DeltaTime)
	if (self.BrainComponent ~= nil) then
		self.BrainComponent:TickComponent(DeltaTime);
	end
end

function AIController:SetBlackboardValueAsBool(key, value)
	if (nil ~= self.BlackboardComp) then
		self.BlackboardComp:SetValueAsBool(key, value);
	end
end

function AIController:SetBlackboardValueAsNumber(key, value)
	if (nil ~= self.BlackboardComp) then
		self.BlackboardComp:SetValueAsNumber(key, value);
	end
end

function AIController:SetBlackboardValueAsObject(key, object)
	if (nil ~= self.BlackboardComp) then
		self.BlackboardComp:SetValueAsObject(key, object);
	end
end

function AIController:SetBlackboardValueAsString(key, value)
	if (nil ~= self.BlackboardComp) then
		self.BlackboardComp:SetValueAsString(key, value);
	end
end

function AIController:SetBlackboardValueAsVector(key, value)
	if (nil ~= self.BlackboardComp) then
		self.BlackboardComp:SetValueAsVector(key, value);
	end
end

function AIController:GetBlackboardValueAsBool(key)
	if (nil ~= self.BlackboardComp) then
		return self.BlackboardComp:GetValueAsBool(key);
	end
end

function AIController:GetBlackboardValueAsNumber(key)
	if (nil ~= self.BlackboardComp) then
		return self.BlackboardComp:GetValueAsNumber(key);
	end
end

function AIController:GetBlackboardValueAsObject(key)
	if (nil ~= self.BlackboardComp) then
		return self.BlackboardComp:GetValueAsObject(key);
	end
end

function AIController:GetBlackboardValueAsString(key)
	if (nil ~= self.BlackboardComp) then
		return self.BlackboardComp:GetValueAsString(key);
	end
end

function AIController:GetBlackboardValueAsVector(key)
	if (nil ~= self.BlackboardComp) then
		return self.BlackboardComp:GetValueAsVector(key);
	end
end

function AIController:InitalizeBlackboard(BlackboardComp, BlackboardAsset)
	if (BlackboardComp and BlackboardComp:InitializeBlackboard(BlackboardAsset)) then
		return true;
	end

	return false;
end

function AIController:GetNumKeys()
	if(self.BlackboardComp) then
		return self.BlackboardComp:GetNumKeys();
	end
	return 0;
end

function AIController:GetKeyType(KeyID)
	if(self.BlackboardComp) then
		return self.BlackboardComp:GetKeyType(KeyID);
	end
	return 0;
end

function AIController:GetKeyID(KeyName)
	if(self.BlackboardComp) then
		self.BlackboardComp:GetKeyID(KeyName);
	end
	return -1;
end

function AIController:GetKeyName(KeyID)
	if(self.BlackboardComp) then
		return self.BlackboardComp:GetKeyName(KeyID);
	end
	return "";
end

function AIController:GetActorLocation()
	return Adapter.GetActorLocation(self.Pawn)
end

