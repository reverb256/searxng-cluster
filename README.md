# SearXNG Cluster

Multi-instance SearXNG meta-search engine with load balancing, supporting
both Docker Compose and Kubernetes deployments.

## Architecture

```
                    ┌──────────────┐
                    │   Caddy/Nginx│  (reverse proxy + load balancer)
                    │   :80/:443   │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────┴─────┐┌────┴─────┐┌────┴─────┐
        │ SearXNG-1 ││SearXNG-2 ││SearXNG-3 │
        │  :8081    ││  :8082   ││  :8083   │
        └─────┬─────┘└────┬─────┘└────┬─────┘
              │            │            │
              └────────────┼────────────┘
                           │
                    ┌──────┴───────┐
                    │   Valkey     │
                    │   :6379      │
                    └──────────────┘
```

## Docker Compose Deployment

### Quick start

```bash
cd docker-compose/
cp .env.example .env
# Edit .env — generate a secret: openssl rand -hex 32
./deploy.sh start
```

### Management

```bash
./deploy.sh start     # Start the cluster
./deploy.sh stop      # Stop the cluster
./deploy.sh status    # Check cluster health
./deploy.sh logs      # Tail logs
./deploy.sh restart   # Rolling restart
./test-all.sh         # Run integration tests
```

### Configuration

- `docker-compose.yml` — Service definitions (3 SearXNG instances, Valkey, Caddy/Nginx)
- `config/searxng_settings.yml` — SearXNG engine settings, rate limits, formats
- `nginx/nginx.conf` — Nginx upstream config (alternative to Caddyfile)
- `Caddyfile` — Caddy reverse proxy + load balancer config
- `.env.example` — Environment variable template

## Kubernetes Deployment

### Apply manifests

```bash
cd k8s/

# Create namespace first
kubectl apply -f 00-namespace.yaml

# Create secrets (edit 01-secret.yaml with your values!)
kubectl apply -f 01-secret.yaml

# ConfigMaps
kubectl apply -f 02-configmap.yaml
kubectl apply -f 02-settings-configmap.yaml

# Deployment + NetworkPolicy
kubectl apply -f 03-deployment.yaml
kubectl apply -f 04-network-policy.yaml

# Valkey (if needed)
kubectl apply -f 05-valkey.yaml
```

### Manifest overview

| File | Purpose |
|------|---------|
| `00-namespace.yaml` | `searxng` namespace |
| `01-secret.yaml` | Secret key + Valkey password |
| `02-configmap.yaml` | Environment variables |
| `02-settings-configmap.yaml` | SearXNG settings (engines, limits) |
| `03-deployment.yaml` | SearXNG pods (3 replicas) |
| `04-network-policy.yaml` | Network isolation |
| `05-valkey.yaml` | Valkey cache deployment |
| `searxng-configmap.yaml` | Search namespace config |

### Required secrets

Edit `01-secret.yaml` before applying:

```yaml
stringData:
  SEARXNG_SECRET: "<generate with: openssl rand -hex 32>"
  VALKEY_PASSWORD: "<generate with: openssl rand -hex 16>"
```

## Port Reference

| Service | Docker | K8s |
|---------|--------|-----|
| SearXNG (individual) | 8081-8083 | 8080 |
| Load balancer | 80/443 | 80/443 |
| Valkey | 6379 | 6379 |
| Caddy admin | 2019 | — |

## Testing

```bash
# Docker Compose
cd docker-compose && ./test-all.sh

# Kubernetes
kubectl port-forward -n searxng svc/searxng 8888:8080
curl http://localhost:8888/search?q=test&format=json
```
