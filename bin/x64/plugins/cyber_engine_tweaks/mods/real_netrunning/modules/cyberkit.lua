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

	-- played around V for a few seconds on jacking in and out (nil: none yet;
	-- Transmission's "leaving cyberspace" entity showed nothing on its own)
	transition     = nil,


	-- things on floors
	data           = "base\\fx\\meshes\\cyberparticles\\q110_platforms.ent",
	console        = "base\\fx\\meshes\\cyberparticles\\mikoshi_prison_cells.ent",
	core           = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_ribs.ent",
	descent        = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_bridge.ent",
	iceGate        = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_rainbow_rift.ent",
	blackIceGate   = "base\\fx\\meshes\\cyberparticles\\q110_blackwall.ent",
	passwordGate   = "base\\quest\\main_quests\\part1\\q116\\entities\\q116_cyberspace_invisible_wall.ent",
}

-- Everything in cyberspace fights the way V has to there: bare hands (fists or
-- Gorilla Arms). Netrunner characters come with guns they keep drawing, and
-- with their guns taken away they don't fight at all, so cyberspace's fighters
-- are the game's own brawlers, chosen to suit each network's owner. Black ICE
-- and NetWatch are elite Gorilla Arms and martial artists.
Kit.ice = {
	gang        = "Character.animals_grunt2_hmelee2_fists_wba_rare",
	maelstrom   = "Character.nid_scavenger_grunt1_melee1_fists_ma",
	tygerclaws  = "Character.jpn_tyger_claws_gangster1_melee1_fists_ma",
	valentinos  = "Character.gle_valentinos_grunt4_hmelee2_fists_mb_rare",
	sixthstreet = "Character.animals_bouncer2_melee2_fists_mb",
	arasaka     = "Character.arasaka_rare2_hmelee3_fists_mm_elite",
	militech    = "Character.militech_strongarms_hmelee3_fists_mb_elite",
	corp        = "Character.arasaka_bodyguard_hmelee2_fists_mb_rare",
	police      = "Character.dtn_security_security1_hmelee2_fists_mb_rare",
	media       = "Character.hil_security_security1_hmelee2_fists_mb_rare",
	civilian    = "Character.cpz_animals_bouncer2_melee2_fists_mb",
	device      = "Character.hil_security_security1_hmelee2_fists_mb_rare",
	black       = "Character.militech_strongarms_hmelee3_fists_mb_elite",
}
Kit.netwatch = "Character.prevention_dogtown_martial_hmelee3_fists_mb_elite"

-- Other things that can be found in any network, even ones you own.
-- (ordinary open-world characters only: quest characters can be unkillable)
Kit.rivals = {
	"Character.jpn_tyger_claws_kunoichi_fmelee3_fists_ma_elite",
	"Character.animals_elite3_hmelee3_fists_mba_elite",
	"Character.animals_elite2_hmelee2_fists_mba_rare",
	"Character.jpn_tyger_claws_martial_hmelee3_StrongArms_mb",
}
-- a rogue AI wearing the body it found: a boxing robot
Kit.rogueAI = {
	"Character.boxingrobot_hard",
}

-- The quickhacks cyberspace's fighters upload into V while they're close (in
-- V's room or the next one through a doorway). Each shows an upload warning
-- first; take the hacker down before it finishes and nothing happens.
--   damage: percent of V's max health   trace: added to V's trace
--   effect: a status effect put on V for its look (if the game has it)
Kit.enemyHacks = {
	{ name = "Overheat",          upload = 3.0, damage = 6,  burn = 3, effect = "BaseStatusEffect.Burning" },
	{ name = "Short Circuit",     upload = 2.0, damage = 10, effect = "BaseStatusEffect.Electrocuted" },
	{ name = "Trace Ping",        upload = 2.0, trace = 10 },
	{ name = "Synapse Burnout",   upload = 4.0, damage = 18, elite = true },
}
Kit.hackEvery = { 9, 15 }    -- seconds between a fighter's hacks (elites a third faster)
Kit.hackRange = 1            -- rooms away a fighter can hack V from

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
Kit.markerSize = { [10] = 1.8, [11] = 1.8, [12] = 1.4, [13] = 6.0, [14] = 6.0, [15] = 3.0, [16] = 3.6, [17] = 1.8, [18] = 4.0 }
-- cyberspace particles in every room (1), every other room (2), or none (0)
Kit.particleRooms = 1
-- the particle system drifting through each room (a .particle; the first that loads is used)
Kit.roomParticles = "base\\fx\\quest\\q116\\q116_04_mikoshi_intro\\q116_alt_background.particle"
Kit.particleKind = 5

function Kit.iceRecord(orgId, org, black)
	if black then return Kit.ice.black end
	return Kit.ice[orgId] or Kit.ice[org.kind] or Kit.ice.corp
end

function Kit.ambience(org, tier)
	if org.kind == "gang" then return Kit.templates.ambienceGang end
	if org.kind == "corp" and tier >= 2 then return Kit.templates.ambienceCorp end
	return Kit.templates.ambienceLocal
end

-- HUD parts hidden while jacked in (the game's Settings > Interface > HUD
-- options; each one is put back as it was on jack-out).
Kit.hideHud = { "minimap", "quest_tracker", "input_hints", "activity_log" }

-- Status effects while jacked in: no fast travel.
Kit.restrictions = { "GameplayRestriction.BlockFastTravel" }
-- No guns or blades in cyberspace: quickhacks and bare hands only. Weapons of
-- any other type are swapped for fists as soon as they're drawn, by applying
-- the boxing-match restriction (it makes V put weapons away and raise their
-- fists) until the weapon is gone. Blocking weapons alone doesn't holster one
-- that's already drawn.
Kit.allowedWeapons = { "Wea_Fists", "Cyb_StrongArms" }  -- gamedataItemType names
Kit.holsterEffect = "GameplayRestriction.FistFight"
Kit.holsterTime = 2.0   -- seconds to keep it on after the weapon is gone

return Kit
