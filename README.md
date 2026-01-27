# MusicBrainz Docker - Local Configuration

This folder contains custom configuration for deploying a production-ready MusicBrainz mirror with automatic HTTPS via Let's Encrypt.

**Important:** This `local` folder must be placed inside the official [musicbrainz-docker](https://github.com/metabrainz/musicbrainz-docker) repository.

## Overview

This setup creates a complete MusicBrainz mirror that:
- Replicates the full MusicBrainz database automatically
- Provides HTTPS with auto-renewing Let's Encrypt certificates
- Is optimized for high-performance hardware (64GB RAM / 16-core)

## Prerequisites

- **Ubuntu Server** (22.04 LTS or newer recommended)
- **Docker** and **Docker Compose** (v2+)
- **Domain name** with DNS pointing to your server
- **Ports 80 and 443** open and available
- **Hardware**: Minimum 16GB RAM, recommended 64GB+ for optimal performance
- **Storage**: ~400GB minimum, SSD/NVMe strongly recommended

## Quick Start

### 1. Clone the Official MusicBrainz Docker Repository

```bash
git clone https://github.com/metabrainz/musicbrainz-docker.git
cd musicbrainz-docker
```

**Recommended:** Use a specific release for stability:
```bash
# Check available releases at:
# https://github.com/metabrainz/musicbrainz-docker/releases

# Clone and checkout a specific version
git clone https://github.com/metabrainz/musicbrainz-docker.git
cd musicbrainz-docker
git checkout v-2026-01-19.0
```

### 2. Download This Local Folder

Download or copy this entire `local` folder into the `musicbrainz-docker` directory you just cloned:

```bash
# Option A: If you have this repo as a zip/tarball
cp -r /path/to/this/local ./local

# Option B: If this is hosted in a separate git repo
git clone https://github.com/OpenHomeFoundation/musicbrainz-docker-local local
```

Your directory structure should look like:
```
musicbrainz-docker/
├── docker-compose.yml      # From official repo
├── compose/                # From official repo
├── .env                    # You will create/edit this
└── local/                  # THIS folder (added by you)
    ├── README.md
    ├── install.sh
    ├── docker-compose.ohf.yml
    └── config/
```

### 3. Configure Environment

Edit the `.env` file in the **musicbrainz-docker root directory** (not this local folder):

```bash
# Required settings
MUSICBRAINZ_DOMAIN=your-domain.com
LETSENCRYPT_EMAIL=your-email@example.com
MUSICBRAINZ_WEB_SERVER_HOST=your-domain.com
MUSICBRAINZ_WEB_SERVER_PORT=443

# Compose file chain (enables all features)
COMPOSE_FILE=docker-compose.yml:compose/replication-cron.yml:local/docker-compose.ohf.yml
```

### 4. Point DNS

Create an A record pointing your domain to your server's IP address.

### 5. Run the Installation Script

```bash
sudo ./local/install.sh
```

This script will:
- Configure the UFW firewall (SSH, HTTP, HTTPS only)
- Apply system performance optimizations
- Verify Docker installation
- Create required directories
- Optionally set up cron jobs for search index rebuilding
- Start all services

### 6. Verify Deployment

```bash
# Check service status
docker compose ps

# Watch certificate generation (takes 30-60 seconds)
docker logs acme-companion -f

# Once certificate is ready, access your site
https://your-domain.com
```

## File Structure

```
local/
├── README.md                    # This file
├── install.sh                   # Automated installation script
├── docker-compose.ohf.yml       # Docker Compose override with optimizations
├── config/
│   └── nginx/
│       └── custom.conf          # Nginx gzip compression settings
├── OHF_SETUP.md                 # Detailed setup guide for Open Home Foundation
└── HTTPS_SETUP.md.old           # Legacy HTTPS documentation (reference)
```

## Services

| Service | Purpose | Notes |
|---------|---------|-------|
| **db** | PostgreSQL 16 database | Stores all MusicBrainz data |
| **musicbrainz** | Web application | The main MusicBrainz server |
| **search** | Solr search engine | Powers artist/release search |
| **mq** | RabbitMQ message queue | Handles inter-service events |
| **redis** | Session cache | Fast in-memory caching |
| **nginx-proxy** | Reverse proxy | HTTPS termination, routing |
| **acme-companion** | Let's Encrypt client | Auto-renews SSL certificates |

## Common Operations

### Start Services
```bash
docker compose up -d
```

### Stop Services
```bash
docker compose down
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f musicbrainz
docker compose logs -f db
```

### Check Service Status
```bash
docker compose ps
```

### Restart a Service
```bash
docker compose restart musicbrainz
```

### Rebuild Search Index
```bash
docker compose exec musicbrainz indexer.sh
```

### Force Database Replication
```bash
docker compose exec musicbrainz replication.sh
```

### View SSL Certificate Status
```bash
docker compose exec nginx-proxy ls -la /etc/nginx/certs/
```

## Configuration Details

### docker-compose.ohf.yml

This file overrides the default configuration with:

**PostgreSQL Optimizations:**
- 8GB shared_buffers
- 40GB effective_cache_size
- pg_prewarm enabled (cache warming on restart)
- Parallel query workers

**Application Optimizations:**
- 24 worker processes
- Optimized for I/O-bound workloads

**Solr Optimizations:**
- 8GB heap size
- Memory swapping disabled

**Redis:**
- Upgraded to Redis 7
- 2GB max memory with LRU eviction

### Nginx Custom Configuration

Located at `config/nginx/custom.conf`:
- Gzip compression enabled (level 6)
- Compresses text, CSS, JavaScript, JSON, XML, SVG
- Minimum size threshold: 1000 bytes

## Troubleshooting

### Services Won't Start

```bash
# Check for port conflicts
sudo lsof -i :80
sudo lsof -i :443

# View startup errors
docker compose logs --tail=50
```

### Certificate Issues

```bash
# Check acme-companion logs
docker compose logs acme-companion

# Verify domain resolves correctly
dig your-domain.com

# Force certificate renewal
docker compose exec acme-companion /app/force_renew
```

### Database Issues

```bash
# Check database logs
docker compose logs db

# Connect to database
docker compose exec db psql -U musicbrainz
```

### High Memory Usage

```bash
# Check container memory usage
docker stats

# Reduce PostgreSQL memory (edit docker-compose.ohf.yml)
# Lower shared_buffers and effective_cache_size values
```

### Search Not Working

```bash
# Check Solr status
docker compose logs search

# Rebuild search index (takes several hours)
docker compose exec musicbrainz indexer.sh
```

## Updating

### Pull Latest Changes

```bash
cd musicbrainz-docker
git pull origin main
docker compose pull
docker compose up -d
```

### Rebuild Containers

```bash
docker compose build --no-cache
docker compose up -d
```

## Backup & Recovery

### Backup Database

```bash
docker compose exec db pg_dump -U musicbrainz musicbrainz_db > backup.sql
```

### Backup Certificates

```bash
# Important: Back up your SSL certificates
docker run --rm -v musicbrainz-docker_nginx-certs:/certs -v $(pwd):/backup \
  alpine tar czf /backup/certs-backup.tar.gz -C /certs .
```

### Restore Database

```bash
docker compose exec -T db psql -U musicbrainz musicbrainz_db < backup.sql
```

## Development Mode (No HTTPS)

For local development without HTTPS, you can bypass nginx-proxy:

1. Comment out nginx-proxy and acme-companion in `docker-compose.ohf.yml`
2. Uncomment the ports section for musicbrainz to expose port 5000 directly
3. Access via `http://localhost:5000`

## Additional Resources

- [MusicBrainz Docker GitHub](https://github.com/metabrainz/musicbrainz-docker)
- [MusicBrainz Documentation](https://musicbrainz.org/doc/MusicBrainz_Documentation)
- [MusicBrainz Database](https://musicbrainz.org/doc/MusicBrainz_Database)
- [Open Home Foundation Setup Guide](OHF_SETUP.md) - Detailed hardware-specific guide

## Support

For issues specific to this setup, check:
1. [OHF_SETUP.md](OHF_SETUP.md) troubleshooting section
2. [MusicBrainz Docker Issues](https://github.com/metabrainz/musicbrainz-docker/issues)
3. [MusicBrainz Forums](https://community.metabrainz.org/)
