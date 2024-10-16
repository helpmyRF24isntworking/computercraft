require("classBluenetNode")
--require("classNetworkNode")

local node = NetworkNode:new("update")
local waitTime = 10

folders = {
"general",
"turtle",
}

files = {
--"classList.lua",
--"classNetworkNode.lua",
}

local restart = false

local function importFile(fileName, fileData)
	file = fs.open(fileName, "r")
	local currentData
	if file then
		currentData = file.readAll()
		file.close()
	end
	if (currentData == fileData) == false then
		print("updating", fileName)
		restart = true
		file = fs.open(fileName, "w")
		file.write(fileData)
		file.close()
	end
end

node.onNoAnswer = function(forMsg)
	print("NO ANSWER",forMsg.data[1])
end

node.onReceive = function(msg,forMsg)
	if msg and msg.data then
		
		if msg.data[1] == "FILE" then
			print("received",msg.data[2].fileName)
			importFile(msg.data[2].fileName, msg.data[2].fileData)			
		elseif msg.data[1] == "FOLDER" then
			for _,file in ipairs(msg.data[2]) do
				if file.fileName == "startup.lua" then
					importFile(file.fileName, file.fileData)
				else
					importFile("runtime/"..file.fileName, file.fileData)
				end
			end
		else
			print(msg.data[1], textutils.serialize(msg.data[2]))
		end
	end
end

if not node.host then
	print("NO UPDATE HOST AVAILABLE")
else
	print("updating...")
	for _,file in ipairs(files) do
		print("requesting", file)
		local data = { "FILE_REQUEST", { fileName = file } }
		node:send(node.host, data, false)
		node:listen(5)
	end
	for _,folder in ipairs(folders) do
		print("requesting folder", folder)
		local data = { "FOLDER_REQUEST", { folderName = folder } }
		node:send(node.host, data, false)
		node:listen(5)
	end
	if restart then
		os.reboot()
	end
end