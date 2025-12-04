-- startup file for standalone storage computer

os.loadAPI("/runtime/global.lua")

-- add runtime as default environment
package.path = package.path ..";../runtime/?.lua"

if rednet then	
	shell.run("runtime/killRednet.lua")
	return
end

os.loadAPI("/runtime/global.lua")
os.loadAPI("/runtime/bluenet.lua")

shell.run("runtime/initialize.lua")


if pocket then
	-- eerm only for viewing storage i guess? 
    -- perhaps deliver items to current position?
end

shell.openTab("runtime/main.lua")
shell.openTab("runtime/receive.lua")
