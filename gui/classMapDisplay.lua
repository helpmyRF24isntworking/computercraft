
local Button = require("classButton")
local CheckBox = require("classCheckBox")
require("classList")
local BasicWindow = require("classBasicWindow")
local Label = require("classLabel")

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


local mathRandom = math.random
local randomChars = {
	"*", "'", ",", " ", " ", " ", " ", " ", " ", " ", " ",
	" ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ",
	" ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " ",  }
local randCount = #randomChars

-- TODO: https://github.com/9551-Dev/pixelbox_lite

local MapDisplay = BasicWindow:new()

function MapDisplay:new(x,y,width,height,map)
	local o = o or BasicWindow:new(x,y,width,height) or {}
	setmetatable(o, self)
	self.__index = self
	
	o.map = map or {}
	
	o.backgroundColor = default.backgroundColor
	
	--(275, 70, -177)
	o.mapX = 0
	o.mapY = 0
	o.mapZ = 0
	o.mapMidX = 0
	o.mapMidY = 0
	o.mapMidZ = 0
	o.zoomLevel = 1
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

	self.scrollFactor = math.floor( (self.height + self.width)/16 )
	if self.scrollFactor <= 0 then self.scrollFactor = 1 end

	self:precomputeBackground()
	
	-- self.btnClose = Button:new("X",self.width-2,1,3,3,colors.red)
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
	self.lblZoom = Label:new(self.zoomLevel..":1", self.width-2, self.height-3)
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
		self:redraw()
	end
	self.btnFocusPocket.click = function()
		self.focusPocket = self.btnFocusPocket.active
		self:redraw()
	end

	
	-- self:addObject(self.btnClose)
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
		varX = self.mapMidX + (x - self.midWidth - 1) * self.zoomLevel
		varZ = self.mapMidZ + (y - self.midHeight - 1) * self.zoomLevel
		if self.doSelectPosition then
			self.doSelectPosition = false
			if self.onPositionSelected then self:onPositionSelected(varX, self.mapMidY, varZ) end
		else
			self:setMid(varX, self.mapMidY, varZ)
			self:redraw()
		end
	end
end
function MapDisplay:onResize()
	BasicWindow.onResize(self) -- super
	
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
end

function MapDisplay:setMid(x,y,z)
	self.mapMidX = x
	self.mapMidY = y
	self.mapMidZ = z
	self.mapX = self.mapMidX - self.midWidth * self.zoomLevel
	self.mapY = self.mapMidY
	self.mapZ = self.mapMidZ - self.midHeight * self.zoomLevel
	
	self.lblX:setText("X  " .. self.mapMidX)
	self.lblY:setText(self.mapMidY)
	self.lblZ:setText("Z  " .. self.mapMidZ)
end

function MapDisplay:calculateMapMid()
	self.mapMidX = self.mapX + self.midWidth * self.zoomLevel
	self.mapMidY = self.mapY
	self.mapMidZ = self.mapZ + self.midHeight * self.zoomLevel
end

function MapDisplay:scrollLeft()
	self:setMid(self.mapMidX - self.scrollFactor*self.zoomLevel, self.mapMidY, self.mapMidZ)
	self.lblX:setText("X  " .. self.mapMidX)
	self:redraw()
end
function MapDisplay:scrollRight()
	self:setMid(self.mapMidX + self.scrollFactor*self.zoomLevel, self.mapMidY, self.mapMidZ)
	self.lblX:setText("X  " .. self.mapMidX)
	self:redraw()
end
function MapDisplay:scrollUp()
	self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ - self.scrollFactor*self.zoomLevel)
	self.lblZ:setText("Z  " .. self.mapMidZ)
	self:redraw()
end
function MapDisplay:scrollDown()
	self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ + self.scrollFactor*self.zoomLevel)
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
function MapDisplay:setZoomLevel(level)
	if level < 1 then level = 1
	elseif level > 10 then level = 10 end
	
	if not ( self.zoomLevel == level ) then
		self.zoomLevel = level

		self:setMid(self.mapMidX, self.mapMidY, self.mapMidZ)
		self.lblZoom:setText(self.zoomLevel .. ":1")
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

function MapDisplay:checkUpdates()
	local x,y,z
	if gps and pocket then 
		x, y, z = gps.locate()
		if x and y and z then
			x, y, z = math.floor(x), math.floor(y), math.floor(z)
			global.pos = vector.new(x,y,z)
		end
	end
	if self.parent and self.visible then
		local redraw = false
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
		elseif pocket and self.focusPocket then 
			if self.mapMidX ~= x or self.mapMidY ~= y or self.mapMidZ ~= z then
				self:setMid(x,y,z)
				redraw = true
			end
		end
		
		redraw = true
		--TODO: use chunk._lastChange to determine if redraw is needed
		-- DO NOT USE MAPLOG to determine redraw
		
		if redraw then self:redraw() end
	end
end

function MapDisplay:precomputeBackground()
    self.background = {
        text = {},
        textColor = {},
        backgroundColor = {}
    }
	local background = self.background

    self.backgroundWidth = 50 -- Fixed width of the background
    self.backgroundHeight = 50 -- Fixed height of the background

    for row = 1, self.backgroundHeight do
        background[row] = {
			text = {},
			textColor = {},
			backgroundColor = {}
		}

        for col = 1, self.backgroundWidth do
            background[row].text[col] = randomChars[mathRandom(1, randCount)]
            background[row].textColor[col] = mathRandom(7, 8)
            background[row].backgroundColor[col] = colors.toBlit(default.unknownColor)
        end
    end
end

function MapDisplay:redraw() -- super override
	if self.parent and self.visible then
		--self:drawFilledBox(1, 1, self.width, self.height, self.backgroundColor)
		--TODO: improve drawing speed (buffer each line and update with blit)
		
	
		local blit = {
			free = colors.toBlit(default.freeColor),
			blocked = colors.toBlit(default.blockedColor),
			unknown = colors.toBlit(default.unknownColor),
			bad = colors.toBlit(default.disallowedColor)
		}
		
		for row=0, self.height-1 do
			self:setCursorPos(1, 1 + row)
			local text, textColor, backgroundColor = {},{},{}
			local bgRow = (self.mapZ + row * self.zoomLevel) % self.backgroundHeight + 1
			local bg = self.background[bgRow]

			for col=1, self.width do
				local data = self.map:getData(self.mapX + (col-1)*self.zoomLevel, self.mapY, self.mapZ + row*self.zoomLevel)
				
				if data then
					if data == 0 then
						text[col] = " "
						textColor[col] = 0
						backgroundColor[col] = blit.free
					else
						text[col] = " "
						textColor[col] = 0
						if data == "computercraft:turtle_advanced" then 
							backgroundColor[col] = blit.bad
						else
							backgroundColor[col] = blit.blocked
						end
					end
				else
					
                    local bgCol = (self.mapX + (col - 1) * self.zoomLevel) % self.backgroundWidth + 1
					text[col] = bg.text[bgCol]
                    textColor[col] = bg.textColor[bgCol]
					backgroundColor[col] = bg.backgroundColor[bgCol]
					--text[col] = randomChars[mathRandom(1,randCount)]
					--textColor[col] = mathRandom(7,8)
					--backgroundColor[col] = blit.unknown
				end
				--textColor[col] = 0
			end
			self:blit(table.concat(text),table.concat(textColor),table.concat(backgroundColor))
		end
		self:redrawOverlay()
		-- redraw map elements
		local node = self.objects.last
		while node do
			node:redraw()
			node = node._prev
		end
	end
end
function MapDisplay:redrawOverlay()
	-- draw turtles and other stuff
	
	if self.displayChunkCircle then
		local pos = global.pos
		-- draw a single circle around the current position
		local centerX, centerZ = self:transformPos(pos)
		local radius = 16*8 / self.zoomLevel
		self:drawCircle(centerX, centerZ, radius, colors.orange)
		local radius = 16*16 / self.zoomLevel
		self:drawCircle(centerX, centerZ, radius, colors.red)
	end
	if self.displayAreas then
		
	end
	if self.displayHome then
		local pos = global.pos
		if pos and self:isWithin(pos.x,nil,pos.z) then
			local x,y = self:transformPos(pos)
			self:setCursorPos(x,y)
			self:blit("H",colors.toBlit(colors.black),colors.toBlit(default.homeColor))
		end
		
		-- draw turtle stations
		for _,station in ipairs(config.stations.turtles) do
			local pos = station.pos
			if pos and self:isWithin(pos.x,nil,pos.z) then
				local x,y = self:transformPos(pos)
				self:setCursorPos(x,y)
				self:blit("T",colors.toBlit(colors.black),colors.toBlit(default.homeColor))
			end
		end
		for _,station in ipairs(config.stations.refuel) do
			local pos = station.pos
			if pos and self:isWithin(pos.x,nil,pos.z) then
				local x,y = self:transformPos(pos)
				self:setCursorPos(x,y)
				self:blit("F",colors.toBlit(colors.black),colors.toBlit(default.homeColor))
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
				self:blit(string.sub(id,string.len(id),string.len(id)),colors.toBlit(colors.white),colors.toBlit(color))
				
			end
		end
	end
end
function MapDisplay:transformPos(pos)
	local varX = pos.x - self.mapX 
	--local varY = pos.y - self.mapY
	local varZ = pos.z - self.mapZ
	local x = math.floor(varX/self.zoomLevel)+1
	local y = math.floor(varZ/self.zoomLevel)+1
	return x,y
end
function MapDisplay:isWithin(x,y,z)
	-- y can be nil if the level is irrelevant
	if x >= self.mapX and x < self.mapX + self.width*self.zoomLevel
	and z >= self.mapZ and z < self.mapZ + self.height*self.zoomLevel then
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