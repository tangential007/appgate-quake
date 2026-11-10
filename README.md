# Appgate customization: Quake III Arena in the browser

Serves Quake III Arena to web browsers from an Appgate SDP appliance, using
[QuakeJS](https://github.com/nerosketch/quakejs) (ioquake3 compiled to
JavaScript) with fixes from
[quakejs-docker](https://github.com/treyyoder/quakejs-docker). Players open
`http://<appliance>:8080/` and play; nothing to install.

Content is the freely distributable **Quake III Arena demo** plus the 1.32
point release: q3dm1, q3dm7, q3dm17, q3tourney2 and the pro-* maps. The demo
license ships in the package as `data/Q3DEMO-EULA.txt`.

## What runs on the appliance

| Unit            | Process              | Listens on                          |
|-----------------|----------------------|-------------------------------------|
| `cz-quake3-web` | `node web.js`        | `0.0.0.0:8080` page, assets, WS proxy |
| `cz-quake3`     | `node ioq3ded.js`    | `127.0.0.1:27960` game (WebSocket)  |

Both run as the unprivileged `q3server` user in sandboxed, memory/CPU-capped
transient systemd units. Only TCP 8080 is opened (iptables chain
`CZ-QUAKE3`, sources from `Q3_ALLOW_FROM`). `web.js` has no dependencies; it
serves static files and passes WebSocket upgrades through to the game server,
setting `X-Forwarded-For` so the server sees each player's real address.

## Build (Linux or WSL with internet)

    ./build.sh --accept-eula

Needs git, npm, python3, zip. Sources are pinned to specific commits and npm
versions (Node 22 runtime, ws 0.4.32). Output: `appgate-quake3.zip`, ~140 MB
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
    nano /var/lib/cz-quake3/base/baseq3/server.cfg && systemctl restart cz-quake3

In-game: Esc for the menu; the backquote key (`` ` ``) opens the console.

## Troubleshooting

- Page doesn't load: `ss -ltn 'sport = :8080'`, `iptables -L CZ-QUAKE3 -n -v`,
  `tcpdump -ni any tcp port 8080`.
- Page loads but "connection refused"/stuck: `ss -ltn 'sport = :27960'` and
  `journalctl -u cz-quake3 -n 50`.
- `stop` removes the firewall chain; to apply config changes just re-run
  `/opt/customization/start`.
