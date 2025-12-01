

-- COPY REQUIRED FILES
local folders = {
"general",
"gui",
"host",
}
if pocket then
	table.insert(folders, "pocket")
end

local reboot = false

local function copyFile(fileName, targetFileName)
	local modified = fs.attributes(fileName).modified
	if fs.exists(targetFileName) then
		local modifiedTarget = fs.attributes(targetFileName).modified
		if modified > modifiedTarget then 
			fs.delete(targetFileName)
			fs.copy(fileName, targetFileName)
			reboot = true
		end
	else
		fs.copy(fileName, targetFileName)
		reboot = true
	end
end

local function copyFolder(folderName, targetFolder)
	print("copying", folderName, targetFolder)
	if not fs.isDir(targetFolder) then
		print("no such folder", folderName)
	end
	if fs.isDir(folderName) then
		for _, fileName in ipairs(fs.list('/' .. folderName)) do
			copyFile(folderName.."/"..fileName, targetFolder.."/"..fileName)
		end
	else
		print("no such folder", folderName)
	end
end

local function copyFiles()
	for _,folderName in ipairs(folders) do
		copyFolder(folderName, "runtime")
	end
	copyFile("runtime/startup.lua", "startup.lua")
	if reboot then
		os.reboot()
	end
end
-- END OF COPY

copyFiles()    
 
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
os.loadAPI("/runtime/bluenet.lua")

shell.run("runtime/initialize.lua")

if pocket then
	local tabGui = shell.openTab("runtime/shellDisplay.lua")
	multishell.setTitle(tabGui, "GUI")
end

shell.openTab("runtime/display.lua")

shell.openTab("runtime/main.lua")
shell.openTab("runtime/receive.lua")
shell.openTab("runtime/send.lua")


--shell.run("runtime/testMonitor")

-- can only be done once receiving is running
-- make its own file: 
shell.run("runtime/hostTransfer.lua")

