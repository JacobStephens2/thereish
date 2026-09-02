### Latency (mac, n=20 sequential calls per candidate, item 9, cache off)

| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| glm | zai-org/GLM-5.3-Flash | 352 | 950 | 613 | 1520 | 56.6 | 175.1 | 694.7 | PASS | PASS | 0/20 |
| luna | gpt-5.6-luna | 1129 | 2085 | 1524 | 2448 | 59.1 | 108.6 | 1681.3 | PASS | PASS | 0/20 |
| opus | claude-opus-5 | 1892 | 2183 | 2691 | 3167 | 75.0 | 94.7 | 2525.3 | FAIL | PASS | 0/20 |
| sonnet | claude-sonnet-5 | 1505 | 2285 | 2064 | 2855 | 55.8 | 98.3 | 2115.6 | PASS | PASS | 0/20 |

### Hedging (2 identical requests to one model, first wins; n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 | hedged failures |
|---|---|---|---|---|---|---|---|
| glm | 1520 | 1172 | 613 | 637 | 950 | 577 | 0 |
| luna | 2448 | 1673 | 1524 | 1224 | 2085 | 1326 | 0 |
| opus | 3167 | 2982 | 2691 | 2689 | 2183 | 2195 | 0 |
| sonnet | 2855 | 2353 | 2064 | 2120 | 2285 | 1718 | 0 |

### Repeat agreement (same submission ×5, cache off)

| candidate | item | closeness values | identical | range ≤ 5 |
|---|---|---|---|---|
| glm | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| glm | 7 | 88, 60, 90, 90, 78 | false | false (range 30) |
| glm | 9 | 45, 55, 45, 45, 55 | false | false (range 10) |
| glm | 18 | 20, 45, 45, 30, 10 | false | false (range 35) |
| luna | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| luna | 7 | 78, 82, 82, 78, 82 | false | true (range 4) |
| luna | 9 | 45, 45, 55, 55, 45 | false | false (range 10) |
| luna | 18 | 20, 35, 10, 20, 28 | false | false (range 25) |
| opus | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| opus | 7 | 76, 82, 82, 80, 80 | false | false (range 6) |
| opus | 9 | 55, 60, 55, 55, 58 | false | true (range 5) |
| opus | 18 | 5, 8, 8, 8, 8 | false | true (range 3) |
| sonnet | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| sonnet | 7 | 80, 80, 60, 85, 85 | false | false (range 25) |
| sonnet | 9 | 45, 40, 45, 45, 45 | false | true (range 5) |
| sonnet | 18 | 15, 10, 15, 15, 10 | false | true (range 5) |

### Ordering agreement ((A,B) vs (B,A) over the 20-item set)

| candidate | mean abs diff | max abs diff | within 5 | graded pairs |
|---|---|---|---|---|
| glm | 8.8 | 25 | 40.0% | 20 |
| luna | 5.5 | 25 | 70.0% | 20 |
| opus | 2.5 | 9 | 90.0% | 20 |
| sonnet | 7.0 | 30 | 65.0% | 20 |

Warm-up call (discarded): glm ttft=509 total=747; luna ttft=2220 total=2666; opus ttft=1954 total=2676; sonnet ttft=2164 total=2664

Bench spend: glm $0.00642; luna $0.01221; opus $0.46198; sonnet $0.16620