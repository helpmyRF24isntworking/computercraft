local Button = require("classButton")
local Window = require("classWindow")


-- simple multiple choice selector

local default = {
	colors = {
		background = colors.black,
		border = colors.gray
	},
	width = 10,
	height = 4,
}

local ChoiceSelector = Window:new()

function ChoiceSelector:new(x,y,width,height,choices)
	local o = o or Window:new(x,y,width or default.width ,height or default.height ) or {}
	setmetatable(o, self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)

	o.choice = nil
	o.choices = {}
	o.longestChoice = 0
	
	o:initialize(choices)
	return o
end

function ChoiceSelector:initialize(choices)
	if choices and #choices > 0 then
		self:addChoices(choices)
	end
	print(self.borderColor, self.innerWin.borderColor)
end

function ChoiceSelector:addChoice(text)
	table.insert(self.choices, text)
	if #text > self.longestChoice then
		self.longestChoice = #text
	end
	self["btn"..text] = Button:new(text,3,1+ (#self.choices * 2),self.width-6,1)
	self["btn"..text].click = function() self:selectChoice(text) end

	self["btn"..text].onResize = function() 
		self["btn"..text]:setWidth(self.width-6)
	end
	
	self:addObject(self["btn"..text])	
	self:setSize(math.max(self.width, self.longestChoice + 6),4 + (#self.choices * 2))
end

function ChoiceSelector:addChoices(choices)
	for i=1,#choices do
		self:addChoice(choices[i])
	end
end

-- pseudo callback
-- function ChoiceSelector.onChoiceSelected(choice)

function ChoiceSelector:selectChoice(text)
	self.choice = text
	self:close()
	if self.onChoiceSelected then
		self.onChoiceSelected(self.choice)
	end
end

return ChoiceSelector