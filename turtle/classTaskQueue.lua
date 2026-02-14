
-- simple task queue for the miner, ensuring persistance
local utils = require("utils")
local MinerTaskAssignment = require("classMinerTaskAssignment")

local osEpoch = os.epoch

local function openTab(fileName, args)
	--TODO: error handling has to be done by the file itself
	if not args then
		shell.openTab("runtime/"..fileName)
	else
		shell.openTab("runtime/"..fileName, table.unpack(args))
	end
end
local function shellRun(fileName, args)
	--TODO: error handling has to be done by the file itself
	if not args then
		shell.run("runtime/"..fileName)
	else
		shell.run("runtime/"..fileName, table.unpack(args))
	end
end



local conditionFactories = {
    timeReached = function(targetTime, locale)
        return function()
            return osEpoch(locale) >= targetTime
        end
    end,
}
-- conditional tasks we want to save, but how do we want to define the condition function? it cannot be serialized, so we need to readd it on load
-- -> we can define some standard conditions and only save a reference to the condition function, then we can readd the condition function on load
-- 
local function createConditionFunc(conditionKey, params)
    local factory = conditionFactories[conditionKey]
    if factory then
        return factory(table.unpack(params))
    else
        error("Unknown condition key: " .. tostring(conditionKey))
    end
end




local TaskQueue = {}
TaskQueue.__index = TaskQueue

function TaskQueue:new(miner)
	local o = o or {}
	setmetatable(o,self)
	o.miner = miner
	o.tasks = {}
	o.conditional = {}
	o.path = "/runtime/tasks/queue.txt"
	return o
end

function TaskQueue:addDirectTask(command, funcName, args, pos)
	return self:addTask({type = "direct", command = command, funcName = funcName, args = args}, pos)
end

function TaskQueue:addArbitraryTask(func, pos)
    -- arbitrarily defined function
    -- return self:addTask({type = "arbitrary", func = func}, pos)
    print("arbitrary not supported yet")
end

function TaskQueue:findTask(taskId)
	if not taskId then return nil end
	local tasks = self.tasks
	for i = 1, #tasks do 
		local task = tasks[i]
		if not task.type or task.type ~= "direct" then 
			if task.id == taskId then
				return task, i
			end
		end
	end
	for i = 1, #self.conditional do
		local conditional = self.conditional[i]
		local task = conditional.task
		if task.id == taskId then
			return task, i
		end
	end
end

function TaskQueue:addTask(task, pos)
	if not self:findTask(task.id) then
		if not task.type or task.type ~= "direct" then 
			task:setGlobals(self.miner, self.miner.node)
		end
		if pos then
			table.insert(self.tasks, pos, task)
		else
			table.insert(self.tasks, task)
		end
		self:save()
		return true
	end
	-- triggers task rejection in case of duplicates
	return false
end

function TaskQueue:executeDirectTask(task)
	-- self.miner:setTaskAssignment(nil)
	local status,err = nil,nil
	if task.command == "RUN" then
		--status,err = pcall(shellRun,task.funcName,task.args)
		global.err = nil
		openTab(task.funcName, task.args)
	elseif task.command == "DO" then
		global.err = nil
		status,err = pcall(utils.callObjectFunction, self.miner, task.funcName, task.args)
		global.handleError(err,status)
	elseif task.command == "UPDATE" then
		shell.run("update.lua")
	else
		print("something else")
	end
end

function TaskQueue:executeNext()
	local tasks = self.tasks
	if #tasks == 0 then return end
	global.err = nil
	local task = table.remove(tasks, 1)
	self:save()
	if task.type and task.type == "direct" then 
		self:executeDirectTask(task)
	else
		task:execute()
	end

end
function TaskQueue:save()
	-- currently running task is saved by checkpointer
    if self.loading then return end

	local data = {}
	local tasks = self.tasks
	for i = 1, #tasks do 
		local task = tasks[i]
        local type = task.type
		if type == "direct" then 
			-- we dont want to save those generally
        else
			table.insert(data, task:toSerializableData())
		end
	end
   
    local conditionals = self.conditional
    for i = 1, #conditionals do
        local conditional = conditionals[i]
        table.insert(data, {type = "conditional", task = conditional.task:toSerializableData(), conditionKey = conditional.conditionKey, params = conditional.params})
    end
     print("saving", #data, "tasks")

	local f = fs.open(self.path, "w")
	f.write(textutils.serialize(data, {allow_repetitions = true}))
	f.close()
	return true
end

function TaskQueue:load()
    self.loading = true
	local f = fs.open(self.path, "r")
	if f then
		local data = textutils.unserialize(f.readAll())
		f.close()
		if data then
			for i = 1, #data do 
				local taskData = data[i]
                local type = taskData.type
				if type == "direct" then
					table.insert(self.tasks, taskData)
                elseif type == "conditional" then
                    local conditionFunc = createConditionFunc(taskData.conditionKey, taskData.params)
                    local task = MinerTaskAssignment:fromData(taskData.task)
                    table.insert(self.conditional, {task = task, condition = conditionFunc, conditionKey = taskData.conditionKey, params = taskData.params})
				else
					local task = MinerTaskAssignment:fromData(taskData)
					self:addTask(task)
				end
			end
		end
	end
    self.loading = false
end
function TaskQueue:remove(taskId)
	local task, pos = self:findTask(taskId)
	if task then
		table.remove(self.tasks, pos)
		self:save()
		return task
	end
	return nil
end

-- edge case: conditional is added to queue but not yet processed
-- will be lost if we save now, since we removed it from the conditional list
-- though the condition is met and the task is in the queue
-- -> readding the conditional must be done by the funciton processing the conditional
-- which is also cleaner in general: condtion is met -> task is added to queue -> executed -> done (and possibly readded)

function TaskQueue:addConditionalTask(task, conditionKey, params)
    local conditionFunc = createConditionFunc(conditionKey, params)
	local result = false
	if not self:findTask(task.id) then
		table.insert(self.conditional, {task = task, condition = conditionFunc, conditionKey = conditionKey, params = params})
		task:setStatus("waiting") -- not really working since the task adds itself and is set to completed after being added
		task:informHost()
		self:save()
		result = true
	end
	return result
end

function TaskQueue:checkConditionalTasks()
	-- check if any task has a (time) condition and add it to the (front?) of queue if condition is met
	local conditionals = self.conditional
	for i = #conditionals, 1, -1 do
		local conditional = conditionals[i]
		if conditional.condition() then
			table.remove(conditionals, i)
            self:addTask(conditional.task, 1)
            -- perhaps always informHost when addTask is called?
            -- no, for tasks created by host a direct answer is expected.
            -- only unknown tasks created by the turtle itself must inform the host
            -- on their own
            conditional.task:setStatus("queued")
            conditional.task:informHost() 
		end
	end
end

return TaskQueue