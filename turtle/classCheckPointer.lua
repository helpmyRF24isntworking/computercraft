require("classList")
local utils = require("utils")
local MinerTaskAssignment = require("classMinerTaskAssignment")

local default = {
	fileName = "runtime/checkpoint.txt",
}

local CheckPointer = {}
CheckPointer.__index = CheckPointer

local tpack = table.pack
local tableinsert = table.insert

function CheckPointer:new(o)
    o = o or {}
    setmetatable(o, self)  

	
	o.fileName = default.fileName
	o.index = 0
	o.checkpoint = nil
	
    return o
end

function CheckPointer:existsCheckpoint()
	if fs.exists(self.fileName) then
		return true
	end
	return false
end

function CheckPointer:load(miner)
	if not fs.exists(self.fileName) then 
		print("no checkpoint available")
		return nil
	end

	local file = fs.open(self.fileName, "r")
	self.checkpoint = textutils.unserialize(file.readAll())
	file.close()
	
	if not self.checkpoint then
		print("checkpoint file empty")
		fs.delete(self.fileName)
		return false
	end

	local taskList = miner.taskList
	for _, task in ipairs(self.checkpoint.tasks or {}) do
		local entry = { task.func, taskState = task.taskState }
		taskList:addLast(entry)
	end

	-- restore position seperately

	return true
end

local function getTaskAssignment(miner)
	local assignmentData 
	local assignment = miner:getTaskAssignment()
	if assignment then
		local noCheckpoint = true
		assignmentData = assignment:toSerializableData(noCheckpoint)
	end
	return assignmentData
end

function CheckPointer:restoreTaskAssignment(miner)
	-- restore task assignment
	local taskAssignment = self.checkpoint.assignment
	if taskAssignment then
		local assignment = MinerTaskAssignment:fromData(taskAssignment)
		if assignment then
			
			local currentAssignment = miner:getTaskAssignment()
			if currentAssignment then
				print("WARNING: turtle already has a task assignment")
			end
			assignment:setCheckpoint(self.checkpoint)
			miner:addTaskAssignment(assignment, 1) -- add as first assignment
			self.checkpoint.assignment = assignment:toSerializableData(true)
			return true
			-- TODO: assignment:notifyResumed()

			-- how do we add all the checkpointed tasks to the assignment?
			-- e.g.
			-- stripMine ( args )
			-- mineArea ( args )
			-- -> these tasks must be added to the assignment's task list
			-- maybe rework the taskassignment anyways to hold lists of funcitons 
			-- then we can also execute more complex tasks like deliverItems -> returnHome -> etc. 
			-- we can do so anyways with the queue but its not as nice
			-- requires tracking individual tasks progress though and saving what steps are done etc.
			-- requires not rewriting taskassignment but creating a wrapper class that holds multiple taskassignments

			-- also for the checkpoint this is no issue, since the taskAssignment can hold a checkpoint
			-- on execute check if checkpoint exists and continue from there
		else
			-- not much we can do about it, checkpoint will be executed anyways if possible
		end
	end
	return false
end

function CheckPointer:setCheckpoint(checkpoint)
	-- to restore a checkpoint sent by the host 
	self.checkpoint = checkpoint
end

function CheckPointer:executeTasks(miner)
	print("CONTINUE FROM CHECKPOINT")
	-- Throws error

	-- restore the miner position
	local pos, orientation = self.checkpoint.pos, self.checkpoint.orientation
	local returnVals = nil
	for k, task in ipairs(self.checkpoint.tasks) do
		if k == 1 and not task.taskState.ignorePosition then 
			-- only restore Position if needed
			if not miner:navigateToPos(pos.x, pos.y, pos.z) then 
				error("cannot reach checkpoint position")
			end
			miner:turnTo(orientation)
		end
		local func = task.func
		local args = task.taskState.args
		returnVals = table.pack(utils.callObjectFunction(miner, func, args))
	end

	-- remove the checkpoint file after restoration
	fs.delete(self.fileName)
	return returnVals
end


local function getCheckpointableTasks(taskList)
	 -- save only checkpointable tasks

    local checkpointableTasks = {}
	local node = taskList.first
	while node do
		if node.taskState then
			-- checkpointable task
			tableinsert(checkpointableTasks, { func = node[1], taskState = node.taskState })
		end
		node = node._next
	end

    return checkpointableTasks
end

function CheckPointer:getLastSavedCheckpoint()
	-- use to get the most recent stable checkpoint
	return self.checkpoint
end

function CheckPointer:getCheckpoint(miner)
	-- ONLY CALL THIS AT SPECIFIC POINTS WHERE THE MINER IS IN A CONSISTENT STATE
	local checkpoint = {
		tasks = getCheckpointableTasks(miner.taskList),
		pos = miner.pos,
		orientation = miner.orientation,
		assignment = getTaskAssignment(miner),
	}
	if #checkpoint.tasks == 0 then 
		checkpoint = nil
	end
	return checkpoint
end

function CheckPointer:save(miner)

	local checkpoint = self:getCheckpoint(miner)

	if not checkpoint or #checkpoint.tasks == 0 then
		fs.delete(self.fileName)
		self.checkpoint = nil
	else
		-- assignment and checkpoint share args -> serialization error
		self.file = fs.open(self.fileName, "w")
		self.file.write(textutils.serialize(checkpoint, { allow_repetitions = true }))
		self.file.close()

		self.checkpoint = checkpoint
	end
end

function CheckPointer:close()
	if self.file then 
		self.file.close()
	end
end

return CheckPointer