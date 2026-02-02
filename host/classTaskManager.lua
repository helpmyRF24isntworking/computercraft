
local TaskAssignment = require("classTaskAssignment")

local TaskManager = {}
TaskManager.__index = TaskManager
--TODO: classTaskManager on host
-- keeps track of all assignments and groups 
-- restarts tasks if needed, assigns new tasks to idle turtles etc.
-- can restart whole groups if needed
-- handles callbacks from turtles etc.

local default = {
    fileName = "runtime/taskData.txt",
}

function TaskManager:new(node)
    local o = {}
    setmetatable(o, self)

    o.groups = {} 
    o.tasks = {}
    o.turtleTasks = {} -- map turtleIds to assignmentIds
    o.cancelledTasks = {}
    o.node = node or nil
    o.turtles = {}

    o:initialize()
    return o
end

function TaskManager:initialize()
    -- initialize task manager
    if not self.node then 
        print("no network node for task manager")
    end
    self:load()
end

function TaskManager:setGroups(groups)
    self.groups = groups
end
function TaskManager:setTurtles(turtles)
    self.turtles = turtles
end
function TaskManager:addTask(task)
    task:setTaskManager(self)
    task:setNode(self.node)
    -- based on the status of the task add to differnt lists?
    self.tasks[task.id] = task

    local turtleTasks = self.turtleTasks[task.turtleId]
    if not turtleTasks then
        turtleTasks = {}
        self.turtleTasks[task.turtleId] = turtleTasks
    end
    turtleTasks[task.id] = task
end

function TaskManager:removeTask(task)
    self.tasks[task.id] = nil
    local turtleTasks = self.turtleTasks[task.turtleId]
    if turtleTasks then 
        turtleTasks[task.id] = nil
    end
    task:setTaskManager(nil)
end

function TaskManager:getTurtleTasks(turtleId)
    return self.turtleTasks[turtleId]
end

function TaskManager:getCurrentTurtleTask(turtleId)
    local turtleTasks = self:getTurtleTasks(turtleId)
    local current
    -- maybe also request turtle task
    local currentList
    if turtleTasks then 
        for id, task in pairs(turtleTasks) do
            local status = task:getStatus()
            if status == "running" then -- other states like "error" can still be the current task though (restart on reboot)
                currentList = task
                break
            end
        end
    end
    -- safe way is to ask the turtle, even though it informs us about task state changes
    local turt = self.turtles[turtleId]
    if turt and turt.state.assignment and turt.state.online then
        local taskId = turt.state.assignment.id
        local currentState = self:getTask(taskId)
        if currentState then 
            if currentState.id ~= (currentList and currentList.id) then
                print("task mismatch for turtle", turtleId, "host has", (currentList and currentList.id), "turtle has", taskId)
                -- request state from turtle
                local answer = self.node:send(turtleId, {"REQUEST_TASK_STATE"}, true, true)
                if answer then 
                    if answer.data[1] == "TASK_STATE" then
                        local taskState = answer.data[2]
                        self:onTaskStateUpdate(taskState)
                        current = self:getTask(taskState.id)
                    elseif answer.data[1] == "NO_TASK" then
                        current = nil
                    end
                else
                    print("could not confirm task with turtle", turtleId)
                    current = currentList or currentState -- turtle offline
                end
            else
                current = currentList or currentState 
            end
        else
            current = currentList
        end
    end
    return current
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

function TaskManager:cancelCurrentTurtleTask(turtleId)
    local task = self:getCurrentTurtleTask(turtleId)
    if task then
        return self:cancelTask(task)
    else
        -- still send the signal to stop whatever it is doing
        self.node:send(turtleId, {"STOP"}, false, false)
        print("no current task to cancel for turtle", turtleId)
        return true
    end
end


function TaskManager:rebootTurtle(turtleId)
    -- find task for turtle and set it to reboot

    -- actually no need to do allat, since the turtle will handle saving and restoring its tasks
    -- unless we want to clear the tasks and redistribute them ourselves
    -- usually we reboot to update the turtle but want to keep its tasks
    -- use the update funcitonality for this, not the "real" reboot
    -- this can also be used to shutdown the turtle safely (perhaps if it has an alarm and will be picked up)

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

function TaskManager:getTask(taskId)
    return self.tasks[taskId]
end


-- ############# MESSAGE HANDLERS
function TaskManager:isTaskMessage(msg)
    local txt = msg.data[1]
    local onRequestAnswerMessages = {
        ["TASK_STATE"] = true,
    }
    return onRequestAnswerMessages[txt]
end

function TaskManager:handleMessage(msg)
-- TODO: also have a message handler
    local txt = msg.data[1]
    if txt == "TASK_STATE" then
        local taskState = msg.data[2]
        self.node:answer(msg, {"TASK_STATE_ACK"})
        self:onTaskStateUpdate(taskState)
    end
end

function TaskManager:onTaskStateUpdate(taskState)
    -- task state update from turtle
    local task = self:getTask(taskState.id)
    if task then
        task:updateFromData(taskState)
    else
        print("received task state for unknown task", taskState.id)
        task = TaskAssignment:fromData(taskState)
        if task then
            print("adding unknown task to task manager", taskState.id)
            print(textutils.serialize(task:toTurtleMessage(), {compact=true}))
            self:addTask(task)
        end
    end

end

-- persistance stuff:
function TaskManager:save(fileName)
    local fileName = fileName or default.fileName
    local data = {}
    data.tasks = {}
    for id, task in pairs(self.tasks) do
        if task:getStatus() ~= "new" then 
            table.insert(data.tasks, task:toSerializableData())
        end
    end

    local f = fs.open(fileName,"w")
    f.write(textutils.serialize(data, { allow_repetitions = true }))
    f.close()

    -- also groups?
    -- currently being handled by global.saveGroups and global.loadGroups
    -- though not needed after everything switched to using the TaskManager

    return data
end

function TaskManager:load(fileName)
    local fileName = fileName or default.fileName
    local f = fs.open(fileName,"r")
    if f then
        local data = textutils.unserialize( f.readAll() )
        f.close()
        if data and data.tasks then
            for _, taskData in pairs(data.tasks) do
                local task = TaskAssignment:fromData(taskData)
                if task then
                    self:addTask(task)
                end
            end
        end
        return data
    else
        print("no task data file found", fileName)
        return nil
    end
end

return TaskManager