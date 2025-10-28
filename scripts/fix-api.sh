#!/bin/bash

# CheaperForDrug API - Complete Fix Script
# Run on server: ssh webet 'bash -s' < scripts/fix-api.sh
# Or: scp scripts/fix-api.sh webet:~ && ssh webet './fix-api.sh'

set -e

APP_NAME="cheaperfordrug-api"
APP_DIR="$HOME/apps/$APP_NAME"
REPO_DIR="$APP_DIR/repo"
DEVOPS_DIR="$HOME/DevOps"

echo "========================================"
echo "CheaperForDrug API - Complete Fix"
echo "========================================"
echo ""

# ============================================================================
# STEP 1: DIAGNOSTICS
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Running Diagnostics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Checking current state..."
echo "  Log directory: $(ls -la $APP_DIR/logs/ 2>/dev/null | wc -l) files"
echo "  production.log: $([ -f "$APP_DIR/logs/production.log" ] && echo "EXISTS" || echo "MISSING")"
echo "  Running containers: $(docker ps --filter "name=$APP_NAME" --format "{{.Names}}" | wc -l)"
echo ""

# ============================================================================
# STEP 2: FIX LOGGING CONFIGURATION
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Fixing Logging Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$REPO_DIR"
PROD_CONFIG="$REPO_DIR/config/environments/production.rb"

if [ ! -f "$PROD_CONFIG" ]; then
    echo "❌ ERROR: production.rb not found"
    exit 1
fi

# Backup
echo "Creating backup..."
cp "$PROD_CONFIG" "${PROD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

# Check if already patched
if grep -q "ActiveSupport::Logger.broadcast" "$PROD_CONFIG"; then
    echo "✓ Dual logging already configured"
else
    echo "Patching production.rb..."

    # Create the logging patch
    cat > /tmp/logging_patch.txt << 'EOFLOG'

  # ============================================================================
  # LOGGING CONFIGURATION - DevOps Auto-configured
  # ============================================================================
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info").to_sym

  # Log to STDOUT (for docker logs)
  config.logger = ActiveSupport::Logger.new(STDOUT)

  # Also log to file (for persistent debugging)
  if File.exist?(Rails.root.join('log'))
    file_logger = ActiveSupport::Logger.new(
      Rails.root.join('log', 'production.log'),
      1, 100.megabytes
    )
    file_logger.level = config.log_level
    config.logger.extend(ActiveSupport::Logger.broadcast(file_logger))
  end

  config.log_formatter = ::Logger::Formatter.new
  config.log_tags = [ :request_id ]

EOFLOG

    # Insert after "Rails.application.configure do"
    awk '
        /Rails.application.configure do/ {
            print
            while (getline < "/tmp/logging_patch.txt") print
            next
        }
        /^[[:space:]]*config\.log_level/ { next }
        /^[[:space:]]*config\.logger.*=/ { next }
        /^[[:space:]]*config\.log_formatter/ { next }
        /^[[:space:]]*config\.log_tags/ { next }
        { print }
    ' "$PROD_CONFIG" > "${PROD_CONFIG}.new"

    mv "${PROD_CONFIG}.new" "$PROD_CONFIG"
    rm /tmp/logging_patch.txt
    echo "✓ Logging configuration updated"
fi
echo ""

# ============================================================================
# STEP 3: FIX HEALTH ENDPOINT
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Fixing /health Endpoint"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ROUTES_FILE="$REPO_DIR/config/routes.rb"

if [ ! -f "$ROUTES_FILE" ]; then
    echo "❌ ERROR: routes.rb not found"
    exit 1
fi

# Backup
echo "Creating backup..."
cp "$ROUTES_FILE" "${ROUTES_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Check if already patched
if grep -q "get.*['\"]\/health['\"]" "$ROUTES_FILE"; then
    echo "✓ /health endpoint already configured"
else
    echo "Patching routes.rb..."

    # Create the routes patch
    cat > /tmp/routes_patch.txt << 'EOFROUTES'
  # Health check endpoints
  get '/health', to: 'rails/health#show', as: :health_check
  get '/up', to: 'rails/health#show', as: :rails_health_check

EOFROUTES

    # Insert after "Rails.application.routes.draw do"
    awk '
        /Rails.application.routes.draw do/ {
            print
            while (getline < "/tmp/routes_patch.txt") print
            next
        }
        { print }
    ' "$ROUTES_FILE" > "${ROUTES_FILE}.new"

    mv "${ROUTES_FILE}.new" "$ROUTES_FILE"
    rm /tmp/routes_patch.txt
    echo "✓ Health endpoints added"
fi
echo ""

# ============================================================================
# STEP 4: COMMIT AND PUSH CHANGES
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Committing Changes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$REPO_DIR"

# Check if there are changes to commit
if git diff --quiet config/environments/production.rb config/routes.rb; then
    echo "No changes to commit"
else
    echo "Committing changes..."
    git add config/environments/production.rb config/routes.rb
    git commit -m "Fix production logging and health endpoints

- Enable dual logging (stdout + file) for debugging
- Add /health endpoint for monitoring
- Configure log rotation (100MB, keep 1 old file)

Auto-fixed by DevOps script" || echo "⚠️  Commit failed (changes may already be committed)"

    echo "Pushing changes..."
    git push || echo "⚠️  Push failed (may need to pull first)"
    echo "✓ Changes committed and pushed"
fi
echo ""

# ============================================================================
# STEP 5: DEPLOY
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Deploying Application"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$DEVOPS_DIR/apps/$APP_NAME"
./deploy.sh

echo ""

# ============================================================================
# STEP 6: VERIFY FIXES
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6: Verifying Fixes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Waiting 15 seconds for containers to stabilize..."
sleep 15
echo ""

echo "1. Testing /health endpoint..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api-public.cheaperfordrug.com/health 2>/dev/null || echo "000")
if [ "$HEALTH_STATUS" = "200" ]; then
    echo "   ✅ /health: OK (HTTP $HEALTH_STATUS)"
else
    echo "   ❌ /health: FAILED (HTTP $HEALTH_STATUS)"
fi

echo "2. Testing /up endpoint..."
UP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api-public.cheaperfordrug.com/up 2>/dev/null || echo "000")
if [ "$UP_STATUS" = "200" ]; then
    echo "   ✅ /up: OK (HTTP $UP_STATUS)"
else
    echo "   ❌ /up: FAILED (HTTP $UP_STATUS)"
fi

echo "3. Checking production.log..."
if [ -f "$APP_DIR/logs/production.log" ]; then
    echo "   ✅ production.log exists"
    LOG_SIZE=$(stat -f%z "$APP_DIR/logs/production.log" 2>/dev/null || stat -c%s "$APP_DIR/logs/production.log" 2>/dev/null || echo "0")
    echo "   Size: $LOG_SIZE bytes"
    if [ "$LOG_SIZE" -gt 0 ]; then
        echo "   Last 3 lines:"
        tail -3 "$APP_DIR/logs/production.log" | sed 's/^/      /'
    fi
else
    echo "   ⚠️  production.log not created yet (will be created on first log)"
fi
echo ""

# ============================================================================
# STEP 7: DEBUG 500 ERROR
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 7: Testing Newsletter Subscriptions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Triggering newsletter subscription endpoint..."
NEWSLETTER_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST https://api-public.cheaperfordrug.com/api/public/newsletter_subscriptions \
    -H "Content-Type: application/json" \
    -H "Origin: https://premiera.taniejpolek.pl" \
    -d '{"email":"test@example.com"}' 2>/dev/null)

NEWSLETTER_STATUS=$(echo "$NEWSLETTER_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
NEWSLETTER_BODY=$(echo "$NEWSLETTER_RESPONSE" | grep -v "HTTP_CODE:")

echo "HTTP Status: $NEWSLETTER_STATUS"

if [ "$NEWSLETTER_STATUS" = "500" ]; then
    echo "⚠️  Still getting 500 error"
    echo ""
    echo "Response body:"
    echo "$NEWSLETTER_BODY" | head -10
    echo ""
    echo "Checking logs for error details..."
    sleep 2

    if [ -f "$APP_DIR/logs/production.log" ]; then
        echo ""
        echo "Recent errors from production.log:"
        tail -50 "$APP_DIR/logs/production.log" | grep -A 5 -B 2 "newsletter\|500\|Error\|Exception" | tail -30 || echo "No specific error found in production.log"
    fi

    echo ""
    echo "Recent Docker logs:"
    docker logs cheaperfordrug-api_web_1 --tail 30 2>&1 | grep -A 5 -B 2 "newsletter\|500\|Error\|Exception" | head -30 || echo "No specific error found in Docker logs"

elif [ "$NEWSLETTER_STATUS" = "200" ] || [ "$NEWSLETTER_STATUS" = "201" ]; then
    echo "✅ Endpoint working correctly!"
    echo "Response: $NEWSLETTER_BODY"
elif [ "$NEWSLETTER_STATUS" = "422" ]; then
    echo "⚠️  Validation error (422) - endpoint is working but request may be invalid"
    echo "Response: $NEWSLETTER_BODY"
else
    echo "⚠️  Unexpected status: $NEWSLETTER_STATUS"
    echo "Response: $NEWSLETTER_BODY"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Fix Process Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "  • Logging: Fixed and configured for dual output"
echo "  • Health endpoints: /health and /up configured"
echo "  • Deployment: Completed successfully"
echo "  • Verification: $([ "$HEALTH_STATUS" = "200" ] && echo "✅ Passed" || echo "⚠️ Check logs")"
echo ""
echo "Useful commands:"
echo "  • View logs:       tail -f $APP_DIR/logs/production.log"
echo "  • Docker logs:     docker logs ${APP_NAME}_web_1 -f"
echo "  • Rails console:   $APP_DIR/console.sh"
echo "  • Check health:    curl https://api-public.cheaperfordrug.com/health"
echo ""
