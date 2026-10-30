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
- **Browser**: the Night City net. A portal, a directory of every network you know, the newsfeed, corporate sites (with their internal files once breached), CyberScript datapack pages, and the stock exchange. Back, Home and Reload buttons; click any `>` line to follow it.
- **Exchange**: opens the browser on the Night City Stock Exchange, where you can buy and sell with real eddies.
- **Terminal**: the cyberdeck shell, already connected to that computer. Type `breach` to unlock its files.
- **Cyberdeck**: opens the full deck popup connected to that computer.

| Command | What it does |
| --- | --- |
| `help` | List commands |
| `scan` | List networks your deck can reach |
| `connect <address>` | Connect to a network |
| `breach` | Break the ICE on the current network (raises trace) |
| `ls`, `cd`, `cat` | Browse and read files once you have access |
| `download <file>` | Sell paydata for eddies (corporate data may carry an insider tip) |
| `leak <file>` | Leak paydata to the press: the owner's stock crashes, the journalist pays a little |
| `market` | Stock prices |
| `buy <ticker> <qty>`, `sell <ticker> <qty or all>` | Trade shares (1% fee) |
| `portfolio` | Your shares and their value |
| `jack` | Jack into the door, camera, turret, computer or access point you're looking at |
| `device <action>` | Control a jacked device (doors: open, close, lock, unlock; cameras and turrets: on, off) |
| `status` | Deck power, trace and NetWatch heat |
| `news` | Recent events across Night City's nets |
| `disconnect`, `clear` | Drop the connection, clear the screen |

- Start with `scan` and `connect nc.subnet.public`. Breaching networks reveals new routes, from gang relays to corporate branches, backbones and eventually Arasaka in Tokyo.
- Deck power comes from V's Intelligence. Higher ICE needs a stronger deck.
- Trace fills while you breach. At 100% NetWatch severs the connection and your heat rises. Black ICE on the hardest targets hits back.
- Progress is saved per save slot.

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

Events: `hack.breach`, `hack.download`, `hack.connected`, `hack.disconnected`, `netwatch.traced`, `netwatch.heat`, `network.revealed`, `network.breached`, `device.action`, `world.faction_score`, `cyberscript.variable`, or `*` for all.

## Credits

`lib/GameSession.lua` and `lib/GameHUD.lua` are from [psiberx's cp2077-cet-kit](https://github.com/psiberx/cp2077-cet-kit) (MIT licence, included).
