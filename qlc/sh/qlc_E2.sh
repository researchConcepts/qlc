#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="evaltools"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create evaltools plots for selected variables"
 log  "Multi-experiment and multi-region support enabled"
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
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
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
module reset
module load conda
fi
if [ "${myOS}" == "Darwin" ]; then
source $HOME/.profile_anaconda
fi
# Check if conda exists
if ! command_exists conda; then
  log  "Error: conda command not found" >&2
  exit 1
else
  log  "Success: conda command found"
  which conda
  conda deactivate
  conda activate evaltools
  which python
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
# Experiments come first, followed by dates in YYYY-MM-DD format, optional config at end
# ----------------------------------------------------------------------------------------
parse_qlc_arguments "$@" || exit 1

# Create experiment strings for different uses
experiments_hyphen=$(IFS=-; echo "${experiments[*]}")

# Process dates
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"
ext="${QLTYPE}.pdf"

# Base path for outputs
base_hpath="$PLOTS_DIRECTORY/${experiments_hyphen}_${mDate}"

# Define path to the aqtool script
AQTOOL_SCRIPT="${QLC_HOME}/config/evaltools/qlc_aqtool_1.0.9.py"
if [ ! -f "$AQTOOL_SCRIPT" ]; then
    log "Error: aqtool script not found at ${AQTOOL_SCRIPT}. Exiting."
    exit 1
fi
log "Found aqtool script: ${AQTOOL_SCRIPT}"

# Create log directory
mkdir -p "${QLC_HOME}/log"

# Check for debug mode
DEBUG_MODE=${EVALTOOLS_DEBUG:-0}
if [[ "$*" =~ "--debug" ]] || [[ "$*" =~ "-d" ]]; then
    DEBUG_MODE=1
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Function to discover evaluators for a region and extract experiment names
discover_evaluators_for_region() {
    local region_name=$1
    local search_dir="${EVALUATOR_OUTPUT_DIR:-${ANALYSIS_DIRECTORY}/evaluators}"
    
    log "Discovering evaluators for region: ${region_name}"
    log "Search directory: ${search_dir}"
    
    # Find evaluator files for this region
    # Pattern: {region}_{exp}_{daterange}_{var}.evaluator.evaltools
    local evaluator_files=($(find "${search_dir}" -type f -name "${region_name}_*_${sDate}-${eDate}_*.evaluator.evaltools" 2>/dev/null))
    
    if [ ${#evaluator_files[@]} -eq 0 ]; then
        log "Warning: No evaluator files found for region ${region_name}"
        return 1
    fi
    
    log "Found ${#evaluator_files[@]} evaluator file(s) for ${region_name}"
    
    # Extract unique experiment names and variables
    local exp_list=()
    local var_list=()
    
    for eval_file in "${evaluator_files[@]}"; do
        local basename_eval=$(basename "$eval_file" .evaluator.evaltools)
        
        # Pattern: {region}_{exp}_{daterange}_{var}_{time_res}
        # Example: EU_b2ro_20181201-20181221_NH3_daily or EU_b2ro_20181201-20181221_NH4_as_daily
        # Extract experiment and variable (variable may contain underscores like NH4_as)
        # Strategy: Match from start, then capture everything between daterange and the LAST underscore
        if [[ "$basename_eval" =~ ^${region_name}_([^_]+)_${sDate}-${eDate}_(.+)_([^_]+)$ ]]; then
            local exp_name="${BASH_REMATCH[1]}"
            local var_name="${BASH_REMATCH[2]}"
            local time_res="${BASH_REMATCH[3]}"
            
            # Add experiment to list if not present
            if [[ ! " ${exp_list[*]} " =~ " ${exp_name} " ]]; then
                exp_list+=("$exp_name")
                log "  Found experiment: $exp_name"
            fi
            
            # Add variable to list if not present
            if [[ ! " ${var_list[*]} " =~ " ${var_name} " ]]; then
                var_list+=("$var_name")
                log "  Found variable: $var_name"
            fi
        fi
    done
    
    if [ ${#exp_list[@]} -eq 0 ]; then
        log "Warning: No experiments extracted from evaluator filenames"
        return 1
    fi
    
    # Export discovered data
    region_experiments=("${exp_list[@]}")
    region_variables=("${var_list[@]}")
    
    log "Region ${region_name} experiments: ${region_experiments[*]}"
    log "Region ${region_name} variables: ${region_variables[*]}"
    
    return 0
}

# Function to run aqtool commands
run_aqtool() {
    local plot_type=$1
    local output_file_template=$2
    local flags=$3
    local title_arg=$4
    local preprocess_arg=$5

    # Properly quote the title to handle spaces
    local safe_title_arg
    if [ -n "$title_arg" ]; then
        printf -v safe_title_arg "%q" "$title_arg"
    fi

    # aqtool automatically adds the extension, so we build the name without it
    local output_file_base="${output_file_template}"
    local output_file_arg=$output_file_base
    
    log "Generating ${plot_type} plot..."
    
    local full_command="python \"$AQTOOL_SCRIPT\""
    if [ -n "$preprocess_arg" ]; then
        full_command="${full_command} preprocess ${preprocess_arg}"
    fi
    full_command="${full_command} plot ${plot_type} ${flags} -of \"${output_file_arg}\""
    if [ -n "$title_arg" ]; then
        full_command="${full_command} -tit ${safe_title_arg}"
    fi
    if [ "$DEBUG_MODE" -eq 1 ]; then
        log "Command: ${full_command}"
    fi

    # Save and unset PYTHONPATH to avoid conflicts
    local saved_pythonpath="$PYTHONPATH"
    unset PYTHONPATH
    
    # Explicitly activate evaltools environment and run command
    if command -v conda >/dev/null 2>&1; then
        eval "$(conda shell.bash hook)"
        conda activate evaltools 2>/dev/null
    fi
    
    # Run command with output control based on debug mode
    if [ "$DEBUG_MODE" -eq 1 ]; then
        eval ${full_command} 2>&1 | tee -a "$REGION_E2_LOG"
    else
        eval ${full_command} >> "$REGION_E2_LOG" 2>&1
    fi
    local cmd_status=$?
    
    # Restore PYTHONPATH
    export PYTHONPATH="$saved_pythonpath"

    # Check if plot was created
    local check_file_pattern="${output_file_base/\{score\}/\*}*.${PLOTEXTENSION}"
    if compgen -G "$check_file_pattern" > /dev/null; then
         local created_files=$(compgen -G "$check_file_pattern" | wc -l)
         log "  ✓ Created ${plot_type} plot(s)"
      else
          log "  ✗ Error: Plot generation failed for ${plot_type} (check ${REGION_E2_LOG})"
      fi
}

# Function to generate plots for a region
generate_plots_for_region() {
    local region_name=$1
    local region_hpath=$2
    
    log "========================================"
    log "Generating plots for region: ${region_name}"
    log "========================================"
    log "Region path: ${region_hpath}"
    
    # Discover evaluators for this region
    if ! discover_evaluators_for_region "${region_name}"; then
        log "Skipping region ${region_name} - no evaluators found"
        return 1
    fi
    
    # Create log file for this region
    REGION_E2_LOG="${QLC_HOME}/log/qlc_E2_${region_name}_${experiments_hyphen}_${sDate}-${eDate}.log"
    
    log "Starting evaltools plot generation for ${region_name}..."
    log "Plot output will be logged to: ${REGION_E2_LOG}"
    if [ "$DEBUG_MODE" -eq 1 ]; then
        log "Debug mode: ENABLED (verbose plot output)"
    else
        log "Debug mode: DISABLED (silent plot output, only summaries shown)"
    fi
    
    # Cleanup old plots
    log "Cleaning up old evaltools plots from ${region_hpath}..."
    if [ -d "$region_hpath" ]; then
        rm -f "${region_hpath}"/qlc_E2_evaltools_*.${PLOTEXTENSION} 2>/dev/null
        log "✓ Removed old evaltools plots"
    else
        log "Creating plot directory: ${region_hpath}"
        mkdir -p "$region_hpath"
    fi
    
    # Define output file prefix
    EVALUATION_PREFIX="qlc_E2_evaltools"
    
    # Create TeX files
    local texPlotsfile="${region_hpath}/texPlotfiles_${QLTYPE}.list"
    local texFile="${texPlotsfile%.list}.tex"
    rm -f "$texPlotsfile" "$texFile"
    touch "$texPlotsfile"
    
    # Evaluator directory
    EVALUATOR_DIR="${EVALTOOLS_OUTPUT_DIR:-${ANALYSIS_DIRECTORY}/evaluators}"
    
    # For each variable, generate plots with all experiments
    for var in "${region_variables[@]}"; do
        log "Processing variable: $var for region ${region_name}"
        
        # Find all evaluator files for this variable and region
        # Pattern now includes temporal resolution: {region}_{exp}_{daterange}_{var}_{time_res}.evaluator.evaltools
        local evaluator_files=()
        for exp in "${region_experiments[@]}"; do
            # Use wildcard for temporal resolution (daily, hourly, etc.)
            local eval_pattern="${EVALUATOR_DIR}/${region_name}_${exp}_${sDate}-${eDate}_${var}_*.evaluator.evaltools"
            while IFS= read -r eval_file; do
                if [ -f "$eval_file" ]; then
                    evaluator_files+=("$eval_file")
                    log "  Found evaluator: $(basename $eval_file)"
                fi
            done < <(compgen -G "$eval_pattern" 2>/dev/null || true)
        done
        
        if [ ${#evaluator_files[@]} -eq 0 ]; then
            log "Warning: No evaluator files found for variable ${var} in region ${region_name}"
            continue
        fi
        
        log "Generating plots with ${#evaluator_files[@]} experiment(s)"
        
        # Auto-detect temporal resolution from first evaluator
        log "Detecting temporal resolution from evaluator..."
        local first_eval="${evaluator_files[0]}"
        series_type=$(python -c "
import pickle
import sys
try:
    with open('${first_eval}', 'rb') as f:
        ev = pickle.load(f)
    series_type = getattr(ev.observations, 'seriesType', 'unknown')
    print(series_type)
except Exception as e:
    print('unknown', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
        
        if [ -n "$series_type" ]; then
            log "  Series type: $series_type"
            if [ "$series_type" = "hourly" ]; then
                ENABLE_DIURNAL_CYCLE=1
                ENABLE_TIME_SCORES=1
                log "  ✓ Hourly data detected - all plots enabled"
            elif [ "$series_type" = "daily" ]; then
                ENABLE_DIURNAL_CYCLE=0
                ENABLE_TIME_SCORES=0
                log "  ⚠ Daily data detected - diurnal_cycle and time_scores disabled"
            else
                ENABLE_DIURNAL_CYCLE=0
                ENABLE_TIME_SCORES=0
                log "  ⚠ Unknown series type - disabling incompatible plots"
            fi
        else
            ENABLE_DIURNAL_CYCLE=0
            ENABLE_TIME_SCORES=0
            log "  ⚠ Could not detect series type - disabling incompatible plots"
        fi

        # Define plot colors and markers based on number of experiments
        local num_exps=${#evaluator_files[@]}
        local colors=("firebrick" "dodgerblue" "forestgreen" "orange" "purple" "brown" "pink" "gray" "olive" "cyan")
        local markers=("'^'" "'+'" "'o'" "'s'" "'D'" "'v'" "'^'" "'<'" "'>'" "'*'")
        
        local col_list=""
        local mrk_list=""
        for ((i=0; i<num_exps && i<${#colors[@]}; i++)); do
            col_list="$col_list ${colors[$i]}"
            mrk_list="$mrk_list ${markers[$i]}"
        done
        col_list=$(echo "$col_list" | xargs)  # Trim whitespace
        mrk_list=$(echo "$mrk_list" | xargs)
        
        # Build experiment list for title
        local experiments_title=$(IFS=" vs "; echo "${region_experiments[*]}")
        local title="Comparison for ${var} (${region_name}): ${experiments_title}"
        
        # Define scores
        all_scores="FGE MMB PearsonR RMSE"
        
        # Generate plots
        # Time series plot (skip if dates are identical)
        if [ "$sDate" != "$eDate" ]; then
            run_aqtool "time_series" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_timeseries" "${evaluator_files[@]} -se $sDate $eDate -mar $mrk_list -col $col_list -ann PROTOTYPE -env" "$title" ""
        else
            log "Skipping time_series plot (start and end dates are identical)"
        fi

        # Diurnal cycle (only for hourly data)
        if [ "$ENABLE_DIURNAL_CYCLE" -eq 1 ]; then
            run_aqtool "diurnal_cycle" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_diurnal" "${evaluator_files[@]} -col $col_list -mar $mrk_list -ann PROTOTYPE -env" "$title" ""
        else
            log "Skipping diurnal_cycle plot (requires hourly data)"
        fi
        
        # Data density
        run_aqtool "data_density" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_density" "${evaluator_files[@]} -col $col_list -ann PROTOTYPE" "$title" ""
        
        # Score plots for each score
        for score in $all_scores; do
            run_aqtool "mean_time_scores" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_meantimescores_${score}" "${evaluator_files[@]} -sco $score -col $col_list -ann PROTOTYPE" "$title" ""
            run_aqtool "median_station_scores" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_medianstationscores_${score}" "${evaluator_files[@]} -sco $score -col $col_list -mar $mrk_list -ann PROTOTYPE" "$title" ""
            
            # Time scores (only for sub-daily data)
            if [ "$ENABLE_TIME_SCORES" -eq 1 ]; then
                run_aqtool "time_scores" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_timescores_${score}" "${evaluator_files[@]} -sco $score -ter 12 -col $col_list -mar $mrk_list -ann PROTOTYPE" "$title" ""
            else
                log "Skipping time_scores plot for $score (requires sub-daily data)"
            fi
        done
        
        # Additional plots (using first evaluator as reference where needed)
        run_aqtool "station_scores" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_stationscores" "${evaluator_files[0]} -sco MeanBias" "$title" ""
        run_aqtool "taylor_diagram" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_taylor" "${evaluator_files[@]} -col $col_list -mar $mrk_list -ann PROTOTYPE -cl 15 -fra" "TAYLOR" ""
        run_aqtool "score_quartiles" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_scorequartiles" "${evaluator_files[@]} -xsc FGE -ysc MMB -col $col_list -ar 0.8 -ba -ocsv ${region_hpath}/score_quartiles_${var}.csv" "" ""
        run_aqtool "station_score_density" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_scoredensity" "${evaluator_files[@]} -sco RMSE -col $col_list -ann PROTOTYPE" "$title" ""
        run_aqtool "bar_scores" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_barscores" "${evaluator_files[@]} -sco RMSE -ave median -col $col_list -ann PROTOTYPE -ar 0.8" "$title" ""
        run_aqtool "bar_exceedances" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_barexceed" "${evaluator_files[0]} -thr 90.0 -se $sDate $eDate" "$title" ""
        run_aqtool "line_exceedances" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_lineexceed" "${evaluator_files[@]} -thr 90.0 -se $sDate $eDate -ann PROTOTYPE -col $col_list" "$title" ""
        run_aqtool "bar_contingency_table" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_contingency" "${evaluator_files[@]} -thr 90.0 -se $sDate $eDate" "$title" ""
        run_aqtool "values_scatter_plot" "${region_hpath}/${EVALUATION_PREFIX}_${region_name}_${var}_${mDate}_valuescatter" "${evaluator_files[0]} -se $sDate $eDate -ann PROTOTYPE" "$title" ""

        log "Successfully generated all evaltools plots for variable: ${var} in region ${region_name}"
    done
    
    # Add plots to TeX list
    log "Ordering plots for TeX file..."
    
    # Helper function to find and add plots
    add_plot_if_found() {
        local plot_pattern=$1
        find "${region_hpath}" -maxdepth 1 -type f -name "${plot_pattern}" 2>/dev/null | sort | while IFS= read -r plot_file; do
            if [ -n "$plot_file" ] && ! grep -qF "$plot_file" "$texPlotsfile"; then
                echo "$plot_file" >> "$texPlotsfile"
                log "Added plot to TeX list: $(basename $plot_file)"
            fi
        done
    }
    
    # Loop through variables in order
    for var in "${region_variables[@]}"; do
        log "Ordering plots for variable: $var"
        add_plot_if_found "*${var}*timeseries*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*diurnal*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*taylor*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*scatter*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*valuescatter*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*density*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*scoredensity*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*barscores*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*barexceed*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*lineexceed*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*meantimescores*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*medianstationscores*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*timescores*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*stationscores*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*scorequartiles*.${PLOTEXTENSION}"
        add_plot_if_found "*${var}*contingency*.${PLOTEXTENSION}"
    done
    
    # Generate TeX file
    log "Generating TeX file for plots: ${texFile}"
    
    local tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
    local tREGION=$(echo "${region_name}" | sed 's/_/\\_/g')
    
    cat > "$texFile" <<EOF
%===============================================================================
\subsection{${tQLTYPE} -- ${tREGION} -- ${mDate} (${TIME_AVERAGE})}
EOF
    
    # Loop through found plots and generate frames
    if [ -s "$texPlotsfile" ]; then
        while IFS= read -r plot_path; do
            plot_filename=$(basename -- "$plot_path")
            var_name_tex=""
            title_prefix=""

            # Extract variable name
            for var in "${region_variables[@]}"; do
                if [[ "$plot_filename" == *"${var}"* ]]; then
                    var_name_tex=$(echo "$var" | sed 's/_/\\_/g')
                    break
                fi
            done

            # Determine title prefix
            case "$plot_filename" in
                *_timeseries.*) title_prefix="Evaltools Time Series" ;;
                *_diurnal.*) title_prefix="Evaltools Diurnal Cycle" ;;
                *_density.*) title_prefix="Evaltools Data Density" ;;
                *_meantimescores_*) title_prefix="Evaltools Mean Time Scores ($(basename "$plot_path" .${PLOTEXTENSION} | sed 's/.*_//'))" ;;
                *_medianstationscores_*) title_prefix="Evaltools Median Station Scores ($(basename "$plot_path" .${PLOTEXTENSION} | sed 's/.*_//'))" ;;
                *_timescores_*) title_prefix="Evaltools Time Scores ($(basename "$plot_path" .${PLOTEXTENSION} | sed 's/.*_//'))" ;;
                *_stationscores.*) title_prefix="Evaltools Station Scores" ;;
                *_taylor.*) title_prefix="Evaltools Taylor Diagram" ;;
                *_scorequartiles.*) title_prefix="Evaltools Score Quartiles" ;;
                *_scatter.*) title_prefix="Evaltools Comparison Scatter" ;;
                *_scoredensity.*) title_prefix="Evaltools Station Score Density" ;;
                *_barscores.*) title_prefix="Evaltools Bar Scores" ;;
                *_barexceed.*) title_prefix="Evaltools Bar Exceedances" ;;
                *_lineexceed.*) title_prefix="Evaltools Line Exceedances" ;;
                *_contingency.*) title_prefix="Evaltools Contingency Table" ;;
                *_valuescatter.*) title_prefix="Evaltools Value Scatter Plot" ;;
                *) title_prefix="Evaltools Plot" ;;
            esac

            # Build experiments title
            local experiments_title=$(IFS=" vs "; echo "${region_experiments[*]}")
            local exps_tex=$(echo "$experiments_title" | sed 's/_/\\_/g')
            title_final="${title_prefix} for ${var_name_tex} (${tREGION}): ${exps_tex}"

            cat >> "$texFile" <<EOF
%===============================================================================
\frame{
\frametitle{${title_final}}
\vspace{0mm}
\centering
\includegraphics[width=0.9\textwidth]{${plot_path}}
}
EOF
            log "Generated TeX frame for $(basename $plot_filename)"
        done < "$texPlotsfile"
        log "Finished generating TeX file: ${texFile}"
    else
        log "No plots found for region ${region_name}"
    fi
    
    # Summary
    plot_count=$(find "${region_hpath}" -name "qlc_E2_evaltools_*.${PLOTEXTENSION}" 2>/dev/null | wc -l)
    log "✓ Created ${plot_count} evaltools plot(s) for region ${region_name}"
    
    log "Completed region: ${region_name}"
    return 0
}

# Function to detect and process multi-region mode
process_multi_region() {
    log "Multi-region mode detection..."
    
    # Check if base directory exists
    if [ ! -d "$base_hpath" ]; then
        log "Error: Base plots directory not found: ${base_hpath}"
        log "Please ensure qlc_D1.sh and qlc_E1.sh have been run successfully."
        exit 1
    fi
    
    # Look for region subdirectories
    local region_dirs=()
    while IFS= read -r dir; do
        if [ -d "$dir" ]; then
            local region_name=$(basename "$dir")
            # Skip hidden directories
            if [[ ! "$region_name" =~ ^\. ]]; then
                region_dirs+=("$dir")
            fi
        fi
    done < <(find "${base_hpath}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    
    if [ ${#region_dirs[@]} -eq 0 ]; then
        log "No region subdirectories found - processing base directory"
        # Process base directory as single region (legacy mode)
        generate_plots_for_region "default" "${base_hpath}"
    else
        log "Found ${#region_dirs[@]} region subdirectories - multi-region mode active"
        
        # Process each region
        local success_count=0
        local fail_count=0
        
        for region_dir in "${region_dirs[@]}"; do
            local region_name=$(basename "$region_dir")
            
            if generate_plots_for_region "${region_name}" "${region_dir}"; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        done
        
        log "========================================"
        log "Multi-region plot generation complete"
        log "  Successful: ${success_count}"
        log "  Failed/Skipped: ${fail_count}"
        log "========================================"
        
        if [ ${success_count} -eq 0 ]; then
            log "Error: No regions were processed successfully"
            exit 1
        fi
        
        # Generate combined TeX file
        log "Generating combined TeX file for all regions..."
        local combined_tex="${base_hpath}/texPlotfiles_${QLTYPE}_all_regions.tex"
        local tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
        
        # Build experiments title
        local experiments_title=$(IFS=" vs "; echo "${experiments[*]}")
        local exps_tex=$(echo "$experiments_title" | sed 's/_/\\_/g')
        
        cat > "$combined_tex" << EOF
%===============================================================================
\section{Multi-Region Analysis: ${tQLTYPE}}
\subsection{Experiments: ${exps_tex} (${mDate}, ${TIME_AVERAGE})}
EOF
        
        # Append each region's TeX content
        for region_dir in "${region_dirs[@]}"; do
            local region_name=$(basename "$region_dir")
            local region_tex="${region_dir}/texPlotfiles_${QLTYPE}.tex"
            if [ -f "$region_tex" ]; then
                echo "%===============================================================================" >> "$combined_tex"
                echo "% Region: ${region_name}" >> "$combined_tex"
                echo "%===============================================================================" >> "$combined_tex"
                cat "$region_tex" >> "$combined_tex"
            fi
        done
        
        log "Generated combined TeX file: ${combined_tex}"
        
        # Create standard name for Z1 compatibility
        local standard_tex="${base_hpath}/texPlotfiles_${QLTYPE}.tex"
        cp "$combined_tex" "$standard_tex"
        log "Created standard TeX file for Z1 compatibility: ${standard_tex}"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log "Starting evaltools plot generation..."
log "Base directory: ${base_hpath}"
log "Debug mode: ${DEBUG_MODE}"

# Process regions (auto-detects multi-region vs single-region)
process_multi_region

log "========================================================================================"
log "Plot Generation Complete"
log "========================================================================================"
log "Output directory: ${base_hpath}"
log "Next step: qlc_Z1.sh will compile plots into PDF presentation"
log "========================================================================================"

log "$ANALYSIS_DIRECTORY"
log "$PLOTS_DIRECTORY"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
