
local Monitor = require("classMonitor")
local HostDisplay = require("classHostDisplay")

local global = global 

global.monitor = Monitor:new(term.current())
global.display = HostDisplay:new(1,1,global.monitor:getWidth(),global.monitor:getHeight())
local monitor = global.monitor

while global.running do
	local event, p1, p2, p3, msg, p5 = os.pullEventRaw()
	if event == "mouse_up" then -- or event == "mouse_click" or event == "monitor_resize" then
		monitor:addEvent({event,p1,p2,p3,msg,p5})
	elseif event == "input_request" then 
		local token = p1
		local input = read()
		os.queueEvent("input_response", token, input)
	elseif event == "terminate" then 
		error("Terminated",0)
	end
end