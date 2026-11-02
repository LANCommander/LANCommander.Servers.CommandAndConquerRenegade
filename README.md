# Command & Conquer: Renegade Server (Docker)

This repository provides a Dockerized **Command & Conquer: Renegade** (2002) dedicated server. It runs the [Tiberian Technologies](https://www.tiberiantechnologies.org/) (TT) server, the community-maintained Free Dedicated Server with the TT patch and SSGM, under Wine. There is no Linux build of the TT server.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Downloads the official TT server package (pinned to 4.8, build b8841, sha256-checked) on first start, and again when `RENEGADE_SERVER_URL` changes
- Takes the retail data the TT package leaves out (`always.dat`, `always2.dat`) from an existing install or from a zip of one (`RENEGADE_ARCHIVE_URL`)
- LAN, GameSpy or WOL (XWIS) mode
- Server name, MOTD, password, player count, time limit, game rules and the map rotation come from environment variables
- The server log is followed into `docker logs`
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  renegade:
    image: lancommander/commandandconquerrenegade:latest
    container_name: renegade

    ports:
      - "4848:4848/udp"
      - "3373:3373/udp"
      - "25300:25300/udp"

    volumes:
      - ./config:/config

    environment:
      RENEGADE_SERVER_NAME: "My Renegade Server"
      RENEGADE_GAME_TYPE: "LAN"
      RENEGADE_MAX_PLAYERS: "32"
      RENEGADE_TIME_LIMIT: "30"
      # RENEGADE_ARCHIVE_URL: "https://example.com/renegade.zip"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

LAN games are found by broadcast, so a network where the container gets its own LAN IP (macvlan/ipvlan, or `network_mode: host`) works better than port mapping. Players can always connect by IP.

---

## Game Files

The TT server package is downloaded automatically. It contains the server, the multiplayer maps and `always3.dat`, but not the retail `always.dat` and `always2.dat`, which you must supply from a copy of the game:

- copy them to `config/Server/data/`, **or**
- copy a whole Renegade install to `config/Server/` (TT's server files are installed over it), **or**
- set `RENEGADE_ARCHIVE_URL` to a zip of a Renegade install. On first start only `data/always.dat`, `data/always2.dat` and `data/always.dbs` are extracted from it.

Clients need the same TT version as the server. The default package, TT 4.8 (build b8841), matches a client patched with `scripts-2023.02.22-b8841`. To use another release, set `RENEGADE_SERVER_URL` to a `server-<version>.zip` from the TT downloads page, and set `RENEGADE_SERVER_SHA256` to its hash or to an empty value.

## Directory Layout (Host)

```
config/
├── Server/                  # TT server + retail data (lower layer, written by the install hook)
│   ├── server.exe
│   ├── server.ini           # stock; edits go to Overlay/
│   ├── tt.cfg
│   ├── ssgm.ini
│   ├── .tt-server-url       # marker: the installed RENEGADE_SERVER_URL
│   └── data/
│       ├── always.dat       # retail
│       ├── always2.dat      # retail
│       ├── svrcfg_cnc.ini
│       └── C&C_*.mix
├── Overlay/                 # your changes and the server's writes
│   ├── server.ini           # written from RENEGADE_*
│   ├── tt.cfg               # rotation, when RENEGADE_MAPS is set
│   ├── data/svrcfg_cnc.ini  # written from RENEGADE_*
│   └── Renegade/FDS/        # renlog_<M>-<D>-<YYYY>.txt, commands.txt
├── Merged/                  # what the server sees
└── wineprefix/
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `RENEGADE_SERVER_URL` | `https://www.tiberiantechnologies.org/files/server-4.8.zip` | TT server package. Installed when `server.exe` is missing or the URL changes |
| `RENEGADE_SERVER_SHA256` | sha256 of server-4.8.zip | Checked after download; empty skips the check |
| `RENEGADE_ARCHIVE_URL` | *(empty)* | Zip of a Renegade install to take `always.dat`/`always2.dat` from, when they're missing |
| `RENEGADE_GAME_TYPE` | `LAN` | `LAN`, `GameSpy` or `WOL` |
| `RENEGADE_CONFIG` | `svrcfg_cnc.ini` | Game settings file in `data/` (server.ini `Config`) |
| `RENEGADE_SERVER_NAME` | `Renegade Server` | `bGameTitle`. Lists cut it off after about 30 characters |
| `RENEGADE_MOTD` | *(empty)* | Message shown to players when they join |
| `RENEGADE_PASSWORD` | *(empty)* | Join password; empty means none |
| `RENEGADE_MAX_PLAYERS` | `32` | 1–127 |
| `RENEGADE_TIME_LIMIT` | `30` | Minutes per map; 0 = no limit |
| `RENEGADE_STARTING_CREDITS` | `0` | Credits each player starts with |
| `RENEGADE_RADAR_MODE` | `1` | 0 off, 1 teammates, 2 everyone |
| `RENEGADE_FRIENDLY_FIRE` | `false` | |
| `RENEGADE_TEAM_CHANGING` | `false` | |
| `RENEGADE_REMIX_TEAMS` | `true` | Remix teams each map |
| `RENEGADE_SPAWN_WEAPONS` | `true` | Weapon pickups on the map |
| `RENEGADE_CAN_REPAIR_BUILDINGS` | `true` | |
| `RENEGADE_DRIVER_IS_GUNNER` | `true` | |
| `RENEGADE_BASE_DESTRUCTION_ENDS_GAME` | `true` | |
| `RENEGADE_BEACON_ENDS_GAME` | `true` | A beacon on the pedestal ends the game |
| `RENEGADE_MAPS` | *(empty)* | Comma-separated rotation, e.g. `C&C_Field,C&C_Under`. Empty keeps the `tt.cfg` rotation (all 13 stock maps) |
| `RENEGADE_PORT` | `4848` | Game port (also the GameSpy game port) |
| `RENEGADE_QUERY_PORT` | `25300` | GameSpy query port |
| `RENEGADE_REMOTE_ADMIN_PASSWORD` | *(empty)* | Enables RenRem remote admin. Empty disables it (the stock file enables it with `password`) |
| `RENEGADE_REMOTE_ADMIN_PORT` | game port + 1 | RenRem port |
| `RENEGADE_REMOTE_ADMIN_IP` | `127.0.0.1` | Address RenRem binds to |
| `RENEGADE_WOL_NICKNAME` / `_PASSWORD` / `_SERIAL` / `_LOGIN_SERVER` | *(empty)* | WOL (XWIS) login; only used in WOL mode, empty keeps server.ini's |
| `WINE_XVFB` | `auto` | `server.exe` needs a display; `auto` starts Xvfb when there's no `DISPLAY` |
| `START_ARGS` | *(empty)* | Extra arguments for `server.exe` |

### Maps

The stock rotation: `C&C_Field`, `C&C_Hourglass`, `C&C_Under`, `C&C_Complex`, `C&C_City`, `C&C_Mesa`, `C&C_Walls`, `C&C_Volcano`, `C&C_Islands`, `C&C_Canyon`, `C&C_City_Flying`, `C&C_Walls_Flying`, `C&C_Glacier_Flying`. Maps in `RENEGADE_MAPS` that have no `.mix` in `data/` are left out with a warning.

Other settings (SSGM in `ssgm.ini`, anti-cheat in `data/anticheat.ini`, the rest of `server.ini` and `tt.cfg`) can be edited in `config/Merged/`; the hooks only change the keys listed above.

## Building

```bash
docker build -t lancommander/commandandconquerrenegade:local .
# against a locally built Wine base
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/commandandconquerrenegade:local .
```

See [Documentation/Docker.md](Documentation/Docker.md) for details and troubleshooting.

## License

MIT, see [LICENSE](LICENSE). Command & Conquer: Renegade is a trademark of Electronic Arts. The game data is not included.
