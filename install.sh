#!/bin/bash
# MusicBrainz Mirror Installation and Setup Script
# Run this script on the server to set up and configure the MusicBrainz mirror

set -e  # Exit on error

echo "================================================="
echo "MusicBrainz Mirror Installation Script"
echo "================================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "⚠️  This script must be run as root (use sudo)"
   exit 1
fi

# Check for required commands
for cmd in docker ufw sysctl; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Error: $cmd is not installed"
        exit 1
    fi
done

echo "✓ All required commands found"
echo ""

# ============================================================================
# 1. Firewall Configuration
# ============================================================================
echo "================================================="
echo "1. Configuring Firewall (UFW)"
echo "================================================="

echo "Setting up UFW firewall rules..."

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    echo "❌ UFW is not installed. Installing..."
    apt-get update && apt-get install -y ufw
fi

# Configure firewall rules
echo "Configuring firewall rules..."
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force allow 22/tcp comment 'SSH access'
ufw --force allow 80/tcp comment 'HTTP (redirects to HTTPS)'
ufw --force allow 443/tcp comment 'HTTPS traffic'

# Enable UFW if not already enabled
if ! ufw status | grep -q "Status: active"; then
    echo "Enabling UFW..."
    ufw --force enable
    echo "✓ UFW firewall enabled"
else
    echo "✓ UFW already enabled"
fi

echo ""
echo "Current firewall status:"
ufw status verbose
echo ""

# ============================================================================
# 2. System Optimizations
# ============================================================================
echo "================================================="
echo "2. Applying System Optimizations"
echo "================================================="

echo "Optimizing kernel parameters for MusicBrainz..."

# Memory and swap optimizations
sysctl -w vm.swappiness=0
sysctl -w vm.dirty_ratio=10
sysctl -w vm.dirty_background_ratio=5
sysctl -w vm.vfs_cache_pressure=50

# Network optimizations
sysctl -w net.core.somaxconn=1024
sysctl -w net.ipv4.tcp_max_syn_backlog=2048

# Make permanent (check if already exists first)
if ! grep -q "MusicBrainz optimizations" /etc/sysctl.conf 2>/dev/null; then
    cat >> /etc/sysctl.conf << 'EOF'

# MusicBrainz optimizations
vm.swappiness=0
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
net.core.somaxconn=1024
net.ipv4.tcp_max_syn_backlog=2048
EOF
    echo "✓ Sysctl configurations added to /etc/sysctl.conf"
else
    echo "✓ MusicBrainz sysctl configurations already exist"
fi

echo ""

# ============================================================================
# 3. Docker Configuration
# ============================================================================
echo "================================================="
echo "3. Checking Docker Installation"
echo "================================================="

if ! docker --version &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first:"
    echo "   curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose plugin."
    exit 1
fi

echo "✓ Docker version: $(docker --version)"
echo "✓ Docker Compose version: $(docker compose version)"

# Ensure Docker is running
if ! docker ps &> /dev/null; then
    echo "❌ Docker daemon is not running. Please start Docker."
    exit 1
fi

echo "✓ Docker is running"
echo ""

# ============================================================================
# 4. Directory and File Setup
# ============================================================================
echo "================================================="
echo "4. Setting Up Directories"
echo "================================================="

# Ask for installation directory
read -p "Enter the installation directory [/home/ubuntu/musicbrainz-docker]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/home/ubuntu/musicbrainz-docker}

if [ ! -d "$INSTALL_DIR" ]; then
    echo "❌ Directory $INSTALL_DIR does not exist."
    read -p "Create it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p "$INSTALL_DIR"
        echo "✓ Created directory: $INSTALL_DIR"
    else
        echo "Installation cancelled."
        exit 1
    fi
else
    echo "✓ Directory exists: $INSTALL_DIR"
fi

# Create local directory structure
mkdir -p "$INSTALL_DIR/local/config/nginx"
echo "✓ Created local directory structure"
echo ""

# ============================================================================
# 5. Environment Configuration Check
# ============================================================================
echo "================================================="
echo "5. Environment Configuration"
echo "================================================="

if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "⚠️  Warning: .env file not found in $INSTALL_DIR"
    echo "   Please ensure you have:"
    echo "   - .env file with MUSICBRAINZ_DOMAIN, SSL_CERTIFICATE_BASE64, SSL_CERTIFICATE_KEY_BASE64"
    echo "   - COMPOSE_FILE set to include local/docker-compose.ohf.yml"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✓ .env file found"

    # Check required variables
    if ! grep -q "MUSICBRAINZ_DOMAIN=" "$INSTALL_DIR/.env"; then
        echo "⚠️  Warning: MUSICBRAINZ_DOMAIN not set in .env"
    else
        DOMAIN=$(grep "MUSICBRAINZ_DOMAIN=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
        echo "✓ Domain configured: $DOMAIN"
    fi

    if ! grep -q "SSL_CERTIFICATE_BASE64=" "$INSTALL_DIR/.env"; then
        echo "⚠️  Warning: SSL_CERTIFICATE_BASE64 not set in .env"
        echo "   Base64 encode your certificate: cat cert.pem | base64 -w0"
    fi
fi

echo ""

# ============================================================================
# 6. Search Index Replication Setup
# ============================================================================
echo "================================================="
echo "6. Search Index Configuration"
echo "================================================="

echo ""
echo "⚠️  WARNING: Search indexes are not included in replication!"
echo "You will need to rebuild search indexes regularly to keep them up-to-date."
echo ""
echo "Options:"
echo "  1. Manually: docker compose exec -T indexer python -m sir reindex"
echo "  2. With Live Indexing (see MusicBrainz docs)"
echo "  3. With a scheduled cron job (recommended)"
echo ""

# Optional: Set up weekly search index rebuild cron job
read -p "Would you like to set up a weekly cron job to rebuild search indexes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Add cron job (runs Sundays at 1 AM)
    CRON_JOB="0 1 * * 7 root cd $INSTALL_DIR && /usr/bin/docker compose exec -T indexer python -m sir reindex"

    if ! crontab -l 2>/dev/null | grep -q "sir reindex"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        echo "✓ Cron job added! Search indexes will rebuild every Sunday at 1 AM."
    else
        echo "✓ A similar cron job already exists"
    fi
else
    echo "Skipped cron job setup. You can add it manually later:"
    echo "0 1 * * 7 root cd $INSTALL_DIR && /usr/bin/docker compose exec -T indexer python -m sir reindex"
fi

echo ""

# ============================================================================
# 7. Service Startup Information
# ============================================================================
echo "================================================="
echo "7. Starting Services"
echo "================================================="

echo ""
echo "To start the MusicBrainz mirror, run:"
echo ""
echo "  cd $INSTALL_DIR"
echo "  docker compose up -d"
echo ""
echo "To check status:"
echo "  docker compose ps"
echo ""
echo "To view logs:"
echo "  docker compose logs nginx -f"
echo "  docker compose logs musicbrainz -f"
echo "  docker compose logs db -f"
echo ""

read -p "Would you like to start the services now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "$INSTALL_DIR"
    echo "Starting services..."
    docker compose up -d
    echo ""
    echo "✓ Services started!"
    echo ""
    echo "Checking status..."
    docker compose ps
else
    echo "Skipped service startup."
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "================================================="
echo "Installation Complete!"
echo "================================================="
echo ""
echo "Summary:"
echo "  ✓ Firewall configured (SSH, HTTP, HTTPS)"
echo "  ✓ System optimizations applied"
echo "  ✓ Docker verified"
echo "  ✓ Directory structure created"
echo ""
echo "Next steps:"
echo "  1. Ensure your domain DNS points to your server"
echo "  2. Verify HTTPS: curl -k https://localhost/health"
echo "  3. Access your site: https://$DOMAIN"
echo ""
echo "For troubleshooting, see: TROUBLESHOOTING.md"
echo ""
