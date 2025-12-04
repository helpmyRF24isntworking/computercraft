
local global = global
local nodeStorage = global.storage.node

while global.running do
	
	nodeStorage:checkMessages()
	sleep(0)
end

print("eeeh how", global.running)