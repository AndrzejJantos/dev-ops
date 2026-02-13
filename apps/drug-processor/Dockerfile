# =============================================================================
# Drug Processor - Self-Contained Docker Image
# =============================================================================
#
# Self-contained container with:
# - Python environment for drug name normalizers (PL, DE, CZ)
# - Ruby/Rails environment for BatchVariantProcessorService
# - Cron daemon for scheduled execution
#
# Connects to the same database as production API (host network mode).
#
# Build context: Project root (to access cheaperfordrug-api/, cheaperfordrug-scraper/)
# Build command: docker build -f DevOps/apps/drug-processor/Dockerfile -t drug-processor:latest .
#
# =============================================================================

FROM ruby:3.4.5-bookworm

LABEL maintainer="andrzej@webet.pl"
LABEL description="Drug Processor Pipeline - Python Normalizers + Rails BatchVariantProcessor"
LABEL version="2.0"

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Warsaw

# Set Rails environment
ENV RAILS_ENV=production
ENV RACK_ENV=production
ENV NODE_ENV=production

# =============================================================================
# INSTALL SYSTEM DEPENDENCIES
# =============================================================================

RUN apt-get update && apt-get install -y \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    # Build tools
    build-essential \
    libpq-dev \
    # Utilities
    curl \
    cron \
    tzdata \
    git \
    # Node.js (for Rails assets if needed)
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/* \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# =============================================================================
# SETUP PYTHON ENVIRONMENT
# =============================================================================

RUN python3 -m venv /opt/python-venv
ENV PATH="/opt/python-venv/bin:$PATH"

RUN pip install --no-cache-dir \
    requests \
    python-dotenv

# =============================================================================
# SETUP RUBY/RAILS (API)
# =============================================================================

WORKDIR /app/api

# Copy API Gemfile first for layer caching
COPY cheaperfordrug-api/Gemfile cheaperfordrug-api/Gemfile.lock ./

# Install Ruby gems
RUN bundle config set --local deployment 'true' \
    && bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 3

# Copy API application code (exclude .bundle to keep container-compiled gems)
COPY cheaperfordrug-api/ ./
RUN rm -rf .bundle/vendor && rm -f .bundle/config && bundle install --jobs 4 --retry 3

# =============================================================================
# SETUP PYTHON SCRIPTS (SCRAPER)
# =============================================================================

WORKDIR /app/scraper

# Copy only the python_scripts directory from scraper
COPY cheaperfordrug-scraper/python_scripts/ ./python_scripts/

# =============================================================================
# SETUP ORCHESTRATOR
# =============================================================================

WORKDIR /app

# Create directories
RUN mkdir -p /var/log/drug-processor \
    && mkdir -p /home/andrzej/DevOps/common

# Copy orchestrator scripts and common utilities
COPY DevOps/apps/drug-processor/scripts/ /app/scripts/
COPY DevOps/apps/drug-processor/common/ /home/andrzej/DevOps/common/

# Copy cron configuration
COPY DevOps/apps/drug-processor/cron.d/drug-processor /etc/cron.d/drug-processor

# Set permissions
RUN chmod +x /app/scripts/*.sh \
    && chmod 0644 /etc/cron.d/drug-processor \
    && touch /var/log/drug-processor/cron.log

# =============================================================================
# ENTRYPOINT
# =============================================================================

RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "============================================"
echo "Drug Processor Container (Self-Contained)"
echo "============================================"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Timezone: $TZ"
echo "Rails Environment: $RAILS_ENV"
echo ""

# Export environment variables for cron (which starts with minimal env).
# EXCLUDE GEM_HOME, GEM_PATH, BUNDLE_PATH because the Ruby base image sets
# these to /usr/local/bundle, but our Dockerfile builds with deployment mode
# which puts gems in vendor/bundle. These vars would override .bundle/config.
# KEEP BUNDLE_APP_CONFIG -- it tells bundler where to find its global config
# (/usr/local/bundle/config) which has the correct deployment settings.
printenv | grep -v '^GEM_HOME=' | grep -v '^GEM_PATH=' | grep -v '^BUNDLE_PATH=' | sed 's/^\([^=]*\)=\(.*\)$/\1="\2"/' > /etc/environment

# Validate database connection
echo "Checking database connection..."
cd /app/api
if bundle exec rails runner "puts 'Database OK'" 2>/dev/null; then
    echo "Database connection: OK"
else
    echo "WARNING: Database connection may have issues - check DATABASE_URL"
fi

# Log schedule
echo ""
echo "Cron schedule configured:"
cat /etc/cron.d/drug-processor | grep -v "^#" | grep -v "^$" | head -5
echo ""

# Check Python
echo "Python: $(python3 --version)"
echo "Python scripts:"
for script in /app/scraper/python_scripts/*/drug_name_normalizer.py; do
    if [ -f "$script" ]; then
        country=$(basename $(dirname "$script"))
        echo "  - $country: $script"
    fi
done
echo ""

# Start cron daemon in foreground
echo "Starting cron daemon..."
echo "============================================"
cron -f
EOF
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep cron > /dev/null || exit 1

WORKDIR /app

CMD ["/entrypoint.sh"]
