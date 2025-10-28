#!/bin/bash

# Complete Removal and Rebuild of CheaperForDrug API
# Run on server: ssh webet 'bash -s' < scripts/remove-and-rebuild-api.sh

set -e

APP_NAME="cheaperfordrug-api"
APP_DIR="$HOME/apps/$APP_NAME"
DEVOPS_DIR="$HOME/DevOps"
DB_NAME="cheaperfordrug_production"
DB_USER="cheaperfordrug_api_user"

echo "========================================"
echo "CheaperForDrug API - Complete Removal"
echo "========================================"
echo ""
echo "⚠️  WARNING: This will completely remove:"
echo "  • All Docker containers ($APP_NAME)"
echo "  • All Docker images ($APP_NAME)"
echo "  • Application directory ($APP_DIR)"
echo "  • Database backups (optional)"
echo "  • PostgreSQL database (optional)"
echo ""
read -p "Are you ABSOLUTELY SURE you want to continue? Type 'yes' to confirm: " CONFIRM
echo ""

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Aborted - you must type 'yes' to confirm"
    exit 1
fi

echo "Database handling options:"
echo "  1) Keep database and backups (recommended for data preservation)"
echo "  2) Backup database, then drop it (fresh start with backup)"
echo "  3) Drop database without backup (complete clean slate - DANGEROUS)"
echo ""
read -p "Choose option (1/2/3): " DB_OPTION
echo ""

# ============================================================================
# STEP 1: STOP AND REMOVE ALL CONTAINERS
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Stopping and Removing Containers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CONTAINERS=$(docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null || true)

if [ -n "$CONTAINERS" ]; then
    echo "Found containers:"
    echo "$CONTAINERS" | sed 's/^/  - /'
    echo ""

    echo "Stopping containers..."
    echo "$CONTAINERS" | xargs -I {} docker stop {} 2>/dev/null || true

    echo "Removing containers..."
    echo "$CONTAINERS" | xargs -I {} docker rm -f {} 2>/dev/null || true

    echo "✓ All containers stopped and removed"
else
    echo "No containers found"
fi
echo ""

# ============================================================================
# STEP 2: REMOVE DOCKER IMAGES
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Removing Docker Images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

IMAGES=$(docker images --filter "reference=${APP_NAME}" --format "{{.ID}} {{.Tag}}" 2>/dev/null || true)

if [ -n "$IMAGES" ]; then
    echo "Found images:"
    echo "$IMAGES" | sed 's/^/  - /'
    echo ""

    echo "Removing images..."
    docker images --filter "reference=${APP_NAME}" --format "{{.ID}}" | xargs -I {} docker rmi -f {} 2>/dev/null || true

    echo "✓ All images removed"
else
    echo "No images found"
fi
echo ""

# ============================================================================
# STEP 3: HANDLE DATABASE
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Handling Database"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

case $DB_OPTION in
    1)
        echo "Keeping database: $DB_NAME"
        echo "✓ Database preserved"
        ;;
    2)
        echo "Creating final backup before removal..."
        BACKUP_FILE="$HOME/backups/${DB_NAME}_final_$(date +%Y%m%d_%H%M%S).sql.gz"
        mkdir -p "$HOME/backups"

        if psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            pg_dump -U postgres "$DB_NAME" | gzip > "$BACKUP_FILE"
            echo "✓ Backup created: $BACKUP_FILE"

            echo "Dropping database..."
            psql -U postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
            echo "✓ Database dropped"
        else
            echo "Database $DB_NAME does not exist"
        fi

        echo "Dropping database user..."
        psql -U postgres -c "DROP USER IF EXISTS $DB_USER;" 2>/dev/null || true
        echo "✓ Database user dropped"
        ;;
    3)
        echo "⚠️  DANGEROUS: Dropping database without backup..."
        sleep 3

        if psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
            psql -U postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
            echo "✓ Database dropped"
        else
            echo "Database $DB_NAME does not exist"
        fi

        psql -U postgres -c "DROP USER IF EXISTS $DB_USER;" 2>/dev/null || true
        echo "✓ Database user dropped"
        ;;
esac
echo ""

# ============================================================================
# STEP 4: REMOVE APPLICATION DIRECTORY
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Removing Application Directory"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -d "$APP_DIR" ]; then
    echo "Removing directory: $APP_DIR"

    # Show what will be deleted
    echo "Contents:"
    du -sh "$APP_DIR"/* 2>/dev/null | sed 's/^/  /' || echo "  (empty)"
    echo ""

    # Move to a backup location instead of deleting
    BACKUP_APP_DIR="${APP_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo "Moving to backup location: $BACKUP_APP_DIR"
    mv "$APP_DIR" "$BACKUP_APP_DIR"

    echo "✓ Application directory backed up and removed"
    echo "  (you can delete $BACKUP_APP_DIR later if not needed)"
else
    echo "Application directory does not exist"
fi
echo ""

# ============================================================================
# STEP 5: CLEAN UP DANGLING RESOURCES
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Cleaning Up Docker Resources"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Removing dangling images..."
docker image prune -f 2>/dev/null || true

echo "Removing unused volumes..."
docker volume prune -f 2>/dev/null || true

echo "✓ Docker cleanup complete"
echo ""

# ============================================================================
# STEP 6: VERIFICATION
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Checking removal status..."
REMAINING_CONTAINERS=$(docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" | wc -l)
REMAINING_IMAGES=$(docker images --filter "reference=${APP_NAME}" --format "{{.ID}}" | wc -l)

echo "  Containers: $([ $REMAINING_CONTAINERS -eq 0 ] && echo "✓ All removed" || echo "⚠️ $REMAINING_CONTAINERS remaining")"
echo "  Images: $([ $REMAINING_IMAGES -eq 0 ] && echo "✓ All removed" || echo "⚠️ $REMAINING_IMAGES remaining")"
echo "  App directory: $([ ! -d "$APP_DIR" ] && echo "✓ Removed" || echo "⚠️ Still exists")"

if [ "$DB_OPTION" != "1" ]; then
    DB_EXISTS=$(psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME" && echo "yes" || echo "no")
    echo "  Database: $([ "$DB_EXISTS" = "no" ] && echo "✓ Removed" || echo "⚠️ Still exists")"
fi
echo ""

echo "✅ Removal complete!"
echo ""

# ============================================================================
# STEP 7: REBUILD OPTION
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 7: Rebuild Application"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Do you want to rebuild the application now? (y/n): " REBUILD
echo ""

if [[ "$REBUILD" =~ ^[Yy]$ ]]; then
    echo "Starting rebuild..."
    echo ""

    # Check if setup script exists
    if [ -f "$DEVOPS_DIR/apps/$APP_NAME/setup.sh" ]; then
        cd "$DEVOPS_DIR/apps/$APP_NAME"
        ./setup.sh
        echo ""
        echo "✅ Setup complete!"
        echo ""
        echo "Next step: Edit configuration and deploy"
        echo "  1. Edit env file: nano $APP_DIR/.env.production"
        echo "  2. Update ALLOWED_ORIGINS, MAILGUN credentials, etc."
        echo "  3. Deploy: cd $DEVOPS_DIR/apps/$APP_NAME && ./deploy.sh"
    else
        echo "⚠️  Setup script not found: $DEVOPS_DIR/apps/$APP_NAME/setup.sh"
        echo ""
        echo "Manual rebuild steps:"
        echo "  1. Go to DevOps directory: cd $DEVOPS_DIR/apps/$APP_NAME"
        echo "  2. Run setup: ./setup.sh"
        echo "  3. Edit configuration: nano ~/apps/$APP_NAME/.env.production"
        echo "  4. Deploy: ./deploy.sh"
    fi
else
    echo "Skipping rebuild"
    echo ""
    echo "To rebuild later, run:"
    echo "  cd $DEVOPS_DIR/apps/$APP_NAME"
    echo "  ./setup.sh"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Process Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary of what was removed:"
echo "  • Containers: $REMAINING_CONTAINERS remaining"
echo "  • Images: $REMAINING_IMAGES remaining"
echo "  • App directory: $([ -d "$BACKUP_APP_DIR" ] && echo "Backed up to $BACKUP_APP_DIR" || echo "N/A")"
case $DB_OPTION in
    1) echo "  • Database: Preserved" ;;
    2) echo "  • Database: Dropped (backup at $BACKUP_FILE)" ;;
    3) echo "  • Database: Dropped (no backup)" ;;
esac
echo ""
