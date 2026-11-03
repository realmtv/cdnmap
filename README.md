# 🕷️ CDN Mapper Daemon (`cdnmap`)

**Version:** 1.0.4 | **License:** MIT | **Platform:** Docker (Linux / Windows) & Python CLI

An enterprise-grade, automated NetDevOps pipeline and CLI utility designed to accurately resolve IP addresses and domains for specific services based on **your localized network environment**. It is highly optimized for generating precise, compact whitelists for routing traffic through VPN tunnels (e.g., in MikroTik RouterOS) without overloading your hardware.

---

## 💡 Why use this?

Existing static CDN lists found on GitHub are often outdated or contain broad global IP blocks that do not match your local GeoDNS/Anycast resolution. Relying on massive generic subnets leads to:

1. **Suboptimal Routing:** Connecting to a distant global CDN node instead of the nearest edge cache node assigned to your ISP/VPS, heavily slowing down media stream latency.
2. **Router Overload:** Injecting thousands of direct static entries into a MikroTik `Mangle` table spikes CPU utilization due to heavy packet filtering overhead.
3. **Over-blocking:** Overlapping entire subnets might accidentally route legitimate domestic traffic through the tunnel.

### ⚡ How `cdnmap` Solves It
Our engine emulates organic browser behavior. It doesn't just query DNS; it follows HTTP redirects and scans page content (HTML) to find "hidden" asset hosts (images, fonts, scripts) that are only revealed after navigation. 

Running as a lightweight persistent Docker background daemon, it uses a multi-iteration **Monitor Mode ("snowball effect")** to accumulate dynamic Anycast IP rotations over time. Finally, it collapses discovered fragments into ultra-compact, routing-friendly `/24` and `/23` CIDR blocks, keeping your firewall rules clean, lean, and lightning-fast.

---

## 🏗️ Architecture Design

```text
               ┌────────────────────────────────────────────────────────┐
               │                     VPN SERVER / VPS                   │
               │                                                        │
┌──────────┐   │   ┌──────────────┐      ┌─────────────┐                │
│ GitHub   ├───┼──>│  start.sh    │─────>│ targets.json│                │
│ Registry │   │   │  (Bootstrap) │      │ (Target Map)│                │
└──────────┘   │   └──────┬───────┘      └──────┬──────┘                │
               │          │                     │                       │
               │          ▼                     ▼                       │
               │   ┌──────────────┐      ┌─────────────┐                │   SSH Tunnel    ┌──────────────┐
               │   │    .env      │─────>│ Docker-Alpine│───────────────┼────────────────>│   MikroTik   │
               │   │ (Local Creds)│      │  (Python)   │ (Inline Pipe)  │                 │  RouterOS    │
               │   └──────────────┘      └─────────────┘                │                 └──────────────┘
               └────────────────────────────────────────────────────────┘
```

---

## 🚀 Core Features

* **📦 Unified Multi-Target Architecture:** One lightweight container handles an infinite number of target services cleanly over isolated configurations via a central JSON ledger.
* **🕵️‍♂️ Dual-Engine Operation:**
  * `crawl` (Websites mode): Traces HTTP redirects, dissects HTML payloads, and automatically extracts hidden static infrastructure origins (e.g., `://ytimg.com`).
  * `dns_only` (Applications mode): Skips transport overhead entirely to run raw, fast, multi-iteration DNS resolution on an explicit list of subdomains—optimized for binary clients like Discord or Telegram.
* **✨ Deduplication & Aggregation:** Automatically collapses discovered IPs into a clean list of unique subnets using your custom cluster mathematical framework.
* **🛡️ Zero-Leak Secrets Management:** Highly secure orchestration separating production assets from private credentials via locally generated `.env` environments (safely bypassed by `.gitignore`).
* **📡 Zero-Overhead Remote Injection:** Executes automated, multi-line deployment via optimized, silent SSH inline pipelines (`"$(cat commands.txt)"`) directly into MikroTik RouterOS without leaving file residue.

---

## 💻 CLI Usage (Manual / Standalone Mode)

You can run the core script manually on any machine with Python 3 installed. No external dependencies required—uses only standard library modules.

### 📋 CLI Arguments Reference

| Argument | Long Flag | Type | Description |
|----------|-----------|------|-------------|
| `domain` | *None* | `str` | Target domain to scan (e.g., `youtube.com`). Optional if `--list` is used. |
| `-v` | `--version` | *Flag* | Show program version (`1.0.4`) and exit. |
| `-o` | `--output` | `str` | Output results to a text file (e.g., `output.txt`). |
| `-m` | `--mikrotik`| `str` | Name of MikroTik address list. If omitted, generates verbose output. Accepts optional value for custom list name. |
| `-i` | `--iterations`| `int` | Number of scanning iterations in Monitor Mode [default: 1]. |
| `-d` | `--delay` | `int` | Delay in seconds between iterations [default: 0]. |
| *None* | `--list` | `str` | Comma-separated list of subdomains for `dns_only` mode (bypasses HTTP crawl). |

*Note: The flag `-d` / `--delay` cannot be used alone. It requires `-i` / `--iterations` with a value greater than 1.*

### 📝 Standalone Command Examples

**Basic scan (verbose output to console):**
```powershell
python cdnmap.py youtube.com
```

**Export verbose results to a local file:**
```powershell
python cdnmap.py youtube.com -o cdn_ips.txt
```

**Generate active MikroTik script for console output:**
```powershell
python cdnmap.py youtube.com -m address-list-youtube
```

**Accumulative monitoring: 20 iterations with a 5-second pause, output raw RouterOS commands:**
```powershell
python cdnmap.py youtube.com -i 20 -d 5 -m address-list-youtube
```

**Monitor mode with file export and custom list name:**
```powershell
python cdnmap.py instagram.com -i 10 -d 3 -m address-list-instagram -o instagram_rules.txt
```

---

## ⚙️ Configuration & Tuning (Daemon Mode)

When running inside the continuous background Docker container, all operational behaviors are centralized across two files:

### ⏱️ Runtime Variables (`docker-compose.yml`)
You can adjust these parameters under the `environment` section to balance deep bandwidth accumulation with server/router resource usage:
* **`ITERATIONS=20`** — How many consecutive DNS query cycles the daemon runs per target during a single execution. Higher values (20–50) build a stronger "snowball effect" to capture highly volatile Anycast IP rotations.
* **`DELAY=5`** — The delay in seconds between each iteration loop. A 5-second window gives the upstream CDN load balancer enough time to rotate IP addresses in its response pool.
* **`RUN_INTERVAL=86400`** — The time in seconds the container sleeps before repeating the entire target map loop. `86400` seconds equals exactly **24 hours**, forcing a clean automated synchronization once a day.

### 🌐 Global Target Map (`targets.json`)
Modify this ledger file directly on your server to append new blocks or update core tracking variables:
```json
{
  "youtube": {
    "mode": "crawl",
    "target": "youtube.com",
    "address_list": "address-list-youtube"
  },
  "instagram": {
    "mode": "crawl",
    "target": "instagram.com",
    "address_list": "address-list-instagram"
  },
  "discord": {
    "mode": "dns_only",
    "target": "discord.com,discordapp.com,discordapp.net,discord.gg,discordapp.com,gateway.discord.gg,discord.media",
    "address_list": "address-list-discord"
  }
}
```

---

## 🛠️ Out-of-the-Box Automated Deployment

The repository includes intelligent bootstrap masters that fully automate Docker installation, handle Windows line endings cleanup, configure local secure secret files, and manage automated SSH identity key generation on the fly.

### 🏁 Deploying on Linux / VPS
Bring up the complete production pipeline on an empty VPS using just **three straightforward shell commands**:

```bash
# 1. Cleanly clone the sterile repository into your target space
cd /app && rm -rf cdnmap
git clone https://github.com && cd cdnmap

# 2. Grant explicit execution permissions to the bootstrap script
chmod +x start.sh

# 3. Initialize the interactive daemon wizard
./start.sh
```

### 🪟 Deploying on Windows
For desktop environments running Docker Desktop, simply initialize the system by executing the native batch setup script:
```powershell
.\start.bat
```

> ⚠️ **Note on SSH Keys:** If administrative SSH private identity keys (`id_rsa`) are missing on your host machine, the setup wizard automatically generates a secure 2048-bit key pair and outputs the exact configuration command to paste into your MikroTik WinBox Terminal to finish user-to-key binding.

---

## 📊 Verification & Diagnostics

### Checking Container Logs
Review real-time sequencing metrics, active processing passes, and execution loops across targets via Docker Compose:
```bash
docker compose logs -f
```

### Checking RouterOS State
To inspect the static address blocks safely applied inside your router, log into your MikroTik Terminal and query the corresponding firewall lists:
```routeros
/ip firewall address-list print where list~"address-list"
```
