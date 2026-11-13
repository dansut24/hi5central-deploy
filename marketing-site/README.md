# Marketing site navigation & theme remediation (13 November 2026)

Purpose: Fix Production Readiness MKT-001 and MKT-002 without replacing Hi5Central's existing ITSM signup, identity, API, or tenant workspaces.

Source: \`hi5central-deploy/marketing-site/\`.
Deploy only to the **original** VPS \`ubuntu\`; do not use the EU environment.

## Routes
- Marketing pages: \`/\`, \`/products\`, \`/pricing\`, \`/about\`, \`/contact\`, \`/privacy\`
- Marketing assets: \`/_site/*\`, \`/robots.txt\`, \`/sitemap.xml\`
- Contact submissions: \`POST /contact/submit\`, CSRF Origin checked and rate limited
- Internal review page: \`/contact-inbox\`; **Caddy Basic Auth mandatory**
- Preserve \`/signup\`, \`/onboarding\`, \`/api/*\` and existing ITSM frontend fallback unchanged.
- Separate 10001:10001 unprivileged Python container on existing internal Docker network, no published host port.

## Content
- Explicit ITSM, RMM, combined product pages and supporting tools.
- Pricing is quote-based (no unconfirmed subscription figures).
- Header/footer links for Products, Pricing, About, Contact, Status, Signup.
- System light/dark mode + user override in client localStorage.
- Responsive mobile navigation and semantic HTML/SEO metadata.

## Contact
- Form writes to \`/opt/hi5central/runtime/marketing-site/data/contact.sqlite3\`.
- Private review at \`https://hi5central.com/contact-inbox\` with the **QA portal's Basic Auth**.
- Staff must manually review the inbox. No email or push notification is claimed.
- Live database prunes enquiries older than 90 days on application start. Backups may have different retention.
- The original VPS has a root-only online SQLite backup script at `/usr/local/sbin/hi5central-marketing-contact-backup`, scheduled daily at 03:05 UTC via `/etc/cron.d/hi5central-marketing-contact-backup`. Source is `marketing-site/backup.py`. It prunes live enquiries older than 90 days, verifies the snapshot with SQLite integrity checks and retains 30 days of **local** backups in `/opt/hi5central/recovery/marketing-contact`. Off-server encrypted backup and full restore are still pending.
- Do not enter passwords, secrets or sensitive ticket/customer data.

## Production verification
1. Start container and verify \`/healthz\`, five pages, assets, sitemap in the private network.
2. Backup original Caddyfile, make a **host+path scoped** route for the marketing pages, preserving signup/API fallback. Protect \`/contact-inbox\` before the public pages. Validate Caddy before reload.
3. Browser/headless smoke: click navigation, inspect accessible links, confirm system dark mode + manual override and mobile menu.
4. Verify \`/signup\` retains original application, and \`/api/v1/... \` retains backend auth responses.
5. Test contact form in a controlled account, read back from authenticated inbox.
6. Manual tester verifies MKT-001/MKT-002, then marks Passed in production QA register. Do not count code build alone as a pass.

## Security
This is an internal small-team system, not a CRM. Migrate to proper individual Admin SSO, approved outbound email and a full privacy policy before opening broad customer acquisition.

## Verified on original VPS — 13 November 2026

- All six marketing pages serve valid HTML with distinct title and canonical URL.
- Public navigation/link sweep: 12 unique local/status targets, zero failures; both hi5central.com and www verified.
- System dark-mode CSS, manual-theme script and mobile menu JavaScript present and syntax-checked; physical iPhone visual check outstanding.
- Contact form saved a controlled test enquiry, confirmed the server database record, then removed the test entry. Anonymous contact inbox returned 401.
- Existing /signup HTML hash was identical before and after Caddy routing. /api/v1/catalogue continued returning expected anonymous 401.
- Daily contact database backup script passed its first run with SQLite integrity validation.
- Automated smoke workflow: https://github.com/dansut24/hi5central-deploy/actions/runs/43490716184 (success).
- QA tracker: MKT-002 and MKT-011 Passed; MKT-001 In progress pending real mobile dark-mode visual acceptance.
