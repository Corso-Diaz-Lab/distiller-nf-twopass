// modules/local/sort_group.nf  (REVISED for two-pass dedup)
// Process A1: sort ONE group of chunk pairsams. Sort only, no dedup.
// Kept as a SEPARATE process from dedup_group so that:
//   - a group's sort is independently cached (-resume can skip it even if the
//     group's later dedup failed)
//   - dedup_group for a group can start the moment THIS finishes, overlapping
//     with slower groups' sorts.

include { initOptions; getSoftwareName; getOutputDir } from './functions'
include { isSingleFile } from './functions'

params.options = [:]
options        = initOptions(params.options)
directory      = getOutputDir('sorted_groups')

ASSEMBLY_NAME = params['input'].genome.assembly_name

process SORT_GROUP {
    tag "library:${library} group:${group_id}"
    label 'process_high'
    publishDir "${directory}", mode: params.publish_dir_mode

    conda (params.enable_conda ? "bioconda::pairtools" : null)

    input:
    tuple val(library), val(group_id), file(group_pairsams)

    output:
    tuple val(library), val(group_id),
        path("${library}.${ASSEMBLY_NAME}.group${group_id}.sorted.pairsam.gz"),
        emit: output
    path "*.version.txt", emit: version

    script:
    def outname = "${library}.${ASSEMBLY_NAME}.group${group_id}.sorted.pairsam.gz"
    def merge_command = (
        isSingleFile(group_pairsams) ?
        "cp \$(readlink -f ${group_pairsams}) ${outname}" :
        "pairtools merge ${group_pairsams} --nproc ${task.cpus} --tmpdir \$TASK_TMP_DIR -o ${outname}"
    )
    """
    TASK_TMP_DIR=\$(mktemp -d -p ${task.distillerTmpDir} distiller.tmp.XXXXXXXXXX)
    ${merge_command}
    rm -rf \$TASK_TMP_DIR
    pairtools --version > ${getSoftwareName(task.process)}.version.txt
    """
}