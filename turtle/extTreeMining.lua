-- Tree related Miner Functions
local Miner = require("classMiner")
local vector = vector
local vectors = Miner.vectors
local vectorUp = Miner.vectorUp
local vectorDown = Miner.vectorDown
local mineBlocks = Miner.mineBlocks
local osEpoch = os.epoch

local Extension = {}

local ChunkyMap = require("classChunkyMap")
local utils = require("utils")
local BreadthFirstSearch = require("classBreadthFirstSearch")
local StateMap = require("classStateMap")
local manhattanDistance = utils.manhattanDistance

local leafBlocks = {
	["minecraft:oak_leaves"] = true,
	["minecraft:spruce_leaves"] = true,
	["minecraft:birch_leaves"] = true,
	["minecraft:jungle_leaves"] = true,
	["minecraft:acacia_leaves"] = true,
	["minecraft:dark_oak_leaves"] = true,
}

local logBlocks = {
	["minecraft:oak_log"] = true,
	["minecraft:spruce_log"] = true,
	["minecraft:birch_log"] = true,
	["minecraft:jungle_log"] = true,
	["minecraft:acacia_log"] = true,
	["minecraft:dark_oak_log"] = true,
}


local function checkValidLeafBFS(block)
	-- only traverse through unknown blocks or leaf blocks
	if block == nil or leafBlocks[block] then return true
	else return false end
end

local function checkGoalLeafBFS(block)
	-- only goal if leaf block
	if block and logBlocks[block] then return true
	else return false end
end

local function checkAirBlock(data)
	if data == 0 or data.name == 0 then 
		return true
	end
	return false
end

local function checkLogBlock(data)
	-- rewrite ts
	if data and not checkAirBlock(data) and logBlocks[data.name] then 
		return true
	end
	return false
end
local function checkLeafBlock(data)
	if data and not checkAirBlock(data) and data.tags and data.tags["minecraft:leaves"] then
		if not leafBlocks[data.name] then
			print("UNKNOWN LEAF BLOCK:", data.name)
			leafBlocks[data.name] = true
		end
		return true
	end
	return false
end
local function checkBeeHive(data)
	if data and not checkAirBlock(data) and data.name == "minecraft:bee_nest"  then
		return true
	end
	return false
end


-- known issues
-- 1. diagonal blocks without any leaves will not be found
-- 2. leaves that are connected to multiple blocks might return plausible if they are not reinspected
-- 		-> they are ignored to check for logs
--     solution? a simple backtracking down the main trunk and inspecting leaves again could help 
--		   (or step after mining all connected logs)
--     also once at the top of the tree: use leaves gradient to find next log, continue from there with rest of logic
-- 3. inefficient mining order -> logs and leaves could be mined in a better order to minimize movement
--    best would be to pick the nearest log/leaf at each step, but that is quite expensive to calculate
--    simpler is to use a heap for the leaves based on state.distance and always priotitize logs
--    immediately mine logs even if another "job" like mineToLeaf is ongoing
--    always mining logs first, then reevaluating the leaves.distance values could also help with 2.

-- 4. old distance values of leaves 
--  after mining all logs, update the distance values of leaves through bfs again? 
-- bfs for dist 2 = nil but neighbour has been inspected recently dist 5 -> dist 4 now
-- randomly reinspect leaves? best to do it on connected groups of leaves
-- how do we get groups of leaves? 


-- only real optimization left: use bfs to floodfill leaves distance values after having mined logs / inspected leaves
-- e.g. leaf inspected: dist 7 -> neighbour has old value dist 2
--           conflicting info, 7 is more recent, which means the neighbour must be at least dist 6
--           so update dist to 6, and continue bfs from there
--           do this for all leaves that have been inspected after last/latest log was mined
--           only then reinspect leaves that still have a somewhat low distance value (also do this by groups)

-- inspect reduction:
-- when mining a leaf, then moving forward and again inspecting the surrounding leaves
-- they can only have distance values of the previous leaf-1, since they were connected to it
-- we could skip inspecting them if we dont care about high distance values (e.g. anything >= 5)


function Extension:mineTree()

	-- only needed for oak trees ig 

	-- TODO: prioritize logs over leaves with distance 1
	-- but instead of doing it at the very end, do it at each DFS node after mining logs?
	-- remove bee nests minecraft:bee_nest
	-- for branches, check the next air block as well

	-- global.miner:navigateToPos(2229, 68, -2665); global.miner:turnTo(1); global.miner:mineTree()

	local currentTask = self:addCheckTask({debug.getinfo(1, "n").name})

	local startPos = vector.new(self.pos.x, self.pos.y, self.pos.z)
	local startOrientation = self.orientation

	local treeMap = StateMap:new()
	self.treeMap = treeMap

	local maxDistance = 7
	local distanceLeaves = {}
	for i = 1, maxDistance do distanceLeaves[i] = {} end
	local leafDistanceMap = {}

	local reinspectionDistance = 3

	local prvReinspectionDistance = reinspectionDistance
	local logs = {}
	local priorityLogPos = nil
	

	local function posToKey(pos)
        return pos.x .. "," .. pos.y .. "," .. pos.z
    end

	local function setReinspectionDistance(dist)
		prvReinspectionDistance = reinspectionDistance
		reinspectionDistance = dist
	end
	local function restoreReinspectionDistance()
		reinspectionDistance = prvReinspectionDistance
	end

	local function shouldInspect(data)
		-- not yet inspected or leaf block with distance <= 2

		local result = false
		if not data then 
			result = true
		elseif checkLeafBlock(data) and data.state.distance <= reinspectionDistance then
			-- check if a log was mined since last inspection, only then reinspect the leaf
			local timeLogMined = treeMap:getLastMined("minecraft:oak_log")
			local wasLogMined = timeLogMined and timeLogMined > data.time or false
			result = wasLogMined
		end
		if not result then 
			--print("noInspect", data.name, data.state and data.state.distance, checkLeafBlock(data))
		elseif result and checkLeafBlock(data)then
			-- print("reinspectLeaf", data.name, data.state.distance)
		end
		return result
	end

	local function rememberBlock(pos, data)
		treeMap:setData(pos.x, pos.y, pos.z, data)

		if checkLogBlock(data) then
			table.insert(logs, pos)
		elseif checkLeafBlock(data) then
			local key = posToKey(pos)
			local oldDist = leafDistanceMap[key]
			local newDist = data.state.distance

			if oldDist and newDist ~= oldDist then
				-- already known leaf, update only if distance changed
				distanceLeaves[oldDist][key] = nil
			end
			distanceLeaves[newDist][key] = pos
			leafDistanceMap[key] = newDist

		elseif checkBeeHive(data) then
			table.insert(logs, pos) -- mine bee hives as well
		end
	end

	local function inspectDown()
		local pos = self.pos + vectorDown
		local data = treeMap:getData(pos.x, pos.y, pos.z)
		if shouldInspect(data) then
			local blockName, data = self:inspectDown(true)
			rememberBlock(pos, data)
		end
	end
	local function inspectUp()
		local pos = self.pos + vectorUp
		local data = treeMap:getData(pos.x, pos.y, pos.z)
		if shouldInspect(data) then
			local blockName, data = self:inspectUp(true)
			rememberBlock(pos, data)
		end
	end
	local function inspect(dir)
		if not dir then dir = self.orientation end
		local pos = self.pos + self.vectors[dir]
		local data = treeMap:getData(pos.x, pos.y, pos.z)
		if shouldInspect(data) then
			self:turnTo(dir)
			local hasBlock, data = self:inspect(true)
			rememberBlock(pos, data)
		end
	end
	local function inspectAll()
		-- return how many logs have been found
		local logCt = #logs

		inspectDown()
		inspectUp()
		local orientation = self.orientation
		for i=0,3 do
			local dir = (orientation+i)%4
			inspect(dir)
		end

		return #logs - logCt
	end


	local function getRoot()
		-- find the root block of the tree
		-- its the lowest block in the whole tree
		local minX, minY, minZ = nil, math.huge, nil
		local log = treeMap.log
		for i = 1, #log do 
			local entry = log[i]
			local chunkId, relativeId, data = entry[1], entry[2], entry[3]

			if checkLogBlock(data) then 
				local x, y, z = ChunkyMap.idsToXYZ(chunkId, relativeId)
				if y < minY then 
					minX, minY, minZ = x, y, z
				end
			end
		end

		if minX then 
			return vector.new(minX, minY, minZ)
		else
			print("no root found")
			return nil
		end
	end

	local function getTrunk()
		-- largest collection of logs with state.axis == y
		-- or any blocks directly above / connected to the root

	end


	local bfs = BreadthFirstSearch()
	local options = { maxDistance = 3, returnPath = true}


	local function followPath(path, safe, stepOffset)
		-- "interrupting" this func is not possible due to main logic in Miner:navigate

		local result = true
		if safe == nil then safe = true end

		-- only move to the second-to-last step, no need to mine the block at the goal position

		for i=1, #path-stepOffset do
			local step = path[i]
			if step.pos ~= self.pos  then
				local diff = step.pos - self.pos
				local upDown = 0
				
				local newOr = self:getTargetOrientation(step.pos.x, step.pos.y, step.pos.z)
				if not newOr then
					if diff.y < 0 then upDown = -1
					else upDown = 1 end
				end

				local block = treeMap:getBlockName(step.pos.x, step.pos.y, step.pos.z)
				local moveBackwards = newOr and (newOr-2)%4 == self.orientation and block == 0

				-- inspect as much as possible without additional movement
				if i > 1 then
					if upDown ~= 1 then inspectUp() end
					if upDown ~= -1 then inspectDown() end
					if not newOr or newOr ~= self.orientation then inspect() end -- and not moveBackwards
				end

				if upDown > 0 then
					if not self:digMoveUp(safe) then result = false; break end
				elseif upDown < 0 then
					if not self:digMoveDown(safe) then result = false; break end
				else
					if moveBackwards then
						if not self:back() then
							self:turnTo(newOr)
							if not self:digMove(safe) then result = false; break end
						end
					else
						self:turnTo(newOr) -- TODO: turn, inspect, turn, inspect
						if not self:digMove(safe) then result = false; break end
					end
				end

			end 
		end

		if result and stepOffset > 0 then
			local lastStep = path[#path]
			if lastStep then 
				self:turnToPos(lastStep.pos.x, lastStep.pos.y, lastStep.pos.z)
			end
			-- print("FACING", lastStep.pos) -- !! could also be above or below
		end

		if result and #path > 0 then
			inspect()
			inspectUp()
			inspectDown()
		end

		return result
	end

    -- while mining a tree, allow normal navigation to mine through tree blocks
    -- otherwise pickup tasks etc. will become very hard to pathfind
    -- TODO!: disallow Dirt blocks / blocks to place tree on!!

	local function addAllowedBlocks()
		-- temporarily add leaf blocks as valid minable blocks for digMove etc.
		local addedMineBlocks = {}
		for k,v in pairs(leafBlocks) do
			if not mineBlocks[k] then
				mineBlocks[k] = v
				addedMineBlocks[k] = true
			end
		end
		return addedMineBlocks
	end
	local function removeAllowedBlocks(blocks)
		-- remove previously added leaf blocks from minable blocks
		for k,v in pairs(blocks) do
			mineBlocks[k] = nil
		end
	end

	local function navigateTree(tx, ty, tz)
		-- navigate using only air
		local options = {
			safe = false, 
			-- to allow mining through tree specific blocks
			-- alternatively addAllowedBlocks and remove them afterwards
			checkValidFunc = function(blockName) return blockName == 0 end,
			followFunc = followPath,
			maxDistance = 20,
			stepOffset = 1, -- stop one block before target
		}
		return self:navigate(tx, ty, tz, treeMap, options)
	end

	local function digToPosUsingLeaves(tx, ty, tz)

		-- idea+optimization: instead of normal digtopos:
			-- try to dig to pos using potentially surrounding leaves (if no logs are there)
			-- could reveal more hidden logs but also increase chance to get saplings back
			-- also solves the issue of the map not being 100% accurate
		-- not quite sure though if this actually helps the edge cases...

		-- prefer y axis to maybe find new logs


		-- caution: using this func to dig toward a leaf with low distance (e.g. 3)
		--          might lead to the leaf being cut from the log. but it is replaced with another entry
		-- not an issue but perhaps reevaluating the target leaf could help avoid unnecessary movement

		local safe = false
		local result = true

		--print("digTo", tx, ty, tz)
		local cx, cy, cz = self.pos.x, self.pos.y, self.pos.z

		if cx == tx and cy == ty and cz == tz then
			return true
		end

		local allVectors = {
			vectors[0],
			vectors[1],
			vectors[2],
			vectors[3],
			vectorUp,
			vectorDown,
		}

		local neighbourVectors = {}
		local xdir, yvec, zdir

		if cx < tx then xdir = 3
		elseif cx > tx then xdir = 1 end

		if cz < tz then zdir = 0
		elseif cz > tz then zdir = 2 end

		if cy < ty then yvec = vectorUp
		elseif cy > ty then yvec = vectorDown end

		if yvec then table.insert(neighbourVectors, yvec) end
		if xdir then table.insert(neighbourVectors, vectors[xdir]) end
		if zdir then table.insert(neighbourVectors, vectors[zdir]) end
		
		-- local logsFound = inspectAll()
		-- do sparse inspection without having to turn so much
		inspect(); inspectUp(); inspectDown()
		
		repeat
			local cpos, nextPos = self.pos, nil


			-- check if our target is directly adjacent
			if manhattanDistance(cpos.x, cpos.y, cpos.z, tx, ty, tz) == 1 then
				-- ignore all other neighbours, go directly to target
				nextPos = vector.new(tx, ty, tz)
			else

				-- check neighbours 
				local relevantNeighbours, relevantSet = {}, {}
				local irrelevantNeighbours = {}

				-- neighbours on the path towards target
				for _, vec in ipairs(neighbourVectors) do
					relevantSet[vec] = true
					table.insert(relevantNeighbours, cpos + vec)
				end

				-- neighbours that do not lead towards target
				for _, vec in ipairs(allVectors) do
					if not relevantSet[vec] then
						table.insert(irrelevantNeighbours, cpos + vec)
					end
				end

				-- check irrelevant neighbours for logs first
				for _, neighbour in ipairs(irrelevantNeighbours) do
					local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z
					local ndata = treeMap:getData(nx, ny, nz)
					if checkLogBlock(ndata) then
						-- found log block nearby, go there first
						-- cancel current digToPos, add it back to the queue for later
						-- prioritize newly found log
						priorityLogPos = vector.new(nx, ny, nz)
						print("interrupting, found log", nx, ny, nz)
						return "interrupted", neighbour
					end
				end

				-- check relevant neighbours and choose preferable path
				for i, neighbour in ipairs(relevantNeighbours) do
					local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z
					neighbour.dir = neighbourVectors[i]
					local ndata = treeMap:getData(nx, ny, nz)
					neighbour.data = ndata
					if checkLeafBlock(ndata) then
						neighbour.distance = ndata.state.distance
					elseif checkLogBlock(ndata) then
						-- logs should not be present here except its the target itself?
						neighbour.distance = 0
					else
						neighbour.distance = 666
					end
				end
				table.sort(relevantNeighbours, function(a,b) return a.distance < b.distance end)
				-- simply go by the "leaf" with the lowest distance if such a leaf exists
				nextPos = relevantNeighbours[1]
			end

			-- actually move
			local diff = nextPos - self.pos
			if diff.y > 0 then
				if not self:digMoveUp(safe) then result = false; break end
			elseif diff.y < 0 then
				if not self:digMoveDown(safe) then result = false; break end
			else
				local newOr
				if diff.x ~= 0 then newOr = xdir
				elseif diff.z ~= 0 then newOr = zdir end
				self:turnTo(newOr)
				if not self:digMove(safe) then result = false; break end
			end
			treeMap:setMined(self.pos.x, self.pos.y, self.pos.z)
			inspect(); inspectUp(); inspectDown()

			-- remove vectors for axes we've already reached
			local filtered = {}
			for _, vec in ipairs(neighbourVectors) do
				local keep = not ((self.pos.x == tx and vec.x ~= 0) or
								(self.pos.y == ty and vec.y ~= 0) or
								(self.pos.z == tz and vec.z ~= 0))
				if keep then
					table.insert(filtered, vec)
				end
			end
			neighbourVectors = filtered

		until ( self.pos.x == tx and self.pos.y == ty and self.pos.z == tz ) or result == false

		return result
	end

	local function checkPlausibleDistance(leafPos, data)
		-- check distance of branch leaves to other logs
		-- if its possible to reach it within distance, if not it suggests there is another log 
		-- hidden in the branch

		-- e.g. 
		-- LOG, 	LEAF(dist1)	???
		-- LOG, 	AIR, 		LEAF(dist2) 
		
		--> to get to the next known log, LEAF must be distance 3, but it has 2
		--> mine this leaf and check if (moving away from trunk) there is a log
		--> could also just be a LOG further up, which hasnt been explored yet but is still connected
		-- use pathfinder to determine distance to nearest log block? if it is bigger than distance, the leaf should be mined

		--[[
			if leav.state.distance > 1 and leaf.state.distance <= 3 then 
				local start = leafPos
				local goal = ?   -- check all log blocks? -> could also just use BFS instead of pathfinding
				local pathFinder = PathFinder()
				pathFinder.checkValid = -- not turtle, not air, preferrably leaves or unknown
				local path = pathFinder:aStarPart(self.pos, self.orientation, goal , self.map, nil)
				local moves = #path 
				if moves > leaf.state.distance then 
					-- mine leaf
				end
			end
		--]]

		-- using bfs instead of astar, because we dont know what the next log is, and thus have no target to pathfind towards
		-- instead we find the nearest log block with bfs

		-- using self.map is not recommended, since it might contain old data when the tree didnt exist yet
		-- or another tree in the same spot has been felled before
		-- create an additional local map for each tree
		-- though if multiple turtles are felling the same tree, this could lead to issues

		-- the map also needs to remember when a block has been mined / inspected
		-- this way we can do the plausibility check for the time the leaf was inspected
		-- and we can also check for logs that have only been expected in the furture (after leaf was instpected, not before)

		local excludeAir = true -- due to leaf decay
		local reconstructedMap = treeMap:reconstructMapAtTime(data.time, excludeAir)
		local getMapBlock = function(x, y, z)
			return reconstructedMap:getBlockName(x, y, z)
		end

		options.maxDistance = data.state.distance

		local path = bfs:breadthFirstSearch(leafPos, checkGoalLeafBFS, checkValidLeafBFS, getMapBlock, options)
		local moves = ( path and #path - 1 ) or math.huge

		if not path or moves > data.state.distance then
			print("BFS mvs", moves, "leaf", leafPos, "dst",  data.state.distance, "max", options.maxDistance)
			return false -- not plausible
		else
			return true -- plausible
		end
	end


	local function getActions(fromPos, fromOr, toPos)
		-- estimate number of actions (turns) to get from fromPos to toPos
		-- used for prioritizing logs

		local diff = toPos - fromPos
		local targetOr
		if diff.x < 0 then targetOr = 1
		elseif diff.x > 0 then targetOr = 3
		elseif diff.z < 0 then targetOr = 2
		elseif diff.z > 0 then targetOr = 0 end

		local actions = 0

		-- up/down, over front, over rest
		if targetOr == fromOr then 
			actions = 0.5
		elseif not targetOr then 
			actions = 0
		else
			local turnDiff = (targetOr - fromOr) % 4
			actions = math.min(turnDiff, 4 - turnDiff)
		end

		return actions
	end


	local function mineTowardsLog(leafPos, leafData)
		-- use leaf gradient descent to find the next log
		-- recursive intersecations are theoretically possible
		-- LOG - LEAF - LEAF - LEAF - LOG
		--              LEAF
		-- leaf has distance 3 but two possible paths to logs

		-- pick a random possible path,
		-- the other leaf is added to distanceLeaves for later processing anyways

		local dist = ( leafData and leafData.state.distance ) or maxDistance
		local minDist = dist
		local minPos, minData = nil, nil
		local x, y, z = leafPos.x, leafPos.y, leafPos.z

		inspectAll()
		local neighbours = bfs.getCardinalNeighbours(x, y, z)
		for i, npos in ipairs(neighbours) do
			local nx, ny, nz = npos.x, npos.y, npos.z
			local ndata = treeMap:getData(nx, ny, nz)

			if checkLeafBlock(ndata) and ndata.state.distance < minDist then
				-- all leaves with a smaller distance are candidates for next step
				-- however we only care about the smallest (usually only for the first step though)
				minDist = ndata.state.distance
				minPos = npos
				minData = ndata
				
			elseif checkLogBlock(ndata) then
				-- found log!
				print("mtl, log", nx, ny, nz, "from leaf", x,y,z)
				local result = digToPosUsingLeaves(nx, ny, nz)
				if result == "interrupted" then
					print("SHOULDNT HAPPEN, 2")
					return false
				elseif result then
					return true
				else
					print("mtl, cannot reach log", nx, ny, nz)
				end
			end
		end

		if minPos then
			local nx, ny, nz = minPos.x, minPos.y, minPos.z
			local ndata = minData
			local result = digToPosUsingLeaves(nx, ny, nz)
			if result == "interrupted" then
				print("SHOULDNT HAPPEN, 1")
				return false
			elseif result then
				print("mtl, leaf", nx, ny, nz, "dst", ndata.state.distance)
				return mineTowardsLog(minPos, ndata) -- recursive call towards log
			else
				print("mtl, cannot reach leaf", nx, ny, nz)
			end

			-- let the basic logic of mineLeaves handle multiple leaves and recall this func	
		end
	end

	local its = 0
	local maxIts = 256
	local firstGradientPass = false

	local function mineLogsDFS()

		while #logs > 0 and its < maxIts do

			its = its + 1
			-- pick next log to mine
			local pos, logDist
			if priorityLogPos then
				-- use prioritized log (usually leading outwards)
				pos = priorityLogPos
				priorityLogPos = nil
				logDist = manhattanDistance(self.pos.x, self.pos.y, self.pos.z, pos.x, pos.y, pos.z)
			else
				-- use the closest log 

				local cpos, cor = self.pos, self.orientation
				local cx, cy, cz = cpos.x, cpos.y, cpos.z
				local log = logs[1]
				local closestId = 1
				local closestDist = manhattanDistance(cx, cy, cz, log.x, log.y, log.z)
				local minActions = getActions(cpos, cor, log)

				for i = 2, #logs do
					log = logs[i]
					local dist = manhattanDistance(cx, cy, cz, log.x, log.y, log.z)
					if dist < closestDist then
						closestDist = dist
						closestId = i
					elseif dist == closestDist then
						-- same distance, prefer smaller action count
						local actions = getActions(cpos, cor, log)
						if actions < minActions then
							minActions = actions
							closestId = i
						end

					end
				end
				pos = table.remove(logs, closestId)
				logDist = closestDist
			end

			-- mine logs DFS
			local x, y, z = pos.x, pos.y, pos.z
			local data = treeMap:getData(x, y, z)

			if data and data.name ~= 0 then

				if logDist > 1 and not firstGradientPass then 
					-- continuous log streak broken -> use leaf gradient for next log
					table.insert(logs, pos) -- requeue current log
					firstGradientPass = true
					if mineTowardsLog(self.pos, nil) then 
						-- could fail if no leaves are around
					end
					-- we only want to do this once though? -- perhaps also remove again
					-- TODO? maybe prefer going upwards first and only triggering this when moving back down?
					-- (actions determine what direction is preferred, currently the one in front, then up)
					-- when pos.y > self.pos.y
				end

				if logDist <= 1 or firstGradientPass then
					-- after first gradient pass, mine all remaining logs directly

					-- print("log at", pos)
					local result = digToPosUsingLeaves(x, y, z)

					if result == "interrupted" then
						-- requeue current log and pick new log
						if self.pos.x ~= x or self.pos.y ~= y or self.pos.z ~= z then
							table.insert(logs, pos)
						end
					elseif result then 
						inspectAll()
					else
						print("Cannot reach log at", pos)
					end
				end
			end
		end

	end

	local uncheckedLeaves = {}

	local function mineLeaves()
		print("MINING LEAVES WITH LOW DISTANCE")

		-- indexed priority list for leaves based on distance
		-- or just go by the nearest leaf, to save on movement?

		while true do 

			-- get next leaf with lowest state.distance and distance to turtle
			local cpos = self.pos
			local cx, cy, cz = cpos.x, cpos.y, cpos.z

			local key, pos, distance
			for dist = 1, #distanceLeaves do
				local leaves = distanceLeaves[dist]

				if next(leaves) then
					distance = dist
				
					local minDist = math.huge
					for k, p in pairs(leaves) do 
						local ldist = manhattanDistance(cx, cy, cz, p.x, p.y, p.z)
						if ldist < minDist then
							minDist = ldist
							key, pos = k, p
						end
					end
					break
				end
			end

			if not pos then break end

			local x, y, z = pos.x, pos.y, pos.z

			distanceLeaves[distance][key] = nil
			leafDistanceMap[key] = nil

			local data = treeMap:getData(x, y, z)
			if data and data.name ~= 0 and checkLeafBlock(data) then 
				local currentDist = data.state.distance

				if currentDist ~= distance then
					-- leaf distance changed
					distanceLeaves[currentDist][key] = pos
					leafDistanceMap[key] = currentDist

				elseif currentDist <= 1 then 
					print("leaf at", pos, "dst", currentDist)
					local result = digToPosUsingLeaves(x, y, z)
					if result == "interrupted" then
						-- requeue current leaf, call mineLogsDFS
						distanceLeaves[currentDist][key] = pos
						leafDistanceMap[key] = currentDist
					elseif result then 
						inspectAll()
					else
						print("Cannot reach leaf at", pos)
					end

				elseif currentDist <= reinspectionDistance and not checkPlausibleDistance(pos, data) then
					local result = digToPosUsingLeaves(x, y, z)
					if result == "interrupted" then
						-- requeue current leaf
						distanceLeaves[currentDist][key] = pos
						leafDistanceMap[key] = currentDist
					elseif result then 
						
						if not mineTowardsLog(pos, nil) then -- data
							-- shouldnt happen, but lets chalk it up to faster inspection than distance values can be updated
							-- also leaf decay could perhaps cause this
							-- check commit 4365578 for more debugging stuff
							print("no log from leaf", pos, "dst", currentDist)
						end
					else
						print("Cannot reach leaf at", pos)
					end

				elseif currentDist < maxDistance then
					-- requeue leaves that theoretically could still have logs, but unlikely
					uncheckedLeaves[key] = pos
				end
			end

			-- mine logs found after mining leaves
			mineLogsDFS()

		end
	end

	local Queue = require("classQueue")

	local function getLeafGroup(start, visited)
		-- bfs like search so we get all connected leaf blocks within distance 6
		-- also calculate centroid and representative

		local components = {}
		local group = { components = components }
		local sumX, sumY, sumZ = 0, 0, 0

		local queue = Queue:new()
		local start = { x = start.x, y = start.y, z = start.z, distance = 0 }
		queue:pushRight(start)

		while true do
			local current = queue:popLeft()
			if not current then break end

			local cx, cy, cz, cdist = current.x, current.y, current.z, current.distance
			table.insert(components, vector.new(cx, cy, cz))
			sumX = sumX + cx
			sumY = sumY + cy
			sumZ = sumZ + cz

			if cdist < 6 then
				local neighbours = bfs.getCardinalNeighbours(cx, cy, cz)
				for i = 1, #neighbours do
					local neighbour = neighbours[i]
					local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z

					local vx = visited[nx]
					if not vx then vx = {}; visited[nx] = vx end
					local vy = vx[ny]
					if not vy then vy = {}; vx[ny] = vy end
					if not vy[nz] then 
						vy[nz] = true

						local ndata = treeMap:getData(nx, ny, nz)
						if checkLeafBlock(ndata) then
							neighbour.distance = cdist + 1
							queue:pushRight(neighbour)
						end
					end
				end
			end
		end
		local ct = #components
		local centroidX = sumX / ct
		local centroidY = sumY / ct
		local centroidZ = sumZ / ct
		group.centroid = { x = centroidX, y = centroidY, z = centroidZ }
		local representative = start

		-- get representative of group (nearest to centroid)
		local minDist = math.huge
		for i = 1, #components do
			local comp = components[i]
			local dist = manhattanDistance(centroidX, centroidY, centroidZ, comp.x, comp.y, comp.z)
			if dist < minDist then
				minDist = dist
				representative = comp
			end
		end
		group.representative = vector.new(representative.x, representative.y, representative.z)

		return group
	end

	local function reinspectLeafGroups(remainingLeaves)
		-- find connected leaf groups and reinspect a single one
		-- since they are within 6 blocks of each other, 
		-- one inspection guarantees that no logs are contained if distance is 7
		-- though navigating to the groups can cut off groups
		-- exclude groups of 1 -> usually lead nowhere useful or are nearby other groups

		local groups = {}
		local visited = {}
		local groupCreationTime = osEpoch()

		for key, pos in pairs(remainingLeaves) do
		
			local sx, sy, sz = pos.x, pos.y, pos.z
			local ndata = treeMap:getData(sx, sy, sz)
			-- check if leaf still exists
			if checkLeafBlock(ndata) then
				local vx = visited[sx]
				if not vx then vx = {}; visited[sx] = vx end
				local vy = vx[sy]
				if not vy then vy = {}; vx[sy] = vy end
				if not vy[sz] then
					vy[sz] = true

					local group = getLeafGroup(pos, visited)
					if #group.components > 1 then
						table.insert(groups, group)
					end
				end
			end
		end

		print("found", #groups, "leaf groups")

		local unvisitedGroups = {}
		for i = 1, #groups do unvisitedGroups[i] = true end

		while next(unvisitedGroups) do 
			-- -- find nearest group based on representative
			local cpos = self.pos
			local cx, cy, cz = cpos.x, cpos.y, cpos.z

			local closestGroupId
			local minDist = math.huge

			for i, _ in pairs(unvisitedGroups) do
				local rep = groups[i].representative
				local dist = manhattanDistance(cx, cy, cz, rep.x, rep.y, rep.z)
				if dist < minDist then
					minDist = dist
					closestGroupId = i
				end
			end

			local group = groups[closestGroupId]
			unvisitedGroups[closestGroupId] = nil

			-- process the group
			-- pick nearest leaf of group to reinspect
			-- also check if a leaf has been updated while processing other groups
			-- if ANY not updated leaf has distance >= 7, skip the group
			-- if ALL updated leaves have distance >= 7, skip the group
			
			local hasUpdatedLeaf, allUpdatesDistant = false, true
			local components = group.components
			local closestLeafId
			minDist = math.huge
			for i = 1, #components do
				local comp = components[i]
				local dist = manhattanDistance(cx, cy, cz, comp.x, comp.y, comp.z)
				if dist < minDist then
					minDist = dist
					closestLeafId = i
				end

				local compData = treeMap:getData(comp.x, comp.y, comp.z)

				-- print("grpLeaf", comp.x, comp.y, comp.z, "time", compData.time, "dst", compData.state.distance)

				if checkLeafBlock(compData) then 
					if compData.time > groupCreationTime then
						-- leaf has been updated since group creation
						-- all updated leaves must be >= 7 to skip the group
						hasUpdatedLeaf = true
						if compData.state.distance < maxDistance then 
							allUpdatesDistant = false
						end
					elseif compData.state.distance >= maxDistance then
						-- found a non-updated leaf with distance 7, skip group
						-- at time of creation, groups were connected, so if one leaf is distant, the whole group is
						allUpdatesDistant = true
						hasUpdatedLeaf = true
						break
						-- TODO: check for conflicting information of leaves?
						-- only rely on most recent inspection time
					end
				end
			end

			if hasUpdatedLeaf and allUpdatesDistant then 
				-- all updated leaves will decay, skip group
				print("skipping group, inspected, size", #components)
			else

				local closestLeaf = components[closestLeafId]
				print("reinsp", closestLeaf.x, closestLeaf.y, closestLeaf.z, "size", #components, "upd", hasUpdatedLeaf)

				-- navigate to leaf, no need for inspection on the way

				-- navigateToPos is allowed to destroy blocks on the way and does not update treeMap
				-- if self:navigateToPos(closestLeaf.x, closestLeaf.y, closestLeaf.z) then 

				-- no need for inspection on the way though...
				-- TODO: expand PathFinder for explicitly following only air blocks or nil 
				--   (but check them for air while following the path)

				-- small issue: reinspection only happens for leaves with distance <= 3
				--  mineTowardsLog also handles leaves with distance 4 and 5
				

				local result = navigateTree(closestLeaf.x, closestLeaf.y, closestLeaf.z)
				-- makes it much faster to recheck certain leaves compared to digTo
				-- local result = digToPosUsingLeaves(closestLeaf.x, closestLeaf.y, closestLeaf.z)
				if result == "interrupted" then 
					-- found new log on the way, add group back to unvisitedGroups
					unvisitedGroups[closestGroupId] = true
					-- we are out of the main mining loop, so call mineLogsDFS again
					mineLogsDFS()

				elseif result then 
					-- if a surrounding leaf is < 7, then mine towards log
					setReinspectionDistance(6)
					-- not from closestLeaf but from current pos
					if mineTowardsLog(self.pos, nil) then
						print("found a log")
					end
					restoreReinspectionDistance()
					-- TODO: what if multiple logs are contained? they wont be caught
					-- update the group again using bfs floodfill?

				else
					print("unable to reach group", closestLeaf.x, closestLeaf.y, closestLeaf.z)
				end
			end
		end
	end

    local addedAllowedBlocks = addAllowedBlocks()

	-- initial pass
	inspectAll()
	-- mine all connected logs
	mineLogsDFS()
	-- do a second pass over leaves with distance 1
	mineLeaves()
	-- group remaining leaves and reinspect one of each group
	reinspectLeafGroups(uncheckedLeaves)
	-- do a final log check, usually there shouldnt be any
	mineLogsDFS()

	-- perhaps also do a final gradient pass to find any remaining logs
	-- mineTowardsLog(self.pos, nil)
	-- rather not, could lead to mining neighbouring trees

	-- todo: set a max distance for the tree size from trunk?
	-- or detect that we entered another tree by detecting its trunk?

	local root = getRoot()
	print("tree ded","root", root)

	--return to start
	self:navigateToPos(startPos.x, startPos.y, startPos.z)
	self:turnTo(startOrientation)

    removeAllowedBlocks(addedAllowedBlocks)

	self.taskList:remove(currentTask)
end

function Extension:growTree()

	local grown = false

	local saplingItem = "minecraft:oak_sapling"
    local bonemealItem = "minecraft:bone_meal"
	local sapling = self:findInventoryItem(saplingItem)
	local bonemeal = self:findInventoryItem(bonemealItem)

    if not bonemeal then
        -- try to pickup some bonemeal first
        local ok, count = self:pickupItems(bonemealItem, 16)
        if ok then
            bonemeal = self:findInventoryItem(bonemealItem)
        else
            print("Pickup bonemeal failed")
        end
    end

    if not sapling then
        -- try to pickup some saplings first
        local ok, count = self:pickupItems(saplingItem, 4)
        if ok then
            sapling = self:findInventoryItem(saplingItem)
        else
            print("Pickup sapling failed")
        end
    end

	if sapling and bonemeal then 
		self:select(sapling)
		local ok, reason = self:place()
		if not ok then
			local blockName, data = self:inspect(true)
			if blockName == saplingItem then
				-- already planted
				ok = true
			else
				print("Placing sapling failed:", reason)
			end
		end
		if ok then
			-- use bonemeal until tree grows
			self:select(bonemeal)
			
			local maxAttempts = 64
			local attempts = 0
			repeat
				attempts = attempts + 1
				local ok, reason = self:place()
				if not ok then
					if reason == "Cannot place item here" then
						-- probably already grown
						local blockName, data = self:inspect(true)
						if blockName and logBlocks[blockName] then
							grown = true
						end
					elseif reason == "No items to place" then
						bonemeal = self:findInventoryItem(bonemealItem)
						if not bonemeal then
							print("Out of bonemeal")
							-- now we can finally use the storage system to request arbitrary items
							-- TODO: requestItem -> storage reserves them -> pickup -> back to job
							-- very cool, like refuel but for any item
							-- pickup location also need a queue, but can be managed by storage provider instead of turtles
							-- but doesnt have to be
							-- new classTurtleStorage -> also add pickupAndDeliver there
							-- has to somehow extend the classMiner, cant all be in here
							-- 
                            local ok, count = self:pickupItems(bonemealItem, 16)
                            if ok then
                                bonemeal = self:findInventoryItem(bonemealItem)
                                if not bonemeal then
                                    print("Pickup bonemeal failed it seems", ok, count)
                                    -- intentionally fail to trace this error
                                    -- if ok, then we should also have bonemeal in the inventory
                                    -- host: extracted 0 of bonemeal to turtle
                                    -- turtle got ok though count is 0?
                                    --> provider thought he had more items than he actually had.
                                    --> res was confirmed, so turtle got ok, but no items were extracted
                                    self:select(bonemeal)
                                    break
                                end
                                self:select(bonemeal)
                            else
                                print("Pickup bonemeal failed")
                                break
                            end
							
						else
							self:select(bonemeal)
							ok = true
						end
					end
					if not ok and not grown then
						print("Using bonemeal failed:", reason)
					end
				end
			until grown or attempts >= maxAttempts
		end
	end

	if not grown then
		print("Failed to grow tree")
	end
	return grown
end

function Extension:fellTree()

	-- inspect for wood
	-- mine wood until none found (can use mineVein?)
	-- track leave metadata while felling? -> no, changes while felling
	-- instead: after wood is removed, inspect surrounding blocks for leaves
	-- check leaves state for distance = 1 to 6   -- distance 7 is not generated by tree gen
	-- if found, mine in direction of lowest distance to find wood blocks
	-- check nearest leave blocks again for distance
	-- repeat until no leaves with distance found
	-- but do not mine all leaves

	-- could also use a breadth first search for leaves
	-- or update the distance of leaves after mining wood blocks using own algorithm
	-- then return to leaves that could still be connected to wood
	-- segment the tree?

	--[[
		{
		state = {
			waterlogged = false,
			persistent = false,
			distance = 6,
		},
		name = "minecraft:oak_leaves",
		tags = {
			[ "minecraft:replaceable_by_trees" ] = true,
			[ "computercraft:turtle_hoe_harvestable" ] = true,
			[ "minecraft:parrots_spawnable_on" ] = true,
			[ "computercraft:turtle_always_breakable" ] = true,
			[ "minecraft:lava_pool_stone_cannot_replace" ] = true,
			[ "minecraft:mineable/hoe" ] = true,
			[ "minecraft:completes_find_tree_tutorial" ] = true,
			[ "minecraft:leaves" ] = true,
			[ "minecraft:sword_efficient" ] = true,
		},
		}
	--]]

	-- then somehow make sure to collect saplings to make it self sufficient

end

return Extension