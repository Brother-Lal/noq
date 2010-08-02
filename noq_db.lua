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
-- ailmanki
-- BubbaG1
-- IRATA [*]

-------------------------------------------------------------------------------
-- DBMS
-------------------------------------------------------------------------------

--
-- We could allocate this each time, but since are used lot of times is better to make them global
-- TODO: cur and res are exactly the same things, so we could save memory using only one of them
-- cur = {}  -- Will handle the SQL commands returning informations ( es: SELECT )
-- res = {}  -- Will handle SQL commands without outputs ( es: INSERT )
-- row = {}  -- To manipulate the outputs of SQL command
-- --row1 = {} -- To manipulate the outputs of SQL command in case we need more than one request
-- TODO: does this apply here also? how to do then? ['cur'] and reference it each time?
--
-- TODO: Check for various injections possibilities, create a function to sanitize input!
-- TODO: Merge double code.. 

DBCon = {
	-- Database managment system to use
	['dbms']	= getConfig("dbms"), -- possible values mySQL, SQLite
	['dbname']  = getConfig("dbname"),
	['debugquerries'] = tonumber(getConfig("debugquerries")),
	['con'] = nil,
	['env'] = nil,
	['cur'] = {},
	['row'] = {},
	
	['DoConnect']	= function( self )
		-- Handle different dbms
		if self.dbms == "mySQL" then
			require "luasql.mysql"
			self.env = assert( luasql.mysql() )
			self.con = assert( self.env:connect(self.dbname, getConfig("dbuser"), getConfig("dbpassword"), getConfig("dbhostname"), getConfig("dbport")) )
		elseif self.dbms == "SQLite" then
			require "luasql.sqlite3" 
			self.env = assert( luasql.sqlite3() )
			-- this opens OR creates a sqlite db - if this file is loaded db is created -fix this?
			self.con = assert( self.env:connect( self.dbname ) )
		else
			-- stop script
			error("DBMS not supported.")
		end
	end,
	
	-------------------------------------------------------------------------------
	-- DoDisconnect
	-- Does close connection to the DBMS
	-------------------------------------------------------------------------------	
	['DoDisconnect']	= function ( self )
		self.con:close()
		self.env:close()
	end,
	
	-------------------------------------------------------------------------------
	-- GetVersion
	-- Returns DB Version
	-------------------------------------------------------------------------------
	['GetVersion']	= function( self )
		-- Check the database version
		self.cur = assert( self.con:execute("SELECT version FROM version ORDER BY id DESC LIMIT 1") )
		self.row = self.cur:fetch ({}, "a")
		self.cur:close()
		return self.row.version
	end,
	
	-------------------------------------------------------------------------------
	-- SetPlayerAlias
	-- Adds an Alias if not existing
	-------------------------------------------------------------------------------
	['SetPlayerAlias'] = function( self, thisName, thisGuid )
		--Search the GUID in the database ( GUID is UNIQUE, so we just have 1 result, stop searching when we have it )
		self.cur = assert (self.con:execute("SELECT * FROM log WHERE guid1='".. thisGuid .."' AND textxml='<name>".. thisName .."</name>' LIMIT 1"))
		self.row = self.cur:fetch ({}, "a")
		self.cur:close()
		if self.row then
			--nothing to do, player name (alias) exists
		else
			self.cur = assert (self.con:execute("INSERT INTO log (guid1, type, textxml)		\
				VALUES ('".. thisGuid .."', 3, '<name>".. thisName .."</name>')"))
		end
	end,
	
	-------------------------------------------------------------------------------
	-- creatNewPlayer
	-- Create a new Player: write to Database, set Xp 0
	-- maybe could also be used to reset Player, as pkey is unique
	-------------------------------------------------------------------------------
	['DoCreateNewPlayer'] = function( self, pkey, isBot, netname, updatedate, createdate, conname )
		self.cur = assert( self.con:execute("INSERT INTO player (pkey, isBot, netname, cleanname, updatedate, createdate, conname) VALUES ('"
			..pkey.."', "
			..isBot..", '"
			..netname.."', '"
			..et.Q_CleanStr(netname).."', "
			..updatedate .."', '"
			..createdate .."', '"
			..conname.."')"))
	end,

	-------------------------------------------------------------------------------
	-- SetPlayerSession
	-- This is the regular sessions ave of a player
	-------------------------------------------------------------------------------
	['SetPlayerSession'] = function ( self, player, map, slot)
		-- TODO: Think about using this earlier, is this the injection check ?
		--       Yes, its an escape function for ' (wich should be the only character allowed by et and with a special meaning for SQL)
		-- TODO: What about ET clients which are modified?
		
		local name = string.gsub(player["netname"],"\'", "\\\'")
		

		local sessquery = "INSERT INTO session (pkey, slot, map, ip, netname, cleanname, valid, start, end, sstime, axtime, altime, sptime, xp0, xp1, xp2, xp3, xp4, xp5, xp6, xptot, acc, kills, tkills, death) VALUES ('"
			..player["pkey"].."', '"
			..slot.."', '"
			..map.."', '"
			..player["ip"].."', '"
			..name.."', "
			..et.Q_CleanStr(name).."', "
			.."1"..", '"
			..player["start"].."','"
			..timehandle('N').. "', '"
	           -- TODO : check if this works. Is the output from 'D' option in the needed format for the database?
			..timehandle('D','N',player["start"]).."' , '"
			..player["axtime"].."', '"
			..player["altime"].."', '"
			..player["sptime"].."', '"
			..player["xp0"].."', '"
			..player["xp1"].."', '"
			..player["xp2"].."', '"
			..player["xp3"].."', '"
			..player["xp4"].."', '"
			..player["xp5"].."', '"
			..player["xp6"].."', '"
			..player["xptot"].."', '"
			.."0".."', '"
			..player["kills"].."', '"
			..player["tkills"].."', '"
			..player["death"].. "')"
			
		if self.debugquerries == 1 then	
			et.G_LogPrint( "\n\n".. sessquery .. "\n\n" ) 
		end
		self.cur = assert (self.con:execute(sessquery))
	end,

	-------------------------------------------------------------------------------
	-- SetPlayerSession_WCD
	-- This is called when a player disconnects while connecting
	-------------------------------------------------------------------------------
	['SetPlayerSessionWCD'] = function ( self, pkey, slot, map, ip, valid, start, ende, sstime, uci )
		local query = "INSERT INTO session (pkey, slot, map, ip, valid, start, end, sstime, uci) VALUES ('"
			..pkey.."', '"
			..slot.."', '"
			..map.."', '"
			..ip.."', '" 
			..valid.."', '"
			..start.."', '"
			..ende.."' , '"
        	-- TODO : check if this works. Is the output from 'D' option in the needed format for the database?
			..sstime.."' , '"
			..uci.."')"
	
		if self.debugquerries == 1 then	
			et.G_LogPrint( "\n\n".. query .. "\n\n" ) 
		end
		self.cur = assert (self.con:execute( query ))
	end,

	-------------------------------------------------------------------------------
	-- SetPlayerInfo
	-- Sets PlayerInfos
	-------------------------------------------------------------------------------
	['SetPlayerInfo'] = function (self, player)
		local name = string.gsub(player["netname"],"\'", "\\\'")
		self.cur = assert (self.con:execute("UPDATE player SET clan='".. player["clan"] .."',           \
			 netname='".. name  .."',\
			 cleanname='"..et.Q_CleanStr(name).."',\
			 xp0='".. player["xp0"]  .."', 	\
			 xp1='".. player["xp1"]  .."', 	\
			 xp2='".. player["xp2"]  .."', 	\
			 xp3='".. player["xp3"]  .."',	\
			 xp4='".. player["xp4"]  .."', 	\
			 xp5='".. player["xp5"]  .."',	\
			 xp6='".. player["xp6"]  .."',	\
			 xptot='"..player["xptot"]  .. "',\
			 level='".. player["level"] .."',				\
			 banreason='".. player["banreason"]  .."',	\
			 bannedby='".. player["bannedby"]  .."',		\
			 banexpire='".. player["banexpire"] .."',		\
			 mutedreason='".. player["mutedreason"] .."',	\
			 mutedby='".. player["mutedby"] .."',			\
			 muteexpire='".. player["muteexpire"] .."',	\
			 warnings='".. player["warnings"] .."',		\
			 suspect='".. player["suspect"] .."'			\
			 WHERE pkey='".. player["pkey"] .."'"))
	end,

	-------------------------------------------------------------------------------
	-- GetPlayerInfo
	-- Returns PlayerInfo table
	-------------------------------------------------------------------------------
	['GetPlayerInfo'] = function( self, thisGuid )
		--Search the GUID in the database ( GUID is UNIQUE, so we just have 1 result, stop searching when we have it )
		self.cur = assert (self.con:execute("SELECT * FROM player WHERE pkey='".. thisGuid .."' LIMIT 1"))
		self.row = self.cur:fetch ({}, "a")
		self.cur:close()
		return self.row
	end,
	
	['DoRegisterUser'] = function ( self, user, password, pkey )
		self.cur = assert (self.con:execute("UPDATE player SET user='"..user.."', password=MD5('"..password.."') WHERE pkey='"..pkey.."'"))
	end,
	
	-- TODO delete old session if (based on config setting), used in function et_ShutdownGame and cleanSessionCMD
	['DoDeleteOldSessions'] = function ( self, months )
		-- TODO @luborg this DATE_SUB() is mysql only
		self.cur = assert (self.con:execute("DELETE FROM session WHERE `end` < DATE_SUB(CURDATE(), INTERVAL "..months.." MONTH)"))
	end

}
return 1
