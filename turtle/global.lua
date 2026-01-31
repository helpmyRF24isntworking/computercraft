
-- global variables

tasks = {}
list = {}
miner = nil
err = nil
node = nil
nodeStream = nil
nodeRefuel = nil
nodeStorage = nil
turtleStorage = nil


handleError = function(err,status)
	if not status then
		if err.text == nil then
			-- unknown error
			global.err = {}
			global.err.text = err
			global.err.func = ""
		elseif err.fake then
			-- error on purpose to cancel running programs
			-- global.err = err
			global.err = nil
		else
			-- real error
			global.err = err
		end
		if global.err then
			print(global.err.fake, global.err.func, global.err.text)
		end
	else
		-- clear previous errors
		global.err = nil
	end
end

addTask = function(task)
	-- instead of global.addtask, miner:addTask would be much nicer ..
	table.insert(global.tasks, task)
end

requestStation = function()
	if global.node then
		if not global.node.host then global.node.host = 0 end
		-- global.node.onNoAnswer = function(forMsg)
			-- print("no answer", forMsg.id)
		-- end
		-- global.node.onAnswer = function(answer,forMsg)
			-- print(answer)
			-- print("b", os.epoch("ingame"),answer.id, answer.time)
		-- end
		local answer, forMsg = global.node:send(global.node.host,{"REQUEST_STATION"},true,true)
		if answer then
			print("a", os.epoch("ingame"),answer.data[1])
		end
	end
end