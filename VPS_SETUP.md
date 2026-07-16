# Running Claude Code on the VPS

This guide sets up **Claude Code directly on the VPS** that hosts the Black Ops
Gunfight server, so it has a real shell on the box — it can pull this repo,
place the mod files, and restart the Plutonium server (a **systemd** service).

> **Why on the VPS and not from the web session?** Claude Code on the web runs
> in a sandboxed, ephemeral container with locked-down egress — it can't open an
> SSH connection to your VPS. Installing the CLI on the VPS itself gives Claude
> a genuine shell there, which is the setup you actually want for server control.

---

## 1. Prerequisites

On the VPS you need:

- A 64-bit Linux host (the same box the Plutonium server runs on)
- **Node.js 18 or newer** and `git`
- SSH access from your own machine
- A **dedicated, non-root user** to run the agent (see §2 — do **not** run it as root)

Check what's already there:

```bash
node --version   # want v18+
git --version
```

Install Node if it's missing (Debian/Ubuntu example):

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs git
```

---

## 2. Create a dedicated deploy user

Give the agent its own account with only the access it needs — never root.

```bash
# as root / sudo:
sudo adduser --disabled-password --gecos "" gunfight-deploy

# let it read/write the server's mod directory (adjust group/path to your setup)
sudo usermod -aG plutonium gunfight-deploy
```

Scope its ability to restart the server to exactly one service via sudoers —
so it can bounce the game server but nothing else:

```bash
# create /etc/sudoers.d/gunfight-deploy  (edit with: sudo visudo -f /etc/sudoers.d/gunfight-deploy)
gunfight-deploy ALL=(root) NOPASSWD: /bin/systemctl restart plutonium-t5.service, \
                                     /bin/systemctl stop plutonium-t5.service, \
                                     /bin/systemctl start plutonium-t5.service, \
                                     /bin/systemctl status plutonium-t5.service, \
                                     /bin/journalctl -u plutonium-t5.service *
```

> Replace `plutonium-t5.service` with your actual unit name (`systemctl list-units --type=service | grep -i pluto`).

---

## 3. Install Claude Code

Switch to the deploy user and install the CLI:

```bash
sudo -iu gunfight-deploy
npm install -g @anthropic-ai/claude-code
claude --version
```

If you can't install globally without root, install into the user's home
instead of using `sudo`:

```bash
npm config set prefix "$HOME/.npm-global"
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
npm install -g @anthropic-ai/claude-code
```

---

## 4. Authenticate

```bash
claude
```

On first run it walks you through login. On a **headless VPS** (no browser), it
prints a URL — open it on your laptop, approve, and paste the code back. Or set
an API key non-interactively:

```bash
export ANTHROPIC_API_KEY=sk-ant-...      # add to ~/.bashrc to persist
```

---

## 5. Clone this repo on the VPS

```bash
cd ~
git clone https://github.com/KL9modz/BO1-Gunfight.git
cd BO1-Gunfight
claude          # start working — Claude now has a shell in the repo on the VPS
```

Claude Code **prompts before running commands** by default. Keep that on until
you trust the workflow; then you can relax it with `/permissions` for specific
safe commands (e.g. `git pull`, the deploy script).

---

## 6. Updating the server (pull → place → restart)

The mod ships as two things in this repo:

| Path | What it is | Where it goes on the server |
|---|---|---|
| `mod.ff` | Compiled Plutonium T5 fastfile | your server's mod folder |
| `maps/mp/gametypes/*.gsc` | Gunfight GSC source | your server's raw `scripts` overlay |

`scripts/deploy.sh` in this repo does the full update in one step: `git pull`,
copy those files into the server's directories, then `systemctl restart` the
service. **Open it and set the three paths at the top for your box first**
(they're placeholders — I can't know your exact Plutonium install path):

```bash
nano scripts/deploy.sh     # set SERVICE_NAME, MOD_DIR, SCRIPTS_DIR
./scripts/deploy.sh
```

Once configured, your day-to-day loop is just:

```bash
./scripts/deploy.sh        # pulls latest release and restarts the server
```

Check it came back up and tail logs:

```bash
sudo systemctl status plutonium-t5.service
sudo journalctl -u plutonium-t5.service -n 100 -f
```

---

## 7. Security checklist

- ✅ Agent runs as `gunfight-deploy`, **not root**
- ✅ `sudo` limited to the one game-server service via `/etc/sudoers.d/`
- ✅ Command approval prompts left on until the flow is trusted
- ✅ No secrets committed to the repo — keep `ANTHROPIC_API_KEY` in the shell env
- ✅ Firewall (`ufw`/security group) exposes only the game + SSH ports you need
```
