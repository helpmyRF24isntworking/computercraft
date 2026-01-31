
-- class to split a single mining task into multiple
-- according to how many turtles are available

local default = {
	groupSize = 5,
	width = 20,
	height = 10,
	yLevel =  {
		top = 73,
		bottom = -60,
	}
}

TaskGroup = {}

function TaskGroup:new(turtles, groupSize, obj)
	local o = obj or {
		taskName = nil,
		--.tasks = {}
		area = nil,
		groupSize = groupSize or default.groupSize or nil,
		assignments = nil,
		id = nil,
		startTime = os.epoch("ingame"),
	}
	setmetatable(o, self)
	self.__index = self
	
	o.turtles = turtles or nil
	
	if not obj then 
		o:initialize()
	end
	
	return o
end

function TaskGroup:initialize()
	self:setGroupSize(self.groupSize)
	self.id = self:generateUUID()
end

function TaskGroup:generateUUID()
	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	return string.gsub(template, '[xy]', function (c)
		local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format('%x', v)
	end)
end

function TaskGroup:getProgress()
	-- weigh the progress of all turtles according to their assigned area volume
	local totalVolume = 0
	local accumulatedProgress = 0
	local assignments = self.assignments
	local turtles = self.turtles
	if assignments then
		for _,assignment in ipairs(assignments) do
			local turtle = turtles[assignment.turtleId]
			local progress = turtle.state.progress or 0
			local area = assignment.area
			local volume = (math.abs(area.start.x - area.finish.x)+1) *
				(math.abs(area.start.y - area.finish.y)+1) *
				(math.abs(area.start.z - area.finish.z)+1)
			totalVolume = totalVolume + volume
			accumulatedProgress = accumulatedProgress + (progress * volume)
		end
	end
	if totalVolume > 0 then
		return accumulatedProgress / totalVolume
	else
		return 0
	end
end


function TaskGroup:getActiveTurtles()
	local count = 0
	if self.assignments then
		for _,assignment in ipairs(self.assignments) do
			local turtle = self.turtles[assignment.turtleId]
			if not turtle or not turtle.state.online 
				or turtle.state.task == nil then
				-- inactive
			else
				count = count + 1
			end
		end
	end
	return count
end

function TaskGroup:getAvailableTurtles()
	local result = {}
	local count = 0
	for id,turtle in pairs(self.turtles) do
		if turtle.state.online and turtle.state.task == nil then
			count = count + 1
			table.insert(result, turtle)
		end
	end
	return count, result
end

function TaskGroup:countAvailableTurtles()
	local ct, turtles = self:getAvailableTurtles()
	return ct
end
function TaskGroup:setGroupSize(groupSize)
	availableCount, availableTurtles = self:getAvailableTurtles()
	if not groupSize then
		-- use default groupSize
		if availableCount >= default.groupSize then
			groupSize = default.groupSize
		else
			groupSize = availableCount
		end
	elseif groupSize <= 0 then
		-- use all available turtles
		groupSize = availableCount
	elseif groupSize > availableCount then 
		-- not enough turtles available
		groupSize = availableCount
	end
	self.groupSize = groupSize
	return groupSize
end
function TaskGroup:forceGroupSize(groupSize)
	-- set the group size forcefully 
	self.groupSize = groupSize
end
function TaskGroup:setTurtles(turtles)
	self.turtles = turtles
end
function TaskGroup:setArea(start,finish)
	self.area = { start = start, finish = finish }
end
function TaskGroup:getArea()
	return self.area
end



function TaskGroup:assignAreas(areas)
	-- assign the splitted areas to available turtles
	self.assignments = {}
	local count, turtles = self:getAvailableTurtles()
	if count < #areas then 
		print("more areas than available turtles")
	end
	for i,area in ipairs(areas) do
		local assignment = {
			turtleId = turtles[i].state.id,
			area = area,
		}
		table.insert(self.assignments, assignment)
	end
	return self.assignments
end

function TaskGroup:getAssignments()
	return self.assignments
end



function TaskGroup.approximate3dDivisions(n)
	-- local nx = math.ceil(n^(1/3))
	-- local ny = math.ceil(math.sqrt(n/nx))
	-- local nz = math.ceil(n/(nx*ny))
	
	-- Start with the cube root approximation
    local k = math.floor(n ^ (1 / 3))
    local nx, ny, nz = k, k, k

    -- Adjust to make sure nx * ny * nz = n
    while nx * ny * nz < n do
        if nx <= ny and nx <= nz then
            nx = nx + 1
        elseif ny <= nx and ny <= nz then
            ny = ny + 1
        else
            nz = nz + 1
        end
    end
	-- reverse last step make sure its <= n
	if nx * ny * nz > n then 
		if nx >= ny and nx >= nz then
			nx = nx - 1
		elseif ny >= nx and ny >= nz then
			ny = ny - 1
		else
			nz = nz - 1
		end
	end
	
    return nx, ny, nz
end

function TaskGroup.approximate2dDivisions(n)
	local nx = math.floor(math.sqrt(n))
	local ny = math.floor(n/nx)
	if ny == 0 then ny = 1 end
	return nx, ny
end

function TaskGroup.partitionArea(x, y, z, n, marginx, marginy, marginz)

	-- print(x,y,z,n,marginx,marginy,marginz)
	if not marginx then marginx = 0 end
	if not marginy then marginy = 0 end
	if not marginz then marginz = 0 end

	local nx, ny, nz = TaskGroup.approximate3dDivisions(n)

	-- check minimal dimension requirements
	if math.floor(x/nx) < 3 then 
		nx = 1
		ny, nz = TaskGroup.approximate2dDivisions(n)
	end
	if math.floor(y/ny) < 3 then 
		ny = 1
		nx, nz = TaskGroup.approximate2dDivisions(n)
	end
	if math.floor(z/nz) < 3 then 
		nz = 1
		nx, ny = TaskGroup.approximate2dDivisions(n)
	end


	local rx, ry, rz = nil, nil, nil 
	local rox, roy, roz = 0, 0, 0

	local nbest = nx * ny * nz
	if nbest < n then 
		-- not perfectly split, create bigger subarea according to the biggest dimension
		if x >= y and x >= z then
			rx = math.floor(x * (1-(nbest/n)) + 0.5)
			x = x - rx - marginx
			rox = x + marginx
			ry = y
			rz = z
		elseif y >= x and y >= z then 
			ry = math.floor(y * (1-(nbest/n)) + 0.5)
			y = y - ry - marginy
			roy = y + marginy
			rx = x
			rz = z
		else
			rz = math.floor(z * (1-(nbest/n)) + 0.5)
			z = z - rz - marginz
			roz = z + marginz
			rx = x
			ry = y
		end
	else
	-- perfect split
	end

	-- actually perform the split
	
	-- usable area
	local ux = x - (nx -1)*marginx
	local uy = y - (ny -1)*marginy
	local uz = z - (nz -1)*marginz
	
	-- subarea dimensions
	local sx = math.floor(ux/nx)
	local sy = math.floor(uy/ny)
	local sz = math.floor(uz/nz)
	
	-- leftovers
	local lx = ux - sx * nx 
	local ly = uy - sy * ny
	local lz = uz - sz * nz

	local areas = {}
	local startx, starty, startz

	for i=0, nx-1 do
		local cx = sx 
		if i < lx then 
			cx = cx + 1
		end
		startx = i * (sx + marginx) + math.min(i,lx)
		for j=0, ny-1 do
			local cy = sy
			if j < ly then
				cy = cy + 1
			end
			starty = j * (sy+marginy) + math.min(j,ly)
			for k=0, nz-1 do
			local cz = sz
			if k < lz then 
				cz = cz + 1
			end
			startz = k * (sz+marginz) + math.min(k,lz)

			local area = { 
				start = { x = startx, y = starty, z = startz }, 
				finish = { x = startx + cx -1, 
				y = starty + cy -1, 
				z = startz + cz -1 }
			}
			table.insert(areas,area)

			end
		end
	end

	-- recursively split the rest until nothing is left
	if rx and ry and rz and nbest > 0 then
		print("splitting rest", rx, ry, rz, rox, roy, roz, nbest)
		local more = TaskGroup.partitionArea(rx,ry,rz,n-nbest,marginx, marginy, marginz)
		for _,area in ipairs(more) do
			area.start.x = area.start.x + rox
			area.start.y = area.start.y + roy
			area.start.z = area.start.z + roz
			area.finish.x = area.finish.x + rox
			area.finish.y = area.finish.y + roy
			area.finish.z = area.finish.z + roz
			table.insert(areas,area)
		end
	end

	return areas
end

function TaskGroup.split3dArea(start, finish, groupSize, rowMargin, levelMargin)
	
	if not rowMargin then rowMargin = 1 end
	if not levelMargin then levelMargin = 1 end
	
	
	
	local minX = math.min(start.x, finish.x)
	local minY = math.min(start.y, finish.y)
	local minZ = math.min(start.z, finish.z)
	
	local x = math.abs(start.x-finish.x)+1
	local y = math.abs(start.y-finish.y)+1
	local z = math.abs(start.z-finish.z)+1
	
	local areas = TaskGroup.partitionArea(x,y,z,groupSize,rowMargin,levelMargin,rowMargin)
	
	for _,area in ipairs(areas) do
		area.start.x = area.start.x + minX
		area.start.y = area.start.y + minY
		area.start.z = area.start.z + minZ
		area.finish.x = area.finish.x + minX
		area.finish.y = area.finish.y + minY
		area.finish.z = area.finish.z + minZ
	end
	
	print("a", "|", start.x, start.y, start.z, "|", finish.x, finish.y, finish.z,"vol", x*y*z, "x,y,z", x,y,z,"size",groupSize)
	for i,area in ipairs(areas) do
		local s = area.start
		local f = area.finish
		local vol = (math.abs(s.x-f.x)+1)*(math.abs(s.y-f.y)+1) * (math.abs(s.z-f.z)+1)
		print(i, "|", area.start.x, area.start.y, area.start.z, "|", area.finish.x, area.finish.y, area.finish.z, "vol", vol)
	end
	
	return areas
end

function TaskGroup:splitArea()
	local start = self.area.start
	local finish = self.area.finish
	local rowMargin, levelMargin = 1, 1
	if self.taskName == "mineArea" then 
		rowMargin = 2
		levelMargin = 1
	elseif self.taskName == "excavateArea" then
		rowMargin = 0
		levelMargin = 0
	end

	local areas = self.split3dArea(start,finish,self.groupSize,rowMargin,levelMargin)
	self:assignAreas(areas)
end


-- local start = { x=50,y=-58,z=50 }
-- local finish = { x=200,y=-50,z=200 }
-- local areas = subdivide(start,finish,7,1,1)
-- --local areas = splitArea(64,20,128,13,2,2,1)
-- for i,area in ipairs(areas) do
  -- local s = area.start
  -- local f = area.finish
  -- local vol = (math.abs(s.x-f.x)+1)*(math.abs(s.y-f.y)+1) * (math.abs(s.z-f.z)+1)
  -- print(i, area.start.x, area.start.y, area.start.z,area.finish.x, area.finish.y, area.finish.z, "vol", vol)
-- end


function TaskGroup:splitAAAAAArea(rowMargin, levelMargin)
	
	local start = self.area.start
	local finish = self.area.finish
	
	-- margins between areas (applied once)
	if not rowMargin then rowMargin = 1 end
	if not levelMargin then levelMargin = 1 end
	
	local minX = math.min(start.x, finish.x)
	local minY = math.min(start.y, finish.y)
	local minZ = math.min(start.z, finish.z)
	local maxX = math.max(start.x, finish.x)
	local maxY = math.max(start.y, finish.y)
	local maxZ = math.max(start.z, finish.z)
	
	local diff = finish - start
	local width = math.abs(diff.x) +1
	local height = math.abs(diff.y) +1 
	local depth = math.abs(diff.z) +1
	
	print("diff", diff)
	local areas = {}
	
	-- first split by y level
	if height / self.groupSize >= 4 then 
		-- split by y level
		local levels = self.groupSize
		local levelHeight = math.floor(height/levels)
		local restHeight = height-(levelHeight*levels)
		print("height", height, "level", levels, levelHeight, restHeight)
		
		for level = 1, levels do

			local yStart = maxY - ((level-1)*levelHeight)
			if level == levels then
				yFinish = minY
			else
				yFinish = yStart - levelHeight + levelMargin + 1
			end
			
			local areaStart = vector.new(minX, yStart, minZ)			
			local areaFinish = vector.new(maxX, yFinish, maxZ)
			table.insert(areas, { start = areaStart, finish = areaFinish })
			
		end
		
	elseif ( width*depth ) / ( 3 * 3 ) >= self.groupSize then
		-- split by x,z
	
		local columns = math.ceil(math.sqrt(self.groupSize))
		local fullRows = math.floor(self.groupSize/columns)
		local rest = self.groupSize % columns
		
		local areaWidth = math.floor(width/columns)
		local areaHeight = 0
		
		if rest == 0 then
			areaHeight = math.floor(depth/fullRows)
		else
			areaHeight = math.floor(depth/(fullRows+1))
		end
		
		print("rows", fullRows, "columns", columns, "rest", rest)
		print("widht, height", areaWidth, areaHeight)
		
		local xMargin = rowMargin
		local zMargin = rowMargin
		
		for row = 1, fullRows do
			for col = 1, columns do
				
				if col == columns then xMargin = -(math.ceil(width/columns)-areaWidth)
				else xMargin = rowMargin + 1 end
				
				if row == 1 then zMargin = 0
				--elseif row == fullRows and rest == 0 then zMargin = 0
				else zMargin = rowMargin + 1 end
				
				-- problem with n > 13 (>3 rows where finish(t-1).z == start.z
				
				local areaStart = vector.new(minX + (col-1)*areaWidth, maxY, minZ + (row-1)*areaHeight + zMargin)
				local areaFinish = vector.new(areaStart.x + areaWidth - xMargin, minY, areaStart.z + areaHeight)
				table.insert(areas, { start = areaStart, finish = areaFinish })
			end
		end
		
		if rest > 0 then
			restWidth = math.floor(width/rest)
			local zStart = minZ
			if #areas > 1 then
				zStart = areas[#areas].finish.z + rowMargin + 1
			end
			zMargin = rowMargin+1
			restHeight = depth-(areaHeight*fullRows)-zMargin
			for i = 1, rest do
				if i == rest then xMargin = -(width-(restWidth*rest))
				else xMargin = xMargin + 1 end
				
				
				print(i, "rest margin", xMargin, "rest width", restWidth, "height", restHeight, "rows", fullRows)
				
				local areaStart = vector.new(minX + (rest-1)*restWidth, maxY, zStart)
				local areaFinish = vector.new(areaStart.x + restWidth - xMargin, minY, maxZ)
				table.insert(areas, { start = areaStart, finish = areaFinish })
			end
		end
		
	else
		areas = self:split3DArea()
		-- print("area too small for group size", self.groupSize)
	end

	print("area splitted", start , "end", finish)
	for _,area in ipairs(areas) do
		print("start", area.start, "end", area.finish)
	end
	return areas
end
