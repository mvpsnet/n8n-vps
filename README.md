# 🚀 One-Click n8n Installer for Debian 12 & 13

[![Debian](https://img.shields.io/badge/Debian-12%20%7C%2013-orange?logo=debian&logoColor=white)](https://www.debian.org/)
[![Docker](https://img.shields.io/badge/Docker-Automated-blue?logo=docker)](https://www.docker.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![n8n](https://img.shields.io/badge/n8n-Automation-red?logo=n8n)](https://n8n.io/)
[![MVPS.net](https://img.shields.io/badge/Optimized%20for-MVPS.net-blueviolet)](https://www.mvps.net)

---

This repository provides a **simple one-click installer** that deploys **n8n** on any **Debian 13 (Trixie)** or **Debian 12 (Bookworm)** VPS.

### ✨ Features

- 🔍 Automatically detects your server’s **primary IP**
- 🌐 Uses the **reverse DNS (rDNS)** as hostname  
- 🔒 Installs **Traefik**, **PostgreSQL**, and **n8n** in Docker
- 🧾 Issues a **free SSL certificate** via **Let’s Encrypt**
- 🔁 Includes **Watchtower** for automatic container updates

---

## ⚙️ Installation

Run this command as **root** (or with `sudo`):

```bash
curl -fsSL https://raw.githubusercontent.com/mvpsnet/n8n-vps/refs/heads/main/install-n8n-debian.sh | bash

```

## 💡 Looking for a VPS?

If you need a reliable and affordable VPS to run your n8n instances:  
👉 [**MVPS.net**](https://www.mvps.net) — High Performance European VPS Hosting.

- ⚡ Instant setup in multiple EU locations  
- 💾 NVMe storage  
- 💡 Perfect for automation, bots, APIs, and integrations

