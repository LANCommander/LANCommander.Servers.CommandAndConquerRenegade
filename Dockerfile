# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

# ----------------------------
# Server settings
#   - The server is the Tiberian Technologies (TT) Renegade server, a Windows-only build of the
#     Free Dedicated Server with the TT patch and SSGM. A hook downloads RENEGADE_SERVER_URL into
#     /config/Server on first start, and again when the URL changes. Keep it on the same TT
#     version as your clients (4.8 = build b8841)
#   - The TT package has no always.dat/always2.dat. They come from the retail game: put them in
#     /config/Server/data, put a whole Renegade install in /config/Server, or set
#     RENEGADE_ARCHIVE_URL to a zip of one (e.g. a LANCommander archive)
#   - The RENEGADE_* settings are written to server.ini, data/<RENEGADE_CONFIG> and tt.cfg on
#     every start
#   - RENEGADE_MAPS: comma-separated rotation (names with or without .mix); empty keeps tt.cfg's
#   - server.exe is a GUI program, so it runs under Xvfb (WINE_XVFB=auto); its log
#     (Renegade/FDS/renlog_*.txt) is followed into `docker logs`
# ----------------------------
ENV RENEGADE_SERVER_URL="https://www.tiberiantechnologies.org/files/server-4.8.zip" \
    RENEGADE_SERVER_SHA256="a3642e0ad5c3ecc7ba88e41af142f398eea6f47686abeb4f87a5f449faef6036" \
    RENEGADE_ARCHIVE_URL="" \
    RENEGADE_GAME_TYPE="LAN" \
    RENEGADE_CONFIG="svrcfg_cnc.ini" \
    RENEGADE_SERVER_NAME="Renegade Server" \
    RENEGADE_MOTD="" \
    RENEGADE_PASSWORD="" \
    RENEGADE_MAX_PLAYERS="32" \
    RENEGADE_TIME_LIMIT="30" \
    RENEGADE_STARTING_CREDITS="0" \
    RENEGADE_RADAR_MODE="1" \
    RENEGADE_FRIENDLY_FIRE="false" \
    RENEGADE_TEAM_CHANGING="false" \
    RENEGADE_REMIX_TEAMS="true" \
    RENEGADE_SPAWN_WEAPONS="true" \
    RENEGADE_CAN_REPAIR_BUILDINGS="true" \
    RENEGADE_DRIVER_IS_GUNNER="true" \
    RENEGADE_BASE_DESTRUCTION_ENDS_GAME="true" \
    RENEGADE_BEACON_ENDS_GAME="true" \
    RENEGADE_MAPS="" \
    RENEGADE_PORT="4848" \
    RENEGADE_QUERY_PORT="25300" \
    RENEGADE_REMOTE_ADMIN_PASSWORD="" \
    RENEGADE_REMOTE_ADMIN_PORT="" \
    RENEGADE_REMOTE_ADMIN_IP="127.0.0.1" \
    RENEGADE_WOL_NICKNAME="" \
    RENEGADE_WOL_PASSWORD="" \
    RENEGADE_WOL_SERIAL="" \
    RENEGADE_WOL_LOGIN_SERVER="" \
    WINE_XVFB="auto" \
    START_EXE="/usr/local/bin/renegade-server" \
    START_ARGS=""

COPY Scripts/renegade-server /usr/local/bin/renegade-server
RUN chmod +x /usr/local/bin/renegade-server

COPY Hooks/ "${BASE_HOOKS}/"

# 4848/udp:  game (RENEGADE_PORT; in GameSpy mode also the GameSpy game port)
# 3373/udp:  bound in LAN mode (fixed; LAN game listing)
# 25300/udp: GameSpy query (RENEGADE_QUERY_PORT, GameSpy mode)
# 4849/udp:  RenRem remote admin (RENEGADE_REMOTE_ADMIN_PORT, default game port + 1; only bound
#            when RENEGADE_REMOTE_ADMIN_PASSWORD is set, on 127.0.0.1 unless
#            RENEGADE_REMOTE_ADMIN_IP says otherwise)
EXPOSE 4848/udp 3373/udp 25300/udp 4849/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
