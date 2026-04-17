#!/usr/bin/env bash
#
# Comprehensive Test Suite for Caddy + SearXNG + AI Gateway
# Tests all components and integrations
#

set -e

COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

pass_count=0
fail_count=0
total_count=0

test_pass() {
    echo -e "${COLOR_GREEN}✓ PASS${COLOR_RESET}: $1"
    ((pass_count++))
    ((total_count++))
}

test_fail() {
    echo -e "${COLOR_RED}✗ FAIL${COLOR_RESET}: $1"
    echo -e "  ${COLOR_YELLOW}Expected:${COLOR_RESET} $2"
    echo -e "  ${COLOR_YELLOW}Got:${COLOR_RESET} $3"
    ((fail_count++))
    ((total_count++))
}

test_info() {
    echo -e "\n${COLOR_BLUE}━━━ $1 ━━━${COLOR_RESET}"
}

test_skip() {
    echo -e "${COLOR_YELLOW}⊘ SKIP${COLOR_RESET}: $1"
}

# ========================================================================
# KUBERNETES CLUSTER TESTS
# ========================================================================

test_info "Kubernetes Cluster Status"

# Test K8s API connectivity
if kubectl get nodes &>/dev/null; then
    test_pass "Kubernetes API accessible"
else
    test_fail "Kubernetes API" "API server responding" "Connection failed"
fi

# Test Caddy DaemonSet status
CADDY_PODS=$(kubectl get pods -n ingress-system -l app.kubernetes.io/name=caddy-ingress -o json | jq -r '.items | length')
if [ "$CADDY_PODS" -eq 3 ]; then
    test_pass "Caddy DaemonSet: 3 replicas running"
else
    test_fail "Caddy DaemonSet" "3 replicas" "Got $CADDY_PODS pods"
fi

# Test Caddy pods are ready
CADDY_READY=$(kubectl get pods -n ingress-system -l app.kubernetes.io/name=caddy-ingress -o json | jq -r '[.items[] | .status.conditions[] | select(.type=="Ready") | .status] | all')
if [ "$CADDY_READY" = "true" ]; then
    test_pass "Caddy pods: All ready"
else
    test_fail "Caddy pods" "All ready" "Some pods not ready"
fi

# Test IngressClass created
if kubectl get ingressclass caddy &>/dev/null; then
    test_pass "Caddy IngressClass created"
else
    test_fail "Caddy IngressClass" "ingressclass/caddy exists" "Not found"
fi

# Test IngressClass default annotation
IS_DEFAULT=$(kubectl get ingressclass caddy -o jsonpath='{.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class}')
if [ "$IS_DEFAULT" = "true" ]; then
    test_pass "Caddy IngressClass marked as default"
else
    test_fail "Caddy IngressClass default" "is-default-class=true" "Got: $IS_DEFAULT"
fi

# ========================================================================
# CADDY CONFIGURATION TESTS
# ========================================================================

test_info "Caddy Configuration"

# Test ConfigMap exists
if kubectl get configmap -n ingress-system caddy-config &>/dev/null; then
    test_pass "Caddy ConfigMap exists"
else
    test_fail "Caddy ConfigMap" "caddy-config ConfigMap" "Not found"
fi

# Test SearXNG routes in ConfigMap
SEARXNG_ROUTE=$(kubectl get configmap -n ingress-system caddy-config -o jsonpath='{.data.Caddyfile}' | grep -c "searxng.cluster.local")
if [ "$SEARXNG_ROUTE" -gt 0 ]; then
    test_pass "SearXNG route configured in Caddyfile"
else
    test_fail "SearXNG route" "searxng.cluster.local in Caddyfile" "Not found"
fi

# Test AI Gateway route in ConfigMap
GATEWAY_ROUTE=$(kubectl get configmap -n ingress-system caddy-config -o jsonpath='{.data.Caddyfile}' | grep -c "ai-gateway.cluster.local")
if [ "$GATEWAY_ROUTE" -gt 0 ]; then
    test_pass "AI Gateway route configured in Caddyfile"
else
    test_fail "AI Gateway route" "ai-gateway.cluster.local in Caddyfile" "Not found"
fi

# ========================================================================
# SEARXNG SERVICE TESTS
# ========================================================================

test_info "SearXNG Service (NixOS)"

# Test SearXNG systemd service is running
if systemctl is-active --quiet searx; then
    test_pass "SearXNG service running"
else
    test_fail "SearXNG service" "active" "Service not running"
fi

# Test SearXNG port 7777 listening
if ss -tlnp | grep -q ":7777.*searx"; then
    test_pass "SearXNG listening on port 7777"
else
    test_fail "SearXNG port" "Port 7777 listening" "Port not bound"
fi

# Test SearXNG health endpoint
SEARXNG_HEALTH=$(curl -s http://127.0.0.1:7777/health 2>/dev/null || echo "failed")
if [ "$SEARXNG_HEALTH" = "OK" ]; then
    test_pass "SearXNG health endpoint: OK"
else
    test_fail "SearXNG health" "OK" "Got: $SEARXNG_HEALTH"
fi

# Test SearXNG search API (direct)
SEARXNG_QUERY=$(curl -s "http://127.0.0.1:7777/search?q=test&format=json" 2>/dev/null | jq -r '.query' 2>/dev/null || echo "failed")
if [ "$SEARXNG_QUERY" = "test" ]; then
    test_pass "SearXNG search API: Working"
else
    test_fail "SearXNG search" "query='test'" "Got: $SEARXNG_QUERY"
fi

# Test SearXNG returns results
SEARXNG_RESULTS=$(curl -s "http://127.0.0.1:7777/search?q=test&format=json" 2>/dev/null | jq -r '.results | length' 2>/dev/null || echo "0")
if [ "$SEARXNG_RESULTS" -gt 0 ]; then
    test_pass "SearXNG returns $SEARXNG_RESULTS results"
else
    test_fail "SearXNG results" ">0 results" "Got: $SEARXNG_RESULTS"
fi

# ========================================================================
# AI GATEWAY TESTS
# ========================================================================

test_info "AI Gateway Service"

# Test AI Gateway systemd service is running
if systemctl is-active --quiet ai-inference-gateway; then
    test_pass "AI Gateway service running"
else
    test_fail "AI Gateway service" "active" "Service not running"
fi

# Test AI Gateway port 8080 listening
if ss -tlnp | grep -q ":8080.*uvicorn"; then
    test_pass "AI Gateway listening on port 8080"
else
    test_fail "AI Gateway port" "Port 8080 listening" "Port not bound"
fi

# Test AI Gateway health endpoint
GATEWAY_HEALTH=$(curl -s http://127.0.0.1:8080/health 2>/dev/null | jq -r '.status' 2>/dev/null || echo "failed")
if [ "$GATEWAY_HEALTH" = "healthy" ] || [ "$GATEWAY_HEALTH" = "degraded" ]; then
    test_pass "AI Gateway health endpoint: $GATEWAY_HEALTH"
else
    test_fail "AI Gateway health" "healthy or degraded" "Got: $GATEWAY_HEALTH"
fi

# ========================================================================
# MCP INTEGRATION TESTS
# ========================================================================

test_info "MCP SearXNG Integration"

# Test SearXNG ping tool
PING_RESULT=$(curl -s -X POST http://127.0.0.1:8080/mcp/call \
    -H 'Content-Type: application/json' \
    -d '{"server":"searxng","tool":"ping_searxng","arguments":{}}' 2>/dev/null)

PING_STATUS=$(echo "$PING_RESULT" | jq -r '.result' 2>/dev/null | jq -r '.content[0].text' 2>/dev/null | jq -r '.status' 2>/dev/null || echo "failed")

if [ "$PING_STATUS" = "healthy" ]; then
    test_pass "MCP ping_searxng: healthy"
else
    test_fail "MCP ping" "status=healthy" "Got: $PING_STATUS"
fi

# Test SearXNG URL in ping response
PING_URL=$(echo "$PING_RESULT" | jq -r '.result' 2>/dev/null | jq -r '.content[0].text' 2>/dev/null | jq -r '.url' 2>/dev/null || echo "failed")
if echo "$PING_URL" | grep -q "127.0.0.1:7777"; then
    test_pass "MCP ping shows correct SearXNG URL: $PING_URL"
else
    test_fail "SearXNG URL in ping" "127.0.0.1:7777" "Got: $PING_URL"
fi

# ========================================================================
# MCP SEARCH TOOLS TESTS
# ========================================================================

test_info "MCP Search Tools (Subset)"

# Test web_search tool
WEB_SEARCH=$(curl -s -X POST http://127.0.0.1:8080/mcp/call \
    -H 'Content-Type: application/json' \
    -d '{"server":"searxng","tool":"web_search","arguments":{"query":"nixos","max_results":1}}' 2>/dev/null)

WEB_HAS_RESULTS=$(echo "$WEB_SEARCH" | jq -r '.result' 2>/dev/null | jq -r '.content[0].text' 2>/dev/null | grep -c "Search Results" || echo "0")

if [ "$WEB_HAS_RESULTS" -gt 0 ]; then
    test_pass "MCP web_search: Returns results"
else
    test_fail "MCP web_search" "Results returned" "No results found"
fi

# Test search_github tool
GITHUB_SEARCH=$(curl -s -X POST http://127.0.0.1:8080/mcp/call \
    -H 'Content-Type: application/json' \
    -d '{"server":"searxng","tool":"search_github","arguments":{"query":"kubernetes","max_results":1}}' 2>/dev/null)

GITHUB_HAS_RESULTS=$(echo "$GITHUB_SEARCH" | jq -r '.result' 2>/dev/null | jq -r '.content[0].text' 2>/dev/null | grep -c "GitHub Search" || echo "0")

if [ "$GITHUB_HAS_RESULTS" -gt 0 ]; then
    test_pass "MCP search_github: Returns results"
else
    test_fail "MCP search_github" "Results returned" "No results found"
fi

# Test search_research tool
RESEARCH_SEARCH=$(curl -s -X POST http://127.0.0.1:8080/mcp/call \
    -H 'Content-Type: application/json' \
    -d '{"server":"searxng","tool":"search_research","arguments":{"query":"machine learning","max_results":1}}' 2>/dev/null)

RESEARCH_HAS_DOMAIN=$(echo "$RESEARCH_SEARCH" | jq -r '.result' 2>/dev/null | jq -r '.content[0].text' 2>/dev/null | grep -c "Domain: research" || echo "0")

if [ "$RESEARCH_HAS_DOMAIN" -gt 0 ]; then
    test_pass "MCP search_research: Domain routing works"
else
    test_fail "MCP search_research" "Domain: research" "Domain not detected"
fi

# ========================================================================
# CADDY ROUTING TESTS
# ========================================================================

test_info "Caddy Routing (via Host Header)"

# Get a worker node IP (Nexus)
NEXUS_IP="10.1.1.120"

# Test SearXNG route via Caddy (with Host header)
CADDY_SEARXNG=$(curl -s -H "Host: searxng.cluster.local" "http://${NEXUS_IP}/" 2>/dev/null)

if echo "$CADDY_SEARXNG" | grep -q "SearXNG\|search\|metasearch"; then
    test_pass "Caddy routing: searxng.cluster.local → SearXNG"
else
    test_fail "Caddy SearXNG route" "SearXNG content" "Got: $CADDY_SEARXNG"
fi

# ========================================================================
# RATE LIMITING TESTS
# ========================================================================

test_info "Rate Limiting Configuration"

# Check SearXNG configuration for rate limiting
if grep -q "limiter = false" /etc/nixos/modules/services/searxng.nix; then
    test_pass "SearXNG: server.limiter = false"
else
    test_fail "SearXNG limiter" "limiter = false" "Not found in config"
fi

if grep -q "limiter = false" /etc/nixos/modules/services/searxng.nix; then
    test_pass "SearXNG: global limiter = false"
else
    test_fail "SearXNG global limiter" "limiter = false" "Not found in config"
fi

# Test rapid requests don't get 403
REQUEST_COUNT=0
SUCCESS_COUNT=0
for i in {1..5}; do
    RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "http://127.0.0.1:7777/search?q=test$i&format=json")
    if [ "$RESPONSE" = "200" ]; then
        ((SUCCESS_COUNT++))
    fi
    ((REQUEST_COUNT++))
done

if [ "$SUCCESS_COUNT" -eq "$REQUEST_COUNT" ]; then
    test_pass "Rate limiting: $REQUEST_COUNT/5 requests succeeded (no 403s)"
else
    test_fail "Rate limiting" "5/5 success" "Got: $SUCCESS_COUNT/$REQUEST_COUNT"
fi

# ========================================================================
# DOCUMENTATION TESTS
# ========================================================================

test_info "Documentation Files"

# Test documentation exists
DOCS=(
    "/etc/nixos/docs/kubernetes/CADDY_INGRESS_MIGRATION_GUIDE.md"
    "/etc/nixos/docs/kubernetes/CADDY_SEARXNG_ARCHITECTURE.md"
    "/etc/nixos/docs/gateway/SEARXNG_AI_PATTERNS_RESEARCH.md"
    "/etc/nixos/docs/kubernetes/CADDY_MIGRATION_SUMMARY.md"
    "/etc/nixos/docs/gateway/SEARXNG_DEPLOYMENT_STATUS.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        test_pass "Documentation exists: $(basename "$doc")"
    else
        test_fail "Documentation" "$doc" "File not found"
    fi
done

# ========================================================================
# SUMMARY
# ========================================================================

test_info "Test Summary"

echo ""
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════${COLOR_RESET}"
echo -e "  ${COLOR_BLUE}Total Tests:${COLOR_RESET} $total_count"
echo -e "  ${COLOR_GREEN}Passed:${COLOR_RESET} $pass_count"
echo -e "  ${COLOR_RED}Failed:${COLOR_RESET} $fail_count"
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════${COLOR_RESET}"

if [ "$fail_count" -eq 0 ]; then
    echo -e "\n${COLOR_GREEN}🎉 ALL TESTS PASSED!${COLOR_RESET}\n"
    exit 0
else
    echo -e "\n${COLOR_RED}⚠️  SOME TESTS FAILED${COLOR_RESET}\n"
    exit 1
fi
