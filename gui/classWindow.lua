
require("classList")
local BasicWindow = require("classBasicWindow")
local Button = require("classButton")
local ScrollBar = require("classScrollBar")

local default = {
}

local Window = BasicWindow:new()

function Window:new(x,y,width,height,complex)
	local o = o or BasicWindow:new(x,y,width,height,complex)
	setmetatable(o, self)
	self.__index = self

	o:initialize()
	return o
end

-- Ideas:
-- addTitle

function Window:initialize()

	-- sub window for actual contents
	self.innerWin = BasicWindow:new(1, 1, self.width, self.height, self.complex)

	-- redirect redraw calls to this
	-- works in theory but not with the mapdisplay as an innerwindow
	-- because it will be displayed within different windows but a innerWin can
	-- only really belong to one parent window...
	-- -> mapdisplay must become its own main window, that is just shuffled around
	-- for other basicwindows that are actually innerwindows, this logic works
	-- or have a version that is embedded and another map that is a main window?
	-- it literally just needs a close button and done, no need to wrap it into another window
	-- since its a special window anyways

	self.redrawInnerFunc = self.innerWin.redraw
	self.innerWin.redraw = function() self:redraw() end

	self:addObjectInternal(self.innerWin)

	
	self.btnClose = Button:new("X",self.width-2,1,3,3,colors.red)
	self.btnClose.click = function() return self:close() end
	self:addObjectInternal(self.btnClose)
end

function Window:setBorderColor(borderColor) -- super override
	self.borderColor = borderColor
	self.innerWin:setBorderColor(self.borderColor)
end

function Window:setBackgroundColor(color) -- super override
    self.prvBackgroundColor = self.backgroundColor
    if color == nil then
        color = default.backgroundColor
    end
    self.backgroundColor = color
	self.innerWin.backgroundColor = self.backgroundColor

	if self.parent then
		self.parent:setBackgroundColor(self.backgroundColor)
	end
end

function Window:removeCloseButton()
	self:removeObjectInternal(self.btnClose)
end

function Window:removeScrollBar()
	if self.scrollBar then
		self:removeObjectInternal(self.scrollBar)
		self.scrollBar = nil
		-- resize inner window back to full size
		self.innerWin:setSize(self.width, self.height)
	end
end

function Window:addScrollbar(vertical)
	local length, x, y 
	if vertical then 
		self.innerWin:setWidth(self.width - 1)
		if self.btnClose.visible then 
			length = self.height - self.btnClose.height
			y = self.btnClose.height + 1
		else
			length = self.height
			y = 1
		end
		x = self.width
	else
		self.innerWin:setHeight(self.height - 1)
		length = self.width
		y = self.height
		x = 1
	end

	self.scrollBar = ScrollBar:new(x, y, vertical, length)
	self.scrollBar:setReferenceWindow(self.innerWin)
	self.scrollBar:setScroll(self.scrollY, self.maxScrollY)
	self:addObjectInternal(self.scrollBar)
end


-- TODO: could also replace this with a callback function in classScrollBar
-- scrollBar.setScrollY = function(value) self.win:setScrollY(value) end 
-- scrollBar.setScrollX = function(value) self.win:setScrollX(value) end

function Window:setScrollX(value)
	-- redirect to inner window
	self.innerWin:setScrollX(value)
end
function Window:setScrollY(value)
	-- redirect to inner window
	self.innerWin:setScrollY(value)
end

--[[ function Window:getObjectByPos(x,y)
	-- super override
	if self.scrollBar then
		-- ignore current scroll offset for scrollbar detection
		local lx = x - self.x + self.scrollX 
		local ly = y - self.y + self.scrollY
		print("click window", x, y, "local", lx, ly, "bar", self.scrollBar.x, self.scrollBar.y, self.scrollBar.length)
		if lx == self.scrollBar.x and ly >= self.scrollBar.y and ly <= self.scrollBar.y + self.scrollBar.length then
			return self.scrollBar
		end
	end

	return BasicWindow.getObjectByPos(self, x, y)
end ]]


-- TODO: change usable space of window when scrollbar is added
-- also so no other objects overlap when using fillWidth/fillHeight/fillParent etc.
-- perhaps even another basicwindow within this window, that is resized whenever scrollbar is added/removed
-- yes, this way we can also easier manage not scrolling the bar itself, hit detection for close and the bar etc.

-- basically works but other windows that inherit from this still draw directly onto this window instead of the inner one
-- innerWin needs to be replaced with the inheriting windows 


function Window:setInnerWindow(win)
	self:removeObjectInternal(self.innerWin)
	self.innerWin = win
	local last = true -- add at end so other elements are on top

	-- redirect redraw calls to this
	self.redrawInnerFunc = win.redraw
	win.redraw = function() self:redraw() end

	BasicWindow.addObject(self, win, last)
	win:setPos(1,1)
	self.innerWin:setVisible(self.visible)
	
	-- todo: if self.scrollBar then self.scrollBar:setReferenceWindow(self.innerWin) end
end

-- mmmh, dont like this solution to not redraw inner window when this is added/removed from parent
function Window:onAdd(parent)
	self.innerWin:setVisible(self.visible)
end
function Window:onRemove(parent)
	self.innerWin:setVisible(self.visible)
	if self.innerWin.onRemove then
		-- inform innerWindow as well?
		self.innerWin:onRemove(self)
	end
end

function Window:addObject(obj) -- super override
	-- add to inner window
	-- BasicWindow.addObject( self, obj )
	self.innerWin:addObject(obj)
end

function Window:removeObject(obj) -- super override
	-- remove from inner window, unless it's the inner window itself
	if obj == self.innerWin then
		BasicWindow.removeObject( self, obj )
		error("removed inner Window, is this intentional?")
	else
		self.innerWin:removeObject(obj)
	end
end

function Window:addObjectInternal(obj)
	-- super
	BasicWindow.addObject(self, obj)
	-- for addint overlay objects like scrollbars, close buttons etc.
end
function Window:removeObjectInternal(obj)
	-- super
	BasicWindow.removeObject(self, obj)
	-- for removing overlay objects like scrollbars, close buttons etc.
end


function Window:redraw()
	-- DELETE THIS

	if self.parent and self.visible then

		-- first redraw innerWindow
		
		-- BasicWindow.redraw(innerWin)
		-- super
		-- BasicWindow.redraw(self) -- but without innerWin...
		-- NONONO wont work for basicwindows that overwrite redraw.


		--local maxScrollY = self.maxScrollY
		self.maxScrollY = 1

		--if self.borderColor == colors.gray then 
			--print("redraw window", self.x, self.y, self.width, self.height, self.borderColor, self.backgroundColor)
		--end

		self:drawFilledBox(self.scrollX, self.scrollY, self.width, self.height, self.backgroundColor)
		if self.borderColor ~= self.backgroundColor then
			self:drawBox(self.scrollX, self.scrollY,self.width,self.height,self.borderColor,1,self.backgroundColor)
		end

		local innerWin = self.innerWin
		self.redrawInnerFunc(innerWin)

		local node = self.objects.last
		while node do
			if node ~= innerWin then
				node:redraw()
			end
			node = node._prev
		end

		if self.onMaxScrollYChanged then
			self.onMaxScrollYChanged(self.maxScrollY)
		end
	end
end
function Window:onResize() -- super override 
	-- resize inner window and overlayed objects

	self:calculateMid()

	local innerWidth, innerHeight
	if self.scrollBar then 
		if self.scrollBar.vertical then
			innerWidth = self.width - 1
			innerHeight = self.height -- self.height - (self.btnClose.visible and self.btnClose.height or 0)
		else
			innerWidth = self.width
			innerHeight = self.height - 1
		end
	else
		innerWidth = self.width
		innerHeight = self.height
	end
	if innerWidth ~= self.innerWin:getWidth() or innerHeight ~= self.innerWin:getHeight() then
		self.innerWin:setSize(innerWidth, innerHeight)
	end
	--self.innerWin:setPos(1,1)

	-- BasicWindow.onResize(self)

	-- setPos calls unnecessary, since the main window wont be scrolled, only the inner one
	self.btnClose:setPos(self.width - 3 + self.scrollX, self.scrollY) 
	if self.scrollBar then
		self.scrollBar:setPos(
			self.scrollBar.vertical and self.width + self.scrollX - 1 or 1,
			self.scrollBar.vertical and 
				(self.btnClose.visible and (self.btnClose.height + self.scrollY) or self.scrollY)
				or self.height
		)
		self.scrollBar:setLength(
			self.scrollBar.vertical and 
				(self.height  - (self.btnClose.visible and self.btnClose.height or 0))
				or self.width
		)
	end
end

return Window