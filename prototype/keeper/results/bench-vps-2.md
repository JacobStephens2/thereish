### Latency (vps-2, n=20 sequential calls per candidate, item 9, cache off)

| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gemini37 | gemini-3.7-flash (low) | 1234 | 1674 | 1347 | 1845 | 131.3 | 760.2 | 1312.9 | PASS | PASS | 0/20 |
| gemini38 | gemini-3.8-flash (low) | 594 | 804 | 718 | 959 | 39.4 | 310.3 | 787.3 | PASS | PASS | 0/20 |
| deepseek_max | accounts/fireworks/models/deepseek-v4-flash-0731 (max) | 9288 | 27955 | 9508 | 28105 | 979.4 | 3690.9 | 9304.3 | FAIL | FAIL | 0/20 |
| deepseek_low | accounts/fireworks/models/deepseek-v4-flash-0731 (low) | 2849 | 4788 | 3041 | 4992 | 273.4 | 1112.9 | 2902.9 | FAIL | FAIL | 0/20 |
| deepseek_none | accounts/fireworks/models/deepseek-v4-flash-0731 (none) | 378 | 1125 | 1030 | 2515 | 36.8 | 58.8 | 1398.0 | PASS | PASS | 0/20 |

### Hedging (2 identical requests to one model, first wins; n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 | hedged failures |
|---|---|---|---|---|---|---|---|
| gemini37 | 1845 | 1475 | 1347 | 1289 | 1674 | 1424 | 0 |
| gemini38 | 959 | 920 | 718 | 681 | 804 | 841 | 0 |
| deepseek_max | 28105 | 18310 | 9508 | 6289 | 27955 | 18094 | 0 |
| deepseek_low | 4992 | 5257 | 3041 | 3001 | 4788 | 5089 | 0 |
| deepseek_none | 2515 | 1036 | 1030 | 851 | 1125 | 386 | 0 |

### Repeat agreement (same submission ×5, cache off)

| candidate | item | closeness values | identical | range ≤ 5 |
|---|---|---|---|---|
| gemini37 | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| gemini37 | 7 | 85, 78, 85, 82, 85 | false | false (range 7) |
| gemini37 | 9 | 68, 70, 70, 65, 68 | false | true (range 5) |
| gemini37 | 18 | 10, 12, 15, 10, 12 | false | true (range 5) |
| gemini38 | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| gemini38 | 7 | 85, 82, 85, 78, 85 | false | false (range 7) |
| gemini38 | 9 | 72, 72, 68, 72, 76 | false | false (range 8) |
| gemini38 | 18 | 12, 5, 10, 12, 12 | false | false (range 7) |
| deepseek_max | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| deepseek_max | 7 | 70, 80, 65, 78, 70 | false | false (range 15) |
| deepseek_max | 9 | 60, 60, 65, 58, 60 | false | false (range 7) |
| deepseek_max | 18 | 25, 45, 15, 30, 20 | false | false (range 30) |
| deepseek_low | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| deepseek_low | 7 | 65, 65, 60, 70, 75 | false | false (range 15) |
| deepseek_low | 9 | 60, 60, 60, 65, 60 | false | true (range 5) |
| deepseek_low | 18 | 20, 25, 50, 20, 20 | false | false (range 30) |
| deepseek_none | 1 | 100, 100, 100, 100, 100 | true | true (range 0) |
| deepseek_none | 7 | 65, 70, 70, 60, 78 | false | false (range 18) |
| deepseek_none | 9 | 45, 55, 45, 55, 35 | false | false (range 20) |
| deepseek_none | 18 | 15, 35, 15, 35, 15 | false | false (range 20) |

### Ordering agreement ((A,B) vs (B,A) over the 20-item set)

| candidate | mean abs diff | max abs diff | within 5 | graded pairs |
|---|---|---|---|---|
| gemini37 | 2.8 | 13 | 80.0% | 20 |
| gemini38 | 4.3 | 40 | 80.0% | 20 |
| deepseek_max | 3.1 | 10 | 88.2% | 17 |
| deepseek_low | 5.5 | 15 | 68.4% | 19 |
| deepseek_none | 8.3 | 35 | 57.9% | 19 |

Warm-up call (discarded): gemini37 ttft=1684 total=1854; gemini38 ttft=919 total=1063; deepseek_max ttft=4290 total=4479; deepseek_low ttft=4171 total=4324; deepseek_none ttft=685 total=1259

Bench spend: gemini37 $0.05369; gemini38 $0.03328; deepseek_max $0.06657; deepseek_low $0.02273; deepseek_none $0.00920