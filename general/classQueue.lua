local Queue = {}

function Queue:new(o)
    local o = o or {}
    setmetatable(o, {__index = self})
    self.__index = self

	-- Function Caching
    for k, v in pairs(self) do
       if type(v) == "function" then
           o[k] = v  -- Directly assign method to object
       end
    end

    o.first = 0
    o.last = -1
    return o
end

function Queue:pushLeft(value)
	local first = self.first - 1
	self.first = first
	self[first] = value
end

function Queue:pushRight(value)
	local last = self.last + 1
	self.last = last
	self[last] = value
end

function Queue:popLeft()
	local first = self.first
	if first > self.last then return nil end
	local value = self[first]
	self[first] = nil        -- to allow garbage collection
	self.first = first + 1
	return value
end

function Queue:popRight()
	local last = self.last
	if self.first > last then return nil end
	local value = self[last]
	self[last] = nil         -- to allow garbage collection
	self.last = last - 1
	return value
end

return Queue