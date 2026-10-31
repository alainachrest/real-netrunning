-- Filler for the generated filesystems: the everyday clutter people leave on a
-- network (notes, mail, spam, logs, receipts), plus the bank accounts some of
-- them keep there. Network.buildFs calls this with its own random stream, so
-- the same save always gets the same clutter.
--
-- Bank accounts are files with a `bank` field:
--   { bank = { name, holder, number, balance, pin, security } }
-- 'bank <file> <pin>' empties one with the PIN (hidden in its owner's mail or
-- notes, if they were careless), 'bank <file>' brute-forces it with the deck.

local Junk = {}

---------------------------------------------------------------------------
-- Word lists
---------------------------------------------------------------------------

Junk.banks = {
	{ name = "EuroBank",              slug = "eurobank",   prefix = "EB" },
	{ name = "Night City Credit Union", slug = "nccu",     prefix = "NCCU" },
	{ name = "Pacific Rim Trust",     slug = "pacrim",     prefix = "PRT" },
	{ name = "Heywood Mutual",        slug = "heymutual",  prefix = "HM" },
	{ name = "Free State Savings",    slug = "fss",        prefix = "FSS" },
	{ name = "Watson Cooperative",    slug = "watsoncoop", prefix = "WC" },
}

-- accounts that belong to a service or a machine, not a person: no bank, no personal mail
local SERVICE = {}
for _, n in ipairs({ "admin", "maint", "svc", "restock", "staff", "dispatch", "billing", "procurement",
	"logistics", "qa_ops", "fieldsec", "secops", "facilities", "newsdesk", "archive", "ratings", "agri_ops",
	"labsec", "seedbank", "fieldops", "pipeline", "refinery_3", "logistika", "tanker_ctl", "flightctl",
	"manifest", "pilot_ops", "lpad_2", "cargo", "optics_qa", "firmware", "fabline", "devops", "ai_lab",
	"release", "support", "wire_desk", "legal", "dispatch_ai", "fleet", "maintenance", "garage",
	"habitat_ops", "docking", "lifesupport", "medbay", "triage", "dispatch_nc", "ncart_ops", "gate", "tech",
	"anchor_ops", "r.kiroshi_lab" }) do SERVICE[n] = true end

function Junk.isPerson(user)
	return user ~= nil and not SERVICE[user]
end

local spam = {
	"CONGRATULATIONS! You've been selected for a FREE Kiroshi upgrade consultation. Reply with your account details to claim.",
	"Tired of your old chrome? Ask about 0% financing at your nearest ripperdoc. Terms apply. Organs accepted as collateral.",
	"Your NCART pass is about to expire. Renew now and get 3 free rides to Pacifica (Pacifica service suspended).",
	"Hot singles in Japantown want to share braindances with you!",
	"URGENT: your Trauma Team subscription is overdue. Platinum coverage lapses in 24 hours.",
	"Buck-a-Slice loyalty card: you're 2 slices away from a FREE slice!",
	"Nicola. Taste the future. Now with 40% less hydrogen.",
	"Re: Re: Re: invoice attached (open this)",
	"Make 10,000 eddies a week from home! No experience needed. Just a neural port and an open mind.",
	"Your Chromanticore order has shipped. It will arrive in 4-6 weeks, or never.",
	"Militech is hiring! Defend what matters. Life insurance not included for probationary staff.",
	"A Nigerian netrunner needs your help moving 2 million eddies out of the Arasaka vault.",
	"Final notice: your car's extended warranty.",
	"Mr. Whitey's Burger Shack: two Whitey Doubles for the price of three!",
}

local personal = {
	"Dinner at Tom's Diner on Friday? My treat this time. Mostly.",
	"Did you see the Ncpd scanner last night? Half of Kabuki was lit up.",
	"Mom says call her. She's worried about the gang stuff near your block.",
	"I'm not lending you more eddies until you pay back the last 300.",
	"Got us tickets for the Samurai tribute night at the Rainbow Cadenza. Don't flake.",
	"The landlord raised rent again. We need to talk about moving to Heywood.",
	"Can you feed the cat this weekend? Food's under the sink, she hates the blue one.",
	"Happy birthday! Sorry the present is late, the courier got jacked on the way.",
	"Stop sending me braindance links at work. My boss reads everything.",
	"Your cousin got his new arm. Looks great, sounds like a blender.",
	"I think someone's been in my apartment. Things moved. Am I crazy?",
	"Brunch Sunday? Lizzie's is off the table after last time.",
	"The kid wants a Johnny Silverhand poster for her room. Is that okay?",
	"I saw that Delamain cab talking to itself again. Creeps me out.",
}

local work = {
	"Reminder: timesheets are due Friday. No exceptions this quarter.",
	"The coffee machine on our floor is broken again. Facilities says next week.",
	"Please stop microwaving fish in the break room.",
	"All-hands moved to 0900. Attendance is mandatory.",
	"Who keeps leaving the back door propped open? Security is asking.",
	"Quarterly numbers attached. Don't forward them outside the team.",
	"New badge policy starts Monday. Old badges stop working at midnight Sunday.",
	"Inventory is short again. If you know something, say it now.",
	"Cleaning crew comes Thursday. Lock away anything you don't want 'cleaned'.",
}

local notes = {
	"buy: synth eggs, soy paste, noodles, batteries (AA!!), nicola x6",
	"call ripperdoc re: twitchy left hand",
	"remember: rent due on the 1st. landlord takes cash only now",
	"Things to fix: shower, door lock, the noise in the vent",
	"ideas for the band name: Neon Requiem, Chrome Dogs, Static Saints",
	"don't trust the guy at the corner shop with the gold optics",
	"workout plan: monday arms, tuesday arms, wednesday ... arms",
	"gift for J: something not chrome",
	"stop buying lottery tickets. seriously.",
	"Max's number changed again. New one is in the other file.",
	"ask about night shifts, pays 20% more",
}

local downloads = {
	{ "bd_receipt_%04d.txt", "Braindance rental receipt\nTitle: Sunset over Pacifica (XBD-free cut)\nPaid: %d eddies" },
	{ "ncart_ticket_%04d.txt", "NCART single journey\nFrom: Japantown To: Watson\nFare: %d eddies" },
	{ "menu_%04d.txt", "Takeout menu. Noodle combo %d eddies. Burritos are 'mostly real'." },
	{ "warranty_%04d.txt", "Warranty card. Covers manufacturing faults for %d days. Not valid if used." },
	{ "playlist_%04d.txt", "Morning mix\n1. Chippin' In\n2. Never Fade Away\n3. something by Us Cracks\n(%d tracks)" },
	{ "manual_%04d.txt", "Kitchen unit quick start. Do not insert hands. Section %d." },
}

local photos = {
	"[photo] sunset over the Badlands, blurry",
	"[photo] a cat asleep on a cyberdeck",
	"[photo] someone's new arm, thumbs up",
	"[photo] a crowded street in Kabuki, neon everywhere",
	"[photo] a birthday cake with too many candles",
	"[photo] a selfie in a broken mirror",
	"[photo] a car on fire. smiling people in front of it",
}

local trash = {
	"[deleted] draft resignation letter. unsent.",
	"[deleted] I'm sorry about last night. can we",
	"[deleted] old address book",
	"[deleted] screenshot of a bank balance",
	"[deleted] password list (old). most crossed out",
}

local notices = {
	"Public notice: scheduled maintenance tonight 0200-0400. Expect brief outages.",
	"Lost and found: one Kiroshi optic, green. Ask at the front desk.",
	"Reminder: this network is monitored. Smile.",
	"Visitor wifi password changed. Ask staff.",
	"Free clinic Tuesdays. Bring ID or don't, we won't ask.",
	"Do NOT plug unknown shards into the public terminals.",
}

local daemonLines = {
	"heartbeat ok", "signature db updated", "probe from %s dropped", "handshake timeout from %s",
	"memory scrub complete", "intrusion pattern matched: generic", "quarantined fragment from %s",
}

local diagLines = {
	"self-test passed", "voltage within tolerance", "fan 2 noisy", "firmware check ok",
	"sensor drift corrected", "uptime %d hours", "watchdog reset",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function eddies(n)
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end
Junk.eddies = eddies

local function ip(rng)
	return string.format("%d.%d.%d.%d", rng:int(10, 223), rng:int(0, 255), rng:int(0, 255), rng:int(1, 254))
end

local function timestamp(rng)
	return string.format("[%02d:%02d]", rng:int(0, 23), rng:int(0, 59))
end

-- How much a person keeps in the bank, by the network's tone and tier.
local RICH = { corp = true, media = true, lab = true, orbital = true }
local MID = { netrunner = true, fixer = true, smuggler = true, police = true }
function Junk.balance(rng, tone, tier)
	tier = math.max(1, tier or 1)
	if RICH[tone] then return rng:int(600, 3500) * tier, 2 + tier end
	if MID[tone] then return rng:int(300, 2500), 3 end
	if tone == "gang" then return rng:int(150, 1200), 2 end
	return rng:int(40, 700), 1
end

---------------------------------------------------------------------------
-- What goes where
---------------------------------------------------------------------------

-- Each generator calls add(path, file), path relative to the floor folder.

function Junk.lobby(rng, add, ctx)
	for _ = 1, rng:int(1, 3) do
		add(string.format("notices/notice_%02d.txt", rng:int(1, 99)), { text = rng:pick(notices) })
	end
	if rng:chance(0.5) then
		add("terms_of_use.txt", { text = "By connecting to " .. ctx.name .. " you agree to be monitored, logged, " ..
			"and reported to NetWatch at the operator's discretion.\nThe operator accepts no liability for lost chrome." })
	end
end

function Junk.ice(rng, add)
	local lines = {}
	for _ = 1, rng:int(4, 8) do
		local line = rng:pick(daemonLines)
		if line:find("%%s") then line = line:format(ip(rng)) end
		table.insert(lines, timestamp(rng) .. " " .. line)
	end
	add("daemon.log", { text = table.concat(lines, "\n") })
	if rng:chance(0.4) then
		add(string.format("quarantine/frag_%04x.bin", rng:int(0, 65535)), { text = "[corrupted fragment, unreadable]" })
	end
end

function Junk.gate(rng, add)
	local lines = {}
	for _ = 1, rng:int(2, 6) do
		table.insert(lines, timestamp(rng) .. (rng:chance(0.3) and " attempt FAILED from " or " attempt ok from ") .. ip(rng))
	end
	add("attempts.log", { text = table.concat(lines, "\n") })
end

function Junk.control(rng, add)
	local lines = {}
	for _ = 1, rng:int(3, 6) do
		local line = rng:pick(diagLines)
		if line:find("%%d") then line = line:format(rng:int(10, 9000)) end
		table.insert(lines, timestamp(rng) .. " " .. line)
	end
	add("diagnostics.log", { text = table.concat(lines, "\n") })
end

function Junk.core(rng, add)
	for _ = 1, rng:int(1, 2) do
		add(string.format("backups/config_%04x.bak", rng:int(0, 65535)), { text = "[configuration backup]" })
	end
	local lines = {}
	for _ = 1, rng:int(3, 6) do
		table.insert(lines, timestamp(rng) .. " root login " .. (rng:chance(0.8) and "ok" or "FAILED") .. " from " .. ip(rng))
	end
	add("audit.log", { text = table.concat(lines, "\n") })
end

-- Shared folders on a files floor: work documents and leftovers.
function Junk.shared(rng, add, ctx)
	for _ = 1, rng:int(2, 4) do
		add(string.format("shared/memo_%03d.txt", rng:int(1, 999)), { text = "To: all staff\n\n" .. rng:pick(work) })
	end
	if rng:chance(0.6) then
		local d = rng:pick(downloads)
		add("tmp/" .. d[1]:format(rng:int(0, 9999)), { text = d[2]:format(rng:int(3, 90)) })
	end
	if rng:chance(0.5) then
		add(string.format("tmp/cache_%04x.tmp", rng:int(0, 65535)), { text = "[temporary file]" })
	end
end

-- One person's home folder: mail, notes, downloads, trash, and maybe a bank account.
-- ctx: { name, org, tone, tier, users, bank (bool: may this network hold accounts) }
function Junk.home(rng, add, ctx, user)
	local person = Junk.isPerson(user)
	local others = {}
	for _, u in ipairs(ctx.users) do if u ~= user then table.insert(others, u) end end

	local function mail(from, body)
		add(string.format("home/%s/mail/%03d.msg", user, rng:int(1, 999)), { text = "From: " .. from .. "\nTo: " .. user .. "\n\n" .. body })
	end

	-- everyone gets spam
	for _ = 1, rng:int(1, 3) do mail("noreply@" .. rng:pick({ "promo.nc", "deals.net", "offers.nusa", "mail.biz" }), rng:pick(spam)) end
	if person then
		for _ = 1, rng:int(1, 3) do mail(#others > 0 and rng:chance(0.5) and rng:pick(others) or rng:pick({ "mom", "jess", "dee", "uncle_ray", "sam" }), rng:pick(personal)) end
		if rng:chance(0.7) then add("home/" .. user .. "/notes.txt", { text = rng:pick(notes) .. "\n" .. rng:pick(notes) }) end
		if rng:chance(0.5) then
			local d = rng:pick(downloads)
			add("home/" .. user .. "/downloads/" .. d[1]:format(rng:int(0, 9999)), { text = d[2]:format(rng:int(3, 90)) })
		end
		if rng:chance(0.4) then add(string.format("home/%s/photos/img_%04d.jpg", user, rng:int(0, 9999)), { text = rng:pick(photos) }) end
		if rng:chance(0.3) then add(string.format("home/%s/.trash/file_%03d", user, rng:int(1, 999)), { text = rng:pick(trash) }) end
	else
		mail("monitor", rng:pick(work))
	end

	-- a bank account, sometimes with its PIN left lying around. The account is
	-- the person's own (ctx.bankRng), so it's the same every time the network's
	-- data changes; only whether they left the PIN about changes.
	if person and ctx.bank then
		local brng = ctx.bankRng and ctx.bankRng(user) or rng
		if brng:chance(ctx.bankChance or 0.55) then
			local b = brng:pick(Junk.banks)
			local balance, security = Junk.balance(brng, ctx.tone, ctx.tier)
			local pin = string.format("%04d", brng:int(0, 9999))
			local number = string.format("%s-%04d-%04d", b.prefix, brng:int(0, 9999), brng:int(0, 9999))
			local account = { name = b.name, holder = user, number = number, balance = balance, pin = pin, security = security }
			add("home/" .. user .. "/bank/" .. b.slug .. ".acct", { bank = account })
			local current = ctx.pinFor and ctx.pinFor(account) or pin
			local leak = rng:next()
			if leak < 0.5 then
				mail("security@" .. b.slug .. ".nc", "Your " .. b.name .. " PIN has been reset.\nNew PIN: " .. current ..
					"\nFor your safety, delete this message after reading.")
			elseif leak < 0.65 then
				add("home/" .. user .. "/pins.txt", { text = "bank " .. current .. "\ndoor 1234\nlocker " .. string.format("%04d", rng:int(0, 9999)) })
			end
		end
	end
end

-- What an account file says, with its balance right now.
-- status: { available, frozen, refillIn, reopensIn } (Network.bankStatus)
function Junk.bankText(b, status)
	local lines = { b.name .. " - personal account", "Holder: " .. b.holder, "Account: " .. b.number,
		"Balance: " .. eddies(status and status.available or b.balance) .. " eddies" }
	if status and status.frozen then
		table.insert(lines, "Status: FROZEN after suspicious activity. Reopens in about " .. math.ceil(status.reopensIn / 60) .. " min, with a new PIN.")
	elseif status and status.refillIn > 0 then
		table.insert(lines, "Next payday in about " .. math.ceil(status.refillIn / 60) .. " min.")
	end
	table.insert(lines, "Access: PIN required.")
	table.insert(lines, "")
	table.insert(lines, "Use 'bank <file> <pin>' if you know the PIN, or 'bank <file>' to brute-force it.")
	return table.concat(lines, "\n")
end

return Junk
