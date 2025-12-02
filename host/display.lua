
local global = global
local display = global.display
local monitor = global.monitor

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
	--local start = os.epoch("local")
	monitor:checkEvents()
	--local t1 = os.epoch("local")-start
	--start = os.epoch("local")
	if frame%5 == 0 then
		display:refresh()
		
	end
	-- display:refresh()
	-- local t2 = os.epoch("local")-start
	-- start = os.epoch("local")

	monitor:update()
	
	-- local t3 = os.epoch("local")-start
	-- print("events", t1, "refresh",t2, "update",t3)
	frame = frame + 1
	sleep(0.05)
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
