#!/bin/bash
#SBATCH --job-name=twopass_test
#SBATCH --partition=normal
#SBATCH --time=04:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --output=logs/twopass_test_%j.out
#SBATCH --error=logs/twopass_test_%j.err
#SBATCH --account=ximenac
set -euo pipefail
mkdir -p logs
module load biology
module load nextflow/24.10.4
cd /scratch/users/singhkak/distiller-nf-twopass
rm -rf pipeline_info_twopass_test
nextflow run distiller_dsl2.nf \
    -params-file test/test_project.yml \
    -c configs/cluster.config \
    -w /scratch/users/singhkak/twopass_test_work \
    -with-report pipeline_info_twopass_test/report.html \
    -with-timeline pipeline_info_twopass_test/timeline.html \
    -resume
