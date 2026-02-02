
local utils = require("utils")


local tasks = global.tasks
local list = global.list
local miner = global.miner

function openTab(fileName, args)
	--TODO: error handling has to be done by the file itself
	if not args then
		shell.openTab("runtime/"..fileName)
	else
		shell.openTab("runtime/"..fileName, table.unpack(args))
	end
end
function callMiner(funcName, args)
	if miner then
		utils.callObjectFunction(miner, funcName, args)
	end
end
function shellRun(fileName, args)
	--TODO: error handling has to be done by the file itself
	if not args then
		shell.run("runtime/"..fileName)
	else
		shell.run("runtime/"..fileName, table.unpack(args))
	end
end
print("waiting for tasks...")
while true do

	local nextTask = miner:getNextTaskAssignment()
	if nextTask then
		global.err = nil
		miner:setTaskAssignment(nextTask)
		nextTask:execute()
	end

	while #tasks > 0 do
		local status,err = nil,nil
		local task = table.remove(tasks, 1)
		local command, funcName, args = task[1], task[2], task[3]

		if command == "RUN" then
			--status,err = pcall(shellRun,funcName,args)
			global.err = nil
			openTab(funcName,args)
		elseif command == "DO" then
			global.err = nil
			status,err = pcall(callMiner,funcName,args)
			global.handleError(err,status)

		elseif command == "UPDATE" then
			shell.run("update.lua")
		else
			print("something else")
		end
	end
	sleep(0.2)

	-- TODO: we have two queues now, one for direct tasks, one for task assignments
	-- merge them into one 
end
