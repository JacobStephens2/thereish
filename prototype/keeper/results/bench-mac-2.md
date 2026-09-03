### Latency (mac-2, n=20 sequential calls per candidate, item 9, cache off)

| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gemini37 | gemini-3.7-flash (low) | 1264 | 2203 | 1408 | 2277 | 104.3 | 921.9 | 1329.1 | PASS | PASS | 0/20 |
| gemini38 | gemini-3.8-flash (low) | 656 | 3051 | 760 | 3198 | 39.9 | 324.1 | 841.1 | PASS | PASS | 0/20 |
| deepseek_max | accounts/fireworks/models/deepseek-v4-flash-0731 (max) | 7151 | 15241 | 7514 | 15413 | 685.9 | 3222.2 | 7169.6 | FAIL | FAIL | 1/20 |
| deepseek_low | accounts/fireworks/models/deepseek-v4-flash-0731 (low) | 2747 | 5647 | 3163 | 5828 | 289.7 | 1009.7 | 2806.4 | FAIL | FAIL | 0/20 |
| deepseek_none | accounts/fireworks/models/deepseek-v4-flash-0731 (none) | 315 | 1533 | 972 | 2200 | 36.6 | 57.8 | 1352.6 | PASS | PASS | 0/20 |

### Hedging (2 identical requests to one model, first wins; n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 | hedged failures |
|---|---|---|---|---|---|---|---|
| gemini37 | 2277 | 1511 | 1408 | 1307 | 2203 | 1413 | 0 |
| gemini38 | 3198 | 864 | 760 | 738 | 3051 | 769 | 0 |
| deepseek_max | 15413 | 19100 | 7514 | 6226 | 15241 | 18919 | 0 |
| deepseek_low | 5828 | 4165 | 3163 | 3109 | 5647 | 3885 | 0 |
| deepseek_none | 2200 | 1515 | 972 | 1022 | 1533 | 1428 | 0 |

### Repeat agreement (same submission ×5, cache off)

| candidate | item | closeness values | identical | range ≤ 5 |
|---|---|---|---|---|
| gemini37 | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| gemini37 | 7 | 85, 85, 82, 78, 82 | false | false (range 7) |
| gemini37 | 9 | 68, 68, 72, 72, 65 | false | false (range 7) |
| gemini37 | 18 | 10, 8, 12, 12, 10 | false | true (range 4) |
| gemini38 | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| gemini38 | 7 | 85, 85, 78, 85, 84 | false | false (range 7) |
| gemini38 | 9 | 72, 72, 72, 72, 72 | true | true (range 0) |
| gemini38 | 18 | 12, 12, 12, 12, 15 | false | true (range 3) |
| deepseek_max | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| deepseek_max | 7 | 70, 70, 65, 70, 85 | false | false (range 20) |
| deepseek_max | 9 | 60, 60, 60, 65, 55 | false | false (range 10) |
| deepseek_max | 18 | 25, 30, 55, 30 | false | false (range 30) |
| deepseek_low | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| deepseek_low | 7 | 65, 65, 65, 70, 65 | false | true (range 5) |
| deepseek_low | 9 | 60, 80, 65, 60, 60 | false | false (range 20) |
| deepseek_low | 18 | 10, 20, 25, 20, 20 | false | false (range 15) |
| deepseek_none | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| deepseek_none | 7 | 80, 70, 65, 80, 65 | false | false (range 15) |
| deepseek_none | 9 | 45, 55, 55, 35, 45 | false | false (range 20) |
| deepseek_none | 18 | 25, 35, 35, 15, 15 | false | false (range 20) |

### Ordering agreement ((A,B) vs (B,A) over the 20-item set)

| candidate | mean abs diff | max abs diff | within 5 | graded pairs |
|---|---|---|---|---|
| gemini37 | 4.0 | 15 | 75.0% | 20 |
| gemini38 | 4.3 | 27 | 75.0% | 20 |
| deepseek_max | 5.7 | 20 | 65.0% | 20 |
| deepseek_low | 9.2 | 35 | 68.4% | 19 |
| deepseek_none | 7.4 | 25 | 57.9% | 19 |

Warm-up call (discarded): gemini37 ttft=1576 total=1633; gemini38 ttft=2047 total=2115; deepseek_max ttft=9566 total=9774; deepseek_low ttft=8845 total=9037; deepseek_none ttft=1227 total=1913

Bench spend: gemini37 $0.05224; gemini38 $0.03309; deepseek_max $0.06946; deepseek_low $0.02327; deepseek_none $0.00917