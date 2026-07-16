
-- installation using github for the host computer

local git = "https://raw.githubusercontent.com/helpmyRF24isntworking/computercraft/main"


local files, folders

local allFolders = {
	["general"] = { 
		name = "general",
		files = {
			"blockColor.lua",
			"blockTranslation.lua",
			"bluenet.lua",
			"classBluenetNode.lua",
			"classBreadthFirstSearch.lua",
			"classChunkyMap.lua",
			"classHeap.lua",
			"classList.lua",
			"classLogger.lua",
			"classNetworkNode.lua",
			"classPathFinder.lua",
			"classQueue.lua",
			"classSimpleVector.lua",
			"classStateMap.lua",
			"config.lua",
			"killRednet.lua",
			"utils.lua",
			"utilsSerialize.lua",
		}
	},
	["gui"] = { 
		name = "gui",
		files = {
			"classBasicWindow.lua",
			"classBox.lua",
			"classButton.lua",
			"classCheckBox.lua",
			"classChoiceSelector.lua",
			"classFrame.lua",
			"classGPU.lua",
			"classHostDisplay.lua",
			"classLabel.lua",
			"classMapDisplay.lua",
			"classMonitor.lua",
			"classNumberInput.lua",
			"classOptionSelector.lua",
			"classPixelDrawer.lua",
			"classScrollBar.lua",
			"classStorageDisplay.lua",
			"classStorageItemControl.lua",
			"classTaskControl.lua",
			"classTaskGroupControl.lua",
			"classTaskGroupDetails.lua",
			"classTaskGroupSelector.lua",
			"classTaskList.lua",
			"classTaskSelector.lua",
			"classToggleButton.lua",
			"classTurtleControl.lua",
			"classTurtleDetails.lua",
			"classTurtleList.lua",
			"classWindow.lua",

		}
	},
	["host"] = { 
		name = "host",
		files = {
			"classComplexTask.lua",
			"classLoadBalancer.lua",
			"classRecurringProject.lua",
			"classTaskAssignment.lua",
			"classTaskGroup.lua",
			"classTaskManager.lua",
			"display.lua",
			"global.lua",
			"initialize.lua",
			"main.lua",
			"receive.lua",
			"send.lua",
			"hostTransfer.lua",
			"startup.lua",
		}
	},
	["storage"] = {
		name = "storage",
		files = {
			"classItemStorage.lua",
			"classRemoteStorage.lua",
			"test.lua",
		}
	},
	["pocket"] = { 
		name = "pocket",
		files = {
			"startup.lua",
			"update.lua",
			"initialize.lua",
			"shellDisplay.lua",
		}
	},
	["turtle"] = { 
		name = "turtle",
		files = {
			"update.lua",
			"classCheckPointer.lua",
			"classMiner.lua",
			"global.lua",
			"initialize.lua",
			"main.lua",
			"receive.lua",
			"send.lua",
			"startup.lua",

		}
	},
}

if turtle then
	-- download turtle files, will be updated by host anyways
	files = {
		-- "turtle/startup.lua",
	}
	folders = {
		["turtle"] = {
		name = "turtle",
		files = {
			"startup.lua",
			"update.lua",
			}
		}
		,
		["general"] = {
		name = "general",
		files = {
			"bluenet.lua",
			"classBluenetNode.lua",
			"classList.lua",
			}
		}
	}
else
	-- host computer
	files = {
		"startup.lua"
	}
	folders = allFolders
end

local function saveFile(filePath, fileData)
	if fs.exists(filePath) then
		fs.delete(filePath)
	end

	local f = fs.open(filePath, "w")
	f.write(fileData)
	f.close()
end


local function downloadFile(filePath)
	local url = git.."/"..filePath
	print("downloading", filePath)

	local file = http.get(url)
	local fileData = file.readAll()
	return fileData
end

-- download folders
for _,folder in pairs(folders) do
	print("downloading folder", folder.name)
	if not fs.exists(folder.name) then
		fs.makeDir(folder.name)
	end
	
	for _,fileName in pairs(folder.files) do
		local filePath = folder.name.."/"..fileName
		local data = downloadFile(filePath)
		if turtle then
			if fileName == "startup.lua" then
				saveFile(fileName, data) -- save to root folder
			else
				saveFile("runtime/"..fileName, data)
			end
		else
			saveFile(filePath, data)
		end
	end
end

-- download single files
for _,fileName in pairs(files) do
	local data = downloadFile(fileName)
	saveFile(fileName, data)
end

turtle.forward(3)

os.reboot()