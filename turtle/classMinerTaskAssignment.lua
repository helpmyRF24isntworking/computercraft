-- Class for the Executing Turtle

local utils = require("utils")

local default = {
	path = "/runtime/tasks/",
}

local MinerTaskAssignment = {}
MinerTaskAssignment.__index = MinerTaskAssignment

-- this is the "new" function
function MinerTaskAssignment:fromData(data)
	-- rebuild class from loaded file data or from host message
	local o = data
	-- sanity check
	if not o or not o.id or not o.funcName then
		print("INVALID TASK ASSIGNMENT DATA")
		return nil
	end
	
	setmetatable(o, MinerTaskAssignment)

	if not o.status then o.status = "new" end
	-- keep track of how often task was attempted
	if not o.attempts then o.attempts = 0 end
    if not o.turtleId then o.turtleId = os.getComputerID() end

	return o
end

function MinerTaskAssignment:fromFile(fileName)
	-- rebuild class from loaded file data or from host message
	local f = fs.open(fileName, "r")
	local data = textutils.unserialize(f.readAll())
	f.close()
	return self:fromData(data)
end

function MinerTaskAssignment:confirmQueued(msg, node)
    -- confirm that task is queued
    node:answer(msg, {"TASK_QUEUED"})
    self.status = "queued"
end

function MinerTaskAssignment:reject(msg, node, reason)
    -- reject task assignment
    node:answer(msg, {"TASK_REJECTED", reason})
    self.status = "rejected"
end

function MinerTaskAssignment:setGlobals(miner, node)
	self.miner = miner
	self.node = node
end

function MinerTaskAssignment:toSerializableData(noCheckpoint)
    -- checkpoint and assignment can have same args
	return {
		id = self.id,
        turtleId = self.turtleId,
		groupId = self.groupId,
		taskName = self.taskName,
		vars = self.vars,

		funcName = self.funcName,
		args = self.args,
		created = self.created,

		status = self.status,
		error = self.error,
		returnVals = self.returnVals,
		checkpoint = not noCheckpoint and self.checkpoint,
        attempts = self.attempts,

	}
end
function MinerTaskAssignment:save(path)
	-- maybe combine this with checkpointer?
	-- yes, would be nice if the checkpointer saves the TaskAssignment as well
	-- this way the currently running task is automatically restored on turtle restart as well as backed up
	-- only tasks that are still in the taskqueue need to be saved independently
	if not path then path = default.path end
	local data = self:toSerializableData()
	local fileName = path .. "/task_" .. self.id .. ".txt" 
	local f = fs.open(fileName, "w")
	f.write(textutils.serialize(data))
	f.close()
end

function MinerTaskAssignment:toState()
	-- get basic assignment info for state message to host 
	return { 
		id = self.id,
        turtleId = self.turtleId,
		groupId = self.groupId,
		status = self.status,
		-- progress = self.miner:getOverallProgress(),
	}
end

function MinerTaskAssignment:setCheckpoint(checkpoint)
    -- shallow copy without assignment to avoid circular reference
    if checkpoint then
        local copy = {}
        for k,v in pairs(checkpoint) do
            copy[k] = v
        end
        copy.assignment = nil
        self.checkpoint = copy
    end
end

function MinerTaskAssignment:getCheckpoint()
	-- get current state from miner
	-- do not get the most current checkPoint in case it is corrupted by an error,
	-- use the last saved one
	local checkpoint = self.miner.checkPointer:getLastSavedCheckpoint()
	-- but remove the assignment from the checkpoint?
	-- TODO: in that case we need to enable adding a new assignment to a checkpoint from host side
	-- if we want to continue the task on another turtle
	-- but host does not have classCheckpointer, nor this version of classTaskAssignment
	-- though he doesnt need to and can just add the checkpoint to a startMessage
	-- special message for continuing a prevoiusly cancelled checkpoint!
    self:setCheckpoint(checkpoint)
	-- WATCH OUT: if task was cancelled on purpose, checkpoint is cleared and saved!
	return self.checkpoint
end

function MinerTaskAssignment:confirmCancelled(msg)
    -- confirm that task was cancelled
    local node = self.node
    if node then
        node:answer(msg, {"TASK_CANCELLED", self:toSerializableData()})
    end
end
function MinerTaskAssignment:onCancel(msg)    -- only relevant if task is running
    if self.status == "running" then
        -- task was cancelled by host
        self:getCheckpoint()
        -- get checkpoint from miner, before it is deleted
        -- then stop miner -> this throws a fake error, which is redirected to this task assignment
        self.miner.stop = true
    end
    self:confirmCancelled(msg)
    -- send old status, so host knows if it was running or just queued
    self.status = "cancelled"
    return true
end

function MinerTaskAssignment:informHost()
	-- send message to host about completion / error
	local node = self.node
	if node then
		local msgData = {
			"TASK_STATE",
			self:toSerializableData()
		}
		local answer = node:send(node.host, msgData, true, true)
        if answer and answer.data[1] == "TASK_STATE_ACK" then 
            -- can safely delete assignment if its done or whatever
            return true
        else 
            -- save state somewhere until host can be informed
            print("no ack from host for task state")
            return false
        end
	end
    return false
end

function MinerTaskAssignment:handleError(ok, err, funcName)
	local error = nil
	if not ok then
		if err.text == nil then
			-- unknown error
			error = {}
			error.text = err
			error.func = funcName or ""
		elseif err.fake then
			-- error on purpose to cancel running programs
			-- but still there must be a reason to cancel
			error = nil
		else
			-- real error
			error = err
		end
		if error then
			print(error.fake, error.func, error.text)
		end
	else
		-- clear previous errors
		error = nil
	end
	global.err = error
end

function MinerTaskAssignment:isResumable()
	-- check if task can be resumed from checkpoint
	if self.checkpoint and self.checkpoint.tasks and #self.checkpoint.tasks > 0 then
		return true
	else
		return false
	end
end

function MinerTaskAssignment:execute()
	self.returnVals = nil
	self.attempts = self.attempts + 1
	local miner = self.miner
    miner:setTaskAssignment(self) -- also clears progress
    self.status = "running"
    self:informHost() -- inform host that task is starting
    self.miner.stop = false -- reset stop flag

    local ok,err
    if self:isResumable() then
        -- TODO: maybe? on reboot confirm continuation of task -> no need, host thinks they are running anyways
        -- see CheckPointer:restoreTaskAssignment() to set flags for this

        -- restore from checkpoint 
        local checkPointer = miner.checkPointer
        if checkPointer then 
            -- let checkpointer handle restoration
            ok, err = pcall(function()
                self.returnVals = checkPointer:executeTasks(miner)
            end)
        else
            print("no checkpointer available for restoration")
            self.status = "error"
        end
    else
        -- start task from new
        print("miner:"..self.funcName, table.unpack(self.args or {}))
        -- execute assigned function
        ok, err = pcall(function()
            self.returnVals = table.pack(utils.callObjectFunction(miner, self.funcName, self.args))
        end)
    end

    -- err = { fake, text, func, checkpoint }
	self:handleError(ok, err, self.funcName)

	if not ok then
		print("error:", textutils.serialize(err, { allow_repetitions = true }))

        if err and err.fake then
            if self.status == "cancelled" then 
                -- task was cancelled on purpose and already processed by onCancel()
                return true
            else
                -- another fake error? 
                self:setCheckpoint(err.checkpoint)
                self.status = "stopped"
            end
        else
            -- try and get saved checkpoint or from error
            if not self:getCheckpoint() then 
                self:setCheckpoint(err.checkpoint)
            end
            self.error = err
            self.status = "error"
        end
    else
        self.status = "completed"
    end
	-- inform host about completion / error
    self:informHost()
	return ok
end


return MinerTaskAssignment
