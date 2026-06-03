# PATRA — SETUP CHECKLIST

> Track all infrastructure and setup tasks for the Render migration.

## DONE

- [x] Render Web Service created
- [x] Render Background Worker created
- [x] Render Postgres (patra-db) created
- [x] Render Redis (patra-redis) created
- [x] GitHub Actions asset pre-builder added
- [x] Railway production environment running (serving live traffic)

## HIGH PRIORITY

- [ ] Migrate Railway DB to Render DB
- [ ] Update DNS patrahq.com to Render
- [ ] Switch FB webhook URL to Render
- [ ] Test full payment flow on Render
- [ ] Confirm Render Web Service deploys green
- [ ] Confirm Render Background Worker is healthy

## IN PROGRESS

- [ ] Render Web Service — GitHub Actions building assets
- [ ] Monitoring Railway production during migration

## BACKLOG

- [ ] Remove Railway services after Render is stable
- [ ] Update all environment variable references
- [ ] Run smoke tests on Render production

Last updated: 2026-06-02
