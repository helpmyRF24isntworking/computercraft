local BasicWindow = require("classBasicWindow")
local Button = require("classButton")

local default = {
	colors = {
		background = colors.gray,
		text = colors.lightGray
	},
}

local ScrollBar = BasicWindow:new()

function ScrollBar:new(x,y,vertical,length,color)
	
	local width, height = 1, length
	if not vertical then
		width = length
		height = 1
	end
    local o = o or BasicWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    
	o.vertical = vertical
	o.length = length
	o:setTextColor(color or default.colors.text)
	
	o:initialize()
    return o
end


function ScrollBar:initialize()

	self.btnDecrease = Button:new("\30",1, 1, 1, 1, default.colors.background) -- up or left 

	local x, y = 1 , self.height
	if not self.vertical then 
		x = self.width
		y = 1
	end
	self.btnIncrease = Button:new("\31",x, y, 1, 1, default.colors.background) -- down or right

	self.btnDecrease.click = function() return self:decrease() end
	self.btnIncrease.click = function() return self:increase() end

	self:addObject(self.btnDecrease)
	self:addObject(self.btnIncrease)
end

function ScrollBar:setReferenceWindow(win)
	-- not parent window, but reference window, which is scrolled by this scrollbar
	if self.vertical then
		win.onMaxScrollYChanged = function(maxScrollY) 
			self:setMaxScroll(maxScrollY)
		end
	else
		win.onMaxScrollXChanged = function(maxScrollX) 
			self:setMaxScroll(maxScrollX)
		end
	end
	self.referenceWindow = win
end

function ScrollBar:handleScroll(dir,x,y)
	if dir == 1 then 
		self:increase()
	else
		self:decrease()
	end
	return true
end

function ScrollBar:increase()
	self.value = self.value + 1
	if self.referenceWindow.scroll then
		if self.vertical then
			self.referenceWindow:setScrollY(self.value)
		else
			self.referenceWindow:setScrollX(self.value)
		end
	else
		print("PARENT IS NOT SCROLLABLE!")
	end
	self.parent:redraw()
end

function ScrollBar:decrease()
	self.value = self.value - 1
	if self.referenceWindow.scroll then
		if self.vertical then
			self.referenceWindow:setScrollY(self.value)
		else
			self.referenceWindow:setScrollX(self.value)
		end
	else
		print("PARENT IS NOT SCROLLABLE!")
	end
	self.parent:redraw()
end

function ScrollBar:setMaxScroll(max)
	self.maxValue = max
end
function ScrollBar:setScroll(value, max)
	self.value = value
	self:setMaxScroll(max)
end

function ScrollBar:onResize()
	-- TODO: if length changed, shorten or lengthen the bar accordingly ( just redraw? )

	print("RESIZE")
	-- self.btnDecrease:setPos(self.x, self.y)
	local x, y = 1, self.height
	if not self.vertical then 
		x = self.width
		y = 1
	end
	self.btnIncrease:setPos(x, y)
end

function ScrollBar:handleClick(x, y)

	--print("scrollbar clicked", x, y)

	local o = self:getObjectByPos(x,y)
	x = x - self.x + self.scrollX
	y = y - self.y + self.scrollY

	--print("found object:", o, x, y, "scroll", self.scrollX, self.scrollY, "self", self.x, self.y)
	if o and o.handleClick then
		o:handleClick(x,y)
	elseif not o and self.visible then
		-- clicked somewhere on the bar 
		-- scroll to the clicked position
		local pos
		if self.vertical then 
			pos = y - 2
		else pos = x - 2 end
		local innerLength = self.length - 3 -- 1 extra pixel offset
		if innerLength < 1 then innerLength = 1 end
		self.value = math.floor((pos / innerLength) * ( self.maxValue - 1 ) + 1.5)
		self.referenceWindow:setScrollY(self.value)
		-- self:redraw()
	end

end

function ScrollBar:setEnabled(enabled)
    self.enabled = enabled
	if enabled then
		self:setBackgroundColor(self.enabledColor)
	else
		self:setBackgroundColor(self.disabledColor)
	end
end

function ScrollBar:redraw()
    --super
    BasicWindow.redraw(self)

    --draw the scroll bar
	if self.parent and self.visible then
		-- use own length instead of parent height to determine size of bar 

		local innerLength = self.length - 2
		if innerLength < 1 then innerLength = 1 end

		local barLength = math.floor(( innerLength ^ 2  / ( innerLength + self.maxValue - 1 )) + 0.5)

		if barLength < 1 then barLength = 1 end
		if barLength > innerLength then barLength = innerLength end

		local barPos = math.floor((self.value / self.maxValue) * (innerLength - barLength)) + 1 -- + 0.5 in floor, but no
		if barPos < 1 then 
			barLength = barLength - (-1-barPos)
			barPos = 1
		end

		--print("value", self.value, "max", self.maxValue, "barPos", barPos, "barLength", barLength)
		--print("innerLength", innerLength, "self.length", self.length)

		if barPos + barLength - 1 > self.length then 
			barLength = self.length - barPos - 1
		end

		if self.vertical then 			
			self.parent:drawFilledBox(self.x, self.y + barPos, self.width, barLength, self.textColor)
		else
			self.parent:drawFilledBox(self.x + barPos, self.y, barLength, self.height, self.textColor)
		end

	end
end

function ScrollBar:setLength(length)
	self.length = length
	if self.vertical then
		self:setHeight(length)
	else
		self:setWidth(length)
	end
end

return ScrollBar