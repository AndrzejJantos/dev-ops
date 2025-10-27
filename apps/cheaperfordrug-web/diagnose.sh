#!/bin/bash

# Diagnostic script for CheaperForDrug Web
# Run this on the remote server to diagnose deployment issues

echo "=================================="
echo "CheaperForDrug Web Diagnostics"
echo "=================================="
echo ""

# Check if running on remote server
echo "1. Server Information:"
echo "   Hostname: $(hostname)"
echo "   User: $(whoami)"
echo ""

# Check Docker containers
echo "2. Docker Containers:"
docker ps -a --filter "name=cheaperfordrug-web" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# Check container logs if any exist
echo "3. Container Logs (last 30 lines):"
CONTAINERS=$(docker ps -a --filter "name=cheaperfordrug-web_web" --format "{{.Names}}" | head -1)
if [ -n "$CONTAINERS" ]; then
    for container in $CONTAINERS; do
        echo "   Container: $container"
        docker logs "$container" --tail 30 2>&1 | sed 's/^/     /'
        echo ""
    done
else
    echo "   No containers found"
fi
echo ""

# Check if ports are listening
echo "4. Port Check:"
for port in 3030 3031 3032; do
    if nc -z localhost $port 2>/dev/null; then
        echo "   Port $port: OPEN"
    else
        echo "   Port $port: CLOSED"
    fi
done
echo ""

# Check nginx status
echo "5. Nginx Status:"
if systemctl is-active --quiet nginx; then
    echo "   Nginx: RUNNING"
else
    echo "   Nginx: NOT RUNNING"
fi
echo ""

# Check nginx configuration
echo "6. Nginx Configuration:"
if [ -f /etc/nginx/sites-available/cheaperfordrug-web ]; then
    echo "   Config file exists: YES"
    echo "   Testing config..."
    sudo nginx -t 2>&1 | sed 's/^/     /'
else
    echo "   Config file exists: NO"
    echo "   Expected: /etc/nginx/sites-available/cheaperfordrug-web"
fi
echo ""

# Check if nginx config is enabled
echo "7. Nginx Enabled Sites:"
if [ -L /etc/nginx/sites-enabled/cheaperfordrug-web ]; then
    echo "   Config enabled: YES"
else
    echo "   Config enabled: NO"
fi
echo ""

# Check SSL certificates
echo "8. SSL Certificates:"
if [ -d /etc/letsencrypt/live/premiera.taniejpolek.pl ]; then
    echo "   Certificates exist: YES"
    echo "   Certificate files:"
    ls -lh /etc/letsencrypt/live/premiera.taniejpolek.pl/ 2>/dev/null | sed 's/^/     /'
else
    echo "   Certificates exist: NO"
fi
echo ""

# Test local connectivity
echo "9. Local Connectivity Test:"
for port in 3030 3031 3032; do
    if nc -z localhost $port 2>/dev/null; then
        echo "   Testing http://localhost:$port/"
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/ 2>/dev/null)
        echo "   Response: HTTP $STATUS"
    fi
done
echo ""

# Check nginx logs
echo "10. Nginx Error Logs (last 20 lines):"
if [ -f /var/log/nginx/cheaperfordrug-web-error.log ]; then
    sudo tail -20 /var/log/nginx/cheaperfordrug-web-error.log 2>/dev/null | sed 's/^/     /'
else
    echo "   No error log found"
fi
echo ""

# DNS check
echo "11. DNS Resolution:"
echo "   Resolving premiera.taniejpolek.pl..."
host premiera.taniejpolek.pl 2>&1 | sed 's/^/     /'
echo ""

echo "=================================="
echo "Diagnostic Complete"
echo "=================================="
