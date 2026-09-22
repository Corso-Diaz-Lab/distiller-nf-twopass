// modules/local/merge_dedup_final.nf
// Process B of the split-apply-combine restructure.
// Receives the pre-sorted group pairsams (from SORT_GROUP) for one library,
// merges them (order-preserving, cheap) and runs the SINGLE global
// dedup+split. Output contract is IDENTICAL to the original
// merge_dedup_splitbam so all downstream stages consume it unchanged.
//
// The dedup/split logic below is copied VERBATIM from merge_dedup_splitbam.nf
// (the correct, output-producing part). Only the input is now group-sorted
// pairsams rather than raw chunks. Because pairtools merge of sorted inputs is
// order-preserving, the single dedup here sees the same globally-sorted stream
// the monolithic version did -> identical dedup result (this is what the
// bundled-test-dataset equality check must confirm before real use).

include { initOptions; getSoftwareName; getOutputDir } from './functions'
include { isSingleFile } from './functions'

params.options = [:]
options        = initOptions(params.options)
directory      = getOutputDir('pairs_library')

ASSEMBLY_NAME = params['input'].genome.assembly_name

process MERGE_DEDUP_FINAL {
    tag "library:${library}"
    label 'process_medium'
    publishDir "${directory}", mode: params.publish_dir_mode

    conda (params.enable_conda ? "bioconda::pairtools" : null)

    input:
    tuple val(library), file(group_pairsams)

    output:
    tuple val(library), path("${library}.${ASSEMBLY_NAME}.nodups.pairs.gz"),
                 path("${library}.${ASSEMBLY_NAME}.nodups.pairs.gz.px2"),
                 path("${library}.${ASSEMBLY_NAME}.nodups.bam"),
                 path("${library}.${ASSEMBLY_NAME}.dups.pairs.gz"),
                 path("${library}.${ASSEMBLY_NAME}.dups.bam"),
                 path("${library}.${ASSEMBLY_NAME}.unmapped.pairs.gz"),
                 path("${library}.${ASSEMBLY_NAME}.unmapped.bam"), emit: output

    tuple val(library), path("${library}.${ASSEMBLY_NAME}.dedup.stats"), emit: stats

    path  "*.version.txt"         , emit: version

    script:
    def software = getSoftwareName(task.process)
    def make_pairsam = params['parse'].get('make_pairsam','false').toBoolean()
    // group_pairsams is always >1 in normal use (N groups), but guard anyway:
    def merge_command = (
        isSingleFile(group_pairsams) ?
        "bgzip -cd -@ 3 ${group_pairsams}" :
        "pairtools merge ${group_pairsams} --nproc ${task.cpus} --tmpdir \$TASK_TMP_DIR"
    )

    if(make_pairsam)
        """
        TASK_TMP_DIR=\$(mktemp -d -p ${task.distillerTmpDir} distiller.tmp.XXXXXXXXXX)

        ${merge_command} | pairtools dedup \
            --max-mismatch ${params.dedup.max_mismatch_bp} \
            --mark-dups \
            --nproc-in ${task.cpus} \
            --nproc-out ${task.cpus} \
            --output \
                >( pairtools split \
                    --output-pairs ${library}.${ASSEMBLY_NAME}.nodups.pairs.gz \
                    --output-sam ${library}.${ASSEMBLY_NAME}.nodups.bam \
                 ) \
            --output-unmapped \
                >( pairtools split \
                    --output-pairs ${library}.${ASSEMBLY_NAME}.unmapped.pairs.gz \
                    --output-sam ${library}.${ASSEMBLY_NAME}.unmapped.bam \
                 ) \
            --output-dups \
                >( pairtools split \
                    --output-pairs ${library}.${ASSEMBLY_NAME}.dups.pairs.gz \
                    --output-sam ${library}.${ASSEMBLY_NAME}.dups.bam \
                 ) \
            --output-stats ${library}.${ASSEMBLY_NAME}.dedup.stats \
            | cat

        rm -rf \$TASK_TMP_DIR
        pairix ${library}.${ASSEMBLY_NAME}.nodups.pairs.gz

        pairtools --version > ${software}.version.txt
        """
    else
        """
        TASK_TMP_DIR=\$(mktemp -d -p ${task.distillerTmpDir} distiller.tmp.XXXXXXXXXX)

        ${merge_command} | pairtools dedup \
            --max-mismatch ${params.dedup.max_mismatch_bp} \
            --mark-dups \
            --nproc-in ${task.cpus} \
            --nproc-out ${task.cpus} \
            --output ${library}.${ASSEMBLY_NAME}.nodups.pairs.gz \
            --output-unmapped ${library}.${ASSEMBLY_NAME}.unmapped.pairs.gz \
            --output-dups ${library}.${ASSEMBLY_NAME}.dups.pairs.gz \
            --output-stats ${library}.${ASSEMBLY_NAME}.dedup.stats \
            | cat

        touch ${library}.${ASSEMBLY_NAME}.unmapped.bam
        touch ${library}.${ASSEMBLY_NAME}.nodups.bam
        touch ${library}.${ASSEMBLY_NAME}.dups.bam

        rm -rf \$TASK_TMP_DIR
        pairix ${library}.${ASSEMBLY_NAME}.nodups.pairs.gz

        pairtools --version > ${software}.version.txt
        """
}
