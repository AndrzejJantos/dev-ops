#!/bin/bash

echo "Quick Diagnostic for premiera.taniejpolek.pl"
echo "============================================="
echo ""

# 1. Test container directly
echo "1. Testing container directly on port 3030:"
curl -I http://localhost:3030/ 2>&1 | head -10
echo ""

# 2. Check nginx status
echo "2. Nginx status:"
sudo systemctl status nginx --no-pager -l | head -10
echo ""

# 3. Test nginx config
echo "3. Testing nginx config:"
sudo nginx -t
echo ""

# 4. Check if nginx config exists
echo "4. Nginx config file:"
if [ -f /etc/nginx/sites-available/cheaperfordrug-web ]; then
    echo "   EXISTS: /etc/nginx/sites-available/cheaperfordrug-web"
    echo "   First 30 lines:"
    head -30 /etc/nginx/sites-available/cheaperfordrug-web | sed 's/^/   /'
else
    echo "   MISSING: /etc/nginx/sites-available/cheaperfordrug-web"
fi
echo ""

# 5. Check if enabled
echo "5. Is nginx config enabled?"
if [ -L /etc/nginx/sites-enabled/cheaperfordrug-web ]; then
    echo "   YES - symlink exists"
else
    echo "   NO - symlink missing!"
    echo "   Run: sudo ln -s /etc/nginx/sites-available/cheaperfordrug-web /etc/nginx/sites-enabled/"
fi
echo ""

# 6. Check SSL certificates
echo "6. SSL Certificates:"
if [ -d /etc/letsencrypt/live/premiera.taniejpolek.pl ]; then
    echo "   EXISTS: /etc/letsencrypt/live/premiera.taniejpolek.pl"
    sudo ls -lh /etc/letsencrypt/live/premiera.taniejpolek.pl/ | sed 's/^/   /'
else
    echo "   MISSING: SSL certificates not found"
    echo "   Run: sudo certbot --nginx -d premiera.taniejpolek.pl -d www.premiera.taniejpolek.pl"
fi
echo ""

# 7. Check nginx error log
echo "7. Recent nginx errors (last 10 lines):"
if [ -f /var/log/nginx/cheaperfordrug-web-error.log ]; then
    sudo tail -10 /var/log/nginx/cheaperfordrug-web-error.log | sed 's/^/   /'
else
    echo "   No error log found"
fi
echo ""

# 8. Test HTTPS locally
echo "8. Testing HTTPS locally:"
curl -I https://premiera.taniejpolek.pl 2>&1 | head -10
echo ""

echo "============================================="
echo "Quick diagnostic complete"
echo "============================================="
