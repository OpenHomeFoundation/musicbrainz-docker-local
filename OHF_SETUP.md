# MusicBrainz Mirror Setup Guide
## Open Home Foundation - Music Assistant Project

This guide documents the complete setup for the Open Home Foundation's MusicBrainz mirror at `your-domain.example.com`.

---

## Table of Contents

1. [Overview](#overview)
2. [Hardware Requirements](#hardware-requirements)
3. [Server Preparation](#server-preparation)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Deployment](#deployment)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Performance Tuning](#performance-tuning)
9. [Troubleshooting](#troubleshooting)

---

## Overview

### What This Setup Provides

- **Full MusicBrainz Mirror**: Complete read-only replica of the MusicBrainz database
- **HTTPS with Auto-Renewal**: Let's Encrypt SSL certificates managed automatically
- **High Performance**: Optimized for 64GB RAM / 16-core / NVMe storage
- **Security Hardened**: UFW firewall, restricted ports, HSTS enabled
- **Gzip Compression**: Automatic compression for text-based responses
- **Automatic Cache Warming**: PostgreSQL pg_prewarm for fast restarts

### Architecture

Traffic flow: Internet → UFW Firewall (ports 22, 80, 443) → nginx-proxy (HTTPS termination + gzip) → acme-companion (Let's Encrypt) → MusicBrainz App (24 workers) → PostgreSQL 16 (8GB shared_buffers) → Solr Search (8GB heap)

### Current Configuration

- **Domain**: `your-domain.example.com`
- **Server**: Ubuntu with Docker
- **Database Size**: ~62GB
- **Total Artists**: 2.7+ million

---

## Hardware Requirements

### Minimum (Current OHF Setup)
- **CPU**: 16 cores
- **RAM**: 64GB
- **Storage**: 1TB NVMe RAID 1
- **Network**: 1Gbps

### Storage Breakdown
- PostgreSQL database: ~62GB
- Solr search indexes: ~10-15GB
- Docker images: ~5GB
- OS + overhead: ~20GB

---

## Server Preparation

### 1. Initial System Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl git ufw

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Reboot to apply Docker group membership
sudo reboot
```

### 2. Clone Repository

```bash
cd ~
git clone https://github.com/metabrainz/musicbrainz-docker.git
cd musicbrainz-docker
```

### 3. Run Installation Script

The OHF setup includes an automated installation script:

```bash
# Copy OHF configuration files
# (These should be provided separately or downloaded from your fork)

# Run the installation script as root
sudo ./local/install.sh
```

The script will:
1. Configure UFW firewall (SSH, HTTP, HTTPS)
2. Apply system optimizations (memory, network)
3. Verify Docker installation
4. Create directory structure
5. Optionally set up search index cron job

---

## Configuration

### Configuration Files Overview

Key files:
- `.env` - Environment variables (domain, email, URL generation settings)
- `docker-compose.yml` - Base MusicBrainz configuration
- `local/docker-compose.ohf.yml` - OHF-specific optimizations
- `local/config/nginx/custom.conf` - Nginx gzip compression and performance settings
- `local/install.sh` - Automated setup script

The `.env` file defines the compose file chain (docker-compose.yml → replication-cron.yml → docker-compose.ohf.yml) which automatically loads the OHF-specific configuration when running `docker compose` commands.

### 1. Environment Configuration (.env)

**Required Settings:**

- `MUSICBRAINZ_DOMAIN` - Your mirror domain (your-domain.example.com)
- `LETSENCRYPT_EMAIL` - Email for SSL certificate notifications 
- `MUSICBRAINZ_WEB_SERVER_HOST` - Public domain for URL generation
- `MUSICBRAINZ_WEB_SERVER_PORT` - Set to 443 to remove :5000 from generated URLs

**Important Notes:**
- `MUSICBRAINZ_WEB_SERVER_HOST` and `MUSICBRAINZ_WEB_SERVER_PORT` control URL generation in HTML
- These are **different** from `VIRTUAL_HOST` and `VIRTUAL_PORT` (nginx routing)
- Without setting port to 443, URLs will include `:5000` suffix

### 2. Docker Compose OHF Configuration (local/docker-compose.ohf.yml)

Key configurations for OHF setup:

#### PostgreSQL Optimizations (8GB RAM)

- **shared_buffers=8GB** - Main PostgreSQL cache (12% of 64GB RAM)
- **effective_cache_size=40GB** - Guides query planner (62% of total RAM)
- **maintenance_work_mem=2GB** - For VACUUM and CREATE INDEX operations
- **work_mem=64MB** - Per-query operation memory
- **pg_prewarm** - Automatic cache warming and restoration after restart

#### MusicBrainz Application (24 Workers)

- **MUSICBRAINZ_SERVER_PROCESSES=24** - 1.5x CPU cores for I/O-bound workload
- **VIRTUAL_HOST** - Tells nginx-proxy which domain to route
- **VIRTUAL_PORT=5000** - Internal container port for nginx routing
- **LETSENCRYPT_HOST** - Domain for SSL certificate generation
- **REPLICATION_TYPE=RT_MIRROR** - Mirror mode (read-only replica)
- **ports** - Override to prevent direct port 5000 exposure (only accessible via nginx)

#### Solr Search (8GB Heap)

- **SOLR_HEAP=8g** - Java heap size (50% of allocated container RAM)
- **mem_swappiness=0** - Never swap Java heap to disk (critical for performance)

#### Nginx-Proxy with Gzip Compression

- **Custom config** - Mounts `local/config/nginx/custom.conf` for gzip compression
- **ENABLE_IPV6=true** - IPv6 support enabled

### 3. Nginx Custom Configuration

The `local/config/nginx/custom.conf` includes:

- **Gzip compression** (level 6, min 1000 bytes)
- **Optimized timeouts** for database queries
- **Connection keep-alive** settings
- **Buffer optimization**

---

## Installation

### Method 1: Automated Installation (Recommended)

```bash
# As root or with sudo
sudo ./local/install.sh
```

This handles:
- Firewall configuration
- System optimizations
- Docker verification
- Directory structure
- Optional cron jobs

### Method 2: Manual Installation

#### 1. Configure Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP (Let'\''s Encrypt)'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
```

#### 2. Apply System Optimizations

```bash
# Create/edit /etc/sysctl.conf
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF

# MusicBrainz optimizations
vm.swappiness=0
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
net.core.somaxconn=1024
net.ipv4.tcp_max_syn_backlog=2048
EOF

# Apply immediately
sudo sysctl -p
```

#### 3. Create Directory Structure

```bash
mkdir -p local/config/nginx
```

#### 4. Configure Environment

```bash
# Create .env file (see Configuration section above)
nano .env
```

---

## Deployment

### Initial Deployment

```bash
cd ~/musicbrainz-docker

# Start all services
docker compose up -d

# Monitor startup
docker compose ps
docker logs -f nginx-proxy
docker logs -f acme-companion
docker logs -f musicbrainz-docker-musicbrainz-1
```

### Verify HTTPS Certificate

```bash
# Watch certificate generation (takes 30-60 seconds)
docker logs -f acme-companion

# Check certificate
echo | openssl s_client -servername your-domain.example.com \
  -connect your-domain.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### DNS Verification

```bash
# Verify DNS points to server
dig +short your-domain.example.com

# Should return your server IP
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
docker logs nginx-proxy --tail 100
docker logs musicbrainz-docker-musicbrainz-1 --tail 100
docker logs musicbrainz-docker-db-1 --tail 100
```

### Database Status

```bash
# Check database size
docker exec musicbrainz-docker-db-1 psql -U musicbrainz musicbrainz_db -c \
  "SELECT pg_size_pretty(pg_database_size(current_database()));"

# Check replication status
docker exec musicbrainz-docker-db-1 psql -U musicbrainz musicbrainz_db -c \
  "SELECT * FROM replication_control;"

# View table sizes
docker exec musicbrainz-docker-db-1 psql -U musicbrainz musicbrainz_db -c \
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

### Certificate Management

```bash
# View certificates
docker exec nginx-proxy ls -la /etc/nginx/certs/

# Force renewal (if needed)
docker exec acme-companion /app/force_renew

# Check expiry
echo | openssl s_client -servername your-domain.example.com \
  -connect your-domain.example.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

---

## Performance Tuning

### Database Cache Statistics

```bash
# Check cache hit ratio (aim for >95%)
docker exec musicbrainz-docker-db-1 psql -U musicbrainz musicbrainz_db -c "
SELECT
  ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 2) AS cache_hit_ratio,
  pg_size_pretty(sum(heap_blks_hit * 8192)) AS cache_hit_size
FROM pg_statio_user_tables;
"
```

### PostgreSQL Connection Pool

```bash
# Check active connections
docker exec musicbrainz-docker-db-1 psql -U musicbrainz -c \
  "SELECT count(*) FROM pg_stat_activity;"

# View slow queries
docker exec musicbrainz-docker-db-1 psql -U musicbrainz musicbrainz_db -c \
  "SELECT pid, now() - query_start AS duration, query
   FROM pg_stat_activity
   WHERE state = 'active' AND now() - query_start > interval '5 seconds';"
```

### Automatic Cache Warming

The pg_prewarm extension automatically saves and restores the cache:
- Saves cache state every 5 minutes
- Restores on PostgreSQL restart
- Reduces cold-start query times

---

## Troubleshooting

### Common Issues

#### 1. 502 Bad Gateway

**Cause**: MusicBrainz container not ready or crashed

**Solution**:
```bash
# Check container status
docker compose ps

# View MusicBrainz logs
docker logs musicbrainz-docker-musicbrainz-1 --tail 50

# Restart if needed
docker compose restart musicbrainz
```

#### 2. Port :5000 in URLs

**Cause**: `MUSICBRAINZ_WEB_SERVER_PORT` not set to 443

**Solution**:
```bash
# Edit .env
echo "MUSICBRAINZ_WEB_SERVER_PORT=443" >> .env

# Recreate container
docker compose up -d --force-recreate musicbrainz
```

#### 3. No Gzip Compression

**Cause**: Custom nginx config not loaded

**Solution**:
```bash
# Verify file exists
ls -l local/config/nginx/custom.conf

# Check nginx config
docker exec nginx-proxy nginx -t

# Restart nginx-proxy
docker compose restart nginx-proxy

# Test compression
curl -H "Accept-Encoding: gzip" -I https://your-domain.example.com/
# Should see: content-encoding: gzip
```

#### 4. Certificate Not Issued

**Cause**: DNS not pointing to server or port 80 blocked

**Solution**:
```bash
# Verify DNS
dig +short your-domain.example.com

# Check firewall
sudo ufw status

# View acme-companion logs
docker logs acme-companion

# Common issues:
# - Domain doesn't resolve to server IP
# - Port 80 not accessible (Let's Encrypt needs HTTP)
# - Rate limit hit (wait 1 hour)
```

#### 5. Database Connection Errors

**Cause**: PostgreSQL not ready or crashed

**Solution**:
```bash
# Check PostgreSQL logs
docker logs musicbrainz-docker-db-1

# Verify database is running
docker exec musicbrainz-docker-db-1 psql -U musicbrainz -c "SELECT version();"

# Check connections
docker exec musicbrainz-docker-db-1 psql -U musicbrainz -c "SELECT * FROM pg_stat_activity;"
```

### Log Locations

```bash
# nginx-proxy access logs
docker logs nginx-proxy | grep "GET\|POST"

# MusicBrainz application logs
docker logs musicbrainz-docker-musicbrainz-1

# PostgreSQL logs
docker logs musicbrainz-docker-db-1

# Solr search logs
docker logs musicbrainz-docker-search-1

# All logs
docker compose logs --tail=100 -f
```

---

## Backup & Recovery

### Critical Data

**Volumes to backup:**
- `nginx-certs` - SSL certificates
- `pgdata` - PostgreSQL database (large!)
- `solrdata` - Search indexes

### Backup Commands

```bash
# Backup certificates
docker run --rm -v musicbrainz-docker_nginx-certs:/data -v $(pwd):/backup alpine \
  tar czf /backup/nginx-certs-backup-$(date +%Y%m%d).tar.gz -C /data .

# Backup database (large - consider using pg_dump instead)
docker exec musicbrainz-docker-db-1 pg_dump -U musicbrainz musicbrainz_db | \
  gzip > musicbrainz-db-backup-$(date +%Y%m%d).sql.gz
```

### Recovery from Backup

```bash
# Restore certificates
docker run --rm -v musicbrainz-docker_nginx-certs:/data -v $(pwd):/backup alpine \
  tar xzf /backup/nginx-certs-backup-YYYYMMDD.tar.gz -C /data
```

---

## Updating

### Update MusicBrainz Images

```bash
cd ~/musicbrainz-docker

# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Clean up old images
docker image prune -f
```

### Update Configuration

```bash
# Edit configuration files
nano local/docker-compose.ohf.yml

# Apply changes
docker compose up -d
```

---

## Security Considerations

### Current Security Measures

1. **Firewall**: UFW blocks all except SSH, HTTP, HTTPS
2. **Port Isolation**: MusicBrainz not directly exposed (only via nginx)
3. **HTTPS Only**: All traffic encrypted with TLS 1.2+
4. **HSTS Enabled**: Browsers enforce HTTPS
5. **Auto-Updates**: Let's Encrypt certificates renew automatically
6. **No Swapping**: Prevents memory contents from being written to disk

### Security Checklist

- [ ] UFW firewall enabled and configured
- [ ] SSH key authentication (disable password auth)
- [ ] Regular system updates (`apt update && apt upgrade`)
- [ ] Docker images kept up to date
- [ ] Monitor logs for suspicious activity
- [ ] Regular backups of critical data

---

## Support & Resources

### Open Home Foundation Contacts
- **Mirror URL**: https://your-domain.example.com

### MusicBrainz Resources
- [MusicBrainz Mirror Documentation](https://musicbrainz.org/doc/MusicBrainz_Server/Setup#Replication)
- [Docker Setup Guide](https://github.com/metabrainz/musicbrainz-docker)
- [MusicBrainz IRC](https://musicbrainz.org/doc/Communication/IRC)

### Related Documentation
- `TROUBLESHOOTING.md` - General troubleshooting guide
- `README.md` - Project overview
- `local/install.sh` - Automated setup script

---

**Last Updated**: 2026-01-16
**Maintained By**: Open Home Foundation
