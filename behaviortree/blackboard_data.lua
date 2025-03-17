local BehaviorTreeTypes = require("behavior_tree_types")


local FBlackboardEntry = {
    EntryName = "",
    KeyType = nil,
    bInstanceSynced = false,
}

function FBlackboardEntry:constructor()
	local mt = getmetatable(self)
	mt.__eq = function(a, b)
		return (a.EntryName == b.EntryName) and
		((a.KeyType and b.KeyType and getclass(a.KeyType) == getclass(b.KeyType)) or (not a.KeyType and not b.KeyType));
	end
end

local statics = {
	FBlackboardEntry = class(FBlackboardEntry)
}

local BlackboardData = {
	Parent = nil,
	Keys = {},
	bHasSynchronizedKeys = false,

	FirstKeyID = 0,
}

function BlackboardData:HasSynchronizedKeys()
	return self.bHasSynchronizedKeys;
end

function BlackboardData:GetFirstKeyID()
	return self.FirstKeyID;
end

function BlackboardData:GetKeys()
	return self.Keys;
end

function BlackboardData:IsRelatedTo(OtherAsset)
	return self == OtherAsset or self:IsChildOf(OtherAsset) or OtherAsset:IsChildOf(self)
			or (self.Parent and OtherAsset.Parent and self.Parent:IsRelatedTo(OtherAsset.Parent));
end

function BlackboardData:GetKeyID(KeyName)
	for KeyIndex = 1, #self.Keys do
		if (self.Keys[KeyIndex].EntryName == KeyName) then
			return KeyIndex + self.FirstKeyID;
		end
	end
	
	return self.Parent and self.Parent:GetKeyID(KeyName) or BehaviorTreeTypes.FBlackboard.InvalidKey;
end


function BlackboardData:GetKeyName(KeyID)
	local KeyEntry = self:GetKey(KeyID);
	return KeyEntry and KeyEntry.EntryName or "";
end

function BlackboardData:GetKeyType(KeyID)
	local KeyEntry = self:GetKey(KeyID);
	return KeyEntry and KeyEntry.KeyType and getclass(KeyEntry.KeyType) or nil;
end

function BlackboardData:IsKeyInstanceSynced(KeyID)
	local KeyEntry = self:GetKey(KeyID);
	return KeyEntry and KeyEntry.bInstanceSynced or false;
end

function BlackboardData:GetKey(KeyID)
	if (KeyID ~= BehaviorTreeTypes.FBlackboard.InvalidKey) then
		if (KeyID >= self.FirstKeyID) then
			return self.Keys[KeyID - self.FirstKeyID];
		elseif (self.Parent) then
			return self.Parent:GetKey(KeyID);
		end
	end

	return nil;
end

function BlackboardData:GetNumKeys()
	return self.FirstKeyID + #self.Keys;
end

function BlackboardData:UpdateIfHasSynchronizedKeys()
	self.bHasSynchronizedKeys = self.Parent and self.Parent.bHasSynchronizedKeys;
	for KeyIndex = 1, #self.Keys do
		if self.bHasSynchronizedKeys then
			break
		end

		if self.Keys[KeyIndex].bInstanceSynced then
			self.bHasSynchronizedKeys = true;
		end
		
	end
end

function BlackboardData:UpdateKeyIDs()
	self.FirstKeyID = self.Parent and self.Parent:GetNumKeys() or 1;
end

function BlackboardData:IsChildOf(OtherAsset)
	local TmpParent = self.Parent;
	
	while (TmpParent and TmpParent ~= OtherAsset) do
		TmpParent = TmpParent.Parent;
	end

	return (TmpParent == OtherAsset);
end


return class(BlackboardData, statics)