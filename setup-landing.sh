#!/bin/bash

################################################################################
# Quick Setup Script for CheaperForDrug Landing
# Run as: bash setup-landing.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CheaperForDrug Landing Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as andrzej user
if [ "$(whoami)" != "andrzej" ]; then
    echo -e "${RED}ERROR: This script must be run as user 'andrzej'${NC}"
    echo -e "${YELLOW}Run: sudo -u andrzej bash setup-landing.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Running as user: andrzej"

# Ensure DevOps repo exists
if [ ! -d "$HOME/DevOps" ]; then
    echo -e "${YELLOW}→${NC} Cloning DevOps repository..."
    cd ~
    git clone git@github.com:AndrzejJantos/dev-ops.git DevOps || \
    git clone https://github.com/AndrzejJantos/dev-ops.git DevOps
    echo -e "${GREEN}✓${NC} DevOps repository cloned"
else
    echo -e "${GREEN}✓${NC} DevOps repository exists"
    cd ~/DevOps
    git pull origin master || true
fi

# Run the setup script
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Running Application Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cd ~/DevOps/apps/cheaperfordrug-landing

if [ ! -x "./setup.sh" ]; then
    chmod +x setup.sh
fi

./setup.sh

# Setup completed
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo -e "1. Edit environment variables:"
echo -e "   ${BLUE}nano ~/apps/cheaperfordrug-landing/.env.production${NC}"
echo ""
echo -e "   Update these keys:"
echo -e "   - STRIPE_PUBLISHABLE_KEY"
echo -e "   - STRIPE_SECRET_KEY"
echo -e "   - GOOGLE_ANALYTICS_ID"
echo -e "   - ROLLBAR_ACCESS_TOKEN"
echo ""
echo -e "2. Deploy the application:"
echo -e "   ${BLUE}cd ~/DevOps/apps/cheaperfordrug-landing${NC}"
echo -e "   ${BLUE}./deploy.sh deploy${NC}"
echo ""
echo -e "3. Check status:"
echo -e "   ${BLUE}docker ps | grep cheaperfordrug-landing${NC}"
echo ""
echo -e "4. Setup SSL (after DNS is configured):"
echo -e "   ${BLUE}sudo certbot --nginx -d presale.taniejpolek.pl${NC}"
echo ""
