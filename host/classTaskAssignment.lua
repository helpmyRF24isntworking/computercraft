
local utils = require("utils")

local default = {
	groupSize = 5,
	width = 20,
	height = 10,
	yLevel =  {
		top = 73,
		bottom = -60,
	}
}

local osEpoch = os.epoch

local TaskAssignment = {}
TaskAssignment.__index = TaskAssignment

function TaskAssignment:new(turtleId, groupId, obj)
	local o = obj or {
		id = nil,
		-- user defined vars and task parameters, like "area"
		taskName = nil,
		vars = {},

		-- actual variables for execution -- miner:funcName(args)
		funcName = nil,
		args = {},
		
		-- general static host task info
		groupId = groupId or nil,
		turtleId = turtleId or nil,
		time = { created = osEpoch("ingame") },
		

		-- callback information from turtle
		-- data in case task had to be abandoned but might be continued later?
		checkpoint = nil, -- state = { }, -- include checkpoint taskState in callback to host?
		-- using this, any other turtle can continue the task from last state
		status = "new",
		progress = nil,
		returnValues = nil,

		
	}
	setmetatable(o, self)
	
	-- actual references
	o.group = nil
	o.turtle = nil
	if not o.lastUpdate then o.lastUpdate = 0 end
	if not o.time then o.time = { created = osEpoch("ingame") } end

	if not obj then 
		o:initialize()
	end
	
	return o
end

function TaskAssignment:fromData(data)
	return TaskAssignment:new(nil,nil,data)
end

function TaskAssignment:initialize()
	self.id = utils.generateUUID()
	self.shortId = string.sub(self.id,1,6)
end


function TaskAssignment:onCompleted()
	--print("task", self.shortId, "completed", self.id)
	-- maybe do something on completion?
end
function TaskAssignment:onExecutionStart()
	--print("task", self.shortId, "started execution", self.id)
	-- maybe do something on start?
end

function TaskAssignment:getStatus()
	return self.status
end
function TaskAssignment:setStatus(status, time)
	if time then 
		self.lastUpdate = time
	else
		self.lastUpdate = osEpoch()
	end
	local oldStatus = self.status
	self.status = status
	if status ~= oldStatus then
		self:onStatusChange(oldStatus, status)
	end
end
function TaskAssignment:onStatusChange(old, new)
	print("task", self.shortId, "status changed", old, "->", new, "time", osEpoch())

	if new == "completed" then

		if self.onCompleted then self.onCompleted(self) end
		if self.group then self.group:onTaskCompleted(self) end

	elseif new == "error" then
		-- log error?
	elseif new == "cancelled" then
		-- log cancellation?
	elseif new == "running" then 
		-- started running
		self:onExecutionStart()
	elseif new == "queued" then
		-- queued for execution
	elseif new == "rejected" then
		-- log rejection?
	elseif new == "no_answer" then
		-- no start answer
	elseif new == "cancel_failed" then
		-- log cancel failure?
	elseif new == "stopped" then 
		-- log stopped?
	elseif new == "deleted" then
		-- log deletion?

	end
end



function TaskAssignment:updateFromData(data)
	-- print("data update", self.status, "->", data.status, "time", osEpoch(), "last update", self.lastUpdate)

	-- conflict same tick:
		-- turtle sends status running
		-- host requests cancel 
		-- host receives cancel ack
		-- host receives status running

	-- perhaps status priorities:
	-- internal (cancel, start) > task_state > stream state

	if data.stateTime >= self.lastUpdate then
		for k,v in pairs(data) do
			if k == "status" then
				self:setStatus(v, data.stateTime)
			else
				self[k] = v
			end
		end
	else
		print("outdated task data", self.shortId, data.status, "time", data.stateTime, "last", self.lastUpdate)
	end
end
function TaskAssignment:updateFromState(state, time)
	-- to avoid pairs loop
	-- watch out, this might be outdated if the task was cancelled
	-- print("state update", self.status, "->", state.status, "time", time, "last update", self.lastUpdate)
	if time > self.lastUpdate then -- same tick updates: state looses, other messages have priority
		self.progress = state.progress or self.progress
		self:setStatus(state.status, time)
	else
		print("outdated task state", self.shortId, state.status, "time", time, "last", self.lastUpdate)
	end
end

function TaskAssignment:getProgress()
	-- weigh the progress of all turtles according to their assigned area volume
	return self.progress
end



function TaskAssignment:delete()
	-- for newly created tasks that are not sent to turtles yet
	if self:getStatus() ~= "new" then
		print("deleting task that is not new:", self.shortId, self:getStatus())
	end
	if self.taskManager then
		self.taskManager:removeTask(self)
	end
	if self.group then 
		self.group:removeTask(self)
	end
	self:setStatus("deleted")
end

function TaskAssignment:setTaskManager(taskManager)
	self.taskManager = taskManager
end

function TaskAssignment:getTurtleId()
	return self.turtleId
end
function TaskAssignment:getId()
	return self.id
end

function TaskAssignment:setTaskName(taskName)
	self.taskName = taskName
end

function TaskAssignment:setFunction(funcName)
	self.funcName = funcName
	if not self.taskName then
		self.taskName = funcName
	end
end
function TaskAssignment:setFunctionArguments(args)
	self.args = args
end
function TaskAssignment:setExecutionParameters(funcName, args)
	self:setFunction(funcName)
	self:setFunctionArguments(args)
end


function TaskAssignment:isActive()
	local turtle = self.turtle
	if not turtle or not turtle.state.online 
		or turtle.state.task == nil then
		-- inactive
		return false
	else
		return true
	end
end

function TaskAssignment:setGroupId(groupId)
	self.groupId = groupId
end
function TaskAssignment:setGroup(group)
	self.group = group
	self:setGroupId(group and group.id)
end
function TaskAssignment:setTurtleId(turtleId)
	if turtleId ~= self.turtleId then
		-- changed turtleId, let taskManager handle reassignment
		local taskManager = self.taskManager
		if taskManager then
			taskManager:removeTask(self)
			self.turtleId = turtleId
			taskManager:addTask(self)
		else
			self.turtleId = turtleId
		end
	end
end

function TaskAssignment:setTurtle(turtle)
	-- TODO: check if turtle changed (reassigned)
	-- inform taskManager about this as well (or remove turtleTasks from manager...)
	if turtle ~= self.turtle then
		self.turtle = turtle
		self:setTurtleId(turtle and turtle.state.id)
	end
end
function TaskAssignment:setVariables(vars)
	self.vars = vars
end
function TaskAssignment:setVar(key, value)
	self.vars[key] = value
end
function TaskAssignment:getVar(key)
	return self.vars[key]
end

function TaskAssignment:setArea(start,finish)
	start = vector.new(start.x, start.y, start.z)
	finish = vector.new(finish.x, finish.y, finish.z)
	self.vars.area = { start = start, finish = finish }
	self.args = { start, finish }
end
function TaskAssignment:getArea()
	return self.vars.area
end
function TaskAssignment:setPos(pos)
	self.vars.pos = vector.new(pos.x, pos.y, pos.z)
	self.args = { pos.x , pos.y , pos.z }
end
function TaskAssignment:getPos()
	return self.vars.pos
end


function TaskAssignment:setNode(node)
	-- needed? if so adjust otther functions
	self.node = node
end


function TaskAssignment:isResumable()
	local status = self.status
	if status ~= "completed" and status ~= "deleted" then
		local chk = self.checkpoint
		if chk and chk.tasks and #chk.tasks > 0 then
			return true
		else
			return false
		end
	else
		return false
	end
end

function TaskAssignment:printCheckpoint()
	if self.checkpoint and self.checkpoint.tasks then
		for k, task in ipairs(self.checkpoint.tasks) do
			print( k, "checkpoint task", task.func, "stage", task.taskState.stage)
		end
	end
end

function TaskAssignment:resume()
	if self:isResumable() then
		return self:start()
	else
		return false
	end
end

function TaskAssignment:start(node)
	-- send to turtle for execution
	local node = node or self.node
	if not self.turtleId then 
		print("cannot start task, no turtleId set", self.id)
		return false
	end
	if self.status == "completed" or self.status == "deleted" then
		print("cannot start task, already completed or deleted", self.turtleId, self.id)
		return true
	end

	local data = { "TASK_ASSIGNMENT", self:toSerializableData() }
	local answer = node:send(self.turtleId, data, true, true)
	if answer then 
		-- print("task answer", self.turtleId, self.id, answer.data[1])
		if answer.data[1] == "TASK_QUEUED" then 
			self:setStatus("queued")
			return true
		elseif answer.data[1] == "TASK_REJECTED" then
			local reason = answer.data[2] or "no reason"
			print("Turtle rejected task", self.turtleId, self.id, reason)
			self:setStatus("rejected")
			return false
		end
	else 
		print("no task answer", self.turtleId, self.id)
		self:setStatus("no_answer")
		return false
	end
end

function TaskAssignment:cancel(node)
	-- send cancel to turtle
	-- turtle should send back checkpoint if possible
	-- turtle: remove from taskList if not yet started

	-- answer might not come directly if turtle is busy
	local node = node or self.node

	print("cancelling", self.shortId, "current status", self.status, "time", osEpoch())

	if self.status == "completed" or self.status == "deleted" then
		print("cannot cancel task, already completed or deleted", self.turtleId, self.id)
		return true
	end

	local answer = node:send(self.turtleId, {"CANCEL_TASK", self.id}, true, true)
	if answer then 
		if answer.data[1] == "TASK_CANCELLED" then 
			local data = answer.data[2]
			if data then
				-- get checkpoint etc.
				self:updateFromData(data)
			end
			self:setStatus("cancelled") -- updateFromData should also set status cancelled, but to be sure
			return true

		elseif answer.data[1] == "TASK_CANCEL_FAILED" then
			print("Turtle failed to cancel task", self.turtleId, self.id)
			self:setStatus("cancel_failed")
			return false
		end
	else
		print("no cancel answer", self.turtleId, self.id)
		self:setStatus("cancel_failed")
		return false
	end
end

function TaskAssignment:toSerializableData()
	local data = {
		id = self.id,
		shortId = self.shortId,
		
		groupId = self.groupId,
		turtleId = self.turtleId,
		taskName = self.taskName,
		vars = self.vars,
		funcName = self.funcName,
		args = self.args,
		time = self.time,
		checkpoint = self.checkpoint,
		status = self.status,
		progress = self.progress,
		returnValues = self.returnValues,
		lastUpdate = self.lastUpdate,
	}
	return data
end

-- GUI stuff
local statusToColor = {
	new = colors.white,
	queued = colors.lightBlue,
	running = colors.green,
	completed = colors.lightGray,
	error = colors.red,
	cancelled = colors.orange,
	rejected = colors.yellow,
	no_answer = colors.yellow,
	cancel_failed = colors.yellow,
	stopped = colors.yellow,
	deleted = colors.gray,
}

function TaskAssignment:getStatusColor()
	return statusToColor[self.status] or colors.white
end
function TaskAssignment:getProgressText()
	--return string.format("%.1f%%", self.progress * 100)
	return ( self.progress and string.format("%3d%%", math.floor((self.progress) * 100)) ) or ""
end

return TaskAssignment
