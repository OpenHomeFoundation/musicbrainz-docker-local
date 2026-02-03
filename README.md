# MusicBrainz Mirror Setup Guide
## Open Home Foundation - Music Assistant Project

Complete setup guide for deploying a production-ready MusicBrainz mirror.

**Important:** This `local` folder must be placed inside the official [musicbrainz-docker](https://github.com/metabrainz/musicbrainz-docker) repository.

---

## Table of Contents

1. [Overview](#overview)
2. [Hardware Requirements](#hardware-requirements)
3. [Quick Start](#quick-start)
4. [Server Preparation](#server-preparation)
5. [Configuration](#configuration)
6. [Deployment](#deployment)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Troubleshooting](#troubleshooting)
9. [Backup & Recovery](#backup--recovery)
10. [Updating](#updating)

---

## Overview

### What This Setup Provides

- **Full MusicBrainz Mirror**: Complete read-only replica of the MusicBrainz database
- **HTTPS with Cloudflare**: Origin Certificates valid for 15 years
- **High Performance**: Optimized for 64GB RAM / 16-core / NVMe storage
- **Security Hardened**: UFW firewall, restricted ports, HSTS enabled
- **Gzip Compression**: Automatic compression for text-based responses
- **Automatic Cache Warming**: PostgreSQL pg_prewarm for fast restarts

### Architecture

```
Internet → Cloudflare
        → Origin Server (ports 80, 443)
        → nginx (HTTPS, gzip, rate limiting)
        → MusicBrainz App (40 workers)
        → PostgreSQL 16 (8GB shared_buffers)
        → Solr Search (12GB heap)
```

### Current Configuration

- **Domain**: `musicbrainz-mirror.music-assistant.io`
- **Server**: Ubuntu with Docker

---

## Hardware Requirements

### Current OHF Setup
- **CPU**: 16 cores
- **RAM**: 64GB
- **Storage**: 1TB NVMe RAID 1
- **Network**: 1Gbps

---

## Quick Start

### One-liner Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/OpenHomeFoundation/musicbrainz-docker-local/main/bootstrap.sh | bash
# OR
wget -qO- https://raw.githubusercontent.com/OpenHomeFoundation/musicbrainz-docker-local/main/bootstrap.sh | bash
```

### Manual Setup

#### 1. Clone the Official Repository

```bash
git clone https://github.com/metabrainz/musicbrainz-docker.git
cd musicbrainz-docker
```

#### 2. Add This Local Folder

```bash
git clone https://github.com/OpenHomeFoundation/musicbrainz-docker-local local
```

#### 3. Create Cloudflare Origin Certificate

1. Go to **Cloudflare Dashboard** → **SSL/TLS** → **Origin Server**
2. Click **Create Certificate**
3. Select "Generate private key and CSR with Cloudflare"
4. Add your domain(s)
5. Choose validity
6. Copy the **Origin Certificate** and **Private Key** and save them as `cert.pem` and `key.pem`.

#### 4. Configure Environment

Base64 encode your certificates:

```bash
# Linux:
cat cert.pem | base64 -w0
cat key.pem | base64 -w0

# macOS:
cat cert.pem | base64 | tr -d '\n'
cat key.pem | base64 | tr -d '\n'
```

Edit `.env` in the musicbrainz-docker root:

```bash
MUSICBRAINZ_DOMAIN=musicbrainz-mirror.music-assistant.io
MUSICBRAINZ_WEB_SERVER_HOST=musicbrainz-mirror.music-assistant.io
MUSICBRAINZ_WEB_SERVER_PORT=443

# SSL Certificate (Base64 encoded - single line each)
SSL_CERTIFICATE_BASE64=LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...
SSL_CERTIFICATE_KEY_BASE64=LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t...

# Enable basic compose fules -- follow original readme procedure to enable replication cron (which updates this line)
COMPOSE_FILE=docker-compose.yml:local/docker-compose.ohf.yml
```

#### 5. Configure Cloudflare SSL Mode

In Cloudflare Dashboard → SSL/TLS:
- Set SSL mode to **Full (strict)**

#### 6. Start Services

```bash
docker compose up -d
```

---

## Server Preparation

### 1. Initial System Setup

Execute `install.sh` to prepare the server(Only ubuntu supported):


---

## Configuration

### 1. Create Cloudflare Origin Certificate

1. Go to **Cloudflare Dashboard** → **SSL/TLS** → **Origin Server**
2. Click **Create Certificate**
3. Select "Generate private key and CSR with Cloudflare"
4. Add your domain(s)
5. Choose validity: **15 years**
6. Copy the **Origin Certificate** and **Private Key**

Save them as `cert.pem` and `key.pem`.

### 2. Configure Environment (.env)

Base64 encode your certificates (required for Docker Compose):

```bash
# On Linux:
cat cert.pem | base64 -w0 > cert.b64
cat key.pem | base64 -w0 > key.b64

# On macOS:
cat cert.pem | base64 | tr -d '\n' > cert.b64
cat key.pem | base64 | tr -d '\n' > key.b64
```

Then create your `.env` file:

```bash
cat > .env << 'EOF'
# Domain Configuration
MUSICBRAINZ_DOMAIN=musicbrainz-mirror.music-assistant.io
MUSICBRAINZ_WEB_SERVER_HOST=musicbrainz-mirror.music-assistant.io
MUSICBRAINZ_WEB_SERVER_PORT=443

# SSL Certificate (Base64 encoded - single line each)
# (Optional) if ommited, the default self-signed cert will be used
SSL_CERTIFICATE_BASE64=<paste contents of cert.b64>
SSL_CERTIFICATE_KEY_BASE64=<paste contents of key.b64>

# Compose Configuration
COMPOSE_FILE=docker-compose.yml:local/docker-compose.ohf.yml
EOF
```

### Key Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Domain, certificates, compose chain |
| `local/docker-compose.ohf.yml` | PostgreSQL, Solr, Redis, nginx optimizations |
| `local/config/nginx/nginx.conf.template` | Nginx configuration template |

---

## Deployment

### Initial Deployment

```bash
cd ~/musicbrainz-docker

# Start all services
docker compose up -d

# Monitor startup
docker compose ps
docker compose logs -f nginx
docker compose logs -f musicbrainz
```

### Verify HTTPS Certificate

```bash
# Check certificate is loaded
docker exec nginx cat /etc/nginx/ssl/fullchain.pem | openssl x509 -noout -dates

# Test HTTPS
curl -k https://localhost/health
```

### DNS Verification

```bash
# Verify DNS points to Cloudflare
dig +short musicbrainz-mirror.music-assistant.io
```

---

## Monitoring & Maintenance

### Container Status

```bash
# View all containers
docker compose ps

# Check resource usage
docker stats

# View logs
docker compose logs -f nginx
docker compose logs -f musicbrainz
docker compose logs -f db
```

### Database Status

```bash
# Check database size
docker compose exec db psql -U musicbrainz musicbrainz_db -c \
  "SELECT pg_size_pretty(pg_database_size(current_database()));"

# Check replication status
docker compose exec db psql -U musicbrainz musicbrainz_db -c \
  "SELECT * FROM replication_control;"

# View table sizes
docker compose exec db psql -U musicbrainz musicbrainz_db -c \
  "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
   FROM pg_tables WHERE schemaname = 'musicbrainz' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"
```

### Memory Usage

```bash
# System memory
free -h

# Container memory
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
```

---


## Troubleshooting

### Common Issues

#### 1. 502 Bad Gateway

**Cause**: MusicBrainz container not ready or crashed

```bash
docker compose ps
docker compose logs musicbrainz --tail 50
docker compose restart musicbrainz
```

#### 2. SSL Certificate Error

**Cause**: Certificate not written or invalid

```bash
# Check certificate exists
docker exec nginx ls -la /etc/nginx/ssl/

# Check certificate content
docker exec nginx cat /etc/nginx/ssl/fullchain.pem | openssl x509 -noout -text

# Check nginx logs
docker compose logs nginx
```

#### 3. Port :5000 in URLs

**Cause**: `MUSICBRAINZ_WEB_SERVER_PORT` not set to 443

```bash
# Verify .env
grep WEB_SERVER_PORT .env

# Recreate container
docker compose up -d --force-recreate musicbrainz
```

#### 4. Database Connection Errors

```bash
# Check PostgreSQL logs
docker compose logs db

# Verify database is running
docker compose exec db psql -U musicbrainz -c "SELECT version();"

# Check connections
docker compose exec db psql -U musicbrainz -c "SELECT count(*) FROM pg_stat_activity;"
```

### Log Locations

```bash
# nginx logs
docker compose logs nginx

# MusicBrainz application logs
docker compose logs musicbrainz

# PostgreSQL logs
docker compose logs db

# Solr search logs
docker compose logs search

# All logs
docker compose logs --tail=100 -f
```

---

## Backup & Recovery

### Backup Database

```bash
docker compose exec db pg_dump -U musicbrainz musicbrainz_db | \
  gzip > musicbrainz-db-backup-$(date +%Y%m%d).sql.gz
```

### Restore Database

```bash
gunzip -c musicbrainz-db-backup-YYYYMMDD.sql.gz | \
  docker compose exec -T db psql -U musicbrainz musicbrainz_db
```

---

## Updating

### Update MusicBrainz Images

```bash
cd ~/musicbrainz-docker

git pull origin main

# Pull latest images
docker compose pull

# Recreate containers
docker compose up -d

# Clean up old images
docker image prune -f
```

---


## Support & Resources

### MusicBrainz Resources
- [MusicBrainz Mirror Documentation](https://musicbrainz.org/doc/MusicBrainz_Server/Setup#Replication)
- [Docker Setup Guide](https://github.com/metabrainz/musicbrainz-docker)
- [MusicBrainz Community](https://community.metabrainz.org/)

### Cloudflare Resources
- [Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [SSL Modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)

### Issues
- [MusicBrainz Docker Issues](https://github.com/metabrainz/musicbrainz-docker/issues)

---

**Last Updated**: 2026-02-03
**Maintained By**: Open Home Foundation
