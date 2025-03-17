local BlackboardKeyType = require("blackboard_keytype")


local BlackboardKeyType_Object = {
    SupportedOp = BlackboardKeyType.EBlackboardKeyOperation.Basic
}

function BlackboardKeyType_Object:TestBasicOperation(OwnerComp, Memory, KeyID, Op)
	local Value = self:GetValue(self, Memory, KeyID);
	return (Op == BlackboardKeyType.EBasicKeyOperation.Set) and Value or not Value;
end

return class(BlackboardKeyType_Object, { InvalidValue = nil }, BlackboardKeyType)