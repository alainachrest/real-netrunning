# Real Netrunning

Grey Hack-style netrunning for Cyberpunk 2077, built from Night City's own lore. Scan for networks, break their ICE, read what's inside, sell paydata and jack into any devices around you. NetWatch is watching.

Version 0.2.0: territory wars, user accounts and bank jobs, data and passwords that change over time.

## Requirements

- Cyberpunk 2077 2.5
- Cyber Engine Tweaks 1.38 or newer
- redscript and Codeware 1.21 or newer, for the in-game deck
- Optional: [Virtual Atelier](https://www.nexusmods.com/cyberpunk2077/mods/2987) 1.4.8 or newer, for its stores in the desktop Browser
- Optional: [Browser Extension](https://www.nexusmods.com/cyberpunk2077/mods/10038), for other mods' sites in the desktop Browser
- CyberScript with the shared core (API 2): the [`api-hooks-and-2.5` build](https://github.com/alainachrest/cyberscript-cp2077-fork/tree/api-hooks-and-2.5). Real Netrunning runs on its shared core (organisations, stock market, news, heat and standing), which other mods share too. Without it, the deck says so and stays offline.

## Install

Copy the `bin` and `r6` folders into your Cyberpunk 2077 folder.

## Playing

Bind **Open cyberdeck** in CET's Hotkeys tab, then press it in game. The deck opens in the game's own UI: the world keeps moving, V's controls pause while it's open, and you type straight into it. Press the hotkey again or Esc to close it.

- Enter runs a command, Up and Down step through past commands, Page Up and Page Down scroll the output.
- If the native deck can't load (no Codeware, or the `r6` folder is missing), the hotkey falls back to the deck in the CET overlay.

### Computer desktops

Every in-game computer gets a **DESKTOP** button in the bottom-right of its screen. It switches into a simulated OS over the normal screen, which stays as it was underneath.

- **Desktop**: icon tiles, a taskbar with an **NC//OS** start menu, a button per open window, and a tray showing NetWatch heat and the in-game time.
- **Windows**: drag them by the title bar, minimise with `[ _ ]`, close with `[ X ]`, click one to bring it to the front, or use its taskbar button. Several can be open at once.
- **Files**: the computer's own mail and documents in folders, plus a `System` folder of files generated for that machine. Encrypted documents and system files stay locked until you breach the computer. Click a document to open it in its own window.
- **Save to Home**: documents you open on other computers can be saved to V's own computers, where they appear under `Home/Saved`. They're kept per save.
- **Browser**: a real browser for the Night City net. Tab, back/forward/reload/home, an address bar you can type an address, ticker or search into, a scrollbar (mouse wheel works over the page) and a status bar that shows where a link goes. Sites have banners in their owner's colours, navigation bars, cards, tables, buttons and live stock charts: the portal, a directory of every network you know, the newsfeed, search, corporate and gang sites (with their internal files once breached), CyberScript datapack pages and the stock exchange.
- **Exchange**: opens the browser on the Night City Stock Exchange, where you can buy and sell with real eddies.
- **Terminal**: the cyberdeck shell, already connected to that computer. Type `breach` to unlock its files.
- **Cyberdeck**: opens the full deck popup connected to that computer.

| Command | What it does |
| --- | --- |
| `help` | List commands |
| `scan [filter]` | List networks you know, grouped by region. Filter with a region (`nc`, `nusa`, `pacific`, `eu`, `orbit`, `closed`), `local` for small nets, `corp`, or any word |
| `uplinks` | Which regions beyond Night City you can reach, and what to root to reach the rest |
| `connect <address>` | Connect to a network |
| `map` | Show the network's floors and what blocks each one |
| `routes` | Where the network you're connected to leads: the routes you've found from it (and closed networks it bridges to), and how many are still hidden until you take root |
| `breach` | Break the ICE on the next locked floor (raises trace) |
| `password <code>` | Open a password gate (codes hide in mail on earlier floors) |
| `crack` | Brute-force a password gate instead (slow, raises trace) |
| `ls`, `cd`, `cat` | Browse and read files once you have access |
| `download <file>` | Sell paydata for eddies (corporate data may carry an insider tip) |
| `leak <file>` | Leak paydata to the press: the owner's stock crashes, the journalist pays a little |
| `holdings` | The networks you hold, their ICE and guards, and any raids on them |
| `territory` | Who holds how many networks, and the fights going on right now |
| `harden [level]` | Install your own ICE (up to 6) on a network you hold, for eddies. Without a level, lists the costs |
| `guard [basic\|elite\|dismiss]` | Hire a netrunner to guard a network you hold for 2 hours of play |
| `defend` | Counter-hack an attack on the network you're connected to |
| `bank <file> [pin]` | Empty a bank account file (`.acct`) into your wallet: with its PIN, or leave the PIN off to brute-force it with your deck |
| `market` | Stock prices |
| `buy <ticker> <qty>`, `sell <ticker> <qty or all>` | Trade shares (1% fee) |
| `portfolio` | Your shares and their value |
| `jack` | Jack into the device you're looking at and join the network it's on. Some access points bridge to closed networks |
| `nearby` (or `scan nearby`) | List the device networks around you: online ones become reachable from anywhere |
| `devices` | List the real devices on an access point network (once its control floor is open) |
| `device <number> <action>` | Control one of them (doors: open, close, lock, unlock; cameras and turrets: on, off). On a single device, just `device <action>` |
| `fight` | Fight a NetWatch agent that has entered your network |
| `scrub` | Wipe your traces from a network you have root on, lowering heat (once per network) |
| `netwatch` | Threat level, heat and agents derezzed. `netwatch world off` stops attacks on V outside the Net |
| `status` | Your cyberdeck and its tier, deck power, trace, NetWatch heat and threat level |
| `jackin`, `jackout`, `cyber` | Enter the network you're connected to in cyberspace, leave it, or see where you are. `cyber scan` maps the rooms around you |
| `news` | Recent events across Night City's nets |
| `disconnect`, `clear` | Drop the connection, clear the screen |

- Every network is a stack of floors, as in Cyberpunk Red: a lobby, then ICE, password gates, file vaults, a control floor on access point networks, and a core. Breaching the core gives root. Small networks (single devices, computers) leave their core unguarded, but you still have to reach it: walk down and use it in cyberspace, or `breach` it (instant) or `cd` into it from the deck. Gangs run shallow networks; corporate headquarters run deep ones with Black ICE, which hits back when a breach fails.
- Start with `scan` and `connect nc.subnet.public`. Breaching networks reveals new routes, from gang relays to corporate branches, backbones and eventually headquarters around the world and in orbit.
- Progress through each network's floors is saved, so you can come back and carry on.
- Networks are full of the things people leave lying around: notices in the lobby, daemon logs behind the ICE, attempt logs at password gates, memos and temp files in shared folders, diagnostics on control floors, backups and audit logs in the core. The same goes for the files on computers.
- **User accounts**: the first files floor has a home folder for each user, with their mail (work, personal and plenty of spam), notes, downloads, photos and deleted files. Real people (not service accounts like `secops`) sometimes keep a bank account there.
- **Bank accounts**: `cat` an `.acct` file to see the bank and balance, then `bank <file> <pin>` to empty it. Careless owners leave the PIN in a reset email from their bank or a `pins.txt`. Without it, `bank <file>` brute-forces the PIN with your deck, which takes time and raises trace. Three wrong PINs or failed cracks and the bank freezes the account; it reopens 2 hours of play later with a new PIN. An emptied account fills back up over 2 hours of play (payday), so you can come back for more. Corporate staff keep the most, and emptying their accounts draws more NetWatch heat. In cyberspace, using an account object starts the brute force. V's own home computers have none.
- **Data changes over time**: every few hours of play (each network on its own schedule) a network's mail, logs, memos, clutter and paydata are replaced with new ones, so networks you've already picked clean are worth another look later. The people who use it and their bank accounts stay the same, and so do the password gates and any research files.
- **Passwords change**: secure networks change their gate codes every few in-game days (ICE 5 and up every 2 days, ICE 3 and 4 every 4 days), each on its own schedule; sleeping or skipping time counts. When they do, any password gate you got through is locked again (unless you have root there) and the hint mail carries the new code. Less secure networks keep theirs.
- Deck power comes from the tier of the cyberdeck V has installed, as in Much Better Netrunning: Common 1, Uncommon 2, Rare 3, Epic 4, Legendary 5, Legendary+ and ++ 6. Without a cyberdeck you can't `breach` or `crack` at all.
- A deck can only `breach` ICE up to one level above its own power (a Common deck handles ICE 2, Epic handles ICE 5), and a stronger deck breaks ICE faster and more reliably. ICE beyond your deck can still be fought in person in cyberspace. `status` shows your deck and its tier.
- Trace fills while you breach. At 100% NetWatch severs the connection and your heat rises. Black ICE on the hardest targets hits back.
- Progress is saved per save slot.

## Cyberspace

Connect to a network and type `jackin`: V's body stays where it is, and V walks into the network itself, built high above Night City out of the game's own cyberspace (Mikoshi, Alt's cyberspace and the Blackwall).

Bind **Cyberspace: use**, **Cyberspace: scan nearby rooms** and **Cyberspace: jack out** in CET's Hotkeys tab.

- Every floor of the network is a complex of 16 m rooms (4 x 4 up to 8 x 8 for off-world headquarters), with walls, doorways and ceilings, stacked downwards. The rooms branch off in every direction, with loops and dead ends, so there's more than one way through. You arrive along one edge; the way down is in the room furthest away, and data objects are tucked into dead ends first, then the other rooms. Only the floor you're on and the one below are built at any time; going back up rebuilds the floor above first. Layouts are generated from your save, so each network's floors are the same every visit.
- While the floor below is locked, the doorway into the room with the way down is sealed by a barrier you can't walk through.
- **ICE** stands guard at the sealed doorway as the owner's own netrunners: gang netrunners on gang nets, corporate security on corp nets, Voodoo Boys-grade elites for Black ICE. They fight the game's own way, with guns and quickhacks. Take them down and the next floor opens. Fighting ICE raises your trace. You can still `breach` from the deck instead: use the gate, or type it.
- Everything you can use is marked so you can see it from across a room, each with its own hologram and a pool of coloured light (data shows as hologram screens, paydata as the same screens in gold, the ways up and down as beams of light, the jack-out node as a holographic pillar): data is cyan, paydata gold (grey once taken), the way down green, the way up and the jack-out node white, a sealed doorway red, device consoles orange and the network core violet. Dust drifts through every room.
- **Scanning** anything in cyberspace shows what it is in the Net, not the character it was built from: "Maelstrom ICE", "Arasaka Black ICE", "Valentinos netrunner", "Rogue AI construct", "NetWatch agent", "Rival netrunner", with the affiliation to match (whoever holds the network now).
- **Data objects** on each floor are its files. Use one to download paydata, or to read it in the deck.
- **Password gates** open your deck to type the code or `crack` it. Control floors have a device console; the core is the bottom floor.
- **NetWatch** agents who trace into the network (never isolated or closed ones: they come in over the Net) show up in person, on the far side of the floor, and work their way through the rooms to you (they don't hit your trace from afar while you're jacked in). Kill one for the same bounty as `fight`.
- **Patrolling ICE** wanders the corridors of networks you don't own, a room at a time. Get within a couple of rooms and it picks up your trail and hunts you. Fighting it raises your trace.
- **Rival netrunners and rogue AIs** turn up now and then in any network, even ones you already own (rivals can't get into isolated or closed networks, but a rogue AI can be lurking anywhere), so going back is never quite safe. They hunt you room by room and follow you between floors. Rivals' deck shards fence for eddies; rogue AIs are rarer and tougher, worth far more, and make the news. (Your own computer at home stays safe.)
- **Deep floors** (floor 3 and down) of networks you don't own raise your trace just for being there, faster the deeper and bigger the network, so you can't wander forever.
- **Scan** (`cyber scan` or its hotkey) lists the doorways out of your room and what's within three rooms of you, with the route to each: data, the way down, the way back up, and anything hostile. It costs 6% trace, free on networks you own.
- Hunters move the way data does: they blink from room to room through the doorways, and fight normally once they're in your room.
- While you're jacked in, the minimap, quest tracker, input hints and activity log are hidden (whichever of them you had on), and come back when you jack out, even if the game closed while you were still in.
- Fast travel and manual saves are blocked until you jack out.
- Jack out with the hotkey, `jackout`, or the exit node on the first floor. You're thrown out, with dumpshock, if you're traced, if your health drops too low (not on Black ICE floors: Black ICE kills), or if something finds your body. Your own home computer's network is the one safe place in cyberspace: nothing comes for your body there, no patrols, rivals or rogue AIs, and its deep floors don't raise your trace. Connect anywhere else, even from your home computer, and you're fair game.
- Terminal and cyberspace are the same network: anything opened in one is open in the other.
- If a save ever loads while V was in cyberspace, V wakes up back where they jacked in.

## Beyond Night City

Networks outside Night City need an uplink: get root on a network that routes to that region, and every network there becomes reachable.

| Region | Uplink | What's there |
| --- | --- | --- |
| New United States | Militech NUSA backbone relay | Militech HQ (Washington), Petrochem HQ (Dallas), Zetatech, World News Service |
| Pacific Rim | Arasaka trans-Pacific backbone or Kang Tao Pacific backbone | Arasaka HQ (Tokyo), Kang Tao HQ, Kiroshi Opticals |
| EuroTheater | Biotechnica transatlantic relay | Biotechnica HQ (Italy), SovOil HQ (Moscow) |
| Orbit | Orbital Air Night City launch control | Orbital Air traffic control, Crystal Palace, Arasaka's orbital station |

- The further away a network is, the more lag: breaches and cracks there raise trace faster (x1.25 up to x1.8 in orbit). `scan` and each site show the lag.
- Headquarters are the deepest networks in the game and carry the most valuable paydata.
- Night City also has new corporate networks: Delamain, Biotechnica Flats, Petrochem's Badlands oil fields and Orbital Air's launch control. Every listed company now has networks, so hacking any of them moves its stock.

## Local networks

Each save also has 48 small networks scattered across Night City's districts: noodle bars, pawn shops, karaoke clubs, ripperdoc clinics, BD parlours, megabuilding meshes, NCART stations, vending machines, freelance netrunners' rigs and dead nodes nobody switched off. They're generated from the save, so they stay the same every time you load it.

- The public subnet leads to one in each district. Each one you own points to a couple more.
- They're easy and pay little, but ripperdocs, BD parlours and netrunners' rigs are worth more, and the odd dead node still has something inside.
- `scan local` lists only these.

## Device networks

Every electronic device in Night City is on a network: doors, cameras, turrets, access points, computers, terminals, vending machines, arcade cabinets, jukeboxes, TVs, radios, speakers, screens, billboards, lights, fans, fuse boxes, alarms, sensors, elevators, and anything else the game counts as a device. `jack` into any of them, or type `nearby` to see what's around you.

- **Access point networks**: devices wired to an access point share its network.
- **Systems**: devices run by something else, such as a building's security system or a computer that works the doors, share a network with it.
- **Local meshes**: other devices share a mesh with their neighbours, one per city block (and per few storeys of a building). It might be a storefront network, a building LAN, a security mesh or a street utility grid, depending on what's in it.
- **Loners**: some devices are on a network of their own. Vending machines, arcade cabinets and old computers often are.
- **Online or isolated**: some networks are linked to the Net, so once you've found one you can `connect` to it from anywhere. Others are isolated, with no link out at all, and the only way in is to stand there and jack into one of their devices.
- **Devices wired in deeper**: most devices sit on their network's lobby, but some are wired into a lower floor, down to the control floor. Jack into one of those and you're in on that floor, with it and every floor above it open, past the locks you'd otherwise have to breach. The deck starts there, and so does cyberspace. `devices` shows which floor each device is on.
- A device is always on the same network, decided by your save. Networks you've found are kept in your save, and their device lists grow as you find more of their devices. Each one's control floor lets you control its devices (`devices`, `device <n> <action>`): doors open, close, lock and unlock, and everything else switches on and off.

## Closed networks

Some networks are air-gapped: you can't reach them over the Net at all. Each one is bridged from a single device somewhere in the world, and the only way in is to go there and jack in.

- When you `jack` into an access point (or, more rarely, a computer), it may turn out to be wired to a closed network. The deck tells you, and the network shows up in `scan closed` and the browser's directory.
- Hack the access point down to its control floor to open the bridge, then `connect` to the closed network while you're still jacked in there. Walk away or connect elsewhere and you're unplugged.
- Most are private: fixers' stash servers, smugglers' manifests, gang safehouses, ripperdocs' offline archives, building security cores, home servers and netrunners' offline vaults.
- Some are **secret corporate research labs**, more likely behind access points that guard turrets or lots of devices. Each runs an off-books project under a codename, such as Militech's autonomous hunter drones or Zetatech's self-learning daemon. Their ICE is the hardest in Night City, and their research files are worth a fortune.
- Selling research raises your heat. Leaking it to the press exposes the project by name and hits the company's stock harder than any other leak.
- Each save has 14 private closed networks and 10 labs. Which device leads to which is decided the first time you jack into it, and stays that way.

## Territory

Networks change hands. The gangs and corporations fight over the Net all the time, and the networks you take are yours only as long as you can hold them.

- Every few minutes of play a gang or corp goes after someone else's network. Gangs fight gangs (and take independent and device networks) on Night City's streets; corps fight corps anywhere. Rivals go for each other first: Valentinos and 6th Street, Maelstrom and Tyger Claws, Arasaka, Militech and Kang Tao, and so on. Each takeover plays out over a few minutes and ends up in the news.
- **NetWatch and rogue AIs take networks too.** Now and then something from beyond the Blackwall takes over a network, anywhere in the world, big corporate networks most of all, and an AI that's loose spreads faster. NetWatch quarantines networks (gang networks, and any network an AI holds, first of all) and hands them back to their operators about 4 hours of play later. On an AI's network its constructs patrol in place of the ICE and more of them turn up; on a quarantined one, NetWatch agents do. Breaking a NetWatch quarantine costs a lot of standing with NetWatch and raises your heat; tearing an AI out of a network earns a little with them. NetWatch raids your networks more the hotter you are, and a rogue AI can come for them too.
- When a network changes hands, its new owner rebuilds the ICE: any progress you'd made on it is gone, and you breach it from the lobby again. Nobody starts a takeover of the network you're working on at that moment.
- `scan` shows who holds a network when it isn't its original operator, and which ones are under attack. `territory` shows who holds how many and every fight going on.
- Taking a network from a gang or corp costs standing with them (more for bigger networks) and earns a little with their rivals. Standing is the shared core's, so other mods see it too.
- Every hour or two of play, someone raids one of your networks: usually whoever you took it from, otherwise the factions that like you least. You get a warning and 5 minutes. When time runs out, the raid's strength is weighed against your defences: the stronger they are, the likelier you hold it. Lose it and you're back to breaching it from the lobby.
- Defend your networks three ways:
  - `harden <level>`: install your own ICE, levels 1 to 6. Costs rise steeply with each level and with the network's size.
  - `guard basic` or `guard elite`: a hired netrunner sits on the network for 2 hours of play, adds to its defences and pushes raiders back while you're away. Guards can be flatlined in a hard fight.
  - Fight them live: `defend` from the deck counter-hacks the attackers, or jack in and the raiders are there in cyberspace. Every one you derezz weakens the attack (and pays a little); they keep coming in waves until the attack breaks or ends.
- You can join other people's fights too: jack into a network under attack and the attackers' netrunners are there, fighting the network's own ICE. Derezz them, or `defend` from the deck, and the defenders will remember who helped.
- Every network is fought over: corporate and gang networks, local ones, device networks, computers, even closed and isolated networks (their new owners walk in on site). Only the public subnet and your home network are safe.

## NetWatch

Heat now has consequences. Your threat level shows in `status`, `netwatch`, and on the `nc://netwatch` site.

| Heat | Threat | What happens |
| --- | --- | --- |
| 0–24 | CLEAR | Nothing |
| 25–49 | WATCHED | Counter-netrunners sometimes trace into networks you're connected to |
| 50–74 | HUNTED | Agents come more often, and NetWatch netrunners shock V in the world |
| 75+ | BURNED | Agents everywhere; NetWatch also tips off the NCPD |

- An agent takes a few seconds to arrive, then attacks your trace until you `fight` it or disconnect. Beating it pays a bounty; losing locks your deck out of breaching for 20 seconds.
- Attacks in the world only happen while you're not connected. Turn them off with `netwatch world off`.
- `scrub` on networks you own brings heat back down.

## Other mods' stores and sites

The desktop Browser brings in what other mods add to Night City's net. Both mods are optional: Real Netrunning compiles and runs without them.

- **Stores** (`shop://`, or **Stores** in the portal bar): every Virtual Atelier store, with its items, prices and quality, 40 to a page. Open an item and press **Buy**: the eddies come out of V's wallet and the item goes straight into the inventory.
- **Sites on this computer**: the portal lists every site Browser Extension mods add to the computer you're on, such as Virtual Atelier's own site (with its outfit preview). These open inside the Browser window, as the mod built them.
- Vanilla sites from the journal (EZEstates, AutoFixer and the rest) are listed too. They open in the computer's own browser, with a button to switch over.

Other CET mods can add stores too:

```lua
local rn = GetMod("real_netrunning")
if rn and rn.api and rn.api.registerStore then
    rn.api.registerStore({ id = "mystore", name = "My Store", items = {
        { id = "Items.Preset_Lexington_Default", price = 1200 },
        { id = "Items.FirstAidWhiffV0" }, -- no price: the game's own price is used
    } })
end
```

## Stock exchange

Thirteen lore companies are listed, from Arasaka (ARA) and Militech (MIL) to Delamain (DLM). Prices move every 30 seconds of play, and every save has its own market. The exchange is CyberScript's shared core, so other mods trade on the same market (and can list companies of their own), and NetWatch heat and the news feed are shared the same way.

- Breaching a company's networks nudges its price down; leaking its data crashes it, and its rivals gain a little.
- Corporate paydata sometimes carries an insider tip about news that hasn't broken yet. Trade on it before it goes public, but trading a tipped stock raises your NetWatch heat.
- CyberScript faction scores for corporations move their stock too.

## CyberScript bridge

Alongside the shared core (whose own datapack actions and triggers, such as `core:add_heat` and `core:standing_above`, are documented in CyberScript):

- Gang and faction score changes from datapacks (such as Gangs of Night City) show up in `news`.
- Datapack webpages appear as sites (`web.<tag>`) you can connect to.
- Datapacks can use these actions and triggers:
  - `realnetrunning:add_heat` (`value`), `realnetrunning:reveal_network` (`address`)
  - `realnetrunning:network_owned` (`address`), `realnetrunning:heat_above` (`value`)
- CyberScript variables under tag `realnetrunning`: `heat`, `breaches`, `last_breached`.

## For other mods

```lua
local rn = GetMod("real_netrunning")
if rn and rn.api and rn.api.apiVersion >= 1 then
    rn.api.on("hack.breach", function(e) print(e.addr, e.success) end)
    rn.api.registerNetwork({ addr = "mymod.site", name = "My site", org = "unregistered", ice = 2, known = true })
end
```

Events: `hack.breach`, `hack.download`, `hack.connected`, `hack.disconnected`, `netwatch.traced`, `netwatch.heat`, `netwatch.tier`, `netwatch.agent_spawn`, `netwatch.agent_arrived`, `netwatch.agent_defeated`, `netwatch.agent_won`, `netwatch.world_attack`, `network.revealed`, `network.breached`, `network.closed_found`, `cyber.jackin`, `cyber.jackout`, `cyber.floor`, `cyber.ice`, `cyber.use`, `device.action`, `world.faction_score`, `cyberscript.variable`, or `*` for all.

## Credits

Cyberspace asset paths were found with the help of [entSpawner / World Builder](https://www.nexusmods.com/cyberpunk2077/mods/7841) and AppearanceMenuMod's prop lists (no code from either is used).


`lib/GameSession.lua` and `lib/GameHUD.lua` are from [psiberx's cp2077-cet-kit](https://github.com/psiberx/cp2077-cet-kit) (MIT licence, included).
