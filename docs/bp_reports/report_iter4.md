# PATRA REPLAY REPORT

Generated: 2026-06-11T23:34:49Z · account=2 · rows graded: 73070

## TIER 1 — deterministic routing (real IntentDetector, zero LLM)

HEADLINE: 73070 rows · resolved 37795 (51.7%) · fallthrough 35275 · **money-label misses (HIGH): 22969** · label-mismatch (informational, labels noisy): 8562 · detect errors: 0

| real_intent | rows | resolved | matched | mismatch | fallthrough | money-miss |
|---|---|---|---|---|---|---|
| load_deposit | 20907 | 13459 | 12800 | 659 | 7448 | 7448 |
| payment_handle_request | 9414 | 4521 | 3277 | 1244 | 4893 | 4893 |
| load_freeplay | 8935 | 7118 | 6515 | 603 | 1817 | 1817 |
| greeting_chitchat | 5513 | 710 | 0 | 0 | 4803 | 0 |
| cashout_redeem | 4621 | 2598 | 1732 | 866 | 2023 | 2023 |
| status_check | 4542 | 1561 | 449 | 1112 | 2981 | 2981 |
| payment_sent_confirmation | 3618 | 1747 | 1491 | 256 | 1871 | 1871 |
| complaint_angry | 3575 | 1234 | 237 | 997 | 2341 | 0 |
| tech_issue | 2759 | 541 | 42 | 499 | 2218 | 0 |
| new_account_other_game | 1742 | 786 | 278 | 508 | 956 | 0 |
| redeem_partial_replay | 1536 | 1145 | 518 | 627 | 391 | 391 |
| referral | 1212 | 451 | 63 | 388 | 761 | 761 |
| reset_password | 869 | 245 | 174 | 71 | 624 | 0 |
| whats_hitting | 860 | 475 | 298 | 177 | 385 | 0 |
| new_account_reissue | 797 | 236 | 106 | 130 | 561 | 0 |
| load_bonus | 601 | 409 | 361 | 48 | 192 | 192 |
| transfer_between_games | 404 | 168 | 18 | 150 | 236 | 236 |
| balance_check | 387 | 144 | 69 | 75 | 243 | 243 |
| unclear | 347 | 40 | 0 | 0 | 307 | 0 |
| replay_from_balance | 220 | 107 | 2 | 105 | 113 | 113 |
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

### 8. (35x) `same game`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Same game"
  - "Same game"
  - "Same game"
  - "Same game"
  - "Same game"

### 9. (28x) `ready`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ready"
  - "Ready"
  - "Ready"
  - "Ready..?"
  - "Ready..?"

### 10. (27x) `request`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Request 60"
  - "Request 4"
  - "Request 4"
  - "Request $5"
  - "Request 5"

### 11. (27x) `ok thanks`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ok thanks"
  - "Ok thanks 🙏🏼🙏🏼💯"
  - "Ok thanks 🙏🏻🙏🏻💯"
  - "Ok thanks 🙏🏻🙏🏻💯"
  - "Ok thanks 🙏🏼🙏🏼💯"

### 12. (26x) `moolah`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "MooLah"
  - "Moolah"
  - "Moolah"
  - "Moolah"
  - "Moolah"

### 13. (25x) `ok done`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "Ok done"
  - "ok done"
  - "Ok done"
  - "Ok done"
  - "Ok done"

### 14. (23x) `yolo ultra panda`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"
  - "20 yolo 20 ultra panda"

### 15. (21x) `yes`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Yes  $carolinelovescash"
  - "Yes 18644997340"
  - "Yes\n$MichelleHenson13"
  - "Yes $12"
  - "Yes 10"

### 16. (21x) `same one`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Same one?"
  - "Same one"
  - "Same one"
  - "Same one"
  - "Same one ?"

### 17. (20x) `cash me out`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "Cash me out 60"
  - "Cash me out"
  - "Cash me out"
  - "Cash me out 50.00"
  - "Cash me out $15"

### 18. (20x) `ok ty`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ok ty"
  - "Ok ty"
  - "Ok ty"
  - "Ok ty"
  - "Ok ty"

### 19. (20x) `any suggestions`
- failing grader: money-miss(HIGH) · top label: whats_hitting · suspected handler: handle_whats_hitting
  - "Any suggestions"
  - "Any suggestions 🤔"
  - "Any suggestions"
  - "Any suggestions 🤔"
  - "Any suggestions"

### 20. (20x) `loaded yet`
- failing grader: money-miss(HIGH) · top label: status_check · suspected handler: handle_status_check
  - "Loaded yet"
  - "Loaded yet"
  - "Loaded yet"
  - "Loaded yet"
  - "Loaded yet"

### 21. (19x) `password`
- failing grader: fallthrough · top label: reset_password · suspected handler: handle_reset_password_intent
  - "Password ??"
  - "Password"
  - "Password"
  - "Password?"
  - "Password"

### 22. (19x) `lmk when loaded`
- failing grader: money-miss(HIGH) · top label: status_check · suspected handler: handle_status_check
  - "Lmk when loaded"
  - "Lmk when loaded"
  - "Lmk When loaded"
  - "Lmk when loaded"
  - "Lmk When loaded"

### 23. (19x) `on all in one`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "On all in one"
  - "On all in one"
  - "On all in one"
  - "On all in one"
  - "On all in one"

### 24. (19x) `juwa loaded`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa loaded..?"
  - "Juwa2.0 Loaded?"
  - "Juwa Loaded"
  - "Juwa Loaded"
  - "Juwa Loaded"

### 25. (18x) `can u let me know when it's loaded plz love`
- failing grader: money-miss(HIGH) · top label: status_check · suspected handler: handle_status_check
  - "Can u let me know when it's loaded plz love"
  - "Can u let me know when it's loaded plz love"
  - "Can u let me know when it's loaded plz love"
  - "Can u let me know when it's loaded plz love"
  - "Can u let me know when it's loaded plz love"

