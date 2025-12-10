
local RemoteStorage = require("classRemoteStorage")


local function initPosition()
	local x,y,z = gps.locate()
	if x and y and z then
		x, y, z = math.floor(x), math.floor(y), math.floor(z)
		global.pos = vector.new(x,y,z)
	else
		print("gps not working")
		global.pos = vector.new(0,70,0) -- this is bad for turtles especially
	end
	print("position:",global.pos.x,global.pos.y,global.pos.z)
end

initPosition()

global.storage = RemoteStorage:new()