---
name: vps-three-ips-dont-confuse-vnc-with-vm
description: "Three different IPs are in play for VPS ops (your own egress IP, the VM's real network IP, the Contabo VNC/KVM console IP) — mixing up the VNC IP for the VM's IP burns a whole troubleshooting session chasing a phantom firewall problem."
metadata:
  node_type: memory
  type: project
  originSessionId: 7f4bd533-59b5-465a-ae81-8754a2a66edb
---

Three IPs matter for VPS ops, and they are **not interchangeable**:

| IP | What it is | What answers there |
|---|---|---|
| `<admin-home-ip>` | **Your own home egress IP** (whoever is doing ops — check live via `curl https://api.ipify.org`, it can rotate) | N/A — this is the *source*, not a destination |
| `<vps-ip>` | **The VM's actual network IP** ([[vps-server-provisioned]]) | SSH (22), RDP (3389), the game (UDP 28960), HTTPS/panel, everything the mod/server actually does |
| `<vnc-console-ip>:<vnc-port>` | **Contabo's out-of-band VNC/KVM console** — a hypervisor-level management interface, separate infrastructure from the VM's own NIC | Only the VNC protocol on `<vnc-port>`. It is NOT a general gateway to the VM's other ports. |

⚠ **The placeholders are the point of this note, not a redaction that costs it anything** — the lesson
is that three addresses fill three distinct *roles*, and the roles are what get confused. Where to get
each real value: `<vps-ip>` is the *Target box* table in `docs/VPS_DEPLOY.md` (its one canonical
declaration); `<admin-home-ip>` and `<vnc-console-ip>:<vnc-port>` are in the gitignored
`tools/ops.local.json` (template `tools/ops.local.json.example`) and are deliberately absent from every
tracked file — a home IP identifies a house, and the VNC console bypasses Windows Firewall.

**The trap (live 2026-07-24):** SSH had been deliberately disabled on the VM in favor of driving the
box via the `gf-vps` Claude Code Remote Control session. Re-enabling direct SSH access got pointed at
the **VNC-console** address (pulled from the CLAUDE.md VNC-console line by pattern-matching "the VPS's
IP") instead of `<vps-ip>`. Every symptom that followed was consistent with a firewall block — SSH/RDP/HTTPS/game
port all timed out, port 80 gave an instant refuse — and a whole session was spent chasing it: enabling a
scoped Windows Firewall rule, confirming `sshd` was running, disabling the Contabo panel firewall entirely.
**None of it was the problem.** A `pktmon` capture run ON THE BOX during a live connection attempt proved
it conclusively: zero packets ever arrived for a connection to the VNC-console address, while a real,
already-working SSH session between `<admin-home-ip>` and `<vps-ip>` was sitting right there in the same
capture. Switching the target to `<vps-ip>` connected instantly.

**The embarrassing part:** the local `~/.ssh/config` already had a correct, working alias the whole
time —
```
Host gf-vps
    HostName <vps-ip>          # real value: the Target box table in docs/VPS_DEPLOY.md
    User Administrator
    IdentityFile ~/.ssh/gf_vps
    IdentitiesOnly yes
```
`ssh gf-vps` (or `scp gf-vps:...`) would have worked from the very first attempt. **Rule: use the `gf-vps`
SSH alias, never hand-type an IP for this box.** (That rule is now also why the repo's docs carry
`<vps-ip>` rather than restating the literal — there is exactly one place to look it up, and every `ssh`
line in the tree uses the alias.) If a connection to the VM times out, check which IP is actually being
dialed before touching any firewall — the **VNC console** address is VNC-console-only and will never
answer SSH/RDP/HTTPS/game-port traffic no matter what's open on the VM side.

**Secondary gotcha hit in the same session — Windows `scp` + Windows-style remote paths:** `scp
gf-vps:C:\work\file.bundle ./local` and `scp -O gf-vps:'C:\work\file.bundle' ./local` both fail
(`protocol error: filename does not match request` / `No such file or directory`) against this box's
Win32-OpenSSH server. Workaround that always works: pipe bytes over `ssh` instead of using `scp`'s own
transfer protocol —
```bash
ssh gf-vps '[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\work\file.bundle"))' | tr -d '\r\n' > file.b64
base64 -d file.b64 > file.bundle
```

**Cleanup owed from this incident** (left open, not yet reverted): the Contabo panel-level firewall was
disabled entirely (not just scoped), and a Windows Firewall rule `SSH-Temp-KL-Home` (TCP 22, RemoteAddress
`<admin-home-ip>`) was added alongside the existing disabled `SSH-Any-In (travel)` rule. Neither was
actually necessary to fix the connectivity (the IP was the whole bug) — worth re-tightening both once
confirmed no longer needed, per the project's stated security posture of key-only SSH deliberately turned
off in favor of the Remote Control session.
