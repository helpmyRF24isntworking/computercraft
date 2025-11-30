
local global = global

local nodeStream = global.nodeStream
local turtles = global.turtles
local osEpoch = os.epoch

nodeStream.onRequestStreamData = function(previous)
	
	--local start = os.epoch("local")
	
	local turtle = turtles[previous.sender]
	-- append the entries
	local mapLog = turtle.mapLog
	local mapBuffer = turtle.mapBuffer
	if #mapLog > 0 then
		local bufCount = #mapBuffer
		for i = 1, #mapLog do 
			mapBuffer[bufCount+i] = mapLog[i]
		end
		turtle.mapLog = {}
		
	end
	
	-- local entry = table.remove(turtle.mapLog)
	-- while entry do
		-- table.insert(turtle.mapBuffer, entry)
		-- entry = table.remove(turtle.mapLog)
	-- end
	-- if global.printSend then 
			-- print(osEpoch("local"), "sending map update", previous.sender, #mapBuffer)
		-- end
	if #mapBuffer > 0 and turtle.state.online then
		
		if global.printSend then 
			print(osEpoch("local"), "sending map update", id, #mapBuffer)
		end
		return {"MAP_UPDATE",mapBuffer}
		--print("id", id, "time", timeSend .. " / " .. os.epoch("local")-start, "count", #data.mapBuffer)
	end
	
	return nil
end


while global.running do
	-- PROBLEM: node:send probably yields and lets other processes work
	-- processes (probably of turtles) should wait until send is done
	-- problem lies on the receiving end of turtles or size of the payload
	-- to avoid high payloads being sent unnecessarily -> only send to online turtles
	-- offline turtle buffer gets filled but only sent if turtle comes back
	
	-- mapBuffer is not cleared if sending takes too long
	-- yield while sending (current implementation) or checkValid not with
	-- current time, rather compare originalMsg with answerMsg
	
	--print(os.epoch("local"),"sending")
	
	local startTime = osEpoch("local")
	nodeStream:stream()
	--sendMapLog()
	if global.printSendTime then 
		print(osEpoch("local")-startTime,"done", "events", global.eventCount, "msgs", global.messageCount, "timers", global.timerCount) 
		global.eventCount = 0
		global.messageCount = 0
		global.timerCount = 0
		end
	local delay = (osEpoch("local")-startTime) / 1000
	if delay < global.minMessageDelay then delay = global.minMessageDelay
	elseif delay > 1 then delay = 1 end
	--else delay = delay * 2 end
	--print("delay", delay)
	-- if running into performance problems again -> set sleep time dynamically
	-- based on duration of sendMapLog
	--sleep(delay) --0.2
	sleep(delay)
	--os.pullEvent(os.queueEvent("yield"))
	
end