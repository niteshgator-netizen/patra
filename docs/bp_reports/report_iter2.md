# PATRA REPLAY REPORT

Generated: 2026-06-11T23:06:31Z · account=2 · rows graded: 73070

## TIER 1 — deterministic routing (real IntentDetector, zero LLM)

HEADLINE: 73070 rows · resolved 35053 (48.0%) · fallthrough 38017 · **money-label misses (HIGH): 25500** · label-mismatch (informational, labels noisy): 8089 · detect errors: 0

| real_intent | rows | resolved | matched | mismatch | fallthrough | money-miss |
|---|---|---|---|---|---|---|
| load_deposit | 20907 | 12159 | 11567 | 592 | 8748 | 8748 |
| payment_handle_request | 9414 | 3791 | 2636 | 1155 | 5623 | 5623 |
| load_freeplay | 8935 | 7014 | 6486 | 528 | 1921 | 1921 |
| greeting_chitchat | 5513 | 670 | 0 | 0 | 4843 | 0 |
| cashout_redeem | 4621 | 2455 | 1603 | 852 | 2166 | 2166 |
| status_check | 4542 | 1404 | 334 | 1070 | 3138 | 3138 |
| payment_sent_confirmation | 3618 | 1692 | 1462 | 230 | 1926 | 1926 |
| complaint_angry | 3575 | 1194 | 241 | 953 | 2381 | 0 |
| tech_issue | 2759 | 505 | 35 | 470 | 2254 | 0 |
| new_account_other_game | 1742 | 755 | 278 | 477 | 987 | 0 |
| redeem_partial_replay | 1536 | 1131 | 504 | 627 | 405 | 405 |
| referral | 1212 | 446 | 63 | 383 | 766 | 766 |
| reset_password | 869 | 239 | 171 | 68 | 630 | 0 |
| whats_hitting | 860 | 431 | 266 | 165 | 429 | 0 |
| new_account_reissue | 797 | 226 | 107 | 119 | 571 | 0 |
| load_bonus | 601 | 406 | 360 | 46 | 195 | 195 |
| transfer_between_games | 404 | 161 | 19 | 142 | 243 | 243 |
| balance_check | 387 | 134 | 69 | 65 | 253 | 253 |
| unclear | 347 | 38 | 0 | 0 | 309 | 0 |
| replay_from_balance | 220 | 104 | 2 | 102 | 116 | 116 |
| new_account_new_player | 201 | 91 | 46 | 45 | 110 | 0 |
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

### 5. (69x) `please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Please"
  - "Please"
  - "35 please"
  - "Please"
  - "Please"

### 6. (52x) `yes please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Yes please"
  - "Yes please"
  - "Yes please"
  - "Yes please"
  - "Yes Please"

### 7. (49x) `https cash app`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "https://cash.app/$Bandigang75"
  - "https://cash.app/$nickbean0629"
  - "https://cash.app/$BobbyBoggs4"
  - "https://cash.app/$BobbyBoggs4"
  - "$brokeagaincM https://cash.app/$brokeagainCM"

### 8. (48x) `juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa +30%"
  - "15/2.0 5 juwa"
  - "15 juwa 5 2.0"
  - "Juwa 5"
  - "10 juwa"

### 9. (39x) `loaded juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Loaded juwa"
  - "Loaded Juwa"
  - "Loaded Juwa"
  - "Loaded Juwa"
  - "Loaded juwa"

### 10. (35x) `same game`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Same game"
  - "Same game"
  - "Same game"
  - "Same game"
  - "Same game"

### 11. (35x) `orion star`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Orion star"
  - "5.00 Orion star 🌟"
  - "Orion star"
  - "Orion star"
  - "Orion star"

### 12. (33x) `is my game loaded`
- failing grader: money-miss(HIGH) · top label: status_check · suspected handler: handle_status_check
  - "Is my game loaded"
  - "Is my game loaded"
  - "Is my game loaded"
  - "Is my game loaded"
  - "Is my game loaded"

### 13. (33x) `i won`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "I won 59"
  - "I won"
  - "I won 100.00"
  - "I won 98.00"
  - "I won 100.00"

### 14. (33x) `yolo`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "20 yolo"
  - "20 yolo"
  - "15 yolo"
  - "20 yolo"
  - "20 yolo"

### 15. (33x) `can i add`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Can I add"
  - "Can I add"
  - "Can I add"
  - "Can I add"
  - "Can I add"

### 16. (32x) `chime tag juwa`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Chime tag Juwa"
  - "Chime tag Juwa"
  - "Chime tag Juwa"
  - "Chime tag Juwa"
  - "Chime tag Juwa"

### 17. (31x) `for juwa account lindsay jw`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "For juwa account Lindsay0987jw"
  - "For juwa account Lindsay0987jw"
  - "For juwa account Lindsay0987jw"
  - "For juwa account Lindsay0987jw"
  - "For juwa account Lindsay0987jw"

### 18. (28x) `on os`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "25 on os"
  - "20 on  os"
  - "30 on os"
  - "25 on os"
  - "5 on os"

### 19. (28x) `ready`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ready"
  - "Ready"
  - "Ready"
  - "Ready..?"
  - "Ready..?"

### 20. (28x) `cashing out do i request it`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "Cashing out 50$ Do I request it"
  - "Cashing out 50$ do I request it?"
  - "Cashing out 50$ Do I request it"
  - "Cashing out 60$ do I request  it"
  - "10 cashing out Do I request it"

### 21. (27x) `ok thanks`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Ok thanks"
  - "Ok thanks 🙏🏼🙏🏼💯"
  - "Ok thanks 🙏🏻🙏🏻💯"
  - "Ok thanks 🙏🏻🙏🏻💯"
  - "Ok thanks 🙏🏼🙏🏼💯"

### 22. (27x) `juwa juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa Juwa"
  - "Juwa Juwa"
  - "Juwa Juwa"
  - "Juwa Juwa"
  - "Juwa Juwa"

### 23. (27x) `request`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Request 60"
  - "Request 4"
  - "Request 4"
  - "Request $5"
  - "Request 5"

### 24. (27x) `tonya fk please and thank you dear`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Tonya729fk Please and thank you dear"
  - "Tonya729fk Please and thank you dear"
  - "Tonya729fk Please and thank you dear"
  - "Tonya729fk Please and thank you dear"
  - "Tonya729fk Please and thank you dear"

### 25. (27x) `chime tag for deposit milkyway`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Chime tag for deposit Milkyway"
  - "Chime tag for deposit Milkyway"
  - "Chime tag for deposit Milkyway"
  - "Chime tag for deposit Milkyway"
  - "Chime tag for deposit Milkyway"

