---
sidebar_label: Docker
---

# Command & Conquer: Renegade Docker Container

The image runs the Tiberian Technologies (TT) Renegade server, `server.exe`, under Wine and Xvfb. It's built on `lancommander/wine`.

## Quick Start

1. Create the data directory and give the server the retail data, either:
   - copy `always.dat` and `always2.dat` from a Renegade install's `Data` folder to `config/Server/data/`, or
   - set `RENEGADE_ARCHIVE_URL` to a zip of a Renegade install (e.g. a LANCommander archive).
2. Start the container:

```yaml
services:
  renegade:
    image: lancommander/commandandconquerrenegade:latest
    volumes:
      - ./config:/config
    ports:
      - "4848:4848/udp"
      - "3373:3373/udp"
    environment:
      RENEGADE_SERVER_NAME: "My Renegade Server"
    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    restart: unless-stopped
```

3. On the first start the TT server package (~70 MB) is downloaded into `config/Server/`. The server is up when `docker logs` shows `Level loaded OK` and `The game has started.`

## How It Starts

1. The base entrypoint mounts `Server/` + `Overlay/` at `Merged/` and creates the Wine prefix.
2. `PostInitialization/20-InstallRenegade.ps1` installs the TT server (when `server.exe` is missing or `RENEGADE_SERVER_URL` differs from `Server/.tt-server-url`), then extracts the retail data from `RENEGADE_ARCHIVE_URL` when `data/always.dat` or `data/always2.dat` is missing. It remounts the overlay when it changed `Server/`. It fires the `PreInstallRenegade` and `PostInstallRenegade` hooks.
3. `PostInitialization/30-ConfigureRenegade.ps1` writes the `RENEGADE_*` settings into `Merged/server.ini`, `Merged/data/<RENEGADE_CONFIG>` and `Merged/tt.cfg`, so the edits land in `Overlay/`.
4. `START_EXE` `/usr/local/bin/renegade-server` runs `wine-run server.exe` from `Merged/` and follows `Renegade/FDS/renlog_*.txt` to stdout.

## Configuration Options

### Ports

| Port | Protocol | Purpose |
|---|---|---|
| 4848 | UDP | Game (`RENEGADE_PORT`) |
| 3373 | UDP | Bound in LAN mode (fixed); used for the LAN game list |
| 25300 | UDP | GameSpy query (`RENEGADE_QUERY_PORT`), GameSpy mode only. Answers `\status\` |
| 4849 | UDP | RenRem remote admin (`RENEGADE_REMOTE_ADMIN_PORT`), only with `RENEGADE_REMOTE_ADMIN_PASSWORD`; bound to `RENEGADE_REMOTE_ADMIN_IP` (127.0.0.1) |

### Environment Variables

See the table in the [README](../README.md#environment-variables).

### Settings files

| File | Section | Keys the hook manages |
|---|---|---|
| `server.ini` | `[Server]` | `Config`, `GameType`, `Port`, `GameSpyGamePort`, `GameSpyQueryPort`, `AllowRemoteAdmin`, `RemoteAdminPassword`/`IP`/`Port`, and `Nickname`/`Password`/`Serial`/`LoginServer` when the WOL variables are set |
| `data/svrcfg_cnc.ini` | `[Settings]` | `bGameTitle`, `bMotd`, `IsPassworded`, `bPassword`, `MaxPlayers`, `TimeLimitMinutes`, `StartingCredits`, `RadarMode`, the rule flags, and `DoMapsLoop`, `IsDedicated`, `IsLaddered=no`, `IsQuickMatch=no`, `IsClanGame=no`, `IsAutoRestart=no` |
| `tt.cfg` | `rotation` | The map list, only when `RENEGADE_MAPS` is set. TT ignores the `MapNameNN` keys in svrcfg |

Every other key is left as it is, so the rest can be edited by hand in `config/Merged/` (SSGM plugins in `ssgm.ini`, the downloader URL and game definitions in `tt.cfg`, anti-cheat in `data/anticheat.ini`).

### Hooks

Put PowerShell scripts in `config/Scripts/Hooks/<HookName>/`. Besides the base image's hooks, this image fires `PreInstallRenegade` and `PostInstallRenegade` around the install.

## Troubleshooting

- **`always.dat and always2.dat not found`**: the TT package doesn't include them. Copy them from a Renegade install's `Data` folder into `config/Server/data/`, or set `RENEGADE_ARCHIVE_URL`.
- **Two data folders**: Linux treats `Data` and `data` as different folders, but Wine sees only one of them. The install hook puts everything in whichever one `Server/` already has and warns when there are both. Merge them if you see that warning.
- **Nothing in `docker logs` after `Starting: server.exe`**: the server writes no stdout. Its log, `Renegade/FDS/renlog_<M>-<D>-<YYYY>.txt`, appears a few seconds after start. A day's file is appended across restarts; only the current run's lines are shown.
- **Clients can't join**: clients must run the same TT version as the server (`SVER` in the GameSpy reply, e.g. `TT/4.80-r8841`).
- **Checking that it's up**: in GameSpy mode, send `\status\` to the query port. The reply includes the host name, map, players and `SVER`. In LAN mode check that 4848/udp is bound (`/proc/net/udp`, hex `12F0`).
- **Idle use**: about 15% of a CPU core and 500–600 MB of RAM, mostly Wine and Xvfb.
