<div align="center">

# 🚀 İktibas Backend

### Self-Hosted Supabase • Production-Ready • One-Click

[![Website](https://img.shields.io/badge/Website-iktibas.app-blue?style=for-the-badge&logo=google-chrome)](https://iktibas.app)
[![Play Store](https://img.shields.io/badge/Google_Play-Download-green?style=for-the-badge&logo=google-play)](https://play.google.com/store/apps/details?id=app.iktibas.iktibas)
[![Supabase](https://img.shields.io/badge/Supabase-Self--Hosted-3ECF8E?style=for-the-badge&logo=supabase)](https://supabase.com)

**The official backend infrastructure for İktibas app** — A fully automated, production-ready Supabase self-hosted deployment that gets you from zero to production in minutes.

[🌐 Live Demo](https://iktibas.app) • [📱 Mobile App](https://play.google.com/store/apps/details?id=app.iktibas.iktibas) • [📖 Documentation](#-table-of-contents) • [🐛 Report Bug](../../issues)

---

</div>

## ✨ Features

<table>
<tr>
<td width="50%">

### 🎯 **One-Click Deployment**
- Single command setup
- Fully automated bootstrap
- Zero manual configuration
- Idempotent execution

</td>
<td width="50%">

### 🔒 **Production Ready**
- Automatic SSL certificates
- SELinux hardening
- Firewall configuration
- Daily backups

</td>
</tr>
<tr>
<td width="50%">

### 🐳 **Docker Powered**
- Docker Compose orchestration
- Multi-container architecture
- Easy scaling
- Resource isolation

</td>
</tr>
</table>

---

## 📋 Table of Contents

- [⚠️ Before You Deploy](#️-before-you-deploy---customize-for-your-domain)
- [🚀 Quick Start](#-quick-start)
- [📦 What's Included](#-whats-included)
- [🔧 Configuration](#-configuration)
- [📖 How It Works](#-how-it-works)
- [🛠️ Management](#️-management-commands)
- [🔍 Troubleshooting](#-troubleshooting)
- [🤝 Contributing](#-contributing)

---

## ⚠️ Before You Deploy - Customize for Your Domain

> [!IMPORTANT]
> This repository is configured for **iktibas.app** domain. Clone it and customize for your own infrastructure!

### 🎨 **Required Customization Steps**

<details open>
<summary><b>📝 Click to see all files that need customization</b></summary>

<br>

#### **1️⃣ Main Bootstrap Script**
**File:** `boot.sh`
```bash
# Line 9-10: Update these variables
readonly BASE_DIRECTORY="/opt/backend.iktibas.app"  # → /opt/backend.yourdomain.com
readonly DOMAIN="api.iktibas.app"                   # → api.yourdomain.com
```

#### **2️⃣ Nginx Configuration**
**File:** `nginx/api.iktibas.app.conf`
- **Rename:** `api.iktibas.app.conf` → `api.yourdomain.com.conf`
- **Update content:**
```nginx
server_name api.iktibas.app;  # → api.yourdomain.com

ssl_certificate /etc/letsencrypt/live/api.iktibas.app/fullchain.pem;      # → your domain
ssl_certificate_key /etc/letsencrypt/live/api.iktibas.app/privkey.pem;    # → your domain
```

#### **3️⃣ Database Backup Script**
**File:** `scripts/db-backup.sh`
```bash
BACKUP_DIR="/opt/backend.iktibas.app/backups"  # → /opt/backend.yourdomain.com/backups
```

#### **4️⃣ Environment Variables**
**File:** `.env`
```bash
API_EXTERNAL_URL=https://api.iktibas.app  # → https://api.yourdomain.com
SITE_URL=https://iktibas.app              # → https://yourdomain.com
```

#### **5️⃣ Directory Structure**
```
/opt/backend.iktibas.app  →  /opt/backend.yourdomain.com
```

</details>

### ⚡ **Quick Replace (Automated)**

```bash
# Clone the repository
git clone <your-repo-url>
cd backend.iktibas.app

# Replace all domain references
find . -type f -exec sed -i 's/iktibas\.app/yourdomain.com/g' {} +
find . -type f -exec sed -i 's/iktibas/yourappname/g' {} +

# Rename nginx config
mv nginx/api.iktibas.app.conf nginx/api.yourdomain.com.conf

# Move to production location
cd ..
mv backend.iktibas.app backend.yourdomain.com
sudo mv backend.yourdomain.com /opt/
```

**✅ Verify changes:**
```bash
grep -r "iktibas" /opt/backend.yourdomain.com
# Should return no results
```

---

## 🚀 Quick Start

<div align="center">

### **Get from zero to production in 3 minutes**

</div>

```bash
# 1️⃣ Navigate to your deployment directory
cd /opt/backend.yourdomain.com

# 2️⃣ Run the magic script ✨
sudo ./boot.sh

# 3️⃣ That's it! 🎉
```

### **What happens automatically:**

```
🔄 System Update          → Updates packages and dependencies
📦 Base Packages          → Installs essential tools
🐳 Docker Setup           → Installs and configures Docker + Compose
🌐 Nginx Installation     → Sets up reverse proxy
🔐 SELinux Configuration  → Hardens security policies
🔥 Firewall Rules         → Opens required ports (80, 443)
🔒 SSL Certificates       → Obtains Let's Encrypt certificates
⚙️  Nginx Configuration   → Applies production config
📁 Log Directory          → Creates logging infrastructure
⏰ Backup Cron           → Schedules daily backups
🛠️  Supabase CLI          → Installs management tools
📝 Environment Files      → Copies configuration templates
🚀 Docker Compose         → Deploys all services
✅ Health Check           → Verifies deployment
```

---

## 📦 What's Included

### **Architecture Overview**

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                    [Port 443/80]
                         │
                    ┌────▼────┐
                    │  Nginx  │  ← SSL Termination
                    │ Reverse │  ← Load Balancing
                    │  Proxy  │
                    └────┬────┘
                         │
                    [Port 8000]
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
    │  Kong   │    │  Auth   │    │   API   │
    │ Gateway │    │ Service │    │ Service │
    └────┬────┘    └────┬────┘    └────┬────┘
         │               │               │
         └───────────────┼───────────────┘
                         │
                    [Port 5432]
                         │
                   ┌─────▼─────┐
                   │ PostgreSQL│
                   │ Database  │
                   └───────────┘
```

### **Components**

| Component | Version | Purpose |
|-----------|---------|---------|
| 🐘 **PostgreSQL** | Latest | Primary database with extensions |
| 🦍 **Kong** | Latest | API Gateway & routing |
| 🔐 **GoTrue** | Latest | Authentication service |
| 📡 **Realtime** | Latest | WebSocket & subscriptions |
| 📧 **Inbucket** | Latest | Email testing |
| 🎨 **Studio** | Latest | Database management UI |
| 🌐 **Nginx** | Latest | Reverse proxy & SSL |
| 📦 **Docker** | Latest | Container orchestration |

---

## 🔧 Configuration

### **Environment Files**

<details>
<summary><b>📄 .env Configuration</b></summary>

```bash
# Site URLs
SITE_URL=https://yourdomain.com
API_EXTERNAL_URL=https://api.yourdomain.com

# Database
POSTGRES_PASSWORD=your-super-secret-password
POSTGRES_DB=postgres

# JWT Secrets
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters

# SMTP (Optional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password

# Studio
STUDIO_DEFAULT_ORGANIZATION=Your Org
STUDIO_DEFAULT_PROJECT=Your Project
```

</details>

<details>
<summary><b>📄 .env.functions Configuration</b></summary>

```bash
# Supabase Function Environment
VERIFY_JWT=true
```

</details>

### **Directory Structure**

```
/opt/backend.yourdomain.com/
├── 📜 boot.sh                        ← Main bootstrap script
├── 🐳 docker-compose.yml             ← Service definitions
├── 📋 .env                           ← Main configuration
├── 📋 .env.functions                 ← Functions config
├── 🌐 nginx/
│   ├── nginx.conf                   ← Main nginx config
│   └── api.yourdomain.com.conf      ← Site config
├── 📜 scripts/
│   └── db-backup.sh                 ← Backup automation
└── 💾 backups/                       ← Backup storage
```

---

## 📖 How It Works

### **The Bootstrap Process (14 Steps)**

<details>
<summary><b>🔍 Click to see detailed execution flow</b></summary>

<br>

#### **Phase 1: System Preparation**
```
1. ✅ System Update
   • Updates all packages (dnf update -y)
   • Skips if updated within 24h
   • Installs EPEL repository

2. ✅ Base Packages
   • epel-release
   • make
   • policycoreutils-python-utils
```

#### **Phase 2: Container Infrastructure**
```
3. ✅ Docker Installation
   • Adds Docker repository
   • Installs Docker Engine + Compose
   • Configures user groups
   • Starts Docker daemon

4. ✅ Nginx Setup
   • Installs Nginx web server
   • Enables auto-start
   • Initial configuration
```

#### **Phase 3: Security Hardening**
```
5. ✅ SELinux Configuration
   • Adds port 8000 to http_port_t
   • Enables httpd_can_network_connect
   • Skips if disabled

6. ✅ Firewall Configuration
   • Opens port 80 (HTTP)
   • Opens port 443 (HTTPS)
   • Reloads rules
```

#### **Phase 4: SSL & Web Server**
```
7. ✅ SSL Certificates
   • Installs Certbot
   • Obtains Let's Encrypt cert
   • Configures auto-renewal

8. ✅ Nginx Configuration
   • Symlinks configs
   • Validates syntax
   • Reloads service
```

#### **Phase 5: Application Deployment**
```
9. ✅ Log Directory
   • Creates /var/log/supabase
   • Sets permissions

10. ✅ Backup Automation
    • Configures daily cron job
    • Sets up at 3:00 AM

11. ✅ Supabase CLI
    • Downloads v2.60.0
    • Installs from GitHub
    • Cleans up files

12. ✅ Environment Setup
    • Copies .env.example
    • Copies .env.functions.example

13. ✅ Docker Deployment
    • Pulls images
    • Starts services
    • Waits for init (60s)

14. ✅ Health Check
    • Tests HTTPS endpoint
    • Validates SSL
    • Shows status
```

</details>

### **Idempotency & Safety**

The script is **fully idempotent** — run it as many times as you want:

```bash
# Run again - only missing steps execute
sudo ./boot.sh

=== Docker ===
[SKIP]    Docker already installed and running

=== SSL Certificate ===
[SKIP]    SSL certificate already exists

=== Docker Compose ===
[SKIP]    Services already running
```

**Management Commands:**

```bash
# Check current status
sudo ./boot.sh --status

# Show help
sudo ./boot.sh --help
```

---

## 🛠️ Management Commands

### **📊 Service Status**

```bash
# All services
cd /opt/backend.yourdomain.com
docker compose ps

# Specific service logs
docker compose logs -f postgres
docker compose logs -f kong
docker compose logs -f auth

# Nginx logs
journalctl -u nginx -f

# Backup logs
tail -f /var/log/supabase/db-backup.log
```

### **🔄 Service Control**

```bash
cd /opt/backend.yourdomain.com

# Stop all
docker compose down

# Start all
docker compose up -d

# Restart specific service
docker compose restart kong

# Rebuild and restart
docker compose up -d --build

# View resource usage
docker stats
```

### **🔐 SSL Management**

```bash
# Test certificate renewal
certbot renew --dry-run

# Force renewal
certbot renew

# Check expiry
certbot certificates

# Auto-renewal is configured via systemd
systemctl list-timers | grep certbot
```

### **💾 Backup & Restore**

```bash
# Manual backup
/opt/backend.yourdomain.com/scripts/db-backup.sh

# List backups
ls -lh /opt/backend.yourdomain.com/backups/

# Restore from backup
docker compose exec postgres psql -U postgres < backup.sql

# Backup logs
tail -f /var/log/supabase/db-backup.log
```

---

## 🔍 Troubleshooting

<details>
<summary><b>🐛 Common Issues & Solutions</b></summary>

<br>

### **Issue 1: Docker Permission Denied**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker ps
```

### **Issue 2: Nginx Config Test Failed**
```bash
# Test configuration
nginx -t

# Fix deprecated http2 directive
# Change: listen 443 ssl http2;
# To:     listen 443 ssl;
#         http2 on;

# Reload after fix
systemctl reload nginx
```

### **Issue 3: SSL Certificate Failed**
```bash
# Check DNS
nslookup api.yourdomain.com

# Verify ports open
firewall-cmd --list-all

# Manual certificate
certbot certonly --nginx -d api.yourdomain.com

# Check logs
journalctl -u certbot -f
```

### **Issue 4: Docker Compose Won't Start**
```bash
# Check environment files
cat .env | grep -v "^#"

# View error logs
docker compose logs

# Restart clean
docker compose down
docker compose up -d

# Check individual services
docker compose ps
```

### **Issue 5: Database Connection Failed**
```bash
# Check PostgreSQL logs
docker compose logs postgres

# Verify password in .env
grep POSTGRES_PASSWORD .env

# Test connection
docker compose exec postgres psql -U postgres

# Restart database
docker compose restart postgres
```

### **Issue 6: Health Check Failed**
```bash
# Manual test
curl -I https://api.yourdomain.com

# Check Kong gateway
docker compose logs kong

# Verify nginx upstream
nginx -T | grep upstream

# Check all service health
docker compose ps
```

</details>

### **🆘 Get Help**

```bash
# Check bootstrap status
sudo ./boot.sh --status

# View all logs
docker compose logs --tail=100

# System status
systemctl status nginx
systemctl status docker
firewall-cmd --list-all
```

---

## 📊 Ports & Services

| Port | Service | Access | Purpose |
|------|---------|--------|---------|
| **80** | Nginx | Public | HTTP → HTTPS redirect |
| **443** | Nginx | Public | HTTPS traffic |
| **8000** | Kong | Internal | API Gateway |
| **5432** | PostgreSQL | Internal | Database |
| **9000** | Studio | Internal | Admin panel |
| **8000** | Backend | Internal | Application server |

---

## 🔒 Security Features

- ✅ **SSL/TLS Encryption** — Automatic Let's Encrypt certificates
- ✅ **SELinux Hardening** — Enhanced security policies
- ✅ **Firewall Rules** — Only required ports exposed
- ✅ **Automated Backups** — Daily database snapshots
- ✅ **User Isolation** — Non-root Docker execution
- ✅ **Secrets Management** — Environment-based configuration
- ✅ **Rate Limiting** — Kong gateway protection
- ✅ **HTTPS Only** — Force SSL redirection

---

## 🚀 Production Checklist

Before going live, verify:

- [ ] ✅ Domain DNS configured correctly
- [ ] ✅ SSL certificate obtained and valid
- [ ] ✅ Environment variables updated with secure values
- [ ] ✅ Firewall rules configured (ports 80, 443 open)
- [ ] ✅ All services running (`docker compose ps`)
- [ ] ✅ Health check passing (`curl https://api.yourdomain.com`)
- [ ] ✅ Backup script tested manually
- [ ] ✅ Nginx configuration validated (`nginx -t`)

---

## 🤝 Contributing

We welcome contributions! Here's how:

1. 🍴 Fork the repository
2. 🔧 Create a feature branch (`git checkout -b feature/amazing`)
3. ✅ Test your changes thoroughly
4. 💾 Commit your changes (`git commit -am 'Add amazing feature'`)
5. 📤 Push to the branch (`git push origin feature/amazing`)
6. 🎉 Open a Pull Request

### **Development Setup**

```bash
# Clone your fork
git clone https://github.com/yourusername/iktibas-backend
cd iktibas-backend

# Make changes
vim boot.sh

# Test locally
sudo ./boot.sh

# Verify
sudo ./boot.sh --status
```

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🌟 Acknowledgments

- **[Supabase](https://supabase.com)** — The open source Firebase alternative
- **[Docker](https://docker.com)** — Container platform
- **[Nginx](https://nginx.org)** — High-performance web server
- **[Let's Encrypt](https://letsencrypt.org)** — Free SSL certificates

---

## 🔗 Links

<div align="center">

[![Website](https://img.shields.io/badge/🌐_Website-iktibas.app-blue?style=for-the-badge)](https://iktibas.app)
[![Play Store](https://img.shields.io/badge/📱_Download-Google_Play-green?style=for-the-badge)](https://play.google.com/store/apps/details?id=app.iktibas.iktibas)
[![Issues](https://img.shields.io/badge/🐛_Report-Issues-red?style=for-the-badge)](../../issues)
[![Docs](https://img.shields.io/badge/📖_Read-Documentation-yellow?style=for-the-badge)](#-table-of-contents)

</div>

---

<div align="center">

### **Made with ❤️ by the @saidtaylan**

**⭐ Star this repo if you find it helpful!**

[🏠 Home](https://iktibas.app) • [📱 App](https://play.google.com/store/apps/details?id=app.iktibas.iktibas) • [🐛 Report Bug](../../issues) • [💡 Request Feature](../../issues)

</div>