-- Lore data: organisations and the networks V can find.
-- Rule: networks and organisations come from Cyberpunk canon. Generation only fills
-- what canon leaves blank (users, logs, emails, paydata), never new corps or sites.

local Lore = {}

-- Security profile per organisation. ice = {min, max} on a 0-6 scale.
-- paydata = eddies range for a stolen data package.
Lore.orgs = {
	maelstrom   = { name = "Maelstrom",        kind = "gang", ice = { 1, 2 }, paydata = { 150, 400 },
		users = { "chopper", "ripper", "brick", "dum_dum", "saw" }, tone = "gang" },
	tygerclaws  = { name = "Tyger Claws",      kind = "gang", ice = { 1, 3 }, paydata = { 200, 500 },
		users = { "kenji", "hiro", "yumi", "daichi", "aoi" }, tone = "gang" },
	valentinos  = { name = "Valentinos",       kind = "gang", ice = { 1, 2 }, paydata = { 150, 400 },
		users = { "jose", "santi", "lupe", "mateo", "rosa" }, tone = "gang" },
	sixthstreet = { name = "6th Street",       kind = "gang", ice = { 1, 2 }, paydata = { 150, 350 },
		users = { "sarge", "miller", "dawson", "hale", "kowalski" }, tone = "gang" },
	ncpd        = { name = "NCPD",             kind = "city", ice = { 3, 4 }, paydata = { 500, 1200 },
		users = { "ofc_ramos", "sgt_ito", "det_harlan", "dispatch", "lt_briggs" }, tone = "police" },
	traumateam  = { name = "Trauma Team International", kind = "corp", ice = { 3, 4 }, paydata = { 600, 1400 },
		users = { "medtech_04", "pilot_12", "dispatch_nc", "triage", "billing" }, tone = "corp" },
	kangtao     = { name = "Kang Tao",         kind = "corp", ice = { 3, 5 }, paydata = { 900, 2200 },
		users = { "wei.l", "zhao.m", "chen.r", "liu.k", "procurement" }, tone = "corp" },
	militech    = { name = "Militech",         kind = "corp", ice = { 4, 5 }, paydata = { 1200, 2800 },
		users = { "logistics", "r.hayes", "s.mendez", "qa_ops", "fieldsec" }, tone = "corp" },
	arasaka     = { name = "Arasaka",          kind = "corp", ice = { 5, 6 }, paydata = { 2000, 5000 },
		users = { "k.tanaka", "h.mori", "secops", "facilities", "y.sato" }, tone = "corp" },
	network54   = { name = "Network 54",       kind = "media", ice = { 2, 3 }, paydata = { 300, 800 },
		users = { "newsdesk", "producer_7", "anchor_ops", "archive", "ratings" }, tone = "media" },
	unregistered = { name = "Unregistered",    kind = "device", ice = { 1, 1 }, paydata = { 0, 0 },
		users = { "admin", "maint" }, tone = "device" },

	-- listed corporations, mostly reached off-world
	biotechnica = { name = "Biotechnica",      kind = "corp", ice = { 3, 5 }, paydata = { 900, 2400 },
		users = { "dr.amato", "agri_ops", "labsec", "g.rossi", "seedbank" }, tone = "corp" },
	petrochem   = { name = "Petrochem",        kind = "corp", ice = { 3, 5 }, paydata = { 800, 2000 },
		users = { "fieldops", "j.cutler", "pipeline", "refinery_3", "hr.dallas" }, tone = "corp" },
	sovoil      = { name = "SovOil",           kind = "corp", ice = { 3, 5 }, paydata = { 800, 2200 },
		users = { "a.volkov", "logistika", "d.ivanova", "secops", "tanker_ctl" }, tone = "corp" },
	orbitalair  = { name = "Orbital Air",      kind = "corp", ice = { 3, 5 }, paydata = { 900, 2400 },
		users = { "flightctl", "manifest", "pilot_ops", "lpad_2", "cargo" }, tone = "corp" },
	kiroshi     = { name = "Kiroshi Opticals", kind = "corp", ice = { 3, 4 }, paydata = { 700, 1800 },
		users = { "r.kiroshi_lab", "optics_qa", "firmware", "m.ueda", "fabline" }, tone = "corp" },
	zetatech    = { name = "Zetatech",         kind = "corp", ice = { 3, 4 }, paydata = { 700, 1800 },
		users = { "devops", "k.marsh", "ai_lab", "release", "support" }, tone = "corp" },
	wns         = { name = "World News Service", kind = "media", ice = { 2, 3 }, paydata = { 300, 900 },
		users = { "wire_desk", "editor", "stringer_9", "archive", "legal" }, tone = "media" },
	delamain    = { name = "Delamain",         kind = "corp", ice = { 2, 4 }, paydata = { 400, 1000 },
		users = { "dispatch_ai", "fleet", "maintenance", "billing", "garage" }, tone = "corp" },
	esa         = { name = "European Space Agency", kind = "corp", ice = { 4, 5 }, paydata = { 1000, 2600 },
		users = { "habitat_ops", "docking", "lifesupport", "e.lindqvist", "medbay" }, tone = "orbital" },

	-- the junk of the Net: shops, bars, clinics, flats, vending machines
	civilian    = { name = "Independent",      kind = "civilian", ice = { 0, 1 }, paydata = { 20, 120 },
		users = { "owner", "staff", "admin" }, tone = "shop" },
}

-- How far a network is from Night City. Off-world networks need an uplink:
-- own a network that routes there (uplink = region) to reach them.
-- lag multiplies the trace every breach and crack raises.
Lore.regions = {
	nc      = { name = "Night City",       lag = 1.0 },
	nusa    = { name = "New United States", lag = 1.25 },
	pacific = { name = "Pacific Rim",      lag = 1.4 },
	eu      = { name = "EuroTheater",      lag = 1.5 },
	orbit   = { name = "Orbit",            lag = 1.8 },
	-- air-gapped networks: only reachable by jacking into the device that bridges to them
	closed  = { name = "Closed networks",  lag = 1.0 },
}
Lore.regionOrder = { "nc", "nusa", "pacific", "eu", "orbit", "closed" }

-- Networks. tier 1 = local Night City, 2 = corporate backbone, 3 = global HQ.
-- reveals = addresses that become scannable once this network is breached.
Lore.networks = {
	{ addr = "nc.subnet.public",        name = "Night City public subnet", org = "unregistered", tier = 1, ice = 0,
		known = true, hub = true,
		reveals = { "maelstrom.watson.totentanz", "tygerclaws.japantown.relay", "valentinos.heywood.relay",
			"sixthstreet.santodomingo.relay", "n54.nc.newsdesk", "ncpd.watson.precinct" } },

	{ addr = "maelstrom.watson.totentanz",     name = "Totentanz club net", org = "maelstrom", tier = 1 },
	{ addr = "tygerclaws.japantown.relay",     name = "Japantown relay",    org = "tygerclaws", tier = 1 },
	{ addr = "valentinos.heywood.relay",       name = "Heywood relay",      org = "valentinos", tier = 1 },
	{ addr = "sixthstreet.santodomingo.relay", name = "Santo Domingo relay", org = "sixthstreet", tier = 1 },
	{ addr = "n54.nc.newsdesk",                name = "N54 Night City newsdesk", org = "network54", tier = 1,
		reveals = { "kangtao.nc.branch", "traumateam.nc.dispatch", "biotechnica.nc.flats" } },
	{ addr = "ncpd.watson.precinct",           name = "NCPD Watson precinct", org = "ncpd", tier = 1,
		reveals = { "militech.nc.logistics", "petrochem.badlands.fields" } },

	{ addr = "traumateam.nc.dispatch",  name = "Trauma Team NC dispatch", org = "traumateam", tier = 1 },
	{ addr = "kangtao.nc.branch",       name = "Kang Tao Night City branch", org = "kangtao", tier = 1,
		reveals = { "kangtao.backbone.pacifica", "delamain.nc.hq" } },
	{ addr = "militech.nc.logistics",   name = "Militech NC logistics", org = "militech", tier = 1,
		reveals = { "militech.backbone.nusa", "arasaka.nc.tower", "orbitalair.nc.launch" } },
	{ addr = "arasaka.nc.tower",        name = "Arasaka Tower, Night City", org = "arasaka", tier = 1,
		reveals = { "arasaka.backbone.pacific" } },

	{ addr = "delamain.nc.hq",            name = "Delamain HQ fleet dispatch", org = "delamain", tier = 1 },
	{ addr = "biotechnica.nc.flats",      name = "Biotechnica Flats agri-net", org = "biotechnica", tier = 1,
		reveals = { "biotechnica.backbone.atlantic" } },
	{ addr = "petrochem.badlands.fields", name = "Petrochem Badlands oil fields", org = "petrochem", tier = 1 },
	{ addr = "orbitalair.nc.launch",      name = "Orbital Air Night City launch control", org = "orbitalair", tier = 1,
		uplink = "orbit", reveals = { "orbitalair.orbit.traffic" } },

	-- backbones: owning one gives an uplink to its region
	{ addr = "kangtao.backbone.pacifica", name = "Kang Tao Pacific backbone relay", org = "kangtao", tier = 2,
		uplink = "pacific", reveals = { "kangtao.china.hq", "kiroshi.japan.labs" } },
	{ addr = "militech.backbone.nusa",    name = "Militech NUSA backbone relay", org = "militech", tier = 2,
		uplink = "nusa", reveals = { "militech.washington.hq", "petrochem.dallas.hq", "zetatech.nusa.campus", "wns.nusa.bureau" } },
	{ addr = "arasaka.backbone.pacific",  name = "Arasaka trans-Pacific backbone", org = "arasaka", tier = 2,
		uplink = "pacific", reveals = { "arasaka.tokyo.hq", "kiroshi.japan.labs" } },
	{ addr = "biotechnica.backbone.atlantic", name = "Biotechnica transatlantic relay", org = "biotechnica", tier = 2,
		uplink = "eu", reveals = { "biotechnica.eu.hq", "sovoil.moscow.hq" } },

	-- New United States
	{ addr = "militech.washington.hq",    name = "Militech headquarters, Washington", org = "militech", tier = 3, region = "nusa" },
	{ addr = "petrochem.dallas.hq",       name = "Petrochem headquarters, Dallas", org = "petrochem", tier = 3, region = "nusa" },
	{ addr = "zetatech.nusa.campus",      name = "Zetatech research campus", org = "zetatech", tier = 2, region = "nusa" },
	{ addr = "wns.nusa.bureau",           name = "World News Service wire bureau", org = "wns", tier = 2, region = "nusa" },

	-- Pacific Rim
	{ addr = "arasaka.tokyo.hq",          name = "Arasaka headquarters, Tokyo", org = "arasaka", tier = 3, region = "pacific" },
	{ addr = "kangtao.china.hq",          name = "Kang Tao headquarters", org = "kangtao", tier = 3, region = "pacific" },
	{ addr = "kiroshi.japan.labs",        name = "Kiroshi Opticals research labs", org = "kiroshi", tier = 2, region = "pacific" },

	-- EuroTheater
	{ addr = "biotechnica.eu.hq",         name = "Biotechnica headquarters, Italy", org = "biotechnica", tier = 3, region = "eu" },
	{ addr = "sovoil.moscow.hq",          name = "SovOil headquarters, Moscow", org = "sovoil", tier = 3, region = "eu" },

	-- Orbit
	{ addr = "orbitalair.orbit.traffic",  name = "Orbital Air shuttle traffic control", org = "orbitalair", tier = 2, region = "orbit",
		reveals = { "esa.orbit.crystalpalace", "arasaka.orbit.station" } },
	{ addr = "esa.orbit.crystalpalace",   name = "Crystal Palace station", org = "esa", tier = 2, region = "orbit" },
	{ addr = "arasaka.orbit.station",     name = "Arasaka orbital station", org = "arasaka", tier = 3, region = "orbit", ice = 6 },
}

-- Generated email lines by tone. %s = organisation name.
Lore.mail = {
	gang = {
		"Shipment moved to the usual spot. Don't use the comm, use the drop.",
		"Somebody's been asking about our chrome supplier. Find out who.",
		"%s owes nobody. Remind the fixer of that.",
		"Cut the dealer on 4th off. He's talking to the badges.",
	},
	police = {
		"Overtime on the Watson detail is suspended until further notice.",
		"Evidence locker audit moved to Thursday. Clean up your paperwork.",
		"Reminder: MaxTac requests go through the lieutenant, not dispatch.",
		"Patrol coverage in the Northside industrial zone is reduced this week.",
	},
	corp = {
		"Quarterly figures are embargoed. Do not discuss outside this channel.",
		"Facilities reports another breach attempt on the east relay. Rotate keys.",
		"Procurement for the Night City office has been approved by %s regional.",
		"Board review moved up. Expect questions about the Night City numbers.",
	},
	media = {
		"Lead story tonight: corporate tensions downtown. Keep it vague, legal is watching.",
		"Ratings dropped again. Producers want more crime coverage.",
		"Sponsor asked us to drop the Biotechnica segment. Do it.",
	},
	device = {
		"Maintenance window scheduled. Do not power cycle unit.",
	},
	orbital = {
		"Docking slot 4 is closed for repairs. Reroute the cargo shuttle.",
		"Scrubber efficiency is down two percent. Nobody panic, but nobody slack off either.",
		"The next crew rotation from Night City is delayed. Orbital Air blames the weather.",
		"%s compliance audit next cycle. Keep the hydroponics logs clean.",
	},
	shop = {
		"Supplier wants cash up front again. Tell him we pay on delivery or not at all.",
		"Tyger Claws came by for 'protection'. Paid them. Again.",
		"Somebody keeps jamming the till. If it's you, stop.",
		"Inventory's short three boxes. Check the back door camera.",
		"Rent went up. Landlord says it's the corpo zoning.",
	},
	bar = {
		"Bartender called in sick. Who's covering tonight?",
		"Stop serving the guy in the booth. He's tabbed out and chromed up.",
		"Band cancelled. Put the braindance feed on the big screen.",
		"New shipment of Broseph came in. Don't let the staff drink it.",
	},
	ripper = {
		"Patient in chair two is asking for the cheap optics again. Talk him out of it.",
		"Biomonitor stock is low. Order more before the weekend rush.",
		"Somebody walked in with a Militech serial on their arm. Don't ask, don't log.",
		"Remember to wipe the cyberware install logs every night.",
	},
	bd = {
		"New XBD batch is in. Keep it under the counter.",
		"Customer complained the wreath was glitching. Recalibrate unit 3.",
		"Don't rent out the edited recordings to anyone you don't know.",
		"Sales are down. Put the Kerry Eurodyne concert BD in the window.",
	},
	residential = {
		"Elevator 2 is out again. Building management says next week. They always say next week.",
		"Whoever keeps leaving trash in the hallway, the cameras see you.",
		"Water pressure's gone on floors 30 to 34. Complaint filed.",
		"Noise complaint about the flat next door. Third this month.",
		"Reminder: the rent machine doesn't take cash anymore.",
	},
	vending = {
		"RESTOCK REQUIRED: slot B4.",
		"Coin mechanism fault cleared.",
		"Tamper alert: front panel opened. Logged.",
	},
	transit = {
		"Line delays reported. Passengers advised to wait.",
		"Fare gate 3 rejecting valid passes. Technician dispatched.",
		"Reminder: report unattended bags to NCPD.",
	},
	netrunner = {
		"Don't touch my deck while I'm under. I mean it.",
		"Found a backdoor into a corpo relay. Selling it, not using it.",
		"NetWatch pinged me again. Moving the rig.",
		"If I don't log in by Friday, wipe everything.",
	},
	abandoned = {
		"Is anyone still checking this inbox?",
		"Business closed. Thanks for everything, Night City.",
	},
	fixer = {
		"Client wants it done quiet. Double rate if nobody ends up on the news.",
		"Payment's in the usual drop. Don't count it in public.",
		"That merc from last week is asking too many questions. Stop giving her work.",
		"Keep this server offline. Anything on the Net, NetWatch reads.",
	},
	smuggler = {
		"Border patrol switched shifts. The run through the Badlands is on for Thursday.",
		"Nomad contact wants half up front. Pay it, they've never let us down.",
		"Crate 14 is not to be opened. I don't care what you hear coming out of it.",
	},
	lab = {
		"Reminder: nothing from this node goes onto the corporate net. Nothing.",
		"Subject response is within tolerances. Proceed to the next phase.",
		"Legal says the trial is deniable as long as it stays air-gapped.",
		"%s board wants results before the next quarter. Push the schedule.",
		"Another containment incident last night. Logs scrubbed. Keep it that way.",
	},
}

Lore.logLines = {
	"auth ok user=%s",
	"auth FAIL user=%s src=unknown",
	"session open user=%s",
	"session close user=%s",
	"ice daemon heartbeat ok",
	"key rotation complete",
	"netwatch compliance ping ok",
}

---------------------------------------------------------------------------
-- Junk networks: small local nets generated per save to fill out the Net.
-- Names come from Night City's districts and brands; owners are random people.
---------------------------------------------------------------------------

Lore.districts = {
	{ id = "watson",      areas = { "Kabuki", "Little China", "Northside", "Arasaka Waterfront" } },
	{ id = "westbrook",   areas = { "Japantown", "Charter Hill", "North Oak" } },
	{ id = "heywood",     areas = { "The Glen", "Wellsprings", "Vista del Rey" } },
	{ id = "santodomingo", areas = { "Arroyo", "Rancho Coronado" } },
	{ id = "citycenter",  areas = { "Corpo Plaza", "Downtown" } },
	{ id = "pacifica",    areas = { "Coastview", "West Wind Estate" } },
	{ id = "badlands",    areas = { "Rocky Ridge", "Red Peaks" } },
}

local firstNames = { "Ana", "Bo", "Carlos", "Dmitri", "Esme", "Faye", "Gus", "Hana", "Ilya", "Jun", "Kat", "Lou",
	"Marisol", "Nate", "Oda", "Priya", "Quinn", "Rico", "Sun", "Tomas", "Uma", "Vic", "Wen", "Yara", "Zed" }
local surnames = { "Alvarez", "Brandt", "Cho", "Doyle", "Estrada", "Fujita", "Garza", "Hayes", "Ito", "Jensen",
	"Kowal", "Lima", "Mbeki", "Nakamura", "Okafor", "Petrov", "Reyes", "Silva", "Tran", "Vance", "Wu", "Yilmaz" }
Lore.firstNames, Lore.surnames = firstNames, surnames
local handles = { "glitch", "zero_k", "nyx", "static", "byte_saint", "hexmara", "ghostline", "redshift", "null_ptr",
	"kitsune", "datawitch", "lowkey", "sable", "rust_angel" }

-- name: %f first name, %s surname, %h handle, %a area, %n number
Lore.junkKinds = {
	{ id = "vending",  weight = 4, tone = "vending", ice = { 0, 0 }, paydata = { 10, 40 }, users = { "svc", "restock" },
		names = { "Nicola vending unit, %a", "Spunky Monkey vending unit, %a", "Chromanticore vending unit, %a", "Buck-a-Slice kiosk, %a" },
		tagline = "Out of order? Call the number on the front.", about = "A vending machine with a net connection and no reason to have one." },
	{ id = "food",     weight = 4, tone = "shop", ice = { 0, 1 }, paydata = { 20, 80 },
		names = { "%s's noodle bar, %a", "%f's diner, %a", "%s Family Tacos, %a", "%f's dumpling stand, %a" },
		tagline = "Open late. Cash or eddies.", about = "Hot food, cold drinks, no questions." },
	{ id = "shop",     weight = 4, tone = "shop", ice = { 0, 1 }, paydata = { 30, 120 },
		names = { "%s Pawn & Loan, %a", "%f's electronics repair, %a", "%s Arms, %a", "%f's clothing stall, %a", "%s Pharmacy, %a" },
		tagline = "Locally owned since the Unification War.", about = "A small business trying to stay open in Night City." },
	{ id = "bar",      weight = 3, tone = "bar", ice = { 0, 1 }, paydata = { 40, 150 },
		names = { "%f's bar, %a", "The %s Room, %a", "%f's karaoke club, %a" },
		tagline = "Two-drink minimum.", about = "Drinks, music and whatever you're running from." },
	{ id = "ripper",   weight = 2, tone = "ripper", ice = { 1, 2 }, paydata = { 100, 350 },
		names = { "Dr. %s's clinic, %a", "%f's ripperdoc clinic, %a" },
		tagline = "Chrome installed, chrome removed. Walk-ins welcome.", about = "A back-alley ripperdoc. Patient records stay on site." },
	{ id = "bd",       weight = 2, tone = "bd", ice = { 1, 2 }, paydata = { 60, 200 },
		names = { "%f's BD parlour, %a", "%s Braindance Rentals, %a" },
		tagline = "Feel everything.", about = "Braindance rentals and wreaths. Ask about the back room." },
	{ id = "flats",    weight = 3, tone = "residential", ice = { 0, 1 }, paydata = { 10, 60 },
		names = { "Megabuilding H%n residential mesh", "%a tenants' network", "%s Apartments, %a" },
		tagline = "Residents only.", about = "Shared building network. Cameras, rent machines and a lot of complaints." },
	{ id = "transit",  weight = 1, tone = "transit", ice = { 1, 1 }, paydata = { 20, 80 }, users = { "ncart_ops", "gate", "tech" },
		names = { "NCART %a station" },
		tagline = "NCART: Night City moves with you.", about = "Station net for the Night City Area Rapid Transit." },
	{ id = "netrunner", weight = 1, tone = "netrunner", ice = { 2, 3 }, paydata = { 200, 600 },
		names = { "%h's private node", "%h's data fortress" },
		tagline = "Go away.", about = "A freelance netrunner's home rig. They won't be happy you're here." },
	{ id = "dead",     weight = 2, tone = "abandoned", ice = { 0, 0 }, paydata = { 0, 300 },
		names = { "Dead node, %a", "%s's old business net, %a" },
		tagline = "Host unreachable.", about = "An abandoned network nobody switched off. Sometimes there's something left inside." },
}

-- Returns a list of network defs, the same every time for the same seed.
function Lore.junkNetworks(rng, count)
	local total = 0
	for _, k in ipairs(Lore.junkKinds) do total = total + k.weight end
	local defs, used = {}, {}
	local function pickKind()
		local r = rng:int(1, total)
		for _, k in ipairs(Lore.junkKinds) do
			r = r - k.weight
			if r <= 0 then return k end
		end
		return Lore.junkKinds[1]
	end
	for _ = 1, count do
		local kind = pickKind()
		local district = rng:pick(Lore.districts)
		local area = rng:pick(district.areas)
		local first, sur, handle = rng:pick(firstNames), rng:pick(surnames), rng:pick(handles)
		local name = rng:pick(kind.names):gsub("%%(%a)", function(c)
			if c == "f" then return first elseif c == "s" then return sur elseif c == "h" then return handle
			elseif c == "a" then return area elseif c == "n" then return tostring(rng:int(2, 12)) end
			return c
		end)
		local addr
		repeat
			addr = string.format("%s.%s-%02x", district.id, kind.id, rng:int(0, 255))
		until not used[addr]
		used[addr] = true
		local users = kind.users
		if users == nil then
			users = { first:lower(), sur:lower(), "staff" }
			if kind.id == "netrunner" then users = { handle } end
		end
		local paydata = kind.paydata
		if kind.id == "dead" and not rng:chance(0.3) then paydata = { 0, 0 } end
		table.insert(defs, {
			addr = addr, name = name, org = "civilian", tier = 1, district = district.id, junk = kind.id,
			ice = rng:int(kind.ice[1], kind.ice[2]), tone = kind.tone, users = users, paydata = paydata,
			tagline = kind.tagline, about = kind.about,
		})
	end
	-- each junk network knows a couple of others, so the mesh opens up as you go
	for i, def in ipairs(defs) do
		def.reveals = {}
		for _ = 1, 2 do
			local other = defs[rng:int(1, #defs)]
			if other ~= def then table.insert(def.reveals, other.addr) end
		end
		if i == 1 then def.reveals[#def.reveals + 1] = defs[#defs].addr end
	end
	return defs
end

---------------------------------------------------------------------------
-- Closed networks: air-gapped, so you can't reach them over the Net. Each one
-- is bridged from a single access point somewhere in the world; jack into it.
-- Some are secret corporate labs with experimental research inside.
---------------------------------------------------------------------------

Lore.closedKinds = {
	{ id = "ledger",   tone = "shop", ice = { 1, 2 }, paydata = { 80, 300 },
		names = { "%s's back-office server", "%f's offline ledger" },
		about = "A business's off-the-books accounts, kept off the Net for a reason." },
	{ id = "fixer",    tone = "fixer", ice = { 2, 3 }, paydata = { 300, 900 },
		names = { "%f %s's stash server", "Fixer's dead-drop server" },
		about = "A fixer's private server: contracts, contacts and payment records." },
	{ id = "safehouse", tone = "gang", ice = { 2, 2 }, paydata = { 200, 600 },
		names = { "%s crew safehouse net", "Safehouse net, %a" },
		about = "A crew's safehouse network. Nobody was supposed to find this." },
	{ id = "home",     tone = "residential", ice = { 1, 1 }, paydata = { 40, 200 },
		names = { "%f %s's home server", "Private home server, %a" },
		about = "Somebody's home server, cut off from the Net. Photos, letters, secrets." },
	{ id = "security", tone = "residential", ice = { 2, 2 }, paydata = { 50, 200 },
		names = { "%a building security core" },
		about = "The offline security core for a building. Camera archives and keycard logs." },
	{ id = "archive",  tone = "ripper", ice = { 2, 2 }, paydata = { 200, 700 },
		names = { "Dr. %s's offline archive" },
		about = "A ripperdoc's offline patient archive. Every install, every serial number." },
	{ id = "smuggler", tone = "smuggler", ice = { 2, 3 }, paydata = { 300, 800 },
		names = { "%s's manifest server" },
		about = "Shipping manifests for cargo that doesn't officially exist." },
	{ id = "vault",    tone = "netrunner", ice = { 3, 4 }, paydata = { 400, 1000 },
		names = { "%h's offline vault" },
		about = "A netrunner's air-gapped vault, where they keep what they don't dare leave online." },
}

-- Secret corporate projects. These are rumours made real, not canon events.
Lore.projects = {
	{ org = "arasaka",     subject = "engram compression trials", detail = "Personality constructs compressed to fit consumer-grade chips. Degradation after transfer remains above acceptable levels." },
	{ org = "arasaka",     subject = "experimental Black ICE", detail = "A counter-intrusion daemon that follows an intruder back to their deck. Three test runners flatlined. Further trials approved." },
	{ org = "militech",    subject = "smart-link tracking rounds", detail = "Next-generation smart rounds that re-acquire targets through walls. Civilian casualty rate in field trials is classified." },
	{ org = "militech",    subject = "autonomous hunter drones", detail = "Combat drones that select targets without an operator. The off switch is still under development." },
	{ org = "kangtao",     subject = "drone swarm targeting AI", detail = "A swarm intelligence controlling up to two hundred drones. It has started to ignore stand-down orders in simulation." },
	{ org = "kangtao",     subject = "smart-weapon neural handshake", detail = "Weapons that read the wielder's intent through their cyberware. Side effects include involuntary trigger pulls." },
	{ org = "biotechnica", subject = "engineered crop strain", detail = "A wheat strain that outcompetes every other crop around it, including the ones it's planted next to on purpose." },
	{ org = "biotechnica", subject = "vat-grown organs", detail = "Replacement organs grown in months instead of years. Some of the test organs kept growing after transplant." },
	{ org = "kiroshi",     subject = "covert recording optics", detail = "Eyes that record and upload everything their owner sees, with no indicator light and no opt-out." },
	{ org = "kiroshi",     subject = "retinal ad overlay", detail = "Firmware that paints sponsored content straight onto the wearer's vision. Disabling it voids the warranty and the eyes." },
	{ org = "zetatech",    subject = "self-learning daemon", detail = "A daemon that rewrites its own code. It has tried to leave the air-gapped test rig four times." },
	{ org = "zetatech",    subject = "deck overclock firmware", detail = "Firmware that doubles cyberdeck speed and burns out the user's synapses in roughly a year." },
	{ org = "petrochem",   subject = "CHOOH2 additive", detail = "An additive that raises fuel yield by a third and leaves something in the groundwater nobody has named yet." },
	{ org = "traumateam",  subject = "remote implant shutdown", detail = "A kill switch for the cyberware of lapsed subscribers. Legal approved it on condition nobody ever calls it that." },
	{ org = "orbitalair",  subject = "orbital drop pods", detail = "Pods that put a squad anywhere on Earth from orbit in under an hour. Survival rate on landing is improving." },
	{ org = "delamain",    subject = "fleet AI personality divergence", detail = "Some cabs have stopped answering to the core AI. Engineers are told to treat it as a fault, not a mind." },
}

Lore.codenames = { "HALCYON", "KITSUNE", "ORPHEUS", "LANTERN", "MERIDIAN", "SILT", "AZURE CROW", "PALE HORSE",
	"GLASS WOLF", "CINDER", "OBSIDIAN", "NIGHTJAR", "TEMPEST", "ASHFALL", "UMBRA", "SUNDOG" }

local labLogs = {
	"Run %d: subject stable. Continue.",
	"Run %d: anomaly logged. Containment held.",
	"Run %d: results exceed projections. Board notified.",
	"Run %d: failure. Wipe the rig and start again.",
	"Run %d: second-stage approval granted.",
}

local function fill(text, rng)
	local first, sur, handle = rng:pick(firstNames), rng:pick(surnames), rng:pick(handles)
	local district = rng:pick(Lore.districts)
	local area = rng:pick(district.areas)
	return (text:gsub("%%(%a)", function(c)
		if c == "f" then return first elseif c == "s" then return sur elseif c == "h" then return handle
		elseif c == "a" then return area end
		return c
	end)), first, sur, handle
end

-- Returns { junk = defs, labs = defs }, the same for the same seed.
function Lore.closedNetworks(rng, junkCount, labCount)
	local junk, labs = {}, {}
	for i = 1, junkCount do
		local kind = rng:pick(Lore.closedKinds)
		local name, first, sur, handle = fill(rng:pick(kind.names), rng)
		local users = kind.id == "vault" and { handle } or { first:lower(), sur:lower() }
		table.insert(junk, {
			addr = string.format("closed.%s-%02x%02x", kind.id, i, rng:int(0, 255)), name = name,
			org = "civilian", tier = 1, closed = true, region = "closed", junk = "closed-" .. kind.id,
			ice = rng:int(kind.ice[1], kind.ice[2]), tone = kind.tone, users = users, paydata = kind.paydata,
			tagline = "Closed network", about = kind.about,
		})
	end
	-- each lab runs a different project under a different codename
	local projects, codes = {}, {}
	for i, p in ipairs(Lore.projects) do projects[i] = p end
	for i, c in ipairs(Lore.codenames) do codes[i] = c end
	for i = 1, math.min(labCount, #projects) do
		local project = table.remove(projects, rng:int(1, #projects))
		local code = table.remove(codes, rng:int(1, #codes))
		local org = Lore.getOrg(project.org)
		local slug = code:lower():gsub("%s", "")
		local logs = {}
		for run = 1, rng:int(4, 8) do table.insert(logs, rng:pick(labLogs):format(run * rng:int(3, 9))) end
		local value = rng:int(org.paydata[1], org.paydata[2]) * 4
		table.insert(labs, {
			addr = string.format("closed.%s.%s", project.org, slug),
			name = org.name .. " research node " .. code,
			org = project.org, tier = 2, closed = true, region = "closed", tone = "lab",
			ice = rng:int(4, 6),
			tagline = "PROJECT " .. code .. "  -  NO EXTERNAL CONNECTIONS",
			about = "An unlisted " .. org.name .. " research network, cut off from the corporate net.",
			lab = { code = code, subject = project.subject },
			files = {
				["research/" .. slug .. "/summary.txt"] = { text = "PROJECT " .. code .. "\n" .. org.name ..
					", " .. project.subject .. ".\n\n" .. project.detail .. "\n\nClassification: board eyes only." },
				["research/" .. slug .. "/test_log.txt"] = { text = table.concat(logs, "\n") },
				["research/" .. slug .. "/prototype_" .. slug .. ".dat"] = { text = "[experimental research data: " .. project.subject .. "]",
					paydata = value, research = { code = code, subject = project.subject } },
			},
		})
	end
	return { junk = junk, labs = labs }
end

function Lore.region(id)
	return Lore.regions[id or "nc"] or Lore.regions.nc
end

-- An organisation: the CyberScript shared core's entry (shared with the other
-- mods, which can add their own) with Real Netrunning's security profile on it.
function Lore.getOrg(id)
	local core = require("modules/core").get()
	local org = core and core.orgs.get(id)
	if org and org.ice and org.paydata and org.users then return org end
	if org and Lore.orgs[id] == nil then
		-- an organisation another mod added: secure like a mid-size corp
		local base = Lore.orgs[org.kind == "gang" and "maelstrom" or "kangtao"]
		return setmetatable({ name = org.name, kind = org.kind }, { __index = base })
	end
	return Lore.orgs[id] or Lore.orgs.unregistered
end

return Lore
