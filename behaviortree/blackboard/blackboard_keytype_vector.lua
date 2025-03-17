local BlackboardKeyType = require("blackboard_keytype")
local Utils = require("library.Utils")
local AITypes = require("ai.ai_types")


local InvalidValue = Utils.table.deepcopy(AITypes.FAISystem.InvalidLocation)

local BlackboardKeyType_Vector = {
    SupportedOp = BlackboardKeyType.EBlackboardKeyOperation.Basic;
}


function BlackboardKeyType_Vector:GetValue(KeyOb, Memory, KeyID)
    return Utils.table.deepcopy(Memory[KeyID])
end

function BlackboardKeyType_Vector:SetValue(KeyOb, Memory, KeyID, Value)
    local bChanged =Utils.table.compare(Memory[KeyID], Value)
    Memory[KeyID] = Utils.table.deepcopy(Value)
	return bChanged
end

function BlackboardKeyType_Vector:CompareValues(OwnerComp, Memory, KeyID, OtherKeyOb, OtherKeyID)
	local MyValue = self:GetValue(self, Memory, KeyID);
	local OtherValue = self:GetValue(OtherKeyOb, Memory, OtherKeyID);

	return Utils.table.compare(MyValue, OtherValue) and BlackboardKeyType.EBlackboardCompare.Equal or BlackboardKeyType.EBlackboardCompare.NotEqual;
end

function BlackboardKeyType_Vector:Clear(OwnerComp, Memory, KeyID)
	Memory[KeyID] = Utils.table.deepcopy(InvalidValue)
end

function BlackboardKeyType_Vector:IsEmpty(OwnerComp, Memory, KeyID)
	local Location = self:GetValue(self, Memory, KeyID);
	return not AITypes.FAISystem.IsValidLocation(Location);
end

function BlackboardKeyType_Vector:GetLocation(OwnerComp, Memory, KeyID, Location)
	Utils.table.deepcopy(self:GetValue(self, Memory, KeyID), Location)
	return AITypes.FAISystem.IsValidLocation(Location);
end

function BlackboardKeyType_Vector:InitializeMemory(OwnerComp, Memory, KeyID)
	Memory[KeyID] = Utils.table.deepcopy(InvalidValue)
end

function BlackboardKeyType_Vector:TestBasicOperation(OwnerComp, Memory, KeyID, Op)
	local Location = self:GetValue(self, Memory, KeyID);
	return (Op == BlackboardKeyType.EBasicKeyOperation.Set) and AITypes.FAISystem.IsValidLocation(Location) or not AITypes.FAISystem.IsValidLocation(Location);
end

return class(BlackboardKeyType_Vector, {InvalidValue = InvalidValue}, BlackboardKeyType)