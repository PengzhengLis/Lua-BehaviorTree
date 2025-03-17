
local AIController = require("ai.ai_controller")

local FAIMessage = {
    
	Failure = 0,
	Success = 1,

    MessageType = 0,
    Sender = nil,
}

function FAIMessage:constructor(...)
    local arg = {...}
    if #arg == 1 then
        self.MessageType = arg[1].MessageType
        self.Sender = arg[1].Sender
    elseif #arg == 2 then
        self.MessageType = arg[1]
        self.Sender = arg[2]
    end
    
end

function FAIMessage.Send(ControllerOrBrainComp, Message)
    local BrainComp = ControllerOrBrainComp
    if instanceof(ControllerOrBrainComp, AIController) then
        BrainComp = ControllerOrBrainComp:GetBrainComponent();
    end

    BrainComp:HandleMessage(Message)
end

local FAIMessageObserver = {
    MessageType = 0,
    Observer = nil,
    Owner = nil,
}

function FAIMessageObserver:constructor(BrainComp, MessageType, Delegate)
    self.MessageType = MessageType;
    self.ObserverDelegate = Delegate;
    self.Owner = BrainComp
    table.insert(self.Owner.MessageObservers, self)
end

function FAIMessageObserver:dtor()
    table.remove(self.Owner.MessageObservers, self)
end

function FAIMessageObserver:OnMessage(Message)
    if (Message.MessageType == self.MessageType) then
        self.ObserverDelegate(self.Owner, Message);
    end
end


local BrainComponent = {
    BlackboadComp = nil,
    AIOwner = nil,
    MessageToProcess = {},
}

function BrainComponent:HandleMessage(Message)
    table.insert(self.MessageToProcess, Message)
end

function BrainComponent:TickComponent(DeltaTime)
	if (#self.MessageToProcess > 0) then
		for Idx = 1, #self.MessageToProcess do
			-- 防止消息处理过程中被改变
			local MessageCopy = self.MessageToProcess[Idx]()

			for ObserverIndex = 1, #self.MessageObserver do
				self.MessageObserver[ObserverIndex]:OnMessage(self, MessageCopy);
			end
		end

		self.MessageToProcess = {}
	end
end

function BrainComponent:CacheBlackboardComponent(BBComp)
	if (BBComp) then
		self.BlackboadComp = BBComp;
	end
end

function BrainComponent:GetBlackboardComponent()
	return self.BlackboadComp;
end

function BrainComponent:SetAIOwner(AIOwner)
    self.AIOwner = AIOwner
end

function BrainComponent:GetAIOwner()
    return self.AIOwner
end

local statics = { FAIMessage = FAIMessage, FAIMessageObserver = FAIMessageObserver}
return class(BrainComponent, statics)