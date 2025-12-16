#!/bin/bash -e

# ============================================================================
# QLC C1-GLOB: Global 3D Analysis with PyFerret
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Processes global model plots using PyFerret, generating surface, burden,
#   zonal, meridional, and vertical range plots for specified variables.
#
# Key Features:
#   - Generates per-variable TeX files (e.g., texPlotfiles_qlc_C1-GLOB_NH3.tex)
#   - TeX and .list files stored in base directory (Plots/exp1-expN_dates/)
#   - Processes plots in predefined order
#   - Includes ALL plots matching first PLOTEXTENSION format
#
# Attribution:
#   PyFerret (NOAA/PMEL)
#   GitHub: https://github.com/NOAA-PMEL/PyFerret
#   Website: https://ferret.pmel.noaa.gov/Ferret/
#
# Usage:
#   Called automatically by qlc_main.sh - Do not call directly
#   For help: qlc -h
#
# Copyright (c) 2018-2025 ResearchConcepts io GmbH. All Rights Reserved.
# Questions/Comments: qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>
# ============================================================================

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="pyferret"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create Ferret plots for selected variables (to be defined in $CONFIG_FILE)              "
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

log "$0 ANALYSIS_DIRECTORY = $ANALYSIS_DIRECTORY"

# Intelligent module loading with fallback to venv/conda
log "Setting up PyFerret with intelligent module loading..."

# Setup PyFerret (integrated or dedicated)
if ! setup_pyferret_integrated; then
  log "Error: Failed to setup PyFerret" >&2
  exit 1
fi

# Setup CDO (Climate Data Operators) - needed for auto-scaling calculations
if ! setup_cdo; then
  log "Error: Failed to setup CDO" >&2
  exit 1
fi

log "Success: PyFerret configured"
log "PYFERRET: $PYFERRET_CMD"

# Display ferret environment variables if available
log "Checking ferret environment variables..."
if [ -n "${FER_DIR:-}" ] && [ -n "${FER_DSETS:-}" ]; then
    log "Ferret environment variables available:"
    log "  FER_DIR: ${FER_DIR}"
    log "  FER_DSETS: ${FER_DSETS}"
else
    log "Warning: Ferret environment variables not set (FER_DIR, FER_DSETS)"
    log "PyFerret may not work correctly without proper ferret environment"
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
# Parse command line arguments: <exp1> <expN> ... <expN> <start_date> <end_date> [config]
# ----------------------------------------------------------------------------------------
# Use common parsing function from qlc_common_functions.sh
# Sets: experiments (array), sDat, eDat, config_arg
parse_qlc_arguments "$@" || exit 1

# Early return if no experiments specified (obs-only mode)
# C1-GLOB only processes experiment data, not observations
if [ ${#experiments[@]} -eq 0 ]; then
    log "No experiments specified - skipping global analysis (obs-only mode)"
    log "End ${SCRIPT} at `date`"
    log "________________________________________________________________________________________"
    exit 0
fi

# Load variable registry for metadata access
load_variable_registry

# Generic experiment handling: last experiment is the reference
num_experiments=${#experiments[@]}
if [ $num_experiments -lt 1 ]; then
    log "Error: At least one experiment required"
    exit 1
fi

# Last experiment is the reference for difference plots
ref_exp="${experiments[$((num_experiments-1))]}"

# exp1 and expN are set by parse_qlc_arguments for convenience
# expN is empty when there's only one experiment (no diff plots needed)
if [ -n "$expN" ] && [ "$exp1" != "$expN" ]; then
    log "Reference experiment (for diff plots): $ref_exp"
    log "Will generate difference plots: exp vs $ref_exp"
else
    log "Single experiment mode: $exp1"
    log "Skipping difference plots (only one experiment)"
fi

# Parse EXP_LABELS if defined (comma-separated list matching experiments order)
# Otherwise use experiments array for labels
if [ -n "${EXP_LABELS:-}" ]; then
    IFS=',' read -ra exp_labels_array <<< "${EXP_LABELS}"
    # Trim whitespace from each label
    for i in "${!exp_labels_array[@]}"; do
        exp_labels_array[$i]=$(echo "${exp_labels_array[$i]}" | xargs)
    done
    # Ensure we have enough labels (pad with experiment names if needed)
    while [ ${#exp_labels_array[@]} -lt ${#experiments[@]} ]; do
        exp_labels_array+=("${experiments[${#exp_labels_array[@]}]}")
    done
    log "Using EXP_LABELS: ${exp_labels_array[*]}"
else
    # Use experiments array as labels
    exp_labels_array=("${experiments[@]}")
    log "Using experiments as labels: ${exp_labels_array[*]}"
fi

# Create experiment strings for different uses
experiments_comma=$(IFS=,;  echo "${experiments[*]}") # Comma-separated for JSON
experiments_hyphen=$(IFS=-; echo "${experiments[*]}") # Hyphen-separated for paths
# Note: exp1 and expN are already set by parse_qlc_arguments in common_functions
# exp1 = first experiment (or empty if no experiments)
# expN = reference experiment (last) for diff plots (or empty if only one experiment or no experiments)

sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# Parse plot format(s) from PLOTEXTENSION (can be comma-separated: "pdf,png")
if [ -n "$PLOTEXTENSION" ]; then
    # Convert comma-separated list to array for iteration
    IFS=',' read -ra PLOT_FORMATS <<< "$PLOTEXTENSION"
    # Trim whitespace from each format
    for i in "${!PLOT_FORMATS[@]}"; do
        PLOT_FORMATS[$i]=$(echo "${PLOT_FORMATS[$i]}" | xargs)
    done
else
    PLOT_FORMATS=("png")  # Default
fi
log "Plot formats configured: ${PLOT_FORMATS[*]}"

# Use first format for plot generation (backward compatibility)
ext="${PLOT_FORMATS[0]}"
# Use first format for TeX inclusion
tex_plot_format="${PLOT_FORMATS[0]}"
log "Using plot format for generation: ${ext}"
log "Using plot format for TeX: ${tex_plot_format}"

# Parse TEX_PLOTS_PER_PAGE configuration (controls multi-experiment plot layout)
# Options: 1, 2, 4, or 6 plots per TeX page (default: 6 for backward compatibility)
if [ -n "${TEX_PLOTS_PER_PAGE:-}" ]; then
    TEX_PLOTS_PER_PAGE=$(echo "${TEX_PLOTS_PER_PAGE}" | xargs)
    case "${TEX_PLOTS_PER_PAGE}" in
        1|2|4|6)
            log "TeX layout: ${TEX_PLOTS_PER_PAGE} plots per page"
            ;;
        *)
            log "Warning: Invalid TEX_PLOTS_PER_PAGE=${TEX_PLOTS_PER_PAGE}, using default (6)"
            TEX_PLOTS_PER_PAGE=6
            ;;
    esac
else
    TEX_PLOTS_PER_PAGE=6  # Default: all 6 plots on one page (backward compatible)
    log "TeX layout: ${TEX_PLOTS_PER_PAGE} plots per page (default)"
fi

# Set initial vertical range (will be updated dynamically per file based on levtype)
# Prefer PL_VRANGE (pressure levels) if defined, as it's more common in MARS retrievals
# The actual value will be correctly determined per-file based on detected levtype
if [ -n "${PL_VRANGE:-}" ]; then
	# Extract from PL_VRANGE config (pressure levels)
	ulev="$(echo "$PL_VRANGE" | cut -d',' -f1):$(echo "$PL_VRANGE" | cut -d',' -f2)"
	log "Initial vertical range from PL_VRANGE: $ulev (will be adjusted per file based on levtype)"
elif [ -n "${ML_VRANGE:-}" ]; then
	# Extract from ML_VRANGE config (model levels)
	ulev="$(echo "$ML_VRANGE" | cut -d',' -f1):$(echo "$ML_VRANGE" | cut -d',' -f2)"
	log "Initial vertical range from ML_VRANGE: $ulev (will be adjusted per file based on levtype)"
else
	# No vertical range defined - will rely on per-file detection
	ulev=""
	log "Warning: No vertical range defined (PL_VRANGE or ML_VRANGE)"
fi

hpath="$PLOTS_DIRECTORY/${experiments_hyphen}_${mDate}"

# Create help directory if not existent
if [  ! -d "$hpath" ]; then
  mkdir -p "$hpath"
fi

# Helper function: Generate TeX frame with 1 plot per page
generate_tex_frame_1plot() {
    local texfile="$1"
    local title="$2"
    local level="$3"
    local plot="$4"
    
    cat >> "${texfile}" <<EOF
%===============================================================================
\frame{
\frametitle{${MODEL_RESOLUTION} -- ${title} (${level})}
\vspace{0mm}
\centering
\begin{minipage}[t]{0.95\textwidth}
	\vspace{-2mm}
	\begin{figure}[H]
	\centering
		\includegraphics[angle=0,clip=true, trim=   0mm 0mm 0mm  0mm, height=0.75\textheight, width=0.75\textwidth]{${plot}} 
%		\vspace{-10mm}\caption{. }
	\end{figure}
\end{minipage}
}
%===============================================================================
EOF
}

# Helper function: Generate TeX frame with 2 plots per page (1x2 layout)
generate_tex_frame_2plots() {
    local texfile="$1"
    local title="$2"
    local level="$3"
    local plot1="$4"
    local plot2="$5"
    
    cat >> "${texfile}" <<EOF
%===============================================================================
\frame{
\frametitle{${MODEL_RESOLUTION} -- ${title} (${level})}
\vspace{0mm}
\centering
\begin{minipage}[t]{0.95\textwidth}
	\vspace{-2mm}
	\begin{figure}[H]
	\centering
		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 3mm  8mm, height=0.40\textheight, width=0.45\textwidth]{${plot1}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 0mm  8mm, height=0.40\textheight, width=0.45\textwidth]{${plot2}} 
%		\vspace{-10mm}\caption{. }
	\end{figure}
\end{minipage}
}
%===============================================================================
EOF
}

# Helper function: Generate TeX frame with 4 plots per page (2x2 layout)
generate_tex_frame_4plots() {
    local texfile="$1"
    local title="$2"
    local level="$3"
    local plot1="$4"
    local plot2="$5"
    local plot3="$6"
    local plot4="$7"
    
    cat >> "${texfile}" <<EOF
%===============================================================================
\frame{
\frametitle{${MODEL_RESOLUTION} -- ${title} (${level})}
\vspace{0mm}
\centering
\begin{minipage}[t]{0.95\textwidth}
	\vspace{-2mm}
	\begin{figure}[H]
	\centering
		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 3mm  8mm, height=0.40\textheight, width=0.45\textwidth]{${plot1}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 0mm  8mm, height=0.40\textheight, width=0.45\textwidth]{${plot2}} 

		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 4mm 29mm, height=0.40\textheight, width=0.45\textwidth]{${plot3}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 1mm 29mm, height=0.40\textheight, width=0.45\textwidth]{${plot4}} 
%		\vspace{-10mm}\caption{. }
	\end{figure}
\end{minipage}
}
%===============================================================================
EOF
}

# Helper function: Generate TeX frame with 6 plots per page (3x2 layout)
generate_tex_frame_6plots() {
    local texfile="$1"
    local title="$2"
    local level="$3"
    local plot1="$4"
    local plot2="$5"
    local plot3="$6"
    local plot4="$7"
    local plot5="$8"
    local plot6="$9"
    
    cat >> "${texfile}" <<EOF
%===============================================================================
\frame{
\frametitle{${MODEL_RESOLUTION} -- ${title} (${level})}
\vspace{0mm}
\centering
\begin{minipage}[t]{0.95\textwidth}
	\vspace{-2mm}
	\begin{figure}[H]
	\centering
		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 3mm  8mm, height=0.32\textheight, width=0.32\textwidth]{${plot1}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 3mm  8mm, height=0.32\textheight, width=0.32\textwidth]{${plot2}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 0mm  8mm, height=0.32\textheight, width=0.32\textwidth]{${plot3}} 

		\includegraphics[angle=0,clip=true, trim=   2mm 4mm 4mm 29mm, height=0.32\textheight, width=0.32\textwidth]{${plot4}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 4mm 29mm, height=0.32\textheight, width=0.32\textwidth]{${plot5}} 
		\includegraphics[angle=0,clip=true, trim=27.5mm 4mm 1mm 29mm, height=0.32\textheight, width=0.32\textwidth]{${plot6}} 
%		\vspace{-10mm}\caption{. }
	\end{figure}
\end{minipage}
}
%===============================================================================
EOF
}


# Clean up old per-variable TeX files
rm -f "${hpath}"/texPlotfiles_${QLTYPE}_*.tex
rm -f "${hpath}"/texPlotfiles_${QLTYPE}_*.list

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
	log "expN             : $expN"
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

	# New naming convention (v0.4.02+): find all *_tavg.nc files and extract variable info from filenames
	# Pattern: {exp}_{dates}_{levtype}_{myvar}_tavg.nc (matches output from B2-PREP)
	# Example: b2ro_20181201-20181221_pl_NH3_tavg.nc
	cd $ipath
	set +e
	all_tavg_files=($(ls ${exp}_${mDate}_*_tavg.nc 2>/dev/null))
	set -e
	
	log "Found ${#all_tavg_files[@]} time-averaged file(s) in directory"
	
	if [ ${#all_tavg_files[@]} -eq 0 ]; then
		log "No time-averaged files found in $ipath"
		log "Expected pattern: ${exp}_${mDate}_*_tavg.nc"
		continue
	fi
	
	# Get list of expected variables from MARS_RETRIEVALS configuration
	# Uses common function to expand variable specs (handles groups, individual vars)
	# Sets global array: expected_vars (format: levtype_myvar, e.g., pl_NH3, sfc_NH4_as)
	get_expected_variables_from_mars_retrievals
	
	# Extract just the variable names (myvar) from expected_vars for filtering
	# Convert "levtype_myvar" -> "myvar" (e.g., "pl_NH3" -> "NH3", "sfc_NH4_as" -> "NH4_as")
	selected_vars=()
	if [ ${#expected_vars[@]} -gt 0 ]; then
		for var_spec in "${expected_vars[@]}"; do
			# Extract myvar from levtype_myvar format
			levtype_part="${var_spec%%_*}"
			myvar_part="${var_spec#${levtype_part}_}"
			if [ -n "$myvar_part" ] && [ "$myvar_part" != "$var_spec" ]; then
				# Only add if not already in list
				if [[ ! " ${selected_vars[*]} " =~ " ${myvar_part} " ]]; then
					selected_vars+=("$myvar_part")
				fi
			fi
		done
	fi
	
	# If no variables selected from MARS_RETRIEVALS, log warning and process all files
	if [ ${#selected_vars[@]} -eq 0 ]; then
		log "Warning: No variables found in MARS_RETRIEVALS, processing all tavg files"
		tavg_files=("${all_tavg_files[@]}")
	else
		log "Selected variables from MARS_RETRIEVALS: ${selected_vars[*]}"
		
		# Filter tavg_files to only include selected variables
		tavg_files=()
		for tavg_file in "${all_tavg_files[@]}"; do
			# Extract variable name from filename
			# Pattern: {exp}_{dates}_{levtype}_{myvar}_tavg.nc
			basename_file=$(basename "$tavg_file" _tavg.nc)
			var_info="${basename_file#${exp}_${mDate}_}"
			levtype="${var_info%%_*}"
			# Extract myvar (everything after levtype_) - works even with underscores in variable name
			myvar_from_file="${var_info#${levtype}_}"
			
			# Check if this variable is in the selected list
			if [[ " ${selected_vars[*]} " =~ " ${myvar_from_file} " ]]; then
				tavg_files+=("$tavg_file")
				log "  Including: $tavg_file (variable: $myvar_from_file)"
			else
				log "  Skipping: $tavg_file (variable: $myvar_from_file not in selected list)"
			fi
		done
	fi
	
	log "Processing ${#tavg_files[@]} time-averaged file(s) for selected variables"
	
	if [ ${#tavg_files[@]} -eq 0 ]; then
		log "No time-averaged files found for selected variables"
		log "Selected variables: ${selected_vars[*]}"
		continue
	fi
	
	# Get experiment label for current experiment
	exp_label="${exp}"
	for i in "${!experiments[@]}"; do
		if [ "${experiments[$i]}" == "${exp}" ]; then
			exp_label="${exp_labels_array[$i]}"
			break
		fi
	done
	
	# Get reference experiment label
	ref_exp_label="${ref_exp}"
	for i in "${!experiments[@]}"; do
		if [ "${experiments[$i]}" == "${ref_exp}" ]; then
			ref_exp_label="${exp_labels_array[$i]}"
			break
		fi
	done
	
	# Process each time-averaged file
	for tavg_file in "${tavg_files[@]}"; do
		# Extract basename and remove _tavg.nc suffix
		basename_file=$(basename "$tavg_file" _tavg.nc)
		
		# Pattern: {exp}_{dates}_{levtype}_{myvar}_tavg.nc (from B2-PREP v0.4.02+)
		# Example: b2ro_20181201-20181221_pl_NH3_tavg.nc
		# Example with underscore: b2ro_20181201-20181221_sfc_NH4_as_tavg.nc
		# Remove exp and dates prefix to get: {levtype}_{myvar}
		var_info="${basename_file#${exp}_${mDate}_}"
		
		# Extract components from {levtype}_{myvar}
		# Extract levtype (first component before first underscore)
		levtype="${var_info%%_*}"
		# Extract myvar (everything after levtype_) - works even with underscores in variable name
		myvar_from_file="${var_info#${levtype}_}"
		
		log "Processing: $tavg_file"
		log "  levtype: $levtype"
		log "  myvar: $myvar_from_file"
		
		# Determine vertical range based on levtype
		# Parse format: "min,max,name" and convert to "min:max"
		if [ "$levtype" == "pl" ]; then
			# Pressure levels - use PL_VRANGE if defined
			if [ -n "${PL_VRANGE:-}" ]; then
				# Extract min,max from "min,max,name" format
				vrange_min=$(echo "$PL_VRANGE" | cut -d',' -f1)
				vrange_max=$(echo "$PL_VRANGE" | cut -d',' -f2)
				vrange_name=$(echo "$PL_VRANGE" | cut -d',' -f3)
				ulev="${vrange_min}:${vrange_max}"
				log "  Using PL_VRANGE: $ulev (${vrange_name}, from ${PL_VRANGE})"
			else
				log "  ERROR: PL_VRANGE not defined in config"
				exit 1
			fi
		elif [ "$levtype" == "ml" ]; then
			# Model levels - use ML_VRANGE if defined
			if [ -n "${ML_VRANGE:-}" ]; then
				# Extract min,max from "min,max,name" format
				vrange_min=$(echo "$ML_VRANGE" | cut -d',' -f1)
				vrange_max=$(echo "$ML_VRANGE" | cut -d',' -f2)
				vrange_name=$(echo "$ML_VRANGE" | cut -d',' -f3)
				ulev="${vrange_min}:${vrange_max}"
				log "  Using ML_VRANGE: $ulev (${vrange_name}, from ${ML_VRANGE})"
			else
				log "  ERROR: ML_VRANGE not defined in config"
				exit 1
			fi
		else
			# Surface or other levtype - use ML_VRANGE
			if [ -n "${ML_VRANGE:-}" ]; then
				vrange_min=$(echo "$ML_VRANGE" | cut -d',' -f1)
				vrange_max=$(echo "$ML_VRANGE" | cut -d',' -f2)
				vrange_name=$(echo "$ML_VRANGE" | cut -d',' -f3)
				ulev="${vrange_min}:${vrange_max}"
				log "  Using ML_VRANGE for levtype=$levtype: $ulev (${vrange_name})"
			else
				log "  ERROR: ML_VRANGE not defined in config"
				exit 1
			fi
		fi
		
		# Create lowercase version for consistent file naming
		vrange_name_lc=$(echo "$vrange_name" | tr '[:upper:]' '[:lower:]')
		
		# Determine PyFerret vertical coordinate specifier
		# For pressure levels: use Z= to select by coordinate value
		#   NetCDF files from MARS may have vertical coordinate in Pa (Pascals)
		#   PL_VRANGE is defined in hPa, so we need to convert: hPa * 100 = Pa
		# For model levels: use K= to select by index
		#   NetCDF files have vertical coordinate as model level indices (1-137 or 1-139)
		if [ "$levtype" == "pl" ]; then
			vcoord_spec="Z"
			# Convert hPa to Pa (multiply by 100)
			vrange_min_pa=$(echo "$vrange_min * 100" | bc)
			vrange_max_pa=$(echo "$vrange_max * 100" | bc)
			ulev="${vrange_min_pa}:${vrange_max_pa}"
			log "  PyFerret vertical coordinate: Z= (pressure level values)"
			log "  Converted range: ${vrange_min} hPa = ${vrange_min_pa} Pa, ${vrange_max} hPa = ${vrange_max_pa} Pa"
		else
			vcoord_spec="K"
			log "  PyFerret vertical coordinate: K= (model level indices)"
		fi
		
		# Build variable name for processing
		# Match file naming convention: levtype_myvar (e.g., sfc_NH4_as, pl_NH3)
		name="${levtype}_${myvar_from_file}"
		myvar_name="$myvar_from_file"
		pvars="${myvar_name}"
		
		log "name             : $name"
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
		  # Keep variable name with underscores (no conversion to dashes)
		  # Variable is at fixed position in filename, so underscores are fine
		  pvar2="$pvar"

		  log "j                : $j"
		  log "pvar             : ${pvar}"
		  log "myvar_from_file  : ${myvar_from_file}"

		  # Only process if pvar matches myvar_from_file from the filename
		  # This ensures files are only processed for the correct variable
		  # Note: For special cases like EQSAM4clim (EQdiag), pvars may contain sub-variables
		  # that are not in selected_vars but should still be processed
		  if [ "$pvar" != "$myvar_from_file" ]; then
		      log "Skipping: pvar ($pvar) doesn't match myvar_from_file ($myvar_from_file)"
		      continue
		  fi

	 		# New naming convention (v0.4.02+): file already identified as tavg_file
   		  	# Pattern: {exp}_{dates}_{levtype}_{myvar}_tavg.nc
   		  	cd $ipath
		  	ltype="_${levtype}"
  			cd $tpath

		# Construct file paths using new naming convention (v0.4.02+)
		# Pattern: {exp}_{dates}_{levtype}_{myvar}_tavg.nc
		ifile="$ipath/$tavg_file"
		# For diff plots: current experiment vs reference experiment
		ref_tavg_file="${ref_exp}_${mDate}_${levtype}_${myvar_from_file}_tavg.nc"
		ifile_current="$ANALYSIS_DIRECTORY/$exp/$tavg_file"
		ifile_ref="$ANALYSIS_DIRECTORY/$ref_exp/$ref_tavg_file"

			if [ -f "${ifile}" ]; then
			
			rm -f          ${pvar}.nc
			ln -s ${ifile} ${pvar}.nc
			
			nlev="`ncdump -h ${pvar}.nc | grep 'plev = ' | awk -F' ' '{print $3}'`"
			if [ "${nlev}" == "" ] ; then
				plev="0"
				surface_lev="0"
			else
				plev="${nlev}"
				# For surface plots: use last level for pl (surface is last in new file format)
				# For other levtypes, use appropriate surface level
				if [ "$levtype" == "pl" ]; then
					# Pressure levels: last level is surface (new file format: 10/50/.../1000)
					surface_lev="${nlev}"
				else
					# Model levels or other: use last level (typically surface)
					surface_lev="${nlev}"
				fi
			fi
			log "Model level array index ${plev} for: $pvar"
			log "Surface level index ${surface_lev} for: $pvar (levtype: $levtype)"

			# definition of plot files for each exp + variable (log, diff for exp1)
			# Pattern: {TEAM_PREFIX}_{experiments}_{dates}_{QLTYPE}_{levtype}_{variable}_{exp}
			# Variable name keeps underscores (e.g., NH4_as)
			tfile="${pfile}_${levtype}_${pvar2}_${exp}"

			log "${PLOTTYPE} plot for: $pvar - $tpath/$tfile.$ext"

			# ferret journal file variable definition
			var='`var`'
			pal='`pal`'
			lon='`lon`'
			lat='`lat`'
			lev='`lev`'
			tim='`tim`'
  			ulev="${ulev}"
			
			# Auto-determine scaling factors based on actual data
			# Goal: Scale values to ~0-100 range for better visualization
			log "Auto-determining scaling factors for ${pvar}..."
			
			# Function to calculate scaling factor from typical value
			calc_scale_factor() {
				local typical_val=$1
				# Calculate order of magnitude and return inverse as scaling factor
				# e.g., typical_val=1e-11 -> factor=1e11*
				
				# Use awk for all calculations to avoid bc portability issues
				# Written for compatibility with both BSD awk (macOS) and GNU awk (Linux)
				local result=$(echo "$typical_val" | awk '
{
	val = $1
	abs_val = (val < 0) ? -val : val
	
	if (abs_val < 1e-30 || abs_val == 0) {
		print "1*"
		exit
	}
	
	log_val = log(abs_val) / log(10)
	
	# Round to nearest integer
	e = log_val
	if (e < 0)
		e = e - 0.5
	else
		e = e + 0.5
	exp_val = int(e)
	
	# Target scale: bring to 0-100 range, so invert and add 2
	scale_exp = 0 - exp_val + 2
	
	# Ensure reasonable bounds
	if (scale_exp > 20) 
		scale_exp = 20
	if (scale_exp < -10) 
		scale_exp = -10
	
	print "1e" scale_exp "*"
}')
				
				echo "$result"
			}
			
			# Calculate typical values for different plot types using CDO
			# Use mean of absolute values for representative scaling
			
			# Surface plots: Single level (typically first/last level depending on levtype)
			if [ "$levtype" == "sfc" ]; then
				# Surface data - no vertical selection needed
				typical_S=$(cdo -s outputtab,nohead,value -fldmean -seltimestep,1 "${ipath}/${tavg_file}" 2>/dev/null | awk 'NR==1 {print $1; exit}')
			else
				# For 3D data, use appropriate surface level
				# For pressure levels: last level is surface (new file format: 10/50/.../1000, surface is last)
				# For model levels: last index (depending on model convention, often surface)
				if [ "$levtype" == "pl" ]; then
					# Pressure levels: last level is surface (new file format)
					# Use nlev (last level index) for surface plots
					if [ -n "${nlev}" ] && [ "${nlev}" != "0" ]; then
						typical_S=$(cdo -s outputtab,nohead,value -fldmean -seltimestep,1 -sellevidx,${nlev} "${ipath}/${tavg_file}" 2>/dev/null | awk 'NR==1 {print $1; exit}')
					else
						typical_S=$(cdo -s outputtab,nohead,value -fldmean -seltimestep,1 -sellevidx,1 "${ipath}/${tavg_file}" 2>/dev/null | awk 'NR==1 {print $1; exit}')
					fi
				else
					# Model levels: try last level (common convention for surface)
					if [ -n "${nlev}" ] && [ "${nlev}" != "0" ]; then
						typical_S=$(cdo -s outputtab,nohead,value -fldmean -seltimestep,1 -sellevidx,${nlev} "${ipath}/${tavg_file}" 2>/dev/null | awk 'NR==1 {print $1; exit}')
					else
						typical_S=$(cdo -s outputtab,nohead,value -fldmean -seltimestep,1 -sellevidx,1 "${ipath}/${tavg_file}" 2>/dev/null | awk 'NR==1 {print $1; exit}')
					fi
				fi
			fi
			# Fallback if CDO fails or returns empty
			if [ -z "$typical_S" ] || [ "$typical_S" == "" ]; then
				typical_S="1.0"
			fi
			facS=$(calc_scale_factor "$typical_S")
			
			# Skip vertical calculations for surface data
			if [ "$levtype" != "sfc" ]; then
				# Burden: Vertical sum (integrated column)
				typical_B=$(cdo -s outputtab,nohead,value -fldmean -vertsum -seltimestep,1 "${ipath}/${tavg_file}" 2>/dev/null | awk 'NR==1 {print $1; exit}')
				if [ -z "$typical_B" ] || [ "$typical_B" == "" ]; then
					typical_B="1.0"
				fi
				facB=$(calc_scale_factor "$typical_B")
				
				# Zonal average: Average over longitude (get mean across all vertical levels)
				typical_Z=$(cdo -s outputtab,nohead,value -timmean -fldmean -zonmean -seltimestep,1 "${ipath}/${tavg_file}" 2>/dev/null | awk '{s+=$1; n++} END {if(n>0) printf "%.6e", s/n; else print "1.0"}')
				if [ -z "$typical_Z" ] || [ "$typical_Z" == "" ]; then
					typical_Z="1.0"
				fi
				facZ=$(calc_scale_factor "$typical_Z")
				
				# Meridional average: Average over latitude (get mean across all vertical levels)
				typical_M=$(cdo -s outputtab,nohead,value -timmean -fldmean -mermean -seltimestep,1 "${ipath}/${tavg_file}" 2>/dev/null | awk '{s+=$1; n++} END {if(n>0) printf "%.6e", s/n; else print "1.0"}')
				if [ -z "$typical_M" ] || [ "$typical_M" == "" ]; then
					typical_M="1.0"
				fi
				facM=$(calc_scale_factor "$typical_M")
				
				# UTLS/vertical range: Subset of vertical levels
				if [ "$levtype" == "pl" ]; then
					# Pressure levels: select by coordinate value (in Pa)
					# Use vrange_min_pa and vrange_max_pa already computed above
					typical_U=$(cdo -s outputtab,nohead,value -fldmean -sellevel,${vrange_min_pa},${vrange_max_pa} -seltimestep,1 "${ipath}/${tavg_file}" 2>/dev/null | awk '{s+=$1; n++} END {if(n>0) printf "%.6e", s/n; else print "1.0"}')
				else
					# Model levels: select by index
					typical_U=$(cdo -s outputtab,nohead,value -fldmean -sellevidx,${vrange_min},${vrange_max} -seltimestep,1 "${ipath}/${tavg_file}" 2>/dev/null | awk '{s+=$1; n++} END {if(n>0) printf "%.6e", s/n; else print "1.0"}')
				fi
				if [ -z "$typical_U" ] || [ "$typical_U" == "" ]; then
					typical_U="1.0"
				fi
				facU=$(calc_scale_factor "$typical_U")
			else
				# For surface data, use same factor for all (only surface plots will be generated)
				facB="$facS"
				facZ="$facS"
				facM="$facS"
				facU="$facS"
			fi
# 			facS="1e11*"
# 			facB="1e10*"
# 			facZ="1e11*"
# 			facM="1e11*"
# 			facU="1e10*"
			
			log "  Scaling factors determined:"
			log "    Surface:     ${facS} (typical value: ${typical_S})"
			if [ "$levtype" != "sfc" ]; then
				log "    Burden:      ${facB} (typical value: ${typical_B})"
				log "    Zonal:       ${facZ} (typical value: ${typical_Z})"
				log "    Meridional:  ${facM} (typical value: ${typical_M})"
				log "    ${vrange_name}: ${facU} (typical value: ${typical_U})"
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

# Parse plot shading or fill format)
if [ -n "$PFILL" ]; then
    fill="$PFILL"
else
   #fill="shaded" # fill or shaded
    fill="fill"  # Default
fi
# Generate PyFerret scripts based on levtype
# Skip vertical structure scripts for surface data or single-level data
if [ "$levtype" != "sfc" ] && [ -n "${nlev}" ] && [ "${nlev}" -gt 1 ]; then
	log "Generating PyFerret scripts for vertical structure plots (nlev=${nlev})..."
	
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
${fill} ${pal} ${LEVELS1} /title="Burden: ${MODEL_RESOLUTION} - ${exp_label}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS1}                                                       (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_burden.$ext
  FRAME/file=${tfile}_burden.$ext
!SPAWN ls -l ${tfile}_burden.$ext
${fill} ${pal} ${LEVELS2}  /title="Burden: ${MODEL_RESOLUTION} - ${exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS2}                                                            (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_burden_log.$ext
  FRAME/file=${tfile}_burden_log.$ext
!SPAWN ls -l ${tfile}_burden_log.$ext
!SPAWN pwd
EOF

# Generate diff scripts only if multiple experiments (expN is not empty)
if [ -n "$expN" ] && [ "$exp1" != "$expN" ]; then
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
${fill} ${pal}  /title="Burden: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
!${CONTOUR}                                                                       (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_burden_diff.$ext
  FRAME/file=${tfile}_burden_diff.$ext
!SPAWN ls -l ${tfile}_burden_diff.$ext
${fill}  ${pal}  /title="Burden: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}                                                                             (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_burden_log_diff.$ext
  FRAME/file=${tfile}_burden_log_diff.$ext
!SPAWN ls -l ${tfile}_burden_log_diff.$ext
!SPAWN pwd
EOF
fi  # End of burden diff scripts generation (only for multiple experiments)

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
fill ${pal} ${LEVELS1} /title="Zonal avg: ${MODEL_RESOLUTION} - ${exp_label}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS1}                                                          (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_zonal.$ext
  FRAME/file=${tfile}_zonal.$ext
!SPAWN ls -l ${tfile}_zonal.$ext
fill ${pal} ${LEVELS2} /title="Zonal avg: ${MODEL_RESOLUTION} - ${exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS2}                                                              (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_zonal_log.$ext
  FRAME/file=${tfile}_zonal_log.$ext
!SPAWN ls -l ${tfile}_zonal_log.$ext
!SPAWN pwd
EOF

# Generate zonal diff scripts only if multiple experiments
if [ -n "$expN" ] && [ "$exp1" != "$expN" ]; then
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
fill  ${pal}  /title="Zonal avg: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
${CONTOUR}                                                                           (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_zonal_diff.$ext
  FRAME/file=${tfile}_zonal_diff.$ext
!SPAWN ls -l ${tfile}_zonal_diff.$ext
fill  ${pal}  /title="Zonal avg: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}                                                                                (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_zonal_log_diff.$ext
  FRAME/file=${tfile}_zonal_log_diff.$ext
!SPAWN ls -l ${tfile}_zonal_log_diff.$ext
!SPAWN pwd
EOF
fi  # End of zonal diff scripts generation

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
fill ${pal} ${LEVELS1} /title="Meridional avg: ${MODEL_RESOLUTION} - ${exp_label}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS1}                                                               (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_meridional.$ext
  FRAME/file=${tfile}_meridional.$ext
!SPAWN ls -l ${tfile}_meridional.$ext
fill ${pal} ${LEVELS2} /title="Meridional avg: ${MODEL_RESOLUTION} - ${exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}  ${LEVELS2}                                                                   (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_meridional_log.$ext
  FRAME/file=${tfile}_meridional_log.$ext
!SPAWN ls -l ${tfile}_meridional_log.$ext
!SPAWN pwd
EOF

# Generate meridional diff scripts only if multiple experiments
if [ -n "$expN" ] && [ "$exp1" != "$expN" ]; then
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
fill  ${pal}  /title="Meridional avg: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
${CONTOUR}                                                                                (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_meridional_diff.$ext
  FRAME/file=${tfile}_meridional_diff.$ext
!SPAWN ls -l ${tfile}_meridional_diff.$ext
fill  ${pal}  /title="Meridional avg: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
${CONTOUR}                                                                                     (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_meridional_log_diff.$ext
  FRAME/file=${tfile}_meridional_log_diff.$ext
!SPAWN ls -l ${tfile}_meridional_log_diff.$ext
!SPAWN pwd
EOF
fi  # End of meridional diff scripts generation

fi  # End of vertical structure scripts (burden, zonal, meridional)

######## surface plots ########
# Always generate surface plots (for all levtypes)
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
let lev="${surface_lev}"
let var="${facS}${pvar}"
${fill} ${pal} ${LEVELS1} /title="Surface: ${MODEL_RESOLUTION} - ${exp_label}: ${var}" (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS1}                                                        (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_surface.$ext
  FRAME/file=${tfile}_surface.$ext
!SPAWN ls -l ${tfile}_surface.$ext
${fill} ${pal} ${LEVELS2} /title="Surface: ${MODEL_RESOLUTION} - ${exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}  ${LEVELS2}                                                            (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_surface_log.$ext
  FRAME/file=${tfile}_surface_log.$ext
!SPAWN ls -l ${tfile}_surface_log.$ext
!SPAWN pwd
EOF

# Generate surface diff scripts only if multiple experiments
if [ -n "$expN" ] && [ "$exp1" != "$expN" ]; then
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
let lev="${surface_lev}"
let var="${facS}${pvar}"
${fill}  ${pal}  /title="Surface: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: ${var}" ${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}];go land
!${CONTOUR}                                                                         (${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_surface_diff.$ext
  FRAME/file=${tfile}_surface_diff.$ext
!SPAWN ls -l ${tfile}_surface_diff.$ext
${fill}  ${pal}  /title="Surface: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]);go land
!${CONTOUR}                                                                              (log(${var}[d=1,x=${lon},y=${lat},k=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},k=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_surface_log_diff.$ext
  FRAME/file=${tfile}_surface_log_diff.$ext
!SPAWN ls -l ${tfile}_surface_log_diff.$ext
!SPAWN pwd
EOF
fi  # End of surface diff scripts generation

# Generate vertical range plots only for data with vertical structure
if [ "$levtype" != "sfc" ] && [ -n "${nlev}" ] && [ "${nlev}" -gt 1 ]; then
	log "Generating PyFerret scripts for vertical range plots (${vrange_name}, nlev=${nlev})..."
	
######## Vertical range plots (${vrange_name}) ######## 
FERRETMEMSIZE="500"
cat > ${tfile}_${vrange_name_lc}_1x1.jnl <<EOF
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
${fill} ${pal} ${LEVELS1} /title="${vrange_name}: ${MODEL_RESOLUTION} - ${exp_label}: ${var}" (${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]);go land
!${CONTOUR} ${LEVELS1}                                                     (${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_${vrange_name_lc}.$ext
  FRAME/file=${tfile}_${vrange_name_lc}.$ext
!SPAWN ls -l ${tfile}_${vrange_name_lc}.$ext
${fill} ${pal} ${LEVELS3} /title="${vrange_name}: ${MODEL_RESOLUTION} - ${exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]);go land
!${CONTOUR} ${LEVELS3}                                                         (log(${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_${vrange_name_lc}_log.$ext
  FRAME/file=${tfile}_${vrange_name_lc}_log.$ext
!SPAWN ls -l ${tfile}_${vrange_name_lc}_log.$ext
!SPAWN pwd
EOF

# Generate vertical range diff scripts only if multiple experiments
if [ -n "$expN" ] && [ "$exp1" != "$expN" ]; then
cat > ${tfile}_${vrange_name_lc}_1x1_diff.jnl <<EOF
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
${fill}  ${pal}  /title="${vrange_name}: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: ${var}" ${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}];go land
!${CONTOUR}                                                                     (${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}])
! FRAME/TRANSPARENT/file=${tfile}_${vrange_name_lc}_diff.$ext
  FRAME/file=${tfile}_${vrange_name_lc}_diff.$ext
!SPAWN ls -l ${tfile}_${vrange_name_lc}_diff.$ext
${fill}  ${pal}  /title="${vrange_name}: ${MODEL_RESOLUTION} - Diff: ${exp_label}-${ref_exp_label}: log(${var})" log(${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]);go land
!${CONTOUR}                                                                          (log(${var}[d=1,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]-${var}[d=2,x=${lon},y=${lat},${vcoord_spec}=${lev},l=${tim}]))
! FRAME/TRANSPARENT/file=${tfile}_${vrange_name_lc}_log_diff.$ext
  FRAME/file=${tfile}_${vrange_name_lc}_log_diff.$ext
!SPAWN ls -l ${tfile}_${vrange_name_lc}_log_diff.$ext
!SPAWN pwd
EOF
fi  # End of vertical range diff scripts generation

fi  # End of vertical range scripts

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
				
				# Skip vertical plots for surface data or single-level data
				if [ "$levtype" != "sfc" ] && [ -n "${nlev}" ] && [ "${nlev}" -gt 1 ]; then
					log "Creating vertical structure plots (burden, zonal, meridional, ${vrange_name}, nlev=${nlev})..."
					
					rm -f ${tfile}_burden.${ext} ${tfile}_burden_log.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1.jnl

					rm -f ${tfile}_zonal.${ext} ${tfile}_zonal_log.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1.jnl

					rm -f ${tfile}_meridional.${ext}  ${tfile}_meridional_log.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1.jnl

					rm -f ${tfile}_${vrange_name_lc}.${ext}        ${tfile}_${vrange_name_lc}_log.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_${vrange_name_lc}_1x1.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_${vrange_name_lc}_1x1.jnl
				else
					log "Skipping vertical structure plots for surface or single-level data (levtype=$levtype, nlev=${nlev:-0})"
				fi
				
				# Always create surface plots
				rm -f ${tfile}_surface.${ext}     ${tfile}_surface_log.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1.jnl
			fi
					 
			# Create diff plots for all experiments except the reference
			# Skip diff plots if only one experiment (expN is empty)
			if [ -n "$expN" ] && [ "${exp}" != "${ref_exp}" ]; then
				log "Creating difference plots: ${exp} - ${ref_exp}"
				
				# Skip vertical diff plots for surface or single-level data
				if [ "$levtype" != "sfc" ] && [ -n "${nlev}" ] && [ "${nlev}" -gt 1 ]; then
					log "Creating vertical structure difference plots (nlev=${nlev})..."
					
					rm -f ${tfile}_burden_diff.${ext} ${tfile}_burden_log_diff.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1_diff.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_burden_1x1_diff.jnl

					rm -f ${tfile}_zonal_diff.${ext}  ${tfile}_zonal_log_diff.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1_diff.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_zonal_1x1_diff.jnl

					rm -f ${tfile}_meridional_diff.${ext} ${tfile}_meridional_log_diff.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1_diff.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_meridional_1x1_diff.jnl

					rm -f ${tfile}_${vrange_name_lc}_diff.${ext}   ${tfile}_${vrange_name_lc}_log_diff.${ext}
					log "$PYFERRET_CMD -nodisplay -script  ${tfile}_${vrange_name_lc}_1x1_diff.jnl"
						 $PYFERRET_CMD -nodisplay -script  ${tfile}_${vrange_name_lc}_1x1_diff.jnl
				else
					log "Skipping vertical structure difference plots for surface or single-level data (levtype=$levtype, nlev=${nlev:-0})"
				fi
				
				# Always create surface diff plots
				rm -f ${tfile}_surface_diff.${ext} ${tfile}_surface_log_diff.${ext}
				log "$PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1_diff.jnl"
					 $PYFERRET_CMD -nodisplay -script  ${tfile}_surface_1x1_diff.jnl

#				files=("${tfile}" "${tfile}_log" "${tfile}_diff" "${tfile}_log_diff")
				# Build file list based on levtype and number of levels
				if [ "$levtype" != "sfc" ] && [ -n "${nlev}" ] && [ "${nlev}" -gt 1 ]; then
					# Include all plots for data with vertical structure
					files=("${tfile}_surface"    "${tfile}_surface_log"    "${tfile}_surface_diff"    "${tfile}_surface_log_diff"    \
					       "${tfile}_burden"     "${tfile}_burden_log"     "${tfile}_burden_diff"     "${tfile}_burden_log_diff"     \
					       "${tfile}_meridional" "${tfile}_meridional_log" "${tfile}_meridional_diff" "${tfile}_meridional_log_diff" \
					       "${tfile}_zonal"      "${tfile}_zonal_log"      "${tfile}_zonal_diff"      "${tfile}_zonal_log_diff"      \
					       "${tfile}_${vrange_name_lc}"       "${tfile}_${vrange_name_lc}_log"       "${tfile}_${vrange_name_lc}_diff"       "${tfile}_${vrange_name_lc}_log_diff"       \
					       )
				else
					# Only surface plots for surface or single-level data
					files=("${tfile}_surface"    "${tfile}_surface_log"    "${tfile}_surface_diff"    "${tfile}_surface_log_diff"    \
					       )
				fi
			else
				log "Skipping difference plots for reference experiment: ${ref_exp}"
#				files=("${tfile}" "${tfile}_log")
#				files=("${tfile}" "${tfile}_log"  "${tfile}_zonal" "${tfile}_zonal_log" "${tfile}_meridional" "${tfile}_meridional_log" "${tfile}_surface" "${tfile}_surface_log" "${tfile}_${vrange_name_lc}" "${tfile}_${vrange_name_lc}_log")
				# Build file list based on levtype and number of levels
				if [ "$levtype" != "sfc" ] && [ -n "${nlev}" ] && [ "${nlev}" -gt 1 ]; then
					# Include all plots for data with vertical structure
					files=("${tfile}_surface"    "${tfile}_surface_log"       \
					       "${tfile}_burden"     "${tfile}_burden_log"        \
					       "${tfile}_meridional" "${tfile}_meridional_log"    \
					       "${tfile}_zonal"      "${tfile}_zonal_log"         \
					       "${tfile}_${vrange_name_lc}"       "${tfile}_${vrange_name_lc}_log"          \
					       )
				else
					# Only surface plots for surface or single-level data
					files=("${tfile}_surface"    "${tfile}_surface_log"       \
					       )
				fi
			fi

			for file in "${files[@]}"; do
				file=$file.$ext
				if [ -f "${file}" ]; then
					log "success: ${file} generated"
					ls -lh "${file}"
					# Track plots per variable (use name as key, which includes levtype_myvar format)
					# This matches MARS_RETRIEVALS format (e.g., pl_NH3, sfc_NH4_as)
					var_plot_list="${hpath}/texPlotfiles_${QLTYPE}_${name}.list"
					if [ ! -f "$var_plot_list" ]; then
						touch "$var_plot_list"
					fi
					# Only add plots of the first format to TeX lists
					if [[ "$file" == *".${tex_plot_format}" ]]; then
						echo "${tpath}/${file}" >> "$var_plot_list"
					fi
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

		done # pvar (j loop)
	done # tavg_file loop
done # exps
log  "----------------------------------------------------------------------------------------"
log "Generating per-variable TeX files"

tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')

# Find all per-variable plot lists
var_plot_lists=($(find "${hpath}" -maxdepth 1 -type f -name "texPlotfiles_${QLTYPE}_*.list" | sort))

if [ ${#var_plot_lists[@]} -eq 0 ]; then
    log "Warning: No per-variable plot lists found"
    log "  Looking in: ${hpath}"
    log "  Pattern: texPlotfiles_${QLTYPE}_*.list"
else
    log "Found ${#var_plot_lists[@]} variable(s) to process"
    
    # Generate per-variable TeX files
    for var_plot_list in "${var_plot_lists[@]}"; do
        # Extract variable name from filename: texPlotfiles_qlc_C1-GLOB_VAR.list -> VAR
        var_tex_basename=$(basename "$var_plot_list" .list)
        varname="${var_tex_basename#texPlotfiles_${QLTYPE}_}"
        var_texfile="${hpath}/${var_tex_basename}.tex"
        
        log "Processing variable: ${varname}"
        
        # Generate sorted file list for this variable
        sorted_files="${hpath}/sorted_files_${script_name}_${varname}.list"
        rm -f ${sorted_files}
        touch ${sorted_files}
        
        # Loop over experiments to generate sorted file lists
        # In single-experiment mode: process that experiment
        # In multi-experiment mode with N experiments:
        #   - exp1, exp2, ..., exp(N-1): sort their files + reference files + diff files
        #   - expN (reference): skip (already included in other experiments' sorts)
        for curr_exp in "${experiments[@]}"; do
            # Skip reference experiment in multi-experiment mode
            # (its files are already sorted and included by non-reference experiments)
            if [ -n "$expN" ] && [ "$curr_exp" == "$ref_exp" ]; then
                log "Skipping reference experiment ${ref_exp} (already included in sorted lists)"
                continue
            fi
            
            log "sort_files  "${QLTYPE}" "${curr_exp}" "${ref_exp}" "$var_plot_list" "${tex_plot_format}" "${hpath}" "${varname}""
            sort_files  "${QLTYPE}" "${curr_exp}" "${ref_exp}" "$var_plot_list" "${tex_plot_format}" "${hpath}" "${varname}"
            # Append this experiment's sorted list to the combined list
            # sort_files creates a per-experiment file: sorted_files_${script_name}_${varname}_${curr_exp}.list
            exp_sorted_files="${hpath}/sorted_files_${script_name}_${varname}_${curr_exp}.list"
            if [ -f "${exp_sorted_files}" ]; then
                cat "${exp_sorted_files}" >> "${sorted_files}"
                # Clean up the per-experiment sorted file (it's now merged into the per-variable file)
                rm -f "${exp_sorted_files}"
            fi
        done
        
        # Generate TeX file for this variable
        rm -f "${var_texfile}"
        # For section/subsection titles, escape underscores for LaTeX but don't use full formatting
        # (format_var_name_tex adds subscripts which we skip in titles)
#       varname_title=$(echo "${varname}" | sed 's/_/\ /g')
#       varname_title=$(echo "${varname}" | sed 's/_/\\_/g')
#       var_title=$(echo "${varname}" | sed 's/_/\ /g' | awk '{printf $2}')

        if [ -n "$varname" ]; then
            # Extract variable part from varname (everything after first underscore)
            var_part="${varname#*_}"
            if [ -n "$var_part" ] && [ "$var_part" != "$varname" ]; then
                var_title=$var_part
            else
                var_title=$varname
            fi
        fi
        varname_title=$(format_var_name_tex "${var_title}")

        cat > "${var_texfile}" <<EOF
%===============================================================================
\section{Global Analysis}
\subsection{${varname_title} --  ${mDate} (mean)}
EOF
#\subsection{${varname_title} -- ${mDate} (mean)}
        
        tfiles="`cat ${sorted_files} 2>/dev/null`"
        num_plots=$(echo "$tfiles" | grep -v '^$' | wc -l | xargs)
        log "  Processing ${varname}: ${num_plots} plots"
        
        if [ -z "$tfiles" ] || [ "$num_plots" -eq 0 ]; then
            log "  Warning: No plots found for ${varname}, skipping TeX generation"
            continue
        fi
        
        for plot in ${tfiles}; do
            if [ -z "$plot" ]; then
                continue  # Skip empty lines
            fi
            file_name=${plot}
            # Extract the file name without directory and extension
            file_name="${file_name##*/}"  # Remove directory path
            file_name="${file_name%.*}"   # Remove extension
            
            # Filename structure: {TEAM_PREFIX}_{experiments_hyphen}_{mDate}_{QLTYPE}_{levtype}_{variable}_{exp}_{plottype}[_{log}][_{diff}]
            # Example: CAMS_b2ro-b2rn_20181201-20181221_qlc_C1-GLOB_pl_NH3_b2ro_surface
            # Example with underscore in variable: CAMS_b2ro-b2rn_20181201-20181221_qlc_C1-GLOB_pl_NH4_as_b2ro_surface
            # For variables with underscores, temporarily replace them with dashes for parsing
            # varname is like "pl_NH3" or "sfc_NH4_as" - extract just the variable part (after first underscore)
            file_name_for_parsing="$file_name"
            if [ -n "$varname" ]; then
                # Extract variable part from varname (everything after first underscore)
                var_part="${varname#*_}"
                if [ -n "$var_part" ] && [ "$var_part" != "$varname" ]; then
                    # Convert underscores in variable part to dashes for parsing
                    var_part_dash=$(var_name_for_parsing "$var_part")
                    # Replace only the variable part in filename (not the full varname)
                    file_name_for_parsing="${file_name//${var_part}/${var_part_dash}}"
                fi
            fi
            
            # Split the file name into parts (using modified version for parsing)
            IFS="_" read -ra parts <<< "$file_name_for_parsing"
            
            # Known from config/context:
            # - QLTYPE: known (script name)
            # - levtype: parts[5] (known position)
            # - variable: known from loop context (varname)
            # - experiment: need to find (one of experiments array)
            # - plot type: need to extract (created by C1, depends on what was generated)
            # - optional suffixes: log, diff (need to extract)
            
            tlev="${parts[5]}"              # levtype (pl, sfc, etc.) - known position
            
            # Find experiment name in filename (needed to locate plot type)
            # Variable name is now a single part (with dashes), so experiment is easier to find
            exp_idx=-1
            for i in "${!parts[@]}"; do
                if [ $i -le 5 ]; then
                    continue  # Skip prefix parts (before levtype)
                fi
                # Check if this part matches any experiment name
                for exp_name in "${experiments[@]}"; do
                    if [ "${parts[$i]}" == "$exp_name" ]; then
                        exp_idx=$i
                        break 2
                    fi
                done
            done
            
            # Extract plot type and optional suffixes (only unknowns from filename)
            if [ $exp_idx -ge 0 ]; then
                pexp="${parts[$exp_idx]}"              # experiment (known from config, but need to identify which one)
                ptyp="${parts[$((exp_idx+1))]:-}"      # plot type (surface, burden, zonal, meridional, etc.) - created by C1
                plog="${parts[$((exp_idx+2))]:-}"      # log suffix (optional)
                pdif="${parts[$((exp_idx+3))]:-}"      # diff suffix (optional)
            else
                # Fallback: assume standard positions (shouldn't happen if filenames are correct)
                log "Warning: Could not find experiment in filename: $file_name"
                pexp="${parts[7]:-}"
                ptyp="${parts[8]:-}"
                plog="${parts[9]:-}"
                pdif="${parts[10]:-}"
            fi
            
            # Extract variable name from filename (between levtype at parts[5] and experiment at exp_idx)
            # The variable name in the filename is at parts[6] (may be split if variable has underscores)
            # Convert dashes back to underscores to get the actual variable name
            if [ $exp_idx -ge 0 ] && [ $exp_idx -gt 6 ]; then
                # Variable name spans from parts[6] to parts[exp_idx-1]
                # Join them with underscores and convert dashes back to underscores
                var_parts=("${parts[@]:6:$((exp_idx-6))}")
                pvar=$(IFS=_; echo "${var_parts[*]}")
                # Convert dashes back to underscores (they were converted for parsing)
                pvar="${pvar//-/_}"
            elif [ $exp_idx -ge 0 ] && [ $exp_idx -eq 6 ]; then
                # Variable is a single part at parts[6]
                pvar="${parts[6]}"
                # Convert dash back to underscore if it was converted
                pvar="${pvar//-/_}"
            else
                # Fallback: extract just the variable part from varname (without levtype)
                # varname is like "pl_NH3" or "sfc_NH4_as", extract the part after first underscore
                pvar="${varname#*_}"
            fi
            
            # Use known values from config/context
            pnml="${varname}"                # variable name (known from MARS_RETRIEVALS config)
#           pvar2=$(echo "${pvar}" | sed 's/_/\\ /g')  # variable name for TeX display (keeps underscores, e.g., NH4_as)
#           pvar2=$(echo "${pvar}" | sed 's/_/\\ /g')  # variable name for TeX display (keeps underscores, e.g., NH4_as)
            
            # format_var_name_tex already escapes underscores, so don't escape them manually
            pvar3=$(format_var_name_tex "$pvar")
            
            # Get experiment labels (use EXP_LABELS if available, else use experiment names)
            pexp_label="${pexp}"
            ref_exp_label="${ref_exp}"
            for i in "${!experiments[@]}"; do
                if [ "${experiments[$i]}" == "${pexp}" ]; then
                    pexp_label="${exp_labels_array[$i]}"
                fi
                if [ "${experiments[$i]}" == "${ref_exp}" ]; then
                    ref_exp_label="${exp_labels_array[$i]}"
                fi
            done
            # Escape underscores in experiment labels for TeX
            pexp_label=$(echo "${pexp_label}" | sed 's/_/\\_/g')
            ref_exp_label=$(echo "${ref_exp_label}" | sed 's/_/\\_/g')
            
            tvar="${ptyp}: ${pvar3} of ${pexp_label} vs ${ref_exp_label}"
            for part in "${parts[@]}"; do
                if [ "${plog}" == "log" ] ; then
                    tvar="${ptyp}: ${pvar3} of ${pexp_label} vs ${ref_exp_label} (log)"
                fi
                if [ "${plog}" == "diff" ]; then
                    tvar="${ptyp}: ${pvar3} | diff of ${pexp_label}-${ref_exp_label}"
                fi
                if [ "${pdif}" == "diff" ]; then
                    tvar="${ptyp}: ${pvar3} | diff of ${pexp_label}-${ref_exp_label} (log)"
                fi
            done
            
            GO="no"
            if [ "${tlev}" == "sfc" ] && [ "${ptyp}" == "surface" ] ; then
                GO="GO"
            fi
            if [ "${tlev}" != "sfc" ] ; then
                GO="GO"
            fi
            
            # Generate TeX frame
            # Single-experiment mode: show only that experiment's plots (simpler layout)
            # Multi-experiment mode: show experiment vs reference (comparison layout)
            # Filename structure: {TEAM_PREFIX}_{experiments_hyphen}_{mDate}_{QLTYPE}_{tlev}_${pvar}_${pexp}_${ptyp}[_log][_diff].${tex_plot_format}
            if [ "${GO}" == "GO" ]; then
                # Check if this is single-experiment or multi-experiment mode
                if [ -z "$expN" ]; then
                    # Single-experiment mode: one frame per plot (loop through all plots)
                    # Current plot file is being processed in the outer loop
                    plot_file="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${pexp}_${ptyp}"
                    if [ -n "${plog}" ]; then
                        plot_file="${plot_file}_${plog}"
                    fi
                    if [ -n "${pdif}" ]; then
                        plot_file="${plot_file}_${pdif}"
                    fi
                    plot_file="${plot_file}.${tex_plot_format}"
                    
                    # Generate single-plot frame using helper function
                    generate_tex_frame_1plot "${var_texfile}" "${tvar}" "${tlev}" "${plot_file}"
                elif [ "${pexp}" != "${ref_exp}" ] && [ "${plog}" == "" ]; then
                    # Multi-experiment mode: flexible comparison layout based on TEX_PLOTS_PER_PAGE
                    # Only trigger on base plots (no _log suffix) to avoid duplicates
                    # Collect all 6 plot files
                    plot1="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${pexp}_${ptyp}.${tex_plot_format}"
                    plot2="$PLOTS_DIRECTORY/${ref_exp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${ref_exp}_${ptyp}.${tex_plot_format}"
                    plot3="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${pexp}_${ptyp}_diff.${tex_plot_format}"
                    plot4="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${pexp}_${ptyp}_log.${tex_plot_format}"
                    plot5="$PLOTS_DIRECTORY/${ref_exp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${ref_exp}_${ptyp}_log.${tex_plot_format}"
                    plot6="$PLOTS_DIRECTORY/${pexp}/${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${tlev}_${pvar}_${pexp}_${ptyp}_log_diff.${tex_plot_format}"
                    
                    # Generate TeX frames based on configured layout
                    case "${TEX_PLOTS_PER_PAGE}" in
                        1)
                            # One plot per page (6 separate frames)
                            generate_tex_frame_1plot "${var_texfile}" "${tvar}" "${tlev}" "${plot1}"
                            generate_tex_frame_1plot "${var_texfile}" "${tvar} (ref)" "${tlev}" "${plot2}"
                            generate_tex_frame_1plot "${var_texfile}" "${tvar} (diff)" "${tlev}" "${plot3}"
                            generate_tex_frame_1plot "${var_texfile}" "${tvar} (log)" "${tlev}" "${plot4}"
                            generate_tex_frame_1plot "${var_texfile}" "${tvar} (ref log)" "${tlev}" "${plot5}"
                            generate_tex_frame_1plot "${var_texfile}" "${tvar} (log diff)" "${tlev}" "${plot6}"
                            ;;
                        2)
                            # Two plots per page (3 frames)
                            generate_tex_frame_2plots "${var_texfile}" "${tvar}" "${tlev}" "${plot1}" "${plot2}"
                            generate_tex_frame_2plots "${var_texfile}" "${tvar} (log)" "${tlev}" "${plot4}" "${plot5}"
                            generate_tex_frame_2plots "${var_texfile}" "${tvar} (diff)" "${tlev}" "${plot3}" "${plot6}"
                            ;;
                        4)
                            # Four plots per page (2 frames: 4 plots + 2 plots)
                            generate_tex_frame_4plots "${var_texfile}" "${tvar}" "${tlev}" "${plot1}" "${plot2}" "${plot4}" "${plot5}"
                            generate_tex_frame_2plots "${var_texfile}" "${tvar} (diff)" "${tlev}" "${plot3}" "${plot6}"
                            ;;
                        6)
                            # Six plots per page (1 frame) - original layout
                            generate_tex_frame_6plots "${var_texfile}" "${tvar}" "${tlev}" "${plot1}" "${plot2}" "${plot3}" "${plot4}" "${plot5}" "${plot6}"
                            ;;
                        *)
                            # Fallback to 6-plot layout
                            generate_tex_frame_6plots "${var_texfile}" "${tvar}" "${tlev}" "${plot1}" "${plot2}" "${plot3}" "${plot4}" "${plot5}" "${plot6}"
                            ;;
                    esac
                fi  # End of single vs multi-experiment TeX generation
            fi  # End of GO check
        done # plot
        
        log "Generated per-variable TeX file: ${var_texfile}"
    done # var_plot_list
    
    log  "----------------------------------------------------------------------------------------"
    log "Per-variable TeX file generation complete"
    log  "----------------------------------------------------------------------------------------"
fi
log "$ipath"
log "$tpath"
log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
