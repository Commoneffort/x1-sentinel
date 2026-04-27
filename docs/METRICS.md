# Metric reference

Every value the dashboard shows, what it means, and how to read it.

---

## PoH HEALTH

The Proof-of-History heartbeat. PoH is a SHA-256 chain that runs continuously to give the validator a verifiable clock. If PoH stutters, slot timing fails and skips follow.

### Tick rate (per sec)
Number of PoH ticks produced per second.
- **Good (green):** ≥160 ticks/sec. Healthy state, exactly the protocol target.
- **Warning (yellow):** 140–159 ticks/sec. Drifting; CPU contention is starting to show.
- **Critical (red):** <140 ticks/sec. PoH thread can't keep up; you will skip slots imminently.
- **Above 160 is fine and normal** — PoH runs ahead and absorbs slack.

### tick-CV (coefficient of variation %)
How consistent ticks-per-emission are. Calculated as stddev / mean × 100.
- **Good:** <5%. Clock is steady.
- **Warning:** 5–10%. Jittery; usually a sign of thread preemption.
- **Critical:** >10%. PoH thread is being interrupted regularly.

### Lock avg (µs)
Average time spent acquiring the PoH internal lock. High values mean other threads are competing with PoH for the same data.
- **Good:** <2,000 µs.
- **Warning:** 2,000–10,000 µs.
- **Critical:** >10,000 µs. Reduce parallelism or pin PoH to its own core.

### Record avg (µs)
Time spent recording transaction entries into PoH. Only non-zero when you're a leader.
- **Idle (when not leading):** 0 µs. This is normal.
- **Leading:** typically 100–2,000 µs. >5,000 µs means transaction processing is slow.

### Status
Composite assessment derived from rate, CV, and lock latency.

---

## POH SLOT FILL

The single most predictive metric for skips. Measures how long it actually takes to fill a slot — the only thing that matters for the 400ms budget.

### Last (ms)
Most recent slot fill time.
- **Good:** <320 ms (under 80% of budget).
- **Warning:** 320–399 ms.
- **Critical:** ≥400 ms. You missed budget for that slot.

### Avg/60s, Peak/60s
Average and worst slot fill over the last 60 seconds.
- **Healthy validators:** Avg ~350ms, Peak <500ms.
- **Stressed validators:** Avg >380ms, Peak >1,000ms.
- **In trouble:** Peak >2,000ms — almost guaranteed to be skipping.

### Slots >80% budget (%)
What fraction of recent slots ran in the last 20% of budget. Predictive: if you're routinely close to budget, the next CPU hiccup misses one.
- **Good:** <30%.
- **Warning:** 30–60%.
- **Critical:** >60%. Add CPU headroom or reduce IO contention.

---

## SLOT TIMING (replay)

How long it takes you to *replay* (validate) a slot produced by another leader. Different from POH SLOT FILL (which measures slots you fill yourself).

### Last replay (ms)
Time to fully replay the most recent slot.
- **Good:** <300 ms.
- **Warning:** 300–500 ms.
- **Critical:** >1,000 ms. Either upstream produced a heavy slot, OR your CPU/IO is starved.

### Peak/60s
Worst replay duration in the last minute.
- A spike here that doesn't correlate with snapshots = upstream pressure (heavy block).
- A spike that correlates with `SNAPSHOT STATE active` = your AccountsDB stalling.

---

## BLOCK PRODUCTION (your validator)

The actual outcome metric: how often your validator produced its scheduled block vs. dropped it.

### Lifetime drop %
Drop rate since validator start.
- **Excellent:** <0.5%.
- **Good:** 0.5–1%.
- **Concerning:** 1–3%. Network or hardware issues likely.
- **Bad:** >3%. Investigate immediately.

### Recent drop %
Drop rate since the sentinel started observing.
- **Compare to lifetime:** if recent < lifetime, you're improving. If recent > lifetime, you're getting worse.
- **0.00% recent over 100+ blocks** = healthy validator.

---

## BANKING STAGE

The transaction processing pipeline. Behavior differs dramatically based on whether you're currently producing a block.

### (idle) vs (leading) tag
- **(idle):** You're not the current leader. Most metrics will be near zero. Drops are normal load-shedding.
- **(leading):** You're producing a block. *Now* drops and queue depth matter.

### Pkts/s in
Packets per second received from QUIC.
- Idle: typically 50–200/s background traffic.
- Leading: can spike to thousands.

### drop (count and %)
Packet drops. Only meaningful when leading.
- **Leading & good:** <1%.
- **Leading & warning:** 1–5%.
- **Leading & critical:** >5%. Banking can't keep up — CPU or scheduler bottleneck.

### consumed
Rate of packets consumed (processed). 0 when idle (correct), should match `Pkts/s in` minus drops when leading.

### Buffered avg
Average queue depth. High values mean backpressure.
- **Good:** <500.
- **Warning:** 500–2,000.
- **Critical:** >2,000. Banking is falling behind.

---

## TPU / QUIC

Network ingress to the validator. The first stage of the pipeline.

### Active conns
Currently open QUIC connections.
- Healthy: 50–500 depending on stake and traffic.
- Sudden drops to near zero: network problem (firewall, ISP).

### Total attempts
Cumulative connection attempts since validator start. Should grow steadily.

### Throttled/s
Rate of connections being rate-limited.
- **Good:** 0.
- **Warning:** 1–10/s.
- **Critical:** >10/s. You're shedding load at the door — increase QUIC limits or scale up.

### Setup-timeouts/s
Connections that timed out during handshake.
- **Good:** 0.
- **Warning:** Any sustained non-zero rate. Check network latency and firewall rules.

---

## BLOCK LOAD (latest slot)

What the most recent slot contained. Useful for spotting when network load is heavy.

### CU (compute units)
How many CUs were consumed in the slot, and what fraction of the 48M cap.
- **Light:** <5M (10%). Normal.
- **Moderate:** 5M–30M.
- **Heavy:** 30M–43M (90%).
- **Saturated:** >43M (90%+). Block was at capacity; transactions were being dropped.

### Tx, Accts
Transaction count and number of unique accounts touched. Higher = busier slot.

### VoteCU
Compute units consumed by vote transactions specifically. Should be a substantial fraction of total CU on a healthy network — votes are mandatory.

---

## ACCOUNTSDB

The on-disk account state store. Most critical IO subsystem.

### Store avg (µs)
Average time to write account changes.
- **Good:** <100 µs.
- **Warning:** 100–1,000 µs.
- **Critical:** >1,000 µs. Disk contention.
- **>50,000 µs:** Almost certainly a snapshot in progress.

### Flush avg (µs)
Time to flush dirty pages. Spikes correlate with snapshots and disk pressure.

### Snapshot peak/5m (ms)
Worst snapshot duration in the last 5 minutes.
- **Good:** <2,000 ms.
- **Warning:** 2,000–10,000 ms.
- **Critical:** >10,000 ms. Snapshots are stalling the validator. Move snapshots to tmpfs or a separate disk.

---

## SNAPSHOT STATE

Aggregate detector for "is a snapshot happening right now?" Three independent signals.

### State
- **idle:** Nothing snapshot-related is happening. Disk and CPU patterns are baseline.
- **building:** One signal active. Could be coincidence; watch.
- **in-progress:** Two of three signals active. Snapshot is starting or finishing.
- **active:** All three signals firing. Snapshot is in mid-flight; expect a transient slot-fill spike.

When state is `in-progress` or `active`, the risk score automatically dampens timing-related contributors so you don't get a false CRIT alarm during normal snapshot windows.

### Signals
Three independent indicators (`●` = firing, `·` = idle):
1. **disk** — NVMe write rate >200 MB/s
2. **adb** — `accounts_db_active` datapoint emission >5/sec
3. **snap** — snapshot-related datapoint within last 30s

### Last event / Last snapshot duration
When the last snapshot-related datapoint was seen, and how long the last completed snapshot took.

---

## SHREDS / TURBINE

Block propagation health. Shreds are the small chunks that blocks are split into for network distribution.

### Repairs peak/60s
Highest count of shreds you needed to request from peers (because Turbine didn't deliver them).
- **Good:** <50.
- **Warning:** 50–200.
- **Critical:** >200. Network partition or turbine tree problem.

### Recovered peak
Erasure-coded recoveries. Some recovery is normal and even healthy; very high values (>2,000) indicate poor primary delivery.

### Turbine 1st/2nd avg
Shreds received via the fast path (1st layer = direct from leader, 2nd = retransmit).
- A healthy validator gets most shreds through 1st/2nd layer. Heavy reliance on repairs = stake/peering issue.

---

## SYSTEM

Host-level metrics. Often the root cause of validator-level symptoms.

### Load (load1, load5, ncpu)
1- and 5-minute load averages, and your core count.
- **Good:** load1 < 50% × ncpu (e.g. <16 on a 32-core box).
- **Warning:** 50–75% × ncpu.
- **Critical:** >75% × ncpu. CPU-bound; expect skips.

### CPU hot
Top 4 busiest cores. PoH will pin one core at 100% (normal); the others should be <70%.
- One core at 100% = PoH, expected.
- Multiple cores at >80% = banking + replay competing, watch carefully.
- All cores >70% = saturated.

### RAM (mem%, pgmajfault)
Memory used and major page fault count.
- **mem%:** Usually 40–70% on a healthy validator. >90% = swapping risk.
- **pgmajfault:** Should grow slowly. Sudden jumps mean disk reads to satisfy memory pressure.

### Net (rx_drops)
Cumulative receive drops on all interfaces since boot. Watch for the *rate of change*, not absolute value.

### Disk (rkB/s, wkB/s, await, qd, util)
NVMe IO statistics from `iostat`.
- **wkB/s:** Sustained writes. >200 MB/s usually means snapshots.
- **w_await (ms):** Average write completion time. <5 ms = excellent. >50 ms = stressed.
- **qd:** Queue depth. <10 normal. >100 means a write burst is being absorbed.
- **util%:** Disk busy time. <30% relaxed. >80% saturated.

---

## PRECOGNITIVE RISK

The composite score. Reads everything above and produces one number.

### Score
Sum of weighted contributions from each subsystem, capped at 30 per contributor (so no single bad metric pegs the score).

### Levels
- **LOW (0–25):** Healthy. Just watch.
- **MED (26–55):** One subsystem degrading. Investigate the listed driver.
- **HIGH (56–90):** Multiple stress signals. Likely already missing slots. Telegram/Discord fires here.
- **CRIT (91+):** Active failure or imminent skip burst.

### Drivers
The list of which subsystems are contributing to the score, with their actual values. Read this first when the score is elevated — it tells you exactly what to investigate.

### Recent transitions
Last 3 level changes with timestamp. Useful for correlation with system events.

---

## DATA FLOW

Diagnostic panel showing the parser is alive.

### events / unique_metrics
Total datapoint events seen and how many unique names. A healthy X1/Tachyon validator emits ~95–110 unique metric names continuously.

### top
The 6 most frequently emitted metrics. Should always include `slot_stats_tracking_complete`, `replay-slot-stats`, and `bank-*` variants.

If this panel says `events=0`, the parser isn't reading the journal — check that the configured SERVICE name is correct.
