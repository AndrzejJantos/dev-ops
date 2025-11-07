# SendGrid Email Notifications - Quick Start Guide

## Setup in 3 Steps

### Step 1: Get SendGrid API Key (5 minutes)

1. Go to https://sendgrid.com and sign up (free tier: 100 emails/day)
2. Navigate to: **Settings** > **API Keys** > **Create API Key**
3. Name: "CheaperForDrug Deployments"
4. Permissions: Select **"Mail Send" - Full Access**
5. Click **Create & View**
6. **Copy the API key** (you'll only see it once!)
   - Format: `SG.xxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### Step 2: Verify Sender Email (2 minutes)

1. In SendGrid, go to: **Settings** > **Sender Authentication**
2. Click **Verify a Single Sender**
3. Fill in:
   - From Name: "CheaperForDrug DevOps"
   - From Email: biuro@webet.pl
   - Reply To: biuro@webet.pl
4. Complete the form and verify via email

### Step 3: Configure API Key (1 minute)

**Option A - In email-config.sh:**
```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps
nano common/email-config.sh

# Find this line and uncomment + set your key:
export SENDGRID_API_KEY="SG.paste_your_api_key_here"

# Save and exit (Ctrl+X, Y, Enter)
```

**Option B - Environment variable (more secure):**
```bash
echo 'export SENDGRID_API_KEY="SG.paste_your_api_key_here"' >> ~/.bashrc
source ~/.bashrc
```

---

## Test It!

```bash
cd /Users/andrzej/Development/CheaperForDrug/DevOps
./scripts/test-email-notification.sh
```

You should receive 3 test emails:
1. Simple test email
2. Sample deployment success notification
3. Sample deployment failure notification

---

## That's It!

Your deployment scripts will now automatically send email notifications via SendGrid when:
- Deployment succeeds
- Deployment fails

No further configuration needed!

---

## Monitoring

Check email delivery status in SendGrid dashboard:
https://app.sendgrid.com/activity

---

## Troubleshooting

### Emails not arriving?

1. **Check SendGrid Activity:**
   - https://app.sendgrid.com/activity
   - Look for your test emails
   - Check delivery status

2. **Check spam folder:**
   - SendGrid emails sometimes go to spam initially
   - Mark as "Not Spam" to train your email filter

3. **Verify sender authentication:**
   - Go to Settings > Sender Authentication
   - Make sure biuro@webet.pl is verified
   - Or set up domain authentication for better deliverability

4. **API Key issues:**
   ```bash
   # Check if API key is set:
   echo $SENDGRID_API_KEY

   # Should output: SG.xxxxxxxxxxxxxxxxxxxx
   # If empty, go back to Step 3
   ```

5. **Test with curl directly:**
   ```bash
   curl -X POST https://api.sendgrid.com/v3/mail/send \
     -H "Authorization: Bearer $SENDGRID_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "personalizations": [{"to": [{"email": "andrzej@webet.pl"}]}],
       "from": {"email": "biuro@webet.pl"},
       "subject": "Direct Test",
       "content": [{"type": "text/plain", "value": "Test from curl"}]
     }'
   ```
   - HTTP 202 = Success
   - HTTP 401 = Invalid API key
   - HTTP 403 = Wrong permissions

---

## Security Note

**Never commit your API key to git!**

The `email-config.sh` file should have the API key set, but you should be careful not to commit it with the actual key value.

Consider using environment variables (Option B) for production servers.

---

## Need Help?

- SendGrid Docs: https://docs.sendgrid.com
- API Reference: https://docs.sendgrid.com/api-reference/mail-send/mail-send
- Support: https://support.sendgrid.com

---

## Advanced: Domain Authentication (Optional but Recommended)

For better email deliverability, set up domain authentication:

1. Go to: **Settings** > **Sender Authentication** > **Authenticate Your Domain**
2. Choose your DNS host
3. Add the provided DNS records (CNAME records)
4. Wait for verification (usually 5-10 minutes)

Benefits:
- Better inbox placement (fewer spam flags)
- Shows "via sendgrid.net" badge in Gmail
- Professional appearance
- Higher delivery rates

This is optional but highly recommended for production use!
