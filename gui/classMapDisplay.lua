
local Button = require("classButton")
local CheckBox = require("classCheckBox")
require("classList")
local BasicWindow = require("classBasicWindow")
local Label = require("classLabel")
local utils = require("utils")
local PixelDrawer = require("classPixelDrawer")

local blockColors = require("blockColor")
local idToBlit = blockColors.idToBlit
local nameToBlit = blockColors.nameToBlit

local default = {
backgroundColor = colors.gray,
unknownColor = colors.black,
freeColor = colors.lightGray,
blockedColor = colors.gray,
disallowedColor = colors.red,
buttonColor = colors.lightBlue,
turtleColor = colors.blue,
aboveColor = colors.purple,
belowColor = colors.orange,
homeColor = colors.magenta,
circleRadius = 16 * 16, -- render distance of 16 chunks
}

local blitTab = BasicWindow.blitTab


local mathRandom = math.random
local randomChars = {
	"*", "'", ",", " ", " ", " ", " ", " ", " ", " ", " ",
	" ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ",
	" ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ",  }
local randCount = #randomChars

-- TODO: https://github.com/9551-Dev/pixelbox_lite

local MapDisplay = BasicWindow:new()
-- change to Window, not basicwindow

function MapDisplay:new(x,y,width,height,map)
	local o = o or BasicWindow:new(x,y,width,height) or {}
	setmetatable(o, self)
	self.__index = self
	
	o.map = map or {}
	o.areas = {}
	o.backgroundColor = default.backgroundColor
	
	o.mapX = 0
	o.mapY = 0
	o.mapZ = 0
	o.mapMidX = 0
	o.mapMidY = 0
	o.mapMidZ = 0
	o.zoomLevel = 1
	o.zoomBase = 1 -- TODO: when starting with 1:2, the level should be 0.5 and base 2, not 1:2
	local zoomText = o.zoomLevel < 1 and "1:"..o.zoomBase or (o.zoomLevel .. ":" .. o.zoomBase)
	self.displayTurtles = true
	self.displayHome = true
	self.displayChunkCircle = true
	self.focusId = nil
	self.focusPos = nil
	self.focusPocket = pocket and true or false
	
	o:initialize()
	
	return o
end

function MapDisplay:initialize()
	self:calculateMapMid()

	self:precomputeBackground()

	self.mapWidth = self.width*2
	self.mapHeight = self.height*3
	self.drawer = PixelDrawer:new(self.width*2, self.height*3)


	self.scrollFactor = math.floor( (self.height + self.width)/16 )
	if self.scrollFactor <= 0 then self.scrollFactor = 1 end

	self.btnClose = Button:new("X",self.width-2,1,3,3,colors.red)
	self.btnClose.click = function() return self:close() end

	self.btnLeft = Button:new("<",1,self.midHeight,3,3,default.buttonColor)
	self.btnRight = Button:new(">",self.width-2,self.midHeight,3,3,default.buttonColor)
	self.btnUp = Button:new("^",self.midWidth,1,3,3,default.buttonColor)
	self.btnDown = Button:new("v",self.midWidth,self.height-2,3,3,default.buttonColor)
	
	self.btnLevelDown= Button:new("-",1,1,3,3,default.buttonColor)
	self.lblLevel = Label:new("Level", 4,1)
	self.lblY = Label:new(self.mapMidY, 5,2)
	self.btnLevelUp = Button:new("+",9,1,3,3,default.buttonColor)
	self.lblX = Label:new("X  " .. self.mapMidX, 1,4)
	self.lblZ = Label:new("Z  " .. self.mapMidZ, 1,5)
	
	self.btnZoomOut = Button:new("-",self.width-2,self.height-2,3,3,default.buttonColor)
	self.btnZoomIn = Button:new("+",self.width-2,self.height-6,3,3,default.buttonColor)
	self.lblZoom = Label:new(self.zoomLevel..":"..self.zoomBase, self.width-2, self.height-3)
	self.btnTurtles = CheckBox:new(1,self.height-2,"turtles",self.displayTurtles,nil,nil,self.backgroundColor)
	self.btnHome = CheckBox:new(1,self.height-1,"home",self.displayHome,nil,nil,self.backgroundColor)
	self.btnCircle = CheckBox:new(1,self.height, "128/256 circles",self.displayChunkCircle,nil,nil,self.backgroundColor)
	self.btnFocusPocket = CheckBox:new(1,self.height-3, "live pos",self.focusPocket,nil,nil,self.backgroundColor)

	-- self == MapDisplay not button!
	self.btnLeft.click = function()
		self:scrollLeft()
	end
	self.btnRight.click = function()
		self:scrollRight()
	end
	self.btnUp.click = function()
		self:scrollUp()
	end
	self.btnDown.click = function()
		self:scrollDown()
	end
	self.btnLevelUp.click = function()
		self:levelUp()
	end
	self.btnLevelDown.click = function()
		self:levelDown()
	end
	self.btnZoomOut.click = function()
		self:zoomOut()
	end
	self.btnZoomIn.click = function()
		self:zoomIn()
	end
	self.btnTurtles.click = function()
		self.displayTurtles = self.btnTurtles.active
		self:redraw()
	end
	self.btnHome.click = function()
		self.displayHome = self.btnHome.active
		self:redraw()
	end
	self.btnCircle.click = function()
		self.displayChunkCircle = self.btnCircle.active
		self.fullRedraw = true
		self:redraw()
	end
	self.btnFocusPocket.click = function()
		self.focusPocket = self.btnFocusPocket.active
		self:redraw()
	end

	
	self:addObject(self.btnLeft)
	self:addObject(self.btnRight)	
	self:addObject(self.btnUp)
	self:addObject(self.btnDown)
	self:addObject(self.btnLevelUp)
	self:addObject(self.btnLevelDown)
	self:addObject(self.lblLevel)
	self:addObject(self.lblX)
	self:addObject(self.lblY)
	self:addObject(self.lblZ)
	self:addObject(self.btnZoomOut)
	self:addObject(self.btnZoomIn)
	self:addObject(self.lblZoom)
	self:addObject(self.btnTurtles)
	self:addObject(self.btnHome)
	self:addObject(self.btnCircle)
	self:addObject(self.btnClose)

	if pocket then self:addObject(self.btnFocusPocket) end
	
end

function MapDisplay:handleClick(x,y) -- super override 
	-- doesnt work because the elements speak to the monitor directly
	local o = self:getObjectByPos(x,y)
	x = x - self.x + self.scrollX
	y = y - self.y + self.scrollY
	if o and o.handleClick then
		o:handleClick(x,y)
	elseif not o and self.visible then
		varX = self.mapMidX + (x - self.midWidth - 1) * self.zoomLevel * 2
		varZ = self.mapMidZ + (y - self.midHeight - 1) * self.zoomLevel * 3

		varX = math.floor(varX + 0.5)
		varZ = math.floor(varZ + 0.5)

		if self.doSelectPosition then
			self.doSelectPosition = false
			if self.onPositionSelected then self:onPositionSelected(varX, self.mapMidY, varZ) end
		else
			self:setMid(varX, self.mapMidY, varZ)
			self:redraw()
		end
	end
end


function MapDisplay:scrollZoom(dir,x,z)
	-- real x and y
	local level = self.zoomLevel + dir

	local dx = self.mapMidX - x
	local dz = self.mapMidZ - z

	local old = self.zoomLevel

	local changed = self:calculateZoomLevel(level)
	if changed then

		dx = ( dx / old ) * self.zoomLevel
		dz =  ( dz / old ) * self.zoomLevel

		if self.focusId or (pocket and self.focusPocket) then
			-- dont zoom towards the cursor but the focus point
			self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ)
		else
			self:setMid(x + dx, self.mapMidY, z + dz)
		end
		local zoomText = self.zoomLevel < 1 and "1:"..self.zoomBase or (self.zoomLevel .. ":" .. self.zoomBase)
		self.lblZoom:setText(zoomText)
		self:redraw()
	end

end


function MapDisplay:handleScroll(dir,x,y) -- super override 

	local o = self:getObjectByPos(x,y)
	x = x - self.x + self.scrollX
	y = y - self.y + self.scrollY
	if o and o.handleScroll then
		o:handleScroll(dir,x,y)
	elseif not o and self.visible then

		varX = self.mapMidX + (x - self.midWidth - 1) * self.zoomLevel * 2
		varZ = self.mapMidZ + (y - self.midHeight - 1) * self.zoomLevel * 3

		self:scrollZoom(dir,varX,varZ)
	end
end

function MapDisplay:onResize()
	BasicWindow.onResize(self) -- super
	
	self.drawer:setSize(self.width*2, self.height*3)
	self.btnClose:setPos(self.width - 3 + self.scrollX, self.scrollY) 

	--self:calculateMapMid()
	self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ)
	self.btnLeft:setPos(1,self.midHeight)
	self.btnRight:setPos(self.width-2,self.midHeight)
	self.btnUp:setPos(self.midWidth,1)
	self.btnDown:setPos(self.midWidth,self.height-2)
	
	self.btnZoomOut:setPos(self.width-2, self.height-2)
	self.btnZoomIn:setPos(self.width-2, self.height-6)
	self.lblZoom:setPos(self.width-2, self.height-3)
	
	self.btnTurtles:setPos(1,self.height-2)
	self.btnHome:setPos(1,self.height-1)
	self.btnCircle:setPos(1,self.height)
	self.btnFocusPocket:setPos(1,self.height-3)
	
end
function MapDisplay:onRemove(parent)
	self.focusId = nil
	self:showControls()
end

function MapDisplay:setMid(x,y,z)

	self.mapMidX = math.floor(x+0.5)
	self.mapMidY = y
	self.mapMidZ = math.floor(z+0.5)

	
	self.mapX = self.mapMidX - math.floor(self.midWidth * self.zoomLevel * 2 + 0.5)
	self.mapY = self.mapMidY
	self.mapZ = self.mapMidZ - math.floor(self.midHeight * self.zoomLevel * 3 + 0.5)

	self.lblX:setText("X  " .. self.mapMidX)
	self.lblY:setText(self.mapMidY)
	self.lblZ:setText("Z  " .. self.mapMidZ)
end

function MapDisplay:calculateMapMid()
	self.mapMidX = self.mapX + self.midWidth * self.zoomLevel * 2
	self.mapMidY = self.mapY
	self.mapMidZ = self.mapZ + self.midHeight * self.zoomLevel * 3
end

function MapDisplay:scrollLeft()
	self:setMid(self.mapMidX - self.scrollFactor*self.zoomLevel * 2, self.mapMidY, self.mapMidZ)
	self.lblX:setText("X  " .. self.mapMidX)
	self:redraw()
end
function MapDisplay:scrollRight()
	self:setMid(self.mapMidX + self.scrollFactor*self.zoomLevel * 2, self.mapMidY, self.mapMidZ)
	self.lblX:setText("X  " .. self.mapMidX)
	self:redraw()
end
function MapDisplay:scrollUp()
	self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ - self.scrollFactor*self.zoomLevel * 3)
	self.lblZ:setText("Z  " .. self.mapMidZ)
	self:redraw()
end
function MapDisplay:scrollDown()
	self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ + self.scrollFactor*self.zoomLevel * 3)
	self.lblZ:setText("Z  " .. self.mapMidZ)
	self:redraw()
end
function MapDisplay:levelUp()
	self:setMid(self.mapMidX, self.mapMidY + 1, self.mapMidZ)
	self.lblY:setText(self.mapMidY)
	self:redraw()
end
function MapDisplay:levelDown()
	self:setMid(self.mapMidX, self.mapMidY - 1, self.mapMidZ)
	self.lblY:setText(self.mapMidY)
	self:redraw()
end
function MapDisplay:zoomOut()
	self:setZoomLevel(self.zoomLevel+1)
end
function MapDisplay:zoomIn()
	self:setZoomLevel(self.zoomLevel-1)
end

function MapDisplay:calculateZoomLevel(level)
	if level < 1 then 
		-- zooming in
		self.zoomBase = self.zoomBase + 1
		level = 1 / self.zoomBase
	elseif level % 1 ~= 0 then 
		-- zooming out
		self.zoomBase = self.zoomBase - 1
		if self.zoomBase < 1 then self.zoomBase = 1 end
		level = 1 / self.zoomBase
	else
		if level > 5 then level = 5 end
	end
	
	if not ( self.zoomLevel == level ) then
		self.zoomLevel = level
		print("new zoom", self.zoomLevel, self.zoomBase)
		return true
	end
end
function MapDisplay:setZoomLevel(level)
	local changed = self:calculateZoomLevel(level)
	if changed then
		self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ)
		local zoomText = level < 1 and "1:"..self.zoomBase or (level .. ":" .. self.zoomBase)
		self.lblZoom:setText(zoomText)
		self:redraw()
	end
end

function MapDisplay:setFocus(id)
	self.focusId = id
	if self.focusId then
		local data = global.turtles[self.focusId]
		if data and data.state and data.state.pos then
			self.focusPos = data.state.pos
			self:setMid(data.state.pos.x, data.state.pos.y, data.state.pos.z)
		end
	end
end
function MapDisplay:hideControls()
	if self.objects and not self.hiddenControls then
		self.hiddenControls = self.objects
		self.objects = List:new()
	end
end

function MapDisplay:showControls()
	if self.hiddenControls then
		self.objects = self.hiddenControls
		self.hiddenControls = nil
	end
end


function MapDisplay:refresh()
	local redraw = false

	--TODO: use chunk._lastChange to determine if redraw is needed
		-- DO NOT USE MAPLOG to determine redraw

	if pocket then 
		self.prvFloatPos = global.floatPos
		global.pos, global.floatPos = utils.gpsLocate()
	end
	if self.parent and self.visible then
		if self.focusId then
			local data = global.turtles[self.focusId]
			if data and data.state and data.state.pos then
				local fp, sp = self.focusPos, data.state.pos
				if not fp or fp.x ~= sp.x or fp.y ~= sp.y or fp.z ~= sp.z then 
					self.focusPos = sp
					self:setMid(sp.x, sp.y, sp.z)
					redraw = true
				end
				
			end
		elseif pocket and self.focusPocket and global.pos then 
			local x, y, z = global.pos.x, global.pos.y, global.pos.z
			if self.mapMidX ~= x or self.mapMidY ~= y or self.mapMidZ ~= z then
				self:setMid(x,y,z)
				redraw = true
			end
		end
		redraw = true
	end
	return redraw
end

--function MapDisplay:checkUpdates()
--
--	local redraw = self:refresh()
--	if redraw then self.parent:redraw() end -- assuming the map is an innerWindow
--end

function MapDisplay:precomputeBackground()
    self.background = {}
	local background = self.background

    self.backgroundWidth = 53 -- Fixed width of the background
    self.backgroundHeight = 53 -- Fixed height of the background
	local unknownColor = blitTab[default.unknownColor]

    for row = 1, self.backgroundHeight do
		local bgRow = { {}, {}, {} }
        background[row] = bgRow

        for col = 1, self.backgroundWidth do
            bgRow[1][col] = randomChars[mathRandom(1, randCount)]
            bgRow[2][col] = mathRandom(7, 8)
            bgRow[3][col] = unknownColor
        end
    end
end

function MapDisplay:redraw() -- super override
	if self.parent and self.visible then

		local drawer = self.drawer
		local frame = drawer.frame

		local freeCol = blitTab[default.freeColor]
		local blockedCol = blitTab[default.blockedColor]
		local unknownCol = blitTab[default.unknownColor]
		local disallowedCol = blitTab[default.disallowedColor]

		local map = self.map
		local ct = 0

		local start = os.epoch("utc")
		
		local x, y, z, width, height = self.mapX, self.mapY, self.mapZ, drawer.width, drawer.height
		local zoomLevel, background, bgWidth, bgHeight = self.zoomLevel, self.background, self.backgroundWidth, self.backgroundHeight
		


		local drawEndX = math.floor(x + (width-1) * zoomLevel)
		local drawEndZ = math.floor(z + (height-1) * zoomLevel)
		local chunkSize = map.chunkSize
		local csminus1 = chunkSize - 1

		local xyzToChunkId = map.xyzToChunkId
		local xyzToRelativeChunkId = map.xyzToRelativeChunkId

		local fullRedraw = self.fullRedraw -- can be set by any other funciton
		local prv = self.previous
		if not fullRedraw and prv then 
			if x ~= prv.mapX or y ~= prv.mapY or z ~= prv.mapZ or zoomLevel ~= prv.zoomLevel then
				-- theoretically we could shift the old frame but whatever
				fullRedraw = true
			end
		end
		self.fullRedraw = false -- for next cycle
		local lastUpdate = prv and prv.time or 0


		if zoomLevel < 1 then
			-- [[
			local base = self.zoomBase

			-- currently we start drawing with full blocks instead of just portions if the zoom is very high, which can cause some jittering when mouse zooming
			-- mainly because mapX, mapZ are rounded instead of starting at 0.33

			local cy = y
			local row = 1
			repeat
				local cz = z + (row-1)  -- * zoomLevel same logic but increment by base, not zoomlevel
				local rsz = cz % chunkSize

				local chunkHeight = csminus1 - rsz
				local chunkEndZ = cz + chunkHeight
				if chunkEndZ > drawEndZ then chunkHeight = drawEndZ - cz end

				local col = 1
				repeat
					local cx = x + (col-1)
					local rsx = cx % chunkSize

					local chunkWidth = csminus1 - rsx
					local chunkEndX = cx + chunkWidth
					if chunkEndX > drawEndX then chunkWidth = drawEndX - cx end

					-- print("row", row,"cz", cz,"chunkHeight", chunkHeight, "col", col, "cx", cx,  "chunkWidth", chunkWidth, "self", width, height, "end", row*base + chunkHeight*base, col*base + chunkWidth*base)

					local chunkId = xyzToChunkId(cx,cy,cz)
					local chunk = map:accessChunk(chunkId,false,true)

					if fullRedraw or chunk._lastChange >= lastUpdate then
						-- only redraw if needed

						local trow = 0
						for chunkz = 0, chunkHeight, 1 do
							local line = frame[row + trow]
							
							local tcol = 0
							for chunkx = 0, chunkWidth, 1 do
								-- for blocks x - 15, z - 15
								ct = ct + 1
								local relativeId = xyzToRelativeChunkId(cx + chunkx, cy, cz + chunkz)
								local blockid = chunk[relativeId]
								local pixelCol = idToBlit[blockid]

								if not pixelCol then
									if blockid then
										pixelCol = blockedCol
									else
										pixelCol = unknownCol
									end
								end

								local rb = (row+trow)*base
								local rc = (col+tcol)*base
								for i = 0, base-1 do
									-- not optimal to get the line every time but whatever
									local line = frame[rb - i]
									if not line then break end
									for j = 0, base-1 do
										line[rc - j] = pixelCol
									end
								end
								tcol = tcol + 1
							end
							trow = trow + 1
						end

					end

					col = col + chunkWidth + 1
				until col*base > width

				row = row + chunkHeight + 1
			until row*base > height
			--]]

			--[[

			local base = self.zoomBase
			-- not necessary to get data for every pixel but only on value for base x base pixels, then fill the rest with the same value
			local height = math.ceil(height / base)
			local width = math.ceil(width / base)

			for row = 1, height do 
				for col = 1, width do 

					-- getdata is main bottleneck (90%)
					local blockid = map:getBlockId(x + (col-1), y, z + (row-1))
					local pixelCol = idToBlit[blockid]
					if not pixelCol then
						if blockid then
							pixelCol = blockedCol
						else
							pixelCol = unknownCol
						end
					end

					local rb = row*base
					local rc = col*base
					for i = 0, base-1 do
						-- not optimal to get the lines every time but whatever
						local line = frame[rb - i]
						if not line then break end
						for j = 0, base-1 do
							line[rc - j] = pixelCol
						end
					end
				end
			end
			--]]
			
		else



			local cy = y
			local row = 1
			repeat
				local cz = z + (row-1) * zoomLevel
				local rsz = cz % chunkSize

				local chunkHeight = csminus1 - rsz
				local chunkEndZ = cz + chunkHeight
				if chunkEndZ > drawEndZ then chunkHeight = drawEndZ - cz end

				local col = 1
				repeat
					local cx = x + (col-1) * zoomLevel
					local rsx = cx % chunkSize

					local chunkWidth = csminus1 - rsx
					local chunkEndX = cx + chunkWidth
					if chunkEndX > drawEndX then chunkWidth = drawEndX - cx end

					--print("row", row,"cz", cz,"chunkHeight", chunkHeight, "col", col, "cx", cx,  "chunkWidth", chunkWidth, "self", width, height, "end", row + chunkHeight, col + chunkWidth)

					local chunkId = xyzToChunkId(cx,cy,cz)
					local chunk = map:accessChunk(chunkId,false,true)

					if fullRedraw or chunk._lastChange >= lastUpdate then
						-- only redraw if needed

						local trow = 0
						for chunkz = 0, chunkHeight, zoomLevel do
							local line = frame[row + trow]
							trow = trow + 1
							local tcol = 0
							for chunkx = 0, chunkWidth, zoomLevel do
								-- for blocks x - 15, z - 15
								ct = ct + 1
								local relativeId = xyzToRelativeChunkId(cx + chunkx, cy, cz + chunkz)
								local blockid = chunk[relativeId]
								local pixelCol = idToBlit[blockid]

								if not pixelCol then
									if blockid then
										pixelCol = blockedCol
									else
										pixelCol = unknownCol
									end
								end
								line[col + tcol] = pixelCol
								tcol = tcol + 1
							end
						end

					end

					col = col + math.floor(chunkWidth / zoomLevel) + 1
				until col > width

				row = row + math.floor(chunkHeight / zoomLevel) + 1
			until row > height

			--[[ -- blockwise drawing
				for row = rx, height do 
					local line = frame[row]
					for col = 1, width do 

						local blockid = map:getBlockId(x + (col-1) * zoomLevel, y, z + (row-1) * zoomLevel)
						local pixelCol = idToBlit[blockid]
						if not pixelCol then
							if blockid then
								pixelCol = blockedCol
							else
								pixelCol = unknownCol
							end
						end
						line[col] = pixelCol

					end
				end
			--]]
		end

		-- drawTurtles if they are not drawn as overlay
		if not self.displayTurtles then
			for id,data in pairs(global.turtles) do
				local pos = data.state.pos
				if pos and self:isWithin(pos.x,pos.y,pos.z) then
					local x,y = self:transformSubPos(pos)
					drawer.frame[y][x] = blitTab[colors.yellow]
				end
			end
		end

		self:drawAreas()
		self:drawTrajectory()
		self:drawChunkCircle()
		self:setCursorPos(1,1)
		self:blitFrame(drawer:toBlitFrame())

		-- save current parameters for next redraw, to know if the old frame can be reused
		self.previous = { mapX = x, mapY = y, mapZ = z, zoomLevel = zoomLevel, time = os.epoch()}
		

		-- draw called multiple times: hostdisplay, turtledetails (redraw + checkupdates)
		-- print("map", "redraw ct", ct, "time", os.epoch("utc") - start)
		
		self:redrawOverlay()
		-- redraw map elements
		local node = self.objects.last
		while node do
			node:redraw()
			node = node._prev
		end
	end
end

function MapDisplay:drawAreas()
	local areas = self.areas
	self.displayAreas = true -- testing
	if areas and self.displayAreas then
		for _,area in ipairs(areas) do
			local start, finish, color = area.start, area.finish, area.color
			if start and finish then
				local sx, sz = self:transformSubPos(start)
				local ex, ez = self:transformSubPos(finish)
				self.drawer:drawBox(sx, sz, ex-sx+1, ez-sz+1, blitTab[color], 1)
			end
		end
	end
end

function MapDisplay:drawTrajectory()
	local curPos = global.floatPos
	local prvPos = self.prvFloatPos

	if pocket then
		local prvPosTime = self.prvPosTime or 0
		local time = os.epoch()
		self.prvPosTime = time -- not truly the last update but whatever

		if self.focusPocket and curPos and prvPos then

			local vec = curPos - prvPos
			vec.y = 0
			local len = vec:length()

			local lenpers = len
			-- normalize by time, so its not dependant on refresh rate
			if prvPosTime > 0 then
				local timeDiff = time - prvPosTime
				local seconds = timeDiff / 72000 -- at 20tps
				lenpers = len / seconds 
			end

			if lenpers > 0.4 then
				--print("len", len, "len/s", lenpers)
				vec = vec / len * 10 
				local sx, sz = self.midWidth * 2, self.midHeight * 3
				sx, sz = sx + vec.x, sz + vec.z
				local ex, ez = sx + vec.x, sz + vec.z
				sx, sz = math.floor(sx + 0.5), math.floor(sz + 0.5)
				ex, ez = math.floor(ex + 0.5), math.floor(ez + 0.5)
				self.drawer:drawLine(sx, sz, ex, ez, colors.toBlit(colors.yellow))
				self.fullRedraw = true
			end
		end
	end
end

function MapDisplay:drawChunkCircle()
	if self.displayChunkCircle then
		local pos = global.pos
		local centerX, centerZ = self:transformSubPos(pos)
		local radius = 16*8 / self.zoomLevel
		self.drawer:drawCircle(centerX, centerZ, radius, colors.toBlit(colors.orange))
		local radius = 16*16 / self.zoomLevel
		self.drawer:drawCircle(centerX, centerZ, radius, colors.toBlit(colors.red))
	end
end

function MapDisplay:redrawOverlay()
	-- draw turtles and other stuff

	if self.displayHome then
		local pos = global.pos
		if pos and self:isWithin(pos.x,nil,pos.z) then
			local x,y = self:transformPos(pos)
			self:setCursorPos(x,y)
			self:blit("H",blitTab[colors.black],blitTab[default.homeColor])
		end
		
		-- draw turtle stations
		for _,station in ipairs(config.stations.turtles) do
			local pos = station.pos
			if pos and self:isWithin(pos.x,nil,pos.z) then
				local x,y = self:transformPos(pos)
				self:setCursorPos(x,y)
				self:blit("T",blitTab[colors.black],blitTab[default.homeColor])
			end
		end
		for _,station in ipairs(config.stations.refuel) do
			local pos = station.pos
			if pos and self:isWithin(pos.x,nil,pos.z) then
				local x,y = self:transformPos(pos)
				self:setCursorPos(x,y)
				self:blit("F",blitTab[colors.black],blitTab[default.homeColor])
			end
		end
	end
	
	if self.displayTurtles then
		for id,data in pairs(global.turtles) do
			local pos = data.state.pos
			if pos and self:isWithin(pos.x,nil,pos.z) then
				local x,y = self:transformPos(pos)
				local varY = pos.y - self.mapY
				local color
				if varY == 0 then color = default.turtleColor
				elseif varY > 0 then color = default.aboveColor
				else color = default.belowColor end
				
				self:setCursorPos(x,y)
				self:blit(string.sub(id,string.len(id),string.len(id)),blitTab[colors.white],blitTab[color])
				
			end
		end
	end
end

function MapDisplay:transformSubPos(pos)
	-- used for drawing on the subpixel level
	local varX = pos.x - self.mapX --+ 1
	local varZ = pos.z - self.mapZ --+ 1
	local x = math.floor(varX/ self.zoomLevel) + 1
	local y = math.floor(varZ/ self.zoomLevel) + 1
	return x,y
end

function MapDisplay:transformPos(pos)
	-- used for drawing full characters on top of subpixel map
	local varX = pos.x - self.mapX 
	--local varY = pos.y - self.mapY
	local varZ = pos.z - self.mapZ
	local x = math.floor(varX/ ( self.zoomLevel * 2))+1
	local y = math.floor(varZ/ ( self.zoomLevel * 3))+1
	return x,y
end
function MapDisplay:isWithin(x,y,z)
	-- y can be nil if the level is irrelevant
	local mx, mz, zoomLevel = self.mapX, self.mapZ, self.zoomLevel
	if x >= mx and x < mx + self.width*zoomLevel * 2
	and z >= mz and z < mz + self.height*zoomLevel * 3 then
		if y then
			if y == self.mapY then
				return true
			else
				return false
			end
		else
			return true
		end
	end
	return false
end

function MapDisplay:setMap(map)
	self.map = map
end
function MapDisplay:getMap()
	return self.map
end

-- pseudo function to be set by the caller of selectPosition
function MapDisplay:onPositionSelected(x,y,z) end

function MapDisplay:selectPosition()
	-- needs to return a position but is not allowed to block the current process
	self.doSelectPosition = true
end

return MapDisplay