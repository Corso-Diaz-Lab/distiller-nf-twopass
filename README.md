#distiller-nf (two-pass merge/dedup restructuring)

This repo is a derivative work based on the open2c/distiller-nf Hi-C mapping pipeline. We restructured the monolithic merge_deduplication stage of open2c/distiller-nf into a parallel 'split-apply-combine' design, enabling the pipeline to complete very deeply sequenced Hi-C libraries (Dyer) which do not finish merging and deduplication within cluster wall-time limits using the original single-process stage.

The core pipeline — mapping (bwa), pair parsing, sorting, binning, and cooler generation — is from open2c/distiller-nf and is the work of the Open2C developers. This repository modifies only the merge/deduplication stage and fixes two bugs (see below). It is released under the same MIT license, preserving the upstream copyright notice. Please cite the original distiller-nf alongside this repository (see CITATION.cff).

The problem this fork solves:

distiller-nf performs deduplication in a single merge_dedup_splitbam process that merges every mapped chunk for a library group, deduplicates the whole stream in one pass, and splits the outputs. For a deep library this stage is a single, long-running, I/O-bound, single-threaded task:

It cannot be parallelized across cores (the dedup pass is inherently serial).
Nextflow -resume operates at task granularity, so a timeout wastes the entire stage — there is no mid-task checkpoint.
On our real workload (a mouse retina Hi-C dataset, 117 sequencing runs, ~3.4 billion read pairs, mm39/GRCm39, MboI) this stage did not complete within a 7-day walltime as a single process.

## The restructuring

The single monolithic stage is split into three processes following a split-apply-combine pattern:

```
sort_group — the mapped chunks are partitioned into N groups (n_sort_groups, default 10); each group is merged/sorted independently and in parallel.
dedup_group — each sorted group is deduplicated independently and in parallel. This removes the ~88% of duplicates that are intra-group before they ever reach the final serial stage.
merge_dedup_final — the pre-deduplicated groups are merged and a single final dedup pass removes the remaining cross-group duplicates, then splits the outputs. This preserves the exact output/stats contract of the original merge_dedup_splitbam.
```

Because most duplicates are removed in parallel upstream, the final serial stage processes far less data and completes within walltime.

## Benefits
Tractability. Completes on libraries where the monolithic stage times out.
Parallelism. The sort and intra-group dedup work scale across cluster nodes.
Finer resume. A failure re-runs one group, not the whole stage.
Speed. ~1.6× faster end-to-end on a 12-sample benchmark (merge_dedup_final 6h38m two-pass vs 10h48m single-pass).
Correctness

On test data the output is exact. The bundled Open2C yeast test produces a byte-identical nodups.pairs.gz between this restructuring and the original pipeline.

On real data there is a small, systematic, well-understood difference. distiller runs pairtools dedup with fuzzy matching (--max-mismatch 3), which is non-transitive: whether two pairs are called duplicates can depend on the order and grouping in which they are compared. Staged (grouped) dedup is therefore very slightly less aggressive than a single global pass. On our data this shows up as a ~0.3–0.5% difference in total duplicates removed, and the difference scales mildly with data volume (0.27% at 3 samples → 0.34% at 12 samples).

This is not a bug and not data loss — the duplicate accounting reconciles exactly:

12-sample: intra-group dups 27,063,241 + cross-group dups 18,112,131
         = 45,175,372  (two-pass)
           vs 45,330,992 (monolith)
           → gap 155,620 (0.34%), within the run-to-run non-determinism floor

If you require a result that is exactly identical to a single global dedup even under fuzzy matching, use the original pipeline for that stage, or watch for the chromosome-pair partition successor (see Future work), which is provably exact under fuzzy matching.

## Bug fixes included

Two upstream bugs have been fixed in this repository (fixes will also be offered upstream as PR):

1. local_truncate.nf variable-name mismatch. 
The process declares inputs query1/query2 but the script body references undefined fastq1/fastq2, breaking the local-truncate path. Fixed to use the declared names.

2. --walks-policy mask discards junction reads. The default masks the "WW" category and drops ~25% of valid junction-spanning read pairs on MboI data. This repository uses --walks-policy 5unique, which rescues them. 

(Offered upstream as a discussion/issue rather than a silent default change.)

## Usage

The usage of this pipeline is identical to distiller-nf, with one added parameter. 
In your project.yml (or via --n_sort_groups) add:

yaml
n_sort_groups: 10   # number of parallel sort/dedup groups; tune to library depth

Then run as usual:

```{bash}
nextflow run distiller_dsl2.nf -params-file project.yml -profile cluster -resume
```

#### Guidance: set n_sort_groups so each group is a few hundred GB or less. For our ~3.4B-pair library, 10 groups (~230 GB each) was workable; deeper libraries benefit from more groups.

## SLURM / walltime note

Only merge_dedup_final is a long single-threaded task. In our SLURM config (cluster.config) it is the only process given a long-QoS walltime; sort_group and dedup_group are short parallel jobs and must not be placed on a QoS with a high walltime minimum (e.g. Sherlock's long QoS rejects sub-48h jobs).

## Limitations

The ~0.3–0.5% dedup difference under fuzzy matching (see Correctness).
n_sort_groups is a manual tuning knob; there is no auto-sizing yet.
Validated on bwa-mem + pairtools + cooler DSL2 path; other distiller paths inherit upstream behavior unchanged.

## Future work

A successor chromosome-pair partition scheme partitions pairs by canonical (chrom1, chrom2) key. Because duplicate mates always share the same chromosome pair, this partition is leak-proof and produces results exactly equivalent to a global dedup even under --max-mismatch 3, while eliminating the final global dedup bottleneck entirely. It is in development and targeted for a separate methods publication.

## Attribution & citation
Original pipeline: open2c/distiller-nf, © 2017–2020 Open2C, MIT license.
This restructuring and the included fixes: © 2026, released under MIT.

See CITATION.cff and NOTICE.