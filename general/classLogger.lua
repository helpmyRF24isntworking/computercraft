local default = {
	fileName = "log.txt",
}

local Logger = {}
Logger.__index = Logger

function Logger:new(fileName)
	local o = o or {}
	setmetatable(o,self)
	
	o.fileName = fileName or default.fileName
	o.log = {}
	
	o:initialize()
	return o
end

function Logger:initialize()
	self.f = fs.open(self.fileName, "w")
end

function Logger:save(fileName)
	fileName = fileName or self.fileName
	if not self.f then 
		if fs.exists(fileName) then
			self.f = fs.open(fileName, "a")
		else
			self.f = fs.open(fileName, "w")
		end
	end

	if self.f then 
		self.f.write(textutils.serialize(self.log))
		self.f.close()
		self.f = nil
		return true
	else
		print("ERROR, UNABLE TO OPEN LOG FILE", fileName)
		return false
	end
end

function Logger:add(...)
	local entry = {...}
	local txt = table.concat(entry, "\t")
	table.insert(self.log, txt)
end

function Logger:addFirst(...)
	local entry = {...}
	local txt = table.concat(entry, "\t")
	table.insert(self.log, 1, txt)
end

function Logger:print()
	for _,entry in ipairs(self.log) do
		print(entry)
	end
end

return Logger