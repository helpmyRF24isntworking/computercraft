

-- add to classMiner
local PathFinderOld = require("classPathFinderOldTest")
function Miner:testPathfinding(distance)
	
	local goal
	if type(distance) == "number" then 
		goal = vector.new(self.pos.x + distance, self.pos.y, self.pos.z)
	else
		goal = distance 
	end
	
	self.map:setMaxChunks(800)
	local pathFinder = PathFinder()
	local pathFinderOld = PathFinderOld()
	self.pf = pathFinder
	pathFinder.checkValid = checkSafe
	pathFinderOld.checkValid = checkSafe
	local path = pathFinder:aStarPart(self.pos, self.orientation, goal , self.map, 10000)
	local path = pathFinderOld:aStarPart(self.pos, self.orientation, goal , self.map, 10000)
end


-- execute in terminal
global.miner:testPathfinding(50)
global.miner:testPathfinding(vector.new(2173, 0, -2579))
global.miner:navigateToPos(2229,68,-2661)