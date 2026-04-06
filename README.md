# That GD Poker Suite

(wip, not playable yet) A web-capable multiplayer poker suite built with Godot
4.6. Supports up to 5 players across three variants: Texas Hold'em, 5-Card
Draw, and 7-Card Stud. All games use antes only — no blinds.

## Playing locally (same PC)

```bash
godot --path .   # terminal 1 — enter a name, click Host
godot --path .   # terminal 2 — enter a name, leave IP blank, click Join
```

## Hosting for friends over the internet

Friends play in their browser. You run the game natively as the server.

### Prerequisites

- [Docker](https://docs.docker.com/engine/install/) with the Compose plugin
- Port **22888** forwarded on your router to this machine
- Godot 4.6.1 with the **Web export template** installed

### One-time setup

**1. Configure the cert path** by copying the example env file and setting your platform's path:

```bash
cp nginx/.env.example nginx/.env
# then edit nginx/.env and set CERTS_PATH
```

**2. Generate a TLS certificate** (self-signed — friends will see a one-time
browser warning):

Linux / macOS:
```bash
mkdir -p ~/.local/share/that-gd-poker-suite/nginx/certs
openssl req -x509 -newkey rsa:4096 \
  -keyout ~/.local/share/that-gd-poker-suite/nginx/certs/key.pem \
  -out    ~/.local/share/that-gd-poker-suite/nginx/certs/cert.pem \
  -days 365 -nodes -subj '/CN=poker'
```

Windows (PowerShell — `openssl` is included with [Git for Windows](https://git-scm.com/)):
```powershell
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\that-gd-poker-suite\nginx\certs"
openssl req -x509 -newkey rsa:4096 `
  -keyout "$env:LOCALAPPDATA\that-gd-poker-suite\nginx\certs\key.pem" `
  -out    "$env:LOCALAPPDATA\that-gd-poker-suite\nginx\certs\cert.pem" `
  -days 365 -nodes -subj '/CN=poker'
```

Set `CERTS_PATH` in `nginx/.env` to match whichever path you used above.

**3. Export the web build** in the Godot editor:

- Project → Export → Web
- Export path: `web-export/index.html`

**4. Start nginx:**

```bash
docker compose -f nginx/docker-compose.yml up -d
```

### Every session

1. Run `godot --path .`, enter your name, configure the game, click **Host**
2. Share your public IP with friends
3. Friends open `https://[your-public-ip]:22888` in their browser
4. They click **Advanced → Accept the Risk**, enter your IP, click **Join**

### Stopping the server

```bash
docker compose -f nginx/docker-compose.yml down
```

### Re-deploying after a code change

```bash
# In the Godot editor: Project → Export → Web (overwrite web-export/)
docker compose -f nginx/docker-compose.yml restart   # picks up the new files immediately
```

## Project structure

```
autoloads/       CardDB, NetworkManager, GameManager, Preloader
core/            Deck, HandEvaluator, PlayerState
games/           BaseGame, FiveCardDraw, TexasHoldem, SevenCardStud
ui/              CardView, PlayerSeat, BettingControls
scenes/          main_menu, lobby, game_table
assets/suits/    SVG suit symbols (heart, diamond, spade, club)
nginx/           nginx reverse-proxy config and docker-compose.yml
web-export/      Godot HTML5 export output (not in git)
```

## Architecture notes

- **Host-as-server**: the player who clicks Host is peer_id 1 and runs all game logic server-side. Clients receive state via RPCs.
- **Single port**: nginx on `:22888` serves the web build over HTTPS and proxies WebSocket (`/ws`) to the Godot server on `localhost:22889`.
- **Antes only**: all variants collect an ante before each hand. No big blind / small blind.
