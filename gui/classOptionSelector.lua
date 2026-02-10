local CheckBox = require("classCheckBox")
local Window = require("classWindow")


-- like for filters

local default = {
	colors = {
		background = colors.black,
		border = colors.gray
	},
	width = 10,
	height = 4,
}

local OptionSelector = Window:new()

function OptionSelector:new(x,y,width,height,options)
	local o = o or Window:new(x,y,width or default.width ,height or default.height ) or {}
	setmetatable(o, self)
	self.__index = self
	
	o:setBackgroundColor(default.colors.background)
	o:setBorderColor(default.colors.border)

	o.choice = nil
	o.options = {}
	o.optCount = 0
	o.longestOption = 0
	o.isList = true
	o.returnAsKeyValue = false

	o:initialize(options)
	return o
end

function OptionSelector:initialize(options)
	local optList = {} -- ensure options is a list of {text, value} pairs
	local i = 0
	for _ in pairs(options) do
		i = i + 1
		if options[i] == nil then
			self.isList = false -- non-sequential
			break
		end
	end
	if self.isList then
		optList = options
	else
		for opt, val in pairs(options) do
			table.insert(optList, {text = opt, value = val})
		end
	end

	if options and #options > 0 then
		self:addOptions(optList)
	end
end

function OptionSelector:addOption(option)
	local text, value = option.text, option.value
	table.insert(self.options, option)
	if #text > self.longestOption then
		self.longestOption = #text
	end

	local chk = CheckBox:new(3,1+ (#self.options * 2),text,value, self.width-6,1)
	self["btn"..text] = chk
	chk.click = function() option.value = chk.active end
	
	self:addObject(chk)	
	self:setSize(math.max(self.width, self.longestOption + 6 + 4),4 + (#self.options * 2))
end

function OptionSelector:addOptions(options)
	for i = 1, #options do
		self:addOption(options[i])
	end

end

-- callback is onClose(options)

function OptionSelector:close() -- super override
	
	Window.close(self)

	local opts = self.options
	if not self.isList or self.returnAsKeyValue then -- convert back to key-value pairs if needed
		opts = {}
		for i = 1, #self.options do
			local opt = self.options[i]
			opts[opt.text] = opt.value
		end
	end

	if self.onClose then 
		self.onClose(opts)
	end
end

return OptionSelector