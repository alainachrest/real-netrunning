# Real Netrunning

Grey Hack-style netrunning for Cyberpunk 2077, built from Night City's own lore. Scan for networks, break their ICE, read what's inside, sell paydata and jack into real doors and cameras around you. NetWatch is watching.

Version 0.1.0 — first playable build.

## Requirements

- Cyberpunk 2077 2.5
- Cyber Engine Tweaks 1.38 or newer
- redscript and Codeware 1.21 or newer, for the in-game deck
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
| `scan` | List networks your deck can reach |
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
| `jack` | Jack into the device you're looking at. Devices wired to an access point join its whole network |
| `devices` | List the real devices on an access point network (once its control floor is open) |
| `device <number> <action>` | Control one of them (doors: open, close, lock, unlock; cameras and turrets: on, off). On a single device, just `device <action>` |
| `fight` | Fight a NetWatch agent that has entered your network |
| `scrub` | Wipe your traces from a network you have root on, lowering heat (once per network) |
| `netwatch` | Threat level, heat and agents derezzed. `netwatch world off` stops attacks on V outside the Net |
| `status` | Deck power, trace, NetWatch heat and threat level |
| `news` | Recent events across Night City's nets |
| `disconnect`, `clear` | Drop the connection, clear the screen |

- Every network is a stack of floors, as in Cyberpunk Red: a lobby, then ICE, password gates, file vaults, a control floor on access point networks, and a core. Breaching the core gives root. Gangs run shallow networks; corporate headquarters run deep ones with Black ICE, which hits back when a breach fails.
- Start with `scan` and `connect nc.subnet.public`. Breaching networks reveals new routes, from gang relays to corporate branches, backbones and eventually Arasaka in Tokyo.
- Progress through each network's floors is saved, so you can come back and carry on.
- Deck power comes from V's Intelligence. Higher ICE needs a stronger deck.
- Trace fills while you breach. At 100% NetWatch severs the connection and your heat rises. Black ICE on the hardest targets hits back.
- Progress is saved per save slot.

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

Events: `hack.breach`, `hack.download`, `hack.connected`, `hack.disconnected`, `netwatch.traced`, `netwatch.heat`, `netwatch.tier`, `netwatch.agent_spawn`, `netwatch.agent_arrived`, `netwatch.agent_defeated`, `netwatch.agent_won`, `netwatch.world_attack`, `network.revealed`, `network.breached`, `device.action`, `world.faction_score`, `cyberscript.variable`, or `*` for all.

## Credits

`lib/GameSession.lua` and `lib/GameHUD.lua` are from [psiberx's cp2077-cet-kit](https://github.com/psiberx/cp2077-cet-kit) (MIT licence, included).
