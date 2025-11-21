#!/bin/bash

# Pull Production Database Locally
# Location: DevOps/scripts/db-pull-prod.sh
# Usage: ./db-pull-prod.sh [app-name]
# Example: ./db-pull-prod.sh cheaperfordrug-api

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Progress bar function
progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r${CYAN}[${NC}"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "${CYAN}]${NC} %3d%%" "$percentage"
}

# Format seconds to human readable
format_time() {
    local seconds=$1
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

# Check for pv (pipe viewer) for better progress
check_pv() {
    command -v pv >/dev/null 2>&1
}

# Configuration
SSH_HOST="${SSH_HOST:-hetzner-andrzej}"
APP_NAME="${1:-cheaperfordrug-api}"

# Generic database name generation
# Pattern: "myapp-api" -> "myapp_production" (API suffix stripped)
# Pattern: "myapp-landing" -> "myapp_landing_production" (kept as-is)
# Local DB matches prod DB exactly
if [[ "$APP_NAME" == *-api ]]; then
    APP_BASE=$(echo "$APP_NAME" | sed 's/-api$//' | tr '-' '_')
    PROD_DB="${APP_BASE}_production"
else
    PROD_DB="${APP_NAME//-/_}_production"
fi
LOCAL_DB="$PROD_DB"

DUMP_FILE="/tmp/${PROD_DB}_$(date +%Y%m%d_%H%M%S).sql.gz"
REMOTE_DUMP="/tmp/${PROD_DB}.sql.gz"

echo ""
echo "========================================"
echo "  Pull Production Database"
echo "========================================"
echo ""
echo "App:        $APP_NAME"
echo "Prod DB:    $PROD_DB"
echo "Local DB:   $LOCAL_DB"
echo "SSH Host:   $SSH_HOST"
echo ""

# Confirm
read -p "This will REPLACE your local '$LOCAL_DB' database. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_info "Cancelled"
    exit 0
fi

TOTAL_START=$(date +%s)

# Step 1: Create dump on remote server
echo ""
log_info "Step 1/4: Creating dump on $SSH_HOST..."
START_TIME=$(date +%s)
ssh "$SSH_HOST" "sudo -u postgres pg_dump $PROD_DB | gzip > $REMOTE_DUMP"
REMOTE_SIZE=$(ssh "$SSH_HOST" "ls -lh $REMOTE_DUMP | awk '{print \$5}'")
REMOTE_BYTES=$(ssh "$SSH_HOST" "stat -c%s $REMOTE_DUMP 2>/dev/null || stat -f%z $REMOTE_DUMP")
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
log_success "Dump created: $REMOTE_SIZE ($(format_time $ELAPSED))"

# Step 2: Download dump with progress
echo ""
log_info "Step 2/4: Downloading dump ($REMOTE_SIZE)..."
START_TIME=$(date +%s)

if check_pv; then
    ssh "$SSH_HOST" "cat $REMOTE_DUMP" | pv -s "$REMOTE_BYTES" -p -t -e -r > "$DUMP_FILE"
else
    # Use rsync with progress as fallback
    rsync -avz --progress -e ssh "$SSH_HOST:$REMOTE_DUMP" "$DUMP_FILE" 2>&1 | \
        grep -E "^\s*[0-9]" | while read line; do
            echo -ne "\r$line"
        done
    echo ""
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
LOCAL_SIZE=$(ls -lh "$DUMP_FILE" | awk '{print $5}')
log_success "Downloaded: $LOCAL_SIZE ($(format_time $ELAPSED))"

# Step 3: Drop and create local database
echo ""
log_info "Step 3/4: Recreating local database '$LOCAL_DB'..."
START_TIME=$(date +%s)
dropdb --if-exists "$LOCAL_DB"
createdb "$LOCAL_DB"
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
log_success "Database created ($(format_time $ELAPSED))"

# Step 4: Import dump with progress
echo ""
log_info "Step 4/4: Importing dump..."
START_TIME=$(date +%s)

# Get uncompressed size estimate (typically 5-10x compressed size)
UNCOMPRESSED_EST=$((REMOTE_BYTES * 7))

if check_pv; then
    gunzip -c "$DUMP_FILE" | pv -s "$UNCOMPRESSED_EST" -p -t -e -r | psql -q "$LOCAL_DB" 2>&1 | grep -v "role .* does not exist" || true
else
    # Show spinning progress indicator
    gunzip -c "$DUMP_FILE" | psql -q "$LOCAL_DB" 2>&1 | grep -v "role .* does not exist" &
    PID=$!
    SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    i=0
    while kill -0 $PID 2>/dev/null; do
        i=$(( (i+1) % ${#SPIN} ))
        printf "\r${CYAN}[${NC}${SPIN:$i:1}${CYAN}]${NC} Importing..."
        sleep 0.1
    done
    wait $PID || true
    echo ""
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
log_success "Import complete ($(format_time $ELAPSED))"

# Step 5: Verify
TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))

echo ""
echo "========================================"
echo -e "  ${GREEN}✓ Import Complete${NC}"
echo "========================================"
echo ""
echo "  Local DB:      $LOCAL_DB"
echo "  Dump file:     $DUMP_FILE"
echo ""

# Get top 5 tables by row count
echo "  ┌─────────────────────────────────────┐"
echo "  │  Top Tables by Row Count            │"
echo "  ├─────────────────────────────────────┤"

psql -t -A -F'|' "$LOCAL_DB" -c "
SELECT relname, n_live_tup
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY n_live_tup DESC
LIMIT 5
" 2>/dev/null | while IFS='|' read -r table rows; do
    printf "  │  %-20s %'10s   │\n" "$table" "$rows"
done

echo "  └─────────────────────────────────────┘"
echo ""
echo -e "  ${CYAN}Total time: $(format_time $TOTAL_ELAPSED)${NC}"
echo ""
log_warning "Update your database.yml to use '$LOCAL_DB' for development"
echo ""
