
local BlackboardKeyType = require("blackboard_keytype")

local BlackboardKeyType_Class = {
    SupportedOp = BlackboardKeyType.EBlackboardKeyOperation.Basic;
}

function BlackboardKeyType_Class:TestBasicOperation(OwnerComp, Memory, KeyID, Op)
	local Value = self:GetValue(self, Memory, KeyID);
	return (Op == BlackboardKeyType.EBasicKeyOperation.Set) and Value or not Value;
end

return class(BlackboardKeyType_Class, { InvalidValue = nil }, BlackboardKeyType)