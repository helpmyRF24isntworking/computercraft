
os.loadAPI("/runtime/bluenet.lua")
shell.run("runtime/update.lua")

-- add runtime as default environment
package.path = package.path ..";../runtime/?.lua"
--package.path = package.path .. ";../?.lua" .. ";../runtime/?.lua"
--require("classMonitor")
--require("../runtime/classMonitor")
--require("runtime/classMonitor")

if rednet then	
	shell.run("runtime/killRednet.lua")
	return
end

os.loadAPI("/runtime/global.lua")
os.loadAPI("/runtime/config.lua")

shell.run("runtime/initialize.lua")

shell.openTab("runtime/shellDisplay.lua")
shell.openTab("runtime/display.lua")
shell.openTab("runtime/main.lua")
shell.openTab("runtime/receive.lua")
shell.openTab("runtime/send.lua")
--shell.openTab("runtime/send.lua")
--shell.openTab("runtime/update.lua")

--shell.run("runtime/testMonitor")

