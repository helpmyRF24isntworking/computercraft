
require("classList")

local default = {
backgroundColor = colors.black,
borderColor = colors.black,
textColor = colors.white,
x = 4,
y = 3,
width = 45,
height = 19,
}

local blitTab = {
    [colors.white] = "0",
    [colors.orange] = "1",
    [colors.magenta] = "2",
    [colors.lightBlue] = "3",
    [colors.yellow] = "4",
    [colors.lime] = "5",
    [colors.pink] = "6",
    [colors.gray] = "7",
    [colors.lightGray] = "8",
    [colors.cyan] = "9",
    [colors.purple] = "a",
    [colors.blue] = "b",
    [colors.brown] = "c",
    [colors.green] = "d",
    [colors.red] = "e",
    [colors.black] = "f",
}

local BasicWindow = {}
BasicWindow.blitTab = blitTab

-- redrawing a basic window, when it plays the role of an innerWindow for Window
-- it can draw over the close button and other elements without redrawing the main Window
-- perhaps do a callback to the main window to redraw those elements
-- also onRemove callbacks only work for the main Window, not for the inner Window
-- see mapDisplay

function BasicWindow:new(x,y,width,height,complex)
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


	-- complex BasicWindows have their own frame buffering
	-- they can be scrolled, and moved
	-- not necessary for simple BasicWindows that are just used as containers
	o.complex = complex or true -- false after testing
	if o.complex then
		o.scrollX = 1
		o.scrollY = 1
		o.maxScrollY = 1
		o.frame = {}
	else
		o.frame = nil
	end

	o:initialize()
	return o
end



function BasicWindow:initialize()

	-- self:resizeFrame()

	self.objects = List:new()
	self:calculateMid()
end


function BasicWindow:close()

	--self:clearObjects() -- not needed
	self:setVisible(false) -- instead of clearObjects
	if self.parent then 
		self.parent:removeObject(self)
		print("closing, redrawing", self.parent)
		self.parent:redraw()
	end
	return true
end

function BasicWindow:setVisible(isVisible)
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
function BasicWindow:onAdd(parent) end
function BasicWindow:onRemove(parent) end

function BasicWindow:fillParent()
	if self.parent then
		self:setWidth(self.parent:getWidth())
		self:setHeight(self.parent:getHeight())
		self:setPos(1,1)
	end
end
function BasicWindow:fillWidth()
	if self.parent then
		self:setWidth(self.parent:getWidth())
		self:setPos(1,self.y)
	end
end
function BasicWindow:fillHeight()
	if self.parent then
		self:setHeight(self.parent:getHeight())
		self:setPos(self.x,1)
	end
end

function BasicWindow:onResize()
	self:calculateMid()
	-- TODO: shouldnt this be the oldest first?
	local o = self.objects.first
	while o do
		if o.onResize then o:onResize() end
		o = o._next
	end
end

function BasicWindow:calculateMid()
	-- not yet using scrollX/Y here, unsure if needed
	self.midWidth = math.floor(self.width/2)
	self.midHeight = math.floor(self.height/2)
	self.midX = self.x + self.midWidth
	self.midY = self.y + self.midHeight
end
function BasicWindow:getX()
	return self.x
end
function BasicWindow:getY()
	return self.y
end
function BasicWindow:setX(x)
	self.x = x
	self:onResize()
end
function BasicWindow:setY(y)
	self.y = y
	self:onResize()
end
function BasicWindow:setPos(x,y)
	self.x = x
	self.y = y
	self:onResize()
end
function BasicWindow:getMidX()
	return self.midX
end
function BasicWindow:getMidY()
	return self.midY
end
function BasicWindow:setSize(width,height)
	self.width = width
	self.height = height
	self:onResize()
end
function BasicWindow:getSize()
	return self.width, self.height
end
function BasicWindow:setWidth(width)
	self.width = width
	self:onResize()
end
function BasicWindow:setHeight(height)
	self.height = height
	self:onResize()
end
function BasicWindow:getWidth()
	return self.width
end
function BasicWindow:getHeight()
	return self.height
end


-- pseudo functions hooked by ScrollBar
-- function BasicWindow.onMaxScrollYChanged(maxScrollY) end
-- funciton BasicWindow.onMaxScrollXChanged(maxScrollX) end

function BasicWindow:linkScrollBar(scrollBar)

end


function BasicWindow:setScrollX(scrollX)
	self.scrollX = scrollX
	self:onResize()
end
function BasicWindow:setScrollY(scrollY)
	self.scrollY = scrollY
	self:onResize()
end
function BasicWindow:scroll(deltaY)
	self.scrollY = self.scrollY + deltaY
	if self.scrollY < 1 then self.scrollY = 1 end
	self:onResize()
end
function BasicWindow:getScrollY()
	return self.scrollY
end
function BasicWindow:getScrollX()
	return self.scrollX
end

function BasicWindow:refresh() end -- to be implemented by subclasses

function BasicWindow:refreshRedraw()
	-- refresh updates the content
	if self.parent and self.visible then
		local needsRedraw = true
		if self.refresh then
			-- only if refresh explicitly returns false, redraw is not called
			needsRedraw = self:refresh()
			if needsRedraw == nil then needsRedraw = true end
		end
		-- redraw forcefully redraws the window
		if needsRedraw then self:redraw() end
	end
end

function BasicWindow:redraw()
	if self.parent and self.visible then

		self.maxScrollY = 1

		self:drawFilledBox(self.scrollX, self.scrollY, self.width, self.height, self.backgroundColor)
		if self.borderColor ~= self.backgroundColor then
			self:drawBox(self.scrollX, self.scrollY,self.width,self.height,self.borderColor,1,self.backgroundColor)
		end
		local node = self.objects.last
		while node do
			node:redraw()
			node = node._prev
		end

		if self.onMaxScrollYChanged then
			self.onMaxScrollYChanged(self.maxScrollY)
		end
	end
end


function BasicWindow:addObject(o, last)
    if last then
        self.objects:addLast(o)
    else
        self.objects:addFirst(o)
    end
	if o.setVisible then
		o:setVisible(true)
	else
		o.visible = true
	end
	o.parent = self
	if o.onAdd then o:onAdd(self) end
	
    return o
end
function BasicWindow:removeObject(o)
    self.objects:remove(o)
	if o.setVisible then
		o:setVisible(false)
	else
		o.visible = false
	end
	o.BasicWindow = nil
	if o.onRemove then o:onRemove(self) end
    return o
end

function BasicWindow:clearObjects()
	local node = self.objects.first
    while node do
		self:removeObject(node)
		node = self.objects.first
    end
end


function BasicWindow:getObjectByPos(x,y)
	x = x - self.x + self.scrollX
	y = y - self.y + self.scrollY
    local node = self.objects.first
    while node do
		local nx, ny, nwidth, nheight, nvisible = node.x, node.y, node.width, node.height, node.visible
        if nwidth and nheight and nvisible then
            if x >= nx and x <= (nx + nwidth - 1)
                and y >= ny and y <= (ny + nheight - 1) then
                return node
            end
        end
        node = node._next
    end
    return nil
end
function BasicWindow:handleClick(x,y)
	local o = self:getObjectByPos(x,y)
	x = x - self.x + self.scrollX
	y = y - self.y + self.scrollY
	if o and o.handleClick then
		o:handleClick(x,y)
	end
end
function BasicWindow:handleScroll(dir,x,y)
	local o = self:getObjectByPos(x,y)
	x = x - self.x + self.scrollX
	y = y - self.y + self.scrollY
	if o and o.handleScroll then
		return o:handleScroll(dir,x,y)
	end
end

function BasicWindow:getBackgroundColorByPos(x,y)
    local o = self:getObjectByPos(x,y)
	x = x - self.x + self.scrollX 
	y = y - self.y + self.scrollY
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

function BasicWindow:setBorderColor(borderColor)
	self.borderColor = borderColor
end

-- NEEDED? - yes
function BasicWindow:setBackgroundColor(color)
    self.prvBackgroundColor = self.backgroundColor
    if color == nil then
        color = default.backgroundColor
    end
    self.backgroundColor = color
	if self.parent then
		self.parent:setBackgroundColor(self.backgroundColor)
	end
end

function BasicWindow:restoreBackgroundColor()
    local color = self.prvBackgroundColor
    if color == nil then
        color = default.backgroundColor
    end
    self.backgroundColor = color
	if self.parent then
		self.parent:restoreBackgroundColor()
	end
end

function BasicWindow:setTextColor(color)
    self.prvTextColor = self.textColor
    if color == nil then
        color = default.textColor
    end
    self.textColor = color
	if self.parent then
		self.parent:setTextColor(color)
	end
end
function BasicWindow:restoreTextColor()
    local color = self.prvTextColor
    if color == nil then
        color = default.textColor
    end
    self.textColor = color
	if self.parent then
		self.parent:restoreBackgroundColor()
	end
end

function BasicWindow:restoreColor()
    self:restoreBackgroundColor()
    self:restoreTextColor()
end

function BasicWindow:getTerm()
	return self.parent:getTerm()
end

function BasicWindow:getRealPos(x,y)
	return self.parent:getRealPos(self.x-self.scrollX+x, self.y-self.scrollY+y)
end

function BasicWindow:update()
	--if self.parent then 
		self.parent:update()
	--end
end

-- DRAW COMMANDS WITH RELATIVE POSITIONS
-- WOW a default BasicWindow implementation already exists ... BasicWindow.create
function BasicWindow:setCursorPos(x,y)
	--if self.parent then
		self.parent:setCursorPos(self.x-self.scrollX+x, self.y-self.scrollY+y)
	--end
end

function BasicWindow:clear()
	--if self.parent then
		self.parent:clear()
	--end
end

function BasicWindow:write(text)
	--if self.parent then
		self.parent:write(text)
	--end
end

function BasicWindow:blit(text,textColor,backgroundColor)
	--if self.parent then
		self.parent:blit(text,textColor,backgroundColor)
	--end
end
function BasicWindow:blitTable(text,textColor,backgroundColor)
	--if self.parent then
		self.parent:blitTable(text,textColor,backgroundColor)
	--end
end
function BasicWindow:blitFrame(frame)
	--if self.parent then
		self.parent:blitFrame(frame)
	--end
end

function BasicWindow:drawText(x,y,text,textColor,backgroundColor)
	--if self.parent then
		self.parent:drawText(self.x-self.scrollX+x, self.y-self.scrollY+y, text, textColor, backgroundColor)
	--end
end

function BasicWindow:drawLine(x,y,endX,endY,color)
	--if self.parent then
		self.parent:drawLine(self.x-self.scrollX+x, self.y-self.scrollY+y, self.x-self.scrollX+endX, self.y-self.scrollY+endY, color)
	--end
end

function BasicWindow:drawBox(x,y,width,height,color,borderWidth,backgroundColor)
	--if self.parent then
		self.parent:drawBox(self.x-self.scrollX+x, self.y-self.scrollY+y, width, height, color, borderWidth, backgroundColor)
	--end
end

function BasicWindow:drawFilledBox(x,y,width,height,color)
	--if self.parent then
		self.parent:drawFilledBox(self.x-self.scrollX+x, self.y-self.scrollY+y, width, height, color)
	--end

	-- estimate max usable scroll
	local maxY = y + height - self.height
	if maxY > self.maxScrollY then
		self.maxScrollY = maxY
	end
end

function BasicWindow:drawCircle(centerX,centerY,radius,color)
	--if self.parent then
		self.parent:drawCircle(self.x-self.scrollX+centerX, self.y-self.scrollY+centerY, radius, color)
	--end
end

function BasicWindow:resizeFrame()
	local frame = self.frame
	local width, height = self.width, self.height

	local tColor = blitTab[self.textColor]
	local bgColor = blitTab[self.backgroundColor]

	for r = 1, height do
		local line = frame[r]
		if not line then 
			line = { {}, {}, {} }
			frame[r] = line
			local text = line[1]
			local textColor = line[2]
			local backgroundColor = line[3]
			for c = 1, width do
				text[c] = " "
				textColor[c] = tColor
				backgroundColor[c] = bgColor
			end
		else
			local text = line[1]
			local textColor = line[2]
			local backgroundColor = line[3]
			for c = #line[1]+1, width do
				text[c] = " "
				textColor[c] = tColor
				backgroundColor[c] = bgColor
			end
		end
	end
end


return BasicWindow