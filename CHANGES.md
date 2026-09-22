### 0.3.3 (2019-07-24) ###

* upgrade dependencies in docker environment
* set up deployment via CI

### 0.3.2 (2019-04-05) ###

* bugfixes in cooler

### 0.3.1 (2019-01-03) ###

* bugfixes in cooler, fastqc task and apt.list

### 0.3.0 (2019-01-02) ###

A major update of the pipeline and the config syntax.
* Simplify and speed up the pipeline by merging several groups of processes.
* Greatly reduce the storage requirements down to ~2x of the fastq.gz size.
* Introduce custom pair filtering during binning.
* Make .mcools with custom resolutions.
* Speed up the .sra->.fastq.gz conversion.
* Rename multiple config options.
* Switch from pbgzip to native bgzip multithreading.
* Allow users to change the location of the temp files.
* Post the list of the packages inside the docker on github.

### 0.2.0 (2018-11-18) ###

* report mapq in .pairs

### 0.1.1 (2018-11-09) ###

* remove .sra files when downloading data from SRA.
* use process selectors in configs.

### 0.1.0 (2018-08-04) ###

* Distiller-env: switch to pairtools v0.2.0 and cooler v0.7.10.

# Changes from upstream open2c/distiller-nf

This document records exactly what differs from the upstream pipeline, so the
derivative nature is transparent and auditable.

## v1.0.0 (2026-09-21)

### Restructured: merge/deduplication stage

**Upstream:** a single process `merge_dedup_splitbam` merges all mapped chunks
for a library group, deduplicates in one serial pass, and splits outputs.

**This fork:** replaced by three processes:

| Process | Role | Parallelism |
|---|---|---|
| `sort_group` | merge/sort one of *N* chunk groups | parallel across groups |
| `dedup_group` | dedup one sorted group (intra-group dups) | parallel across groups |
| `merge_dedup_final` | merge pre-deduped groups, final cross-group dedup, split | serial (but much smaller input) |

New parameter `n_sort_groups` (default 10) controls the partition count.

Workflow wiring in `distiller_dsl2.nf`:

```
N_GROUPS = (params.getOrDefault('n_sort_groups', 10) as int)
SORT_GROUP_INPUT = BAM.map{...}.groupTuple()
                      .flatMap{ lib, pairsams -> ...collate(sz).withIndex()... }
SORTED_GROUPS  = sort_group( SORT_GROUP_INPUT ).output
DEDUPED_GROUPS = dedup_group( SORTED_GROUPS ).output
FINAL_DEDUP_INPUT = DEDUPED_GROUPS.groupTuple()
PAIRS = merge_dedup_final( FINAL_DEDUP_INPUT )
```

The original `merge_dedup_splitbam` is retained (commented out) for reference.

### Bug fix: local_truncate.nf variable-name mismatch

The process declared inputs `query1`/`query2` but the script body referenced
undefined `fastq1`/`fastq2`. Fixed to reference the declared input names.
(To be offered upstream as a PR.)

### Behavior change: walks-policy default

Changed `pairtools parse --walks-policy` from `mask` to `5unique`. The `mask`
default assigns junction-spanning reads to the "WW" category and discards them,
losing ~25% of valid pairs on MboI data. (To be raised upstream as a
discussion/issue.)

### Output contract

`merge_dedup_final` emits the same output files and stats as the original
`merge_dedup_splitbam`, so downstream binning/zoomify stages are unchanged.

### Validation

- Bundled yeast test: byte-identical `nodups.pairs.gz` vs upstream.
- Real data (3 and 12 samples): duplicate accounting reconciles; a systematic
  ~0.3–0.5% difference in total dups removed arises from the non-transitivity of
  `pairtools dedup --max-mismatch 3` under staged grouping (documented, expected).

