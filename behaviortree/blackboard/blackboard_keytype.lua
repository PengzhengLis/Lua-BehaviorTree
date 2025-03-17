
local EBlackboardCompare = {
	Less = -1, 	
	Equal = 0, 
	Greater = 1,

	NotEqual = 1,
}

local EBlackboardKeyOperation = {
	Basic = 0,
	Arithmetic = 1,
	Text = 2,
}

local EBasicKeyOperation = {
	Set = 0,
	NotSet = 1,
}

local EArithmeticKeyOperation = {
	Equal = 0,
	NotEqual = 1,
	Less = 2,
	LessOrEqual = 3,
	Greater = 4,
	GreaterOrEqual = 5,
}

local ETextKeyOperation = {
	Equal = 0,
	NotEqual = 1,
	Contain = 2,
	NotContain = 3,
}

local FBlackboardInstancedKeyMemory = {
	KeyIdx = 0,
};

local statics = {
    EBlackboardCompare = EBlackboardCompare,
    EBlackboardKeyOperation = EBlackboardKeyOperation,
    EBasicKeyOperation = EBasicKeyOperation,
    EArithmeticKeyOperation = EArithmeticKeyOperation,
    ETextKeyOperation = ETextKeyOperation,
    FBlackboardInstancedKeyMemory = class(FBlackboardInstancedKeyMemory),
}

local BlackboardKeyType = {
    SupportedOp = EBlackboardKeyOperation.Basic,
    bIsInstanced = false,
    bCreateKeyInstance = false,
}

function BlackboardKeyType:GetTestOperation()
	return self.SupportedOp; 
end

function BlackboardKeyType:HasInstance()
	return self.bCreateKeyInstance;
end

function BlackboardKeyType:IsInstanced()
	return self.bIsInstanced;
end

function BlackboardKeyType:InitializeKey(OwnerComp, Memory, KeyID)
	if (self.bCreateKeyInstance) then
		local KeyInstance = self()
		KeyInstance.bIsInstanced = true;
		OwnerComp.KeyInstances[KeyID] = KeyInstance;

		KeyInstance:InitializeMemory(OwnerComp, Memory, KeyID);
	else
		self:InitializeMemory(OwnerComp, Memory, KeyID);
	end
end

function BlackboardKeyType:GetKeyInstance(OwnerComp, KeyID)
	return OwnerComp.KeyInstances[KeyID];
end

function BlackboardKeyType:InitializeMemory(OwnerComp, Memory, KeyID)
	-- empty in base class
end

function BlackboardKeyType:WrappedFree(OwnerComp, Memory, KeyID)
	if (self:HasInstance()) then
		local InstancedKey = self:GetKeyInstance(OwnerComp, KeyID);
		InstancedKey:FreeMemory(OwnerComp, Memory, KeyID);
	end

	return self:FreeMemory(OwnerComp, Memory, KeyID);
end

function BlackboardKeyType:FreeMemory(OwnerComp, Memory, KeyID)
	Memory[KeyID] = nil
end

function BlackboardKeyType:WrappedClear(OwnerComp, Memory, KeyID)
	if (self:HasInstance()) then
		local InstancedKey = self:GetKeyInstance(OwnerComp, KeyID);
		InstancedKey:Clear(OwnerComp, Memory, KeyID);
	else
		self:Clear(OwnerComp, Memory, KeyID);
	end
end

function BlackboardKeyType:Clear(OwnerComp, Memory, KeyID)
	Memory[KeyID] = nil
end

function BlackboardKeyType:WrappedIsEmpty(OwnerComp, Memory, KeyID)
	if (self:HasInstance()) then
		local InstancedKey = self:GetKeyInstance(OwnerComp, KeyID);
		return InstancedKey:IsEmpty(OwnerComp, Memory, KeyID);
	end

	return self:IsEmpty(OwnerComp, Memory, KeyID);
end

function BlackboardKeyType:IsEmpty(OwnerComp, Memory, KeyID)
	return Memory[KeyID] == nil
end

function BlackboardKeyType:WrappedTestBasicOperation(OwnerComp, Memory, KeyID, Op)
	if (self:HasInstance()) then
		local InstancedKey = self:GetKeyInstance(OwnerComp, KeyID);
		return InstancedKey:TestBasicOperation(OwnerComp, Memory, KeyID, Op);
	end

	return self:TestBasicOperation(OwnerComp, Memory, KeyID, Op);
end

function BlackboardKeyType:TestBasicOperation(OwnerComp, Memory, KeyID, Op)
	return false;
end

function BlackboardKeyType:WrappedTestArithmeticOperation(OwnerComp, Memory, KeyID, Op, OtherValue)
	if (self:HasInstance()) then
		local InstancedKey = self:GetKeyInstance(OwnerComp, KeyID);
		return InstancedKey:TestArithmeticOperation(OwnerComp, Memory, KeyID, Op, OtherValue);
	end

	return self:TestArithmeticOperation(OwnerComp, Memory, KeyID, Op, OtherValue);
end

function BlackboardKeyType:TestArithmeticOperation(OwnerComp, Memory, KeyID, Op, OtherValue)
	return false;
end

function BlackboardKeyType:WrappedTestTextOperation(OwnerComp, Memory, KeyID, Op, OtherString)
	if (self:HasInstance()) then
		local InstancedKey = self:GetKeyInstance(OwnerComp, KeyID);
		return InstancedKey:TestTextOperation(OwnerComp, Memory, KeyID, Op, OtherString);
	end

	return self:TestTextOperation(OwnerComp, Memory, KeyID, Op, OtherString);
end

function BlackboardKeyType:TestTextOperation(OwnerComp, Memory, KeyID, Op, OtherString)
	return false;
end

function BlackboardKeyType:CopyValues(Memory, KeyID, SourceKeyOb, SourceMemory, SourceKeyID)
	Memory[KeyID] = SourceMemory[SourceKeyID]
end

function BlackboardKeyType:GetValue(KeyOb, Memory, KeyID)
	return Memory[KeyID]
end

function BlackboardKeyType:SetValue(KeyOb, Memory, KeyID, Value)
	local bChanged = Memory[KeyID] ~= Value
    Memory[KeyID] = Value
	return bChanged
end

function BlackboardKeyType:CompareValues(OwnerComp, Memory, KeyID, OtherKeyOb, OtherKeyID)
	local MyValue = self:GetValue(self, Memory, KeyID);
	local OtherValue = self:GetValue(OtherKeyOb, Memory, OtherKeyID);

	return (MyValue == OtherValue) and EBlackboardCompare.Equal or EBlackboardCompare.NotEqual;
end

return class(BlackboardKeyType, statics)