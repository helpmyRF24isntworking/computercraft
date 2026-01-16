local Button = require("classButton")
local Label = require("classLabel")
local Window = require("classWindow")


-- simple number input dialog using a button grid

local default = {
	colors = {
		background = colors.black,
		border = colors.gray,
	},
	width =21,
	height = 21,
}

local NumberInput = Window:new()

function NumberInput:new(x,y, title, min, max)
	local o = o or Window:new(x,y,default.width , default.height ) or {}
	setmetatable(o, self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)

	o.title = title or "Enter Number"
	o.max = max or nil
	o.min = min or nil
	o.numberString = ""
	o.number = nil

	o:initialize()
	return o
end

function NumberInput:initialize()

	self.lblTitle = Label:new(self.title, 3, 1, colors.white, self.borderColor)
	self:addObject(self.lblTitle)

	local xs, ys = 3, 5
	local xMargin = 4
	local height = 1
	local yMargin = height + 1
	
	for i=0, 8 do
		local btn = Button:new(tostring(i+1), xs + ((i % 3) * xMargin), ys + (math.floor(i / 3) * yMargin), 3, height)
		btn.click = function() self:addNumber(i+1) end
		
		self["btn"..i] = btn
		self:addObject(btn)
	end
	self.btn0 = Button:new("0", xs + xMargin, ys + (3 * yMargin), 3, height)
	self.btn0.click = function() self:addNumber(0) end
	self:addObject(self.btn0)

	self.btnDel = Button:new("DEL", xs + (2 * xMargin), ys + (3 * yMargin), 3, height)
	self.btnDel.click = function() self:delNumber() end

	self.btnComma = Button:new(".", xs, ys + (3 * yMargin), 3, height)
	self.btnComma.click = function() self:addComma() end

	self.btnOk = Button:new("OK", self.width-6, xs, 3, 1)
	self.btnOk.click = function()
		self:returnNumber()
	end

	self.lblNumber = Label:new("_", 3, 3, colors.purple)
	self:addObject(self.lblNumber)
	self:addObject(self.btnDel)
	self:addObject(self.btnComma)
	self:addObject(self.btnOk)

	print(self.borderColor, self.backgroundColor)

	self:setHeight(ys + (4 * yMargin))

end

function NumberInput:center()
	-- center on parent window
	-- could also hook into "onAdd" -> center
	if self.parent then
		local parentWidth, parentHeight = self.parent:getSize()
		local x = math.floor((parentWidth - self.width) / 2)
		local y = math.floor((parentHeight - self.height) / 2) + 1
		self:setPos(x,y)
	end
end

function NumberInput:refreshNumber()
	self.lblNumber:setText(self.numberString)
	self.lblNumber:redraw()
	self.parent:update()
end

function NumberInput:addNumber(n)

	local numberString = self.numberString .. tostring(n)
	local num = tonumber(numberString)
	if self.min and num < self.min then num = self.min end
	if self.max and num > self.max then num = self.max end
	self.number = num
	self.numberString = tostring(num)

	self:refreshNumber()
end

function NumberInput:delNumber()
	if self.number then
		local numberString = self.numberString
		numberString = string.sub(numberString, 1, -2)
		if #numberString == 0 then
			self.number = nil
		else
			self.number = tonumber(numberString)
		end
		self.numberString = numberString
	end

	self:refreshNumber()
end

function NumberInput:addComma()
	if not string.find(self.numberString, "%.") then
		self.numberString = self.numberString .. "."
		self.number = tonumber(self.numberString)
	end
	self:refreshNumber()
end

-- pseudo callback
-- function NumberInput.onNumberEntered(number)

function NumberInput:returnNumber()
	self:close()
	if self.onNumberEntered then
		self.onNumberEntered(self.number) -- or 0
	end
end

return NumberInput