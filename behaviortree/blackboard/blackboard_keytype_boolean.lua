local BlackboardKeyType = require("blackboard_keytype")


local BlackboardKeyType_Bool = {
    SupportedOp = BlackboardKeyType.EBlackboardKeyOperation.Basic
}

function BlackboardKeyType_Bool:InitializeMemory(OwnerComp, Memory, KeyID)
    Memory[KeyID] = false
end

function BlackboardKeyType_Bool:IsEmpty(OwnerComp, Memory, KeyID)
    return Memory[KeyID] == false
end

function BlackboardKeyType:Clear(OwnerComp, Memory, KeyID)
	Memory[KeyID] = false
end

function BlackboardKeyType_Bool:TestBasicOperation(OwnerComp, Memory, KeyID, Op)
	local Value = self:GetValue(self, Memory, KeyID);
	return (Op == BlackboardKeyType.EBasicKeyOperation.Set) and Value or not Value;
end

return class(BlackboardKeyType_Bool, { InvalidValue = false }, BlackboardKeyType)