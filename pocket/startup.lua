
shell.run("runtime/update.lua")

os.loadAPI("/runtime/global.lua")

shell.run("runtime/initialize.lua")
tabMain = shell.openTab("runtime/main.lua")
tabReceive = shell.openTab("runtime/receive.lua")
tabSend = shell.openTab("runtime/send.lua")


multishell.setTitle(tabMain, "main")
multishell.setTitle(tabReceive, "receive")
multishell.setTitle(tabSend, "send")

-- MultiShell tests: 
-- shell.openTab("/multi/multi_1.lua")
-- shell.openTab("multi/multi_2")

--shell.openTab better than multishell.launch because it does not disable some global functionalities like require()