
-- The NOQ - No Quarter Lua next generation game manager
--
-- A Shrubbot replacement and also kind of new game manager and tracking system based on mysql or sqlite3. 
-- Both are supported and in case of sqlite there is no extra sqlite installation needed.
--
-- NQ Lua team 2009-2010 - No warrenty :)
 
-- NQ Lua team is:
-- IlDuca
-- Luborg
-- Hose
-- IRATA [*]

-- Setup:
-- - Make sure all required Lua SQL libs are on server and run properly. 
-- 		For MySQL dbms you need the additional lib in the path.
-- - If you want to use sqlite make sure your server instance has write permissions in fs_homepath. 
--		SQLite will create a file "noquarter.sqlite" at this location.
--
-- - Copy the content of this path to fs_homepath/nq
-- - Set lua_modules "noq.lua noq_i.lua"
--   
-- - Make the config your own. There is no need to change code in the NOQ. If you want to see changes use the forum
-- - Restart the server and check if all lua_modules noq_i.lua, noq_c.lua (optinonal) and noq.lua are registered.
-- - Call /rcon !sqlcreate - Done. Your system is set up - you should remove noq_i.lua from lua_modules now.
--
-- Files:
-- noq_i.lua 				- Install script remove after install
-- noq_c.lua 				- Additional tool to enter sql cmds on the ET console
-- noq_config.cfg 			- Stores all data to run & control the NOQ. Make this file your own!
-- noq_commands.cfg 		- Commands definition file - Make this file your own! 
--
-- noq_mods_names.cfg 		- Methods of death enum file - never touch!
-- noq_mods.cfg 			- Methods of death enum file - never touch!
-- noq_weapons.cfg 			- Weapon enum config file - never touch!
-- noq_weapons_names.cfg	- Weapon enum config file - never touch!
--
-- nqconst.lua 				- No Quarter constants
--

-- Notes: 
-- - Use with NQ 1.2.8 and later only	
-- - Again - you don't need to modyfiy any code in this script. If you disagree contact the dev team.


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- SCRIPT VARS - don't touch !

-------------------------------------------------------------------------------

-- LUA module version
version 		= "1" -- see version table
databasecheck 	= 1

homepath 		= et.trap_Cvar_Get("fs_homepath")
pbpath 			= homepath .. "/pb/"
scriptpath 		= homepath .. "/nq/" -- full qualified path for the NOQ scripts

-------------------------------------------------------------------------------
-- table functions - don't move down!
-------------------------------------------------------------------------------

-- The table load 
function table.load( sfile )
   -- catch marker for stringtable
   if string.sub( sfile,-3,-1 ) == "--|" then
	  tables,err = loadstring( sfile )
   else
	  tables,err = loadfile( sfile )
   end
   if err then return _,err
   end
   tables = tables()
   for idx = 1,#tables do
	  local tolinkv,tolinki = {},{}
	  for i,v in pairs( tables[idx] ) do
		 if type( v ) == "table" and tables[v[1]] then
			table.insert( tolinkv,{ i,tables[v[1]] } )
		 end
		 if type( i ) == "table" and tables[i[1]] then
			table.insert( tolinki,{ i,tables[i[1]] } )
		 end
	  end
	  -- link values, first due to possible changes of indices
	  for _,v in ipairs( tolinkv ) do
		 tables[idx][v[1]] = v[2]
	  end
	  -- link indices
	  for _,v in ipairs( tolinki ) do
		 tables[idx][v[2]],tables[idx][v[1]] =  tables[idx][v[1]],nil
	  end
   end
   return tables[1]
end


-- table helper
function getInfoFromTable( _table )
	-- table.sort(cvartable)
	for k,v in pairs(_table) do et.G_Print(k .. "=" .. v .. "\n") end
	-- setn not set so empty
	-- et.G_Print("size:" .. table.getn(cvartable) .. "\n")
end
-- table functions end


et.G_LogPrint("Loading NOQ config from ".. scriptpath.."\n")
noqvartable		= assert(table.load( scriptpath .. "noq_config.cfg"))
-- TODO: check if we can do this in 2 tables 
meansofdeath 	= assert(table.load( scriptpath .. "noq_mods.cfg")) -- all MODS 
weapons 		= assert(table.load( scriptpath .. "noq_weapons.cfg")) -- all weapons
mod				= assert(table.load( scriptpath .. "noq_mods_names.cfg")) -- mods by name
w				= assert(table.load( scriptpath .. "noq_weapons_names.cfg")) -- waepons by name
-- end TODO
greetings		= assert(table.load( scriptpath .. "noq_greetings.cfg")) -- all greetings, customize as wished

-- Gets varvalue else null
function getConfig ( varname )
	local value = noqvartable[varname]
	
	if value then
	  	return value
	else
		et.G_Print("warning, invalid config value for " .. varname .. "\n")
	  	return "null"
	end
end


-- don't get often used vars from noqvartable ...

-- Database managment system to use
dbms	= getConfig("dbms") -- possible values mySQL, SQLite
dbname  = getConfig("dbname")

-- common
-- enables mail option, make sure all required libs are available
mail 			= getConfig("mail") 
recordbots 		= tonumber(getConfig("recordbots")) -- don't write session for bots
color 			= getConfig("color")
commandprefix 	= getConfig("commandprefix")
debug 			= tonumber(getConfig("debug")) -- debug 0/1
debugquerries   = tonumber(getConfig("debugquerries"))
usecommands 	= tonumber(getConfig("usecommands"))
xprestore 		= tonumber(getConfig("xprestore"))
pussyfact 		= tonumber(getConfig("pussyfactor"))
nextmapVoteTime = tonumber(getConfig("nextmapVoteSec"))
evenerdist 		= tonumber(getConfig("evenerCheckallSec"))
polldist 		= tonumber(getConfig("polldistance")) -- time in seconds between polls, change in noq_config.cfg, -1 to disable
maxSelfKills 	= tonumber(getConfig("maxSelfKills")) -- Selfkill restriction: -1 to disable

if debug == 1 then
	et.G_Print("************************\n")
	getInfoFromTable(noqvartable)
	et.G_Print("************************\n")
end

--[[-----------------------------------------------------------------------------
-- DOCU of Datastructurs in this script
--
-- The table slot[clientNum] is created each time someone connect and will store the current client informations
-- The current fields are:
-- 
-- ["team"] = nil
--
-- ["id"] = nil
-- ["pkey"] = 0
-- ["conname"] = row.conname
-- ["regname"] = row.regname
-- ["netname"] = row.netname
-- ["isBot"] = 0	
-- ["clan"] = 0
-- ["level"] = 0
-- ["flags"] = ''		
-- ["user"] = 0
-- ["password"] = 0
-- ["email"] = 0
-- ["banreason"] = 0 
-- ["bannedby"] = 0 
-- ["banexpire"] = 0 
-- ["mutedreason"] = 0
-- ["mutedby"] = 0
-- ["muteexpire"] = 0
-- ["warnings"] = 0 	
-- ["suspect"] = 0
-- ["regdate"] = 0
-- ["updatedate"] = 0	
-- ["createdate"] = 0	
-- ["session"] -- last used or in use session see table session.id // was client["id"] before!			
-- ["ip"] = 0	
-- ["valid "] -- not used in script only written into db if player enters for real 
-- ["start"] = 0		
-- ["end"] = 0  -- not used in script only written into db
-- ["axtime"] = 0
-- ["altime"] = 0
-- ["sptime"] = 0
-- ["lctime"] = 0
-- ["sstime"] = 0
-- ["xp0"] = 0
-- ["xp1"] = 0
-- ["xp2"] = 0
-- ["xp3"] = 0
-- ["xp4"] = 0
-- ["xp5"] = 0
-- ["xp6"] = 0
-- ["xptot"] = 0
-- ["acc"] = 0
-- ["kills"] = 0
-- ["tkills"] = 0
-- ["death"] = 0
-- ["uci"] = 0
-- Added Fields during ingame session in slot[clientNum]
--
-- slot[clientNum]["victim"] = last victim of clientNum(ID)
-- slot[clientNum]["killwep"] = meansofdeathbumber
-- slot[clientNum]["killer"] = last person who killed clientNum(ID)
-- slot[clientNum]["deadwep"] =  meansfdeathnumber
-- slot[_clientNum]["lastTeamChange"] -- in seconds
-- slot[_clientNum]["selfkills"]
--
--]]

-- This is above meantinoned table
slot = {}

-- Note: Players are ents 0 - (sv_maxclients-1)
maxclients = tonumber(et.trap_Cvar_Get("sv_maxclients"))-1 -- add 1 again if used in view

-- We do this for accessing the table with [][] syntax, dirty but it works
for i=0, maxclients, 1 do				
	slot[i] = {}	
end

-- command table
commands = {}
-- Shrub uses only 31 Levels. at least wiki says TODO: VERIFY
for i=0, 31, 1 do				
	commands[i] = {}
end
 
--[[ 
--For testing, the !owned known from ETadmin
commands[0]['owned'] = "print ^1Ha^3ha^5ha^3, i owned ^7<PLAYER_LAST_VICTIM_CNAME>^3 with my ^7<PLAYER_LAST_VICTIM_WEAPON>^7!!!"
commands[0]['pants'] = "print ^1No^3no^5noooo^7, i was killed by ^3<PLAYER_LAST_KILLER_CNAME>^7 with a ^3<PLAYER_LAST_KILLER_WEAPON>^7!!!"
commands[0]['parsecmds'] = "$LUA$ parseconf()"
commands[0]['pussyfactor'] = "$LUA$ pussyout(<PART2IDS>)"
commands[0]['spectime'] = "$LUA$ time = slot[_clientNum]['sptime']; et.trap_SendServerCommand(et.EXEC_APPEND , 'print \"..time.. \" seconds in spec')"
commands[0]['axtime'] = "$LUA$ time = slot[_clientNum]['axtime']; et.trap_SendServerCommand(et.EXEC_APPEND , 'print \"..time.. \" seconds in axis')"
commands[0]['altime'] = "$LUA$ time = slot[_clientNum]['altime']; et.trap_SendServerCommand(et.EXEC_APPEND , 'print \"..time.. \" seconds in allies')"
commands[0]['noqban'] = "$LUA$ ban(<PART2ID>)" --TODO The BANFUNCTION...
-- ^      ^      ^ 
-- Array  |      |
--      level    |
-- 			   Part after Prefix
-- Its possible to implement 2 commands with same commandname but different functions for different levels
--]]

-- current map
map = ""
mapStartTime = 0;
--Gamestate 1 ,2 , 3 = End of Map 
gstate = nil

-- for the evener, an perhaps if you want a nifty message a total of bla persons where killed in this game.
evener = 0
killcount = 0
lastevener = 0
 
-- Poll restriction
lastpoll = 0

-------------------------------------------------------------------------------

-- Handle different dbms
if getConfig("dbms") == "mySQL" then
	require "luasql.mysql"
	env = assert( luasql.mysql() )
	con = assert( env:connect(getConfig("dbname"), getConfig("dbuser"), getConfig("dbpassword"), getConfig("dbhostname"), getConfig("dbport")) )
elseif getConfig("dbms") == "SQLite" then
	require "luasql.sqlite3" 
	env = assert( luasql.sqlite3() )
	-- this opens OR creates a sqlite db - if this file is loaded db is created -fix this?
	con = assert( env:connect( getConfig("dbname") ) )
else
  -- stop script
  error("DBMS not supported.")
end

-- Declare some vars we will use in the script
-- We could allocate this each time, but since are used lot of times is better to make them global
-- TODO: cur and res are exactly the same things, so we could save memory using only one of them
cur = {}  -- Will handle the SQL commands returning informations ( es: SELECT )
res = {}  -- Will handle SQL commands without outputs ( es: INSERT )
row = {}  -- To manipulate the outputs of SQL command
row1 = {} -- To manipulate the outputs of SQL command in case we need more than one request

-- mail setup
if mail == "1" then
	smtp = require("socket.smtp")
end

team = { "AXIS" , "ALLIES" , "SPECTATOR" }
class = { [0]="SOLDIER" , "MEDIC" , "ENGINEER" , "FIELD OPS" , "COVERT OPS" }

-------------------------------------------------------------------------------
-- ET functions
-------------------------------------------------------------------------------

function et_InitGame( _levelTime, _randomSeed, _restart )
	et.RegisterModname( "NOQ version " .. version .. " " .. et.FindSelf() )
    initNOQ()
	getDBVersion()
	mapStartTime = et.trap_Milliseconds()
	if usecommands ~= 0 then
		parseconf () 
	end
	lastpoll = (et.trap_Milliseconds() / 1000) - 110
	
	-- IlDuca: TEST for mail function
	-- sendMail("<mymail@myprovider.com>", "Test smtp", "Questo è un test, speriamo funzioni!!")
end

function et_ClientConnect( _clientNum, _firstTime, _isBot )
	initClient( _clientNum, _firstTime, _isBot )
	
	local ban = checkBan ( _clientNum )
	if ban ~= nil then
		return ban
	end
	-- valid client
	
	checkMute( _clientNum )
	
	-- personal game start message / server greetings	
	if firstTime == 0 or isBot == 1 or getConfig("persgamestartmessage") == "" then 
		return nil
	end
	userInfo = et.trap_GetUserinfo( _clientNum ) 
	et.trap_SendServerCommand(_clientNum, string.format("%s \"%s %s", getConfig("persgamestartmessagelocation") , getConfig("persgamestartmessage") , et.Info_ValueForKey( userInfo, "name" )))

	return nil
end

-- This function is called:
--	- after the connection is over, so when you first join the game world
--
-- Before r3493 also:
--	- when you change team
--	- when you are spectator and switch from "free look mode" to "follow player mode"
-- IRATA: check et_ClientSpawn()
-- TODO/NOTE: Afaik we only need to check if ClientBegin is called once to keep 1.2.7 compatinility
function et_ClientBegin( _clientNum )

	-- TODO Move this functionality in an own function
	-- Get the player name if its not set
	if slot[_clientNum]["netname"] == false then
		slot[_clientNum]["netname"] = et.gentity_get( _clientNum ,"pers.netname")
	end
	
	-- He first connected - so we set his team.
	slot[_clientNum]["team"] = tonumber(et.gentity_get(_clientNum,"sess.sessionTeam"))
	slot[_clientNum]["lastTeamChange"] = (et.trap_Milliseconds() / 1000) -- Hossa! We needa seconds

	-- greeting functionality after netname is set
	if slot[_clientNum]["ntg"] == true then
		greetClient(_clientNum)
	end
	
	if databasecheck == 1 then
		-- If we have Dbaccess, then we will create new Playerentry if necessary
		if slot[_clientNum]["new"] == true then
			createNewPlayer ( _clientNum )
		end
		
		-- if we have xprestore, we need to restore now!
		if slot[_clientNum]["setxp"] == true then
			-- But only, if xprestore is on!
			if xprestore == 1 then
				updatePlayerXP( _clientNum )
			end
			slot[_clientNum]["setxp"] = nil
		end
	end -- end databasecheck
end

-- Possible values are :
--	- slot[_clientNum].team == nil -> the player connected and disconnected without join the gameworld = not-valid session
--	- slot[_clientNum].gstate = 0 and gstate = 0 -> we have to update playing time and store all the player infos = valid session
--	- slot[_clientNum].gstate = 1 or 2 and gstate = 1 or 2 -> player connected during warmup and disconnected during warmup = store only start and end time + valid session
--	- slot[_clientNum].gstate = 3 and gstate = 3 -> player connected during intermission and disconnected during intermission = store only start and end time + valid session
--	- slot[_clientNum].gstate = 0 and gstate = 3 -> we have to store all the player infos = valid session

function et_ClientDisconnect( _clientNum )
	if databasecheck == 1 then
		local endtime = timehandle ('N')
		-- TODO : check if this works. Is the output from 'D' option in the needed format for the database?
		local timediff = timehandle('D','N', slot[_clientNum]["start"])
		
		WriteClientDisconnect( _clientNum , endtime, timediff )
	end
	slot[_clientNum] = {}
	slot[_clientNum]["ntg"] = false
end

function et_ClientCommand( _clientNum, _command )
	local arg0 = string.lower(et.trap_Argv(0))
	local arg1 = string.lower(et.trap_Argv(1))
	local arg2 = string.lower(et.trap_Argv(2))
	local callershrublvl = et.G_shrubbot_level(_clientNum)

	if debug ~= 0 then
		et.G_Print("Got a Clientcommand: ".. arg0 .. "\n")
	end

	-- switch to disable the !commands 
	if usecommands ~= 0 then
		if arg0 == "say" and string.sub( arg1, 1,1) == commandprefix then -- this means normal say
		if debug ~= 0 then
			et.G_Print("Got saycommand: " .. _command)
		end
			gotCmd( _clientNum, _command , false)
		
		end
		
		if arg0 == "vsay" and string.sub( arg2 , 1, 1) == commandprefix then -- this means a !command with vsay
			gotCmd ( _clientNum, _command, true)
		end
		
		if et.G_shrubbot_permission( _clientNum, "3" ) == 1 then -- and finally, a silent !command
			if string.sub( arg0 , 1, 1) == commandprefix then
			gotCmd ( _clientNum, _command, nil)
			return 0
			end
		end
		 
	end

	-- register command
	if arg0 == "register" then
		local arg1 = string.lower(et.trap_Argv(1)) -- username
		local arg2 = string.lower(et.trap_Argv(2)) -- password
		local name = string.gsub(arg1,"\'", "\\\'")
		if arg1 ~= "" and arg2 ~= "" then
			slot[_clientNum]["user"] = name 
			res = assert (con:execute("UPDATE player SET user='" .. name .."', password='MD5("..arg2..")' WHERE pkey='"..slot[_clientNum]["pkey"].."'"))
			et.trap_SendServerCommand( _clientNum, "print \"^3Successfully registered. To reset password just re-register. \n\"" ) 
			return 1
		else
			et.trap_SendServerCommand( _clientNum, "print \"^3Syntax for the register Command: /register username password  \n\"" ) 
			et.trap_SendServerCommand( _clientNum, "print \"^3Username is your desired username (for web & offlinemessages)  \n\"" )
			et.trap_SendServerCommand( _clientNum, "print \"^3Password will be your password for your webaccess  \n\"" ) 
			return 1
		end

	end
	
	-- Voting restriction
	if arg0 == "callvote" then
	   -- restriction is enabled	
		if polldist ~= -1 then

			milliseconds = et.trap_Milliseconds() 
			seconds = milliseconds / 1000

			-- checks for shrubbot flag "7" -> check shrubbot wiki for explanation 
			if et.G_shrubbot_permission( _clientNum, "7" ) == 1 then
				return 0

			-- checks time betw. last vote and this one
			elseif (seconds - lastpoll) < polldist then
				et.trap_SendConsoleCommand (et.EXEC_APPEND , "chat \"".. et.gentity_get(_clientNum, "pers.netname") .."^7, please wait ^1".. string.format("%.0f", polldist - (seconds - lastpoll) ) .." ^7seconds for your next poll.\"" )
				return 1
			end
			
			-- handles nextmap vote restriction
			if arg1 == "nextmap" then

				--check the time that the map is running already
				mapTime = et.trap_Milliseconds() - mapStartTime
				if debug == 1 then
					et.G_Print("maptime = " .. mapTime .."\n")
					et.G_Print("maptime in seconds = " .. mapTime/1000 .."\n")
					et.G_Print("mapstarttime = " .. mapStartTime .."\n")
					et.G_Print("mapstarttime in seconds = " .. mapStartTime/1000 .."\n")
				end
				--compare to the value that is given in config where nextmap votes are allowed
				if nextmapVoteTime == 0 then
					if debug == 1 then
						et.G_Print("Nextmap vote limiter is disabled!")
					end
					return 0
				elseif mapTime / 1000 > nextmapVoteTime then
					--if not allowed send error msg and return 1	
					et.trap_SendConsoleCommand (et.EXEC_APPEND, "chat \"Nextmap vote is only allowed during the first " .. nextmapVoteTime .." seconds of the map! Current maptime is ".. mapTime/1000 .. " seconds!\"")
					return 1
				end
				
			end
				
			lastpoll = seconds
		end
	end
	
	-- /kill restriction
	if arg0 == "kill" then	
		if maxSelfKills ~= -1 then
				if slot[_clientNum]["selfkills"] > maxSelfKills then
					et.trap_SendServerCommand( _clientNum, "cp \"^1You don't have any more selfkills left!") 
					et.trap_SendServerCommand( _clientNum, "cpm \"^1You don't have any more selfkills left!")
					return 1
				end
			et.trap_SendServerCommand( _clientNum, "cp \"^1You have ^2".. (maxSelfKills - slot[_clientNum]["selfkills"])  .."^1 selfkills left!")
			et.trap_SendServerCommand( _clientNum, "cpm \"^1You have ^2".. (maxSelfKills - slot[_clientNum]["selfkills"])  .."^1 selfkills left!")
			return 0
		end
	end
	
	-- read in the commandsfile 
	if usecommands ~= 0 then
		if et.G_shrubbot_permission( _clientNum, "G" ) == 1 then -- has the right to read the config in.. So he also can read commands
			if arg0 == "readthefile" then 
					parseconf()
				return 1
			end
		end
	end
end

function et_ShutdownGame( _restart )
	if databasecheck == 1 then
		-- We write only the informations from a session that gone till intermission end
		if tonumber(et.trap_Cvar_Get( "gamestate" )) == -1 then
			-- This is when the map ends: we have to close all opened sessions
			-- Cycle between all possible clients
			
			local endgametime = timehandle('N')
			
			for i=0, maxclients, 1 do
				if et.gentity_get(i,"classname") == "player" then
	
     				-- TODO : check if this works. Is the output from 'D' option in the needed format for the database?
					local timediff = timehandle('D',endgametime,slot[i]["start"])

					WriteClientDisconnect( i , endgametime, timediff )

					slot[i] = nil
				end
			end

			con:close()
			env:close()
		end
		
		-- delete old sessions if set in config
		local deleteSessionsOlderXDays = tonumber(getConfig("deleteSessionsOlderXDays"))
		if  deleteSessionsOlderXDays > 0 then
			-- TODO
			-- res = assert (con:execute("DELETE FROM session WHERE `end` < "))
		end
	end
end

function et_RunFrame( _levelTime )
	-- TODO: is this what we want? I suppose yes...	
    -- This check works only once, when the intermission start: here we have to close sptime, axtime and altime
	-- For all players in the LUA table "slot"
	if ( gstate == 0 ) and ( tonumber(et.trap_Cvar_Get( "gamestate" )) == 3 ) then
		local now = timehandle()			

		for i=0, maxclients, 1 do
			if et.gentity_get(i,"classname") == "player" then -- this tests if the playerentity is used! useless to close a entity wich is not in use.
				-- @Ilduca note: client["team"] is set to false somewhere in this code
				if slot[i]["team"] ~= -1 then
					closeTeam ( i )
				end
			end
		end

		gstate = tonumber(et.trap_Cvar_Get( "gamestate" ))
		
		-- Added last kill of the round
		execCmd(lastkill, "chat \"^2And the last kill of the round goes to: ^7<COLOR_PLAYER>\"" , lastkill)
		--TODO: Should we call the save to the DB right here?
	end
end

function et_Obituary( _victim, _killer, _mod )
	if debug == 1 then
		et.G_LogPrint ("MOD: ".._victim .. " wurd kill " .._killer .."Index:".. _Deaththingie .."  ;".. meansofdeath[_mod].."\n")
	end
	
	if _killer == 1022 then
		-- this is for a kill by falling or similar trough the world. Mapmortar etc also.
		
		slot[_victim]["killer"] = _killer
		slot[_victim]["deadwep"] = string.sub(meansofdeath[_mod], 5)
		
		-- update kill vars (victim only)
		
	else -- all non world kills
		 
		pussyFactCheck( _victim, _killer, _mod )

		slot[_killer]["victim"] = _victim
		slot[_killer]["killwep"] = string.sub(meansofdeath[_mod], 5)

		slot[_victim]["killer"] = _killer
		slot[_victim]["deadwep"] = string.sub(meansofdeath[_mod], 5)
		

		lastkiller = _killer
		
		
		-- update client vars ...
		
		-- Self kill (restriction)
		if _killer == _victim then
			if _mod == 33 then
				slot[_killer]["selfkills"] = slot[_killer]["selfkills"] + 1 -- what about if they use nades?
			end
			-- TODO: wtf? why not just add 1 to the field? Why call an ETfunction if WE could do it faster?? 
			slot[_victim]["death"] = tonumber(et.gentity_get(_victim,"sess.deaths"))
			-- slot[_victim]["tkills"] = tonumber(et.gentity_get(_clientNum,"sess.team_kills")) -- TODO ????
			slot[_victim]["tkilled"] = slot[_victim]["tkilled"] + 1
		else -- _killer <> _victim
			-- we assume client[team] is always updated
			if slot[_killer]["team"] == slot[_victim]["team"] then -- Team kill
				-- TODO: check if death/kills need an update here
				slot[_victim]["tkills"] = tonumber(et.gentity_get(_clientNum,"sess.team_kills"))			
			else -- cool kill
				slot[_victim]["death"] = tonumber(et.gentity_get(_victim,"sess.deaths"))
				slot[_killer]["kills"] = tonumber(et.gentity_get(_killer,"sess.kills"))		
			end
		end
			
	end -- end of 'all not world kills'

	-- uneven teams solution - the evener
	if evenerdist ~= -1 then
		killcount = killcount +1
		seconds = (et.trap_Milliseconds() / 1000)
		if killcount % 2 == 0 and (seconds - lastevener ) >= evenerdist then
			checkBalance( true )
			lastevener = seconds
		end
	end

	-- last kill of the round
	lastkill = _killer
end

function et_ConsoleCommand( _command )
	if debug == 1 then
	  et.trap_SendServerCommand( -1 ,"cpm \"" .. color .. "ConsoleCommand - command: " .. _command )
	end
	
	-- noq cmds ...
	if string.lower(et.trap_Argv(0)) == commandprefix.."noq" then  
		if (et.trap_Argc() < 2) then 
			et.G_Print("#sql is used to access the db with common sql commands.\n") 
			et.G_Print("usage: ...")
			return 1 
		end 
	-- noq warn ...	
	elseif string.lower(et.trap_Argv(0)) == commandprefix.."warn" then
		-- try first param to cast as int
		-- if int check if slot .. ban
		-- if not try to get player via part of name ...
		
	end
	-- add more cmds here ...
end

function et_ClientSpawn( _clientNum, _revived )
	-- TODO: check if this works
	-- _revived == 1 means he was revived
	if _revived ~= 1 then
		updateTeam(_clientNum)	
	end
end

-------------------------------------------------------------------------------
-- help functions
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- initClient
-- Gets DbInfos and checks for Ban and Mute
-- the very first action  
-------------------------------------------------------------------------------
function initClient ( _clientNum, _FirstTime, _isBot)
	-- note: this script should work w/o db connection
	-- greetings functionality: check if connect (1) or reconnect (2)
	

	--'static' clientfields
	slot[_clientNum]["pkey"] 	= string.upper( et.Info_ValueForKey( et.trap_GetUserinfo( _clientNum ), "cl_guid" ))
	slot[_clientNum]["ip"] 		= et.Info_ValueForKey( et.trap_GetUserinfo( _clientNum ), "ip" )
	slot[_clientNum]["isBot"] 	= _isBot
	slot[_clientNum]["conname"] = et.Info_ValueForKey( et.trap_GetUserinfo( _clientNum ), "name" )
	slot[_clientNum]["level"]	= et.G_shrubbot_level(_clientNum)
	slot[_clientNum]["flags"]	= "" -- TODO
	slot[_clientNum]["start"] 	= timehandle('N') 		-- Get the start connection time

	-- 'dynamic' clientfields
	slot[_clientNum]["team"] 	= false -- set the team on client begin (don't use nil here, as it deletes the index!)
	slot[_clientNum]["axtime"] 	= 0
	slot[_clientNum]["altime"] 	= 0
	slot[_clientNum]["sptime"] 	= 0
	slot[_clientNum]["lctime"] 	= 0
	slot[_clientNum]["acc"] 	= 0
	slot[_clientNum]["kills"] 	= 0
	slot[_clientNum]["tkills"] 	= 0
	slot[_clientNum]["netname"] = false
	slot[_clientNum]["victim"] 	= -1
	slot[_clientNum]["killwep"] = "nothing"
	slot[_clientNum]["killer"] 	= -1
	slot[_clientNum]["deadwep"] = "nothing"
	slot[_clientNum]["selfkills"]	= 0
	

	slot[_clientNum]["death"] 	= 0
	slot[_clientNum]["uci"] 	= 0
	slot[_clientNum]["pf"]		= 0

	-- non db client fields
	slot[_clientNum]["tkilled"] = 0

	
	if _FirstTime == 1 then 
		slot[_clientNum]["ntg"] = true
	else
		slot[_clientNum]["ntg"] = false
	end	
					
	if debug == 1 then
		et.trap_SendConsoleCommand(et.EXEC_NOW , "cpm \"LUA: INIT CLIENT \n \"" )
	end
	
	if databasecheck == 1 then
		if debug == 1 then
			et.trap_SendConsoleCommand(et.EXEC_NOW , "cpm \"LUA: INIT DATABASECHECK EXEC \n \"" )
		end
		
		updatePlayerInfo(_clientNum)
		
		slot[_clientNum]["setxp"] = true
		slot[_clientNum]["xpset"] = false
		
		return nil
				
	end
	
	if debug == 1 then		
		et.trap_SendConsoleCommand(et.EXEC_NOW , "cpm \"LUA: INIT CLIENT NO DATABASE INTERACTION \n \"" )
	end
	
    return nil
end

-------------------------------------------------------------------------------
-- updatePlayerInfo
-- Updates the Playerinformation out of the Database (IF POSSIBLE!)
-------------------------------------------------------------------------------
function updatePlayerInfo ( _clientNum )
	--Search the GUID in the database ( GUID is UNIQUE, so we just have 1 result, stop searching when we have it )
	cur = assert (con:execute("SELECT * FROM player WHERE pkey='".. slot[_clientNum]["pkey"] .."' LIMIT 1"))
	row = cur:fetch ({}, "a")
	cur:close()
	
	-- This player is already present in the database
	if row then
		if debug == 1 then
			et.trap_SendConsoleCommand(et.EXEC_NOW , "cpm \"LUA: INIT CLIENT ROW EXISTS \n \"" )
		end
		-- Start to collect related information for this player id
		-- player
		slot[_clientNum]["id"] = row.id
		slot[_clientNum]["regname"] = row.regname
		slot[_clientNum]["conname"] = row.conname
		--slot[_clientNum]["netname"] = row.netname --we dont set netname to a invalid old databaseentry
		slot[_clientNum]["clan"] = row.clan	
		slot[_clientNum]["user"] = row.user -- only for admin info
		slot[_clientNum]["banreason"] = row.banreason
		slot[_clientNum]["bannedby"] = row.bannedby
		slot[_clientNum]["banexpire"] = row.banexpire
		slot[_clientNum]["mutedreason"] = row.mutedreason
		slot[_clientNum]["mutedby"] = row.mutedby
		slot[_clientNum]["muteexpire"] = row.muteexpire
		slot[_clientNum]["warnings"] = row.warnings
		slot[_clientNum]["suspect"] = row.suspect
		slot[_clientNum]["regdate"] = row.regdate
		slot[_clientNum]["createdate"] = row.createdate -- first seen
		slot[_clientNum]["level"] = et.G_shrubbot_level( _clientNum ) --TODO: REAL LEVEL/Who is more important, shrub or database? IRATA: no q - database
		slot[_clientNum]["flags"] = row.flags -- TODO: pump it into game
				
		--Perhaps put into updatePlayerXP
		slot[_clientNum]["xp0"] = row.xp0
		slot[_clientNum]["xp1"] = row.xp1
		slot[_clientNum]["xp2"] = row.xp2
		slot[_clientNum]["xp3"] = row.xp3
		slot[_clientNum]["xp4"] = row.xp4
		slot[_clientNum]["xp5"] = row.xp5
		slot[_clientNum]["xp6"] = row.xp6
		slot[_clientNum]["xptot"] = row.xptot
			
		if debug == 1 then
			et.trap_SendConsoleCommand(et.EXEC_NOW , "cpm \"LUA: INIT CLIENT FROM ROW GOOD\n \"" )
		end
	else	
		if debug == 1 then
			et.trap_SendConsoleCommand(et.EXEC_NOW , "cpm \"LUA: INIT CLIENT NO ROW -> NEW \n \"" )
		end
		-- Since he is new, he isn't banned or muted: let him pass those check
		slot[_clientNum]["banreason"] = ""
		slot[_clientNum]["bannedby"] = ""
		slot[_clientNum]["banexpire"] = "1000-01-01 00:00:00"
		slot[_clientNum]["mutedreason"] = ""
		slot[_clientNum]["mutedby"] = ""
		slot[_clientNum]["muteexpire"] = "1000-01-01 00:00:00"
		
		-- Go to Clientbegin and say hes new
		slot[_clientNum]["new"] = true
	end
end

-------------------------------------------------------------------------------
-- updatePlayerXP
-- Update a players xp from the values in his previously set Xptable
-- just a g_xp_setfunction for all values
-------------------------------------------------------------------------------
function updatePlayerXP( _clientNum )
	
	if tonumber(slot[_clientNum]["xp0"]) < 0 then
		slot[_clientNum]["xp0"] = 0
	end
	if tonumber(slot[_clientNum]["xp1"]) < 0 then
		slot[_clientNum]["xp1"] = 0
	end
	if tonumber(slot[_clientNum]["xp2"]) < 0 then
		slot[_clientNum]["xp2"] = 0
	end
	if tonumber(slot[_clientNum]["xp3"]) < 0 then
		slot[_clientNum]["xp3"] = 0
	end
	if tonumber(slot[_clientNum]["xp4"]) < 0 then
		slot[_clientNum]["xp4"] = 0
	end
	if tonumber(slot[_clientNum]["xp5"]) < 0 then
		slot[_clientNum]["xp5"] = 0
	end
	if tonumber(slot[_clientNum]["xp6"]) < 0 then
		slot[_clientNum]["xp6"] = 0
	end
	
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp0"], 0, 0 ) -- battle
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp1"], 1, 0 ) -- engi
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp2"], 2, 0 ) -- medic
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp3"], 3, 0 ) -- signals
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp4"], 4, 0 ) -- light
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp5"], 5, 0 ) -- heavy
	et.G_XP_Set ( _clientNum , slot[_clientNum]["xp6"], 6, 0 ) -- covert
	slot[_clientNum]["xpset"] = true
end

-------------------------------------------------------------------------------
-- checkBan
-- Check if player is banned and kick him
-- TODO : would be cool to inform admins about bans through mail
-- TODO : add something that track a just-unbanned player ( for time bans )
--        in order to warn online admins and maybe the player himself
------------------------------------------------------------------------------- 
function checkBan ( _clientNum )
		
	if slot[_clientNum]["bannedby"] ~= "" then
		if  slot[_clientNum]["banreason"] ~= "" then
			if  slot[_clientNum]["banexpire"] ~= "1000-01-01 00:00:00" then
				-- Check for expired ban
				if timehandle( 'DS', 'N', slot[_clientNum]["banexpire"] ) > 0 then
				    -- The ban is expired: clear the ban fields and continue
				    slot[_clientNum]["bannedby"] = ""
				    slot[_clientNum]["banreason"] = ""
				    slot[_clientNum]["banexpire"] = "1000-01-01 00:00:00"
				    
				    return nil
				end
				return "You are banned by "..slot[_clientNum]["bannedby"].." until "..slot[_clientNum]["banexpire"]..". Reason: "..slot[_clientNum]["banreason"]
			else
				return "You are permanently banned by "..slot[_clientNum]["bannedby"]..". Reason: "..slot[_clientNum]["banreason"]
			end
		else
			if  slot[_clientNum]["banexpire"] ~= "1000-01-01 00:00:00" then
				-- Check for expired ban	
			    if timehandle( 'DS', 'N', slot[_clientNum]["banexpire"] ) > 0 then
				    -- The ban is expired: clear the ban fields and continue
				    slot[_clientNum]["bannedby"] = ""
				    slot[_clientNum]["banexpire"] = "1000-01-01 00:00:00"

				    return nil
				end
				return "You are banned by "..slot[_clientNum]["bannedby"].." until "..slot[_clientNum]["banexpire"]
			else
				return "You are permanently banned by "..slot[_clientNum]["bannedby"]
			end
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- checkMute
-- TODO: check this, functions is prepared to work w/o using the shrubbot.cfg
-- We need a function, which checks if bans/mutes are still valid and updates the database (delete old values of non connected players)
-- @IlDuca TODO is done ?
-------------------------------------------------------------------------------
function checkMute ( _clientNum )
	-- give hint and mute player ...
	if slot[_clientNum]["mutedby"] ~= "" then
		et.gentity_set(_clientNum,"sess.muted", 1) 
		if slot[_clientNum]["mutedreason"] ~= "" then
			et.gentity_set(_clientNum,"sess.muted_by", slot[_clientNum]["mutedreason"])
			if slot[_clientNum]["muteexpire"] ~= "1000-01-01 00:00:00" then
				et.gentity_set(_clientNum,"sess.auto_mute_time", slot[_clientNum]["muteexpire"])
				et.trap_SendServerCommand( _clientNum, "cpm \"^1You are muted by "..slot[_clientNum][mutedby].." until "..row.muteexpire..". Reason: "..slot[_clientNum][mutedreason])
			else
				et.trap_SendServerCommand( _clientNum, "cpm \"^1You are permanently muted by "..slot[_clientNum][mutedby]..". Reason: "..slot[_clientNum][mutedreason])
			end
		else
			if slot[_clientNum]["muteexpire"] ~= "1000-01-01 00:00:00" then
				et.gentity_set(_clientNum,"sess.auto_mute_time", slot[_clientNum]["muteexpire"])
				et.trap_SendServerCommand( _clientNum, "cpm \"^1You are muted by "..slot[_clientNum][mutedby].." until "..slot[_clientNum][muteexpire])
			else
				et.trap_SendServerCommand( _clientNum, "cpm \"^1You are permanently muted by "..slot[_clientNum][mutedby])
			end
		end
	end
	
	return nil
end

-------------------------------------------------------------------------------
-- creatNewPlayer
-- Create a new Player: write to Database, set Xp 0
-- maybe could also be used to reset Player, as pkey is unique
-------------------------------------------------------------------------------
function createNewPlayer ( _clientNum )
	local name = string.gsub(slot[_clientNum]["netname"],"\'", "\\\'")
	local conname = string.gsub(slot[_clientNum]["conname"],"\'", "\\\'")

	-- This player is a new one: create a new database entry with our Infos
	res = assert (con:execute("INSERT INTO player (pkey, isBot, netname, updatedate, createdate, conname) VALUES ('"
		..slot[_clientNum]["pkey"].."', "
		..slot[_clientNum]["isBot"]..", '"
		..name.."', '"
		..slot[_clientNum]["start"] .."', '"
		..slot[_clientNum]["start"] .."', '"
		..conname.."')"))
		
	-- Jep, these values are correct, as he is new!
	slot[_clientNum]["xp0"] = 0
	slot[_clientNum]["xp1"] = 0
	slot[_clientNum]["xp2"] = 0
	slot[_clientNum]["xp3"] = 0
	slot[_clientNum]["xp4"] = 0
	slot[_clientNum]["xp5"] = 0
	slot[_clientNum]["xp6"] = 0
	slot[_clientNum]["xptot"] = 0
	slot[_clientNum]["suspect"] = 0
	slot[_clientNum]["new"] = nil
	
	-- And now we will get all our default values 
	updatePlayerInfo (_clientNum)
end

-------------------------------------------------------------------------------
--timehandle
-- Function to handle times
-- TODO : check if the time returned with option 'D' is in the right format we need
-- TODO : actually, 'D' and 'DS' are almost equal: save some lines mergin them!!
-- NOTE ABOUT TIME IN LUA: the function os.difftime works only with arguments passed in seconds, so
--						   before pass anything to that functions we have to convert the date in seconds
--						   with the function os.time, then convert back the result with os.date
-------------------------------------------------------------------------------
function timehandle ( op, time1, time2)
	-- The os.* functions needs a shell to be linked and accessible by the process running LUA
	-- TODO : this check should be moved at script start because os.* functions are really
	-- 		  "popular" so we may use them in other functions too
	if os.execute() == 0 then
		error("This process needs an active shell to be executed.")
	end

	local timed = nil

	if op == 'N' then
		-- N -> return current date ( NOW )
		local timed = os.date("%Y-%m-%d %X")
		if timed then
			return timed
		end
		return nil
	elseif op == 'D' then
	    -- D -> compute time difference time1-time2
	    if time1==nil or time2==nil then
	        error("You must to input 2 arguments to use the 'D' option.")
	    end

	    -- Check if time1 is 'N' ( NOW )
	    if time1 == 'N' then
	    	-- Check if time2 is in the right format
	    	if string.len(time2) == 19 then
	    		timed = os.difftime(os.time(),os.time{year=tonumber(string.sub(time2,1,4)), month=tonumber(string.sub(time2,6,7)), day=tonumber(string.sub(time2,9,10)), hour=tonumber(string.sub(time2,12,13)), min=tonumber(string.sub(time2,15,16)), sec=tonumber(string.sub(time2,18,19))})
			end
	    end
	    -- Check if time1 and time2 are in the right format
	    if string.len(time1) == 19 and string.len(time2) == 19 then
      		timed = os.difftime(os.time{year=tonumber(string.sub(time1,1,4)), month=tonumber(string.sub(time1,6,7)), day=tonumber(string.sub(time1,9,10)), hour=tonumber(string.sub(time1,12,13)), min=tonumber(string.sub(time1,15,16)), sec=tonumber(string.sub(time1,18,19))},os.time{year=tonumber(string.sub(time2,1,4)), month=tonumber(string.sub(time2,6,7)), day=tonumber(string.sub(time2,9,10)), hour=tonumber(string.sub(time2,12,13)), min=tonumber(string.sub(time2,15,16)), sec=tonumber(string.sub(time2,18,19))})
	    end
	elseif op == 'DS' then
	    -- DS -> compute time difference time1-time2 and return result in seconds
	    if time1==nil or time2==nil then
	        error("You must to input 2 arguments to use the 'DS' option.")
	    end

	    -- Check if time1 is 'N' ( NOW )
	    if time1 == 'N' then
	    	-- Check if time2 is in the right format
	    	if string.len(time2) == 19 then
	    		timed = os.difftime(os.time(),os.time{year=tonumber(string.sub(time2,1,4)), month=tonumber(string.sub(time2,6,7)), day=tonumber(string.sub(time2,9,10)), hour=tonumber(string.sub(time2,12,13)), min=tonumber(string.sub(time2,15,16)), sec=tonumber(string.sub(time2,18,19))})
				return timed
			end
	    end
	    -- Check if time1 and time2 are in the right format
	    if string.len(time1) == 19 and string.len(time2) == 19 then
      		timed = os.difftime(os.time{year=tonumber(string.sub(time1,1,4)), month=tonumber(string.sub(time1,6,7)), day=tonumber(string.sub(time1,9,10)), hour=tonumber(string.sub(time1,12,13)), min=tonumber(string.sub(time1,15,16)), sec=tonumber(string.sub(time1,18,19))},os.time{year=tonumber(string.sub(time2,1,4)), month=tonumber(string.sub(time2,6,7)), day=tonumber(string.sub(time2,9,10)), hour=tonumber(string.sub(time2,12,13)), min=tonumber(string.sub(time2,15,16)), sec=tonumber(string.sub(time2,18,19))})
			return timed
		end
	end

 	if timed then
		if timed < 60 then
		    if timed < 10 then
		        return string.format("00:00:0%d",timed)
		    else
	    		return string.format("00:00:%d",timed)
	    	end
	    end

	    local seconds = timed % 60
	    local minutes = (( timed - seconds ) / 60 )

	    if minutes < 60 then
	        if minutes < 10 and seconds < 10 then
	    		return string.format("00:0%d:0%d",minutes,seconds)
	    	elseif minutes < 10 then
	    	    return string.format("00:0%d:%d",minutes,seconds)
			elseif seconds < 10 then
			    return string.format("00:%d:0%d",minutes,seconds)
			else
			    return string.format("00:%d:%d",minutes,seconds)
			end
	    end

	    minutes = minutes % 60
	    local houres = ((( timed - seconds ) / 60 ) - minutes ) / 60

		if minutes < 10 and seconds < 10 then
			return string.format("%d:0%d:0%d",houres,minutes,seconds)
		elseif minutes < 10 then
	    	return string.format("%d:0%d:%d",houres,minutes,seconds)
		elseif seconds < 10 then
			return string.format("%d:%d:0%d",houres,minutes,seconds)
		else
			return string.format("%d:%d:%d",houres,minutes,seconds)
		end
	end

	return nil
end

-------------------------------------------------------------------------------
-- WriteClientDisconnect
-- Dumps Client into Dbase at Disconnect or end of round
-- This function really dumps everything by calling our two helper functions
-------------------------------------------------------------------------------
function WriteClientDisconnect( _clientNum, _now, _timediff )
	if slot[_clientNum]["team"] == false then
		slot[_clientNum]["uci"] = et.gentity_get( _clientNum ,"sess.uci")
	
		-- In this case the player never entered the game world, he disconnected during connection time
		query = "INSERT INTO session (pkey, slot, map, ip, valid, start, end, sstime, uci) VALUES ('"
			..slot[_clientNum]["pkey"].."', '"
			.._clientNum.."', '"
			..map.."', '"
			..slot[_clientNum]["ip"].."', '" 
			.."0".."', '"
			..slot[_clientNum]["start"].."', '"
			..timehandle('N').."' , '"
            -- TODO : check if this works. Is the output from 'D' option in the needed format for the database?
			..timehandle('D','N',slot[_clientNum]["start"]).."' , '"
			.. slot[_clientNum]["uci"].."')"
		
		if debugquerries == 1 then	
			et.G_LogPrint( "\n\n".. query .. "\n\n" ) 
		end
		
		res = assert (con:execute( query ))
		et.G_LogPrint( "Noq: saved player ".._clientNum.." to Database\n" ) 
	else
		-- The player disconnected during a valid game session. We have to close his playing time
		-- If "team" == -1 means we already closed the team time, so we don't have to do it again
		-- This is needed to stop team time at map end, when debriefing starts
		if slot[_clientNum]["team"] ~= -1 then
			closeTeam ( _clientNum )
		end
						
		-- Write to session if player was in game
		saveSession ( _clientNum )
		savePlayer ( _clientNum )
		et.G_LogPrint( "Noq: saved player and session ".._clientNum.." to Database\n" )

	end	
	slot[_clientNum]["ntg"] = false
end

-------------------------------------------------------------------------------
-- savePlayer
-- Dumps into player table - NO SESSIONDUMPING
-- call if you changed something important to secure it in database
-- eg Xp, Level, Ban, Mute, 
-------------------------------------------------------------------------------
function savePlayer ( _clientNum )
	slot[_clientNum]["ip"] = et.Info_ValueForKey( et.trap_GetUserinfo( _clientNum ), "ip" )
	if slot[_clientNum]["ip"] == "localhost" then
		-- He is a bot, mark it's ip as "localhost"
		slot[_clientNum]["ip"] = "127.0.0.1"
	else
		s,e,slot[_clientNum]["ip"] = string.find(slot[_clientNum]["ip"],"(%d+%.%d+%.%d+%.%d+)")
	end 
	
	if slot[_clientNum]["xpset"] == false and xprestore == 1 then
    	et.G_LogPrint("NOQ: ERROR while setting xp in database: XP not properly restored!\n")
    	return
    end

	-- We also write to player, for our actual data
	-- TODO
	-- slot[_clientNum]["user"] 
	-- slot[_clientNum]["password"] 
	-- slot[_clientNum]["email"] 
	-- slot[_clientNum]["netname"] ????

	local name = string.gsub(slot[_clientNum]["netname"],"\'", "\\\'")

	-- FIXME getting attempt to concatenate field 'muteexpire' (a nil value) (sqlite
	-- IlDuca : done for banexpire
	res = assert (con:execute("UPDATE player SET clan='".. slot[_clientNum]["clan"] .."',           \
		 netname='".. name  .."',\
		 xp0='".. et.gentity_get(_clientNum,"sess.skillpoints",0)  .."', 	\
		 xp1='".. et.gentity_get(_clientNum,"sess.skillpoints",1)  .."', 	\
		 xp2='".. et.gentity_get(_clientNum,"sess.skillpoints",2)  .."', 	\
		 xp3='".. et.gentity_get(_clientNum,"sess.skillpoints",3)  .."',	\
		 xp4='".. et.gentity_get(_clientNum,"sess.skillpoints",4)  .."', 	\
		 xp5='".. et.gentity_get(_clientNum,"sess.skillpoints",5)  .."',	\
		 xp6='".. et.gentity_get(_clientNum,"sess.skillpoints",6)  .."',	\
		 xptot='".. ( et.gentity_get(_clientNum,"sess.skillpoints",0)  + et.gentity_get(_clientNum,"sess.skillpoints",1)  + et.gentity_get(_clientNum,"sess.skillpoints",2)  + et.gentity_get(_clientNum,"sess.skillpoints",3)  + et.gentity_get(_clientNum,"sess.skillpoints",4)  + et.gentity_get(_clientNum,"sess.skillpoints",5)  + et.gentity_get(_clientNum,"sess.skillpoints",6) )  .. "',\
		 level='".. slot[_clientNum]["level"] .."',				\
		 banreason='".. slot[_clientNum]["banreason"]  .."',	\
		 bannedby='".. slot[_clientNum]["bannedby"]  .."',		\
		 banexpire='".. slot[_clientNum]["banexpire"] .."',		\
		 mutedreason='".. slot[_clientNum]["mutedreason"] .."',	\
		 mutedby='".. slot[_clientNum]["mutedby"] .."',			\
		 warnings='".. slot[_clientNum]["warnings"] .."',		\
		 suspect='".. slot[_clientNum]["suspect"] .."'			\
		 WHERE pkey='".. slot[_clientNum]["pkey"] .."'"))

--		muteexpire='".. slot[_clientNum]["muteexpire"] .."',	\
end

-------------------------------------------------------------------------------
-- saveSession
-- Dumps the sessiondata
-- should only be used on session-end to not falsify sessions
-------------------------------------------------------------------------------
function saveSession( _clientNum )
	if recordbots == 0 and slot[_clientNum]["isBot"] == 1 then
		 et.G_LogPrint( "Noq: not saved bot session ".._clientNum.." to Database" )
		return
	end

	-- TODO: fixme sqlite only ?
	-- TODO: think about moving these vars into client structure earlier ...
	slot[_clientNum]["uci"] = et.gentity_get( _clientNum ,"sess.uci")
	slot[_clientNum]["ip"] = et.Info_ValueForKey( et.trap_GetUserinfo( _clientNum ), "ip" )
	
	if slot[_clientNum]["ip"] == "localhost" then
		-- He is a bot, mark it's ip as "localhost"
		slot[_clientNum]["ip"] = "127.0.0.1"
	else
		s,e,slot[_clientNum]["ip"] = string.find(slot[_clientNum]["ip"],"(%d+%.%d+%.%d+%.%d+)")
	end 

	-- If player was ingame, we really should save his XP to!
	-- TODO: think about updating this into client structure
	-- The final questions is: Do we need the XP stuff at runtime in the client structure ?
--[[
	local battle	=	et.gentity_get(_clientNum,"sess.skillpoints",0) 
	local engi		=	et.gentity_get(_clientNum,"sess.skillpoints",1)
	local medic		=	et.gentity_get(_clientNum,"sess.skillpoints",2)
	local signals	=	et.gentity_get(_clientNum,"sess.skillpoints",3)
	local light		=	et.gentity_get(_clientNum,"sess.skillpoints",4)
	local heavy		=	et.gentity_get(_clientNum,"sess.skillpoints",5)
	local covert	=	et.gentity_get(_clientNum,"sess.skillpoints",6)
--]]
	
	-- TODO: Think about using this earlier, is this the injection check ?		Yes, its an escape function for ' (wich should be the only character allowed by et and with a special meaning for SQL)
	local name = string.gsub(slot[_clientNum]["netname"],"\'", "\\\'")
	
	-- Write to session if player was in game
		
	local sessquery = "INSERT INTO session (pkey, slot, map, ip, netname, valid, start, end, sstime, axtime, altime, sptime, xp0, xp1, xp2, xp3, xp4, xp5, xp6, xptot, acc, kills, tkills, death) VALUES ('"
			..slot[_clientNum]["pkey"].."', '"
			.._clientNum .."', '"
			..map.."', '"
			..slot[_clientNum]["ip"].."', '"
			.. name .."', "
			.."1" ..", '"
			..slot[_clientNum]["start"].."', '"
			..timehandle('N').. "',  '"
            -- TODO : check if this works. Is the output from 'D' option in the needed format for the database?
			..timehandle('D','N',slot[_clientNum]["start"]).."' , '"
			..slot[_clientNum]["axtime"].."', '"
			..slot[_clientNum]["altime"].."', '"
			..slot[_clientNum]["sptime"].."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",0).."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",1).."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",2).."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",3).."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",4).."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",5).."', '"
			..et.gentity_get(_clientNum,"sess.skillpoints",6).."','"
			..(et.gentity_get(_clientNum,"sess.skillpoints",0) + et.gentity_get(_clientNum,"sess.skillpoints",1) + et.gentity_get(_clientNum,"sess.skillpoints",2) + et.gentity_get(_clientNum,"sess.skillpoints",3) + et.gentity_get(_clientNum,"sess.skillpoints",4) + et.gentity_get(_clientNum,"sess.skillpoints",5) + et.gentity_get(_clientNum,"sess.skillpoints",6) ).."','"
			.."0".."', '"
			..slot[_clientNum]["kills"].."', '"
			..slot[_clientNum]["tkills"].."', '"
			..slot[_clientNum]["death"].. "' )"
		res = assert (con:execute(sessquery))
	
	if debugquerries == 1 then	
		et.G_LogPrint( "\n\n".. sessquery .. "\n\n" ) 
	end
end

-------------------------------------------------------------------------------
-- gotCmd
-- determines and prepares the arguments for our Shrubcmds
-------------------------------------------------------------------------------
function gotCmd( _clientNum, _command, _vsay)

	local arg0 = string.lower(et.trap_Argv(0))
	local arg1 = string.lower(et.trap_Argv(1))
	local arg2 = string.lower(et.trap_Argv(2))

	local cmd
	-- TODO: we should use level from Lua client model
	local lvl = tonumber(et.G_shrubbot_level( _clientNum ) )
	local realcmd
	
	if _vsay == nil then -- silent cmd
	cmd = string.sub(arg0 ,2)
		argw = arg1
	elseif _vsay == false then -- normal say
		cmd = string.sub(arg1 ,2)
		argw = arg2
	else  -- its a vsay!
		cmd = string.sub(arg2 ,2)
		argw = string.lower(et.trap_Argv(3))
	end

	-- thats a hack to clearly get the second parameter.
	-- NQ-Gui chat uses cvars to pass the say-content
	if string.find(cmd, " ") ~= nil then
	t = justWords(cmd)
		cmd = t[1]
		argw = t[2]
	end

	-- We search trough the commands-array for a suitable command
	for i=lvl, 0, -1 do
		if commands[i][cmd] ~= nil then
			execCmd(_clientNum, commands[i][cmd], argw)
			if _vsay == nil then
				return 1
			end
			return
		end
	end
end

-------------------------------------------------------------------------------
-- justWords
-- Splits a string into a table on occurence of Whitespaces
-------------------------------------------------------------------------------
function justWords( _str )
	local t = {}
	local function helper(word)	table.insert(t, word) return "" end
	if not _str:gsub("%S+", helper):find"%S" then 	return t end
end

-------------------------------------------------------------------------------
-- execCmd
-- The real work to exec a cmd is done here, all substitutions and the switch for
-- Lua and shellcommands are done here
-------------------------------------------------------------------------------
function execCmd(_clientNum , _cmd, _argw)
	local str = _cmd
	local lastkilled = slot[_clientNum]["victim"]
	local lastkiller = slot[_clientNum]["killer"] 
	
	if lastkilled == 1022 then
		nlastkilled = "World"
	elseif lastkilled == -1 then -- well, fresh player...
		lastkilled = _clientNum
		nlastkilled = "nobody"
	elseif lastkilled == _clientNum then
		nlastkilled = "myself"
	else
		nlastkilled = et.gentity_get(lastkilled, "pers.netname")
	end
	
	if lastkiller == 1022 then 
		nlastkiller = "World"
	elseif lastkiller == -1 then
		lastkiller = _clientNum
		nlastkiller = "nobody"
	elseif lastkiller == _clientNum then
		nlastkiller = "myself"
	else
		nlastkiller = et.gentity_get(lastkiller, "pers.netname")
	end
	
	
	local otherplayer = _argw
	
	local assume = false
	otherplayer = getPlayerId(otherplayer)
	if otherplayer == nil then
		otherplayer = _clientNum
		assume = true
	end


	local t = tonumber(et.gentity_get(_clientNum,"sess.sessionTeam"))
	local c = tonumber(et.gentity_get(_clientNum,"sess.latchPlayerType"))
	local str = string.gsub(str, "<CLIENT_ID>", _clientNum)
	local str = string.gsub(str, "<GUID>", et.Info_ValueForKey( et.trap_GetUserinfo( _clientNum ), "cl_guid" ))
	local str = string.gsub(str, "<COLOR_PLAYER>", et.gentity_get(_clientNum,"pers.netname"))
	local str = string.gsub(str, "<ADMINLEVEL>", slot[_clientNum]["level"] )
	local str = string.gsub(str, "<PLAYER>", et.Q_CleanStr(et.gentity_get(_clientNum,"pers.netname")))
	local str = string.gsub(str, "<PLAYER_CLASS>", class[c])
	local str = string.gsub(str, "<PLAYER_TEAM>", team[t])
	local str = string.gsub(str, "<PARAMETER>", et.ConcatArgs( 2 ) )
	local str = string.gsub(str, "<PLAYER_LAST_KILLER_ID>", lastkiller )
	local str = string.gsub(str, "<PLAYER_LAST_KILLER_NAME>", et.Q_CleanStr( nlastkiller ))
	local str = string.gsub(str, "<PLAYER_LAST_KILLER_CNAME>", nlastkiller )
	local str = string.gsub(str, "<PLAYER_LAST_KILLER_WEAPON>", slot[_clientNum]["deadwep"])
	local str = string.gsub(str, "<PLAYER_LAST_VICTIM_ID>", lastkilled )
	local str = string.gsub(str, "<PLAYER_LAST_VICTIM_NAME>", et.Q_CleanStr( nlastkilled ))
	local str = string.gsub(str, "<PLAYER_LAST_VICTIM_CNAME>", nlastkilled )
	local str = string.gsub(str, "<PLAYER_LAST_VICTIM_WEAPON>", slot[_clientNum]["killwep"])
	--TODO
	-- local str = string.gsub(str, "<PLAYER_LAST_KILL_DISTANCE>", calculate! )
	
	--TODO Implement them
	--  Other possible Variables: <CVAR_XXX> <????>
	--local str = string.gsub(str, "<PNAME2ID>", pnameID)
	--local str = string.gsub(str, "<PBPNAME2ID>", PBpnameID)
	--local str = string.gsub(str, "<PB_ID>", PBID)
	--local str = string.gsub(str, "<RANDOM_ID>", randomC) 
	--local str = string.gsub(str, "<RANDOM_CNAME>", randomCName)
	--local str = string.gsub(str, "<RANDOM_NAME>", randomName)
	--local str = string.gsub(str, "<RANDOM_CLASS>", randomClass)
	--local str = string.gsub(str, "<RANDOM_TEAM>", randomTeam)
	--local teamnumber = tonumber(et.gentity_get(PlayerID,"sess.sessionTeam"))
	--local classnumber = tonumber(et.gentity_get(PlayerID,"sess.latchPlayerType"))
	
	
--		if otherplayer == _clientNum then -- "light security" to not ban or kick yourself (use only ids to ban or kick, then its safe)
	if assume == true then
		str = string.gsub(str, "<PART2PBID>", "65" )
		str = string.gsub(str, "<PART2ID>", "65" ) 
	end
		
	--else
	local t = tonumber(et.gentity_get(otherplayer,"sess.sessionTeam"))
	local c = tonumber(et.gentity_get(otherplayer,"sess.latchPlayerType"))
	str = string.gsub(str, "<PART2_CLASS>", class[c])
	str = string.gsub(str, "<PART2_TEAM>", team[t])
	str = string.gsub(str, "<PART2CNAME>", et.gentity_get(otherplayer, "pers.netname" ))
	str = string.gsub(str, "<PART2ID>", otherplayer )
	str = string.gsub(str, "<PART2PBID>", otherplayer + 1 ) 
	str = string.gsub(str, "<PART2GUID>", et.Info_ValueForKey( et.trap_GetUserinfo( otherplayer ), "cl_guid" ))
	str = string.gsub(str, "<PART2LEVEL>", et.G_shrubbot_level (otherplayer) )
	str = string.gsub(str, "<PART2NAME>", et.Q_CleanStr(et.gentity_get(otherplayer,"pers.netname")))

	--added for !afk etc, use when assume is ok 
	 str = string.gsub(str, "<PART2IDS>", otherplayer )
	--end
	
	-- This allows execution of lua-code in a normal Command. 
	if string.sub(str, 1,5) == "$LUA$" then
		--et.G_Print(string.sub(str,6))
		local tokall = loadstring(string.sub(str,6))
		tokall()
		return	
	else
	
	-- This allows Shell commands. WARNING: As long as lua waits for the command to complete, NQ+ET arent responding to anything, they are HALTED!
	-- Response of the Script is piped into NQ-Console(via print, so no commands)
		if string.sub(str, 1,5) == "$SHL$" then
			execthis = io.popen(string.sub(str,6))
			readshit = execthis:read("*a")
			execthis:close()
			readshit = string.gsub(readshit, "\n","\"\nqsay \"")
			et.trap_SendConsoleCommand(et.EXEC_APPEND, "qsay \" ".. readshit .. " \"")
			return	
		else
		-- well, at the end we send the command to the console
		et.trap_SendConsoleCommand( et.EXEC_APPEND, "".. str .. "\n " )
		
		end
	end
end

-------------------------------------------------------------------------------
-- getPlayerId
-- helper function to compute the clientid matching a part-string or the clientid
-------------------------------------------------------------------------------
function getPlayerId( _name )
    -- if it's nil, return nil
    if (_name == "") then
        return nil
    end

    -- if it's a number, interpret as slot number
    local clientnum = tonumber(_name)
    if clientnum then
        if (clientnum <= maxclients) and et.gentity_get(clientnum,"inuse") then
            return clientnum
        else
            return nil
        end
    end

	local test = et.ClientNumberFromString( _name ) -- Cool NQ function!
	if test == -1 then
    	return nil
	else
		return test
	end
end

-------------------------------------------------------------------------------
-- parseconf
-- Parses commandos from commandofile function
-------------------------------------------------------------------------------
function parseconf()
	local	datei = io.open ( (scriptpath .. "commands.cfg" ) ,"r") 
	
	for i=0, 31, 1 do				
		commands[i] = {}
	end
	nmr = 1
	nmr2 = 1
	for line in datei:lines() do
		local filestr = line
		local testcase = string.find(filestr, "^%s*%#")
		if testcase == nil then
			for level,comm,commin in string.gfind(filestr, "[^%#](%d+)%s*%-%s*(%w+)%s*%=%s*(.*)[^%\n]*") do
		--		et.G_LogPrint ("Parsing CMD:"..comm .. "level: "..level.." Content: ".. commin .."\n")
				i = tonumber(level)
				commands[i][comm] = commin	
		
				nmr = nmr +1
			end
		end
		nmr2 = nmr2 +1
	end

	datei:close()
	et.G_LogPrint("Parsed " ..nmr .." commands from "..nmr2.." lines. \n")
end

-------------------------------------------------------------------------------
-- Init NOQ function
-------------------------------------------------------------------------------
function initNOQ ()
	-- get all we need at gamestart from game
	gstate = tonumber(et.trap_Cvar_Get( "gamestate" ))
	map = tostring(et.trap_Cvar_Get("mapname"))
	    
	-- timelimit = tonumber(et.trap_Cvar_Get("timelimit")) -- update this on frame (if changed during game?) -- use it if you need it :) 
end

-------------------------------------------------------------------------------
-- getDBVersion
-- Checks for correct DBVersion
-- Disables DBaccess on wrong version!
-------------------------------------------------------------------------------
function getDBVersion()
	-- Check the database version
	cur = assert (con:execute("SELECT version FROM version ORDER BY id DESC LIMIT 1"))
	row = cur:fetch ({}, "a")
	cur:close()
	
	if row.version == version then
		databasecheck = 1
		et.G_LogPrint("^1Database "..dbname.." is up to date. Script version is ".. version .."\n")
	else
		et.G_LogPrint("^1Database "..dbname.." is not up to date: SQL support disabled! Requested version is ".. version .."\n")
		-- We don't need to keep the connection with the database open
		con:close()
		env:close()
	end
end

-------------------------------------------------------------------------------
-- updateTeam
-- set times accordingly when the player changes team
-------------------------------------------------------------------------------
function updateTeam( _clientNum )
	local teamTemp = tonumber(et.gentity_get(_clientNum,"sess.sessionTeam"))
	
	if teamTemp ~= tonumber(slot[_clientNum]["team"]) then -- now we have teamchange!!!
		
		if debug == 1 then
			if slot[_clientNum]["team"] ~= nil and teamTemp ~= nil then
			  et.SendConsoleCommand(et.EXEC_APPEND, "chat \" TEAMCHANGE: " ..team[tonumber(slot[_clientNum]["team"])] .." to " .. team[teamTemp] .. "  \"  ")
			end
		end
		
		closeTeam ( _clientNum )
		-- Now, we change the teamchangetime & team
		slot[_clientNum]["lastTeamChange"] = (et.trap_Milliseconds() / 1000 )
		slot[_clientNum]["team"] = teamTemp
	end
end

-------------------------------------------------------------------------------
-- closeTeam
-- closes a time session for a player
-------------------------------------------------------------------------------
function closeTeam( _clientNum )
	if tonumber(slot[_clientNum]["team"]) == 1 then -- axis
		slot[_clientNum]["axtime"] = slot[_clientNum]["axtime"] +( (et.trap_Milliseconds() / 1000) - slot[_clientNum]["lastTeamChange"]  )
	elseif tonumber(slot[_clientNum]["team"]) == 2 then -- allies
		slot[_clientNum]["altime"] = slot[_clientNum]["altime"] +( (et.trap_Milliseconds() / 1000) - slot[_clientNum]["lastTeamChange"]  )
	elseif tonumber(slot[_clientNum]["team"]) == 3 then -- Spec
		slot[_clientNum]["sptime"] = slot[_clientNum]["sptime"] +( (et.trap_Milliseconds() / 1000) - slot[_clientNum]["lastTeamChange"]  )
	end
		
	-- Set the player team to -1 so we know he cannot to change team anymore
	slot[_clientNum]["team"] = -1
end	

-------------------------------------------------------------------------------
-- mail functions
-------------------------------------------------------------------------------
function sendMail( _to, _subject, _text )
	if mail == "1" then
		-- TODO: clean up
		local mailserv = getConfig("mailserv")
		local mailport = getConfig("mailport")
		local mailfrom = getConfig("mailfrom")
		rcpt = _to
		-- end clean up

		mesgt = {
					headers = 	{
								to = _to,
								subject = _subject
								},
					body = _text
				}


		r, e = smtp.send {
		   from = mailfrom,
		   rcpt = rcpt, 
		   source = smtp.message(mesgt),
		   --user = "",
		   --password = "",
		   server = mailserv,
		   port = mailport
		}

		if (e) then
		   et.G_LogPrint("Could not send email: "..e.. "\n")
		end
	else
		et.G_LogPrint("Mails disabled.\n")
	end
end

-------------------------------------------------------------------------------
-- checkBalance ( force )
-- Checks for uneven teams and tries to even them
-- force is a boolean controlling if there is only an announcement or a real action is taken.
-- Action is taken if its true.
-------------------------------------------------------------------------------

function checkBalance( _force )

	-- TODO: rework this, actually we can access the needed data from the slot table: "team" etc
	-- would save a bit performance .. 
	local axis = {} -- is this a field required?
	local allies = {} -- is this a field required?
	--local numclients = 0 -- current clients in game

	for i=0, maxclients, 1 do				
			local team = tonumber(et.gentity_get(i,"sess.sessionTeam"))
			if team == 0 then
				table.insert(axis,i)
				--numclients = numclients +1
			end 
			if team == 1 then
				table.insert(allies,i)
				--numclients = numclients +1
			end
			-- team == 3 -- spec
	end
    

	local numaxis   = # axis
	local numallies = # allies
	local greaterteam = 3
	local smallerteam = 3
	local gtable = {}
	local teamchar = { "r" , "b" , "s" }

	if numaxis > numallies then
		greaterteam = 1
		smallerteam = 2
		gtable = axis
	end
	if numallies > numaxis then
		greaterteam = 2
		smallerteam = 1
		gtable = allies
	end


	if math.abs(numaxis - numallies) >= 5 then
		
		evener = evener +1
		if _force == true and evener >= 2  then
			et.trap_SendConsoleCommand( et.EXEC_NOW, "!shuffle " )
			et.trap_SendConsoleCommand( et.EXEC_APPEND, "cpm \"^2EVENER: ^1TEAMS SHUFFLED \" " )
		else
			et.trap_SendConsoleCommand( et.EXEC_APPEND, "cpm \"^1EVEN TEAMS OR SHUFFLE \" " )
		end
		return
	end

	if math.abs(numaxis - numallies) >= 2 then
		
		evener = evener +1
		if _force == true and evener >= 3  then
			local rand = math.random(# gtable)
			local cmd =  "!put ".. gtable[rand] .." "..teamchar[smallerteam].." \n"  
			--et.G_Print( "CMD: ".. cmd .. "\n") 
			et.trap_SendConsoleCommand( et.EXEC_APPEND, cmd ) 
			et.trap_SendServerCommand(-1 , "chat \"^2EVENER: ^7Thank you, ".. et.gentity_get(gtable[rand], "pers.netname") .." ^7for helping to even the teams. \" ")
		else
			et.trap_SendConsoleCommand( et.EXEC_APPEND, "chat \"^2EVENER: ^1Teams seem unfair, would someone from ^2".. team[greaterteam] .."^1 please switch to ^2"..team[smallerteam].."^1?  \" " )
		end
		
		return
	else
		evener = 0
	end
end

-------------------------------------------------------------------------------
-- greetClient - greets a client after his first clientbegin
-- only call after netname is set!
-------------------------------------------------------------------------------
function greetClient( _clientNum )
	local lvl = slot[_clientNum]["level"]
	if greetings[lvl] ~= nil then
		et.trap_SendConsoleCommand(et.EXEC_NOW, "cpm " .. string.gsub(greetings[lvl], "<COLOR_PLAYER>", slot[_clientNum]["netname"]))
	end
end

--***************************************************************************
-- Here start the commands usualy called trough the new command-system
-- they should not change internals, they are more informative 
--***************************************************************************
-- Current available:
-- cleanSession
-- pussout
-- checkBalance
-- rm_pbalias
-- teamdamage
-- showmaps


-------------------------------------------------------------------------------
-- cleanSession
-- cleans the Sessiontable from values older than X months
-- _arg for first call is amount of months, second call OK to confirm
-------------------------------------------------------------------------------
function cleanSession(_callerID, _arg)

	if arg == "" then
	et.trap_SendServerCommand(_callerID, "print \"\n Argument: first call: months to keep records, second call: OK  \n\"")
	return
	end

	if _arg == "OK" then
		if months ~= nil and months >= 1 and months <= 24 then
			et.trap_SendServerCommand(_callerID, "print \"\n Now erasing all records older than ".. months .." months  \n\"")
			
			-- TODO @luborg this DATE_SUB() is mysql only
			res = assert (con:execute("DELETE FROM session WHERE `end` < DATE_SUB(CURDATE(), INTERVAL "..months.." MONTH)"))
			
			et.trap_SendServerCommand(_callerID, "print \"\n Erased all records older than ".. months .." months  \n\"")
			et.G_LogPrint( "Noq: Erased data older than "..months.." months from the sessiontable\n" )
			if _callerID ~= -1 then
				et.G_LogPrint( "Noq: Deletion was issued by: "..slot[_callerID]['netname'].. " , GUID:"..slot[_callerID]['pkey'].. " \n" )
			end
			
			 
		else
			et.trap_SendServerCommand(_callerID, "print \"\n Please at first specify a value between 1 and 24   \n\"")
			et.trap_SendServerCommand(_callerID, "print \"\n Example: <command> 1 erases all sessionrecords older than 1 month\n\"")
			return
		end
	
	elseif tonumber(_arg) >= 1 and tonumber(_arg) <= 24 then
		
		local months = tonumber(_arg)
		et.trap_SendServerCommand(_callerID, "print \"\n Please confirm the deletion of "..months.." month's data with OK as argument of the same command\n\"")
		
	else
		et.trap_SendServerCommand(_callerID, "print \"\n Please specify a value between 1 and 24  \n\"")
		return
	end

end
-------------------------------------------------------------------------------
-- pussyout
-- Displays the Pussyfactor for Player _ClientNum
-------------------------------------------------------------------------------
--[[
-- Some Documentation for Pussyfactor:
-- For every kill, we add a value to the clients number, and to determine the the Pussyfactor, we 
-- divide that number trough the number of his kills multiplicated with 100.
-- If we add 100 for an mp40/thompsonkill, if makes only those kills , he will stay at pussyfactor 1
-- if we add more or less(as 100) to the number, his pf will rise or decline.
-- 
-- Pussyfactor < 1 		means he made "cool kills" = poison, goomba, knive
-- Pussyfactor = 1 		means he makes normal kills
-- Pussyfactor > 1      means he does uncool kills (Panzerfaust, teamkills, arty?)
--
-- As we add 100 for every normal kill, the pussyfactor approaches 1 after some time with "normal" kills
-- 
--]]

function pussyout( _clientNum )
	local pf = slot[tonumber(_clientNum)]["pf"]
	-- TODO: use client structure slot[tonumber(_clientNum)]["kills"] -- it should be up to date!
	local kills = tonumber(et.gentity_get(_clientNum,"sess.kills"))
	local realpf = 1

	if pf == 0 or kills == 0 then
		et.trap_SendConsoleCommand(et.EXEC_APPEND, "qsay \"^1Do some kills first...\"")
		return
	else
		realpf = string.format("%.1f", ( pf / (100 * kills) ) )
	end

	-- TODO: do we need to number here =
	et.trap_SendConsoleCommand(et.EXEC_APPEND,"qsay \""..slot[tonumber(_clientNum)]["netname"].."^3's pussyfactor is at: ".. realpf ..".Higher is worse. \"" ) 
	et.G_LogPrint("NOQ: PUSSY:"..slot[tonumber(_clientNum)]["netname"].." at ".. realpf .."\n")
end

-------------------------------------------------------------------------------
-- rm_pbalias
-- removes all your aliases from the pbalias.dat
-- thks to hose! (yeah, this is cool!)
-------------------------------------------------------------------------------
function rm_pbalias( _myClient, _hisClient )
	et.trap_SendServerCommand(-1, "print \"function pbalias entered\n\"")
	
	local file_name = "pbalias.dat"
	local inFile = pbpath .. file_name
	local outFile = pbpath .. file_name

	local hisGuid = slot[_hisClient]["pkey"]
	local arg1 = string.lower(hisGuid:sub(25, 32))

	-- all input is evil! check for length!
	et.trap_SendServerCommand(_myClient, "print \"\nSearching for Guid: " .. arg1 .. "\"")
	local file = assert(io.open( inFile , "r"))
	local lineCounter = 0
	local lineTable = {}
	local deletedLines = {}
	local loopcounter = 0

	for line in file:lines() do
		lineCounter = lineCounter + 1
		if arg1 ~= line:sub(25, 32) then
			table.insert(lineTable, line)
		else 
			table.insert(deletedLines, line)
		end
	end

	local inserted = table.maxn(lineTable) 
	local deleted = table.maxn(deletedLines)
	file:close()

	if deleted > 0 then
		-- writing new pbalias.dat
		file = assert(io.open(outFile, "w+"))
		for i, v in ipairs(lineTable) do
			file:write(v .. "\n")
			loopcounter = loopcounter + 1
		end
		file:flush()
		file:close()
	end

	-- some status info printed to stdout
	et.trap_SendServerCommand(myClient, "print \"\nEntries processed: " .. lineCounter .. "\"")
	et.trap_SendServerCommand(myClient, "print \"\nEntries deleted: " .. deleted .. "\"")
	et.trap_SendConsoleCommand(et.EXEC_NOW, "pb_sv_restart")
	
	return 1
end

-------------------------------------------------------------------------------
-- teamdamage 
-- Displays information about teamdamage to the caller and a small line for all
-- thks to hose!
-------------------------------------------------------------------------------
function teamdamage( myclient, slotnumber ) -- TODO: change this to (_myclient, _slotnumber) 
	
	local teamdamage 	= et.gentity_get (slotnumber, "sess.team_damage")		
	local damage 		= et.gentity_get(slotnumber, "sess.damage_given")

	local classnumber 	= et.gentity_get(slotnumber, "sess.playerType")

	-- TODO: use slottable 
	local teamnumber 	= et.gentity_get(slotnumber, "sess.sessionTeam")
	local teamname 		= team[teamnumber]		

	et.trap_SendServerCommand( myclient, "print \" ^7:" .. et.gentity_get(slotnumber, "pers.netname") .. "^w | Slot: ".. slotnumber ..
		"\n" .. 		class[classnumber] .. " | " .. teamname .. " | " .. weapons[et.gentity_get(slotnumber, "sess.latchPlayerWeapon")] .. " | " ..  weapons[et.gentity_get(slotnumber, "sess.latchPlayerWeapon2")] .. 
		"\nkills:        " .. et.gentity_get(slotnumber, "sess.kills") ..   	" | damage:       " .. damage .. 
		"\nteamkills:    " .. et.gentity_get(slotnumber, "sess.team_kills") ..  " | teamdamage:   " .. teamdamage .. "\n\"")

	-- notorische teambleeder ab ins cp!!!
	if teamdamage == 0 then
		et.trap_SendServerCommand( slotnumber, "cp \" ^7You got ^1"..teamdamage.." teamdamage ^7and ^2" .. damage .. " damage given! ^1".. getConfig("teamdamageMessage1") .. "\"") 
	elseif teamdamage < damage/10 then
		et.trap_SendServerCommand( slotnumber, "cp \" ^7You got ^1"..teamdamage.." teamdamage ^7and ^2" .. damage .. " damage given! ^1".. getConfig("teamdamageMessage2").. "\"") 
	elseif teamdamage < damage/5 then
		et.trap_SendServerCommand( slotnumber, "cp \" ^7You got ^1"..teamdamage.." teamdamage ^7and ^2" .. damage .. " damage given! ^1".. getConfig("teamdamageMessage3").. "\"") 
	elseif teamdamage < damage/2 then
		et.trap_SendServerCommand( slotnumber, "cp \" ^7You got ^1"..teamdamage.." teamdamage ^7and ^2" .. damage .. " damage given! ^1".. getConfig("teamdamageMessage4").. "\"") 
	elseif teamdamage < damage then
		et.trap_SendServerCommand( slotnumber, "cp \" ^7You got ^1"..teamdamage.." teamdamage ^7and ^2" .. damage .. " damage given! ^1".. getConfig("teamdamageMessage5").. "\"") 
	else 
		et.trap_SendServerCommand( slotnumber, "cp \" ^7You got ^1"..teamdamage.." teamdamage ^7and ^2" .. damage .. " damage given! ^1".. getConfig("teamdamageMessage6").. "\"") 
	end
end

-------------------------------------------------------------------------------
-- showmaps
-- Reads the camapaign-info in, then compares with current map, then
-- displays all maps and marks the current one
-------------------------------------------------------------------------------
function showmaps()
	ent = et.trap_Cvar_Get( "campaign_maps" ); -- TODO: create and use global var ? 
	local tat34 = {}
	local sep = ","

	-- helper function
	function split(str, pat)
	   local t = {}  -- NOTE: use {n = 0} in Lua-5.0
	   local fpat = "(.-)" .. pat
	   local last_end = 1
	   local s, e, cap = str:find(fpat, 1)
	   while s do
		  if s ~= 1 or cap ~= "" then
			 table.insert(t,cap)
		  end
		  last_end = e+1
		  s, e, cap = str:find(fpat, last_end)
	   end
	   if last_end <= #str then
		  cap = str:sub(last_end)
		  table.insert(t, cap)
	   end
	   return t
	end

	tat34 = split (ent, sep)
	local ent2 = "^3"

	map = tostring(et.trap_Cvar_Get("mapname"))

	-- helper function
	local function addit( i, v)
		if v == map  then
			ent2 = ent2 .. "^1" .. v .. "^3 <> "
		else
			ent2 = ent2 .. v .. " <> "
		end
	end

	for i,v in ipairs(tat34) do addit(i,v) end

	et.trap_SendConsoleCommand(et.EXEC_APPEND, "chat \"".. ent2 .. "\"")
end

-- Retuns rest of time to play
function timeLeft()
	return tonumber(et.trap_Cvar_Get("timelimit"))*1000 - ( et.trap_Milliseconds() - mapStartTime) -- TODO: check this!
end

-- Does the check for our pussy detection -- called in et_Obituary for non world kills
function pussyFactCheck( _victim, _killer, _mod )
	if pussyfact == 1 then
		-- determine teamkill or not
		if slot[_killer]["team"] == slot[_victim]["team"] then
			-- here it is teamkill
			-- NOTE: teamkill is not counted as a kill, wich means all added here is even stronger in its weight
			if _mod == 15 or _mod == 69 then
				slot[_killer]["pf"] = slot[_killer]["pf"] + 170
			else
				slot[_killer]["pf"] = slot[_killer]["pf"] + 110
			end
			
		else
			-- no teamkill -- TODO: use names ...
		
			--Knivekill -- why this? knife is cool! .... therefore it adds a value under 100. 
			if _mod == 5 or _mod == 65 then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 70
			
			-- PF
			elseif _mod == 15 or _mod == 69 then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 140
			
			-- Flamer
			elseif _mod == 17  then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 115
			
			--poison -- why this? poison is cool!
			elseif _mod == 61 then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 65
			
			-- goomba -- why this? goomba is cool!
			elseif _mod == 60  then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 60
			
			-- kick -- also cool
			elseif _mod == 21 then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 40
			
			-- sniper -- hhmmmmm
			elseif _mod == 51 or _mod == 14 or _mod == 46 then
			slot[_killer]["pf"] = slot[_killer]["pf"] + 90
			else
			-- if we count 100 up, nothing changes. at least it should 
			slot[_killer]["pf"] = slot[_killer]["pf"] + 100
			end
		end -- teamkill end

	end -- pussy end
end
