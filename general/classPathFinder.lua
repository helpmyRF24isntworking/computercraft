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
	-- each action takes 400 ms
	[0] = 1, 	-- forward, up, down
	[2] = 1, -- back
	[-2] = 1, -- back
	[-1] = 2, -- left
	[3] = 2,	-- left
	[1] = 2,	-- right
	[-3] = 2,	-- right
}

--KEEP COSTS LOW BECAUSE HEURISTIC VALUE IS ALSO SMALL IN DIFFERENCE

local function calculateCost(currentOr,neighbourOr,neighbourBlock)
	
	local odiff = neighbourOr - currentOr
	local cost = costOrientation[odiff]
	
	if odiff == 2 or odiff == -2 then
		-- moving backwards
		if neighbourBlock == 0 then
			-- no extra cost 
		elseif neighbourBlock then
			-- known solid behind: turn(400) + turn(400) + fail(50) + inspect(50) + dig(400) + forward(400) = 1700ms
			cost = 4.25  -- 1700/400 = 4.25 actions
		else 
			-- unknown block, add probability of existing
			-- 4.25 * 0.8 + 0.2 * 1.0 -- 80% chance of a block being here
			cost = 3.6
		end
	else
		-- moving forward/side/up/down
		if neighbourBlock == 0 then 
			-- no extra cost
		elseif neighbourBlock then
			-- known solid block, requires 0-1 turns(x*400) + fail(50) + inspect(50) + dig(400) + forward(400)
			-- forward + turns already counted in costOrientation
			cost = cost + 1.25 -- 500/400 = 1.25 actions
		else 
			-- unknown block; expected additional cost
			-- 0.8 * 1.25 + 0.2 * 0
			cost = cost + 1.0
		end
	end
	return cost
end

local function calculateHeuristic(cx,cy,cz,fx,fy,fz)
	--manhattan = orthogonal
	return ( abs(cx - fx) + abs(cy - fy) + abs(cz - fz) ) * 1.75 -- 1.75 - 1.775 might be better
	-- multiplier represents average cost per move/block 
	-- best case = 1.0 
	-- worst case = 4.25 (moving backwards into known solid block)
	-- digMove has 900/400 = 2.25 cost with a block
end

--[[ 
	add this to aStarPart function for eval of the multiplier
	
	-- Calculate map knowledge ratio
    local totalBlocks = 0
    local knownBlocks = 0
    local sampleSize = 10000
    
    -- Sample area between start and finish
    for i = 1, sampleSize do
        local rx = sx + math.random(0, abs(fx-sx))
        local ry = sy + math.random(0, abs(fy-sy))
        local rz = sz + math.random(0, abs(fz-sz))
        totalBlocks = totalBlocks + 1
        if map:getBlockName(rx, ry, rz) ~= nil then
            knownBlocks = knownBlocks + 1
        end
    end
    
    local explorationRatio = knownBlocks / totalBlocks
    
    -- Adjust heuristic based on knowledge
    -- More explored = lower multiplier (turns matter more)
    -- Less explored = higher multiplier (unknowns add cost)
    local heuristicMult = 1.0 + (1.0 - explorationRatio) * 0.5
    -- Range: 1.0 (fully explored) to 1.5 (fully unknown)
    print("ratio:", explorationRatio, "known", knownBlocks, "total", totalBlocks, "mult", heuristicMult)

	highly explored area: 1.1 multiplier
	unknown: 1.3-1.4 multiplier
	-> average 1.2
--]]



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
			current.pos = vector.new(current[1], current[2], current[3])
			tableinsert(path, 1, current)
			current = current.previous
		else
			start.pos = vector.new(start[1], start[2], start[3])
			tableinsert(path, 1, start)
			return path
		end		
	end
end

local neighbours = {}
for i=1,6 do neighbours[i] = { 0, 0, 0, 0 } end -- prealloc x, y, z, o


local function getNeighbours(cx, cy, cz, co)
    local n = neighbours
    
    -- Unroll based on orientation
    if co == 0 then
        n[1][1], n[1][2], n[1][3], n[1][4] = cx, cy, cz+1, 0
        n[4][1], n[4][2], n[4][3], n[4][4] = cx+1, cy, cz, 3
        n[5][1], n[5][2], n[5][3], n[5][4] = cx-1, cy, cz, 1
        n[6][1], n[6][2], n[6][3], n[6][4] = cx, cy, cz-1, 2

    elseif co == 1 then
        n[1][1], n[1][2], n[1][3], n[1][4] = cx-1, cy, cz, 1
        n[4][1], n[4][2], n[4][3], n[4][4] = cx, cy, cz+1, 0
        n[5][1], n[5][2], n[5][3], n[5][4] = cx, cy, cz-1, 2
        n[6][1], n[6][2], n[6][3], n[6][4] = cx+1, cy, cz, 3

    elseif co == 2 then
        n[1][1], n[1][2], n[1][3], n[1][4] = cx, cy, cz-1, 2
        n[4][1], n[4][2], n[4][3], n[4][4] = cx-1, cy, cz, 1
        n[5][1], n[5][2], n[5][3], n[5][4] = cx+1, cy, cz, 3
        n[6][1], n[6][2], n[6][3], n[6][4] = cx, cy, cz+1, 0

    else -- co == 3
        n[1][1], n[1][2], n[1][3], n[1][4] = cx+1, cy, cz, 3
        n[4][1], n[4][2], n[4][3], n[4][4] = cx, cy, cz-1, 2
        n[5][1], n[5][2], n[5][3], n[5][4] = cx, cy, cz+1, 0
        n[6][1], n[6][2], n[6][3], n[6][4] = cx-1, cy, cz, 1
    end
    
    -- Up/down same regardless
    n[2][1], n[2][2], n[2][3], n[2][4] = cx, cy+1, cz, co
    n[3][1], n[3][2], n[3][3], n[3][4] = cx, cy-1, cz, co
    
    return n
end

local function getCachedData(map, x, y, z, cache)
    local cx = cache[x]
    if not cx then
        cx = {}
        cache[x] = cx
    end
    local cy = cx[y]
    if not cy then
        cy = {}
        cx[y] = cy
    end
    local data = cy[z]
    if data == nil then
        data = map:getBlockName(x, y, z) or false -- false if nil to cache it
        cy[z] = data
	elseif data == false then -- cached nil in form of false
		return nil
	end
    return data
end


-- also need some way to clear old turtle positions from map
-- they stick around for too long otherwise and often block or hinder pathfinding

function PathFinder:checkPossible(startPos, startOrientation, finishPos, map, distance, doReset)
	-- reverse search
	local distance = distance or default.distance * 2
	local path, gScore = self:aStarPart(finishPos,0,startPos,map,distance)
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
			for x,gx in pairs(gScore) do
				for y,gy in pairs(gx) do
					for z,score in pairs(gy) do
						if score < 0 then -- closed
							map:setData(x,y,z,nil,true)
						end
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

	-- 25.01.2026: x+200 random map
	    -- default: 				5100-5300 ct 256573
		-- neighbours pool 			4650-4900 ct 256573
		-- chached map 		   		4250-4350 ct 256573
		-- [1][2] .. 				4150-4250
		-- only gscore (no closed) 	4000-4100 ct 256573, open 710903, closed 671757 (like all above)
		-- heap optimized 			3650-3750  -- oof, same improvements for old logic 
		-- chat heap 				3180 aber andere zahlen für open 
		-- heap2: 					3090 - 3130 				-- 254974, 707176, 668425
		-- no open:epmty() 		  	3010 - 3100

		
	local startTime = osEpoch("local")
	
	
	local checkValid = self.checkValid
	local map = map
	local distance = distance or default.distance
	
	local mapCache = {}
	local sx, sy, sz = startPos.x, startPos.y, startPos.z
	local fx, fy, fz = finishPos.x, finishPos.y, finishPos.z
	
	
	local finishBlock = map:getBlockName(fx, fy, fz) -- do not use cache here
	if not checkValid(finishBlock) then
		-- print("ASTAR: FINISH NOT VALID", finishBlock)
		map:setData(fx, fy, fz, 0)
		-- overwrite current map value
	end

	local start = { [1]=sx, [2]=sy, [3]=sz, [4] = startOrientation, block = 0 }
	start[5] = 0
	start[6] = calculateHeuristic(sx, sy, sz, fx, fy, fz)

	local gScore = { [sx] = { [sy] = { [sz] = 0 }}}
	
	local open = Heap.new()
	open.Compare = function(a,b)
		return a[6] < b[6]
	end

	local ct = 0
	local closedCount = 0
	local openCount = 0

	local current = start
	
	while current do
		ct = ct + 1

		local cx,cy,cz,co,cGscore = current[1], current[2], current[3], current[4], current[5]

		local minGscore = gScore[cx][cy][cz]
		if minGscore >= 0 then
			if cx == fx and cy == fy and cz == fz
			or abs(cx - sx) + abs(cy - sy) + abs(cz - sz) >= distance then

				-- check if current pos is further than threshold for max distance
				-- or use time/iteration based approach
				
				local path = reconstructPath(current,start)
				-- print(osEpoch("local")-startTime, "FOUND, MOV:", #path, "CT", ct)
				-- print("open neighbours:", openCount, "closed", closedCount)
				return path

			end
			gScore[cx][cy][cz] = -1 -- mark as closed
		
			local neighbours = getNeighbours(cx, cy, cz, co)
			for i=1, #neighbours do
				local neighbour = neighbours[i]
				local nx, ny, nz, no = neighbour[1], neighbour[2], neighbour[3], neighbour[4]
				

				local gScorex = gScore[nx]
				if not gScorex then
					gScorex = {}
					gScore[nx] = gScorex
				end
				local gScorey = gScorex[ny]
				if not gScorey then
					gScorey = {}
					gScorex[ny] = gScorey
				end
				
				local nGscore = gScorey[nz]
				if not nGscore or nGscore >= 0 then -- open 

					local nBlock = getCachedData(map, nx, ny, nz, mapCache)
					if checkValid(nBlock) then
					
						openCount = openCount + 1
						local addedGScore = cGscore + calculateCost(co, no, nBlock)
						
						if not nGscore or addedGScore < nGscore then
							gScorey[nz] = addedGScore

							local nHscore = calculateHeuristic(nx, ny, nz, fx, fy, fz)

							local node = { nx, ny, nz, no,
									addedGScore,
									addedGScore + nHscore,
									previous = current,
								}
							open:push(node)

						end
						
					else
						-- path not safe, close this node
						gScorey[nz] = -1
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

		current = open:pop()
	end

	print(osEpoch("local")-startTime, "NO PATH FOUND", "CT", ct)
	return nil, gScore
	--https://github.com/GlorifiedPig/Luafinding/blob/master/src/luafinding.lua

end

return setmetatable( PathFinder, { __call = function( self, ... ) return newPathFinder( self, ... ) end } )