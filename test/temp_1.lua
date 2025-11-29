
-- require("general/classBluenetNode")

-- local node = NetworkNode:new("test")
print(bluenet, global)
local global = global

while true do
	local event, time = os.pullEvent()
	if event == "test" then
		print(event,time,global.running)
	elseif event == "timer" then 
		--print(event,time)
	end
end




m = global.miner; m.map:findNextBlock(m.pos, m.checkOreBlock, 8)

m = global.miner; s = vector.new(2229, 68, -2651); e = vector.new(2226, 69, -2647); m:excavateArea(s,e)