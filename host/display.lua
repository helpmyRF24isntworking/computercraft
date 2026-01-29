
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

-- print("display", global.sleepCountDisplay, "tmr", global.timerDisplay, "cur", global.curTimerDisplay); print("send", global.sleepCountSend, "tmr", global.timerSend, "cur", global.curTimerSend)
while global.running and global.displaying do

	local start = osEpoch("local")

	monitor:checkEvents()

	if frame%5 == 0 then
		display:refresh()
	end

	monitor:update()

	if global.printDisplayTime then 
		print(osEpoch("local") - start, "frame", frame )
	end
	
	frame = frame + 1
	sleep()
end

print("display stopped, how?", global.running, global.displaying)
--if pocket then
--	-- if on pocket, pull events
--	parallel.waitForAny(
--		update(),
--		catchEvents()
--		
--	)
--else
--	update()
--end
