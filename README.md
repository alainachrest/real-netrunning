# Real Netrunning

Grey Hack-style netrunning for Cyberpunk 2077, built from Night City's own lore. Scan for networks, break their ICE, read what's inside, sell paydata and jack into real doors and cameras around you. NetWatch is watching.

Version 0.1.0 — first playable build.

## Requirements

- Cyberpunk 2077 2.5
- Cyber Engine Tweaks 1.38 or newer
- redscript and Codeware 1.21 or newer, for the in-game deck
- Optional: [Virtual Atelier](https://www.nexusmods.com/cyberpunk2077/mods/2987) 1.4.8 or newer, for its stores in the desktop Browser
- Optional: [Browser Extension](https://www.nexusmods.com/cyberpunk2077/mods/10038), for other mods' sites in the desktop Browser
- Optional: CyberScript with the extension API (`api-hooks-and-2.5` branch), for the CyberScript bridge https://github.com/alainachrest/cyberscript-cp2077-fork/tree/api-hooks-and-2.5

## Install

Copy the `bin` and `r6` folders into your Cyberpunk 2077 folder.

## Playing

Bind **Open cyberdeck** in CET's Hotkeys tab, then press it in game. The deck opens in the game's own UI: time slows, V's controls pause, and you type straight into it. Press the hotkey again or Esc to close it.

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
| `breach` | Break the ICE on the next locked floor (raises trace) |
| `password <code>` | Open a password gate (codes hide in mail on earlier floors) |
| `crack` | Brute-force a password gate instead (slow, raises trace) |
| `ls`, `cd`, `cat` | Browse and read files once you have access |
| `download <file>` | Sell paydata for eddies (corporate data may carry an insider tip) |
| `leak <file>` | Leak paydata to the press: the owner's stock crashes, the journalist pays a little |
| `market` | Stock prices |
| `buy <ticker> <qty>`, `sell <ticker> <qty or all>` | Trade shares (1% fee) |
| `portfolio` | Your shares and their value |
| `jack` | Jack into the device you're looking at. Devices wired to an access point join its whole network, and some access points bridge to closed networks |
| `devices` | List the real devices on an access point network (once its control floor is open) |
| `device <number> <action>` | Control one of them (doors: open, close, lock, unlock; cameras and turrets: on, off). On a single device, just `device <action>` |
| `fight` | Fight a NetWatch agent that has entered your network |
| `scrub` | Wipe your traces from a network you have root on, lowering heat (once per network) |
| `netwatch` | Threat level, heat and agents derezzed. `netwatch world off` stops attacks on V outside the Net |
| `status` | Deck power, trace, NetWatch heat and threat level |
| `jackin`, `jackout`, `cyber` | Enter the network you're connected to in cyberspace, leave it, or see where you are |
| `news` | Recent events across Night City's nets |
| `disconnect`, `clear` | Drop the connection, clear the screen |

- Every network is a stack of floors, as in Cyberpunk Red: a lobby, then ICE, password gates, file vaults, a control floor on access point networks, and a core. Breaching the core gives root. Gangs run shallow networks; corporate headquarters run deep ones with Black ICE, which hits back when a breach fails.
- Start with `scan` and `connect nc.subnet.public`. Breaching networks reveals new routes, from gang relays to corporate branches, backbones and eventually headquarters around the world and in orbit.
- Progress through each network's floors is saved, so you can come back and carry on.
- Deck power comes from V's Intelligence. Higher ICE needs a stronger deck.
- Trace fills while you breach. At 100% NetWatch severs the connection and your heat rises. Black ICE on the hardest targets hits back.
- Progress is saved per save slot.

## Cyberspace

Connect to a network and type `jackin`: V's body stays where it is, and V walks into the network itself, built high above Night City out of the game's own cyberspace (Mikoshi, Alt's cyberspace and the Blackwall).

Bind **Cyberspace: use** and **Cyberspace: jack out** in CET's Hotkeys tab.

- Every floor of the network is a small complex of 16 m rooms (2 x 2 up to 3 x 3), with walls, doorways and ceilings, stacked downwards. You arrive in one room; the way down is in the room furthest away, and data objects are spread through the rooms in between. Layouts are generated from your save, so each network's floors are the same every visit.
- While the floor below is locked, the doorway into the room with the way down is sealed by a barrier you can't walk through.
- **ICE** stands guard at the sealed doorway as the owner's own netrunners: gang netrunners on gang nets, corporate security on corp nets, Voodoo Boys-grade elites for Black ICE. Take them down and the next floor opens. Fighting ICE raises your trace. You can still `breach` from the deck instead: use the gate, or type it.
- **Data objects** on each floor are its files. Use one to download paydata, or to read it in the deck.
- **Password gates** open your deck to type the code or `crack` it. Control floors have a device console; the core is the bottom floor.
- **NetWatch** agents who trace into the network show up in person. Kill one for the same bounty as `fight`.
- No guns in cyberspace: quickhacks only. Fast travel and manual saves are blocked until you jack out.
- Jack out with the hotkey, `jackout`, or the exit node on the first floor. You're thrown out, with dumpshock, if you're traced, if your health drops too low (not on Black ICE floors: Black ICE kills), or if something finds your body. Jacking in from one of V's own home computers keeps your body safe.
- Terminal and cyberspace are the same network: anything opened in one is open in the other.
- If a save ever loads while V was in cyberspace, V wakes up back where they jacked in.
- Change the look in the deck, live: `cyber style` picks the floor and `cyber walls` the walls from the game's own cyberspace meshes, `cyber scale` resizes it, `cyber light` sets the brightness and colour of the room lights, and `cyber sky` sets the weather while you're jacked in (put back when you leave). Your choices are kept per save.

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

## Closed networks

Some networks are air-gapped: you can't reach them over the Net at all. Each one is bridged from a single device somewhere in the world, and the only way in is to go there and jack in.

- When you `jack` into an access point (or, more rarely, a computer), it may turn out to be wired to a closed network. The deck tells you, and the network shows up in `scan closed` and the browser's directory.
- Hack the access point down to its control floor to open the bridge, then `connect` to the closed network while you're still jacked in there. Walk away or connect elsewhere and you're unplugged.
- Most are private: fixers' stash servers, smugglers' manifests, gang safehouses, ripperdocs' offline archives, building security cores, home servers and netrunners' offline vaults.
- Some are **secret corporate research labs**, more likely behind access points that guard turrets or lots of devices. Each runs an off-books project under a codename, such as Militech's autonomous hunter drones or Zetatech's self-learning daemon. Their ICE is the hardest in Night City, and their research files are worth a fortune.
- Selling research raises your heat. Leaking it to the press exposes the project by name and hits the company's stock harder than any other leak.
- Each save has 14 private closed networks and 10 labs. Which device leads to which is decided the first time you jack into it, and stays that way.

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

Thirteen lore companies are listed, from Arasaka (ARA) and Militech (MIL) to Delamain (DLM). Prices move every 30 seconds of play, and every save has its own market.

- Breaching a company's networks nudges its price down; leaking its data crashes it, and its rivals gain a little.
- Corporate paydata sometimes carries an insider tip about news that hasn't broken yet. Trade on it before it goes public, but trading a tipped stock raises your NetWatch heat.
- CyberScript faction scores for corporations move their stock too.

## CyberScript bridge

When CyberScript's extension API is installed:

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
