#!/bin/bash -e
SCRIPT="$0"
# user specific configuration file
QLC_DIR="$HOME/qlc"
CONFIG_DIR="$QLC_DIR/config"
CONFIG_FILE="$CONFIG_DIR/qlc.conf"

# Source the configuration file and automatically export all defined variables
# to make them available to any subscripts that are called.
set -a
. "$CONFIG_FILE"
set +a

# Source the common functions script to make the 'log' function available
. "$SCRIPTS_PATH/qlc_common_functions.sh"

log  "________________________________________________________________________________________"
log  "Start ${SCRIPT} at `date`"
#log "----------------------------------------------------------------------------------------"
#log "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
log  "----------------------------------------------------------------------------------------"
if [ "$1" == "" ] ;then
log "type, e.g.:"
log "sqlc b2ro b2rn 2018-12-01 2018-12-21 mars"
log "sqlc b2ro b2rn 2018-12-01 2018-12-21"
log " "
log "Use option 'mars' to retrieve files and then submit a a dependency job once all data have been retrieved."
log "Or, option 'mars' can be skipped, if all data are already present in $MARS_RETRIEVAL_DIRECTORY"
log  "________________________________________________________________________________________"
log  "End   ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"
exit 0
fi
if [ "$5" == "mars" ] ;then
jobid='${SLURM_JOB_ID}'
cat > $HOME/qlc/run/qlc_batch.sh$$<<EOF
#!/bin/ksh -e
#SBATCH --job-name=$HOME/qlc/run/qlc_batch.sh$$
#SBATCH --output=log-%J.out
#SBATCH --error=err-%J.out
#SBATCH --export=ALL
qlc $1 $2 $3 $4 $5
echo "SLURM_JOB_ID = ${jobid}"
sbatch --dependency=afterok:${jobid} --mail-user=$USER@ecmwf.int qlc $1 $2 $3 $4
EOF
else
cat > $HOME/qlc/run/qlc_batch.sh$$<<EOF
#!/bin/ksh -e
#SBATCH --job-name=$HOME/qlc/run/qlc_batch.sh$$
#SBATCH --output=log-%J.out
#SBATCH --error=err-%J.out
qlc $1 $2 $3 $4
EOF
fi
sbatch $HOME/qlc/run/qlc_batch.sh$$
squeue -u "$USER"
log  "________________________________________________________________________________________"
log  "End   ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"
exit 0
