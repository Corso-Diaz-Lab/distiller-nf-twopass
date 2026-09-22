// modules/local/dedup_group.nf  (NEW - first dedup pass, per group)
// Process A2: dedup ONE already-sorted group. Removes INTRA-group duplicates
// only. Cross-group duplicates are caught later by the mandatory final dedup
// in merge_dedup_final. Separate process from SORT_GROUP for resume
// granularity + overlap (starts as soon as this group's sort finishes).
//
// IMPORTANT: this outputs a deduplicated-WITHIN-group pairs file that is STILL
// sorted (pairtools dedup preserves sort order of the kept pairs), so the
// downstream final merge of these group outputs remains a merge of sorted
// inputs -> the final global dedup still sees a correctly-sorted stream.
//
// CORRECTNESS NOTE: this first pass does NOT --output-dups/--output-unmapped
// or split to BAM. It just removes intra-group dup pairs and passes the kept,
// still-sorted pairs downstream. All the final stats/dups/unmapped/BAM outputs
// are produced by merge_dedup_final on the FULL merged data, so the reported
// duplicate counts remain global and correct. The intra-group pass is purely a
// data-shrinking optimization ahead of the final pass.

include { initOptions; getSoftwareName; getOutputDir } from './functions'

params.options = [:]
options        = initOptions(params.options)
directory      = getOutputDir('deduped_groups')

ASSEMBLY_NAME = params['input'].genome.assembly_name

process DEDUP_GROUP {
    tag "library:${library} group:${group_id}"
    label 'process_medium'
    publishDir "${directory}", mode: params.publish_dir_mode

    conda (params.enable_conda ? "bioconda::pairtools" : null)

    input:
    tuple val(library), val(group_id), file(sorted_group)

    output:
    tuple val(library),
        path("${library}.${ASSEMBLY_NAME}.group${group_id}.dedup.pairsam.gz"),
        emit: output
    path "*.version.txt", emit: version

    script:
    def outname = "${library}.${ASSEMBLY_NAME}.group${group_id}.dedup.pairsam.gz"
    """
    TASK_TMP_DIR=\$(mktemp -d -p ${task.distillerTmpDir} distiller.tmp.XXXXXXXXXX)

    # Intra-group dedup. --mark-dups keeps the same record structure; we keep
    # only the non-duplicate records for the downstream merge. Output stays
    # sorted (dedup preserves order of kept pairs).
    pairtools dedup \
        --max-mismatch ${params.dedup.max_mismatch_bp} \
        --nproc-in ${task.cpus} \
        --nproc-out ${task.cpus} \
        --output ${outname} \
        --output-stats ${library}.${ASSEMBLY_NAME}.group${group_id}.dedup.stats \
        ${sorted_group}

    rm -rf \$TASK_TMP_DIR
    pairtools --version > ${getSoftwareName(task.process)}.version.txt
    """
}