require("classBluenetNode")

local node = NetworkNode:new("update")
local waitTime = 5

folders = {
"general",
"storage",
}

files = {
--"classList.lua",
--"classNetworkNode.lua",
}  
 
local restart = false 
 

local function getFileAttributes(folder)
	local fileAttributes = {}
	if fs.exists(folder) and fs.isDir(folder) then 
		
		for _, fileName in ipairs(fs.list("/"..folder)) do 
			local modified = fs.attributes(folder .."/"..fileName).modified
			fileAttributes[fileName] = { modified = modified }
		end
	end
	return fileAttributes
end 

local function compareFiles(f1, f2)
	local file = fs.open(f1, "r")
	local data1, data2
	if file then
		data1 = file.readAll()
		file.close()
	end
	local file = fs.open(f2, "r")
	if file then 
		data2 = file.readAll()
		file.close()
	end
	if data1 and data2 then
		return data1 == data2
	end
	return false
end
local function importFile(fileName, fileData)

	print("updating", fileName)
	restart = true
	if fs.exists(fileName) then 
		fs.delete(fileName)
	end
	file = fs.open(fileName, "w")
	file.write(fileData)
	file.close()
	
end

node.onNoAnswer = function(forMsg)
	print("NO ANSWER",forMsg.data[1])
end 

function handleAnswer(msg,forMsg)
	if msg and msg.data then
		
		if msg.data[1] == "FILE" then
			print("received",msg.data[2].name)
			importFile(msg.data[2].name, msg.data[2].data)			
		elseif msg.data[1] == "FOLDERS" then
			
			for folderName, folder in pairs(msg.data[2]) do
				for fileName,file in pairs(folder) do
					print("importing", folderName, fileName)
					if fileName == "startup.lua" then
						importFile(fileName, file.data)
					else
						importFile("runtime/"..fileName, file.data)
					end
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
		local modified = nil
		if fs.exists(file) then 
			modified = fs.attributes(file).modified
		end
		local data = { "FILE_REQUEST", { fileName = file, modified = modified } }
		local answer, forMsg = node:send(node.host, data, true, true, waitTime)
		handleAnswer(answer, forMsg)
	end
	local files = getFileAttributes("/runtime")
	if fs.exists("startup.lua") then 
		files["startup.lua"] = { modified = fs.attributes("startup.lua").modified }
	end
	
	print("requesting folders")
	local data = { "FOLDERS_REQUEST", { folderNames = folders, files = files } }
	local answer, forMsg = node:send(node.host, data, true, true, waitTime)
	handleAnswer(answer, forMsg)

	if restart then
		os.reboot()
	end
end