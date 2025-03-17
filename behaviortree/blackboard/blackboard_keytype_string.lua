local BlackboardKeyType = require("blackboard_keytype")

local BlackboardKeyType_String = {
    SupportedOp = BlackboardKeyType.EBlackboardKeyOperation.Text
}

function BlackboardKeyType_String:TestTextOperation(OwnerComp, Memory, KeyID, Op, OtherString)
	local StringValue = self:GetValue(self, Memory, KeyID)
	if Op == BlackboardKeyType.ETextKeyOperation.Equal then
		return StringValue == OtherString
	elseif Op == BlackboardKeyType.ETextKeyOperation.NotEqual then
		return StringValue ~= OtherString
	elseif Op == BlackboardKeyType.ETextKeyOperation.Contain then
		return string.find(StringValue, OtherString) > 0
	elseif Op == BlackboardKeyType.ETextKeyOperation.NotContain then
		return string.find(StringValue, OtherString) == 0
	end

	return false;
end

function BlackboardKeyType_String:Clear(OwnerComp, Memory, KeyID)
	Memory[KeyID] = ""
end

function BlackboardKeyType_String:InitializeMemory(OwnerComp, Memory, KeyID)
	Memory[KeyID] = ""
end

function BlackboardKeyType_String:IsEmpty(OwnerComp, Memory, KeyID)
	return Memory[KeyID] ~= ""
end

return class(BlackboardKeyType_String, { InvalidValue = "" }, BlackboardKeyType)