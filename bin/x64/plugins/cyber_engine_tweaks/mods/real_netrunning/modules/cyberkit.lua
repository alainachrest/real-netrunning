-- The cyberspace kit: which of the game's own assets build cyberspace, and how
-- big things are. Everything visual is in this one file so it can be tuned
-- without touching the logic in modules/cyberspace.lua.
--
-- All templates are vanilla: Mikoshi's cyberspace (q116), Alt's cyberspace
-- (q110), the Arasaka Tower point cloud (q114) and Phantom Liberty's Blackwall.

local Kit = {}

-- Where cyberspace is built: high above Night City, out of sight of the world.
Kit.origin = { x = -1085.0, y = 880.0, z = 9000.0 }

-- Each floor of a network is a square platform; floors are stacked downwards.
Kit.floorGap = 18.0      -- metres between floors
Kit.roomSize = 16.0      -- each floor is a grid of 16 x 16 m rooms
Kit.doorWidth = 4.0      -- doorways between rooms
Kit.wallHeight = 6.0
Kit.wallThickness = 0.5
Kit.defaultStyle = 2     -- floor: Mikoshi prison platform
Kit.defaultWalls = 3     -- walls: Mikoshi cyberspace wall
Kit.defaultScale = 1.3   -- the prison platform looks right a little larger
Kit.defaultLightColour = 1 -- netrunner blue
Kit.lightLevel = 1.0
-- the big scenery (point clouds, particles) stands well away from the platforms
Kit.sceneryOffset = { x = 0.0, y = 140.0, z = -40.0 }
Kit.useRadius = 2.6      -- how close V must be to use an object
Kit.fallLimit = 25.0     -- falling this far below a floor puts V back on it

-- Positions on a floor, relative to its centre.
Kit.arrival = { x = 0.0, y = -8.0 }  -- where V lands; also the way back up
Kit.descent = { x = 0.0, y = 9.5 }   -- the way down to the next floor
Kit.ringRadius = 6.5                 -- data objects stand in a ring

Kit.templates = {
	-- around the whole network
	ambienceGang   = "base\\quest\\main_quests\\part1\\q101\\entities\\q101_cyberspace_point_cloud.ent",
	ambienceCorp   = "base\\quest\\main_quests\\part1\\q114\\entities\\q114_cyberspace_point_cloud.ent",
	ambienceLocal  = "base\\quest\\main_quests\\part1\\q110\\entities\\q110_cyberspace_point_cloud_simple.ent",
	particles      = "base\\fx\\meshes\\cyberparticles\\cyberparticles.ent",
	blocks         = "base\\fx\\meshes\\cyberparticles\\mikoshi_blocks.ent",
	blackwall      = "ep1\\fx\\blackwall\\entities\\blackwall_horizon_fx.ent",

	-- floors
	floor          = "base\\worlds\\03_night_city\\sectors\\c_city_center\\corpo_plaza\\loc_q116_mikoshi_cyberspace\\mikoshi_plates.ent",
	floorCore      = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_well_floor.ent",

	-- cyberspace particles drifting through every room
	roomParticles  = "base\\fx\\meshes\\cyberparticles\\cyberparticles.ent",

	-- things on floors
	data           = "base\\fx\\meshes\\cyberparticles\\q110_platforms.ent",
	console        = "base\\fx\\meshes\\cyberparticles\\mikoshi_prison_cells.ent",
	core           = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_ribs.ent",
	descent        = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_bridge.ent",
	iceGate        = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_rainbow_rift.ent",
	blackIceGate   = "base\\fx\\meshes\\cyberparticles\\q110_blackwall.ent",
	passwordGate   = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_invisible_wall.ent",
}

-- ICE takes the form of the owner's own netrunners. Black ICE is elite.
Kit.ice = {
	gang     = "Character.nid_maelstrom_netrunner_m_medium",
	maelstrom = "Character.nid_maelstrom_netrunner_m_medium",
	tygerclaws = "Character.tygerclaw_gangster3_netrunner_nue_wa_rare",
	valentinos = "Character.generic_netrunner_netrunner_chao_wa_rare",
	sixthstreet = "Character.nid_generic_netrunner_netrunner_chao_ma_rare",
	arasaka  = "Character.dtn_arasaka_netrunner_netrunner2_yukimura_wa_rare",
	corp     = "Character.dtn_security_netrunner_netrunner2_lexington_ma_rare",
	police   = "Character.dtn_security_netrunner_netrunner2_lexington_ma_rare",
	media    = "Character.afterlife_merc_netrunner_w_easy",
	civilian = "Character.afterlife_merc_netrunner_w_easy",
	device   = "Character.afterlife_merc_netrunner_w_easy",
	black    = "Character.high_voodooboys_netrunner3_netrunner3_quasar_wa_elite",
}
Kit.netwatch = "Character.cpz_netwatch_agent_netrunner3_omaha_elite"

-- Other things that can be found in any network, even ones you own.
Kit.rivals = {
	"Character.afterlife_merc_netrunner_m_hard",
	"Character.afterlife_netrunner_netrunner2_yukimura_wa_rare",
	"Character.sts_ep1_06_enemy_netrunner_rare_suit_ma",
	"Character.generic_netrunner_netrunner_chao_ma_rare",
}
Kit.rogueAI = {
	"Character.kangtao_base_android",
	"Character.militech_base_android",
	"Character.security_android_android2_lexington_ma",
}

-- How cyberspace pushes back
Kit.encounterEvery = 30      -- seconds between rolls for a rival or rogue AI
Kit.encounterMax = 2         -- at most this many at once
Kit.patrolHop = 6            -- seconds between a patrol's moves
Kit.huntHop = 3              -- seconds between a hunter's moves
Kit.patrolSight = 2          -- rooms away (through doorways) a patrol notices V from
Kit.deepFloor = 3            -- from this floor down, unowned networks raise trace...
Kit.deepTrace = 0.08         -- ...by this much per second for each floor from there, more on bigger networks
Kit.scanTrace = 6            -- what 'cyber scan' costs (free on networks you own)
Kit.scanRange = 3            -- how many rooms (through doorways) a scan reaches

-- Everything V can use is marked so it can be seen across a room: a mesh and a
-- pool of coloured light (Cyberspace.reds, RNMarker*). Block kinds:
Kit.markers = { file = 10, paydata = 11, taken = 12, down = 13, up = 14, exit = 15, gate = 16, console = 17, core = 18 }
-- how big each one is, in metres (the ways up and down run floor to ceiling: Kit.wallHeight)
Kit.markerSize = { [10] = 1.2, [11] = 1.2, [12] = 0.9, [13] = 6.0, [14] = 6.0, [15] = 3.0, [16] = 3.6, [17] = 1.8, [18] = 4.0 }
-- cyberspace particles in every room (1), every other room (2), or none (0)
Kit.particleRooms = 1

function Kit.iceRecord(orgId, org, black)
	if black then return Kit.ice.black end
	return Kit.ice[orgId] or Kit.ice[org.kind] or Kit.ice.corp
end

function Kit.ambience(org, tier)
	if org.kind == "gang" then return Kit.templates.ambienceGang end
	if org.kind == "corp" and tier >= 2 then return Kit.templates.ambienceCorp end
	return Kit.templates.ambienceLocal
end

-- Status effects while jacked in: no guns in cyberspace, no fast travel.
Kit.restrictions = { "GameplayRestriction.NoWeapons", "GameplayRestriction.BlockFastTravel" }

return Kit
