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
| `76.167.246.191` | **Your own home egress IP** (whoever is doing ops — check live via `curl https://api.ipify.org`, it can rotate) | N/A — this is the *source*, not a destination |
| `94.72.121.4` | **The VM's actual network IP** ([[vps-server-provisioned]]) | SSH (22), RDP (3389), the game (UDP 28960), HTTPS/panel, everything the mod/server actually does |
| `144.126.146.144:63019` | **Contabo's out-of-band VNC/KVM console** — a hypervisor-level management interface, separate infrastructure from the VM's own NIC | Only the VNC protocol on `:63019`. It is NOT a general gateway to the VM's other ports. |

**The trap (live 2026-07-24):** SSH had been deliberately disabled on the VM in favor of driving the
box via the `gf-vps` Claude Code Remote Control session. Re-enabling direct SSH access got pointed at
`144.126.146.144` (pulled from the CLAUDE.md VNC-console line by pattern-matching "the VPS's IP") instead
of `94.72.121.4`. Every symptom that followed was consistent with a firewall block — SSH/RDP/HTTPS/game
port all timed out, port 80 gave an instant refuse — and a whole session was spent chasing it: enabling a
scoped Windows Firewall rule, confirming `sshd` was running, disabling the Contabo panel firewall entirely.
**None of it was the problem.** A `pktmon` capture run ON THE BOX during a live connection attempt proved
it conclusively: zero packets ever arrived for a connection to `.144`, while a real, already-working SSH
session between `76.167.246.191` and `94.72.121.4` was sitting right there in the same capture. Switching
the target to `94.72.121.4` connected instantly.

**The embarrassing part:** the local `~/.ssh/config` already had a correct, working alias the whole
time —
```
Host gf-vps
    HostName 94.72.121.4
    User Administrator
    IdentityFile ~/.ssh/gf_vps
    IdentitiesOnly yes
```
`ssh gf-vps` (or `scp gf-vps:...`) would have worked from the very first attempt. **Rule: use the `gf-vps`
SSH alias, never hand-type an IP for this box.** If a connection to the VM times out, check which IP is
actually being dialed before touching any firewall — `144.126.146.144` is VNC-console-only and will never
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
`76.167.246.191`) was added alongside the existing disabled `SSH-Any-In (travel)` rule. Neither was
actually necessary to fix the connectivity (the IP was the whole bug) — worth re-tightening both once
confirmed no longer needed, per the project's stated security posture of key-only SSH deliberately turned
off in favor of the Remote Control session.
