local BlackboardKeyType_Object = require("behaviortree.blackboard.blackboard_keytype_object")
local BlackboardKeyType_Vector = require("behaviortree.blackboard.blackboard_keytype_vector")
local BTDecorator_BlackboardBase = require("bt_decorator_blackboardbase")
local AITypes = require("ai.ai_types")
local Adapter = require("library.adapter")

local BTDecorator_IsAtLocation = {
    AcceptableRadius = 50.0,
    GeometricDistanceType = AITypes.FAIDistanceType.Distance3D
}

function BTDecorator_IsAtLocation:constructor(args)
    BTDecorator_BlackboardBase.constructor(self, args)

    self.AcceptableRadius = args.AcceptableRadius
    self.GeometricDistanceType = args.GeometricDistanceType
end


function BTDecorator_IsAtLocation:GetGeometricDistanceSquared(A, B)
	local Result = AITypes.FLT_MAX;
    if self.GeometricDistanceType == AITypes.FAIDistanceType.Distance3D then
        Result = (A.X-B.X)*(A.X-B.X) + (A.Y-B.Y)*(A.Y-B.Y) + (A.Z-B.Z)*(A.Z-B.Z)
    elseif self.GeometricDistanceType == AITypes.FAIDistanceType.Distance2D then
        Result = (A.X-B.X)*(A.X-B.X) + (A.Y-B.Y)*(A.Y-B.Y)
    elseif self.GeometricDistanceType == AITypes.FAIDistanceType.DistanceZ then
        Result = (A.Z-B.Z)*(A.Z-B.Z)
    end

	return Result;
end

function BTDecorator_IsAtLocation:CalculateRawConditionValue(OwnerComp, NodeMemory)
	local bHasReached = false;

	local AIOwner = OwnerComp:GetAIOwner();
	local MyBlackboard = OwnerComp:GetBlackboardComponent();
	local Radius = self.AcceptableRadius;

	if (self.BlackboardKey.SelectedKeyType == BlackboardKeyType_Object) then
		local KeyValue = MyBlackboard:GetValue(self.BlackboardKey:GetSelectedKeyID());
        local TargetActor = KeyValue
		
		bHasReached = self:GetGeometricDistanceSquared(AIOwner:GetActorLocation(), Adapter.GetActorLocation(TargetActor)) < Radius * Radius

	elseif (self.BlackboardKey.SelectedKeyType == BlackboardKeyType_Vector) then
		local TargetLocation = MyBlackboard:GetValue(self.BlackboardKey:GetSelectedKeyID());
		if (AITypes.FAISystem.IsValidLocation(TargetLocation)) then
			bHasReached = self:GetGeometricDistanceSquared(AIOwner:GetActorLocation(), TargetLocation) < Radius * Radius
        end
    end

	return bHasReached;
end

return class(BTDecorator_IsAtLocation, {}, BTDecorator_BlackboardBase)