#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="pyferret"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create Ferret plots for selected variables (to be defined in $CONFIG_FILE)              "
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"

# module load for ATOS
myOS="$(uname -s)"
HOST="$(hostname -s | cut -c 1)"
log "HOST = ${HOST} | $(hostname -s)"
log "myOS = ${myOS}"

if [ "${HOST}" = "a" ] && [ "${myOS}" != "Darwin" ]; then
    # Only on ATOS-like hosts (non-macOS, short host starting with 'a')
    if command -v module >/dev/null 2>&1; then
        module load ferret/7.6.3
    else
        log "[WARN] 'module' command not found; skipping ferret module load"
    fi
else
    # Conda activation for pyferret/ferret environment
    # Try multiple possible environment names and base paths
    for base in "$HOME/miniforge3" "$HOME/anaconda3" "/opt/homebrew/anaconda3"; do
        if [ -f "$base/etc/profile.d/conda.sh" ]; then
            . "$base/etc/profile.d/conda.sh"
            # Try activating common pyferret environment names
            for env in "pyferret_env" "pyferret" "ferret"; do
                if conda activate "$env" 2>/dev/null; then
                    log "[INFO] conda activate $env"
                    log "[INFO] Activated conda environment: $env"
                    source $HOME/ferret_paths.sh
                    break 2
                fi
            done
        fi
    done
fi

# Determine the pyferret command to use.
# Check multiple possible locations
PYFERRET_CMD=""
if command -v pyferret &> /dev/null; then
    PYFERRET_CMD="pyferret"
    log "Using 'pyferret' found in system PATH: `which $PYFERRET_CMD`"
else
    # Search for pyferret in common conda environment locations
    for base in "$HOME/miniforge3" "$HOME/anaconda3" "/opt/homebrew/anaconda3"; do
        for env in "pyferret_env" "pyferret" "ferret"; do
            if [ -x "$base/envs/$env/bin/pyferret" ]; then
                log "Using 'pyferret' from conda environment: $env at $base"
                PYFERRET_CMD="$base/envs/$env/bin/pyferret"
                break 2
            fi
        done
    done
fi

# Check if we found a valid pyferret command
if [ -z "$PYFERRET_CMD" ]; then
  ARCH=$(uname -m)
  log  "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  log  "WARNING: pyferret command not found."
  log  "The qlc_C5.sh script requires pyferret for generating global map plots."
  log  ""
  
  if [ "$ARCH" = "arm64" ]; then
    log  "IMPORTANT: You are running on Apple Silicon (ARM64) architecture."
    log  "PyFerret native ARM64 builds are not available, but it CAN run via Rosetta 2."
    log  ""
    log  "Installation options for Apple Silicon:"
    log  ""
    log  "Option 1: Install x86_64 conda and pyferret (via Rosetta 2)"
    log  "  # Install Rosetta 2 if not already installed"
    log  "  softwareupdate --install-rosetta"
    log  ""
    log  "  # Download x86_64 version of Anaconda/Miniforge"
    log  "  arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh)\""
    log  ""
    log  "  # Create x86_64 environment with pyferret"
    log  "  CONDA_SUBDIR=osx-64 conda create -n ferret python=3.10"
    log  "  conda activate ferret"
    log  "  conda config --env --set subdir osx-64"
    log  "  conda install -c conda-forge pyferret"
    log  ""
    log  "Option 2: Disable C5 script"
    log  "  Remove 'C5' from SUBSCRIPT_NAMES array in your config file"
    log  ""
    log  "Note: All other QLC functionality works natively on Apple Silicon."
  else
    log  "PyFerret is available via conda-forge for your architecture."
    log  "To install pyferret:"
    log  ""
    log  "    conda activate qlc-dev"
    log  "    conda install -c conda-forge pyferret"
    log  ""
    log  "Alternatively, you can disable this script by removing 'C5' from the"
    log  "SUBSCRIPT_NAMES array in your config file."
  fi
  
  log  "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  log  "Skipping pyferret plots and exiting script gracefully."
  exit 0
fi

# Create output directory if not existent
if [    ! -d "$PLOTS_DIRECTORY" ]; then
    mkdir -p "$PLOTS_DIRECTORY"
fi

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
ext="$PLOTEXTENSION"
ulev="$UTLS"

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

# Loop over all experiments
for exp in "${experiments[@]}" ; do
	log  "----------------------------------------------------------------------------------------"
	log "Processing ${PLOTTYPE} plot for experiment: $exp (reference: $ref_exp)"

	log "QLTYPE           : $QLTYPE"
	log "TEAM_PREFIX      : ${TEAM_PREFIX}"
	log "EVALUATION_PREFIX: ${EVALUATION_PREFIX}"
	log "MODEL_RESOLUTION : ${MODEL_RESOLUTION}"
	log "TIME_RESOLUTION  : ${TIME_RESOLUTION}"
	log "mDate            : $mDate"
	log "ext              : $ext"
	log "exp1             : $exp1"
	log "exp2             : $exp2"
	log "ulev             : $ulev"

	# definition of plot file base name (includes all experiments)
	pfile="${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}"
	log "pfile base name  : $pfile"

	ipath="$ANALYSIS_DIRECTORY/$exp"
	tpath="$PLOTS_DIRECTORY/$exp"

	# Create analysis directory if not existent
  	if [  ! -d "$ipath" ]; then
    	mkdir -p "$ipath"
	fi
	# Create output directory if not existent
  	if [  ! -d "$tpath" ]; then
    	mkdir -p "$tpath"
	fi

	cd $tpath
	pwd -P

    for name in "${MARS_RETRIEVALS[@]}"; do

	  log "name             : $name"

	  # Define the corresponding arrays based on the name
	  param_var="param_${name}[@]"
	  ncvar_var="ncvar_${name}[@]"
	  myvar_var="myvar_${name}[@]"

	  log "param_var        : $param_var"
	  log "ncvar_var        : $ncvar_var"
	  log "myvar_var        : $myvar_var"

	  # Use variable indirection to access the arrays
	  param=("${!param_var}")
	  ncvar=("${!ncvar_var}")
	  myvar=("${!myvar_var}")

	  log "param            : $param"
	  log "ncvar            : $ncvar"
	  log "myvar            : $myvar"

	  # Loop through the variables for this $name
	  for ((i = 0; i < ${#ncvar[@]}; i++)); do

		myvar_name="${myvar[i]}"
		pvars="${myvar_name}"

		log "i                : $i"
		log "#ncvar[@]        : "${#ncvar[@]}
		log "myvar_${name}[@] : "myvar_${name}[@]
		log "myvar_name       : $myvar_name"
		log "pvars            : ${pvars}"
		
		# special case for diagnostic output of EQSAM4clim (71 / 80 sub-variables)
	  	if [ "${name}" == "E" ]; then
		case "$myvar_name" in
			"EQdiag")
#		     declare -a pvars=("GFh2o" "GFhsa" "GFhna" "GFhca" "GFxam" "GFalc" "GFasu" "GFahs" "GFano" "GFacl" "GFslc" "GFssu" "GFshs" "GFsno" "GFscl" "GFplc" "GFpsu" "GFphs" "GFpno" "GFpcl" "GFc01" "GFcsu" "GFc02" "GFcno" "GFccl" "GFm01" "GFmsu" "GFm02" "GFmno" "GFmcl" "AWh2o" "AWhsa" "AWhna" "AWhca" "AWxam" "AWalc" "AWasu" "AWahs" "AWano" "AWacl" "AWslc" "AWssu" "AWshs" "AWsno" "AWscl" "AWplc" "AWpsu" "AWphs" "AWpno" "AWpcl" "AWc01" "AWcsu" "AWc02" "AWcno" "AWccl" "AWm01" "AWmsu" "AWm02" "AWmno" "AWmcl" "EQpH1" "EQpH2" "EQpH3" "EQpH4" "EQpH5" "EQAW1" "EQAW2" "EQAW3" "EQAW4" "EQAD" "EQHp" "EQPMt" "EQPMs" "EQsPM" "EQaPM" "EQRHO" "EQGF" "EQTT" "EQRH" "EQP")
#			 declare -a nvars=(  "1"     "2"     "3"     "4"     "5"     "6"     "7"     "8"     "9"     "10"   "11"    "12"    "13"     "14"    "15"   "16"     "17"    "18"    "19"    "20"    "21"    "22"    "23"    "24"    "25"   "26"     "27"   "28"     "29"    "30"    "31"    "32"    "33"    "34"    "35"   "36"     "37"    "38"    "39"    "40"    "41"    "42"    "43"    "44"    "45"    "46"    "47"    "48"    "49"    "50"    "51"   "52"     "53"    "54"    "55"    "56"    "57"    "58"    "59"    "60"   "61"    "62"     "63"    "64"    "65"   "66"    "67"    "68"    "69"    "70"   "71"   "72"    "73"    "74"    "75"     "76"   "77"   "78"   "79"   "80")
#			 declare -a nvars=(  "1"     "2"     "3"     "4"     "5"     "6"     "7"     "8"     "9"     "10"   "11"    "12"    "13"     "14"    "15"   "16"     "17"    "18"    "19"    "20"    "21"    "22"    "23"    "24"    "25"   "26"     "27"   "28"     "29"    "30"    "31"    "32"    "33"    "34"    "35"   "36"     "37"    "38"    "39"    "40"    "41"    "42"    "43"    "44"    "45"    "46"    "47"    "48"    "49"    "50"    "51"   "52"     "53"    "54"    "55"    "56"    "57"    "58"    "59"    "60"   "61"    "62"     "63"    "64"    "65"   "66"    "67"    "68"    "69"    "70"     "71"   "72"    "73"    "74"    "75"     "76"   "77"    "78"    "79"    "80")
#			 declare -a pvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre" "GFalc" "GFasu" "GFahs" "GFano" "GFacl" "GFslc" "GFssu" "GFshs" "GFsno" "GFscl" "GFplc" "GFpsu" "GFphs" "GFpno" "GFpcl" "GFc01" "GFcsu" "GFc02" "GFcno" "GFccl" "GFm01" "GFmsu" "GFm02" "GFmno" "GFmcl" "LWtot" "LWaeq" "LWaer" "LWcld" "LWpre" "AWalc" "AWasu" "AWahs" "AWano" "AWacl" "AWslc" "AWssu" "AWshs" "AWsno" "AWscl" "AWplc" "AWpsu" "AWphs" "AWpno" "AWpcl" "AWc01" "AWcsu" "AWc02" "AWcno" "AWccl" "AWm01" "AWmsu" "AWm02" "AWmno" "AWmcl" "eq_TT" "eq_RH" "eq__P" "eq_ID" "eqPMt" "eqPMs" "eqsPM" "eqaPM" "eqRHO" "eq_Hp" "eq_GF" "DUMMY" "DUMMY" "DUMMY" "DUMMY" "DUMMY" "DUMMY" "DUMMY" "DUMMY" "DUMMY")
#			 declare -a nvars=(  "1"     "2"     "3"     "4"     "5"     "6"     "7"     "8"     "9"     "10"   "11"    "12"    "13"     "14"    "15"   "16"     "17"    "18"    "19"    "20"    "21"    "22"    "23"    "24"    "25"   "26"     "27"   "28"     "29"    "30"    "31"    "32"    "33"    "34"    "35"   "36"     "37"    "38"    "39"    "40"    "41"    "42"    "43"    "44"    "45"    "46"    "47"    "48"    "49"    "50"    "51"   "52"     "53"    "54"    "55"    "56"    "57"    "58"    "59"    "60"   "61"    "62"     "63"    "64"    "65"   "66"    "67"    "68"    "69"    "70"     "71" )
			 declare -a pvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre" "GFalc" "GFasu" "GFahs" "GFano" "GFacl" "GFslc" "GFssu" "GFshs" "GFsno" "GFscl" "GFplc" "GFpsu" "GFphs" "GFpno" "GFpcl" "GFc01" "GFcsu" "GFc02" "GFcno" "GFccl" "GFm01" "GFmsu" "GFm02" "GFmno" "GFmcl" "LWtot" "LWaeq" "LWaer" "LWcld" "LWpre" "AWalc" "AWasu" "AWahs" "AWano" "AWacl" "AWslc" "AWssu" "AWshs" "AWsno" "AWscl" "AWplc" "AWpsu" "AWphs" "AWpno" "AWpcl" "AWc01" "AWcsu" "AWc02" "AWcno" "AWccl" "AWm01" "AWmsu" "AWm02" "AWmno" "AWmcl" "eqTT"  "eqRH"   "eqP"   "eqID" "eqPMt" "eqPMs" "eqsPM" "eqaPM" "eqRHO" "eqHp"  "eqGF")
#			 declare -a pvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre" "LWtot" "LWaeq" "LWaer" "LWcld" "LWpre")
#			 declare -a pvars=("pHtot" "pHaeq" "pHaer" "pHcld" "pHpre")
#			 declare -a pvars=("GFano" "AWano")
			 ;;
		esac
	  	fi

		log "pvars            : ${pvars}"
	
		for ((j=0; j<${#pvars[@]}; j++)); do
		  pvar="${pvars[$j]}"
		  if [[ "$pvar" == *"_"* ]]; then
		     pvar2=$(echo "$pvar" | sed 's/_/\-/g')
		  else
		     pvar2=$pvar
		  fi

		  log "j                : $j"
		  log "pvar             : ${pvar}"

	 		# one NC-file file for each variable is expected here
   		  	# Extract the data level type
   		  	cd $ipath
			file="`echo ${exp}_${mDate}_*${pvar}_tavg.nc`"
		  	ltype="_$(echo "$file" | awk -F'_' '{print $4}' | cut -d'.' -f1)"
  			cd $tpath

#			ifile="$ipath/${exp}_${mDate}_${name}${ltype}_${pvar}_tavg.nc"
#			ifile1="$ANALYSIS_DIRECTORY/$exp1/${exp1}_${mDate}_${name}${ltype}_${pvar}_tavg.nc"
#			ifile2="$ANALYSIS_DIRECTORY/$exp2/${exp2}_${mDate}_${name}${ltype}_${pvar}_tavg.nc"

		ifile="$ipath/${exp}_${mDate}_${name}_${pvar}_tavg.nc"
		# For diff plots: current experiment vs reference experiment
		ifile_current="$ANALYSIS_DIRECTORY/$exp/${exp}_${mDate}_${name}_${pvar}_tavg.nc"
		ifile_ref="$ANALYSIS_DIRECTORY/$ref_exp/${ref_exp}_${mDate}_${name}_${pvar}_tavg.nc"

			if [ -f "${ifile}" ]; then
			
			rm -f          ${pvar}.nc
			ln -s ${ifile} ${pvar}.nc
			
			nlev="`ncdump -h ${pvar}.nc | grep 'plev = ' | awk -F' ' '{print $3}'`"
			if [ "${nlev}" == "" ] ; then
				plev="0"
			else
				plev="${nlev}"
			fi
			log "Model level array index ${plev} for: $pvar"

			# definition of plot files for each exp + variable (log, diff for exp1)
#			tfile="${pfile}_${name}_${pvar}_${exp}"
			tfile="${pfile}_${name}_${pvar2}_${exp}"

			log "${PLOTTYPE} plot for: $pvar - $tpath/$tfile.$ext"

			# ferret journal file variable definition
			var='`var`'
			pal='`pal`'
			lon='`lon`'
			lat='`lat`'
			lev='`lev`'
			tim='`tim`'
  			ulev="${ulev}"
			facS="1*"
			facB="1*"
			facZ="1*"
			facM="1*"
			facU="1*"
			if   [ "${pvar}" == "NO3a" ] || [ "${pvar}" == "NO3_ks" ] || [ "${pvar}" == "NO3_as" ] || [ "${pvar}" == "NO3_cs" ]; then
			   facS="1e11*"
			   facB="1e10*"
			   facZ="1e11*"
			   facM="1e11*"
			   facU="1e10*"
			elif [ "${pvar}" == "NO3b" ]; then
			   facS="1e11*"
			   facB="1e10*"
			   facZ="1e11*"
			   facM="1e11*"
			   facU="1e11*"
			elif [ "${pvar}" == "HNO3" ]; then
			   facS="1e11*"
			   facB="1e9*"
			   facZ="1e10*"
			   facM="1e10*"
			   facU="1e9*"
			elif [ "${pvar}" == "NH3"  ]; then
			   facS="1e11*"
			   facB="1e10*"
			   facZ="1e11*"
			   facM="1e11*"
			   facU="1e11*"
			elif [ "${pvar}" == "NH4" ] || [ "${pvar}" == "NH4_ks" ] || [ "${pvar}" == "NH4_as" ] || [ "${pvar}" == "NH4_cs" ]; then
			   facS="1e11*"
			   facB="1e10*"
			   facZ="1e11*"
			   facM="1e11*"
			   facU="1e10*"
			elif [ "${pvar}" == "O3" ]; then
			   facS="1e8*"
			   facB="1e7*"
			   facZ="1e7*"
			   facM="1e7*"
			   facU="1e8*"
			elif [ "${pvar}" == "AOD" ]; then
			   facS="1e1*"
			   facB="1e1*"
			   facZ="1e1*"
			   facM="1e1*"
			   facU="1e1*"
			elif [ "${pvar}" == "SO2" ]; then
			   facS="1e11*"
			   facB="1e10*"
			   facZ="1e11*"
			   facM="1e11*"
			   facU="1e11*"
			elif [ "${pvar}" == "SO4" ] || [ "${pvar}" == "SO4_ks" ] || [ "${pvar}" == "SO4_as" ] || [ "${pvar}" == "SO4_cs" ]; then
			   facS="1e10*"
			   facB="1e9*"
			   facZ="1e11*"
			   facM="1e11*"
			   facU="1e10*"
			fi

# create default ferret journal file (variable independent)
# To resolve system dependent memory issues, please see:
# https://ferret.pmel.noaa.gov/Ferret/documentation/users-guide/commands-reference/SET#_VPINDEXENTRY_set_memory
# SET MEMORY/SIZE=100 (Approximately 0.8 Gigabytes)
FERRETMEMSIZE="500"
LEVELS1='/LEVELS="(1,10,0.5,0)(10,50,5,0)(50,100,10,0)"'
LEVELS2='/LEVELS="(-10,10,0.5,0)"'
LEVELS3='/LEVELS="(-2,2,0.1,0)"'
LEVELS4='/LEVELS="(-10,-1,0.5,0)(-1,0,0.1,0)(0,1,0.1,0)(1,10,0.5,0)"'
LEVELS2=''
LEVELS3=''
CONTOUR='CONTOUR/OVER/NOLAB/COLOR=lightgrey'
cat > ${tfile}_burden_1x1.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${pvar}.nc
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
!let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90"
let tim="@AVE"
let lev="@SUM"
let var="${facB}${pvar}"
fill ${pal} ${LEVELS1} /title="Burden: ${MODEL_RESOLUTION} - ${exp}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS1}                                                       (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_burden.$ext
  FRAME/file=${tfile}_burden.$ext
!SPAWN ls -l ${tfile}_burden.$ext
fill ${pal} ${LEVELS2}  /title="Burden: ${MODEL_RESOLUTION} - ${exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS2}                                                            (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_burden_log.$ext
  FRAME/file=${tfile}_burden_log.$ext
!SPAWN ls -l ${tfile}_burden_log.$ext
!SPAWN pwd
EOF
cat > ${tfile}_burden_1x1_diff.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${ifile_current}
use ${ifile_ref}
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
!let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90"
let tim="@AVE"
let lev="@SUM"
let var="${facB}${pvar}"
fill ${pal}  /title="Burden: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
!${CONTOUR}                                                                       (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_burden_diff.$ext
  FRAME/file=${tfile}_burden_diff.$ext
!SPAWN ls -l ${tfile}_burden_diff.$ext
fill  ${pal}  /title="Burden: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}                                                                             (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_burden_log_diff.$ext
  FRAME/file=${tfile}_burden_log_diff.$ext
!SPAWN ls -l ${tfile}_burden_log_diff.$ext
!SPAWN pwd
EOF
######## zonal plots ########
FERRETMEMSIZE="4000" # 5000
cat > ${tfile}_zonal_1x1.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${pvar}.nc
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
!let pal="/PALETTE=white_centered"
let lon="-180:180@AVE"
let lat="-90:90"
let tim="@AVE"
let lev="1:${plev}"
let var="${facZ}${pvar}"
fill ${pal} ${LEVELS1} /title="Zonal avg: ${MODEL_RESOLUTION} - ${exp}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS1}                                                          (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_zonal.$ext
  FRAME/file=${tfile}_zonal.$ext
!SPAWN ls -l ${tfile}_zonal.$ext
fill ${pal} ${LEVELS2} /title="Zonal avg: ${MODEL_RESOLUTION} - ${exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS2}                                                              (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_zonal_log.$ext
  FRAME/file=${tfile}_zonal_log.$ext
!SPAWN ls -l ${tfile}_zonal_log.$ext
!SPAWN pwd
EOF
cat > ${tfile}_zonal_1x1_diff.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${ifile_current}
use ${ifile_ref}
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
SET VAR/BAD=-9.e+33 ${pvar}
!let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
let pal="/PALETTE=white_centered"
let lon="-180:180@AVE"
let lat="-90:90"
let tim="@AVE"
let lev="1:${plev}"
let var="${facZ}${pvar}"
fill  ${pal}  /title="Zonal avg: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
${CONTOUR}                                                                           (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_zonal_diff.$ext
  FRAME/file=${tfile}_zonal_diff.$ext
!SPAWN ls -l ${tfile}_zonal_diff.$ext
fill  ${pal}  /title="Zonal avg: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}                                                                                (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_zonal_log_diff.$ext
  FRAME/file=${tfile}_zonal_log_diff.$ext
!SPAWN ls -l ${tfile}_zonal_log_diff.$ext
!SPAWN pwd
EOF
######## meridional plots ######## 
cat > ${tfile}_meridional_1x1.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${pvar}.nc
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
!let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90@AVE"
let tim="@AVE"
let lev="1:${plev}"
let var="${facM}${pvar}"
fill ${pal} ${LEVELS1} /title="Meridional avg: ${MODEL_RESOLUTION} - ${exp}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS1}                                                               (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_meridional.$ext
  FRAME/file=${tfile}_meridional.$ext
!SPAWN ls -l ${tfile}_meridional.$ext
fill ${pal} ${LEVELS2} /title="Meridional avg: ${MODEL_RESOLUTION} - ${exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS2}                                                                   (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_meridional_log.$ext
  FRAME/file=${tfile}_meridional_log.$ext
!SPAWN ls -l ${tfile}_meridional_log.$ext
!SPAWN pwd
EOF
cat > ${tfile}_meridional_1x1_diff.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${ifile_current}
use ${ifile_ref}
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
!let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90@AVE"
let tim="@AVE"
let lev="1:${plev}"
let var="${facM}${pvar}"
fill  ${pal}  /title="Meridional avg: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
${CONTOUR}                                                                                (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_meridional_diff.$ext
  FRAME/file=${tfile}_meridional_diff.$ext
!SPAWN ls -l ${tfile}_meridional_diff.$ext
fill  ${pal}  /title="Meridional avg: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}                                                                                     (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_meridional_log_diff.$ext
  FRAME/file=${tfile}_meridional_log_diff.$ext
!SPAWN ls -l ${tfile}_meridional_log_diff.$ext
!SPAWN pwd
EOF
######## surface plots ########
FERRETMEMSIZE="500"
cat > ${tfile}_surface_1x1.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${pvar}.nc
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
!let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90"
let tim="@AVE"
let lev="${plev}"
let var="${facS}${pvar}"
fill ${pal} ${LEVELS1} /title="Surface: ${MODEL_RESOLUTION} - ${exp}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS1}                                                        (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_surface.$ext
  FRAME/file=${tfile}_surface.$ext
!SPAWN ls -l ${tfile}_surface.$ext
fill ${pal} ${LEVELS2} /title="Surface: ${MODEL_RESOLUTION} - ${exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS2}                                                            (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_surface_log.$ext
  FRAME/file=${tfile}_surface_log.$ext
!SPAWN ls -l ${tfile}_surface_log.$ext
!SPAWN pwd
EOF
cat > ${tfile}_surface_1x1_diff.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${ifile_current}
use ${ifile_ref}
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
!let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90"
let tim="@AVE"
let lev="${plev}"
let var="${facS}${pvar}"
fill  ${pal}  /title="Surface: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
!${CONTOUR}                                                                         (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_surface_diff.$ext
  FRAME/file=${tfile}_surface_diff.$ext
!SPAWN ls -l ${tfile}_surface_diff.$ext
fill  ${pal}  /title="Surface: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}                                                                              (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_surface_log_diff.$ext
  FRAME/file=${tfile}_surface_log_diff.$ext
!SPAWN ls -l ${tfile}_surface_log_diff.$ext
!SPAWN pwd
EOF
######## UTLS plots ######## 
FERRETMEMSIZE="500"
cat > ${tfile}_utls_1x1.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${pvar}.nc
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
!let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90"
let tim="@AVE"
let lev="${ulev}@SUM"
let var="${facU}${pvar}"
fill ${pal} ${LEVELS1} /title="UTLS: ${MODEL_RESOLUTION} - ${exp}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR} ${LEVELS1}                                                     (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_utls.$ext
  FRAME/file=${tfile}_utls.$ext
!SPAWN ls -l ${tfile}_utls.$ext
fill ${pal} ${LEVELS3} /title="UTLS: ${MODEL_RESOLUTION} - ${exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR} ${LEVELS3}                                                         (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_utls_log.$ext
  FRAME/file=${tfile}_utls_log.$ext
!SPAWN ls -l ${tfile}_utls_log.$ext
!SPAWN pwd
EOF
cat > ${tfile}_utls_1x1_diff.jnl <<EOF
! pyferret -nodisplay -script ferret_1x1.jnl
use ${ifile_current}
use ${ifile_ref}
show data
CANCEL MODE logo
SET MEMORY/SIZE=${FERRETMEMSIZE}
SET VAR/BAD=-9.e+33 ${pvar}
PPL AXLSZE,0.14,0.14
PPL LABSET 0.18,0.18,0.18,0.18 ! character heights for labels
PPL SHASET 0 100 100 100 ! white for 0% LEVEL
!let pal="/PALETTE=rainbow"
!let pal="/PALETTE=rain_cmyk"
!let pal="/PALETTE=no_green_centered"
let pal="/PALETTE=white_centered"
let lon="-180:180"
let lat="-90:90"
let tim="@AVE"
let lev="${ulev}@SUM"
let var="${facU}${pvar}"
fill  ${pal}  /title="UTLS: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
!${CONTOUR}                                                                     (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_utls_diff.$ext
  FRAME/file=${tfile}_utls_diff.$ext
!SPAWN ls -l ${tfile}_utls_diff.$ext
fill  ${pal}  /title="UTLS: ${MODEL_RESOLUTION} - Diff: ${exp}-${ref_exp}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}                                                                          (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_utls_log_diff.$ext
  FRAME/file=${tfile}_utls_log_diff.$ext
!SPAWN ls -l ${tfile}_utls_log_diff.$ext
!SPAWN pwd
EOF
######## ########## ######## 

			# ferret plots using user provided journal file
			  ferret="$SCRIPTS_PATH/pyferret/ferret_${pvar}"
			if [ -f  "$ferret.jnl" ]; then
			    cp -p $ferret.jnl  .
				rm -f ${tfile}_burden.${ext} ${tfile}_burden_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script $ferret.jnl ${ifile} ${pvar} ${MODEL_RESOLUTION} ${exp} ${tfile}_burden ${ext}"
					 $PYFERRET_CMD -nodisplay -script $ferret.jnl ${ifile} ${pvar} ${MODEL_RESOLUTION} ${exp} ${tfile}_burden ${ext}
			else
			 	# ferret plots for default journal file
				rm -f ${tfile}_burden.${ext} ${tfile}_burden_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1.jnl

				rm -f ${tfile}_zonal.${ext} ${tfile}_zonal_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1.jnl

				rm -f ${tfile}_meridional.${ext}  ${tfile}_meridional_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1.jnl

				rm -f ${tfile}_surface.${ext}     ${tfile}_surface_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1.jnl

				rm -f ${tfile}_utls.${ext}        ${tfile}_utls_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_utls_1x1.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_utls_1x1.jnl
			fi
					 
			# Create diff plots for all experiments except the reference
			if [ "${exp}" != "${ref_exp}" ]; then
				log "Creating difference plots: ${exp} - ${ref_exp}"
				rm -f ${tfile}_burden_diff.${ext} ${tfile}_burden_log_diff.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1_diff.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1_diff.jnl

				rm -f ${tfile}_zonal_diff.${ext}  ${tfile}_zonal_log_diff.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1_diff.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1_diff.jnl

				rm -f ${tfile}_meridional_diff.${ext} ${tfile}_meridional_log_diff.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1_diff.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1_diff.jnl

				rm -f ${tfile}_surface_diff.${ext} ${tfile}_surface_log_diff.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1_diff.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1_diff.jnl

				rm -f ${tfile}_utls_diff.${ext}   ${tfile}_utls_log_diff.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_utls_1x1_diff.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_utls_1x1_diff.jnl

#				files=("${tfile}" "${tfile}_log" "${tfile}_diff" "${tfile}_log_diff")
				files=("${tfile}_surface"    "${tfile}_surface_log"    "${tfile}_surface_diff"    "${tfile}_surface_log_diff"    \
				       "${tfile}_burden"     "${tfile}_burden_log"     "${tfile}_burden_diff"     "${tfile}_burden_log_diff"     \
				       "${tfile}_meridional" "${tfile}_meridional_log" "${tfile}_meridional_diff" "${tfile}_meridional_log_diff" \
				       "${tfile}_zonal"      "${tfile}_zonal_log"      "${tfile}_zonal_diff"      "${tfile}_zonal_log_diff"      \
				       "${tfile}_utls"       "${tfile}_utls_log"       "${tfile}_utls_diff"       "${tfile}_utls_log_diff"       \
				       )
			else
				log "Skipping difference plots for reference experiment: ${ref_exp}"
#				files=("${tfile}" "${tfile}_log")
#				files=("${tfile}" "${tfile}_log"  "${tfile}_zonal" "${tfile}_zonal_log" "${tfile}_meridional" "${tfile}_meridional_log" "${tfile}_surface" "${tfile}_surface_log" "${tfile}_utls" "${tfile}_utls_log")
				files=("${tfile}_surface"    "${tfile}_surface_log"       \
				       "${tfile}_burden"     "${tfile}_burden_log"        \
				       "${tfile}_meridional" "${tfile}_meridional_log"    \
				       "${tfile}_zonal"      "${tfile}_zonal_log"         \
				       "${tfile}_utls"       "${tfile}_utls_log"          \
				       )
			fi

			for file in "${files[@]}"; do
				file=$file.$ext
				if [ -f "${file}" ]; then
					log "success: ${file} generated"
					ls -lh "${file}"
					echo "${tpath}/${file}" >> "$texPlotsfile"
 					if [ "${myOS}" == "Darwin1" ] && [ "${pvar}" == "AW" ] ; then
						open "${file}"
					fi
				else
					log "error: ${file} not generated"
				fi
			done			
			else # ifile
				log "error: ${ifile} not found!"
			fi # ifile

		done # pvar
 	  done # ncvar
    done # name
done # exps
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
rm -f ${sorted_files}
touch ${sorted_files}

# Loop over each non-reference experiment to generate sorted file lists
for curr_exp in "${experiments[@]}"; do
  if [ "${curr_exp}" != "${ref_exp}" ]; then
    log "sort_files  "${QLTYPE}" "${curr_exp}" "${ref_exp}" "$texPlotsfile" "${ext}" "${hpath}""
         sort_files  "${QLTYPE}" "${curr_exp}" "${ref_exp}" "$texPlotsfile" "${ext}" "${hpath}"
    # Append this experiment's sorted list to the combined list
    exp_sorted_files="${hpath}/sorted_files_${script_name}.list"
    if [ -f "${exp_sorted_files}" ]; then
      cat "${exp_sorted_files}" >> "${sorted_files}.combined"
    fi
  fi
done

# Use the combined sorted file
mv "${sorted_files}.combined" "${sorted_files}"

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

pqlc="${parts[4]}"
pnml="${parts[5]}"
tlev="${parts[6]}"
pvar2="${parts[7]}"
pexp="${parts[8]}"
ptyp="${parts[9]}"
plog="${parts[10]}"
pdif="${parts[11]}"

if [[ "$pvar2" == *"-"* ]]; then
# echo "INFO: variable name '$pvar2' contains dash, display as underscore."
  pvar=$pvar2
# pvar=$(echo "$pvar2"  | sed 's/-/\_/g')
  pvar3=$(echo "$pvar2" | sed 's/-/\\_/g')
else
  pvar=$pvar2
  pvar3=$pvar2
fi
tvar="${ptyp}: ${pvar3} of ${pexp} vs ${ref_exp}"
for part in "${parts[@]}"; do
  if [ "${plog}" == "log" ] ; then
    tvar="${ptyp}: ${pvar3} of ${pexp} vs ${ref_exp} (log)"
  fi
  if [ "${plog}" == "diff" ]; then
    tvar="${ptyp}: ${pvar3} | diff of ${pexp}-${ref_exp}"
  fi
  if [ "${pdif}" == "diff" ]; then
    tvar="${ptyp}: ${pvar3} | diff of ${pexp}-${ref_exp} (log)"
  fi
done

GO="no"
if [ "${tlev}" == "sfc" ] && [ "${ptyp}" == "surface" ] ; then
  GO="GO"
fi
if [ "${tlev}" != "sfc" ] ; then
  GO="GO"
fi
#log "${GO} = GO | ${pexp} = ${pexp} vs ${ref_exp} | ${plog}"
# Generate TeX frame for each non-reference experiment (showing it vs reference)
if [ "${GO}" == "GO" ] && [ "${pexp}" != "${ref_exp}" ] && [ "${plog}" == "" ] ; then
plot1="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${pnml}_${tlev}_${pvar}_${pexp}_${ptyp}.${ext}"
plot2="$PLOTS_DIRECTORY/${ref_exp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${pnml}_${tlev}_${pvar}_${ref_exp}_${ptyp}.${ext}"
plot3="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${pnml}_${tlev}_${pvar}_${pexp}_${ptyp}_diff.${ext}"
plot4="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${pnml}_${tlev}_${pvar}_${pexp}_${ptyp}_log.${ext}"
plot5="$PLOTS_DIRECTORY/${ref_exp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${pnml}_${tlev}_${pvar}_${ref_exp}_${ptyp}_log.${ext}"
plot6="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${pnml}_${tlev}_${pvar}_${pexp}_${ptyp}_log_diff.${ext}"
cat >> ${texFile} <<EOF
%===============================================================================
\frame{
\frametitle{${MODEL_RESOLUTION} -- ${tvar} (${tlev})}
\vspace{0mm}
\centering
\begin{minipage}[t]{0.89\textwidth}
	\vspace{-2mm}
	\begin{figure}[H]
	\centering
		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 3mm  8mm, height=0.32\textheight, width=0.32\textwidth]{${plot1}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 3mm  8mm, height=0.32\textheight, width=0.32\textwidth]{${plot2}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 0mm  8mm, height=0.32\textheight, width=0.32\textwidth]{${plot3}} 

		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 3mm 28mm, height=0.32\textheight, width=0.32\textwidth]{${plot4}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 3mm 28mm, height=0.32\textheight, width=0.32\textwidth]{${plot5}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 0mm 28mm, height=0.32\textheight, width=0.32\textwidth]{${plot6}} 
%		\vspace{-10mm}\caption{. }
	\end{figure}
\end{minipage}
}
%===============================================================================
EOF
fi
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
