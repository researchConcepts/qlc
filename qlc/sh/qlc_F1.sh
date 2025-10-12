#!/bin/sh -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="ver0D"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
#log  "----------------------------------------------------------------------------------------"
 log  "Start ver0D data retrieval                                                              "
#log  "Copyright (c) 2021-2025 ResearchConcepts Io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"
pwd -P

# module load for ATOS
myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`
#log   ${HOST} ${ARCH}
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
#ln -s $vdir/v0d_get_model_data $bdir/v0d_get_model_data
#ln -s $vdir/v0d_verify         $bdir/v0d_verify
qsub="/usr/bin/sbatch"
qstt="/usr/bin/squeue -u $USER -a"
fi
hdir="$HOME"
bdir="$HOME/bin"
sdir="$SCRATCH/ver0D"
pdir="$HOME/perm/ver0D/data"
which $bdir/v0d_get_model_data

#modes="aod gaw tcol surfaer"
modes="aod gaw"
lt='ls -alrth --color=auto'

# get script name without path and extension
script_name="${SCRIPT##*/}"     # Remove directory path
script_name="${script_name%.*}" # Remove extension
QLTYPE="$script_name"

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# ----------------------------------------------------------------------------------------
# Use common parsing function from qlc_common_functions.sh
# Sets: experiments (array), sDat, eDat, config_arg
parse_qlc_arguments "$@" || exit 1

# Generic experiment handling: last experiment is the reference
num_experiments=${#experiments[@]}
if [ $num_experiments -lt 1 ]; then
    log "Error: At least one experiment required"
    exit 1
fi

# Last experiment is the reference for difference plots
ref_exp="${experiments[$((num_experiments-1))]}"
log "Reference experiment (for diff plots): $ref_exp"

# For backward compatibility, set exp1 and exp2
exp1="${experiments[0]}"
exp2="${ref_exp}"

experiments_hyphen=$(IFS=-; echo "${experiments[*]}")
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"
ext="${QLTYPE}.pdf"
EXP="${experiments_hyphen}"
REF="$ref_exp"

YY1=`echo ${sDat} | sed "s|-| |g" | awk '{printf $1}'`
MM1=`echo ${sDat} | sed "s|-| |g" | awk '{printf $2}'`
DD1=`echo ${sDat} | sed "s|-| |g" | awk '{printf $3}'`
YY2=`echo ${eDat} | sed "s|-| |g" | awk '{printf $1}'`
MM2=`echo ${eDat} | sed "s|-| |g" | awk '{printf $2}'`
DD2=`echo ${eDat} | sed "s|-| |g" | awk '{printf $3}'`
VD2="${DD2}"
if [ ${MM2} == "01" ] && [ ${DD2} == "31" ] ;then
# ver0D constraint
VD2="28"
fi

for mode in ${modes} ;do
	log "Processing ${PLOTTYPE} data retrieval for mode: $mode"

	log "TEAM_PREFIX      : $TEAM_PREFIX"
	log "EVALUATION_PREFIX: $EVALUATION_PREFIX"
	log "MODEL_RESOLUTION : $MODEL_RESOLUTION"
	log "TIME_RESOLUTION  : $TIME_RESOLUTION"
	log "mDate            : $mDate"
	log "ext              : $ext"
	log "exp1             : $exp1"
	log "exp2             : $exp2"
	log "ref_exp          : $ref_exp"
	log "experiments      : ${experiments[@]}"
	log "EXP              : $EXP"

	# Loop over all experiments
	for exp in "${experiments[@]}" ; do
	log "exp              : $exp"

	ipath="$ANALYSIS_DIRECTORY/$exp"

	# Create output directory if not existent
    
  	if [    ! -d "$ipath" ]; then
    	mkdir -p "$ipath"
	fi

    cd $ipath

	log "ver0D mode = mode_"${mode}
	log      "Start: ${pdir}/mode_${mode}/model_data/${exp}/${exp}_${YY1}${MM1}${DD1}_00.nc"
	log      "End  : ${pdir}/mode_${mode}/model_data/${exp}/${exp}_${YY2}${MM2}${DD2}_00.nc"
	if [        ! -f ${pdir}/mode_${mode}/model_data/${exp}/${exp}_${YY1}${MM1}${DD1}_00.nc ] ;then
	log  "process ver0D mode = mode_"${mode}
	cat   ${hdir}/ver0D/mode_${mode}/retrieval_settings/init.txt  | sed "s|hvvs|${exp}|g"            >  ${hdir}/ver0D/mode_${mode}/retrieval_settings/${exp}.txt
	echo "${bdir}/v0d_get_model_data -s -q ${RETRIEVE} ${mode} ${exp}  ${YY1}${MM1}-${YY2}${MM2}"    >  ${hdir}/ver0D/mode_${mode}/retrieval_settings/retrieve.sh
	log  "${hdir}/ver0D/mode_${mode}/retrieval_settings/retrieve.sh"
	ls -l ${hdir}/ver0D/mode_${mode}/retrieval_settings/retrieve.sh
	cat   ${hdir}/ver0D/mode_${mode}/retrieval_settings/retrieve.sh
	if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
		  ${hdir}/ver0D/mode_${mode}/retrieval_settings/retrieve.sh
		  v0d_joblist
	fi
	log  "v0d_joblist"
	log  "v0d_jobcancel"
	else
	log "Nothing to do for ver0D mode = mode_"${mode}
	log "Data already esxists: ${pdir}/mode_${mode}/model_data/${exp}/${exp}_${YY1}${MM1}${DD1}_00.nc"
	${lt}                      ${pdir}/mode_${mode}/model_data/${exp}/${exp}_${YY1}${MM1}${DD1}_00.nc
	fi
	log   ${pdir}/mode_${mode}/model_data
	${lt} ${pdir}/mode_${mode}/model_data
	log   ${pdir}/mode_${mode}/results/exptsets/${EXP}

done # experiments
done # modes

log "$ipath"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
