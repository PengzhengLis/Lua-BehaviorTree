local Utils = require("library.Utils")

local AISystem = {
    BehaviorTreeManager = nil,
    BlackboardDataToComponentsMap = nil
}

function AISystem:constructor()
    self.BlackboardDataToComponentsMap = {}
end

function AISystem:RegisterBlackboardComponent(BlackboardData, BlackboardComp)

    if not self.BlackboardDataToComponentsMap[BlackboardData] then
        self.BlackboardDataToComponentsMap[BlackboardData] = {}
    end

    local tab = self.BlackboardDataToComponentsMap[BlackboardData]
    table.insert(tab, BlackboardComp)

    if BlackboardData.Parent then
        self:RegisterBlackboardComponent(BlackboardData.Parent, BlackboardComp)
    end
end

function AISystem:UnregisterBlackboardComponent(BlackboardData, BlackboardComp)
    if BlackboardData.Parent then
        self:UnregisterBlackboardComponent(BlackboardData.Parent, BlackboardComp)
    end

    Utils.array.remove(self.BlackboardDataToComponentsMap[BlackboardData], BlackboardComp)
end

function AISystem:GetBlackboardComponents(BlackboardData, tab)
    tab = tab or {}

    Utils.array.concat(tab, self.BlackboardDataToComponentsMap[BlackboardData])

    if BlackboardData.Parent then
        self:GetBlackboardComponents(BlackboardData.Parent, tab)
    end
end

return AISystem