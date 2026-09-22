#!/bin/bash
# =============================================================================
# capture_benchmark.sh — snapshot a completed run's benchmark + QC data into a
# permanent, labelled archive BEFORE the next run overwrites trace/report.
#
# Run this IMMEDIATELY after every test/production run completes.
#
# Usage:
#   bash capture_benchmark.sh <label> <repo_dir> <work_dir>
# Example:
#   bash capture_benchmark.sh test3_restruct \
#        /scratch/users/singhkak/distiller-nf \
#        /scratch/users/singhkak/test3_restruct_work
# =============================================================================
set -euo pipefail

LABEL="${1:?need a label, e.g. test3_restruct}"
REPO_DIR="${2:?need the repo dir (where pipeline_info lives)}"
WORK_DIR="${3:?need the -w work dir (where dedup.stats live)}"

STAMP=$(date +%Y%m%d_%H%M%S)
DEST="${HOME}/distiller_benchmarks/${LABEL}_${STAMP}"
mkdir -p "${DEST}"

echo "== Capturing benchmark snapshot for '${LABEL}' -> ${DEST} =="

# 1. Nextflow trace/report/timeline (THE benchmark data - overwritten on rerun)
for f in trace.txt report.html timeline.html dag.html; do
    if [ -f "${REPO_DIR}/pipeline_info/${f}" ]; then
        cp "${REPO_DIR}/pipeline_info/${f}" "${DEST}/"
        echo "  saved ${f}"
    fi
done

# 2. dedup stats (per library) - the QC/correctness numbers
find "${WORK_DIR}" -name "*.dedup.stats" -exec cp {} "${DEST}/" \; 2>/dev/null \
    && echo "  saved dedup.stats files"

# 3. A compact human-readable timing summary pulled from trace.txt
#    (process name, status, wall time, peak memory) sorted slowest-first
if [ -f "${DEST}/trace.txt" ]; then
    echo "  building timing_summary.tsv"
    # trace.txt columns include: name, status, realtime, peak_rss (header-driven)
    # This awk finds columns by header name so it survives column-order changes.
    awk -F'\t' '
        NR==1 {
            for (i=1;i<=NF;i++) h[$i]=i
            print "process\tstatus\trealtime\tpeak_rss"
            next
        }
        {
            print $(h["name"]) "\t" $(h["status"]) "\t" $(h["realtime"]) "\t" $(h["peak_rss"])
        }
    ' "${DEST}/trace.txt" > "${DEST}/timing_summary.tsv" 2>/dev/null \
      || echo "  (could not parse trace.txt columns - keep raw trace.txt)"
fi

# 4. Record the provenance so the snapshot is self-describing
cat > "${DEST}/SNAPSHOT_INFO.txt" <<EOF
label:     ${LABEL}
captured:  ${STAMP}
repo_dir:  ${REPO_DIR}
work_dir:  ${WORK_DIR}
git_head:  $(cd "${REPO_DIR}" && git rev-parse HEAD 2>/dev/null || echo "not a git repo")
note:      Snapshot of benchmark + QC data for the Zenodo writeup. Do not edit;
           append analysis in a separate file.
EOF

echo "== Done. Archived to: ${DEST} =="
echo "   Contents:"
ls -la "${DEST}"