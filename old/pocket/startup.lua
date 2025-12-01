
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



-- TODO:
-- check if other host ist online
-- request host transfer ( or "teamviewer" mode )
-- if no host available, become host ( after asking user )
-- current host: stop receiving messages from turtles
-- transfer all files/states ( config, turtles, stations, taskGroups, alerts etc. )
-- optionally: transfer all chunks from map
-- shut down host
-- reboot pocket as host 

-- basically as if rebooting the host but instead all files were transferred to pocket
-- vice versa when changing back from pocket to host

-- important: when transferring, turtles must be made aware of the new host
-- reboot does the trick in theory but thats not very elegant
-- "hostProtocol(hijack)" -> send: "NEW_HOST", newHostAddress 
-- either hijack the protocol forcefully or the current host gives its ok by sending out the new host id
-- wait for turtles to confirm new host, to ensure all switched over before old host is not longer available
-- maybe have a "grace period" where both hosts are online to ensure smooth transition 
-- -> mmhna only keep old host as dns around to redirect turtles to new host
-- or maybe keep it online to enable switching back remotely from pocket to host
