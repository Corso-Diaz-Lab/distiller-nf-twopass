#!/bin/bash
# =============================================================================
# Clean Nextflow's execution state for a fresh test run.
# Run from the distiller-nf directory on a login node.
#
# KEEPS: distiller_env.sif, test/genome/ (index we just built), project.yml,
#        configs/cluster.config, the local_truncate.nf patch
# REMOVES: work/, results/, .nextflow*, pipeline_info/ (all prior run state)
# =============================================================================
set -euo pipefail

cd /home/groups/ximenac/distiller-nf

echo "== Before cleanup =="
du -sh work results pipeline_info .nextflow* 2>/dev/null || true

echo ""
echo "== Removing Nextflow work directory (task execution cache) =="
rm -rf work/

echo "== Removing prior results =="
rm -rf results/

echo "== Removing prior execution reports =="
rm -rf pipeline_info/

echo "== Removing Nextflow session logs/cache =="
rm -rf .nextflow.log*
rm -rf .nextflow/

echo ""
echo "== Confirming preserved files are still intact =="
ls -la distiller_env.sif
ls -la test/genome/
ls -la configs/cluster.config
ls -la modules/local/local_truncate.nf

echo ""
echo "== Done. Ready for a clean run (no -resume this time): =="
echo "  nextflow run distiller_dsl2.nf -params-file test/test_project.yml -c configs/cluster.config"