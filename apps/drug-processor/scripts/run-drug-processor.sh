#!/bin/bash

# =============================================================================
# Drug Name Normalizer & Variant Processor - Orchestrator Script
# =============================================================================
#
# Self-contained execution (no docker exec):
# 1. Runs Python drug_name_normalizer.py for Poland (full version)
# 2. Runs Python drug_name_normalizer.py for Germany (initial version)
# 3. Runs Python drug_name_normalizer.py for Czech (initial version)
# 4. Runs BatchVariantProcessorService.new.call - ONCE for all countries
# 5. Sends email notifications on start/finish
#
# Schedule: 2 AM on Wednesday, Thursday, Friday, Saturday, Sunday
# Cron: 0 2 * * 0,3,4,5,6
#
# =============================================================================

set -e

# =============================================================================
# ENVIRONMENT SETUP (for cron execution)
# =============================================================================
# Cron starts with a minimal environment. Source /etc/environment which the
# container entrypoint populates with ALL env vars (DATABASE_URL, REDIS_URL,
# SENDGRID_API_KEY, RAILS_ENV, PATH, etc.).

if [ -f /etc/environment ]; then
    set -a
    . /etc/environment
    set +a
fi

# IMPORTANT: Unset GEM_HOME, GEM_PATH, BUNDLE_PATH so they don't override
# bundler's own config. The Ruby base image sets GEM_HOME=/usr/local/bundle
# but gems are installed in /app/api/vendor/bundle via deployment mode.
# If GEM_HOME or BUNDLE_PATH are set, bundler looks in the wrong place.
#
# KEEP BUNDLE_APP_CONFIG=/usr/local/bundle -- this is critical! It tells
# bundler to read config from /usr/local/bundle/config (which has the
# deployment=true setting and correct paths) instead of the source repo's
# stale .bundle/config (which has BUNDLE_PATH: ".bundle/vendor").
unset GEM_HOME
unset GEM_PATH
unset BUNDLE_PATH
export BUNDLE_APP_CONFIG="${BUNDLE_APP_CONFIG:-/usr/local/bundle}"

# Ensure PATH includes bundler/ruby/python bin directories
export PATH="/usr/local/bundle/bin:/usr/local/bin:/opt/python-venv/bin:${PATH}"

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_NAME="Drug Processor Pipeline"
LOG_FILE="/var/log/drug-processor/drug-processor-$(date +%Y%m%d).log"
TIMESTAMP_START=$(date '+%Y-%m-%d %H:%M:%S')
DAY_OF_WEEK=$(date '+%A')

# Paths (inside container)
DEVOPS_COMMON="/home/andrzej/DevOps/common"
SCRAPER_PATH="/app/scraper"
API_PATH="/app/api"

# Email configuration
EMAIL_FROM="${DEPLOYMENT_EMAIL_FROM:-biuro@webet.pl}"
EMAIL_TO="${DEPLOYMENT_EMAIL_TO:-andrzej@webet.pl}"
EMAIL_ENABLED="${DEPLOYMENT_EMAIL_ENABLED:-true}"

# Countries to process (order matters)
declare -A COUNTRIES=(
    ["PL"]="Poland|${SCRAPER_PATH}/python_scripts/poland/drug_name_normalizer.py|full"
    ["DE"]="Germany|${SCRAPER_PATH}/python_scripts/germany/drug_name_normalizer.py|initial"
    ["CZ"]="Czech|${SCRAPER_PATH}/python_scripts/czech/drug_name_normalizer.py|initial"
)
COUNTRY_ORDER=("PL" "DE" "CZ")

# Results tracking
declare -A NORMALIZER_RESULTS

# =============================================================================
# LOGGING
# =============================================================================

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_warning() { log "WARNING" "$@"; }

# =============================================================================
# EMAIL NOTIFICATION
# =============================================================================

# Source SendGrid API helper
if [ -f "$DEVOPS_COMMON/sendgrid-api.sh" ]; then
    source "$DEVOPS_COMMON/sendgrid-api.sh"
fi

send_notification() {
    local subject="$1"
    local body="$2"

    if [ "$EMAIL_ENABLED" != "true" ]; then
        log_info "Email notifications disabled, skipping"
        return 0
    fi

    if [ -z "${SENDGRID_API_KEY:-}" ]; then
        log_warning "SENDGRID_API_KEY not set, skipping email notification"
        return 0
    fi

    log_info "Sending email notification: $subject"

    if send_email_via_sendgrid "$EMAIL_FROM" "$EMAIL_TO" "$subject" "$body"; then
        log_info "Email notification sent successfully"
    else
        log_warning "Failed to send email notification"
    fi
}

# =============================================================================
# PYTHON NORMALIZERS (PL, DE, CZ) - LOCAL EXECUTION
# =============================================================================

run_python_normalizer() {
    local country_code="$1"
    local country_info="${COUNTRIES[$country_code]}"

    IFS='|' read -r country_name script_path version_type <<< "$country_info"

    log_info "=== Running Python Normalizer: $country_name ($country_code) - $version_type version ==="

    local start_time=$(date +%s)
    local output_file="/tmp/normalizer-${country_code}-output-$$.txt"

    # Check if script exists
    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script_path"
        NORMALIZER_RESULTS[$country_code]="FAILED|0s|Script not found"
        return 1
    fi

    log_info "Executing: python3 $script_path"

    if python3 "$script_path" > "$output_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_success "$country_name normalizer completed successfully in ${duration}s"

        # Extract stats from output
        local drugs_processed=$(grep -oP 'Total drugs processed: \K\d+' "$output_file" | tail -1 || echo "N/A")
        local unique_drugs=$(grep -oP 'Unique normalized drugs: \K\d+' "$output_file" | tail -1 || echo "N/A")

        NORMALIZER_RESULTS[$country_code]="SUCCESS|${duration}s|Processed: $drugs_processed, Unique: $unique_drugs"

        log_info "$country_name output summary:"
        tail -20 "$output_file" | tee -a "$LOG_FILE"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_error "$country_name normalizer failed after ${duration}s"
        NORMALIZER_RESULTS[$country_code]="FAILED|${duration}s|See log for details"

        log_error "Error output:"
        cat "$output_file" | tee -a "$LOG_FILE"

        rm -f "$output_file"
        return 1
    fi

    rm -f "$output_file"
    return 0
}

# =============================================================================
# RAILS BatchVariantProcessorService - LOCAL EXECUTION
# =============================================================================

run_batch_variant_processor() {
    log_info "=== Running BatchVariantProcessorService (ALL COUNTRIES) ==="

    local start_time=$(date +%s)
    local output_file="/tmp/variant-processor-output-$$.txt"

    # Change to API directory
    cd "$API_PATH"

    log_info "Executing BatchVariantProcessorService from $API_PATH"

    local rails_command='
result = BatchVariantProcessorService.new.call
puts "=== BATCH VARIANT PROCESSOR RESULT ==="
puts "Success: #{result[:success]}"
puts "Processed: #{result[:processed]}"
puts "Variants Created: #{result[:variants_created]}"
puts "Variants Updated: #{result[:variants_updated]}"
puts "Associations Updated: #{result[:associations_updated]}"
puts "Variants Reindexed: #{result[:variants_reindexed]}"
puts "Variants Deleted: #{result[:variants_deleted]}"
puts "Reassignments: #{result[:reassignments]}"
puts "Shopping List Items Moved: #{result[:shopping_list_items_moved]}"
if result[:errors].any?
  puts "Errors: #{result[:errors].join(", ")}"
end
puts "=== END RESULT ==="
'

    if bundle exec rails runner "$rails_command" > "$output_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_success "BatchVariantProcessorService completed successfully in ${duration}s"

        VARIANT_OUTPUT=$(cat "$output_file")
        VARIANT_DURATION="${duration}s"
        VARIANT_STATUS="SUCCESS"

        # Extract stats from output
        VARIANT_PROCESSED=$(grep "Processed:" "$output_file" | awk '{print $2}' || echo "N/A")
        VARIANT_CREATED=$(grep "Variants Created:" "$output_file" | awk '{print $3}' || echo "N/A")
        VARIANT_UPDATED=$(grep "Variants Updated:" "$output_file" | awk '{print $3}' || echo "N/A")
        VARIANT_DELETED=$(grep "Variants Deleted:" "$output_file" | awk '{print $3}' || echo "N/A")
        VARIANT_REINDEXED=$(grep "Variants Reindexed:" "$output_file" | awk '{print $3}' || echo "N/A")

        log_info "Variant processor output:"
        cat "$output_file" | tee -a "$LOG_FILE"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_error "BatchVariantProcessorService failed after ${duration}s"
        VARIANT_OUTPUT=$(cat "$output_file")
        VARIANT_DURATION="${duration}s"
        VARIANT_STATUS="FAILED"
        VARIANT_PROCESSED="N/A"
        VARIANT_CREATED="N/A"
        VARIANT_UPDATED="N/A"
        VARIANT_DELETED="N/A"
        VARIANT_REINDEXED="N/A"

        log_error "Error output:"
        cat "$output_file" | tee -a "$LOG_FILE"

        rm -f "$output_file"
        return 1
    fi

    rm -f "$output_file"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "=========================================="
    log_info "Starting $SCRIPT_NAME"
    log_info "Date: $TIMESTAMP_START ($DAY_OF_WEEK)"
    log_info "Mode: Self-contained (local execution)"
    log_info "=========================================="

    local pipeline_start=$(date +%s)
    local overall_status="SUCCESS"
    local normalizer_failures=0

    # Pre-flight check: verify bundle exec rails is available
    log_info "Pre-flight check: verifying Rails environment..."
    cd "$API_PATH"
    if bundle exec rails runner "puts 'Pre-flight OK'" > /dev/null 2>&1; then
        log_success "Pre-flight check passed: bundle exec rails is available"
    else
        log_error "Pre-flight check FAILED: 'bundle exec rails' not working"
        log_error "Environment dump:"
        log_error "  GEM_HOME=${GEM_HOME:-<unset>}"
        log_error "  BUNDLE_PATH=${BUNDLE_PATH:-<unset>}"
        log_error "  BUNDLE_APP_CONFIG=${BUNDLE_APP_CONFIG:-<unset>}"
        log_error "  PATH=$PATH"
        log_error "  which bundle: $(which bundle 2>&1 || echo 'not found')"
        log_error "  which rails: $(which rails 2>&1 || echo 'not found')"
        log_error "  .bundle/config: $(cat /app/api/.bundle/config 2>&1 || echo 'not found')"
        log_error "Aborting pipeline to avoid wasting time on normalizers"

        send_notification \
            "[FAILED] Drug Processor Pre-flight Check Failed - $(date '+%Y-%m-%d')" \
            "Drug Processor Pipeline ABORTED during pre-flight check.

The 'bundle exec rails' command is not working in the cron environment.
This means Phase 2 (BatchVariantProcessorService) would fail.

Environment:
  GEM_HOME=${GEM_HOME:-<unset>}
  BUNDLE_PATH=${BUNDLE_PATH:-<unset>}
  PATH=$PATH
  .bundle/config contents: $(cat /app/api/.bundle/config 2>&1 || echo 'not found')

Please check the container environment and /etc/environment.
Log file: $LOG_FILE"

        return 2
    fi

    # Send start notification
    send_notification \
        "[Drug Processor] Started - $DAY_OF_WEEK $(date '+%Y-%m-%d')" \
        "Drug Processor Pipeline has started.

Server: $(hostname)
Started: $TIMESTAMP_START
Day: $DAY_OF_WEEK
Mode: Self-contained container

Steps to execute:
1. Python Drug Name Normalizer - Poland (full version)
2. Python Drug Name Normalizer - Germany (initial version)
3. Python Drug Name Normalizer - Czech (initial version)
4. Rails BatchVariantProcessorService (all countries)

You will receive another notification when the process completes."

    # ==========================================================================
    # PHASE 1: Run Python normalizers for each country
    # ==========================================================================
    log_info ""
    log_info "=========================================="
    log_info "PHASE 1: Python Drug Name Normalizers"
    log_info "=========================================="

    for country_code in "${COUNTRY_ORDER[@]}"; do
        local country_info="${COUNTRIES[$country_code]}"
        IFS='|' read -r country_name script_path version_type <<< "$country_info"

        log_info ""
        log_info "------------------------------------------"
        log_info "Processing: $country_name ($country_code) - $version_type version"
        log_info "------------------------------------------"

        if run_python_normalizer "$country_code"; then
            log_success "$country_name normalizer completed"
        else
            log_error "$country_name normalizer failed"
            ((normalizer_failures++)) || true
        fi
    done

    # ==========================================================================
    # PHASE 2: Run Rails BatchVariantProcessor (once for all countries)
    # ==========================================================================
    log_info ""
    log_info "=========================================="
    log_info "PHASE 2: BatchVariantProcessorService"
    log_info "=========================================="

    local variant_status="PENDING"
    if run_batch_variant_processor; then
        variant_status="SUCCESS"
    else
        variant_status="FAILED"
        overall_status="PARTIAL_FAILURE"
    fi

    # Determine overall status
    if [ $normalizer_failures -gt 0 ]; then
        if [ "$variant_status" = "SUCCESS" ]; then
            overall_status="PARTIAL_FAILURE"
        else
            overall_status="FAILED"
        fi
    fi

    local pipeline_end=$(date +%s)
    local total_duration=$((pipeline_end - pipeline_start))
    local total_minutes=$((total_duration / 60))
    local total_seconds=$((total_duration % 60))

    log_info ""
    log_info "=========================================="
    log_info "Pipeline completed with status: $overall_status"
    log_info "Total duration: ${total_minutes}m ${total_seconds}s"
    log_info "=========================================="

    # Build normalizer results summary
    local normalizer_summary=""
    for country_code in "${COUNTRY_ORDER[@]}"; do
        local country_info="${COUNTRIES[$country_code]}"
        IFS='|' read -r country_name script_path version_type <<< "$country_info"
        local result="${NORMALIZER_RESULTS[$country_code]:-SKIPPED|N/A|Not executed}"
        IFS='|' read -r status duration details <<< "$result"

        normalizer_summary+="
$country_name ($country_code) - $version_type version:
  Status: $status
  Duration: $duration
  Details: $details
"
    done

    # Send completion notification
    local subject_prefix=""
    case "$overall_status" in
        SUCCESS) subject_prefix="[SUCCESS]" ;;
        PARTIAL_FAILURE) subject_prefix="[PARTIAL FAILURE]" ;;
        FAILED) subject_prefix="[FAILED]" ;;
    esac

    send_notification \
        "$subject_prefix Drug Processor Completed - $DAY_OF_WEEK $(date '+%Y-%m-%d')" \
        "Drug Processor Pipeline has completed.

========================================
SUMMARY
========================================
Server: $(hostname)
Started: $TIMESTAMP_START
Finished: $(date '+%Y-%m-%d %H:%M:%S')
Total Duration: ${total_minutes}m ${total_seconds}s
Overall Status: $overall_status

========================================
PHASE 1: Python Normalizers
========================================
$normalizer_summary

========================================
PHASE 2: BatchVariantProcessorService
========================================
Status: $VARIANT_STATUS
Duration: ${VARIANT_DURATION:-N/A}
Processed: ${VARIANT_PROCESSED:-N/A}
Variants Created: ${VARIANT_CREATED:-N/A}
Variants Updated: ${VARIANT_UPDATED:-N/A}
Variants Deleted: ${VARIANT_DELETED:-N/A}
Variants Reindexed: ${VARIANT_REINDEXED:-N/A}

========================================
Log file: $LOG_FILE
========================================

This is an automated message from the Drug Processor Pipeline.
Schedule: 2 AM on Wed, Thu, Fri, Sat, Sun"

    # Return appropriate exit code
    case "$overall_status" in
        SUCCESS) return 0 ;;
        PARTIAL_FAILURE) return 1 ;;
        FAILED) return 2 ;;
    esac
}

# Run main function
main "$@"
