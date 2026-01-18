local default = {
	textColor = colors.white,
	backgroundColor = colors.black,
}

local Label = {}

function Label:new(text,x,y,textColor, backgroundColor)
	local o = o or {}
	setmetatable(o, self)
	self.__index = self
	
	o.backgroundColor = backgroundColor

	o.text = tostring(text) or ""
	o.x = x or 0
	o.y = y or 0
	o.textColor = textColor or default.textColor
	
	return o
end

function Label:getTextColor()
	return self.textColor
end

function Label:setTextColor(color)
	self.textColor = color
end
function Label:setBackgroundColor(color)
	self.backgroundColor = color
end
function Label:getBackgroundColor()
	return self.backgroundColor
end
function Label:setPos(x,y)
	self.x = x
	self.y = y
end

function Label:setText(text)
	self.text = tostring(text)
end
function Label:getText()
	return self.text
end
function Label:redraw()
	if self.parent and self.visible then
		self.parent:drawText(self.x, self.y, self:getText(), self.textColor, self.backgroundColor)
	end
end

return Label