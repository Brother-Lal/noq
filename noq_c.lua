--  
-- ET Lua SQL console - noq_c.lua (p) 2010 IRATA [*] as part of the NOQ
--

--
-- Execute SQL via the ET server console like
-- [commandprefix]sql "select * from players" 
-- 

--
-- Enables faster debugging for SQL based Lua scripts, adds some new options and is nice to have ...
--

-- Notes:
-- There are limits by the buffer of ET. 
-- Avoid very long statements and don't expect you always get the full result printed.
-- Keep it short.
-------------------------------------------------------------------------------

color = "^5"
version = 1
commandprefix = "!"
debug = 0 -- debug 0/1
tablespacer = " " -- use something like " " or "|"

fs_game 		= et.trap_Cvar_Get("fs_game")
homepath 		= et.trap_Cvar_Get("fs_homepath")
scriptpath 		= homepath .. "/" .. fs_game .. "/noq/" -- full qualified path for the NOQ scripts

-------------------------------------------------------------------------------
-- table functions - don't move down or edit!
-------------------------------------------------------------------------------

-- TODO: we use same functions in the noq.lua
-- Find a way to use more centralized

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

-- Gets varvalue else null
function getConfig( varname )
	local value = noqvartable[varname]
	
	if value then
	  	return value
	else
		et.G_Print("warning, invalid config value for " .. varname .. "\n")
	  	return "null"
	end
end

et.G_LogPrint("Loading NOQ config from ".. scriptpath.."\n")
noqvartable		= assert(table.load( scriptpath .. "noq_config.cfg"))

--------------------------------------------------------------------------------

env = nil
con = nil

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

cur = {}
res = {}
row = {}
--------------------------------------------------------------------------------

function et_InitGame( levelTime, randomSeed, restart )
	if debug == 1 then
	  et.trap_SendServerCommand( -1 ,"chat \"" .. color .. "ET Lua SQL console " .. version )
	end
	et.RegisterModname( "ET SQL console " .. version .. " " .. et.FindSelf() )
end

function et_ConsoleCommand( command )
	if debug == 1 then
	  et.trap_SendServerCommand( -1 ,"chat \"" .. color .. "ConsoleCommand - command: " .. command )
	end

	-- TODO should be used by admins only 
	if string.lower(et.trap_Argv(0)) == commandprefix.."sql" then
	
		-- TODO sanity checks - help output
		-- 2 ?
		if (et.trap_Argc() < 1) then 
			et.G_Print(color..commandprefix.."sql is used to access the db with common sql commands.\n" .. "usage: ...\n")
			return 1
		end 
		
		-- we have some cases now - get the sql command ... insert, update
		local cmd = string.lower( string.sub(et.trap_Argv(1), 0 , 6) )

		if debug == 1 then
			et.G_Print(color .. commandprefix.."sql: " .. et.trap_Argv(1) .. "\n")
		end		

		-- ok, does work
		if cmd == "select" then

			cur = assert (con:execute(et.trap_Argv(1)))
			row = cur:fetch ({}, "a")	-- the rows will be indexed by field names

			local collect = ""
			for i,v in pairs(cur:getcolnames()) do collect = collect .. v .. tablespacer end
			et.G_Print(collect .. "\n") -- fix this order is not in sync with following output

			-- add a limit to 20 rows ?
			while row do
				collect = ""
				for i,v in pairs(row) do collect = collect .. v .. tablespacer end
				-- send more rows each print ? (depends on table size)
				et.G_Print(collect .. "\n")
				row = cur:fetch (row, "a")	-- reusing the table of results
			end
			cur:close()

		elseif cmd == "insert" or "create" or "delete" then
			-- exec cmd
			res = assert (con:execute(et.trap_Argv(1)))
			et.G_Print(res .. "\n")

		elseif cmd == "vacuum" then 
			-- only sqlite	defrag the database
			if dbms == "SQLite" then
				res = assert (con:execute(et.trap_Argv(1)))
				et.G_Print(res .. "\n")
			else
				et.G_Print(color..commandprefix.."sql: Command unknown for this dbms\n")
			end
		else
			-- cmd is 5 char based ?
			cmd = string.lower( string.sub(et.trap_Argv(1), 0 , 5) )
			
			-- alter 
			if cmd == "alter" then
				res = assert (con:execute(et.trap_Argv(1)))
				et.G_Print(res .. "\n")
			else 
				-- cmd is 4 char based
				cmd = string.lower( string.sub(et.trap_Argv(1), 0 , 4) )
				
				-- drop
				if cmd == "drop" then
					-- create a row of data
					res = assert (con:execute(et.trap_Argv(1)))
					cur:close()
				-- untested (only mysql atm)	
				elseif cmd == "show" then
					cur = assert (con:execute(et.trap_Argv(1)))
					row = cur:fetch ({}, "a")	-- the rows will be indexed by field names
					local collect = ""
					for i,v in pairs(cur:getcolnames()) do collect = collect .. v .. tablespacer end
					et.G_Print(collect .. "\n")

					-- add a limit to 20 rows ?
					while row do
						collect = ""
						for i,v in pairs(row) do collect = collect .. v .. tablespacer end
						-- send more rows each print ? (depends on table size
						et.G_Print(collect .. "\n")
						row = cur:fetch (row, "a")	-- reusing the table of results
					end
					cur:close()
						
				else
					et.G_Print(color..commandprefix.."sql: Command unknown\n")
				end
			end
		end
	end
	-- add more cmds here ...
end

function shuttdownDBMS()
	if getConfig("dbms") == "mySQL" or getConfig("dbms") == "SQLite" then
		con:close()
		env:close()
	else 
		-- should never happen
		error("DBMS not supported.")
	end
end

function et_ShutdownGame( restart )
	shuttdownDBMS()
end
