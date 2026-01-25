local PathFinder = {}
PathFinder.__index = PathFinder

local Heap = require("classHeap")
-- local SimpleVector = require("classSimpleVector")

local abs = math.abs
local tableinsert = table.insert
local osEpoch = os.epoch

local default = {
	distance = 10,
}

local vectors = {
	[0] = {x=0, y=0, z=1},  -- 	+z = 0	south
	[1] = {x=-1, y=0, z=0}, -- 	-x = 1	west
	[2] = {x=0, y=0, z=-1}, -- 	-z = 2	north
	[3] = {x=1, y=0, z=0},  -- 	+x = 3 	east
}

local costOrientation = {
	[0] = 1, 	-- forward, up, down
	[2] = 1.75, -- back
	[-2] = 1.75, -- back
	[-1] = 1.5, -- left
	[3] = 1.5,	-- left
	[1] = 1.5,	-- right
	[-3] = 1.5,	-- right
}

local function checkValid(block)
	if block then return false
	else return true end
end


local function newPathFinder(template, checkValidFunc)
    return setmetatable( {
        checkValid = checkValidFunc or checkValid,
    }, template )
end


local function reconstructPath(current,start)
	local path = {}
	while true do
		if current.previous then
			current.pos = vector.new(current.x, current.y, current.z)
			tableinsert(path, 1, current)
			current = current.previous
		else
			start.pos = vector.new(start.x, start.y, start.z)
			tableinsert(path, 1, start)
			return path
		end		
	end
end


local function calculateHeuristic(cur,goal)
	--manhattan = orthogonal
	return abs(cur.x - goal.x) + abs(cur.y - goal.y) + abs(cur.z - goal.z)
	-- return math.sqrt((current.x-goal.x)^2 + (current.y+goal.y)^2 + (current.z+goal.z)^2)
end

local function getNeighbours(cur)
	local neighbours = {}
	
	local cx, cy, cz, co = cur.x, cur.y, cur.z, cur.o
	-- forward
	local vector = vectors[co]
	neighbours[1] = { x = cx + vector.x, y = cy + vector.y, z = cz + vector.z, o = co }
	-- up
	neighbours[2] = { x = cx, y = cy + 1, z = cz, o = co }
	-- down
	neighbours[3] = { x = cx, y = cy - 1, z = cz, o = co }
	-- left
	local curo = (co-1)%4
	vector = vectors[curo]
	neighbours[4] = { x = cx + vector.x, y = cy + vector.y, z = cz + vector.z, o = curo }
	-- right
	curo = (co+1)%4
	vector = vectors[curo]
	neighbours[5] = { x = cx + vector.x, y = cy + vector.y, z = cz + vector.z, o = curo }
	-- back
	curo = (co+2)%4
	vector = vectors[curo]
	neighbours[6] = { x = cx + vector.x, y = cy + vector.y, z = cz + vector.z, o = curo }

	return neighbours
end



--KEEP COSTS LOW BECAUSE HEURISTIC VALUE IS ALSO SMALL IN DIFFERENCE

local function calculateCost(current,neighbour)
	
	local cost = costOrientation[neighbour.o-current.o]
	
	if neighbour.block then
		--block already explored
		if neighbour.block == 0 then
			-- no extra cost
		else
			-- if block is mineable is checked in checkValidNode -> not yet
			cost = cost + 0.75 -- 0.75 fastest
			-- WARNING: we dont neccessarily know which block comes after this one...
		end
	else
		-- it is unknown what type of block is here could be air, could be a chest
		-- SOLUTION -> recalculate path when it is blocked by a disallowed block
		cost = cost + 1.5 -- 1.5 fastest
		-- if map is mostly unknown this is not good
	end
	return cost
end

function PathFinder:checkPossible(startPos, startOrientation, finishPos, map, distance, doReset)
	-- reverse search
	local distance = distance or default.distance * 2
	local path, closed = self:aStarPart(finishPos,0,startPos,map,distance)
	if path then 
		--print(#path, path[#path].pos, startPos)
		if path[#path].pos == startPos then
			-- return the reversed path
			local reversed = {}
			local ct = 0
			for i = #path, 1, -1 do
				ct = ct + 1
				reversed[ct] = path[i]
			end
			return reversed
		else
			-- not neccessarily impossible but out of the search range
			return false
		end
	else
		if doReset then 
			print("RESET CLOSED")
			-- set the visited blocks to nil
			for x,closedx in pairs(closed) do
				for y,closedy in pairs(closedx) do
					for z,_ in pairs(closedy) do
						map:setData(x,y,z,nil,true)
					end
				end
			end
		end
		return false
	end
	
end

function PathFinder:aStarPart(startPos, startOrientation, finishPos, map, distance)
	-- very good path for medium distances
	-- e.g. navigateHome
	-- start and finish must be free!

	-- miner = global.miner; miner:aStarPart(miner.pos,miner.orientation,vector.new(1,1,1),miner.map,500)
	
	-- evaluation x+50 empty map
		-- default: 			5270    5000, 5040, 5200, 5240,5520,5800 ct 30107
		-- neighbours:			4850	ct 30446
		-- xyzToId: 			4700-4950
		-- cost + heuristic 	4250
		-- gScore				2750 - 2950	open: 48231	closed:	77421
		-- fScore				2900		open: 48231	closed:	77421
		-- closed checkSafe		
		-- with vectors			3714, 3594, 3579, 3485, 3669
		-- simple vectors 		3381, 3439, 3327, 3300
		-- no map access : -650
		-- no vectors			2850
		-- no xyzToId			2650 -- nur für lange distanzen?
		
	local startTime = osEpoch("local")
	
	
	local checkValid = self.checkValid
	local map = map
	local distance = distance or default.distance
	
	local start = { x=startPos.x, y=startPos.y, z=startPos.z, o = startOrientation, block = 0 }
	local finish = { x=finishPos.x, y=finishPos.y, z=finishPos.z }
	
	local startBlock = map:getData(finish.x, finish.y, finish.z)
	if not checkValid(startBlock) then
		print("ASTAR: FINISH NOT VALID", startBlock)
		map:setData(finish.x, finish.y, finish.z, 0)
		-- overwrite current map value
	end
	
	local fScore = {}
	local gScore = {}

	gScore[start.x] = {}
	gScore[start.x][start.y] = {}
	gScore[start.x][start.y][start.z] = 0

	
	start.gScore = 0
	start.fScore = calculateHeuristic(start, finish)
	
	local closed = {}
	if not closed[start.x] then closed[start.x] = {} end
	if not closed[start.x][start.y] then closed[start.x][start.y] = {} end
	
	local open = Heap()
	open.Compare = function(a,b)
		return a.fScore < b.fScore
	end
	open:Push(start)
	
	local ct = 0
	local closedCount = 0
	local openCount = 0
	
	while not open:Empty() do
		ct = ct + 1
		
		local current = open:Pop()
		local cx,cy,cz = current.x, current.y, current.z
		--logger:add(tostring(current.pos))
		
		--local currentId = xyzToId(current.x, current.y, current.z)
		--print(currentId)

		
		if not closed[cx][cy][cz] then
			if cx == finish.x and cy == finish.y and cz == finish.z
			or abs(cx - start.x) + abs(cy - start.y) + abs(cz - start.z) >= distance then
				-- check if current pos is further than threshold for max distance
				-- or use time/iteration based approach
				
				local path = reconstructPath(current,start)
				print(osEpoch("local")-startTime, "FOUND, MOV:", #path, "CT", ct)
				print("open neighbours:", openCount, "closed", closedCount)
				return path

			end
			closed[cx][cy][cz] = true
			
			local neighbours = getNeighbours(current)
			for i=1, #neighbours do
				local neighbour = neighbours[i]
				local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z
				
				--local neighbourId = xyzToId(neighbour.x, neighbour.y, neighbour.z)
				
				local closedx = closed[nx]
				local gScorex, gScorey
				if not closedx then
					closedx = {}
					closed[nx] = closedx
					gScorex = {}
					gScore[nx] = gScorex
				else
					gScorex = gScore[nx]
				end
				local closedy = closedx[ny]
				if not closedy then
					closedy = {}
					closedx[ny] = closedy
					gScorey = {}
					gScorex[ny] = gScorey
				else
					gScorey = gScorex[ny]
				end
				
				if not closedy[nz] then

					neighbour.block = map:getData(nx, ny, nz)
					if checkValid(neighbour.block) then
					
						openCount = openCount + 1
							
						local addedGScore = current.gScore + calculateCost(current,neighbour)
						neighbour.gScore = gScorey[nz]
						if not neighbour.gScore or addedGScore < neighbour.gScore then
							gScorey[nz] = addedGScore
							neighbour.gScore = addedGScore
							
							neighbour.hScore = calculateHeuristic(neighbour,finish)
							neighbour.fScore = addedGScore + neighbour.hScore
							
							open:Push(neighbour)
							neighbour.previous = current
							
							-- -- previous = current could result in very long chains
							-- -- perhaps use a table to store paths?
						end
						
					else
						-- path not safe
						-- close this id? TEST
						closed[nx][ny][nz] = true
					end
				else
					closedCount = closedCount + 1
				end
			end
		end
		if ct > 1000000 then
			print("NO PATH FOUND")
			return nil
		end
		if ct%10000 == 0 then
			--sleep(0.001) -- to avoid timeout
			os.pullEvent(os.queueEvent("yield"))
		end
		if ct%1000 == 0 then
			-- maybe yield for longer for other tasks to catch up
			--> seems to solve all problems -> test interval and duration
			--sleep(0.5)
			-- print(osEpoch("local")-startTime, ct)
		end
	end
	print(osEpoch("local")-startTime, "NO PATH FOUND", "CT", ct)
	return nil, closed
	--https://github.com/GlorifiedPig/Luafinding/blob/master/src/luafinding.lua
end


function PathFinder:aStarId(startPos, startOrientation, finishPos, map, distance)
	-- very good path for medium distances
	-- e.g. navigateHome
	-- start and finish must be free!

	-- miner = global.miner; miner:aStarPart(miner.pos,miner.orientation,vector.new(1,1,1),miner.map,500)
	
	-- evaluation x+50 empty map
		-- default: 			5270    5000, 5040, 5200, 5240,5520,5800 ct 30107
		-- neighbours:			4850	ct 30446
		-- xyzToId: 			4700-4950
		-- cost + heuristic 	4250
		-- gScore				2750 - 2950	open: 48231	closed:	77421
		-- fScore				2900		open: 48231	closed:	77421
		-- closed checkSafe		
		-- with vectors			3714, 3594, 3579, 3485, 3669
		-- simple vectors 		3381, 3439, 3327, 3300
		-- no map access : -650
		-- no vectors			2850
		
	local startTime = osEpoch("local")
	
	local xyzToId = map.xyzToId
	
	local checkValid = self.checkValid
	local map = map
	local distance = distance or default.distance
	
	
	local start = { x=startPos.x, y=startPos.y, z=startPos.z, o = startOrientation, block = 0 }
	local finish = { x=finishPos.x, y=finishPos.y, z=finishPos.z }
	
	local startBlock = map:getData(finish.x, finish.y, finish.z)
	if not checkValid(startBlock) then
		print("ASTAR: FINISH NOT VALID", startBlock)
		map:setData(finish.x, finish.y, finish.z,0)
		-- overwrite current map value
	end
	
	local fScore = {}
	local gScore = {}
	local startId = xyzToId(start.x,start.y,start.z)
	gScore[startId] = 0
	
	start.gScore = 0
	start.fScore = calculateHeuristic(start, finish)
	fScore[startId] = start.fScore
	
	local closed = {}
	
	local open = Heap()
	open.Compare = function(a,b)
		return a.fScore < b.fScore
	end
	open:Push(start)
	
	local ct = 0
	local closedCount = 0
	local openCount = 0
	
	while not open:Empty() do
		ct = ct + 1
		
		local current = open:Pop()
		--logger:add(tostring(current.pos))
		
		local currentId = xyzToId(current.x, current.y, current.z)
		--print(currentId)
		if not closed[currentId] then
			if current.x == finish.x and current.y == finish.y and current.z == finish.z
			or abs(current.x - start.x) + abs(current.y - start.y) + abs(current.z - start.z) >= distance then
				-- check if current pos is further than threshold for max distance
				-- or use time/iteration based approach
				
				local path = reconstructPath(current,start)
				--print(osEpoch("local")-startTime, "FOUND, MOV:", #path, "CT", ct)
				--print("open neighbours:", openCount, "closed", closedCount)
				return path

			end
			closed[currentId] = true
			
			local neighbours = getNeighbours(current)
			for i=1, #neighbours do
				local neighbour = neighbours[i]
				
				local neighbourId = xyzToId(neighbour.x, neighbour.y, neighbour.z)
				if not closed[neighbourId] then

					neighbour.block = map:getData(neighbour.x, neighbour.y, neighbour.z)
					if checkValid(neighbour.block) then
					
						openCount = openCount + 1
							
						local addedGScore = current.gScore + calculateCost(current,neighbour)
						neighbour.gScore = gScore[neighbourId]
						if not neighbour.gScore or addedGScore < neighbour.gScore then
							gScore[neighbourId] = addedGScore
							neighbour.gScore = addedGScore
							
							neighbour.hScore = calculateHeuristic(neighbour,finish)
							neighbour.fScore = addedGScore + neighbour.hScore
							
							open:Push(neighbour)
							neighbour.previous = current
							
							-- -- previous = current could result in very long chains
							-- -- perhaps use a table to store paths?
						end
						
					else
						-- path not safe
						-- close this id? TEST
						closed[neighbourId] = true
					end
				else
					closedCount = closedCount + 1
				end
			end
		end
		if ct > 1000000 then
			print("NO PATH FOUND")
			return nil
		end
		if ct%10000 == 0 then
			--sleep(0.001) -- to avoid timeout
			os.pullEvent(os.queueEvent("yield"))
		end
		if ct%1000 == 0 then
			-- maybe yield for longer for other tasks to catch up
			--> seems to solve all problems -> test interval and duration
			--sleep(0.5)
			-- print(osEpoch("local")-startTime, ct)
		end
	end
	return nil
	--https://github.com/GlorifiedPig/Luafinding/blob/master/src/luafinding.lua
end

return setmetatable( PathFinder, { __call = function( self, ... ) return newPathFinder( self, ... ) end } )