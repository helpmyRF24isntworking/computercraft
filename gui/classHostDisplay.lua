local Monitor = require("classMonitor")
local Button = require("classButton")
local GPU = require("classGPU")
local Box = require("classBox")
local ToggleButton = require("classToggleButton")
local Frame = require("classFrame")
local Label = require("classLabel")
--require("classBluenetNode")
--require("classNetworkNode")
local CheckBox = require("classCheckBox")
local Window = require("classWindow")
local BasicWindow = require("classBasicWindow")
local MapDisplay = require("classMapDisplay")
local TurtleControl = require("classTurtleControl")
local TaskGroupSelector = require("classTaskGroupSelector")
local TaskGroupControl = require("classTaskGroupControl")
local StorageDisplay = require("classStorageDisplay")
local ScrollBar = require("classScrollBar")

local default = {
	colors = {
		background = colors.black,
	},
}
local global = global

local HostDisplay = BasicWindow:new()

function HostDisplay:new(x,y,width,height)
	local o = o or BasicWindow:new(x,y,width,height)
	setmetatable(o,self)
	self.__index = self
	
	o.backgroundColor = default.colors.background
	o.doSlowReboot = false
	o.doSlowStart = true

	o:initialize()
	
	return o
end

function HostDisplay:loadGlobals()
	if global then
		self.node = global.node
		self.map = global.map
		self.turtles = global.turtles
		self.pos = global.pos
		self.taskGroups = global.taskGroups
		self.alerts = global.alerts
		self.storage = global.storage
	else
		print("GLOBALS NOT AVAILABLE")
	end
end

function HostDisplay:initialize()
	self:loadGlobals()
	
	-- init main window
	self.winMain = Window:new(1,1)
	self:addObject(self.winMain)
	self.winMain:fillParent()
	self.winMain:removeCloseButton()
	
	-- add main window objects
	--self.winMain.btnGlobalRebootSlow = Button:new("REBOOT SLW", self:getWidth()-9,10,11,3)
	--self.winMain.btnGlobalShutdown = Button:new("SHUTDOWN", self:getWidth()-9,13,11,3,colors.pink)
	
	--self.winMain.btnGlobalRebootSlow.click = function() return self:globalReboot(true) end
	--self.winMain.btnGlobalShutdown.click = function() return self:globalShutdown() end
	
	self.winMain.lblHeading = Label:new("Turtle Manager",2,1)
	local sx, sy = 10,2
	self.winMain.btnReboot = Button:new("REBOOT", self:getWidth()-8,sy,8,3,colors.blue)
	self.winMain.btnTerminate = Button:new("STOP", self:getWidth()-17,sy,8,3,colors.red)
	
	self.winMain.btnMap = Button:new("MAP", sx-8, sy, 7, 3)
	self.winMain.mp1 = Label:new("\155\156\136", sx, sy, colors.blue, colors.green)
	self.winMain.mp2 = Label:new("\137", sx+3, sy, colors.yellow, colors.blue)
	self.winMain.mp3 = Label:new("\155\156", sx, sy+1, colors.green, colors.blue)
	self.winMain.mp4 = Label:new("\148", sx+2, sy+1, colors.yellow, colors.blue)
	self.winMain.mp5 = Label:new("\159", sx+3, sy+1, colors.green, colors.blue)
	self.winMain.mp6 = Label:new("\154\158\141\151", sx, sy+2, colors.green, colors.blue)
	self.winMain.btnGroups = Button:new("Groups", sx+6, sy, 10, 3)
	self.winMain.btnStorage = Button:new("Storage", sx+17, sy, 10, 3)
	
	local sx, sy = 2, sy+4
	self.winMain.btnTurtles = Button:new("Turtles", sx, sy, 10, 3)
	self.winMain.lblRow1 = Label:new(   "      |        |        |", sx+12, sy)
	self.winMain.lblRow2 = Label:new(   "      |        |        |", sx+12, sy+1)
	self.winMain.lblTotalHd = Label:new(" total", sx+11, sy)
	self.winMain.lblTotal =   Label:new("     0", sx+11, sy+1)
	self.winMain.lblOnlineHd = Label:new(		 "online", sx+20, sy)
	self.winMain.lblOnline =   Label:new(         "     0", sx+20, sy+1)
	self.winMain.lblActiveHd = Label:new(				  "active", sx+29, sy)
	self.winMain.lblActive =   Label:new(				  "    0", sx+29, sy+1)
	self.winMain.lblAlertsHd = Label:new(				  " alerts", sx+38, sy)
	self.winMain.lblAlerts =   Label:new(				  "      0", sx+38, sy+1)

	self.winMain.btnGlobalReboot = Button:new("reboot", sx+11, sy+2, 7, 1)
	self.winMain.btnHome = Button:new("home", sx+20, sy+2, 7, 1)
	self.winMain.btnCancel = Button:new("cancel", sx+29, sy+2, 7, 1)
	self.winMain.lblTimeVal = Label:new("00:00:00", self:getWidth()-8, sy+2)


	local sx, sy = 2, sy + 12
	self.winMain.btnDumpItems = Button:new("dump", sx, sy+0, 7, 1)
	self.winMain.btnRefuel = Button:new("refuel", sx, sy+1, 7, 1)

	self.winMain.btnMap.click = function() return self:displayMap() end
	self.winMain.btnTurtles.click = function() return self:displayTurtles() end
	self.winMain.btnGroups.click = function() return self:displayGroups() end
	self.winMain.btnReboot.click = function() self:reboot() end
	self.winMain.btnTerminate.click = function() return self:terminate() end
	self.winMain.btnGlobalReboot.click = function() return self:globalReboot(self.doSlowReboot) end
	self.winMain.btnCancel.click = function() return self:globalCancelTask() end
	self.winMain.btnHome.click = function() return self:globalCallHome() end
	self.winMain.btnDumpItems.click = function() return self:globalDumpItems() end
	self.winMain.btnRefuel.click = function() return self:globalGetFuel() end
	self.winMain.btnStorage.click = function() return self:displayStorage() end



	--self.winMain:addObject(self.winMain.lblHeading)
	self.winMain:addObject(self.winMain.btnReboot)
	self.winMain:addObject(self.winMain.btnTerminate)
	self.winMain:addObject(self.winMain.btnMap)
	self.winMain:addObject(self.winMain.mp1)
	self.winMain:addObject(self.winMain.mp2)
	self.winMain:addObject(self.winMain.mp3)
	self.winMain:addObject(self.winMain.mp4)
	self.winMain:addObject(self.winMain.mp5)
	self.winMain:addObject(self.winMain.mp6)
	self.winMain:addObject(self.winMain.btnGroups)
	self.winMain:addObject(self.winMain.btnStorage)
	self.winMain:addObject(self.winMain.btnTurtles)
	self.winMain:addObject(self.winMain.lblRow1)
	self.winMain:addObject(self.winMain.lblRow2)
	self.winMain:addObject(self.winMain.lblTotalHd)
	self.winMain:addObject(self.winMain.lblTotal)
	self.winMain:addObject(self.winMain.lblOnlineHd)
	self.winMain:addObject(self.winMain.lblOnline)
	self.winMain:addObject(self.winMain.lblActiveHd)
	self.winMain:addObject(self.winMain.lblActive)
	self.winMain:addObject(self.winMain.lblAlertsHd)
	self.winMain:addObject(self.winMain.lblAlerts)
	self.winMain:addObject(self.winMain.btnGlobalReboot)
	self.winMain:addObject(self.winMain.btnHome)
	self.winMain:addObject(self.winMain.btnCancel)
	self.winMain:addObject(self.winMain.lblTimeVal)

	self.winMain:addObject(self.winMain.btnDumpItems)
	self.winMain:addObject(self.winMain.btnRefuel)


	--self.winMain:addObject(self.winMain.btnGlobalRebootSlow)
	--self.winMain:addObject(self.winMain.btnGlobalShutdown)
	
	self.winData = BasicWindow:new(2,11,self:getWidth()-2,6)
	self.winMain:addObject(self.winData)

	self.winData.frm = Frame:new("general", 1, 1, 55, 6)
	self.winData:addObject(self.winData.frm)
	self.winData.frm:setWidth(self.winData:getWidth())

	
	self.winData.btnPrintStatus = CheckBox:new(3,2, "print status", global.printStatus)
	self.winData.btnPrintMainTime = CheckBox:new(3,3, "print main", global.printMainTime)
	self.winData.btnPrintEvents = CheckBox:new(3,4, "print events", global.printEvents)
	self.winData.btnPrintDisplayTime = CheckBox:new(3,5, "print display", global.printDisplayTime)
	self.winData.btnPrintSend = CheckBox:new(25,2, "print send", global.printSend)
	self.winData.btnPrintSendTime = CheckBox:new(25,3, "print send time", global.printSendTime)
	self.winData.chkSlowReboot = CheckBox:new(25,4, "slow reboot", self.doSlowReboot)
	self.winData.chkSlowStart = CheckBox:new(25,5, "slow task start", self.doSlowStart)

	self.winData.btnPrintStatus.click = function()
		global.printStatus = self.winData.btnPrintStatus.active
	end
	self.winData.btnPrintEvents.click = function()
		global.printEvents = self.winData.btnPrintEvents.active
	end
	self.winData.btnPrintDisplayTime.click = function()
		global.printDisplayTime = self.winData.btnPrintDisplayTime.active
	end
	self.winData.btnPrintSend.click = function()
		global.printSend = self.winData.btnPrintSend.active
	end
	self.winData.btnPrintMainTime.click = function()
		global.printMainTime = self.winData.btnPrintMainTime.active
	end
	self.winData.btnPrintSendTime.click = function()
		global.printSendTime = self.winData.btnPrintSendTime.active
	end
	self.winData.chkSlowReboot.click = function()
		self.doSlowReboot = self.winData.chkSlowReboot.active
	end
	self.winData.chkSlowStart.click = function()
		self.doSlowStart = self.winData.chkSlowStart.active
	end

	self.winData:addObject(self.winData.btnPrintStatus)
	self.winData:addObject(self.winData.btnPrintEvents)
	self.winData:addObject(self.winData.btnPrintSend)
	self.winData:addObject(self.winData.btnPrintMainTime)
	self.winData:addObject(self.winData.btnPrintDisplayTime)
	self.winData:addObject(self.winData.btnPrintSendTime)
	self.winData:addObject(self.winData.chkSlowReboot)
	self.winData:addObject(self.winData.chkSlowStart)
	-- settings subwindow for main display
	self.winSettings = BasicWindow:new(12,18,30,1)
	self.winMain:addObject(self.winSettings)

	self.winSettings.lblMsgDelay = Label:new("message interval", 1,1)
	self.winSettings.btnDecreaseDelay = Button:new("-",21,1,1,1)
	self.winSettings.lblMsgDelayVal = Label:new(string.format("%.2f",global.minMessageDelay),23,1)
	self.winSettings.btnIncreaseDelay = Button:new("+",28,1,1,1)
	
	self.winSettings.changeMsgDelay = function(increment)
		global.minMessageDelay = global.minMessageDelay + increment
		if global.minMessageDelay < 0 then global.minMessageDelay = 0 end
		self.winSettings.lblMsgDelayVal:setText(string.format("%.2f",global.minMessageDelay))
		self.winSettings.lblMsgDelayVal:redraw()
	end
	self.winSettings.btnIncreaseDelay.click = function() self.winSettings.changeMsgDelay(0.05) end
	self.winSettings.btnDecreaseDelay.click = function() self.winSettings.changeMsgDelay(-0.05) end

	self.winSettings.lblMsgCount = Label:new("messages:",1,2)
	self.winSettings.lblMsgCountVal = Label:new("0",12,2)

	self.winSettings:addObject(self.winSettings.lblMsgDelay)
	self.winSettings:addObject(self.winSettings.btnDecreaseDelay)
	self.winSettings:addObject(self.winSettings.lblMsgDelayVal)
	self.winSettings:addObject(self.winSettings.btnIncreaseDelay)
	self.winSettings:addObject(self.winSettings.lblMsgCount)
	self.winSettings:addObject(self.winSettings.lblMsgCountVal)
	
	-- init hidden windows
	self.storageDisplay = StorageDisplay:new(1,1,self:getWidth(),self:getHeight(),self.storage)
	self.storageDisplay:setHostDisplay(self)

	self.winMap = Window:new()
	self.mapDisplay = MapDisplay:new(4,4,32,16)
	self.winMap:setInnerWindow(self.mapDisplay)
	self.winTurtles = Window:new()
	self.winGroups = Window:new()
	
	-- add map window data
	self.mapDisplay:setMap(self.map)
	self.mapDisplay:setMid(self.pos.x,self.pos.y,self.pos.z)
	
	-- add turtles window objects
	self.winTurtles.lblTurtles = Label:new("Turtles",1,1)

	self.winTurtles.filter = {
		online = true,
		active = false,
		stuck = false,
	}
	
	
	self.winTurtles.chkFilterOnline = CheckBox:new(14,1,"online",self.winTurtles.filter.online)
	self.winTurtles.chkFilterActive = CheckBox:new(27,1,"active",self.winTurtles.filter.active)
	self.winTurtles.chkFilterStuck = CheckBox:new(40,1,"stuck",self.winTurtles.filter.stuck)

	self.winTurtles.chkFilterOnline.click = function()
		self.winTurtles.filter.online = self.winTurtles.chkFilterOnline.active
	end
	self.winTurtles.chkFilterActive.click = function()
		self.winTurtles.filter.active = self.winTurtles.chkFilterActive.active
	end
	self.winTurtles.chkFilterStuck.click = function()
		self.winTurtles.filter.stuck = self.winTurtles.chkFilterStuck.active
	end

	self.winTurtles.turtleControls = {}
	self.winTurtles.turtleCt = 0
	
	self.winTurtles.refresh = function() self:updateTurtles() end
	
	self.winTurtles:addObject(self.winTurtles.lblTurtles)
	self.winTurtles:addObject(self.winTurtles.chkFilterOnline)
	self.winTurtles:addObject(self.winTurtles.chkFilterActive)
	self.winTurtles:addObject(self.winTurtles.chkFilterStuck)
	self.winTurtles:addScrollbar(true)
	
	-- init groups window
	self.winGroups.lblName = Label:new("Task Groups",1,1)
	self.winGroups.btnAdd = Button:new("create",14,1,8,1)
	self.winGroups.taskGroupControls = {}
	self.winGroups.groupCt = 0
	
	self.winGroups.btnAdd.click = function() return self:addGroup() end
	
	self.winGroups:addObject(self.winGroups.lblName)
	self.winGroups:addObject(self.winGroups.btnAdd)
	-- initial redraw
	-- self:redraw()


end 

function HostDisplay:refresh()
	self.mapDisplay:checkUpdates()
	-- self.winMap:redraw()
	self.storageDisplay:checkUpdates()
	self:updateTurtles()
	self:updateGroups()
	self:updateTime()
end
function HostDisplay:redraw()
	-- only redraw the top window and set the rest invisible
	-- get first visible window
	local winTop = self.objects.first
	local o = winTop
	while o do
		if o.visible then
			winTop = o
			break
		end
		o = o._next
	end
	
	-- set other windows invisible
	local o = winTop._next
	while o do
		if o.setVisible then
			o:setVisible(false)
		else
			o.visible = false
		end
		o = o._next
	end
	
	-- make sure the window is set to visible
	if winTop.setVisible then
		winTop:setVisible(true)
	else
		winTop.visible = true
	end
	winTop:redraw()
end
function HostDisplay:updateTime()

	local winMain = self.winMain
	local lbl = winMain.lblTimeVal
	local time = os.epoch("ingame") / 1000
	local timeTable = os.date("*t", time)
	local txt = string.format("%02d:%02d:%02d",timeTable.hour,timeTable.min,timeTable.sec)
	lbl:setText(txt)
	lbl:redraw()

	local activeCount = 0
	local onlineCount = 0
	local totalCount = 0
	for id,turtle in pairs(self.turtles) do
		totalCount = totalCount + 1
		if turtle.state.online then
			onlineCount = onlineCount + 1
			if turtle.state.task then
				activeCount = activeCount + 1
			end
		end
	end

	local activeColor = (activeCount == totalCount and colors.green)
			or (activeCount == 0 and colors.orange)
			or colors.white
	local txt = tostring(activeCount)
	local len = string.len(txt)
	local txt = string.format("%s%s",string.rep(" ", 6-len),txt)
	winMain.lblActiveHd:setTextColor(activeColor)
	winMain.lblActive:setText(txt)
	winMain.lblActive:setTextColor( activeColor )
	
	local onlineColor = (onlineCount == totalCount and colors.green)
			or (onlineCount == 0 and colors.red)
			or colors.orange
	local txt = tostring(onlineCount)
	local len = string.len(txt)
	local txt = string.format("%s%s",string.rep(" ", 6-len),txt)
	winMain.lblOnlineHd:setTextColor(onlineColor)
	winMain.lblOnline:setText(txt)
	winMain.lblOnline:setTextColor( onlineColor )
	
	local txt = tostring(totalCount)
	local len = string.len(txt)
	local txt = string.format("%s%s",string.rep(" ", 6-len),txt)
	winMain.lblTotal:setText(txt)

	local openAlertCount = #self.alerts.open
	local handledAlertCount = #self.alerts.handled
	local alertColor = (openAlertCount == 0 and colors.white)
			or colors.red
	local txt = tostring(openAlertCount .. "(" .. handledAlertCount .. ")")
	local len = string.len(txt)
	local txt = string.format("%s%s",string.rep(" ", 7-len),txt)
	winMain.lblAlertsHd:setTextColor(alertColor)
	winMain.lblAlerts:setText(txt)
	winMain.lblAlerts:setTextColor(alertColor)

	-- not sure if this is clean like this...
	local winSettings = self.winSettings
	winSettings.lblMsgCountVal:setText(global.messageCount or "0")
	winSettings.lblMsgCountVal:redraw()

	winMain.lblActiveHd:redraw()
	winMain.lblActive:redraw()	
	winMain.lblOnlineHd:redraw()
	winMain.lblOnline:redraw()
	winMain.lblTotal:redraw()
	winMain.lblAlertsHd:redraw()
	winMain.lblAlerts:redraw()
end
function HostDisplay:getMapDisplay()
	return self.mapDisplay
end
function HostDisplay:displayMap()

	self:addObject(self.winMap)
	--self:addObject(self.mapDisplay)
	self.winMap:fillParent()
	
	self:redraw()
	return true
end
function HostDisplay:closeMap()
	self.winMap:close()
end
function HostDisplay:displayStorage()
	self:addObject(self.storageDisplay)
	self.storageDisplay:fillParent()
	self.storageDisplay:refresh()
	self:redraw()
	return true
end
function HostDisplay:displayTurtles()
	self:addObject(self.winTurtles)
	self.winTurtles:fillParent()
	for _,turtleControl in pairs(self.winTurtles.turtleControls) do
		turtleControl:fillWidth()
	end
	self:updateTurtles()
	self:redraw()
	return true
end
function HostDisplay:updateTurtles()
	if self.winTurtles.visible then 
		local y = 3
		local prvHeight = 1
		local turtleControls = self.winTurtles.turtleControls
		for id,data in pairs(self.turtles) do
			
			local filter = self.winTurtles.filter
			if filter.online == data.state.online and filter.active == (data.state.task ~= nil)
				and (filter.stuck == data.state.stuck or (not filter.stuck and data.state.stuck == nil)) then

				if not turtleControls[id] then 		
					turtleControls[id] = TurtleControl:new(1,y,data.state,self.node)
					self.winTurtles:addObject(turtleControls[id])
					turtleControls[id]:fillWidth()
					turtleControls[id]:setHostDisplay(self)
					self.winTurtles.turtleCt = self.winTurtles.turtleCt + 1
				else
					if prvHeight > 3 and turtleControls[id]:getHeight() > 3 then
						y = y - 1
					end
					turtleControls[id]:setY(y)
					turtleControls[id]:setData(data.state)
				end
				y = y + turtleControls[id]:getHeight()
				prvHeight = turtleControls[id]:getHeight()
			else
				-- remove turtle
				if turtleControls[id] then
					self.winTurtles:removeObject(turtleControls[id])
					turtleControls[id] = nil
					self.winTurtles.turtleCt = self.winTurtles.turtleCt - 1
				end
			end
		end
		self.winTurtles:redraw()
	end
end
function HostDisplay:deleteTurtle(id)
	if self.turtles[id] then
		-- delete from global
		self.turtles[id] = nil
	end
	for _,turtleControl in pairs(self.winTurtles.turtleControls) do
		self.winTurtles:removeObject(turtleControl)
	end
	self.winTurtles.turtleControls = {}
	self.winTurtles.turtleCt = 0
end

-- task groups
function HostDisplay:displayGroups()
	self:addObject(self.winGroups)
	self.winGroups:fillParent()
	for _,taskControl in pairs(self.winGroups.taskGroupControls) do
		taskControl:fillWidth()
	end
	self:updateGroups()
	self:redraw()
	return true
end
function HostDisplay:addGroup()
	self.winGroups.groupSelector = TaskGroupSelector:new(1,1,self.turtles,
		self.node,self.taskGroups, self.doSlowStart)
	self.winGroups.groupSelector:setHostDisplay(self)
	self.winGroups:addObject(self.winGroups.groupSelector)
	self.winGroups.groupSelector:fillParent()
	self:redraw()
	return true
end

function HostDisplay:updateGroups()
	if self.winGroups.visible then 
		local taskControls = self.winGroups.taskGroupControls
		for id,taskGroup in pairs(self.taskGroups) do
		
			if not taskControls[id] then 		
				taskControls[id] = TaskGroupControl:new(1,3+6*self.winGroups.groupCt,
					taskGroup,self.node,self.taskGroups)
				self.winGroups:addObject(taskControls[id])
				taskControls[id]:fillWidth()
				taskControls[id]:setHostDisplay(self)
				self.winGroups.groupCt = self.winGroups.groupCt + 1
			else
				-- nothing
			end
		end
		self.winGroups:redraw()
	end
end
function HostDisplay:deleteGroup(id)
	if self.taskGroups[id] then
		-- delete from global
		self.taskGroups[id] = nil
		global.saveGroups()
	end
	for _,groupControl in pairs(self.winGroups.taskGroupControls) do
		self.winGroups:removeObject(groupControl)
	end
	self.winGroups.taskGroupControls = {}
	self.winGroups.groupCt = 0
end

function HostDisplay:globalReboot(slow)
	if self.node then
		if slow then 
		for id,turtle in pairs(self.turtles) do
			self.node:send(id, {"REBOOT"},false,false)
			sleep(0.15)
		end
		else
			self.node:broadcast({"REBOOT"},true)
		end
	end
	--self:reboot()
end

function HostDisplay:globalCancelTask()
	-- cancel all running tasks of the turtles
	if self.node then
		for id,turtle in pairs(self.turtles) do
			self.node:send(id, {"STOP"}, false, false)
		end
	end
end
function HostDisplay:globalCallHome()
	-- cancel all running tasks of the turtles
	if self.node then
		for id,turtle in pairs(self.turtles) do
			self.node:send(id, {"DO", "returnHome"}, false, false)
		end
	end
end
function HostDisplay:globalDumpItems(dropAll)
	-- cancel all running tasks of the turtles
	if self.node then
		for id,turtle in pairs(self.turtles) do
			self.node:send(id, {"DO", "dumpBadItems", {dropAll}}, false, false)
		end
	end
end
function HostDisplay:globalGetFuel()
	-- cancel all running tasks of the turtles
	if self.node then
		for id,turtle in pairs(self.turtles) do
			self.node:send(id, {"DO", "getFuel"}, false, false)
			--self.node:send(id, {"DO", "returnHome"}, false, false)
		end
	end
end


function HostDisplay:globalShutdown()
	if self.node then
		self.node:broadcast({"SHUTDOWN"},true)
	end
	--self:reboot()
end

function HostDisplay:beforeTerminate()
	global.map:save()
	global.saveTurtles()
	global.saveStations()
	global.saveGroups()
end

function HostDisplay:reboot()
	self:clear()
    self:setCursorPos(math.floor((self:getWidth()-10)/2),math.floor(self:getHeight()/2))
    self:write("REBOOTING")
	self:update()
	self:beforeTerminate()
	-- self.node:broadcast({"REBOOT"},true)
    os.reboot()
end

function HostDisplay:terminate()
	global.running = false
	self:clear()
	self:setCursorPos(math.floor((self:getWidth()-10)/2),math.floor(self:getHeight()/2))
	self:write("TERMINATED")
	self:update()
	self:beforeTerminate()
	print("TERMINATED")
	return true
end

return HostDisplay