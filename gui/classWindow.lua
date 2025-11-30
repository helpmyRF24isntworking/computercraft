
require("classList")
local Button = require("classButton")

local default = {
backgroundColor = colors.black,
borderColor = colors.black,
textColor = colors.white,
x = 4,
y = 3,
width = 45,
height = 19,
}

local Window = {}

function Window:new(x,y,width,height)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	
	o.x = x or default.x
	o.y = y or default.y
	o.width = width or default.width
	o.height = height or default.height
	o.backgroundColor = default.backgroundColor
	o.borderColor = default.borderColor
	o.textColor = default.textColor
	
	o:initialize()
	return o
end



function Window:initialize()
	self.objects = List:new()
	self:calculateMid()
	self.btnClose = Button:new("X",self.width-2,1,3,3,colors.red)
	self.btnClose.click = function() return self:close() end
	self:addObject(self.btnClose)
end

function Window:close()
	--self:clearObjects() -- not needed
	self:setVisible(false) -- instead of clearObjects
	if self.parent then 
		self.parent:removeObject(self)
		self.parent:redraw()
	end
	return true
end

function Window:setVisible(isVisible)
	self.visible = isVisible
	local node = self.objects.first
    while node do
		if node.setVisible then
			node:setVisible(isVisible)
		else
			node.visible = isVisible
		end
		node = node._next
	end
end

-- pseudo functions
function Window:onAdd(parent) end
function Window:onRemove(parent) end

function Window:fillParent()
	if self.parent then
		self:setWidth(self.parent:getWidth())
		self:setHeight(self.parent:getHeight())
		self:setPos(1,1)
	end
end
function Window:fillWidth()
	if self.parent then
		self:setWidth(self.parent:getWidth())
		self:setPos(1,self.y)
	end
end
function Window:fillHeight()
	if self.parent then
		self:setHeight(self.parent:getHeight())
		self:setPos(self.x,1)
	end
end

function Window:onResize()
	self:calculateMid()
	-- TODO: shouldnt this be the oldest first?
	self.btnClose:setPos(self.width-2,1) 
	local o = self.objects.first
	while o do
		if o.onResize then o:onResize() end
		o = o._next
	end
end

function Window:calculateMid()
	self.midWidth = math.floor(self.width/2)
	self.midHeight = math.floor(self.height/2)
	self.midX = self.x + self.midWidth
	self.midY = self.y + self.midHeight
end
function Window:setX(x)
	self.x = x
	self:onResize()
end
function Window:setY(y)
	self.y = y
	self:onResize()
end
function Window:setPos(x,y)
	self.x = x
	self.y = y
	self:onResize()
end
function Window:getMidX()
	return self.midX
end
function Window:getMidY()
	return self.midY
end
function Window:setSize(width,height)
	self.width = width
	self.height = height
	self:onResize()
end
function Window:setWidth(width)
	self.width = width
	self:onResize()
end
function Window:setHeight(height)
	self.height = height
	self:onResize()
end
function Window:getWidth()
	return self.width
end
function Window:getHeight()
	return self.height
end

function Window:redraw()
	if self.parent and self.visible then
		
		self:drawFilledBox(1, 1, self.width, self.height, self.backgroundColor)
		if self.borderColor ~= self.backgroundColor then
			self:drawBox(1,1,self.width,self.height,self.borderColor)
		end
		local node = self.objects.last
		while node do
			node:redraw()
			node = node._prev
		end
	end
end

function Window:getObjectByPos(x,y)
	x = x - self.x + 1
	y = y - self.y + 1
    local node = self.objects.first
    while node do
        if node.width and node.height and node.visible then
            if x >= node.x and x <= (node.x + node.width - 1)
                and y >= node.y and y <= (node.y + node.height - 1) then
                return node
            end
        end
        node = node._next
    end
    return nil
end
function Window:handleClick(x,y)
	-- doesnt work because the elements speak to the monitor directly
	local o = self:getObjectByPos(x,y)
	x = x - self.x + 1
	y = y - self.y + 1
	if o and o.handleClick then
		o:handleClick(x,y)
	end
end
function Window:addObject(o)
    self.objects:addFirst(o)
	if o.setVisible then
		o:setVisible(true)
	else
		o.visible = true
	end
	o.parent = self
	if o.onAdd then o:onAdd(self) end
	
    return o
end
function Window:removeObject(o)
    self.objects:remove(o)
	if o.setVisible then
		o:setVisible(false)
	else
		o.visible = false
	end
	o.window = nil
	if o.onRemove then o:onRemove(self) end
    return o
end

function Window:clearObjects()
	local node = self.objects.first
    while node do
		self:removeObject(node)
		node = self.objects.first
    end
end

function Window:getBackgroundColorByPos(x,y)
    local o = self:getObjectByPos(x,y)
	x = x - self.x + 1
	y = y - self.y + 1
	if o and o.visible then
		if o.getBackgroundColorByPos then
			return o:getBackgroundColorByPos(x,y)
		elseif o.getBackgroundColor then
			return o:getBackgroundColor()
		elseif o.backgroundColor then
			return o.backgroundColor
		end
	elseif self.visible then
		return self.backgroundColor
	end
    return nil
end

-- NEEDED? - yes
function Window:setBackgroundColor(color)
    self.prvBackgroundColor = self.backgroundColor
    if color == nil then
        color = default.backgroundColor
    end
    self.backgroundColor = color
	if self.parent then
		self.parent:setBackgroundColor(self.backgroundColor)
	end
end

function Window:restoreBackgroundColor()
    local color = self.prvBackgroundColor
    if color == nil then
        color = default.backgroundColor
    end
    self.backgroundColor = color
	if self.parent then
		self.parent:restoreBackgroundColor()
	end
end

function Window:setTextColor(color)
    self.prvTextColor = self.textColor
    if color == nil then
        color = default.textColor
    end
    self.textColor = color
	if self.parent then
		self.parent:setTextColor(color)
	end
end
function Window:restoreTextColor()
    local color = self.prvTextColor
    if color == nil then
        color = default.textColor
    end
    self.textColor = color
	if self.parent then
		self.parent:restoreBackgroundColor()
	end
end

function Window:restoreColor()
    self:restoreBackgroundColor()
    self:restoreTextColor()
end

function Window:update()
	--if self.parent then 
		self.parent:update()
	--end
end

-- DRAW COMMANDS WITH RELATIVE POSITIONS
-- WOW a default window implementation already exists ... window.create
function Window:setCursorPos(x,y)
	--if self.parent then
		self.parent:setCursorPos(self.x-1+x, self.y-1+y)
	--end
end

function Window:clear()
	--if self.parent then
		self.parent:clear()
	--end
end

function Window:write(text)
	--if self.parent then
		self.parent:write(text)
	--end
end

function Window:blit(text,textColor,backgroundColor)
	--if self.parent then
		self.parent:blit(text,textColor,backgroundColor)
	--end
end

function Window:drawText(x,y,text,textColor,backgroundColor)
	--if self.parent then
		self.parent:drawText(self.x-1+x, self.y-1+y, text, textColor, backgroundColor)
	--end
end

function Window:drawLine(x,y,endX,endY,color)
	--if self.parent then
		self.parent:drawLine(self.x-1+x, self.y-1+y, self.x-1+endX, self.y-1+endY, color)
	--end
end

function Window:drawBox(x,y,width,height,color,borderWidth,backgroundColor)
	--if self.parent then
		self.parent:drawBox(self.x-1+x, self.y-1+y, width, height, color, borderWidth, backgroundColor)
	--end
end

function Window:drawFilledBox(x,y,width,height,color)
	--if self.parent then
		self.parent:drawFilledBox(self.x-1+x, self.y-1+y, width, height, color)
	--end
end

function Window:drawCircle(centerX,centerY,radius,color)
	--if self.parent then
		self.parent:drawCircle(self.x-1+centerX, self.y-1+centerY, radius, color)
	--end
end

return Window