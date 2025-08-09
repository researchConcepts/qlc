#!/bin/sh -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

CUSR="`echo $USER`"
PLOTTYPE="pdftex"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

log "$0 TEX_DIRECTORY = $TEX_DIRECTORY"
pwd -P

# module load for ATOS
myOS="`uname -s`"
HOST=`hostname -s  | awk '{printf $1}' | cut -c 1`
#log   ${HOST} ${ARCH}
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
module load texlive/2022
fi
# Check if pdflatex exists
if ! command_exists pdflatex; then
  log  "Error: pdflatex command not found" >&2
  exit 1
else
  log  "Success: pdflatex command found"
  TEX="`which pdflatex` -interaction=batchmode -shell-escape"
  log "${TEX}"
fi

# get script name without path and extension
script_name="${SCRIPT##*/}"     # Remove directory path
script_name="${script_name%.*}" # Remove extension
QLTYPE="$script_name"           # qlc script type
base_name="${QLTYPE%_*}"        # Remove subscript
CDATE="20`date +"%y%m%d%H"`"    # pdf creation date
CDATE="20`date +"%y%m%d%H%M"`"  # pdf creation date
ext="$PLOTEXTENSION"            # embedded plot type

# Assign the command line input parameters to variables
exp1="$1"
exp2="$2"
sDat="$3"
eDat="$4"
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# definition of tex file name
pfile="${TEAM_PREFIX}_${exp1}-${exp2}_${mDate}_${QLTYPE}-${ext}_${CDATE}"
log "pfile base name  : $pfile"

tpath="${TEX_DIRECTORY}/${pfile}"
hpath="$PLOTS_DIRECTORY/${exp1}-${exp2}_${mDate}"

# Create help directory if not existent
if [  ! -d "$hpath" ]; then
    mkdir -p "$hpath"
fi

# Create output directory if not existent
if [    ! -d "$tpath" ]; then
	mkdir -p "$tpath"
fi

cd ${tpath}
pwd -P

if [   -d "$SCRIPTS_PATH/tex_template" ]; then
    rm -rf                            ${tpath}/tex
	cp -rp $SCRIPTS_PATH/tex_template ${tpath}/tex
else
	log "Error: tex template not found! : $SCRIPTS_PATH/tex_template"
	exit 1
fi

log  "----------------------------------------------------------------------------------------"
log "Processing ${PLOTTYPE}:"

log "QLTYPE           : $QLTYPE"
log "TEAM_PREFIX      : $TEAM_PREFIX"
log "EVALUATION_PREFIX: $EVALUATION_PREFIX"
log "MODEL_RESOLUTION : $MODEL_RESOLUTION"
log "TIME_RESOLUTION  : $TIME_RESOLUTION"
log "mDate            : $mDate"
log "ext              : $ext"
log "exp1             : $exp1"
log "exp2             : $exp2"
log "USER             : $CUSR"
log "DATE             : $CDATE"

cd ${tpath}/tex
pwd -P

rm -f texPlotfiles.tex
touch texPlotfiles.tex

log  "----------------------------------------------------------------------------------------"
for subname in "${SUBSCRIPT_NAMES[@]}"; do

	name="${base_name}_${subname}"
	log "name             : $name"

	# list name for plot files used for final tex pdf
	texPlots="${hpath}/texPlotfiles_${name}.tex"
	if [ -f "${texPlots}" ]; then
		log "${texPlots}"
		cat  ${texPlots} >> texPlotfiles.tex
	else
		log "Note: No texPlotfiles_${name}.tex found!"
		log "${texPlots}"
	fi

done # name
log  "----------------------------------------------------------------------------------------"
ls -lh        texPlotfiles.tex
log  "----------------------------------------------------------------------------------------"
cat           texPlotfiles.tex > ./CAMS_PLOTS.tex
log  "----------------------------------------------------------------------------------------"
log                             "./CAMS_PLOTS.tex"
	cat                          ./CAMS_PLOTS.tex
log  "----------------------------------------------------------------------------------------"
# Replace placeholders in the template file
# XXTIT, XXRES, XEXP1, XEXP2, XXDAT, XXAVG, XXUSR, XXTEAM
TEAM=$(echo "$TEAM_PREFIX" | sed 's/_/\\\\_/g')
log "TEAM $TEAM"
sed -e "s/XXTIT/${EVALUATION_PREFIX}/g" \
    -e "s/XXRES/${MODEL_RESOLUTION}/g" \
    -e "s/XEXP1/${exp1}/g" \
    -e "s/XEXP2/${exp2}/g" \
    -e "s/XXAVG/${TIME_RESOLUTION}/g" \
    -e "s/XXDAT/${mDate}/g" \
    -e "s/XXUSR/${CUSR}/g" \
    -e "s|XTEAM|${TEAM}|g" \
     "template.tex" >    "./${pfile}.tex"
log  "${TEX}              ./${pfile}.tex"
      ${TEX}              ./${pfile}.tex
      ${TEX}              ./${pfile}.tex
      mv                  ./${pfile}.pdf $TEX_DIRECTORY/
	  if [ "${myOS}" == "Darwin" ]; then
      open   $TEX_DIRECTORY/${pfile}.pdf
      fi
      ls -lh $TEX_DIRECTORY/${pfile}.pdf
rm -f *.aux *.nav *.out *.snm *.toc *.log 
log  "----------------------------------------------------------------------------------------"
log "$tpath"
log  "----------------------------------------------------------------------------------------"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
