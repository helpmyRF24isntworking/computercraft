local BreadthFirstSearch = {}
BreadthFirstSearch.__index = BreadthFirstSearch

local Queue = require("classQueue")

local abs = math.abs
local tableinsert = table.insert
local osEpoch = os.epoch

local function checkValid(block)
	if block then return false
	else return true end
end


local function newBreadthFirstSearch(template, checkValidFunc)
    return setmetatable( {
        checkValid = checkValidFunc or checkValid,
    }, template )
end


local function reconstructPath(current)
	local path = {}
end


function BreadthFirstSearch.getCardinalNeighbours(cx, cy, cz)

	-- only use cardinal directions + up/down
	return { 
		{ x =  cx + 0, y = cy + 0, z = cz + 1 }, -- south
		{ x =  cx + 0, y = cy + 1, z = cz + 0 }, -- up
		{ x =  cx + 0, y = cy - 1, z = cz + 0 }, -- down
		{ x =  cx - 1, y = cy + 0, z = cz + 0 }, -- west
		{ x =  cx + 1, y = cy + 0, z = cz + 0 }, -- east
		{ x =  cx + 0, y = cy + 0, z = cz - 1 }, -- north
	}
end
local getNeighbours = BreadthFirstSearch.getCardinalNeighbours

function BreadthFirstSearch:breadthFirstSearch(startPos, checkGoal, checkValid, getBlock, options)
    --[[
        Performs a breadth-first search from startPos
		-- only useful if goal is not known in advance but rather a condition to be met
		-- for specific routing, astar is better suited
        
        Parameters:
        - startPos: Starting position (table with coordinates, e.g., {x=0, y=0, z=0})
        - checkGoal: function(pos, data) that returns true when goal is found
        - checkValid: function(pos) that returns true if the position is valid to move into
        - getBlock: function(x,y,z) that returns block name at given position
        - options: (optional) table with:
            - maxDistance: maximum search distance (default: nil, unlimited)
            - maxNodes: maximum nodes to explore (default: nil, unlimited)
            - returnPath: if true, returns path array; if false, returns goal pos (default: false)
            - returnAll: if true, returns all visited nodes with distances (default: false)
        
        Returns:
        - If returnPath: array of positions from start to goal, or nil if not found
        - If returnAll: table of {pos -> distance} for all visited nodes
        - Otherwise: {pos=goalPos, distance=distance, parent=parentPos} or nil if not found
    --]]
    
    options = options or {}
    local maxDistance = options.maxDistance
    local returnPath = options.returnPath
	local checkValid = checkValid or function() return true end
    
    local queue = Queue:new()
    local visited = {}  -- visited[key] = {pos=pos, distance=distance, parent=parentKey}
    local nodesExplored = 0
    

    local sx, sy, sz = startPos.x, startPos.y, startPos.z
	local start = { x=sx, y=sy, z=sz, distance=0 }

	if checkGoal(sx, sy, sz) then
		if returnPath then
			return { vector.new(sx, sy, sz) }
		else
			return vector.new(sx, sy, sz), 0
		end
	end

    visited[sx] = { [sy] = { [sz] = true } }
    queue:pushRight(start)
    
    while true do
        local current = queue:popLeft()
        if not current then break end
		local cx,cy,cz,cdist = current.x, current.y, current.z, current.distance
        
		-- Check if max nodes limit reached optional bs
        nodesExplored = nodesExplored + 1
        -- if maxNodes and nodesExplored > maxNodes then break end

        -- Check if max distance reached
        if maxDistance and cdist >= maxDistance then
			break
		else
        
			-- Explore neighbors
			local neighbours = getNeighbours(cx, cy, cz)
			for i = 1, #neighbours do 
				local neighbour = neighbours[i]
				local nx, ny, nz = neighbour.x, neighbour.y, neighbour.z
				local vx = visited[nx]
				if not vx then vx = {}; visited[nx] = vx end
				local vy = vx[ny]
				if not vy then vy = {}; vx[ny] = vy end
				if not vy[nz] then 
					vy[nz] = true

					
					neighbour.previous = current
					neighbour.distance = current.distance + 1

					local block = getBlock(nx, ny, nz)
					if checkGoal(block) then
						-- can stop search early, since its bfs
						if returnPath then
							-- Reconstruct path
							local path = {}
							local node = neighbour
							while node do
								table.insert(path, 1, vector.new(node.x, node.y, node.z))
								node = node.previous
							end
							return path
						else
							return vector.new(nx, ny, nz), neighbour.distance
						end
					end

					if checkValid(block) then 
						queue:pushRight(neighbour)
					end
				end
			end
		end
    end
    
	-- print("BFS: NO PATH FOUND", nodesExplored)
    return nil 
end

return setmetatable( BreadthFirstSearch, { __call = function( self, ... ) return newBreadthFirstSearch( self, ... ) end } )