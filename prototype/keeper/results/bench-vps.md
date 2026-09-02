### Latency (vps, n=20 sequential calls per candidate, item 9, cache off)

| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| glm | zai-org/GLM-5.3-Flash | 314 | 645 | 627 | 961 | 59.5 | 196.0 | 620.2 | PASS | PASS | 0/20 |
| luna | gpt-5.6-luna | 689 | 1359 | 1029 | 1777 | 56.8 | 124.2 | 1172.2 | PASS | PASS | 0/20 |
| opus | claude-opus-5 | 1932 | 2445 | 2817 | 3132 | 72.9 | 88.3 | 2611.2 | FAIL | PASS | 0/20 |
| sonnet | claude-sonnet-5 | 1468 | 1610 | 2077 | 2259 | 56.1 | 95.7 | 2095.3 | PASS | PASS | 0/20 |

### Hedging (2 identical requests to one model, first wins; n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 | hedged failures |
|---|---|---|---|---|---|---|---|
| glm | 961 | 839 | 627 | 516 | 645 | 527 | 0 |
| luna | 1777 | 1260 | 1029 | 998 | 1359 | 928 | 0 |
| opus | 3132 | 2990 | 2817 | 2768 | 2445 | 2076 | 0 |
| sonnet | 2259 | 2242 | 2077 | 2016 | 1610 | 1660 | 0 |

### Repeat agreement (same submission ×5, cache off)

| candidate | item | closeness values | identical | range ≤ 5 |
|---|---|---|---|---|
| glm | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| glm | 7 | 85, 70, 90, 90, 85 | false | false (range 20) |
| glm | 9 | 55, 40, 45, 45, 55 | false | false (range 15) |
| glm | 18 | 5, 10, 15, 15, 20 | false | false (range 15) |
| luna | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| luna | 7 | 70, 80, 78, 72, 82 | false | false (range 12) |
| luna | 9 | 55, 48, 58, 58, 35 | false | false (range 23) |
| luna | 18 | 20, 28, 15, 25, 25 | false | false (range 13) |
| opus | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| opus | 7 | 80, 82, 80, 78, 78 | false | true (range 4) |
| opus | 9 | 55, 55, 52, 55, 52 | false | true (range 3) |
| opus | 18 | 8, 6, 18, 8, 8 | false | false (range 12) |
| sonnet | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| sonnet | 7 | 80, 80, 85, 85, 85 | false | true (range 5) |
| sonnet | 9 | 45, 45, 45, 45, 45 | true | true (range 0) |
| sonnet | 18 | 15, 10, 10, 15, 15 | false | true (range 5) |

### Ordering agreement ((A,B) vs (B,A) over the 20-item set)

| candidate | mean abs diff | max abs diff | within 5 | graded pairs |
|---|---|---|---|---|
| glm | 10.3 | 40 | 45.0% | 20 |
| luna | 5.6 | 20 | 65.0% | 20 |
| opus | 3.5 | 13 | 75.0% | 20 |
| sonnet | 4.7 | 15 | 75.0% | 20 |

Warm-up call (discarded): glm ttft=790 total=1084; luna ttft=756 total=1013; opus ttft=2241 total=3297; sonnet ttft=2973 total=3494

Bench spend: glm $0.00660; luna $0.01268; opus $0.46496; sonnet $0.16643