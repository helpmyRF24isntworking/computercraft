
local TaskAssignment = require("classTaskAssignment")
local TaskGroup =  require("classTaskGroup")
local LoadBalancer = require("classLoadBalancer")
local RecurringProject = require("classRecurringProject")

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
    o.projects = {}

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
function TaskManager:getProjects()
    return self.projects
end
function TaskManager:getProject(projectId)
    local project = self.projects[projectId]
    if not project then 
        local interval = 72000 * 60 * 2 -- 2 mins
        project = RecurringProject:new(projectId, interval)
        self.projects[projectId] = project
    end
    return project
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
            group:addTask(task)
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

    -- remove from group
    if task.group then
        task.group:removeTask(task)
    elseif task.groupId then
        local group = self.groups[task.groupId]
        if group then
            group:removeTask(task)
        end
    end

    local turtleTasks = self.turtleTasks[task.turtleId]
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

function TaskManager:createDummyGroup(id)
    -- create dummy group for unknown tasks
    local group = self:createGroup()
    self.groups[group.id] = nil
    group:changeId(id)
    self.groups[id] = group
    return group
end

function TaskManager:saveGroups()
    print("SAVE GROUPS NOT IMPLEMENTED")
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

function TaskManager:getAvailableTurtles()
    local result = {}
	local count = 0
	for id,turtle in pairs(self.turtles) do
		if turtle.state.online and turtle.state.task == nil then
			count = count + 1
			table.insert(result, turtle)
		end
	end
	return count, result
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
        -- self:removeTask(task) dont remove it
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
    if turtleTasks then
        for id, task in pairs(turtleTasks) do
            -- prepare tasks for reboot -- put them on ice, but dont delete them
            if not self:cancelTask(task) then 
                tasksCancelled = false
            end
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


function TaskManager:getTurtleTasks(turtleId)
    -- we have to ensure the table is uptodate
    return self.turtleTasks[turtleId]
end
-- maybe its time to create a turtle class that holds the state and has subscriber funcitons for state changes etc.
-- then we can easier manage and track the turtles

function TaskManager:getTaskWithStatus(...)
    local statusList = {...}
    local statusMap = {}
    local taskList = {}
    if #statusList <= 0 then
        print("no status filter provided")
    else
        if type(statusList[1]) == "table" then
            -- we assume the filter has been pre-made
            statusMap = statusList[1]
        else
            for _, status in ipairs(statusList) do
                statusMap[status] = true
            end
        end
        for _, task in pairs(self.tasks) do
            if statusMap[task:getStatus()] then
                table.insert(taskList, task)
            end
        end
    end
    return taskList
end

function TaskManager:getTaskList(filter)
    -- filter = { taskIds = {}, groupIds = {}, turtleIds = {}, statuses = {} }
    -- use dedicated function for other filters
    local taskList = {}
    if not filter then 
        print("no filter provided for getTaskList")
        return taskList
    end

    local taskIds = filter.taskIds
    local groupIds = filter.groupIds
    local turtleIds = filter.turtleIds
    local statuses = filter.statuses

    local hasTaskFilter = taskIds and #taskIds > 0
    local hasGroupFilter = groupIds and #groupIds > 0
    local hasTurtleFilter = turtleIds and #turtleIds > 0
    local hasStatusFilter = statuses and #statuses > 0

    local statusMap
    if hasStatusFilter then 
        -- build status map
        statusMap = {}
        for _, status in ipairs(statuses) do
            statusMap[status] = true
        end
    end

    if hasGroupFilter and not hasTaskFilter and not hasTurtleFilter then
        -- if only group id filter is set, we can directly get the tasks from the group
        for _, groupId in ipairs(groupIds) do
            local group = self.groups[groupId]
            if group then
                if hasStatusFilter then 
                    taskList = group:getTasksWithStatus(table.unpack(statuses))
                else
                    taskList = group:getTasks()
                end
            end
        end
    elseif hasTurtleFilter and not hasTaskFilter and not hasGroupFilter then
        for _, turtleId in ipairs(turtleIds) do
            local turtleTasks = self:getTurtleTasks(turtleId)
            if turtleTasks then
                for id, task in pairs(turtleTasks) do
                    if hasStatusFilter then 
                        if statusMap[task:getStatus()] then
                            table.insert(taskList, task)
                        end
                    else
                        table.insert(taskList, task)
                    end
                end
            end
        end
    elseif hasStatusFilter and not hasTaskFilter and not hasGroupFilter and not hasTurtleFilter then
        taskList = self:getTasksWithStatus(statusMap)
    else


        -- otherwise we have to iterate over all tasks and check the filters
        -- this also covers the case where only taskIds are provided, since we check those first in the matching function
        local function matchesFilter(task)
            if hasGroupFilter then
                local match = false
                for _, groupId in ipairs(groupIds) do
                    if task.groupId == groupId then
                        match = true
                        break
                    end
                end
                if not match then return false end
            end

            if hasTurtleFilter then
                local match = false
                for _, turtleId in ipairs(turtleIds) do
                    if task.turtleId == turtleId then
                        match = true
                        break
                    end
                end
                if not match then return false end
            end

            if hasStatusFilter then
                return statusMap[task:getStatus()]
            end

            return true
        end

        -- Iterate over tasks and apply filters
        if hasTaskFilter then
            for _, id in ipairs(taskIds) do
                local task = self.tasks[id]
                if task and matchesFilter(task) then
                    table.insert(taskList, task)
                end
            end
        else
            for _, task in pairs(self.tasks) do
                if matchesFilter(task) then
                    table.insert(taskList, task)
                end
            end
        end

    end



    return taskList
end

-- ############# MESSAGE HANDLERS
function TaskManager:isTaskMessage(msg)
    local txt = msg.data[1]
    local onRequestAnswerMessages = {
        ["TASK_STATE"] = true,
        ["REQUEST_LOAD_BALANCING"] = true,
        ["RECURRING_REPORT"] = true,
    }
    return onRequestAnswerMessages[txt]
end

function TaskManager:handleMessage(msg)
-- TODO: also have a message handler

    local ok,err = pcall(function()

    local data, sender = msg.data, msg.sender
    local txt = data[1]
    if txt == "TASK_STATE" then
        local taskState = data[2]
        self.node:answer(msg, {"TASK_STATE_ACK"})
        self:onTaskStateUpdate(taskState)

    elseif txt == "RECURRING_REPORT" then 
        local report = data[2]
        
        print("received recurring report", "proc", report.processed, "of", #report.items, "rtime", report.runtime / 72000) --, textutils.serialize(report, {compact=true, allow_repetitions=true}))
        local project = self:getProject(report.project)

        local respawnTask, reassignments, unassigned = project:handleReport(report)
        self.node:answer(msg, {"REPORT_RECEIVED", respawnTask})

        -- TODO: keep task creation generic by using executeRecurringTask 
        --[[ 
        if reassignments then
            for turtleId, items in pairs(reassignments) do
                local taskArgs = {
                    project = project.name,
                    items = items,
                    interval = project.executionInterval,
                    source = "host"
                }
                global.taskManager:createTask("executeRecurringTask", taskArgs, turtleId)
            end
        end
        --]]

        -- for now
        if reassignments then
            local senderTask = self:getTask(report.taskId)
            local funcName = senderTask.funcName
            for tid, items in pairs(reassignments) do
                local args = { items, "host" } -- project.executionInterval }
                local task = self:createTask(tid, nil) -- TODO groupId for project
                task:setExecutionParameters(funcName, args)
                if not task:start() then 
                    self:removeTask(task)
                    print("failed to start recurring task for turtle", tid)
                end
                print("rebalanced", tid, "#items", #items) --, textutils.serialize(args, {compact=true, allow_repetitions=true}))
            end

            -- this works for adding new tasks or updating existing ones
            -- but we have to kill tasks of turtles that have been unassigned 
            -- for this we should be semi-safe to use the taskId provided in its last report
            -- might not work on reboot
            for tid,ass in pairs(unassigned) do
                local lastTaskId = ass.lastTaskId
                local task = self:getTask(lastTaskId)
                local ok = task and task:cancel()
                if not ok then 
                    print("unable to stop recurring task", tid, "task", lastTaskId, "obj", task)
                end
                -- cannot cancel because status is completed
                -- current logic for trying to cancel completed tasks does not allow it
                -- might have to use forced-cancel 
                -- or different status for those recurring tasks in queue
                print("unassigned", tid)
            end
        end




    elseif txt == "REQUEST_LOAD_BALANCING" then 
        print("whatever")
        -- TODO use a taskGroup to manage projects that require loadbalancing
        local taskState = data[2].taskState
        local senderTask = self:getTask(taskState.id)
		local project, assignment = data[2].project, data[2].assignment

        local assignments = { assignment }
        local assignedTurts = { self.turtles[sender] }
        local count, availableTurts = self:getAvailableTurtles()
       
        local balancer = LoadBalancer:new()
        local reassignments = balancer:balanceAssignments(assignments, assignedTurts, availableTurts)
        local answerReassignment = reassignments[sender]
        -- this is also our chance to create a group for the project if it doesnt exist yet and tell the turts
        -- have the loadbalancer be part of the group and automatically trigger rebalancing
        -- based on the utilization of the turtles reported to the group
        
        -- man why did i decide to not allow answering on answers, now we cant ack the message...

        print("func", senderTask and senderTask.funcName, senderTask, "state", taskState, "id", taskState and taskState.id)
         print(textutils.serialize(reassignments, {compact=true, allow_repetitions=true}))

        local funcName = senderTask and senderTask.funcName or nil
        if not senderTask then
            senderTask = TaskAssignment:fromData(taskState)
            if senderTask then 
                self:addTask(senderTask)
                funcName = senderTask.funcName
            end
        end

        if not funcName then 
            sleep(10000)
            error("ALARM") 
            return
        end
        -- how do we make it gerneric so this works with any task

       
        -- now we can distribute the rest of the assignments
        for id, reassignment in pairs(reassignments) do
            if id ~= sender then
                local groupId = nil -- projectId or idk
                local task = self:createTask(id, groupId)
                local args = { reassignment, "host" }
                task:setExecutionParameters(funcName, args)
                if not task:start() then 
                    self:removeTask(task)
                    print("failed to start load balancing task for turtle", id)
                end
                print("rebalanced", id, "assignment", reassignment, textutils.serialize(args, {compact=true, allow_repetitions=true}))
            end
            -- TODO: differentiate between new assignments and just updates to the existing assignment
            -- alternatively we can just override the current recurring task with a new one like we do with newly assigned turtles
        end

        self.node:answer(msg, {"LOAD_BALANCING_ASSIGNMENT", { project = project, assignment = answerReassignment}})

		--self:rebalanceProject(project, assignment)
		-- from all turtles currently active on this project, collect their assignment
		-- then redistribute the assignment evenly and add a new turtle if needed
		-- for now we just do it for this one request
    end

    end)

    if not ok then
        print("ERROR", err)
        sleep(100000)
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
            print(textutils.serialize(task:toSerializableData(), {compact=true, allow_repetitions=true}))
            self:addTask(task)
        end
    end

    if task.groupId then 
        local group = self.groups[task.groupId]
        if not group then 
            group = self:createDummyGroup(task.groupId)
            if group then
                group:setStatus("unknown")
                print("adding unknown group", group.shortId, "for task", task.shortId)
            end
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