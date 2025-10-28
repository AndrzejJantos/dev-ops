#!/bin/bash

# Continue API Rebuild from Current State
# Run on server: ssh webet 'bash -s' < scripts/continue-rebuild-api.sh
# This picks up from where the previous script failed

set -e

APP_NAME="cheaperfordrug-api"
APP_DIR="$HOME/apps/$APP_NAME"
DEVOPS_DIR="$HOME/DevOps"
DB_NAME="cheaperfordrug_production"
DB_USER="cheaperfordrug_api_user"

echo "========================================"
echo "CheaperForDrug API - Continue Rebuild"
echo "========================================"
echo ""
echo "Current status:"
echo "  • Containers: Already removed"
echo "  • Images: Already removed"
echo "  • Database: Still needs handling"
echo ""

# ============================================================================
# STEP 1: HANDLE DATABASE
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Handling Database"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "What do you want to do with the database?"
echo "  1) Keep it (recommended - your data is preserved)"
echo "  2) Backup and drop (fresh start with safety net)"
echo "  3) Drop without backup (complete clean slate)"
echo ""
read -p "Choose option (1/2/3): " DB_OPTION
echo ""

case $DB_OPTION in
    1)
        echo "Keeping database: $DB_NAME"
        echo "✓ Database preserved"
        ;;
    2)
        echo "Creating backup..."
        BACKUP_FILE="$HOME/backups/${DB_NAME}_final_$(date +%Y%m%d_%H%M%S).sql.gz"
        mkdir -p "$HOME/backups"

        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            sudo -u postgres pg_dump "$DB_NAME" | gzip > "$BACKUP_FILE"
            echo "✓ Backup created: $BACKUP_FILE"

            echo "Dropping database..."
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
            echo "✓ Database dropped"
        else
            echo "Database $DB_NAME does not exist"
        fi

        echo "Dropping database user..."
        sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;" 2>/dev/null || true
        echo "✓ Database user dropped"
        ;;
    3)
        echo "⚠️  Dropping database without backup..."
        sleep 2

        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"
            echo "✓ Database dropped"
        else
            echo "Database $DB_NAME does not exist"
        fi

        sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;" 2>/dev/null || true
        echo "✓ Database user dropped"
        ;;
esac
echo ""

# ============================================================================
# STEP 2: REMOVE APPLICATION DIRECTORY
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Removing Application Directory"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -d "$APP_DIR" ]; then
    echo "Backing up directory: $APP_DIR"
    BACKUP_APP_DIR="${APP_DIR}_backup_$(date +%Y%m%d_%H%M%S)"

    du -sh "$APP_DIR" 2>/dev/null

    mv "$APP_DIR" "$BACKUP_APP_DIR"
    echo "✓ Moved to: $BACKUP_APP_DIR"
else
    echo "Application directory already removed"
fi
echo ""

# ============================================================================
# STEP 3: REBUILD
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Rebuilding Application"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ ! -f "$DEVOPS_DIR/apps/$APP_NAME/setup.sh" ]; then
    echo "❌ ERROR: Setup script not found at $DEVOPS_DIR/apps/$APP_NAME/setup.sh"
    echo ""
    echo "Please ensure DevOps repository is up to date:"
    echo "  cd $DEVOPS_DIR"
    echo "  git pull"
    exit 1
fi

echo "Running setup..."
cd "$DEVOPS_DIR/apps/$APP_NAME"
./setup.sh

echo ""
echo "✅ Setup complete!"
echo ""

# ============================================================================
# STEP 4: CONFIGURATION
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Configuration Required"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "⚠️  IMPORTANT: You need to configure the application before deploying"
echo ""
echo "Configuration file: $HOME/apps/$APP_NAME/.env.production"
echo ""
echo "Required updates:"
echo "  1. ALLOWED_ORIGINS - Add your frontend domains"
echo "     Current: https://example.com"
echo "     Update to: https://premiera.taniejpolek.pl,https://taniejpolek.pl"
echo ""
echo "  2. MAILGUN credentials (if needed)"
echo "     MAILGUN_API_KEY=your_key"
echo "     MAILGUN_DOMAIN=your_domain"
echo ""
echo "  3. Any other app-specific settings"
echo ""

read -p "Do you want to edit configuration now? (y/n): " EDIT_CONFIG
echo ""

if [[ "$EDIT_CONFIG" =~ ^[Yy]$ ]]; then
    nano "$HOME/apps/$APP_NAME/.env.production"
    echo ""
    echo "✓ Configuration updated"
else
    echo "⚠️  Remember to edit before deploying:"
    echo "   nano $HOME/apps/$APP_NAME/.env.production"
fi
echo ""

# ============================================================================
# STEP 5: DEPLOY
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Do you want to deploy now? (y/n): " DEPLOY_NOW
echo ""

if [[ "$DEPLOY_NOW" =~ ^[Yy]$ ]]; then
    echo "Deploying application..."
    cd "$DEVOPS_DIR/apps/$APP_NAME"
    ./deploy.sh

    echo ""
    echo "✅ Deployment complete!"
    echo ""

    # Verify deployment
    echo "Verifying deployment..."
    sleep 5

    HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api-public.cheaperfordrug.com/up 2>/dev/null || echo "000")

    if [ "$HEALTH_STATUS" = "200" ]; then
        echo "✅ Health check: PASSED"
    else
        echo "⚠️  Health check: Status $HEALTH_STATUS"
        echo "   Check logs: docker logs ${APP_NAME}_web_1 -f"
    fi
else
    echo "Skipping deployment"
    echo ""
    echo "To deploy later:"
    echo "  cd $DEVOPS_DIR/apps/$APP_NAME"
    echo "  ./deploy.sh"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Rebuild Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "  • Database: $([ "$DB_OPTION" = "1" ] && echo "Preserved" || echo "Rebuilt")"
echo "  • Application: Freshly installed"
echo "  • Status: $([ "$DEPLOY_NOW" = "y" ] || [ "$DEPLOY_NOW" = "Y" ] && echo "Deployed" || echo "Ready to deploy")"
echo ""
echo "Useful commands:"
echo "  • Edit config:     nano $HOME/apps/$APP_NAME/.env.production"
echo "  • Deploy:          cd $DEVOPS_DIR/apps/$APP_NAME && ./deploy.sh"
echo "  • View logs:       docker logs ${APP_NAME}_web_1 -f"
echo "  • Rails console:   $HOME/apps/$APP_NAME/console.sh"
echo "  • Health check:    curl https://api-public.cheaperfordrug.com/up"
echo ""
