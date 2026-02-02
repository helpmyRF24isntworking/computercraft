
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
		created = os.epoch("ingame"),
		

		-- callback information from turtle
		-- data in case task had to be abandoned but might be continued later?
		checkpoint = nil, -- state = { }, -- include checkpoint taskState in callback to host?
		-- using this, any other turtle can continue the task from last state
		status = "new",
		progress = 0,
		returnValues = nil,

		
	}
	setmetatable(o, self)
	
	-- actual references
	o.group = nil
	o.turtle = nil

	if not obj then 
		o:initialize()
	end
	
	return o
end

function TaskAssignment:fromData(data)
	return TaskAssignment:new(nil,nil,data)
end

function TaskAssignment:onCompleted()
	print("task completed", self.id)
	-- maybe do something on completion?
end
function TaskAssignment:onExecutionStart()
	print("task started execution", self.id)
	-- maybe do something on start?
end

function TaskAssignment:getStatus()
	return self.status
end
function TaskAssignment:setStatus(status)
	local oldStatus = self.status
	self.status = status
	if status ~= oldStatus then
		self:onStatusChange(oldStatus, status)
	end
end
function TaskAssignment:onStatusChange(old, new)
	print("task status changed", old, "->", new)

	if new == "completed" then
		-- maybe do something on completion?
		self:onCompleted()
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
	
	end
end

function TaskAssignment:updateFromData(data)

	for k,v in pairs(data) do
		if k == "status" then
			self:setStatus(v)
		else
			self[k] = v
		end
	end
end

function TaskAssignment:initialize()
	self.id = utils.generateUUID()
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



function TaskAssignment:getProgress()
	-- weigh the progress of all turtles according to their assigned area volume

	local turt = self.turtle
	if turt then
		return turt.state.progress or 0
	else
		-- get turtle reference? 
		-- !! should classAssignment be available both on host monitoring
		-- and turtle execution side? 
		-- host creates the assignment, sends to turtle, turtle executes and updates state
		-- turtle sends state back with progress to host using id to assign to groups
		
		-- common things between host and turtle: turtle.state ...

		-- how do we differentiate host and turtle side code?
		-- maybe have separate classes for hostAssignment and turtleAssignment inheriting from classAssignment?
		return 0
	end
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
	self:setGroupId(group.id)
end
function TaskAssignment:setTurtleId(turtleId)
	print("set turtleId", turtleId)
	self.turtleId = turtleId
end
function TaskAssignment:setTurtle(turtle)
	self.turtle = turtle
	self:setTurtleId(turtle.state.id)
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
end
function TaskAssignment:getArea()
	return self.vars.area
end
function TaskAssignment:setPos(pos)
	self.vars.pos = vector.new(pos.x, pos.y, pos.z)
end
function TaskAssignment:getPos()
	return self.vars.pos
end


function TaskAssignment:setNode(node)
	-- needed? if so adjust otther functions
	self.node = node
end

function TaskAssignment:start(node)
	-- send to turtle for execution
	local node = node or self.node
	if not self.turtleId then 
		print("cannot start task, no turtleId set", self.id)
		return false
	end

	-- print(textutils.serialize(self:toTurtleMessage()))

	local answer = node:send(self.turtleId, self:toTurtleMessage(), true, true)
	if answer then 
		print("task answer", self.turtleId, self.id, answer.data[1])
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

	local answer = node:send(self.turtleId, {"CANCEL_TASK", self.id}, true, true)
	if answer then 
		if answer.data[1] == "TASK_CANCELLED" then 
			local data = answer.data[2]
			if data then
				if data.status == "running" then 
					-- task was running when it was cancelled
					if data.checkpoint then 
						self.checkpoint = data.checkpoint
					end
				else
					-- task was not yet started
				end
			end
			self:setStatus("cancelled")
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
		groupId = self.groupId,
		turtleId = self.turtleId,
		taskName = self.taskName,
		vars = self.vars,
		funcName = self.funcName,
		args = self.args,
		created = self.created,
		checkpoint = self.checkpoint,
		status = self.status,
		progress = self.progress,
		returnValues = self.returnValues,
	}
	return data
end


function TaskAssignment:toTurtleMessage()
	return {
		"TASK_ASSIGNMENT",
		{
			id = self.id,
			groupId = self.groupId,
			turtleId = self.turtleId,
			taskName = self.taskName,
			vars = self.vars,
			funcName = self.funcName,
			args = self.args,
			created = self.created,
		}
	}
end

return TaskAssignment
