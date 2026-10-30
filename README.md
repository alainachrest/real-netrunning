# Real Netrunning

Grey Hack-style netrunning for Cyberpunk 2077, built from Night City's own lore. Scan for networks, break their ICE, read what's inside, sell paydata and jack into real doors and cameras around you. NetWatch is watching.

Version 0.1.0 — first playable build.

## Requirements

- Cyberpunk 2077 2.5
- Cyber Engine Tweaks 1.38 or newer
- Optional: CyberScript with the extension API (`api-hooks-and-2.5` branch), for the CyberScript bridge https://github.com/alainachrest/cyberscript-cp2077-fork/tree/api-hooks-and-2.5

## Install

Copy the `bin` folder into your Cyberpunk 2077 folder.

## Playing

Open the CET overlay to use the cyberdeck. CET only gives windows mouse and keyboard input while the overlay is open. A hotkey to show or hide the deck is in CET's Hotkeys tab.

| Command | What it does |
| --- | --- |
| `help` | List commands |
| `scan` | List networks your deck can reach |
| `connect <address>` | Connect to a network |
| `breach` | Break the ICE on the current network (raises trace) |
| `ls`, `cd`, `cat` | Browse and read files once you have access |
| `download <file>` | Sell paydata for eddies |
| `jack` | Jack into the door, camera, turret, computer or access point you're looking at |
| `device <action>` | Control a jacked device (doors: open, close, lock, unlock; cameras and turrets: on, off) |
| `status` | Deck power, trace and NetWatch heat |
| `news` | Recent events across Night City's nets |
| `disconnect`, `clear` | Drop the connection, clear the screen |

- Start with `scan` and `connect nc.subnet.public`. Breaching networks reveals new routes, from gang relays to corporate branches, backbones and eventually Arasaka in Tokyo.
- Deck power comes from V's Intelligence. Higher ICE needs a stronger deck.
- Trace fills while you breach. At 100% NetWatch severs the connection and your heat rises. Black ICE on the hardest targets hits back.
- Progress is saved per save slot.

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
