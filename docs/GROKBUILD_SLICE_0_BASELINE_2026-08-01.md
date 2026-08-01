# GrokBuild Slice 0 Baseline — 2026-08-01

This is the pre-Slice-1 baseline required by the coherence and accessibility repair plan. It contains counts and timing only: no prompts, transcript text, credentials, headers, environment values, raw session identifiers, or private file paths.

## Identity

- Hardware: MacBook Air (M1, 8-core CPU, 8 GB memory)
- OS: macOS 26.5.2
- Installed app before the slice: clean build of `f7cb3183`
- Source branch at measurement: `codex/warm-glass-ui`
- Plan commit at measurement: `ee55e48ebc2e6181226302995df56959529ee115`
- Installed and packaged executable SHA-256: `464e2cd2bdcfa7e1ba2b94a3b442ca35677e25a00a7cab8b10fd09b78f84ccd8`
- Grok CLI: 0.2.118

## Corpus

| Corpus | Count | Size / rows |
|---|---:|---:|
| v2 session-layout records | 24 | 7,902 bytes |
| Stored local transcript blobs | 33 | 128,256 bytes; 173 rows |
| Backend history files | 141 | 8,508,173 bytes |
| Full automated suite | 413 tests | 0 failures; 13.475 seconds |

The Slice 0 synthetic corpus is under `Tests/GrokBuildTests/Fixtures/CoherenceRepair/`. It freezes empty/synthetic-only, verified, divergent, and composite worker/parent histories; Grok 0.2.118 `externalCompat`; MCP help and serialization shapes; and versioned transcript-normalization/HMAC vectors.

## Installed-app measurements

Ten one-second settled samples of the old installed app produced:

| Signal | Samples | P50 | P95 | Mean |
|---|---:|---:|---:|---:|
| App CPU | 10 | 0.0% | 0.0% | 0.0% |
| App RSS | 10 | 106,576 KiB | 106,624 KiB | 106,581 KiB |

The settled owned process tree contained one GrokBuild app process, one idle Grok agent process, one browser helper, and one Computer Use MCP helper. All observed owned processes were idle. This short baseline does not satisfy the plan's later ten-minute soak gate.

Fresh accessibility-tree reads of the exact installed app, after one warm-up, took 126–161 ms across ten samples (P50 131 ms, P95 161 ms). One Computer Use navigation round trip to Settings took 1,387 ms; Skills took 2,576 ms; Marketplace took 1,657 ms; returning to the existing session succeeded.

Those navigation numbers include accessibility snapshotting, action dispatch, and automation transport. They are not product-only signpost durations and therefore cannot revise the provisional D6 budgets. Slice 0 adds the redacted `os_signpost` lanes needed to separate product work from automation overhead in subsequent profiling.

## Required signpost contract

`GrokBuildPerformanceLane` pins all fifteen D5 spans: launch, layout, restore decision, selected transcript load, continuity verification, process readiness, first chunk, settled render, tab switching, Settings pane load, model catalog, provider credential metadata, rich-message parsing, Mermaid rendering, and transcript writes. The subsystem is `com.grokbuild.app`, category `Performance`. Call sites attach no dynamic content.

## Baseline limitations

- The pre-slice installed build had no product signposts, so only accessibility round trips and process samples were available.
- Skills and Marketplace exceeded their provisional cold-load hard limits when measured end-to-end through Computer Use; the product/automation split is not yet known.
- No backend history, installed artifact, or v2 preference data was mutated to collect this baseline.
