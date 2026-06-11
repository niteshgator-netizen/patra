# PATRA REPLAY REPORT

Generated: 2026-06-11T23:22:37Z · account=2 · rows graded: 73070

## TIER 1 — deterministic routing (real IntentDetector, zero LLM)

HEADLINE: 73070 rows · resolved 37175 (50.9%) · fallthrough 35895 · **money-label misses (HIGH): 23497** · label-mismatch (informational, labels noisy): 8389 · detect errors: 0

| real_intent | rows | resolved | matched | mismatch | fallthrough | money-miss |
|---|---|---|---|---|---|---|
| load_deposit | 20907 | 13281 | 12645 | 636 | 7626 | 7626 |
| payment_handle_request | 9414 | 4308 | 3118 | 1190 | 5106 | 5106 |
| load_freeplay | 8935 | 7095 | 6511 | 584 | 1840 | 1840 |
| greeting_chitchat | 5513 | 698 | 0 | 0 | 4815 | 0 |
| cashout_redeem | 4621 | 2577 | 1732 | 845 | 2044 | 2044 |
| status_check | 4542 | 1501 | 401 | 1100 | 3041 | 3041 |
| payment_sent_confirmation | 3618 | 1718 | 1466 | 252 | 1900 | 1900 |
| complaint_angry | 3575 | 1229 | 236 | 993 | 2346 | 0 |
| tech_issue | 2759 | 510 | 35 | 475 | 2249 | 0 |
| new_account_other_game | 1742 | 783 | 278 | 505 | 959 | 0 |
| redeem_partial_replay | 1536 | 1145 | 518 | 627 | 391 | 391 |
| referral | 1212 | 450 | 63 | 387 | 762 | 762 |
| reset_password | 869 | 242 | 171 | 71 | 627 | 0 |
| whats_hitting | 860 | 442 | 266 | 176 | 418 | 0 |
| new_account_reissue | 797 | 232 | 107 | 125 | 565 | 0 |
| load_bonus | 601 | 409 | 361 | 48 | 192 | 192 |
| transfer_between_games | 404 | 167 | 18 | 149 | 237 | 237 |
| balance_check | 387 | 143 | 68 | 75 | 244 | 244 |
| unclear | 347 | 39 | 0 | 0 | 308 | 0 |
| replay_from_balance | 220 | 106 | 2 | 104 | 114 | 114 |
| new_account_new_player | 201 | 93 | 46 | 47 | 108 | 0 |
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

### 4. (76x) `thank you`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Thank you"
  - "Thank you"
  - "Thank you"
  - "Thank you"
  - "Thank you"

### 5. (52x) `yes please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Yes please"
  - "Yes please"
  - "Yes please"
  - "Yes please"
  - "Yes Please"

### 6. (49x) `https cash app`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "https://cash.app/$Bandigang75"
  - "https://cash.app/$nickbean0629"
  - "https://cash.app/$BobbyBoggs4"
  - "https://cash.app/$BobbyBoggs4"
  - "$brokeagaincM https://cash.app/$brokeagainCM"

### 7. (48x) `please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Please"
  - "Please"
  - "35 please"
  - "Please"
  - "Please"

### 8. (39x) `loaded juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Loaded juwa"
  - "Loaded Juwa"
  - "Loaded Juwa"
  - "Loaded Juwa"
  - "Loaded juwa"

### 9. (35x) `same game`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Same game"
  - "Same game"
  - "Same game"
  - "Same game"
  - "Same game"

### 10. (28x) `ready`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ready"
  - "Ready"
  - "Ready"
  - "Ready..?"
  - "Ready..?"

### 11. (27x) `request`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Request 60"
  - "Request 4"
  - "Request 4"
  - "Request $5"
  - "Request 5"

### 12. (27x) `ok thanks`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ok thanks"
  - "Ok thanks 🙏🏼🙏🏼💯"
  - "Ok thanks 🙏🏻🙏🏻💯"
  - "Ok thanks 🙏🏻🙏🏻💯"
  - "Ok thanks 🙏🏼🙏🏼💯"

### 13. (26x) `moolah`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "MooLah"
  - "Moolah"
  - "Moolah"
  - "Moolah"
  - "Moolah"

### 14. (25x) `ok done`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "Ok done"
  - "ok done"
  - "Ok done"
  - "Ok done"
  - "Ok done"

### 15. (25x) `paypal available`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "PayPal available?"
  - "PayPal available?"
  - "PayPal available?"
  - "PayPal available?"
  - "PayPal available"

### 16. (24x) `what s hitting`
- failing grader: fallthrough · top label: whats_hitting · suspected handler: handle_whats_hitting
  - "What’s hitting"
  - "What’s hitting"
  - "What’s hitting"
  - "What’s hitting"
  - "What’s hitting"

### 17. (24x) `it's not on there`
- failing grader: money-miss(HIGH) · top label: tech_issue · suspected handler: handle_tech_issue
  - "It's not on there"
  - "It's not on there"
  - "It's not on there"
  - "It's not on there"
  - "It's not on there"

### 18. (23x) `not loaded`
- failing grader: money-miss(HIGH) · top label: status_check · suspected handler: handle_status_check
  - "Not loaded"
  - "Not loaded"
  - "Not loaded"
  - "Not loaded"
  - "Not loaded"

### 19. (23x) `yolo ultra panda`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"

### 20. (21x) `same one`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Same one?"
  - "Same one"
  - "Same one"
  - "Same one"
  - "Same one ?"

### 21. (21x) `yes`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Yes  $carolinelovescash"
  - "Yes 18644997340"
  - "Yes\n$MichelleHenson13"
  - "Yes $12"
  - "Yes 10"

### 22. (20x) `sent request`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "Sent request"
  - "Sent request"
  - "Sent request"
  - "Sent request"
  - "Sent Request"

### 23. (20x) `ok ty`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ok ty"
  - "Ok ty"
  - "Ok ty"
  - "Ok ty"
  - "Ok ty"

### 24. (20x) `juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "15/2.0 5 juwa"
  - "15 juwa 5 2.0"
  - "juwa2.0"
  - "Juwa2.0"
  - "JuwA2. 0"

### 25. (20x) `chime gv please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Chime Gv please"
  - "Chime Gv please"
  - "Chime? Gv please"
  - "Chime? Gv please"
  - "Chime? Gv please"

