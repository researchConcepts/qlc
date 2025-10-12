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
 log  "Start ver0D surfaer plots                                                               "
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
which $bdir/v0d_verify

modes="aod gaw tcol surfaer"
modes="surfaer"
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
ext="${QLTYPE}.gif"
EXP="${experiments_hyphen}"

hpath="$PLOTS_DIRECTORY/${experiments_hyphen}_${mDate}"

# Create help directory if not existent
if [  ! -d "$hpath" ]; then
  mkdir -p "$hpath"
fi

# list name for plot files used for final tex pdf
texPlotsfile="${hpath}/texPlotfiles_${QLTYPE}.list"
texFile="${texPlotsfile%.list}.tex"
# clean up previous plot file for current tex pdf creation
rm -f $texPlotsfile
touch $texPlotsfile

YY1=`echo ${sDat} | sed "s|-| |g" | awk '{printf $1}'`
MM1=`echo ${sDat} | sed "s|-| |g" | awk '{printf $2}'`
DD1=`echo ${sDat} | sed "s|-| |g" | awk '{printf $3}'`
YY2=`echo ${eDat} | sed "s|-| |g" | awk '{printf $1}'`
MM2=`echo ${eDat} | sed "s|-| |g" | awk '{printf $2}'`
DD2=`echo ${eDat} | sed "s|-| |g" | awk '{printf $3}'`
VD2="${DD2}"
#if [ ${MM2} == "01" ] && [ ${DD2} == "31" ] ;then
## ver0D constraint, check if still needed
#VD2="28"
#fi

# ver0D-specific date format for directory paths
v0d_date_range="${YY1}${MM1}${DD1}-${YY2}${MM2}${VD2}"

for mode in ${modes} ;do
	log "Processing ${PLOTTYPE} plots for mode: $mode"

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

	if [ ! -d ${pdir}/mode_${mode}/model_data/${exp1} ] ;then
		log " Error: Required data not existent: ${pdir}/mode_${mode}/model_data/${exp1}"
		log " Rerun ${SCRIPT} again to download the ${PLOTTYPE} data"
		exit 0 
	fi

	ipath="$ANALYSIS_DIRECTORY/$exp"
	tpath="$PLOTS_DIRECTORY/$exp"

	# Create output directory if not existent
  	if [    ! -d "$tpath" ]; then
    	mkdir -p "$tpath"
	fi
    
  	if [    ! -d "$ipath" ]; then
    	mkdir -p "$ipath"
	fi
    cd $ipath

	log "ver0D mode = mode_"${mode}
	if  [ ! -d ${pdir}/mode_${mode}/results/exptsets/${EXP}/${v0d_date_range} ] ;then
	if [ ${mode} == "tcol" ] ;then
	echo "to be implemented ..."
	fi
	else
	log "Nothing to do for ver0D mode = mode_"${mode}
	log "Plot directory already esxists: ${pdir}/mode_${mode}/results/exptsets/${EXP}"
	${lt} ${pdir}/mode_${mode}/results/exptsets
	fi
	log   ${pdir}/mode_${mode}
	${lt} ${pdir}/mode_${mode}
	log   ${pdir}/mode_${mode}/results/exptsets/${EXP}

done # modes

log  "----------------------------------------------------------------------------------------"
log "${texPlotsfile}"
cat  ${texPlotsfile}
log  "----------------------------------------------------------------------------------------"
tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
rm -f  ${texFile}
cat  > ${texFile} <<EOF
%===============================================================================
\subsection{${tQLTYPE} -- ${mDate} (${TIME_RESOLUTION})}
EOF
pfiles="`cat ${texPlotsfile}`"
#log "${pfiles}"
log  "----------------------------------------------------------------------------------------"
log  "sorted file list:"
sorted_files="${hpath}/sorted_files_${script_name}.list"
touch ${sorted_files}
# ToDo: adopt for ver0D file names
#log "sort_files  "${QLTYPE}" "${exp1}" "${exp2}" "$texPlotsfile" "${ext}" "${hpath}""
#     sort_files  "${QLTYPE}" "${exp1}" "${exp2}" "$texPlotsfile" "${ext}" "${hpath}"
cp ${texPlotsfile} ${sorted_files} # test / remove
tfiles="`cat ${sorted_files}`"
log         "${tfiles}"
log  "----------------------------------------------------------------------------------------"

for plot in ${tfiles} ; do

file_name=${plot}
# Extract the file name without directory and extension
file_name="${file_name##*/}"  # Remove directory path
file_name="${file_name%.*}"   # Remove extension

# Split the file name into parts
IFS="_" read -ra parts <<< "$file_name"

# tvar="${parts[7]}"
# texp="${parts[8]}"
# pvar="${tvar} of ${texp}"
# 
# for part in "${parts[@]}"; do
#   if [ "${parts[1]}" == "taylor" ] ; then
#     pvar="${tvar} (log) of ${texp}"
#   fi
#   if [ "${parts[9]}" == "diff" ]; then
#     pvar="${tvar} | diff of ${exp1}-${exp2}"
#   fi
#   if [ "${parts[10]}" == "diff" ]; then
#     pvar="${tvar} | diff of ${exp1}-${exp2} (log)"
#   fi
# done

cat >> ${texFile} <<EOF
%===============================================================================
\frame{
\frametitle{${MODEL_RESOLUTION} -- ${PLOTTYPE} - ${EXP}}
\vspace{0mm}
\centering
\begin{minipage}[t]{0.89\textwidth}
	\vspace{-2mm}
	\begin{figure}[H]
	\centering
		\includegraphics[angle=0,clip=true, trim=0mm 0mm 0mm 0mm, height=0.85\textheight, width=0.85\textwidth]{${plot}} 
%		\vspace{-10mm}\caption{. }
	\end{figure}
\end{minipage}
}
%===============================================================================
EOF
done # plot
log  "----------------------------------------------------------------------------------------"
log "${texFile}"
cat  ${texFile}
log  "----------------------------------------------------------------------------------------"

log "$ipath"
log "$tpath"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
