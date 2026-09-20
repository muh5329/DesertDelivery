# Observed runtime benchmark

Measured the final full-render game on 2026-09-19, Apple M4 Pro, 24 GiB unified memory, macOS 26.6.2, Godot 4.7 stable, GL Compatibility, 1600 × 900. VSync disabled. Each fixed-camera scene warmed for 120 frames, then measured 300 consecutive wall-clock frame intervals. Simulation and normal streaming stayed active; the courier was parked with bike physics disabled. These are short scene samples, not a long driving or streaming stress test.

| Scene | Average FPS | Median frame | p95 frame | p99 frame | Worst frame | Mean draw calls |
|---|---:|---:|---:|---:|---:|---:|
| Village | 47.3 | 20.91 ms | 22.44 ms | 24.14 ms | 75.78 ms | 4,482 |
| Wilderness | 212.6 | 4.36 ms | 6.05 ms | 6.47 ms | 7.05 ms | 390 |

World generation took 4.377 s; benchmark setup was reached 5.560 s after process initialization. Assets were already imported, so this is not a clean first-install startup measurement.

Engine-reported static memory: village 279.4 MiB, wilderness 243.2 MiB. Engine-reported video memory: 278.4 and 275.0 MiB. These counters are not total operating-system resident memory. Scene node counts were 11,279 and 2,381 respectively.

No other task-owned tests or screenshot runs overlapped this benchmark. An existing unrelated Godot editor and the user's running Loot and Plunder project remained open; their CPU/GPU load is an uncontrolled confound. This is an observation of the current workstation, not a clean target-hardware performance certification or pre/post comparison.

The village does not sustain 60 FPS in this sample. Its roughly 4,482 draw calls versus 390 in the outer scene identify batching/visibility work as a concrete next optimization target, but do not alone prove the bottleneck. The long village frame also warrants a longer traversal profile. No AAA performance signoff is given.

Raw data: benchmark.json. Reproduce with `Godot --path . -- --test=overhaul_benchmark --out=<absolute output folder>`.

## Rejected optimization experiments

Two bounded follow-up samples used the same camera, resolution, warmup and 300-frame measurement, with no other task-owned test processes. Background user editor/game confound remained.

| Village experiment | Average FPS | Median frame | p95 frame | Draw calls | Decision |
|---|---:|---:|---:|---:|---|
| Baseline, authored 320 m shadows | 47.32 | 20.912 ms | 22.442 ms | 4,482 | Final source retained |
| Small-static-detail culling plus shadow proxies | 47.34 | 21.206 ms | 22.841 ms | 4,373 | Reverted |
| Runtime-only 160 m directional shadows | 48.49 | 20.730 ms | 22.327 ms | 3,814 | Not applied to source |

Independent critique rejected the proxy change: only 2.45% fewer draw calls, essentially unchanged FPS, slightly worse median/p95 times, and 301 extra scene nodes. Code review found no blocking correctness issue, but the complexity was unsupported by measured benefit. The author reverted the entire chunk change.

Halving the directional shadow distance reduced draw calls by 14.9%, yet median and p95 frame times improved by less than 1%. The higher average FPS is not strong evidence of material improvement in this short noisy sample, and does not reach 60 FPS. Recommended retaining the authored 320 m shadow range rather than making an unproven visual tradeoff. These experiments do not prove draw submission is the dominant bottleneck.

Candidate raw results remain separately under benchmark-shadow-proxy/ and benchmark-shadow-160/. They are experiments, not final-build performance claims. Final source continues to correspond to the original benchmark.json settings.

## Independent bottleneck attribution

One additional rendered process tested diagnostic-only toggles in sequence at the same village camera, 90 warmup frames and 180 measured frames per case. No production behavior was changed. Eight resident actors were present.

| Case | Average FPS | Median frame | Mean physics CPU | Draw calls |
|---|---:|---:|---:|---:|
| Baseline | 47.10 | 21.261 ms | 1.605 ms | 4,643 |
| Freeze IslandLife updates, keep visuals | 51.17 | 19.598 ms | 0.398 ms | 4,628 |
| Freeze IslandLife and hide resident actors | 54.91 | 18.299 ms | 0.422 ms | 3,391 |
| Restore baseline | 46.76 | 21.521 ms | 1.536 ms | 4,188 |
| Render at 75% internal linear resolution | 51.74 | 19.379 ms | 1.665 ms | 4,188 |
| Restore full resolution | 46.57 | 21.580 ms | 1.659 ms | 4,188 |

Freezing IslandLife removes roughly 1.2 ms of physics CPU work, while hiding the frozen residents improves median frame time by another 1.3 ms. Reducing pixel count by about 44% saves roughly 2.2 ms versus the neighboring full-resolution controls. None of these isolated shortcuts reaches 60 FPS; none is an acceptable production optimization by itself because each changes simulation or visuals. Resident movement changes draw counts during earlier cases, so these are diagnostic indications rather than perfectly identical scene A/B comparisons. The later resolution trio has matching draw counts and bracketing baselines. Raw data: attribution.json.

## Matched runtime candidate review after character revision

The next candidate cached resident car pivots/invariant poses and stationary support, and skipped rock noise calculations only when their authored output weight was exactly zero. Independent review found no immediate state/visual correctness blocker. Added a two-physics-frame bypass after chunk events to avoid caching queries before new static shapes synchronize. The station cache invalidates on position, heading, driving/view tier, movement, task reassignment, loading and time skips.

A paired run replaced only IslandLife, ResidentActor and the rock shader with exact pre-candidate copies, measured, then restored/measured the candidate. Character GLB and all other sources stayed identical during both runs. Initial resident clock/stations were reset after scene warmup; normal simulation continued during measurement. The new character asset and improved snapshot method mean these figures must be compared within this pair, not directly against the earlier 47 FPS run.

| Scene | Baseline FPS | Candidate FPS | Baseline median | Candidate median | Baseline p95 | Candidate p95 |
|---|---:|---:|---:|---:|---:|---:|
| Village | 52.27 | 51.77 | 19.131 ms | 19.234 ms | 21.665 ms | 21.975 ms |
| Wilderness | 215.59 | 213.93 | 4.317 ms | 4.361 ms | 6.131 ms | 6.158 ms |
| Dense meadow (4200, 3400) | 179.13 | 184.43 | 5.199 ms | 5.138 ms | 6.876 ms | 6.842 ms |

Village draw calls matched closely (4618.53 vs 4618.41), with eight residents. Dense meadow contained 55,510 dressing instances across 25 tiles in both builds. The candidate produced no measured village improvement and only a ~1.2% meadow median difference, insufficient evidence for a performance claim. Independent critic recommends rejecting the additional cache/shader complexity absent a targeted, repeatable win. Raw data: runtime-baseline/benchmark.json and runtime-candidate/benchmark.json. The swap script restored candidate files after measurement. The author subsequently reverted stationary support caching, invariant pose changes and rock-noise gates. Only cached wheel/steering node references remain as a simple lookup cleanup, with no measured performance claim.


## Character asset-only comparison before final fit adjustment

Held the final runtime source fixed (speculative station cache/pose/shader changes removed), imported the preserved old character GLB and measured the village, then imported the final revised character GLB and repeated. Same camera, eight visible resident actors, 1600 × 900 GL Compatibility, 320 m shadows, 120 warmup/300 measured frames and resident-state reset. No task-owned workloads overlapped. Existing unrelated user Godot processes remained open.

| Metric | Preserved old GLB | Revised GLB at this pair |
|---|---:|---:|
| Average FPS | 48.10 | 52.17 |
| Median frame time | 20.701 ms | 19.193 ms |
| p95 frame time | 22.458 ms | 21.960 ms |
| p99 frame time | 23.773 ms | 22.719 ms |
| Mean draw calls | 4,641.98 | 4,618.54 |
| GLB bytes | 1,692,648 | 1,150,504 |
| Imported mesh nodes | 13 | 13 |
| Material surfaces | 43 | 42 |
| Imported vertices | 33,088 | 26,654 |
| Imported triangles | 60,950 | 49,429 |

Observed average FPS improved 8.45% and median frame time fell 7.28% in this single pair. The final asset uses 32.0% fewer file bytes, 19.4% fewer imported vertices and 18.9% fewer triangles. This is a measured benefit from the revised asset in this scene, not evidence that rejected runtime experiments helped. It still falls below 60 FPS and requires longer repeated traversal profiling before a sustained-performance claim.

The measured new GLB was restored and reimported after the pair. The author subsequently added a small waist overlap and motorcycle-specific footpeg pose, so 52.17 FPS describes the measured intermediate revision, not the later final fit adjustment. A final single-shot measurement is pending. Raw results: asset-old/benchmark.json and asset-new/benchmark.json. Earlier wilderness/dense-meadow results remain separate scene observations.


### Environment audit correction

A process audit after the asset pair found a second persistent DesertDelivery game process (PID 57412, started 21:55:48) consuming about 46% CPU, in addition to the previously disclosed unrelated editor/game. It was not one of the auto-quitting benchmark processes. Therefore the subsequent attribution, runtime-pair and asset-pair measurements included this extra background instance; statements above about no competing task workloads should be read as no simultaneous test/capture runs, not an otherwise idle machine. The paired runs shared this confound, but it limits absolute FPS claims and may affect apparent deltas. The initial 21:44 baseline predates this process. The final measurement should close that stale instance first or disclose it explicitly.


## Final fit revision: geometry verified, timing inconclusive

After the author's final waist/footpeg fit changes, the stale second DesertDelivery instance was stopped and the asset-only pair repeated with the current runtime pose shared by both assets. The unrelated user editor/game remained open. Both imports and runs completed; the new GLB was restored and reimported afterward, verified byte-for-byte against its saved backup.

Final imported character: **1,158,420 bytes, 13 mesh nodes, 43 material surfaces, 26,977 vertices, 49,957 triangles**. Versus the preserved original, this is 31.6% fewer file bytes, 18.5% fewer vertices and 18.0% fewer triangles, with the same surface count. These structural counts are reliable independently of workstation load.

The repeated timing pair is **inconclusive and must not be presented as a valid performance comparison**. The old run reported 64.38 average FPS but a highly bimodal frame distribution (7.337 ms median, 40.466 ms p95); the new run reported 17.18 FPS (57.973 ms median, 67.824 ms p95). Their timestamps unexpectedly span approximately eleven minutes, although the script launched them sequentially. A subsequent process audit showed the unrelated user's game at ~104.5% CPU and WindowServer at ~33.6% CPU. This establishes uncontrolled background activity, not the exact cause of the timing change. No regression or speedup can responsibly be attributed to the asset from this pair.

Raw observations are retained in asset-old-clean/benchmark.json and asset-new-clean/benchmark.json rather than discarded. The "clean" folder label only means the stale DesertDelivery copy was removed; it does not imply an idle or controlled machine. Earlier 48.10→52.17 FPS figures remain a single observed pair for an intermediate fit revision under disclosed background load, not a final sustained-performance claim. Final visual/correctness tests can proceed; a valid final performance comparison still needs a controlled, repeatable measurement window.

### Post-validation geometry correction
The final walk capture required closed hip caps and cloth overlap. Delivered counts supersede earlier asset-count snapshots: 1,202,432 bytes, 27,625 vertices, 51,141 triangles, 43 surfaces (29.0% smaller file, 16.1% fewer triangles than the original). No timing result is claimed for this final minor revision. See `../reference-pass/asset-counts.json` and its README for current validation.
