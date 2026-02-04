
local TaskAssignment = require("classTaskAssignment")
local TaskGroup =  require("classTaskGroup")

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

function TaskManager:new(node, turtles, groups)
    local o = {}
    setmetatable(o, self)

    o.groups = groups or {}
    o.tasks = {}
    o.turtleTasks = {} -- map turtleIds to assignmentIds
    o.cancelledTasks = {}
    o.node = node or nil
    o.turtles = turtles or {}

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
    for _,task in pairs(self.tasks) do
        if task.groupId then
            local group = self.groups[task.groupId]
            if group then
                task:setGroup(group)
            end
        end
    end
end

function TaskManager:setTurtles(turtles)
    self.turtles = turtles
    for _, task in pairs(self.tasks) do
        local turtle = self.turtles[task.turtleId]
        if turtle then
            task:setTurtle(turtle)
        end
    end
    for _, group in pairs(self.groups) do
        group:setTurtles(self.turtles)
    end
end

function TaskManager:getGroups()
    return self.groups
end
function TaskManager:getTasks()
    return self.tasks
end
function TaskManager:addTask(task)
    task:setTaskManager(self)
    task:setNode(self.node)
    -- based on the status of the task add to differnt lists?
    self.tasks[task.id] = task

    -- add to group
    if task.groupId then 
        local group = self.groups[task.groupId]
        if group then
            task:setGroup(group)
        else
            print("task has unknown group id", task.groupId)
        end
    end

    -- add to internal turtle list
    local turtleTasks = self.turtleTasks[task.turtleId]
    if not turtleTasks then
        turtleTasks = {}
        self.turtleTasks[task.turtleId] = turtleTasks
    end
    turtleTasks[task.id] = task

    -- also set turtle reference
    if self.turtles then 
        local turtle = self.turtles[task.turtleId]
        if turtle then
            task:setTurtle(turtle)
        end
    end
end

function TaskManager:removeTask(task)
    self.tasks[task.id] = nil
    local turtleTasks = self.turtleTasks[task.turtleId]

    -- remove from group
    if task.group then
        task.group:removeTask(task)
    elseif task.groupId then
        local group = self.groups[task.groupId]
        if group then
            group:removeTask(task)
        end
    end

    if turtleTasks then 
        turtleTasks[task.id] = nil
    end
    task:setTaskManager(nil)
end

function TaskManager:createTask(turtleId, groupId)
    local task = TaskAssignment:new(turtleId, groupId)
    self:addTask(task)
    return task
end

function TaskManager:addGroup(group)
    group:setTaskManager(self)
    self.groups[group.id] = group
end

function TaskManager:removeGroup(group)
    self.groups[group.id] = nil
    group:setTaskManager(nil)
    -- removing tasks is done by group / tasks itself
    self:saveGroups()
    -- not sure when to save 
end

-- do we want this wrapper? deletion should be handled by group itself like task
--function TaskManager:deleteGroup(id)
--    local group = self.groups[id] 
--    if group then return group:delete() end
--end

function TaskManager:createGroup()
    local group = TaskGroup:new(self.turtles)
    group:setTaskManager(self)
    self.groups[group.id] = group
    return group
end

function TaskManager:saveGroups()
    print("SAVE GROUPS NOT IMPLEMENTED")
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
            print(textutils.serialize(task:toTurtleMessage(), {compact=true, allow_repetitions=true}))
            self:addTask(task)
        end
    end

end

-- persistance stuff:
function TaskManager:save(fileName)
    print("saving task data")
    local fileName = fileName or default.fileName
    local data = {}
    data.tasks = {}
    for id, task in pairs(self.tasks) do
        if task:getStatus() ~= "new" then 
            table.insert(data.tasks, task:toSerializableData())
        end
    end

    data.groups = {}
    for id, group in pairs(self.groups) do
        if group:getStatus() ~= "new" then
            table.insert(data.groups, group:toSerializableData())
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
        if data then 

            -- load groups first, tasks reattach themselves
            if data.groups then
                for _, groupData in pairs(data.groups) do
                    local group = TaskGroup:new(self.turtles, groupData)
                    if group then
                        self:addGroup(group)
                    end
                end
            end

            if data.tasks then
                for _, taskData in pairs(data.tasks) do
                    local task = TaskAssignment:fromData(taskData)
                    if task then
                        self:addTask(task)
                    end
                end
            end

            -- optional: reattach tasks to groups
            for _, group in pairs(self.groups) do
                group:reattachTasks(self.tasks)
            end

        end
        return data
    else
        print("no task data file found", fileName)
        return nil
    end
end

return TaskManager