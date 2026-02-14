
local utils = require("utils")
local LoadBalancer = require("classLoadBalancer")

-- mainly for recurring tasks
-- projects like maintaining a tree farm 

local RecurringProject = {}
RecurringProject.__index = RecurringProject

local tableinsert = table.insert
local osEpoch = os.epoch

local default = {

}

function RecurringProject:new(name, interval)
    local o = {}
    setmetatable(o, self)
    o.name = name
    o.metrics = {
        totalProcessed = 0,
        totalRuntime = 0,
        avgTimePerItem = 0,
    }
    o.assignments = {} -- [turtleId] = items

    o.balancer = LoadBalancer:new(global.taskManager)

    o.lastRebalance = osEpoch()
    o.itemInterval = interval
    o.executionInterval = interval
    o.acceptableDrift = interval * 2

    return o
end

function RecurringProject:getAllItems()
    local all = {}
    for tid, ass in pairs(self.assignments) do 
        local items = ass.items
        if items then
            for i = 1, #items do 
                tableinsert(all, items[i])
            end
        end
    end
    return all
end
function RecurringProject:getAssignedTurtles()
    local assigned = {}
    local turtles = global.turtles
    for tid, ass in pairs(self.assignments) do
        tableinsert(assigned, turtles[tid])
    end
    return assigned
end

function RecurringProject:handleReport(report)
    if report.project ~= self.name then 
        print("report project mismatch", report.project, self.name)
        return
    end

    local timestamp = report.timestamp
    local processed = report.processed
    local runtime = report.runtime
    local turtleId = report.turtleId
    local items = report.items
    local taskId = report.taskId    
    -- overall metrics
    local metrics = self.metrics
    metrics.totalProcessed = metrics.totalProcessed + processed
    metrics.totalRuntime = metrics.totalRuntime + runtime
    if metrics.totalProcessed > 0 then
        metrics.avgTimePerItem = metrics.totalRuntime / metrics.totalProcessed
    end


    local itemCount = items and #items or 0
    if itemCount == 0 then self.assignments[turtleId] = nil; return end

    local assignment = self.assignments[turtleId]
    if not assignment then assignment = { metrics = {} }; self.assignments[turtleId] = assignment end
    

    assignment.items = items
    -- do we want to check if the items changed?

    assignment.lastReportTime = timestamp
    assignment.lastTaskId = taskId

    -- assignment metrics
    local ametrics = assignment.metrics
    ametrics.totalProcessed = (ametrics.totalProcessed or 0) + processed
    ametrics.totalRuntime = (ametrics.totalRuntime or 0) + runtime
    if ametrics.totalProcessed > 0 then
        ametrics.avgTimePerItem = ametrics.totalRuntime / ametrics.totalProcessed
    end

    
    -- check if turtle is falling behind
    local now = osEpoch()
    assignment.lateBy = runtime - self.executionInterval
    assignment.behind = assignment.lateBy > self.acceptableDrift


    local utilization = ( itemCount * ( ametrics.avgTimePerItem or 0 ) ) / self.itemInterval
    assignment.utilization = utilization

    local rebalance = false
    if utilization > 1 or utilization < 0.5 then
        rebalance = now - self.lastRebalance > self.executionInterval *  3
    end
    print("turtle", turtleId, "utilization", utilization, "proj util", (metrics.avgTimePerItem * itemCount) / self.itemInterval, "rebalance", rebalance)
    print("turt avg", ametrics.avgTimePerItem, "proj avg", metrics.avgTimePerItem)

    local unassigned = {}
    local respawnTask, reassignments = true, nil
    if rebalance then
        self.lastRebalance = now
        reassignments = self.balancer:balanceProject(self)
        
        -- what turtles have been removed?
        local assigned = self:getAssignedTurtles()
        for i = 1, #assigned do 
            local tid = assigned[i].state.id
            local ass = self.assignments[tid]
            unassigned[tid] = ass
        end
        for tid, items in pairs(reassignments) do
            unassigned[tid] = nil
        end

        respawnTask = false -- host spawned new tasks
    end

    return respawnTask, reassignments, unassigned
end


return RecurringProject