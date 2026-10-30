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
}

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
		reveals = { "kangtao.nc.branch", "traumateam.nc.dispatch" } },
	{ addr = "ncpd.watson.precinct",           name = "NCPD Watson precinct", org = "ncpd", tier = 1,
		reveals = { "militech.nc.logistics" } },

	{ addr = "traumateam.nc.dispatch",  name = "Trauma Team NC dispatch", org = "traumateam", tier = 1 },
	{ addr = "kangtao.nc.branch",       name = "Kang Tao Night City branch", org = "kangtao", tier = 1,
		reveals = { "kangtao.backbone.pacifica" } },
	{ addr = "militech.nc.logistics",   name = "Militech NC logistics", org = "militech", tier = 1,
		reveals = { "militech.backbone.nusa", "arasaka.nc.tower" } },
	{ addr = "arasaka.nc.tower",        name = "Arasaka Tower, Night City", org = "arasaka", tier = 1,
		reveals = { "arasaka.backbone.pacific" } },

	{ addr = "kangtao.backbone.pacifica", name = "Kang Tao Pacific backbone relay", org = "kangtao", tier = 2 },
	{ addr = "militech.backbone.nusa",    name = "Militech NUSA backbone relay", org = "militech", tier = 2 },
	{ addr = "arasaka.backbone.pacific",  name = "Arasaka trans-Pacific backbone", org = "arasaka", tier = 2,
		reveals = { "arasaka.tokyo.hq" } },

	{ addr = "arasaka.tokyo.hq",          name = "Arasaka headquarters, Tokyo", org = "arasaka", tier = 3 },
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

function Lore.getOrg(id)
	return Lore.orgs[id] or Lore.orgs.unregistered
end

return Lore
