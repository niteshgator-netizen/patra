# PATRA REPLAY REPORT

Generated: 2026-06-11T22:52:42Z · account=2 · rows graded: 73070

## TIER 1 — deterministic routing (real IntentDetector, zero LLM)

HEADLINE: 73070 rows · resolved 32571 (44.6%) · fallthrough 40499 · **money-label misses (HIGH): 27883** · label-mismatch (informational, labels noisy): 7494 · detect errors: 0

| real_intent | rows | resolved | matched | mismatch | fallthrough | money-miss |
|---|---|---|---|---|---|---|
| load_deposit | 20907 | 10917 | 10437 | 480 | 9990 | 9990 |
| payment_handle_request | 9414 | 3195 | 2238 | 957 | 6219 | 6219 |
| load_freeplay | 8935 | 6829 | 6368 | 461 | 2106 | 2106 |
| greeting_chitchat | 5513 | 648 | 0 | 0 | 4865 | 0 |
| cashout_redeem | 4621 | 2253 | 1438 | 815 | 2368 | 2368 |
| status_check | 4542 | 1378 | 334 | 1044 | 3164 | 3164 |
| payment_sent_confirmation | 3618 | 1613 | 1420 | 193 | 2005 | 2005 |
| complaint_angry | 3575 | 1189 | 241 | 948 | 2386 | 0 |
| tech_issue | 2759 | 500 | 35 | 465 | 2259 | 0 |
| new_account_other_game | 1742 | 698 | 278 | 420 | 1044 | 0 |
| redeem_partial_replay | 1536 | 1121 | 502 | 619 | 415 | 415 |
| referral | 1212 | 440 | 63 | 377 | 772 | 772 |
| reset_password | 869 | 239 | 171 | 68 | 630 | 0 |
| whats_hitting | 860 | 428 | 271 | 157 | 432 | 0 |
| new_account_reissue | 797 | 224 | 107 | 117 | 573 | 0 |
| load_bonus | 601 | 382 | 349 | 33 | 219 | 219 |
| transfer_between_games | 404 | 151 | 19 | 132 | 253 | 253 |
| balance_check | 387 | 132 | 69 | 63 | 255 | 255 |
| unclear | 347 | 34 | 0 | 0 | 313 | 0 |
| replay_from_balance | 220 | 103 | 2 | 101 | 117 | 117 |
| new_account_new_player | 201 | 90 | 46 | 44 | 111 | 0 |
| cashout_rules | 2 | 2 | 2 | 0 | 0 | 0 |
| request_download_link | 2 | 2 | 2 | 0 | 0 | 0 |
| request_game_link | 2 | 0 | 0 | 0 | 2 | 0 |
| list_platforms | 2 | 2 | 2 | 0 | 0 | 0 |
| payment_method_question | 1 | 0 | 0 | 0 | 1 | 0 |
| request_app_link | 1 | 1 | 1 | 0 | 0 | 0 |

(fallthrough on greeting_chitchat/unclear is the designed outcome — excluded from clusters)

## TOP 25 FALLTHROUGH CLUSTERS

### 1. (266x) ``
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "$MegsnAvakian5"
  - "$CasiqueJorge69 10$"
  - "$phillipevans28"
  - "51.03"
  - "@Afaseler1981"

### 2. (94x) `thanks`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Thanks"
  - "Thanks"
  - "Thanks"
  - "Thanks"
  - "Thanks"

### 3. (92x) `i did`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "I did"
  - "I did"
  - "I did"
  - "I did"
  - "I did"

### 4. (76x) `same tag`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Same tag?"
  - "40%? Same tag?"
  - "40%? Same tag?"
  - "Same tag"
  - "Same tag"

### 5. (76x) `thank you`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Thank you"
  - "Thank you"
  - "Thank you"
  - "Thank you"
  - "Thank you"

### 6. (69x) `please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Please"
  - "Please"
  - "35 please"
  - "Please"
  - "Please"

### 7. (65x) `for juwa please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "For juwa please"
  - "For juwa please"
  - "For juwa please"
  - "For juwa please"
  - "For juwa please"

### 8. (65x) `on gv`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "On gv"
  - "On gv"
  - "On gv"
  - "10 on gv"
  - "10 on gv"

### 9. (62x) `cash out please`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "Cash out please"
  - "Cash out please"
  - "Cash out please"
  - "Cash out please"
  - "Cash out please"

### 10. (56x) `same chime`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Same chime"
  - "Same chime"
  - "Same chime"
  - "Same chime"
  - "40%? Same chime?"

### 11. (53x) `billion balls`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Billion balls"
  - "Billion balls"
  - "Billion balls"
  - "Billion balls"
  - "Billion balls"

### 12. (53x) `orions`
- failing grader: money-miss(HIGH) · top label: load_freeplay · suspected handler: handle_load_freeplay
  - "Orions"
  - "Orions"
  - "Orions"
  - "Orions"
  - "Orions"

### 13. (52x) `yes please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Yes please"
  - "Yes please"
  - "Yes please"
  - "Yes please"
  - "Yes Please"

### 14. (52x) `sent please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Sent 15 2.0 please"
  - "Sent 20 2.0 please"
  - "Sent 20 2.0 please"
  - "Sent 10 2.0 please"
  - "Sent 10 2.0 please"

### 15. (49x) `https cash app`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "https://cash.app/$Bandigang75"
  - "https://cash.app/$nickbean0629"
  - "https://cash.app/$BobbyBoggs4"
  - "https://cash.app/$BobbyBoggs4"
  - "$brokeagaincM https://cash.app/$brokeagainCM"

### 16. (48x) `juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa +30%"
  - "15/2.0 5 juwa"
  - "15 juwa 5 2.0"
  - "Juwa 5"
  - "10 juwa"

### 17. (45x) `juwa dyar`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa Dyar760"
  - "Juwa Dyar760"
  - "Juwa Dyar760"
  - "Juwa Dyar760"
  - "Juwa Dyar760"

### 18. (45x) `what's your paypal`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "What's your PayPal"
  - "What's your paypal"
  - "What's your paypal"
  - "What's your PayPal"
  - "What's your paypal"

### 19. (41x) `for original juwa please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "For original juwa please"
  - "For original juwa please"
  - "For original juwa please"
  - "For original juwa please"
  - "For original juwa please"

### 20. (40x) `same paypal`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Same paypal?"
  - "Same paypal?"
  - "Same paypal?"
  - "Same paypal?"
  - "Same paypal"

### 21. (39x) `loaded juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Loaded juwa"
  - "Loaded Juwa"
  - "Loaded Juwa"
  - "Loaded Juwa"
  - "Loaded juwa"

### 22. (38x) `on juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "On juwa"
  - "On juwa"
  - "On juwa"
  - "On Juwa"
  - "On Juwa"

### 23. (37x) `check out`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "Check out"
  - "Check out"
  - "Check out"
  - "Check out"
  - "Check out"

### 24. (36x) `for gv please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "For gv please"
  - "For gv please"
  - "For GV please"
  - "10 for gv please"
  - "For gv please"

### 25. (35x) `redeem plz`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "Redeem plz"
  - "Redeem plz"
  - "Redeem plz"
  - "Redeem plz"
  - "Redeem plz"

