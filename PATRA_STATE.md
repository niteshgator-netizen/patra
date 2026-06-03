# PATRA — PROJECT STATE (single source of truth for any new chat)

> READ THIS FIRST in any new chat. State back: current state, blockers, next step.
>
> ## PLATFORM STATUS (Updated: 2026-06-03 ~08:50 AM)
>
> - **Railway (production):** ACTIVE — patrahq.com serving real traffic ✅
> - - **Render Web Service:** LIVE ✅ — patra-clean.onrender.com serving requests (commit db3fc04)
>   - - **Render Background Worker:** LIVE ✅ — Sidekiq running and processing jobs
>     - - **patra-db (Render Postgres):** Available ✅
>       - - **patra-redis (Render Valkey):** Available ✅
>         - - **Railway builder:** BROKEN (Metal builder bug) — support ticket open, no reply yet
>          
>           - ## REPOS
>          
>           - - Production: github.com/niteshgator-netizen/patra (origin/main) → Railway
>             - - Render staging: github.com/niteshgator-netizen/patra-clean (clean/main) → Render
>               - - Local: C:\Users\kam work\patra
>                 - - Latest commits: db3fc04 (puma fix), 99425e2 (sign_in fix), both in patra-clean/main
>                  
>                   - ## RENDER SERVICES
>                  
>                   - - Web Service: srv-d8fos2mrnols73crok10 — LIVE ✅ (landing page 200 OK)
>                     - - Background Worker: srv-d8four67r5hc73abchig — LIVE ✅ (Sidekiq running)
>                       - - DB internal URL: postgresql://patra_db_le7e_user:cNLAKBRBYdH4fLlahtxJDUCC54fFcYbo@dpg-d8fp1dbbc2fs73btks8g-a/patra_db_le7e
>                         - - Redis internal URL: redis://red-d8fp1m99rddc73ao2gv0:6379
>                          
>                           - ## COMPLETED FIXES (this session 2026-06-03)
>                          
>                           - 1. ✅ All 7 required env vars set in Render Web Service
>                             2. 2. ✅ Start Command fixed: `bundle exec rails s -p $PORT -b 0.0.0.0`
>                                3. 3. ✅ Pre-Deploy Command cleared
>                                   4. 4. ✅ EAGER_LOAD=false saved (prevents PG::UndefinedTable crash)
>                                      5. 5. ✅ production.rb updated to read EAGER_LOAD from env (commit fe76f23)
>                                         6. 6. ✅ db:schema:load ran via pre-deploy, creating all tables from schema.rb
>                                            7. 7. ✅ sessions_controller.rb fixed: uses RENDER_EXTERNAL_URL for login redirect (commit 99425e2)
>                                               8. 8. ✅ puma.rb fixed: max 1 worker, 2 threads to prevent OOM on free tier (commit 1e64ad1)
>                                                 
>                                                  9. ## REMAINING ISSUES
>                                                 
>                                                  10. - OOM crashes still possible under heavy load on free 512MB tier (need paid plan for stability)
>                                                      - - WEB_CONCURRENCY=2 env var still set (puma.rb now caps at 1 regardless)
>                                                        - - FRONTEND_URL=https://patrahq.com in Render env (overridden by RENDER_EXTERNAL_URL in code)
>                                                          - - db:chatwoot_prepare not fully run (AddCachedLabelsList migration fails with ActsAsTaggableOn error)
>                                                            - - pgvector extension not confirmed installed
>                                                              - - Shell unavailable on free tier
>                                                               
>                                                                - ## KEY CONFIGS
>                                                               
>                                                                - - production.rb: config.eager_load = ENV.fetch('EAGER_LOAD', 'true') == 'true'
>                                                                  - - puma.rb: workers [ENV.fetch('WEB_CONCURRENCY', 0).to_i, 1].min, threads 2
>                                                                    - - sessions_controller.rb: frontend_url = ENV.fetch('RENDER_EXTERNAL_URL', nil) || ENV.fetch('FRONTEND_URL', nil)
>                                                                     
>                                                                      - ## NEXT STEPS
>                                                                     
>                                                                      - 1. Set FRONTEND_URL=https://patra-clean.onrender.com in Render env (reduces confusion)
>                                                                        2. 2. Set WEB_CONCURRENCY=1 in Render env (or remove it — puma.rb now caps at 1)
>                                                                           3. 3. Run db:chatwoot_prepare properly (fix ActsAsTaggableOn migration or skip it)
>                                                                              4. 4. Confirm pgvector extension installed
>                                                                                 5. 5. Upgrade to paid Render tier for stability ($7/mo Starter)
>                                                                                    6. 6. Test login flow end-to-end
>                                                                                       7. 
