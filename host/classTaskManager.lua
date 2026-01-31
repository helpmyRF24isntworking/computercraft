
local TaskAssignment = require("classTaskAssignment")

local TaskManager = {}
TaskManager.__index = TaskManager
--TODO: classTaskManager on host
-- keeps track of all assignments and groups 
-- restarts tasks if needed, assigns new tasks to idle turtles etc.
-- can restart whole groups if needed
-- handles callbacks from turtles etc.

function TaskManager:new()
    local o = {}
    setmetatable(o, self)

    o.groups = {} 
    o.assignments = {}
    o.turtleAssignments = {} -- map turtleIds to assignmentIds
    o.cancelledTasks = {}

    o:initialize()
    return o
end

function TaskManager:initialize()
    -- initialize task manager
end


function TaskManager:handleMessage(msg)
-- TODO: also have a message handler
end


function TaskManager:addTask(task)
    task:setTaskManager(self)
    self.assignments[task:getId()] = task
    self.turtleAssignments[task:getTurtleId()] = task
end
function TaskManager:removeTask(task)
    self.assignments[task:getId()] = nil
    self.turtleAssignments[task:getTurtleId()] = nil
end

function TaskManager:getTurtleTasks(turtleId)
    return self.turtleAssignments[turtleId]
end

function TaskManager:createTask(turtleId, groupId)
    local task = TaskAssignment:new(turtleId, groupId)
    self:addTask(task)
    return task
end

function TaskManager:addTaskToTurtle(turtleId, funcName, args)
    -- find an assignment for the turtle or create a new one
    -- check if turtle already has an assignment?
    local turtleTasks = self:getTurtleTasks(turtleId)

    local task = self:createTask(turtleId, nil)
    task:setFunction(funcName)
    task:setFunctionArguments(args)
    if not task:start() then
        self:removeTask(task)
        return nil
    end
    return task
end

-- direct funcitons
function TaskManager:callTurtleHome(turtleId)
    -- find task for turtle and set it to return home
    return self:addTaskToTurtle(turtleId, "returnHome", {})
end
function TaskManager:cancelTask(task)
    -- mark task as abandoned, so it wont be restarted
    if task:cancel() then
        self.cancelledTasks[task:getId()] = task
        self:removeTask(task)
        return true
    else
        return false
    end
end

function TaskManager:rebootTurtle(turtleId)
    -- find task for turtle and set it to reboot
    local tasksCancelled = true
    local turtleTasks = self:getTurtleTasks(turtleId)
    -- maybe also request turtle task
    for id, task in pairs(turtleTasks) do
        -- prepare tasks for reboot -- put them on ice, but dont delete them
        if not self:cancelTask(task) then 
            tasksCancelled = false
        end
    end
    if tasksCancelled then
        -- all tasks cancelled, safe to reboot
        self.node:send(turtleId, {"REBOOT"}, false, false)
        return true
    else
        self.node:send(turtleId, {"REBOOT"}, false, false)
        print("unable to cancel all tasks for", turtleId)
        return true
    end
end

return TaskManager