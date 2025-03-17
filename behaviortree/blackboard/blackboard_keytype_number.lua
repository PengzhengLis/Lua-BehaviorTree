local BlackboardKeyType = require("blackboard_keytype")

local BlackboardKeyType_Number = {
    SupportedOp = BlackboardKeyType.EBlackboardKeyOperation.Arithmetic
}

function BlackboardKeyType_Number:InitializeMemory(OwnerComp, Memory, KeyID)
    Memory[KeyID] = 0
end

function BlackboardKeyType_Number:IsEmpty(OwnerComp, Memory, KeyID)
    return Memory[KeyID] == 0
end

function BlackboardKeyType:Clear(OwnerComp, Memory, KeyID)
	Memory[KeyID] = 0
end

function BlackboardKeyType_Number:CompareValues(OwnerComp, Memory, KeyID, OtherKeyOb, OtherKeyID)

	local MyValue = self:GetValue(self, Memory, KeyID);
	local OtherValue = self:GetValue(OtherKeyOb, Memory, OtherKeyID);

	return (MyValue > OtherValue) and BlackboardKeyType.EBlackboardCompare.Greater or
		(MyValue < OtherValue) and BlackboardKeyType.EBlackboardCompare.Less or
		BlackboardKeyType.EBlackboardCompare.Equal;
end

function BlackboardKeyType_Number:TestArithmeticOperation(OwnerComp, Memory, KeyID, Op, OtherValue)
	local Value = self:GetValue(self, Memory, KeyID);

    if Op == BlackboardKeyType.EArithmeticKeyOperation.Equal then
        return Value == OtherValue
    elseif Op == BlackboardKeyType.EArithmeticKeyOperation.NotEqual then
        return Value ~= OtherValue
    elseif Op == BlackboardKeyType.EArithmeticKeyOperation.Less then
        return Value < OtherValue
    elseif Op == BlackboardKeyType.EArithmeticKeyOperation.LessOrEqual then
        return Value <= OtherValue
    elseif Op == BlackboardKeyType.EArithmeticKeyOperation.Greater then
        return Value > OtherValue
    elseif Op == BlackboardKeyType.EArithmeticKeyOperation.GreaterOrEqual then
        return Value >= OtherValue
    end

	return false;
end

return class(BlackboardKeyType_Number, {InvalidValue = 0}, BlackboardKeyType)