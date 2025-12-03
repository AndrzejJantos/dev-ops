#!/bin/bash

# Domain Verification Script
# Tests all configured domains for proper functionality

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║           Domain Verification Report                      ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to test a domain
test_domain() {
    local domain=$1
    local endpoint=${2:-/}
    local description=$3

    echo -e "${BLUE}Testing: ${domain}${endpoint}${NC}"
    echo -e "  Description: ${description}"

    # Test HTTP redirect
    echo -n "  HTTP → HTTPS redirect: "
    http_status=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "http://${domain}" 2>/dev/null || echo "FAILED")
    if [ "$http_status" = "200" ] || [ "$http_status" = "301" ] || [ "$http_status" = "302" ]; then
        echo -e "${GREEN}✓ ${http_status}${NC}"
    else
        echo -e "${RED}✗ ${http_status}${NC}"
    fi

    # Test HTTPS
    echo -n "  HTTPS status: "
    https_status=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time 10 "https://${domain}${endpoint}" 2>/dev/null || echo "FAILED")
    if [ "$https_status" = "200" ]; then
        echo -e "${GREEN}✓ 200 OK${NC}"
    elif [ "$https_status" = "301" ] || [ "$https_status" = "302" ]; then
        echo -e "${YELLOW}→ ${https_status} Redirect${NC}"
    else
        echo -e "${RED}✗ ${https_status}${NC}"
    fi

    # Test SSL certificate
    echo -n "  SSL certificate: "
    if timeout 5 openssl s_client -connect ${domain}:443 -servername ${domain} </dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        echo -e "${GREEN}✓ Valid${NC}"
    else
        echo -e "${RED}✗ Invalid or unreachable${NC}"
    fi

    # Get response time
    echo -n "  Response time: "
    response_time=$(curl -s -o /dev/null -w "%{time_total}" --max-time 10 "https://${domain}${endpoint}" 2>/dev/null || echo "TIMEOUT")
    if [ "$response_time" != "TIMEOUT" ]; then
        echo -e "${GREEN}${response_time}s${NC}"
    else
        echo -e "${RED}TIMEOUT${NC}"
    fi

    echo ""
}

# Function to test backend health
test_backend_health() {
    local port=$1
    local app=$2

    echo -n "  Backend port ${port}: "
    if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${port}/up" 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}✓ Healthy${NC}"
    elif curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${port}/" 2>/dev/null | grep -q "200"; then
        echo -e "${GREEN}✓ Responding${NC}"
    else
        echo -e "${RED}✗ Not responding${NC}"
    fi
}

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  1. CheaperForDrug API (cheaperfordrug-api)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

test_domain "api-public.cheaperfordrug.com" "/up" "Public API health endpoint"
test_domain "api-internal.cheaperfordrug.com" "/up" "Internal API health endpoint"

echo -e "${YELLOW}Backend Health:${NC}"
test_backend_health 3020 "api"
test_backend_health 3021 "api"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  2. CheaperForDrug Landing (cheaperfordrug-landing)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

test_domain "taniejpolek.pl" "/" "Main domain (should redirect to www)"
test_domain "www.taniejpolek.pl" "/" "Main landing page"
test_domain "presale.taniejpolek.pl" "/" "Presale landing page"

echo -e "${YELLOW}Backend Health:${NC}"
test_backend_health 3010 "landing"
test_backend_health 3011 "landing"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  3. CheaperForDrug Web (cheaperfordrug-web)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

test_domain "taniejpolek.pl" "/" "Main domain (should redirect to www)"
test_domain "www.taniejpolek.pl" "/" "Web application"

echo -e "${YELLOW}Backend Health:${NC}"
test_backend_health 3055 "web"
test_backend_health 3056 "web"
test_backend_health 3057 "web"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  4. Brokik API (brokik-api)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

test_domain "api-public.brokik.com" "/up" "Public API health endpoint"
test_domain "api-internal.brokik.com" "/up" "Internal API health endpoint"

echo -e "${YELLOW}Backend Health:${NC}"
test_backend_health 3040 "brokik-api"
test_backend_health 3041 "brokik-api"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  5. Brokik Web (brokik-web)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

test_domain "brokik.com" "/" "Main domain"
test_domain "www.brokik.com" "/" "WWW domain"

echo -e "${YELLOW}Backend Health:${NC}"
test_backend_health 3050 "brokik-web"
test_backend_health 3051 "brokik-web"
test_backend_health 3052 "brokik-web"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check nginx status
echo -n "Nginx service: "
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
fi

# Count running containers
echo -n "Docker containers: "
container_count=$(docker ps | grep -E "(cheaperfordrug|brokik)" | wc -l)
echo -e "${GREEN}${container_count} running${NC}"

# Check for nginx errors in last 5 minutes
echo -n "Recent nginx errors: "
error_count=$(sudo tail -100 /var/log/nginx/error.log 2>/dev/null | grep -c "error" || echo "0")
if [ "$error_count" = "0" ]; then
    echo -e "${GREEN}None${NC}"
else
    echo -e "${YELLOW}${error_count} found${NC}"
    echo -e "${YELLOW}  Check: sudo tail /var/log/nginx/error.log${NC}"
fi

echo ""
echo -e "${GREEN}Verification complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  • Test domains in browser"
echo "  • Monitor logs: sudo tail -f /var/log/nginx/error.log"
echo "  • Check container logs: docker logs <container-name>"
