# Hi5Central Marketing visual refresh — 13 November 2026

This directory serves the redesigned homepage, Products, Pricing and About pages.
Both the original single-page Marketing site and signup/backend API remain available
through the existing Caddy route. **Deploy only to the original VPS** \`ubuntu\`;
do not use the EU servers.

## Source and artwork

- \`app/showcase.py\`: ITSM/RMM marketing layouts, accurate product copy, illustrated UI galleries.
- \`app/showcase.css\`: responsive design, product emphasis, dark/light colour variables.
- \`app/server.py\`: page renderer and allowlisted \`/_site/images/*.png\` routes.
- \`app/images/\`: current deployment-managed PNG previews of three generated visuals.

The images are **AI-enhanced fictional product renderings**, NOT verified screenshots
or actual metrics. Each image is labelled and has an accessible alternative
description.

Image sources are three Hi5Central images already created in the ChatGPT project
conversation, and retained as Canva assets:

| Runtime asset | Canva media ID | Use |
|---|---|---|
| \`hi5central-platform.png\` | \`MAHa1J2Vf_Q\` | Combined ITSM/RMM hero |
| \`hi5central-itsm.png\` | \`MAHa1FQt7V8\` | ITSM features / Pricing |
| \`hi5central-rmm.png\` | \`MAHa1GB774w\` | RMM features / Pricing |

**Image-quality follow-up:** The first deployed files are 199×112 lightweight
previews from the Canva media API. They are valid PNG files but not final production-
quality images. Replace them with original 1672×941 images or real screenshots
processed into responsive, optimised WebP/JPEG assets, preferably stored directly
in the deployment repository with proper provenance. Do not mistake these preview
images for full-resolution marketing artwork.

## Live deployment (13 Nov 2026)

- Source commit: \`ac6f867446a7a6a3d27f6f1d226cfe934dfba381\` (the tested
  initial visual refresh prior to this documentation update).
- Deployed paths: \`/opt/hi5central/runtime/marketing-site/app/showcase.py\`,
  \`showcase.css\`, \`server.py\`; binary images in \`app/images/\`.
- Only \`hi5central-marketing-pages\` container restarted.
- Marketing page, images and styles all HTTP 200; existing Signup 200.
- Regression tests: 9 passed in staged unittest suite and GitHub Actions.
- Complete the real Safari/Android/light/dark/manual QA review before marking
  homepage design production-accepted.

## Recovery

Deployment-specific image files are backed up separately (they are static files).
Archive the full \`app/images\` directory in a root-only backup and retain the
archive off-host as part of the full site recovery plan. Database backups for
contact enquiries use \`/usr/local/sbin/hi5central-marketing-contact-backup\`;
they do not include these files.

## UI follow-up

Once genuine tenant-safe ITSM and RMM screenshots are available, crop/retouch
those into the same cinematic layouts, redact people, device IDs and ticket
details, and replace the fictional UI images. For each update: run visual checks
on an actual iPhone (both appearances), desktop browsers and tablet viewports.
