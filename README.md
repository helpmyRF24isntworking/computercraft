# Actually Useful Turtles

Remotely controlled mining turtles for the CC:Tweaked mod in Minecraft. This project started as a funny idea while playing with friends to compete with those ridiculously op mining mods. At first i wrote some simple code but after 15k lines of code i cant stop. 

While turtles are quite cool, they are more of a novelty than being actually useful for a normal playthrough or at least require a high level of maintainence. To compete with other quarry mods you would also need a LOT of turtles, controlling them individually is a nightmare even with prewritten scripts.

With this I aim to centralize the management via a single host. Just give them fuel and select a task. Tested with up to 250 Turtles.



### Features:


#### Full remote GUI Control from a single Host
> All turtles can be controlled via the monitor next to the host. There you can view the status of each turtle and assign them a task - individually or via groups.  
> View the map with live updates from the turtles.
####  High Performance ingame Messaging via Modems
> Uses a questionable protocol and a more performant implementation of rednet -> bluenet  
> - Bidirectional message streaming ( basically an ingame websocket )  
> - Faster lookups
> - Message acknowledgements ( kind of like MQTT QOS 1 )
> - Host as message broker
> - Versioned file sharing / requesting for updating the turtles
> - More performant event pulling and filtering
> - up to 50.000 messages per second with default settings, the upper limit for cached messaging with peripheral.call sits at 70.000.
> 
> A lot of time has been spent on ensuring consistency while maintaining performance.

#### Chunk based Mapping
> Turtles passively map the entire map during their tasks and pass the updates basically in real time to one another via bluenet. This enables the live-map display and pathfinding.
Each turtle only has the needed chunks cached in memory, while the host manages version control, persistence and distribution. The map is stored in chunks in runtime/map/chunks on the host.

#### Actual Mining Tasks
> The turtles are basically just there to mine... for this they use efficient mining strategies: When assigning turtles with an area to mine, the area is split evenly across each member of the group. Afterwards the turtle pathfinds to the closest starting position and starts stripmining the entire area. It uses the map to skip already explored blocks and find previously discovered but unmined ores. Turtles can resume their tasks while the host is offline and store their updates for distribution until it is back online. They automatically refuel, condense their inventory, dropoff items when full etc.
>
#### Unload Protection
> By creating checkpoints during specific tasks, the turtles can always resume their task after being unloaded, rebooted or after closing the game. GPS needs to be available during startup though, to determine their position.   
> In regular intervals the map changes are saved onto the disk by the host, some updates might be lost when the host is suddenly unloaded.


  <br><br>

![grafik](https://github.com/user-attachments/assets/7731f1ae-0d55-4345-b8da-e62db92dde1f)
  
THIS IS WORK IN PROGRESS.  
Let me know about any issues you have or ideas. :)  


# INSTALLATION

### GPS

Before setting up the actual Computers, GPS should be available. Place it somewhere near the Host-Computer.  
https://tweaked.cc/guide/gps_setup.html  

### HOST COMPUTER

1. Place the Host-Computer with a Wireless Modem and Monitor next to it
   ( I recommend the monitors facing south, so the map is aligned more intuitively )
3. Download and run the installation using those commands:  
   ``pastebin get https://pastebin.com/Svg4QckR install``  
   ``install``
3. Setup the Stations for the Turtles:
   1. Open lua
   2. Delete existing stations, otherwise the turtles will run away:  
      ``global.deleteAllStations()``
   3.  Add new Stations:  
         ``global.addStation(x, y, z, facing, type)``  
         facing = "north", "west", "south", "east"  
         type = "turtle" for home and dropoff, "refuel" for refueling   
   4. optional but recommended: add a refuel queue area   
         ``global.setRefuelQueue(x, y, z, maxDistance)``  
         maxDistance like 8, and position a few blocks above the actual refuel stations
4.  Save Config:  
      ``global.saveConfig()``

<br> 

Other helpful commands:  
   - View the stations: ``global.listStations()``  
   - Delete a station: ``global.deleteStation(x, y, z)``

  <br> 

![grafik](https://github.com/user-attachments/assets/b37d059c-8b09-4d74-8bf2-eb3a31dfa35d)


### TURTLES

1.  Place Turtle anywhere, with a Wireless Modem and some Fuel
2.  Install using pastebin ( see Host, same file )
   Turtle should request a Station from Host and move there

After having placed all turtles and they moved to their station, reboot the host using the reboot button.
This saves the station assignments for each turtle.

Done

![grafik](https://github.com/user-attachments/assets/e493f9d3-a631-4364-aff3-c813791652b8)
![grafik](https://github.com/user-attachments/assets/224e47a3-88e6-428c-8a6d-2c7643ce7ddb)
