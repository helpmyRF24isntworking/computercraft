
-- code to test the actual cost of various turtle actions




local sleepTime = 1
local miner = global.miner


miner.digMoveTest = function(self)
    local blockName, data
    local ct = 0
    local result = true
	--try to move
    local start = os.epoch("utc")
	while not self:forward() do
        print("fail forward", os.epoch("utc") - start)
        start = os.epoch("utc")
		blockName, data = self:inspect(true) -- cannot move so there has to be a block
        print("inspected:", blockName, "time", os.epoch("utc") - start)
        start = os.epoch("utc")
		--check block
		if blockName then
			--dig if safe
			local doMine = true
			if doMine then
                
				self:dig()
                print("dug", os.epoch("utc") - start)
                start = os.epoch("utc")
				sleep(0.25)
                print("selpt", os.epoch("utc") - start)
                start = os.epoch("utc")
				--print("digMove", checkSafe(blockName), blockName)
			else
				print("NOT SAFE",blockName)
				result = false -- return false
				break
			end
		end
		ct = ct + 1
		if ct > 100 then
			if turtle.getFuelLevel() == 0 then
				self:refuel()
				ct = 90
				--possible endless loop if fuel is empty -> no refuel raises error
			else
				print("UNABLE TO MOVE")
			end
			result = false -- return false
			break
		end
	end
    print("moved", os.epoch("utc") - start)
end


local function testAction(action)
    sleep(sleepTime)
    turtle.forward() -- warm up

    if action.prepFunc then
        action.prepFunc()
    end
    sleep(sleepTime)

    local startTime = os.epoch("utc")
    local startClock = os.clock()
    action.func()
    local endTime = os.epoch("utc")
    local endClock = os.clock()

    if action.cleanFunc then
        action.cleanFunc()
    end

    turtle.forward()
    return (endTime - startTime), (endClock - startClock)

end


local turtleActions = {
    { name = "baseline", func = function() turtle.turnLeft(); turtle.forward() end },
    { name = "inspect", func = function() turtle.inspect() end },
    { name = "detect", func = function() turtle.detect() end },
    { name = "forward", func = function() turtle.forward() end },
    { name = "turnLeft", func = function() turtle.turnLeft() end },
    { name = "turnRight", func = function() turtle.turnRight() end },
    { name = "up", func = function() turtle.up() end },
    { name = "down", func = function() turtle.down() end },
    { name = "place", func = function() turtle.place() end },
    { name = "dig", func = function() turtle.dig() end },
}

local minerActions = {
    { name = "baseline", func = function() end },
    { name = "failMove", prepFunc = function() turtle.place() end, func = function() miner:forward() end, cleanFunc = function() turtle.dig() end },
    { name = "digMove", func = function() miner:digMove() end },
    { name = "digMoveBlocked", prepFunc = function() turtle.place() end, func = function() miner:digMove() end },
    { name = "digMoveUp", prepFunc = function() turtle.placeUp() end, func = function() miner:digMoveUp() end },
    { name = "digMoveDown", prepFunc = function() turtle.placeDown() end, func = function() miner:digMoveDown() end },
    { name = "inspect", func = function() miner:inspect(true) end },
    { name = "digMoveTest", prepFunc = function() turtle.place() end, func = function() miner:digMoveTest() end },
}


local function testAllActions(actions)
    for i, action in ipairs(actions) do
        local timeEpoch, timeClock = testAction(action)
        print(string.format("%-10s: utc %d ms, clock %.2f s", action.name, timeEpoch, timeClock))
    end
end

testAllActions(minerActions)
--testAllActions(minerActions)


-- result:
-- all actions take 400ms or 8 ticks


-- but
-- depending on the previous move: 
-- no previous move:
-- forward returns in 50ms / 1 tick 

-- failed forward always returns in 1 tick 


-- stationary + dig/inspect = 1 tick
-- movement + dig/inspect = 8 + 1 tick


-- basically: inspect takes 1 tick; dig takes 1 tick
-- movement takes 8 ticks
-- sleep() does only affect movement if its > 8 ticks

--> time = (previousCost - previousSleep) + actionCost - sleepTime