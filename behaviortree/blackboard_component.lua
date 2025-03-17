local BehaviorTreeTypes = require("behavior_tree_types")
local AiSystem = require("ai_system")
local Utils = require("library.Utils")
local BlackboardKeyType_Bool = require("ai.blackboard.blackboard_keytype_boolean")
local BlackboardKeyType_Class = require("ai.blackboard.blackboard_keytype_class")
local BlackboardKeyType_Number = require("ai.blackboard.blackboard_keytype_number")
local BlackboardKeyType_Object = require("ai.blackboard.blackboard_keytype_object")
local BlackboardKeyType_String = require("ai.blackboard.blackboard_keytype_string")
local BlackboardKeyType_Vector = require("ai.blackboard.blackboard_keytype_vector")

local BlackboardComponent = {
    BrainComp = nil,
    ValueMemory = {},
    KeyInstances = {},
    NotifyObserversRecursionCount = 0,
    ObserversToRemoveCount = 0,
    Observers = {},
    ObserverHandles = {},
    QueuedUpdates = {},
    bPausedNotifies = false,
    bSynchronizedKeyPopulated = false,
	BlackboardAsset = nil,
}


function BlackboardComponent:IsValidKey(KeyID) 
	return KeyID ~= BehaviorTreeTypes.FBlackboard.InvalidKey and self.BlackboardAsset.Keys[KeyID];
end

function BlackboardComponent:IsKeyOfType(KeyID, TDataClass)
	local EntryInfo = self.BlackboardAsset and self.BlackboardAsset:GetKey(KeyID) or nil;
	return (EntryInfo) and (EntryInfo.KeyType) and instanceof(EntryInfo.KeyType, TDataClass);
end

function BlackboardComponent:SetValue(KeyID, Value, TDataClass)
	if type(KeyID) == "string" then
		KeyID = self:GetKeyID(KeyID)
	end

	local EntryInfo = self.BlackboardAsset and self.BlackboardAsset:GetKey(KeyID) or nil
	if ((EntryInfo == nil) or (EntryInfo.KeyType == nil) or (getclass(EntryInfo.KeyType) ~= TDataClass)) then
		return false;
	end

	local KeyOb = EntryInfo.KeyType:HasInstance() and self.KeyInstances[KeyID] or EntryInfo.KeyType;
	local bChanged = TDataClass:SetValue(KeyOb, self.ValueMemory, KeyID, Value);
	if (bChanged) then
		self:NotifyObservers(KeyID);
		if (self.BlackboardAsset:HasSynchronizedKeys() and self:IsKeyInstanceSynced(KeyID)) then
			local tab = AiSystem:GetBlackboardComponents(self.BlackboardAsset)
			for i = 1, #tab do
				local OtherBlackboard = tab[i];
				if (OtherBlackboard ~= nil and self:ShouldSyncWithBlackboard(OtherBlackboard)) then
					local OtherBlackboardAsset = OtherBlackboard:GetBlackboardAsset();
					local OtherKeyID = OtherBlackboardAsset and OtherBlackboardAsset:GetKeyID(EntryInfo.EntryName) or BehaviorTreeTypes.FBlackboard.InvalidKey;
					local OtherKeyOb = EntryInfo.KeyType:HasInstance() and OtherBlackboard.KeyInstances[OtherKeyID] or EntryInfo.KeyType;

					TDataClass:SetValue(OtherKeyOb, OtherBlackboard.ValueMemory, OtherKeyID, Value);
					OtherBlackboard:NotifyObservers(OtherKeyID);
				end
			end
		end
	end

	return true;
end

function BlackboardComponent:GetValue(KeyID, TDataClass)
	if type(KeyID) == "string" then
		KeyID = self:GetKeyID(KeyID)
	end

	local EntryInfo = self.BlackboardAsset and self.BlackboardAsset:GetKey(KeyID) or nil;
	if ((EntryInfo == nil) or (EntryInfo.KeyType == nil) or (getclass(EntryInfo.KeyType) ~= TDataClass)) then
		return TDataClass.InvalidValue;
	end

	local KeyOb = EntryInfo.KeyType:HasInstance() and self.KeyInstances[KeyID] or EntryInfo.KeyType;
	return TDataClass:GetValue(KeyOb, self.ValueMemory, KeyID) or TDataClass.InvalidValue
end


function BlackboardComponent:UnInitializeBlackboard()
	if (self.BlackboardAsset and self.BlackboardAsset:HasSynchronizedKeys()) then
		AiSystem:UnregisterBlackboardComponent(self.BlackboardAsset, self);
	end

	self:DestroyValues();
end

function BlackboardComponent:CacheBrainComponent(BrainComponent)
	if (BrainComponent ~= self.BrainComp) then
		self.BrainComp = BrainComponent;
	end
end

function BlackboardComponent:InitializeParentChain(NewAsset)
	if (NewAsset) then
		self:InitializeParentChain(NewAsset.Parent);
		NewAsset:UpdateKeyIDs();
	end
end

function BlackboardComponent:InitializeBlackboard(NewAsset)
	if (NewAsset == self.BlackboardAsset) then
		return true;
	end

	if (self.BlackboardAsset and self.BlackboardAsset:HasSynchronizedKeys()) then
		AiSystem:UnregisterBlackboardComponent(self.BlackboardAsset, self);
		self:DestroyValues();
	end

	self.BlackboardAsset = NewAsset;
	self.ValueMemory = {}
	self.bSynchronizedKeyPopulated = false;

	local bSuccess = true;
	
	if (self.BlackboardAsset:IsValid()) then
		self:InitializeParentChain(self.BlackboardAsset);

		local InitList = {};
		local NumKeys = self.BlackboardAsset:GetNumKeys();

		local It = self.BlackboardAsset
		while (It) do
			for KeyIndex = 1, #It.Keys do
				local KeyType = It.Keys[KeyIndex].KeyType;
				if (KeyType) then
					KeyType:PreInitialize(self);
					KeyType:InitializeKey(self, self.ValueMemory, KeyIndex + It:GetFirstKeyID())
				end
			end

			It = It.Parent
		end

		if (self.BlackboardAsset:HasSynchronizedKeys()) then
			self:PopulateSynchronizedKeys();
		end
	else
		bSuccess = false;
	end

	return bSuccess;
end

function BlackboardComponent:DestroyValues()
	local It = self.BlackboardAsset
	while (It) do
		for KeyIndex = 1, #It.Keys do
			local KeyType = It.Keys[KeyIndex].KeyType;
			if (KeyType) then
				local UseIdx = KeyIndex + It:GetFirstKeyID();
				KeyType:WrappedFree(self, self.ValueMemory, UseIdx);
			end
		end

		It = It.Parent
	end

	self.ValueMemory = {}
end

function BlackboardComponent:PopulateSynchronizedKeys()
	AiSystem:RegisterBlackboardComponent(self.BlackboardAsset, self);

	local tab = AiSystem:GetBlackboardComponents(self.BlackboardAsset)
	for i = 1, #tab do
		local OtherBlackboard = tab[i]
		if (OtherBlackboard ~= nil and self:ShouldSyncWithBlackboard(OtherBlackboard)) then
			for j = 1, #self.BlackboardAsset.Keys do
				local Key = self.BlackboardAsset.Keys[j]
				if (Key.bInstanceSynced) then
					local OtherBlackboardAsset = OtherBlackboard:GetBlackboardAsset();
					local OtherKeyID = OtherBlackboardAsset and OtherBlackboardAsset:GetKeyID(Key.EntryName) or BehaviorTreeTypes.FBlackboard.InvalidKey;
					if (OtherKeyID ~= BehaviorTreeTypes.FBlackboard.InvalidKey) then

						local bKeyHasInstance = Key.KeyType:HasInstance();
						local KeyID = self.BlackboardAsset:GetKeyID(Key.EntryName);

						local KeyOb = bKeyHasInstance and self.KeyInstances[KeyID] or Key.KeyType;
						local SourceKeyOb = bKeyHasInstance and OtherBlackboard.KeyInstances[OtherKeyID] or Key.KeyType;

						KeyOb:CopyValues(self.ValueMemory, KeyID, SourceKeyOb, OtherBlackboard.ValueMemory, OtherKeyID);
					end
				end
			end
			break;
		end
	end

	self.bSynchronizedKeyPopulated = true;
end

function BlackboardComponent:ShouldSyncWithBlackboard(OtherBlackboardComponent)
	return OtherBlackboardComponent ~= self and (
		(self.BrainComp == nil or (self.BrainComp:GetAIOwner() ~= nil and BrainComp:GetAIOwner():ShouldSyncBlackboardWith(OtherBlackboardComponent) == true))
		or (OtherBlackboardComponent.BrainComp == nil or (OtherBlackboardComponent.BrainComp:GetAIOwner() ~= nil and OtherBlackboardComponent.BrainComp:GetAIOwner():ShouldSyncBlackboardWith(self) == true)));
end

function BlackboardComponent:GetBrainComponent()
	return self.BrainComp;
end

function BlackboardComponent:GetBlackboardAsset()
	return self.BlackboardAsset;
end

function BlackboardComponent:GetKeyName(KeyID)
	return self.BlackboardAsset and self.BlackboardAsset:GetKeyName(KeyID) or "";
end

function BlackboardComponent:GetKeyID(KeyName)
	return self.BlackboardAsset and self.BlackboardAsset:GetKeyID(KeyName) or BehaviorTreeTypes.FBlackboard.InvalidKey;
end

function BlackboardComponent:GetKeyType(KeyID)
	return self.BlackboardAsset and self.BlackboardAsset:GetKeyType(KeyID) or nil;
end

function BlackboardComponent:IsKeyInstanceSynced(KeyID)
	return self.BlackboardAsset and self.BlackboardAsset:IsKeyInstanceSynced(KeyID) or false;
end

function BlackboardComponent:GetNumKeys()
	return self.BlackboardAsset and self.BlackboardAsset:GetNumKeys() or 0;
end

function BlackboardComponent:GetObservers(KeyID)
	if self.Observers[KeyID] == nil then
		self.Observers[KeyID] = {}
	end
	return self.Observers[KeyID]
end

function BlackboardComponent:GetObserverHandles(NotifyOwner)
	if self.ObserverHandles[NotifyOwner] == nil then
		self.ObserverHandles[NotifyOwner] = {}
	end
	return self.ObserverHandles[NotifyOwner]
end

function BlackboardComponent:RegisterObserver(KeyID, NotifyOwner, ObserverDelegate)
	local Observers = self:GetObservers(KeyID)
	for i = 1, #Observers do
		if Observers[i] == ObserverDelegate then
			return ObserverDelegate
		end
	end

	table.insert(Observers, ObserverDelegate)

	local ObserverHandles = self:GetObserverHandles(NotifyOwner)
	table.insert(ObserverHandles, ObserverDelegate)

	return ObserverDelegate;
end

function BlackboardComponent:UnregisterObserver(KeyID, ObserverHandle)
	local Observers = self:GetObservers(KeyID)

	for i = 1, #Observers do
		if Observers[i] == ObserverHandle then
			for k, v in pairs(self.ObserverHandles) do
				for j = 1, #v do
					if v[j] == ObserverHandle then
						table.remove(v, j)
						break
					end
				end
			end

			if self.NotifyObserversRecursionCount == 0 then
				table.remove(Observers, i)
			elseif not Observers[i].bToBeRemoved then
				Observers[i].bToBeRemoved = true
				self.ObserversToRemoveCount = self.ObserversToRemoveCount + 1
			end

			break
		end
	end
end

function BlackboardComponent:UnregisterObserversFrom(NotifyOwner)
	local ObserverHandles = self:GetObserverHandles(NotifyOwner)
	for i = 1, #ObserverHandles do
		for k, v in pairs(self.Observers) do
			for j = 1, #v do
				if v[j] == ObserverHandles[i] then
					if self.NotifyObserversRecursionCount == 0 then
						table.remove(v, j)
					elseif not v[j].bToBeRemoved then
						v[j].bToBeRemoved = true
						self.ObserversToRemoveCount = self.ObserversToRemoveCount + 1
					end
					
					break
				end
			end
		end
	end

	self.ObserverHandles[NotifyOwner] = {}
end

function BlackboardComponent:PauseObserverNotifications()
	self.bPausedNotifies = true;
end

function BlackboardComponent:ResumeObserverNotifications(bSendQueuedObserverNotifications)
	self.bPausedNotifies = false;

	if (bSendQueuedObserverNotifications) then
		for UpdateIndex = 1, #self.QueuedUpdates do
			self:NotifyObservers(self.QueuedUpdates[UpdateIndex]);
		end
	end

	self.QueuedUpdates = {}
end

function BlackboardComponent:PauseUpdates()
	self.bPausedNotifies = true;
end

function BlackboardComponent:ResumeUpdates()
	self.bPausedNotifies = false;

	for UpdateIndex = 1, #self.QueuedUpdates do
		self:NotifyObservers(self.QueuedUpdates[UpdateIndex]);
	end

	self.QueuedUpdates = {}
end

function BlackboardComponent:NotifyObservers(KeyID)

	local Observers = self:GetObservers(KeyID)

	if (#Observers > 0) then
		if (self.bPausedNotifies) then
			table.insert(self.QueuedUpdates, KeyID);
		else
			self.NotifyObserversRecursionCount = self.NotifyObserversRecursionCount + 1
			for i = #Observers, 1, -1 do
				local ObserverDelegateInfo = Observers[i]
				if (not ObserverDelegateInfo.bToBeRemoved) then
					local ObserverDelegate = ObserverDelegateInfo.DelegateHandle;
					local bWantsToContinueObserving = ObserverDelegate and (ObserverDelegate(self, KeyID) == BehaviorTreeTypes.EBlackboardNotificationResult.ContinueObserving);

					if (not bWantsToContinueObserving) then
						if (not ObserverDelegateInfo.bToBeRemoved) then
							for k, v in pairs(self.ObserverHandles) do
								for j = 1, #v do
									if v[j] == ObserverDelegateInfo then
										table.remove(v, j)
										break
									end
								end
							end
						end

						if (self.NotifyObserversRecursionCount == 1) then
							table.remove(Observers, i)

							if (ObserverDelegateInfo.bToBeRemoved) then
								self.ObserversToRemoveCount = self.ObserversToRemoveCount - 1
							end
						elseif(not ObserverDelegateInfo.bToBeRemoved) then
							ObserverDelegateInfo.bToBeRemoved = true;
							self.ObserversToRemoveCount = self.ObserversToRemoveCount + 1
						end
					end
				end
		
				self.NotifyObserversRecursionCount = self.NotifyObserversRecursionCount - 1

				if (self.NotifyObserversRecursionCount == 0 and self.ObserversToRemoveCount > 0) then
					for k, v in pairs(self.Observers) do
						for j = #v, 1, -1 do
							if v[j].bToBeRemoved then
								table.remove(v, j)
								self.ObserversToRemoveCount = self.ObserversToRemoveCount - 1
								if self.ObserversToRemoveCount == 0 then
									break
								end
							end
						end

						if self.ObserversToRemoveCount == 0 then
							break
						end
					end

					self.ObserversToRemoveCount = 0;
				end
			end
		end
	end
end

function BlackboardComponent:IsCompatibleWith(TestAsset)
	local It = self.BlackboardAsset
	while (It) do
		if (It == TestAsset) then
			return true;
		end

		if (Utils.array.isEqual(It.Keys, TestAsset.Keys)) then
			return true;
		end

		It = It.Parent
	end

	return false;
end

function BlackboardComponent:CompareKeyValues(KeyType, KeyA, KeyB)
	local KeyAOb = self.KeyInstances[KeyA] and self.KeyInstances[KeyA] or KeyType;
	return KeyAOb:CompareValues(self, self.ValueMemory, KeyA, self.KeyInstances[KeyB], KeyB);
end


function BlackboardComponent:GetValueAsObject(KeyName)
	return self:GetValue(KeyName, BlackboardKeyType_Object);
end

function BlackboardComponent:GetValueAsClass(KeyName)
	return self:GetValue(KeyName, BlackboardKeyType_Class);
end

function BlackboardComponent:GetValueAsNumer(KeyName)
	return self:GetValue(KeyName, BlackboardKeyType_Number);
end

function BlackboardComponent:GetValueAsBool(KeyName)
	return self:GetValue(KeyName, BlackboardKeyType_Bool);
end

function BlackboardComponent:GetValueAsString(KeyName)
	return self:GetValue(KeyName, BlackboardKeyType_String);
end

function BlackboardComponent:GetValueAsVector(KeyName)
	return self:GetValue(KeyName, BlackboardKeyType_Vector);
end

function BlackboardComponent:SetValueAsObject(KeyName, ObjectValue)
	local KeyID = self:GetKeyID(KeyName);
	self:SetValue(KeyID, ObjectValue, BlackboardKeyType_Object);
end

function BlackboardComponent:SetValueAsClass(KeyName, ClassValue)
	local KeyID = self:GetKeyID(KeyName);
	self:SetValue(KeyID, ClassValue, BlackboardKeyType_Class);
end

function BlackboardComponent:SetValueAsNumber(KeyName, NumberValue)
	local KeyID = self:GetKeyID(KeyName);
	self:SetValue(KeyID, NumberValue, BlackboardKeyType_Number);
end

function BlackboardComponent:SetValueAsBool(KeyName, BoolValue)
	local KeyID = self:GetKeyID(KeyName);
	self:SetValue(KeyID, BoolValue, BlackboardKeyType_Bool);
end

function BlackboardComponent:SetValueAsString(KeyName, StringValue)
	local KeyID = self:GetKeyID(KeyName);
	self:SetValue(KeyID, StringValue, BlackboardKeyType_String);
end

function BlackboardComponent:SetValueAsVector(KeyName, VectorValue)
	local KeyID = self:GetKeyID(KeyName);
	self:SetValue(KeyID, VectorValue, BlackboardKeyType_Vector);
end

function BlackboardComponent:IsVectorValueSet(KeyID)
	if type(KeyID) == "string" then
		KeyID = self:GetKeyID(KeyID);
	end

	local VectorValue = self:GetValue(KeyID, BlackboardKeyType_Vector);
	return (VectorValue ~= AiSystem.InvalidLocation);
end

function BlackboardComponent:ClearValue(KeyID)
	if (self.BlackboardAsset == nil) then
		return;
	end

	if type(KeyID) == "string" then
		KeyID = self:GetKeyID(KeyID);
	end

	local EntryInfo = self.BlackboardAsset:GetKey(KeyID);
	local bHasData = (EntryInfo.KeyType:WrappedIsEmpty(self, self.ValueMemory, KeyID) == false);
	if (bHasData) then
		EntryInfo.KeyType:WrappedClear(self, self.ValueMemory, KeyID);
		self:NotifyObservers(KeyID);

		if (self.BlackboardAsset:HasSynchronizedKeys() and self:IsKeyInstanceSynced(KeyID)) then
			local bKeyHasInstance = EntryInfo.KeyType:HasInstance();

			local KeyOb = bKeyHasInstance and self.KeyInstances[KeyID] or EntryInfo.KeyType;

			local tab = AiSystem:GetBlackboardComponents(self.BlackboardAsset)
			for i = 1, #tab do
				local OtherBlackboard = tab[i]
				if OtherBlackboard and self:ShouldSyncWithBlackboard(OtherBlackboard) then
					local OtherBlackboardAsset = OtherBlackboard:GetBlackboardAsset()
					local OtherKeyID = OtherBlackboardAsset and OtherBlackboardAsset:GetKeyID(EntryInfo.EntryName) or BehaviorTreeTypes.FBlackboard.InvalidKey;

					if OtherKeyID ~= BehaviorTreeTypes.FBlackboard.InvalidKey then
						local OtherEntryInfo = OtherBlackboard.BlackboardAsset:GetKey(OtherKeyID);
						local OtherKeyOb = bKeyHasInstance and OtherBlackboard.KeyInstances[OtherKeyID] or EntryInfo.KeyType;
					
						OtherKeyOb:CopyValues(OtherBlackboard.ValueMemory, OtherKeyID, KeyOb, self.ValueMemory, KeyID);
						OtherBlackboard:NotifyObservers(OtherKeyID);
					end
				end
			end
		end
	end
end

function BlackboardComponent:CopyKeyValue(SourceKeyID, DestinationKeyID)
	local BBAsset = self:GetBlackboardAsset();
	if (BBAsset == nil) then
		return false;
	end

	if (#self.ValueMemory == 0) then
		return false;
	end

	local SourceValueEntryInfo = BBAsset:GetKey(SourceKeyID);
	local DestinationValueEntryInfo = BBAsset:GetKey(DestinationKeyID);

	if (SourceValueEntryInfo == nil or DestinationValueEntryInfo == nil or SourceValueEntryInfo.KeyType == nil or DestinationValueEntryInfo.KeyType == nil) then
		return false;
	end

	if (SourceValueEntryInfo.KeyType:GetClass() ~= DestinationValueEntryInfo.KeyType:GetClass()) then
		return false;
	end

	local bKeyHasInstance = SourceValueEntryInfo.KeyType:HasInstance();

	local SourceKeyOb = bKeyHasInstance and self.KeyInstances[SourceKeyID] or SourceValueEntryInfo.KeyType;
	local DestKeyOb = bKeyHasInstance and self.KeyInstances[DestinationKeyID] or DestinationValueEntryInfo.KeyType;

	DestKeyOb:CopyValues(self.ValueMemory, DestinationKeyID, SourceKeyOb, self.ValueMemory, SourceKeyID);

	return true;
end

local FOnBlackboardChangeNotificationInfo = {
	DelegateHandle = nil,
	bToBeRemoved = false,
}

function FOnBlackboardChangeNotificationInfo:constructor(delegate)
	self.DelegateHandle = delegate
end

local statics = {
	FOnBlackboardChangeNotificationInfo = class(FOnBlackboardChangeNotificationInfo)
}


return class(BlackboardComponent, statics)