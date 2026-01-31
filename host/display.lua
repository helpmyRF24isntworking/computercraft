
local global = global
local display = global.display
local monitor = global.monitor
local osEpoch = os.epoch


monitor:addObject(display)
monitor:redraw()

local frame = 0

local function catchEvents()
	local event, p1, p2, p3, msg, p5 = os.pullEvent("mouse_up")
	if event == "mouse_up" or event == "mouse_click" or event == "monitor_resize" then
		monitor:addEvent({event,p1,p2,p3,msg,p5})
	end
end

while global.running and global.displaying do

	local printDisplayTime = global.printDisplayTime
	local start

	if printDisplayTime then 
		start = osEpoch("local")
	end

	monitor:checkEvents()

	if frame%5 == 0 then
		display:refresh()

		if printDisplayTime then 
			print(osEpoch("local") - start, "frame", frame )
		end
	end

	monitor:update() -- update takes essentially no time

	frame = frame + 1
	sleep()
end

print("display stopped, how?", global.running, global.displaying)
