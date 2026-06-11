# PATRA REPLAY REPORT

Generated: 2026-06-11T22:37:25Z · account=2 · rows graded: 73070

## TIER 1 — deterministic routing (real IntentDetector, zero LLM)

HEADLINE: 73070 rows · resolved 26507 (36.3%) · fallthrough 46563 · **money-label misses (HIGH): 33505** · label-mismatch (informational, labels noisy): 5992 · detect errors: 0

| real_intent | rows | resolved | matched | mismatch | fallthrough | money-miss |
|---|---|---|---|---|---|---|
| load_deposit | 20907 | 8022 | 7577 | 445 | 12885 | 12885 |
| payment_handle_request | 9414 | 2533 | 1901 | 632 | 6881 | 6881 |
| load_freeplay | 8935 | 6107 | 5825 | 282 | 2828 | 2828 |
| greeting_chitchat | 5513 | 559 | 0 | 0 | 4954 | 0 |
| cashout_redeem | 4621 | 1796 | 1317 | 479 | 2825 | 2825 |
| status_check | 4542 | 1174 | 273 | 901 | 3368 | 3368 |
| payment_sent_confirmation | 3618 | 1039 | 905 | 134 | 2579 | 2579 |
| complaint_angry | 3575 | 1176 | 241 | 935 | 2399 | 0 |
| tech_issue | 2759 | 461 | 35 | 426 | 2298 | 0 |
| new_account_other_game | 1742 | 482 | 278 | 204 | 1260 | 0 |
| redeem_partial_replay | 1536 | 1093 | 501 | 592 | 443 | 443 |
| referral | 1212 | 427 | 63 | 364 | 785 | 785 |
| reset_password | 869 | 227 | 171 | 56 | 642 | 0 |
| whats_hitting | 860 | 418 | 274 | 144 | 442 | 0 |
| new_account_reissue | 797 | 181 | 107 | 74 | 616 | 0 |
| load_bonus | 601 | 348 | 318 | 30 | 253 | 253 |
| transfer_between_games | 404 | 134 | 19 | 115 | 270 | 270 |
| balance_check | 387 | 124 | 69 | 55 | 263 | 263 |
| unclear | 347 | 27 | 0 | 0 | 320 | 0 |
| replay_from_balance | 220 | 95 | 2 | 93 | 125 | 125 |
| new_account_new_player | 201 | 77 | 46 | 31 | 124 | 0 |
| cashout_rules | 2 | 2 | 2 | 0 | 0 | 0 |
| request_download_link | 2 | 2 | 2 | 0 | 0 | 0 |
| request_game_link | 2 | 0 | 0 | 0 | 2 | 0 |
| list_platforms | 2 | 2 | 2 | 0 | 0 | 0 |
| payment_method_question | 1 | 0 | 0 | 0 | 1 | 0 |
| request_app_link | 1 | 1 | 1 | 0 | 0 | 0 |

(fallthrough on greeting_chitchat/unclear is the designed outcome — excluded from clusters)

## TOP 25 FALLTHROUGH CLUSTERS

### 1. (332x) `juwa`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa 2.0"
  - "Juwa2"
  - "Juwa 2"
  - "Juwa2"
  - "Juwa2"

### 2. (304x) `juwa please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Juwa please"
  - "Juwa please"
  - "Juwa please"
  - "Juwa please"
  - "Juwa Please"

### 3. (266x) ``
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "$MegsnAvakian5"
  - "$CasiqueJorge69 10$"
  - "$phillipevans28"
  - "51.03"
  - "@Afaseler1981"

### 4. (207x) `request sent`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "Request sent"
  - "Request sent"
  - "Request sent"
  - "Request sent"
  - "Request sent"

### 5. (205x) `orion`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Orion"
  - "Orion"
  - "Orion"
  - "Orion"
  - "Orion"

### 6. (172x) `vblink`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Vblink"
  - "Vblink"
  - "Vblink"
  - "Vblink"
  - "Vblink"

### 7. (148x) `requested`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "Requested"
  - "Requested"
  - "Requested"
  - "Requested"
  - "Requested"

### 8. (146x) `game vault`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Game vault"
  - "Game vault"
  - "Game Vault"
  - "Game vault"
  - "Game vault"

### 9. (140x) `gv please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Gv please"
  - "Gv please"
  - "Gv please"
  - "Gv please"
  - "Gv please"

### 10. (128x) `fire kirin`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Fire kirin"
  - "Fire kirin"
  - "10 2.0 , 10 fire Kirin"
  - "Fire kirin"
  - "10 fire kirin"

### 11. (126x) `alexis jw`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Alexis726_jw"
  - "Alexis726_jw"
  - "Alexis726_jw"
  - "Alexis726_jw"
  - "Alexis726_jw"

### 12. (113x) `loaded`
- failing grader: money-miss(HIGH) · top label: status_check · suspected handler: handle_status_check
  - "Loaded?"
  - "Loaded?"
  - "Loaded?"
  - "loaded??"
  - "loaded"

### 13. (111x) `milkyway`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Milkyway"
  - "Milkyway"
  - "Milkyway"
  - "Milkyway"
  - "Milkyway"

### 14. (97x) `orion plz`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Orion plz"
  - "Orion plz"
  - "Orion plz"
  - "Orion plz"
  - "Orion plz"

### 15. (95x) `orion please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Orion please"
  - "Orion please"
  - "Orion please"
  - "Orion please"
  - "Orion please"

### 16. (95x) `cashtag`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Cashtag?"
  - "Cashtag?"
  - "Cashtag"
  - "Cashtag"
  - "Cashtag"

### 17. (94x) `thanks`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Thanks"
  - "Thanks"
  - "Thanks"
  - "Thanks"
  - "Thanks"

### 18. (92x) `i did`
- failing grader: money-miss(HIGH) · top label: payment_sent_confirmation · suspected handler: handle_payment_sent_confirmation
  - "I did"
  - "I did"
  - "I did"
  - "I did"
  - "I did"

### 19. (83x) `game vault please`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Game vault please"
  - "Game vault please"
  - "Game vault please"
  - "Game vault Please"
  - "Game vault please"

### 20. (80x) `sent`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Sent 10"
  - "Sent 5"
  - "Sent 15"
  - "Sent 15"
  - "Sent 6"

### 21. (77x) `milky way`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Milky way"
  - "Milky way"
  - "Milky Way"
  - "Milky Way"
  - "Milky Way"

### 22. (76x) `cash out`
- failing grader: money-miss(HIGH) · top label: cashout_redeem · suspected handler: handle_cashout_intent
  - "Cash out"
  - "Cash out?"
  - "Cash out"
  - "Cash out"
  - "Cash out"

### 23. (76x) `same tag`
- failing grader: money-miss(HIGH) · top label: payment_handle_request · suspected handler: handle_payment_method_chosen
  - "Same tag?"
  - "40%? Same tag?"
  - "40%? Same tag?"
  - "Same tag"
  - "Same tag"

### 24. (76x) `thank you`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Thank you"
  - "Thank you"
  - "Thank you"
  - "Thank you"
  - "Thank you"

### 25. (74x) `game room`
- failing grader: money-miss(HIGH) · top label: load_deposit · suspected handler: handle_load_intent
  - "Game room?"
  - "Game room"
  - "Game room"
  - "Game room"
  - "Game room"

