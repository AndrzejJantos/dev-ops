# Drug Processor Pipeline

Automated pipeline that normalizes drug names and processes variants for multiple countries.

## What It Does

### Phase 1: Python Drug Name Normalizers (Sequential)
1. **Poland (PL)** - Full version with advanced normalization
2. **Germany (DE)** - Initial version (basic normalization)
3. **Czech (CZ)** - Initial version (basic normalization)

### Phase 2: Rails BatchVariantProcessor (Once)
4. **BatchVariantProcessorService** - Processes all countries at once
   - Groups drugs by normalized name
   - Creates/updates DrugVariants
   - Reindexes in Elasticsearch
   - Handles orphaned variants

### Email Notifications
- Sends email when pipeline starts
- Sends detailed report when pipeline finishes (per-country stats)

## Schedule

**2 AM** on **Wednesday, Thursday, Friday, Saturday, Sunday**

Cron: `0 2 * * 0,3,4,5,6`

## Country Versions

| Country | Code | Version | Notes |
|---------|------|---------|-------|
| Poland | PL | Full | Advanced normalization with brand extraction, context-aware processing |
| Germany | DE | Initial | Basic normalization - will be extended like PL |
| Czech | CZ | Initial | Basic normalization - will be extended like PL |

## Python Scripts Location (Scraper)

```
cheaperfordrug-scraper/python_scripts/
├── poland/
│   ├── drug_name_normalizer.py    # Full version
│   └── drug_name_processor.py     # Processing logic
├── germany/
│   └── drug_name_normalizer.py    # Initial version
└── czech/
    └── drug_name_normalizer.py    # Initial version
```

## Deployment

### Option 1: Docker Container (Recommended)

```bash
# Copy and configure environment
cp .env.example .env
nano .env  # Add your SENDGRID_API_KEY

# Build and deploy
./deploy.sh build

# View logs
./deploy.sh logs
```

### Option 2: Cron Job (Non-Docker)

```bash
# Install cron job directly
./deploy.sh cron
```

## Manual Execution

```bash
# Run via Docker
docker-compose exec drug-processor /app/scripts/run-drug-processor.sh

# Or run directly
./deploy.sh test
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `SENDGRID_API_KEY` | SendGrid API key for emails | Required |
| `DEPLOYMENT_EMAIL_FROM` | Sender email address | biuro@webet.pl |
| `DEPLOYMENT_EMAIL_TO` | Recipient email address | andrzej@webet.pl |
| `DEPLOYMENT_EMAIL_ENABLED` | Enable/disable emails | true |
| `SCRAPER_CONTAINER` | Name of scraper container | scraper-vpn-poland |
| `API_CONTAINER` | Name of API container | cheaperfordrug-api_web_1 |

## Logs

- Container logs: `docker-compose logs -f`
- Cron logs: `/var/log/drug-processor/cron.log`
- Daily logs: `/var/log/drug-processor/drug-processor-YYYYMMDD.log`

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    PHASE 1: Normalizers                      │
├─────────────────────────────────────────────────────────────┤
│  1. Poland (PL)     →  drug_name_normalizer.py (full)       │
│  2. Germany (DE)    →  drug_name_normalizer.py (initial)    │
│  3. Czech (CZ)      →  drug_name_normalizer.py (initial)    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 PHASE 2: Variant Processor                   │
├─────────────────────────────────────────────────────────────┤
│  4. BatchVariantProcessorService.new.call (ALL countries)   │
│     - Groups by normalized_name + country_id                │
│     - Creates/updates DrugVariants                          │
│     - Reindexes Elasticsearch                               │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Container not found

```bash
# Check running containers
docker ps --format '{{.Names}}'

# Update container names in .env
SCRAPER_CONTAINER=your-scraper-container
API_CONTAINER=your-api-container
```

### Country normalizer fails

The pipeline continues even if one country fails. Check logs for details:

```bash
tail -100 /var/log/drug-processor/drug-processor-$(date +%Y%m%d).log
```

## Files

```
drug-processor/
├── Dockerfile              # Container definition
├── docker-compose.yml      # Docker Compose config
├── deploy.sh               # Deployment script
├── .env.example            # Environment template
├── README.md               # This file
├── scripts/
│   └── run-drug-processor.sh  # Main orchestrator (PL, DE, CZ → API)
├── cron.d/
│   └── drug-processor      # Cron configuration
└── common/
    ├── sendgrid-api.sh     # Email helper
    └── utils.sh            # Logging utilities
```

## TODO: Extend DE/CZ Normalizers

The Germany and Czech normalizers are initial versions. To extend them like Poland:

1. Create `drug_name_processor.py` for each country
2. Add brand extraction logic
3. Add dosage/form parsing
4. Add context-aware processing
5. Add country-specific rules
