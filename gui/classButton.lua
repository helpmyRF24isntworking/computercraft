local Box = require("classBox")

local defaultBackgroundColor = colors.gray
local defaultTextColor = colors.white
local defaultDisabledColor = colors.lightGray
local defaultWidth = 10
local defaultHeight = 3
local blinkTime = 0.12

local Button = Box:new()

function Button:new(text,x,y,width,height,color)
    local o = o or Box:new(x,y,width or defaultWidth,height or defaultHeight,color or defaultBackgroundColor)
    setmetatable(o, self)
    self.__index = self
    
    o.parent = parent or nil
    o.textColor = defaultTextColor
    o.text = text or ""

    o.enabled = true
    o.disabledColor = defaultDisabledColor
	o.enabledColor = o.backgroundColor
	
	o:initialize()
    return o
end

function Button:initialize()
	self:calculateMid()
end

function Button:calculateMid() -- super override
	self.midWidth = math.floor((self.width-string.len(self.text)) /2)
	self.midHeight = math.floor(self.height/2)
	self.midX = self.x + self.midWidth
    self.midY = self.y + self.midHeight
end

function Button:blink()
	local col = self:getBackgroundColor()
	if self.parent then
		self:setBackgroundColor(self.disabledColor)
		self:redraw()
		self.parent:update() 
		sleep(blinkTime)
		self:setBackgroundColor(col)
		self:redraw()
		self.parent:update()
	end
end
function Button:handleClick()
    if self.enabled == true then
        local noBlink = self:click()
		if not noBlink then
			self:blink()
		end
    end
end

function Button:click()
    --pseudo function
    --print(self:getText(), "clicked", "no function assigned")
end

function Button:setEnabled(enabled)
    self.enabled = enabled
	if enabled then
		self:setBackgroundColor(self.enabledColor)
	else
		self:setBackgroundColor(self.disabledColor)
	end
end

function Button:redraw()
    --super
    Box.redraw(self)
    
    --text
	if self.parent and self.visible then
		self.parent:drawText(self.midX, self.midY, self.text, self.textColor, self.backgroundColor)
	end
end

function Button:setText(text)
    self.text = tostring(text)
	self.midWidth = math.floor((self.width-string.len(self.text)) /2)
    self.midX = self.x + self.midWidth
    --self.midY = self.y + math.floor(self.height/2)
end
function Button:getText()
    return self.text
end
function Button:setTextColor(color)
    self.textColor = color
end

function Button:setDisabledColor(color)
	self.disabledColor = color
end

function Button:setWidth(width)
	self.width = width
	self:calculateMid()
end

function Button:setHeight(height)
	self.height = height
	self:calculateMid()
end

return Button