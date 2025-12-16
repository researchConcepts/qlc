#!/bin/bash -e

# ============================================================================
# QLC Z1-XPDF: TeX/PDF Report Generation
# ============================================================================
# Part of QLC (Quick Look Content) v1.0.1-beta
# An Automated Model-Observation Comparison Suite Optimized for CAMS
#
# Documentation:
#   https://docs.researchconcepts.io/qlc/latest/
#
# Description:
#   Generates publication-quality PDF reports from TeX files created by
#   previous workflow steps. Uses XeLaTeX/pdfLaTeX with intelligent module
#   loading and fallback support. Compiles all generated plots into
#   comprehensive analysis reports.
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

CUSR="`echo $USER`"
PLOTTYPE="pdftex"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "----------------------------------------------------------------------------------------"

# Loop through and process the parameters received
for param in "$@"; do
  log "Subscript $0 received parameter: $param"
done

log "$0 TEX_DIRECTORY = ${TEX_DIRECTORY}"
pwd -P

# Intelligent module loading with fallback to venv/conda
log "Setting up PDF conversion with intelligent module loading..."

# Setup PDF converter (XeLaTeX - cross-platform LaTeX)
if ! setup_pdf_converter; then
  log "Error: Failed to setup PDF converter" >&2
  exit 1
fi

log "Success: PDF converter configured"
log "PDF converter: ${PDF_CONVERTER}"

# get script name without path and extension
script_name="${SCRIPT##*/}"     # Remove directory path
script_name="${script_name%.*}" # Remove extension
QLTYPE="$script_name"           # qlc script type
base_name="${QLTYPE%_*}"        # Remove subscript
CDATE="20`date +"%y%m%d%H"`"    # pdf creation date
CDATE="20`date +"%y%m%d%H%M"`"  # pdf creation date
ext="$PLOTEXTENSION"            # embedded plot type

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# Experiments come first, followed by dates in YYYY-MM-DD format, optional config at end
# ----------------------------------------------------------------------------------------
parse_qlc_arguments "$@" || exit 1

# Create experiment strings for different uses
experiments_comma=$(IFS=,; echo "${experiments[*]}")  # Comma-separated for JSON
experiments_hyphen=$(IFS=-; echo "${experiments[*]}") # Hyphen-separated for paths
exp1="${experiments[0]}" # Keep exp1 for backward compatibility in some operations

# Process dates
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"

# definition of tex file name
pfile="${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${QLTYPE}_${CDATE}"
log "pfile base name  : $pfile"

tpath="${TEX_DIRECTORY}/${pfile}"
hpath="$PLOTS_DIRECTORY/${experiments_hyphen}_${mDate}"

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
log "TEAM_PREFIX      : ${TEAM_PREFIX}"
log "EVALUATION_PREFIX: ${EVALUATION_PREFIX}"
log "MODEL_RESOLUTION : ${MODEL_RESOLUTION}"
log "TIME_RESOLUTION  : ${TIME_RESOLUTION}"
log "mDate            : $mDate"
log "ext              : $ext"
log "experiments      : ${experiments[*]}"
log "USER             : $CUSR"
log "DATE             : $CDATE"

cd ${tpath}/tex
pwd -P


rm -f texPlotfiles.tex
touch texPlotfiles.tex

log  "----------------------------------------------------------------------------------------"

# Check if only Z1-XPDF is in SUBSCRIPT_NAMES (collect all TeX files)
# Otherwise, collect only TeX files for specified scripts
only_z1=false
if [ ${#SUBSCRIPT_NAMES[@]} -eq 1 ] && [[ "${SUBSCRIPT_NAMES[0]}" == "Z1-XPDF" ]]; then
	only_z1=true
	log "Only Z1-XPDF specified: collecting ALL texPlotfiles_*.tex files in ${hpath}"
	
	# Collect all TeX files (both per-variable and legacy single files)
	all_tex_files=($(find "${hpath}" -maxdepth 1 -type f -name "texPlotfiles_*.tex" | sort))
	
		if [ ${#all_tex_files[@]} -gt 0 ]; then
			log "Found ${#all_tex_files[@]} TeX files"
			
			# Check if these are per-variable files (contain underscore after QLTYPE)
			# Pattern: texPlotfiles_qlc_*-*_*.tex indicates per-variable files
			per_var_detected=false
			for tex_file in "${all_tex_files[@]}"; do
				tex_basename=$(basename "${tex_file}" .tex)
				if [[ "${tex_basename}" =~ texPlotfiles_qlc_[^-]+-[^-]+_.+ ]]; then
					per_var_detected=true
					break
				fi
			done
			
			# Check TEX_FILE_MODE config setting
			if [[ "${TEX_FILE_MODE:-combined}" == "combined" ]]; then
				# Combined mode: collect all TeX files
				log "Combined mode (TEX_FILE_MODE=combined): generating combined PDF"
				for tex_file in "${all_tex_files[@]}"; do
					log "  Adding: $(basename ${tex_file})"
					cat "${tex_file}" >> texPlotfiles.tex
				done
			elif [[ "${TEX_FILE_MODE}" == "per_region" ]]; then
				# Per-region mode (per variable): will generate individual PDFs
				log "Per-region mode (TEX_FILE_MODE=per_region): will generate individual PDFs"
				printf '%s\n' "${all_tex_files[@]}" > "${tpath}/per_variable_tex_files.list"
			else
				# Default or auto-detect: use combined mode
				log "Default mode: generating combined PDF"
				for tex_file in "${all_tex_files[@]}"; do
					log "  Adding: $(basename ${tex_file})"
					cat "${tex_file}" >> texPlotfiles.tex
				done
			fi
	else
		log "Warning: No texPlotfiles_*.tex found in ${hpath}"
	fi
else
	# Collect TeX files only for specified scripts
	for subname in "${SUBSCRIPT_NAMES[@]}"; do
		# Skip Z1-XPDF itself as it doesn't generate TeX files
		if [[ "$subname" == "Z1-XPDF" ]]; then
			continue
		fi
		
		name="${base_name}_${subname}"
		log "name             : $name"

		# Check for per-variable/per-region TeX files (new structure: texPlotfiles_${name}_*.tex)
		per_var_tex_files=($(find "${hpath}" -maxdepth 1 -type f -name "texPlotfiles_${name}_*.tex" | sort))
		
		if [ ${#per_var_tex_files[@]} -gt 0 ]; then
			# Found per-variable/per-region TeX files
			log "Found ${#per_var_tex_files[@]} per-variable/per-region TeX files for ${name}"
			
			# Check TEX_FILE_MODE config setting
			if [[ "${TEX_FILE_MODE:-combined}" == "combined" ]]; then
				# Combined mode: add to combined file
				log "Combined mode (TEX_FILE_MODE=combined): adding to combined PDF"
				for tex_file in "${per_var_tex_files[@]}"; do
					log "  Adding: $(basename ${tex_file})"
					cat "${tex_file}" >> texPlotfiles.tex
				done
			elif [[ "${TEX_FILE_MODE}" == "per_region" ]]; then
				# Per-region mode: generate individual PDFs
				log "Per-region mode (TEX_FILE_MODE=per_region): will generate individual PDFs"
				if [ -f "${tpath}/per_variable_tex_files.list" ]; then
					printf '%s\n' "${per_var_tex_files[@]}" >> "${tpath}/per_variable_tex_files.list"
				else
					printf '%s\n' "${per_var_tex_files[@]}" > "${tpath}/per_variable_tex_files.list"
				fi
			else
				# Default: combined mode
				log "Default mode: adding to combined PDF"
				for tex_file in "${per_var_tex_files[@]}"; do
					log "  Adding: $(basename ${tex_file})"
					cat "${tex_file}" >> texPlotfiles.tex
				done
			fi
		else
			# Legacy mode: look for single TeX file
			texPlots="${hpath}/texPlotfiles_${name}.tex"
			if [ -f "${texPlots}" ]; then
				log "Found legacy single TeX file: ${texPlots}"
				cat  ${texPlots} >> texPlotfiles.tex
			else
				log "Note: No texPlotfiles_${name}.tex or texPlotfiles_${name}_*.tex found!"
				log "  Looking in: ${hpath}"
			fi
		fi
	done # name
fi
log  "----------------------------------------------------------------------------------------"
ls -lh        texPlotfiles.tex
log  "----------------------------------------------------------------------------------------"
cat           texPlotfiles.tex > ./CAMS_PLOTS.tex
log  "----------------------------------------------------------------------------------------"
log                             "./CAMS_PLOTS.tex"
	cat                          ./CAMS_PLOTS.tex
log  "----------------------------------------------------------------------------------------"

# Check if we should skip combined PDF
# Respect TEX_FILE_MODE config setting
skip_combined=false
if [[ "${TEX_FILE_MODE:-combined}" == "combined" ]]; then
    # Combined mode: don't skip combined PDF
    skip_combined=false
    if [ -f "${tpath}/per_variable_tex_files.list" ]; then
        log "Warning: per_variable_tex_files.list exists but TEX_FILE_MODE=combined, ignoring per-variable files"
        rm -f "${tpath}/per_variable_tex_files.list"
    fi
elif [[ "${TEX_FILE_MODE}" == "per_region" ]]; then
    # Per-region mode: skip combined PDF
    skip_combined=true
    log "Per-region mode (TEX_FILE_MODE=per_region): will generate individual PDFs instead of combined PDF"
fi

# Replace placeholders in the template file
# XXTIT, XXRES, XEXP1, XEXP2, XXDAT, XXAVG, XXUSR, XXTEAM
TEAM=$(echo "$TEAM_PREFIX" | sed 's/_/\\\\_/g')
log "TEAM $TEAM"

# Parse EXP_LABELS if defined (comma-separated list matching experiments order)
exp_labels_array=()
if [ -n "${EXP_LABELS:-}" ]; then
    IFS=',' read -ra exp_labels_array <<< "${EXP_LABELS}"
    # Trim whitespace from each label
    for i in "${!exp_labels_array[@]}"; do
        exp_labels_array[$i]=$(echo "${exp_labels_array[$i]}" | xargs)
    done
    # Pad with experiment names if not enough labels provided
    while [ ${#exp_labels_array[@]} -lt ${#experiments[@]} ]; do
        exp_labels_array+=("${experiments[${#exp_labels_array[@]}]}")
    done
    log "Using EXP_LABELS: ${exp_labels_array[*]}"
else
    exp_labels_array=("${experiments[@]}")
    log "Using experiments as labels: ${exp_labels_array[*]}"
fi

# Build experiment title string for multiple experiments
# Format: "exp1 vs exp2" or "exp1, exp2 vs exp3" etc.
# Use EXP_LABELS if available, otherwise use experiment names
exp_title=""
for i in "${!experiments[@]}"; do
    exp_label="${exp_labels_array[$i]}"
    if [ $i -eq 0 ]; then
        exp_title="${exp_label}"
    elif [ $i -eq $((${#experiments[@]} - 1)) ]; then
        exp_title="${exp_title} vs ${exp_label}"
    else
        exp_title="${exp_title}, ${exp_label}"
    fi
done

log "Experiment title: $exp_title"

# For backward compatibility, keep XEXP1 and XEXP2 but populate with labels
exp1_tex="${exp_labels_array[0]}"
exp2_tex="${exp_labels_array[1]:-${exp_labels_array[0]}}"  # Use first if only one experiment

# Generate combined PDF only if not in per-variable mode
if [ "$skip_combined" = false ]; then
    sed -e "s/XXTIT/${EVALUATION_PREFIX}/g" \
        -e "s/XXRES/${MODEL_RESOLUTION}/g" \
        -e "s/XEXP1 vs XEXP2/${exp_title}/g" \
        -e "s/XEXP1/${exp1_tex}/g" \
        -e "s/XEXP2/${exp2_tex}/g" \
        -e "s/XXAVG/${TIME_RESOLUTION}/g" \
        -e "s/XXDAT/${mDate}/g" \
        -e "s/XXUSR/${CUSR}/g" \
        -e "s|XTEAM|${TEAM}|g" \
         "template.tex" >    "./${pfile}.tex"
    log  "Converting ${pfile}.tex to PDF using ${PDF_CONVERTER}"
    log  "${PDF_CONVERTER} -interaction=nonstopmode ./${pfile}.tex"
          ${PDF_CONVERTER} -interaction=nonstopmode ./${pfile}.tex >/dev/null 2>&1
          ${PDF_CONVERTER} -interaction=nonstopmode ./${pfile}.tex >/dev/null 2>&1
          mv           ./${pfile}.pdf  $TEX_DIRECTORY/
          log "Final presentation PDF: $TEX_DIRECTORY/${pfile}.pdf"
          ls -lh       $TEX_DIRECTORY/${pfile}.pdf
          echo "open   $TEX_DIRECTORY/${pfile}.pdf"
          rm -f *.aux *.nav *.out *.snm *.toc *.log
else
    log "Skipping combined PDF generation (per-variable mode)"
fi

# Generate individual PDFs for per-variable mode if requested
if [ -f "${tpath}/per_variable_tex_files.list" ]; then
    log  "----------------------------------------------------------------------------------------"
    log "Generating individual PDFs for per-variable TeX files"
    log  "----------------------------------------------------------------------------------------"
    
    # Read list file line by line
    while IFS= read -r var_tex || [ -n "$var_tex" ]; do
        if [ -f "${var_tex}" ]; then
            var_tex_basename=$(basename "${var_tex}" .tex)
            
            # Base name for all PDFs: TEAM_experiments_dates_qlc_Z1-XPDF_CDATE
            base_pdf_name="${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_qlc_Z1-XPDF_${CDATE}"
            
            # Extract QLTYPE, region (if present), and variable from filename
            # Pattern: texPlotfiles_qlc_D1-ANAL_REGION_VAR.tex or texPlotfiles_qlc_C1-GLOB_VAR.tex
            if [[ "${var_tex_basename}" =~ texPlotfiles_(qlc_[^-]+-[^-]+)_(.+) ]]; then
                qltype_part="${BASH_REMATCH[1]}"
                rest_part="${BASH_REMATCH[2]}"
                
                # Extract script name (remove "qlc_" prefix)
                script_name="${qltype_part#qlc_}"
                
                # Determine if this QLTYPE has regions (D1-ANAL has regions, C1-GLOB doesn't)
                # Scripts with regions: D1-ANAL, E2-EVAL (and potentially others)
                # Scripts without regions: C1-GLOB
                region_part=""
                var_part=""
                if [[ "${qltype_part}" == "qlc_D1-ANAL" ]] || [[ "${qltype_part}" == "qlc_E2-EVAL" ]]; then
                    # Has region: extract first underscore-separated part as region, rest as variable
                    # e.g., "EU_NH4_as" -> region="EU", var="NH4_as"
                    if [[ "${rest_part}" =~ ^([^_]+)_(.+)$ ]]; then
                        region_part="${BASH_REMATCH[1]}"
                        var_part="${BASH_REMATCH[2]}"
                    else
                        # No underscore found - treat entire rest_part as variable (shouldn't happen for D1/E2)
                        var_part="${rest_part}"
                    fi
                else
                    # No region (e.g., C1-GLOB): treat entire rest_part as variable
                    # e.g., "NH4_as" -> var="NH4_as"
                    var_part="${rest_part}"
                fi
                
                # Build directory name: base_script_region (if region exists) or base_script
                if [ -n "$region_part" ]; then
                    pdf_dir="${TEX_DIRECTORY}/${base_pdf_name}_${script_name}_${region_part}"
                    pdf_name="${base_pdf_name}_${script_name}_${region_part}_${var_part}.pdf"
                else
                    pdf_dir="${TEX_DIRECTORY}/${base_pdf_name}_${script_name}"
                    pdf_name="${base_pdf_name}_${script_name}_${var_part}.pdf"
                fi
                
                # Create directory if it doesn't exist
                mkdir -p "${pdf_dir}"
            else
                # Fallback to original naming if pattern doesn't match
                pdf_dir="${TEX_DIRECTORY}"
                pdf_name="${TEAM_PREFIX}_${experiments_hyphen}_${mDate}_${var_tex_basename}-${ext}_${CDATE}.pdf"
                var_part="${var_tex_basename#texPlotfiles_*_}"
            fi
            
            log "Processing individual TeX file: ${var_tex_basename}"
            log "  Directory: ${pdf_dir}"
            log "  PDF will be: ${pdf_name}"
            
log  "----------------------------------------------------------------------------------------"
            # Create individual CAMS_PLOTS.tex from this variable's TeX file
            cat "${var_tex}" > ./CAMS_PLOTS.tex
log  "----------------------------------------------------------------------------------------"
            ls -lh             ./CAMS_PLOTS.tex
            cp -p              ./CAMS_PLOTS.tex ./CAMS_PLOTS_${var_part}.tex
log  "----------------------------------------------------------------------------------------"
log                             "./CAMS_PLOTS_${var_part}.tex"
	cat                          ./CAMS_PLOTS_${var_part}.tex
log  "----------------------------------------------------------------------------------------"
            
            # Replace placeholders in template
            sed -e "s/XXTIT/${EVALUATION_PREFIX}/g" \
                -e "s/XXRES/${MODEL_RESOLUTION}/g" \
                -e "s/XEXP1 vs XEXP2/${exp_title}/g" \
                -e "s/XEXP1/${exp1_tex}/g" \
                -e "s/XEXP2/${exp2_tex}/g" \
                -e "s/XXAVG/${TIME_RESOLUTION}/g" \
                -e "s/XXDAT/${mDate}/g" \
                -e "s/XXUSR/${CUSR}/g" \
                -e "s|XTEAM|${TEAM}|g" \
                 "template.tex" >    "./${pdf_name%.pdf}.tex"
            
            log "Converting ${pdf_name%.pdf}.tex to PDF"
            log  "${PDF_CONVERTER} -interaction=nonstopmode ./${pdf_name%.pdf}.tex"
                  ${PDF_CONVERTER} -interaction=nonstopmode ./${pdf_name%.pdf}.tex >/dev/null 2>&1
                  ${PDF_CONVERTER} -interaction=nonstopmode ./${pdf_name%.pdf}.tex >/dev/null 2>&1
            
            if [ -f "./${pdf_name}" ]; then
                mv  "./${pdf_name}" "${TEX_DIRECTORY}/"
                ls -lh     ${TEX_DIRECTORY}/${pdf_name}
                echo "open ${TEX_DIRECTORY}/${pdf_name}"
            else
                log "Warning: Failed to generate PDF for ${pdf_name%.pdf}.tex"
            fi
            
            # Clean up intermediate files
            rm -f *.aux *.nav *.out *.snm *.toc *.log
        fi
    done < "${tpath}/per_variable_tex_files.list"
    
    log  "----------------------------------------------------------------------------------------"
    log "Individual PDF generation complete"
    log  "----------------------------------------------------------------------------------------"
fi

log  "----------------------------------------------------------------------------------------"
log "$TEX_DIRECTORY"
if  ls "${TEX_DIRECTORY}" | grep "${pfile}" >/dev/null 2>&1; then
    ls "${TEX_DIRECTORY}" | grep "${pfile}"
else
    log "Warning: no tex files found"
fi
log  "----------------------------------------------------------------------------------------"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
