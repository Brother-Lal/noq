-- The NOQ - No Quarter Lua next generation game manager
--
-- A Shrubbot replacement and also kind of new game manager and tracking system based on mysql or sqlite3. 
-- Both are supported and in case of sqlite there is no extra sqlite installation needed. Use with NQ 1.2.9 and later only!
--
-- NQ Lua team 2009-2011 - No warranty :)
--
--
-- This is the Noquarter -- Etpro compatibility script
-- it will allow NOQ to run on ETPro, without loosing to much functionallity.
--	What wont work:
--	-Database, everything that needs external libs
-- What might work: commands, but without adminlevels 
--	-Todo: some way to get the adminlevels from a file or similar, perhaps parse shrubbot.cfg


function et.G_shrubbot_permission( _clientNum, flag ) 
	if string.fing(slot[_clientNum]["flags"], flag) ~= nil then
		return true
	else
		return false
	end
end

function et.G_shrubbot_level( _clientNum )
	return slot[_clientNum]["level"]
end

function et.G_XP_Set ( clientNum , xp, skill, add )
-- Todo check if sess.skillpoints will work.
end

function et.ClientNumberFromString (_name)
	found = false

	for i=0, et.trap_Cvar_Get( "sv_maxclients" ) -1, 1 do					
		if slot[i][inuse] then
			if string.find(slot[i]["cleanname"],_name) or string.find(slot[i]["netname"],_name) then
				if found then
					return nil
				end
			found = i
			
			end
			
		end
	end
	
	if found then
		return found 
	else
		return nil
	end	
	
end
