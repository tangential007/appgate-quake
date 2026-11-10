# Appgate customization: Quake III Arena in the browser

Serves Quake III Arena to web browsers from an Appgate SDP appliance, using
[QuakeJS](https://github.com/nerosketch/quakejs) (ioquake3 compiled to
JavaScript) with fixes from
[quakejs-docker](https://github.com/treyyoder/quakejs-docker). Players open
`http://<appliance>:8080/` and play; nothing to install.

Content is the freely distributable **Quake III Arena demo** plus the 1.32
point release: q3dm1, q3dm7, q3dm17, q3tourney2 and the pro-* maps. The demo
license ships in the package as `data/Q3DEMO-EULA.txt`.

By default the server runs **CPMA (Challenge ProMode Arena) 1.48**: CPM
physics (air control, faster movement), FFA to start, and the arena maps
cpm1a, cpm22 and cpm3a on top of the demo maps. Players switch modes in game
with `callvote mode 1v1` (also `2v2`, `TDM`, `FFA`). CTF needs CTF maps, which
the demo content doesn't have. Set `Q3_GAME=baseq3` in `quake3.conf` for
vanilla Quake 3.

## Players

Opening the page shows a join screen: player name, name color, mouse
sensitivity and field of view. They're saved in that browser's local storage
and passed to the game before it connects, so every player has their own
name and settings; nothing about a player is stored on the server. The game
keeps its own config (key binds, model, everything set from the Esc menu) in
the browser's IndexedDB, also per player. Two people sharing one browser
profile share settings; a private window or another browser gives a fresh one.

Browsers only capture the mouse after a click in the page; Esc releases it.
A "Click to play" prompt covers the game whenever it's running without the
mouse captured, so the click that re-captures doesn't also fire a weapon.

First visit in a browser: the game shows the Quake III demo license once
("I Agree"), then downloads ~100 MB of game data, cached afterwards.

## What runs on the appliance

| Unit            | Process              | Listens on                          |
|-----------------|----------------------|-------------------------------------|
| `cz-quake3-web` | `node web.js`        | `0.0.0.0:8080` page, assets, WS proxy, `/server.json` |
| `cz-quake3`     | `node ioq3ded.js`    | `127.0.0.1:27960` game (WebSocket)  |

Both run as the unprivileged `q3server` user in sandboxed, memory/CPU-capped
transient systemd units. Only TCP 8080 is opened (iptables chain
`CZ-QUAKE3`, sources from `Q3_ALLOW_FROM`). `web.js` has no dependencies; it
serves static files and passes WebSocket upgrades through to the game server,
setting `X-Forwarded-For` so the server sees each player's real address.

## Build (Linux or WSL with internet)

    ./build.sh --accept-eula

Needs git, npm, python3, zip. Sources are pinned to specific commits and npm
versions (Node 22 runtime, ws 0.4.32). Output: `appgate-quake3.zip`, ~150 MB
(Appgate limit is 200 MB).

## Deploy

1. Customizations enabled on the appliance (`cz-config set -j customization/enabled true`).
2. Admin UI > System > Appliance Customizations: upload the zip and select it
   in the appliance's configuration. One customization per appliance: this
   replaces any other (its `stop` runs first).
3. First start takes ~30 s while the server installs the demo paks into
   `/var/lib/cz-quake3/base/baseq3`.

## Connecting through Appgate

- Entitlement: **TCP 8080** to the appliance IP. That's all; the game runs over
  the same port.
- The Gateway NATs tunnel traffic, so its IP must be inside `Q3_ALLOW_FROM`.
- Every browser downloads ~100 MB of game data on first load (cached after).

## Operate

    systemctl status cz-quake3 cz-quake3-web
    journalctl -u cz-quake3 -f
    nano /var/lib/cz-quake3/base/cpma/server.cfg && systemctl restart cz-quake3
    # (base/baseq3/server.cfg when Q3_GAME=baseq3)

Switching `Q3_GAME`: edit `/opt/customization/data/quake3.conf` and re-run
`/opt/customization/start` (or rebuild with the change in `src/data/quake3.conf`).
In `server.cfg`, `server_gameplay` picks CPM or VQ3 physics and `mode_start`
the starting mode.

In-game: Esc for the menu; the backquote key (`` ` ``) opens the console.

## Troubleshooting

- Page doesn't load: `ss -ltn 'sport = :8080'`, `iptables -L CZ-QUAKE3 -n -v`,
  `tcpdump -ni any tcp port 8080`.
- Page loads but "connection refused"/stuck: `ss -ltn 'sport = :27960'` and
  `journalctl -u cz-quake3 -n 50`.
- `stop` removes the firewall chain; to apply config changes just re-run
  `/opt/customization/start`.
