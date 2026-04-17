#!/usr/bin/env bash
#
# SearXNG Cluster Deployment Script
# Deploys and manages multi-instance SearXNG cluster with load balancing
#

set -euo pipefail

# Configuration
COMPOSE_DIR="/etc/nixos/docker-compose/searxng-cluster"
ENV_FILE=".env"
SEARXNG_SETTINGS="../../modules/services/ai-inference/ai_inference_gateway/mcp_servers/searxng_settings.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Change to compose directory
cd "$COMPOSE_DIR"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Install with: nix-shell -p docker"
        exit 1
    fi

    # Check Docker Compose
    if ! command -v docker compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi

    # Check if .env exists
    if [ ! -f "$ENV_FILE" ]; then
        log_warn ".env file not found. Creating from .env.example..."
        cp .env.example .env
        log_warn "Edit .env and set SEARXNG_SECRET before continuing!"
        exit 1
    fi

    # Check if settings.yml exists
    if [ ! -f "config/searxng_settings.yml" ]; then
        log_info "Copying SearXNG settings.yml..."
        mkdir -p config
        cp "$SEARXNG_SETTINGS" config/searxng_settings.yml
    fi

    log_info "Prerequisites check passed ✓"
}

# Start cluster
start_cluster() {
    log_info "Starting SearXNG cluster..."

    # Create data directories
    mkdir -p data/{searxng-1,searxng-2,searxng-3,valkey}

    # Start services
    docker compose up -d

    log_info "Waiting for services to be healthy..."
    sleep 10

    # Check status
    show_status

    log_info "Cluster started successfully!"
    log_info "Load balancer: http://localhost:8888"
    log_info "Direct instances:"
    log_info "  - Instance 1: http://localhost:7777"
    log_info "  - Instance 2: http://localhost:7778"
    log_info "  - Instance 3: http://localhost:7779"
}

# Stop cluster
stop_cluster() {
    log_info "Stopping SearXNG cluster..."
    docker compose down
    log_info "Cluster stopped."
}

# Restart cluster
restart_cluster() {
    log_info "Restarting SearXNG cluster..."
    docker compose restart
    sleep 5
    show_status
    log_info "Cluster restarted."
}

# Show status
show_status() {
    log_info "Cluster status:"
    echo ""
    docker compose ps
    echo ""

    # Show health
    log_info "Health checks:"
    echo ""

    # Check load balancer
    if curl -sf http://localhost:8888/health > /dev/null; then
        echo "✓ NGINX Load Balancer: healthy"
    else
        echo "✗ NGINX Load Balancer: unhealthy"
    fi

    # Check instances
    for port in 7777 7778 7779; do
        if curl -sf http://localhost:${port}/health > /dev/null 2>&1; then
            echo "✓ SearXNG (port ${port}): healthy"
        else
            echo "✗ SearXNG (port ${port}): unhealthy"
        fi
    done

    # Check Valkey
    if docker exec valkey-searxng valkey-cli ping > /dev/null 2>&1; then
        echo "✓ Valkey: healthy"
    else
        echo "✗ Valkey: unhealthy"
    fi

    echo ""
}

# Show logs
show_logs() {
    local service="${1:-}"
    if [ -z "$service" ]; then
        docker compose logs -f --tail=100
    else
        docker compose logs -f --tail=100 "$service"
    fi
}

# Test search
test_search() {
    local query="${1:-nixos}"

    log_info "Testing search with query: '$query'"
    echo ""

    # Test via load balancer
    result=$(curl -s "http://localhost:8888/search?q=${query}&format=json" | head -c 500)

    if echo "$result" | grep -q "results"; then
        log_info "✓ Search successful via load balancer"
    else
        log_error "✗ Search failed via load balancer"
        echo "$result"
    fi
}

# Clear cache
clear_cache() {
    log_info "Clearing Valkey cache..."
    docker exec valkey-searxng valkey-cli FLUSHALL
    log_info "Cache cleared."
}

# Show stats
show_stats() {
    log_info "Valkey cache statistics:"
    docker exec valkey-searxng valkey-cli INFO stats | grep -E "keys|hits|misses"
}

# Update cluster
update_cluster() {
    log_info "Updating SearXNG cluster..."
    docker compose pull
    docker compose up -d
    log_info "Cluster updated."
}

# Clean up
cleanup() {
    log_warn "This will remove all containers, volumes, and data!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker compose down -v
        rm -rf data/*
        log_info "Cleanup complete."
    else
        log_info "Cleanup cancelled."
    fi
}

# Main
case "${1:-}" in
    start)
        check_prerequisites
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    restart)
        restart_cluster
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "${2:-}"
        ;;
    test)
        test_search "${2:-}"
        ;;
    cache-clear)
        clear_cache
        ;;
    stats)
        show_stats
        ;;
    update)
        update_cluster
        ;;
    cleanup)
        cleanup
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|test|cache-clear|stats|update|cleanup}"
        echo ""
        echo "Commands:"
        echo "  start       - Start the SearXNG cluster"
        echo "  stop        - Stop the cluster"
        echo "  restart     - Restart the cluster"
        echo "  status      - Show cluster status and health"
        echo "  logs        - Show logs (optional: specify service name)"
        echo "  test        - Test search functionality"
        echo "  cache-clear - Clear Valkey cache"
        echo "  stats       - Show cache statistics"
        echo "  update      - Pull latest images and restart"
        echo "  cleanup     - Remove all containers and data"
        exit 1
        ;;
esac
