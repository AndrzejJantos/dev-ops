#!/bin/bash

# Quick fix: Create log directory for Rails app
# Run on server: ssh webet 'bash -s' < scripts/fix-log-directory.sh

set -e

APP_NAME="cheaperfordrug-api"
REPO_DIR="$HOME/apps/$APP_NAME/repo"

echo "========================================"
echo "Quick Fix: Create Log Directory"
echo "========================================"
echo ""

echo "Creating log directory in repo..."
mkdir -p "$REPO_DIR/log"

echo "Setting permissions..."
chmod 755 "$REPO_DIR/log"

echo "✓ Log directory created: $REPO_DIR/log"
echo ""

echo "Restarting containers to pick up the change..."
cd "$HOME/DevOps/apps/$APP_NAME"
./deploy.sh restart

echo ""
echo "Waiting for containers to start..."
sleep 10
echo ""

echo "Testing Rails console..."
if $HOME/apps/$APP_NAME/console.sh -e "puts 'Console works!'; exit" 2>&1 | grep -q "Console works!"; then
    echo "✅ Rails console working!"
else
    echo "⚠️  Rails console check inconclusive"
fi
echo ""

echo "Checking if production.log is created..."
if [ -f "$REPO_DIR/log/production.log" ]; then
    echo "✅ production.log exists!"
    ls -lh "$REPO_DIR/log/production.log"
else
    echo "⚠️  production.log not created yet"
    echo "   Trigger a request to create it:"
    echo "   curl https://api-public.cheaperfordrug.com/up"
fi
echo ""

echo "Checking mounted logs directory..."
if [ -f "$HOME/apps/$APP_NAME/logs/production.log" ]; then
    echo "✅ Mounted log file exists!"
    ls -lh "$HOME/apps/$APP_NAME/logs/production.log"
    echo ""
    echo "Last 5 lines:"
    tail -5 "$HOME/apps/$APP_NAME/logs/production.log"
else
    echo "⚠️  Mounted log file not created yet"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Fix Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Log files:"
echo "  • In repo:    $REPO_DIR/log/production.log"
echo "  • Mounted:    $HOME/apps/$APP_NAME/logs/production.log"
echo ""
echo "View logs:"
echo "  • From repo:   tail -f $REPO_DIR/log/production.log"
echo "  • From mount:  tail -f $HOME/apps/$APP_NAME/logs/production.log"
echo "  • Docker logs: docker logs ${APP_NAME}_web_1 -f"
echo ""
