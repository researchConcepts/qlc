#!/bin/sh -e
SCRIPT="$0"
echo  "________________________________________________________________________________________"
echo  "Start ${SCRIPT} at `date`"
#echo "----------------------------------------------------------------------------------------"
#echo "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#echo "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
echo  "----------------------------------------------------------------------------------------"
if [ "$1" == "" ] ;then
echo "type, e.g.:"
echo "$HOME/qlc/bin/sqlc b2ro iqi9 2018-12-01 2018-12-31"
echo "$HOME/qlc/bin/sqlc b2ro iqi9 2018-12-01 2018-12-31 mars"
echo "Use option 'mars' to retrieve files and then submit a dependency job once all data have been retrieved."
echo "Or, option 'mars' can be skipped, if all data are already present in $HOME/qlc/Results"
echo  "________________________________________________________________________________________"
echo  "End   ${SCRIPT} at `date`"
echo  "________________________________________________________________________________________"
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
$HOME/qlc/bin/qlc $1 $2 $3 $4 $5
echo "SLURM_JOB_ID = ${jobid}"
sbatch --dependency=afterok:${jobid} --mail-user=$USER@ecmwf.int $HOME/qlc/bin/qlc $1 $2 $3 $4
EOF
else
cat > $HOME/qlc/run/qlc_batch.sh$$<<EOF
#!/bin/ksh -e
#SBATCH --job-name=$HOME/qlc/run/qlc_batch.sh$$
#SBATCH --output=log-%J.out
#SBATCH --error=err-%J.out
$HOME/qlc/bin/qlc $1 $2 $3 $4
EOF
fi
sbatch $HOME/qlc/run/qlc_batch.sh$$
squeue -u "$USER"
echo  "________________________________________________________________________________________"
echo  "End   ${SCRIPT} at `date`"
echo  "________________________________________________________________________________________"
exit 0
