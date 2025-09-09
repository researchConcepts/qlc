#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

PLOTTYPE="python"
SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Create Python plots for selected variables (to be defined in $CONFIG_FILE)              "
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
#log   ${HOST} ${ARCH}
if [  "${HOST}" == "a" ] && [ "${myOS}" != "Darwin" ]; then
module load python3/3.10.10-01
fi

# Check if qlc-py exists
if ! command_exists qlc-py; then
  log  "Error: qlc-py command not found" >&2
  exit 1
else
  log  "Success: qlc-py command found"
  which qlc-py
fi

# Create output directory if not existent
if [    ! -d "$PLOTS_DIRECTORY" ]; then
    mkdir -p "$PLOTS_DIRECTORY"
fi

# get script name without path and extension
script_name="${SCRIPT##*/}"     # Remove directory path
script_name="${script_name%.*}" # Remove extension
QLTYPE="$script_name"

# Assign the command line input parameters to variables
exp1="$1"
exp2="$2"
sDat="$3"
eDat="$4"
sDate="${sDat//[-:]/}"
eDate="${eDat//[-:]/}"
mDate="$sDate-$eDate"
ext="${QLTYPE}.pdf"

# Create a temporary list for TeX files and a temporary JSON config
hpath="$PLOTS_DIRECTORY/${exp1}-${exp2}_${mDate}"
texPlotsfile="${hpath}/texPlotfiles_${QLTYPE}.list"
texFile="${texPlotsfile%.list}.tex"
temp_config_file="${hpath}/temp_qlc_D1_config.json"

# Ensure the output directory exists
mkdir -p "$hpath"
rm -f "$texPlotsfile" "$temp_config_file" "$texFile"
touch "$texPlotsfile"

# Dynamically discover variables from config, validated against existing .nc files.
log "Discovering variables from config and validating against files in ${ANALYSIS_DIRECTORY}/${exp1}..."
validated_vars=()
if [[ -z "${MARS_RETRIEVALS[*]}" ]]; then
    log "Warning: MARS_RETRIEVALS array is not defined in the configuration. Falling back to filename parsing."
    # Fallback to the old method if config arrays are missing
    myvar_list_array=($(find "${ANALYSIS_DIRECTORY}/${exp1}" -type f -name "*.nc" ! -name "*_tavg.nc" -print0 | \
        xargs -0 -n 1 basename | \
        sed -E 's/.*_[A-Z][0-9]+_[a-z]+_(.*)\.nc/\1/' | \
        sort -u))
else
    for name in "${MARS_RETRIEVALS[@]}"; do
        myvar_array_name="myvar_${name}[@]"
        myvars=("${!myvar_array_name}")

        for var_name in "${myvars[@]}"; do
            # Check if a file for this variable exists for the first experiment.
            # The pattern looks for any file ending in _<var_name>.nc
            if compgen -G "${ANALYSIS_DIRECTORY}/${exp1}/*_${var_name}.nc" > /dev/null; then
                validated_vars+=("$var_name")
            fi
        done
    done
    # De-duplicate the results
    myvar_list_array=($(printf "%s\n" "${validated_vars[@]}" | sort -u))
fi


if [ ${#myvar_list_array[@]} -eq 0 ]; then
    log "Error: Could not find any variables to process. Check config and analysis files. Exiting."
    exit 1
fi
myvar_list_string=$(IFS=,; echo "${myvar_list_array[*]}")
log "Found variables: ${myvar_list_string}"

# Dynamically create a temporary JSON config file with three entries.
cat > "$temp_config_file" << EOM
[
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${hpath}/${QLTYPE}",
    "station_file": "${STATION_FILE:-""}",
    "obs_path": "${OBS_DATA_PATH:-""}",
    "obs_dataset_type": "${OBS_DATASET_TYPE:-""}",
    "obs_dataset_version": "${OBS_DATASET_VERSION:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${myvar_list_string}",
    "plot_region": "${REGION:-""}",
    "station_radius_deg": ${STATION_RADIUS_DEG:-0.5},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": true,
    "show_station_timeseries_obs": true,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": false,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${REGION:-""}, ${myvar_list_string}",
      "summary": "netCDF output: ${OBS_DATASET_TYPE:-""} observations for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  },
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${hpath}/${QLTYPE}",
    "station_file": "${STATION_FILE:-""}",    
    "mod_path": "${ANALYSIS_DIRECTORY:-""}",
    "model": "${MODEL:-""}",
    "experiments": "${exp1},${exp2}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${myvar_list_string}",
    "plot_region": "${REGION:-""}",
    "station_radius_deg": ${STATION_RADIUS_DEG:-0.5},
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "show_station_timeseries_obs": false,
    "show_station_timeseries_mod": true,
    "show_station_timeseries_com": false,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${REGION:-""}, ${myvar_list_string}",
      "summary": "netCDF output: Model data for ${exp1},${exp2} for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  },
  {
    "name": "${TEAM_PREFIX}",
    "logdir": "${QLC_HOME}/log",
    "workdir": "${QLC_HOME}/run",
    "output_base_name": "${hpath}/${QLTYPE}",
    "station_file": "${STATION_FILE:-""}",
    "obs_path": "${OBS_DATA_PATH:-""}",
    "obs_dataset_type": "${OBS_DATASET_TYPE:-""}",
    "obs_dataset_version": "${OBS_DATASET_VERSION:-""}",
    "mod_path": "${ANALYSIS_DIRECTORY:-""}",
    "model": "${MODEL:-""}",
    "experiments": "${exp1},${exp2}",
    "exp_labels": "${EXP_LABELS:-""}",
    "start_date": "${sDat}",
    "end_date": "${eDat}",
    "variable": "${myvar_list_string}",
    "plot_region": "${REGION:-""}",
    "station_radius_deg": ${STATION_RADIUS_DEG:-0.5},
    "model_level": ${MODEL_LEVEL:-null},
    "plot_type": "${PLOT_TYPE:-""}",
    "time_average": "${TIME_AVERAGE:-""}",
    "station_plot_group_size": ${STATION_PLOT_GROUP_SIZE:-5},
    "show_stations": false,
    "show_min_max": true,
    "log_y_axis": false,
    "fix_y_axis": true,
    "show_station_map": true,
    "load_station_timeseries_obs": false,
    "show_station_timeseries_obs": false,
    "show_station_timeseries_mod": false,
    "show_station_timeseries_com": true,
    "save_plot_format": "${PLOTEXTENSION}",
    "save_data_format": "nc",
    "multiprocessing": ${MULTIPROCESSING:-false},
    "n_threads": ${N_THREADS:-4},
    "debug": ${DEBUG:-false},
    "global_attributes": {
      "title": "Air pollutants over ${REGION:-""}, ${myvar_list_string}",
      "summary": "netCDF output: Collocated model and observation data for selected stations.",
      "author": "$(echo $USER)",
      "history": "Processed for CAMS2_35bis (qlc_v${QLC_VERSION})",
      "Conventions": "CF-1.8"
    }
  }
]
EOM

log "Generated temporary config file for qlc-py: ${temp_config_file}"

# Execute qlc-py with the temporary config file.
# Note: qlc-py expects the config via stdin when using '--config -'
log "Executing qlc-py with the multi-entry config file..."
qlc-py --config "${temp_config_file}"

# After the run, find the specific final collocation plot(s) and add them to the TeX list.
log "Searching for final collocation plots in ${hpath}..."
rm -f "$texPlotsfile" # Start with an empty list
touch "$texPlotsfile" # Ensure the file exists before grep is called

# Loop through each variable to control the order of plots in the TeX file
for var in "${myvar_list_array[@]}"; do
    log "Ordering plots for variable: $var"

    # Helper function to find a plot and add it to the list if it exists and is not already there
    add_plot_if_found() {
        local plot_pattern=$1
        # Use find and sort to ensure a consistent order if multiple files match
        find "${hpath}" -maxdepth 1 -type f -name "${plot_pattern}" 2>/dev/null | sort | while IFS= read -r plot_file; do
            if [ -n "$plot_file" ] && ! grep -qF "$plot_file" "$texPlotsfile"; then
                echo "$plot_file" >> "$texPlotsfile"
                log "Added plot to TeX list: $plot_file"
            fi
        done
    }

    # Find plots in the specified order using more precise patterns
    # 1. Time series plots (individual experiments first, then collocated)
    add_plot_if_found "*${var}*collocated*regional_mean*.${PLOTEXTENSION}"
    
    # 2. Bias plot
    add_plot_if_found "*${var}*collocated*regional_bias*.${PLOTEXTENSION}"
    
    # 3. All statistics plots
    add_plot_if_found "*${var}*collocated*stats_plot_Error_Metrics*.${PLOTEXTENSION}"
    add_plot_if_found "*${var}*collocated*stats_plot_Correlation_Metrics*.${PLOTEXTENSION}"
    add_plot_if_found "*${var}*collocated*stats_plot_Descriptive_Statistics*.${PLOTEXTENSION}"

    # 4. Value map plots (individual experiments)
    add_plot_if_found "*${var}*val.${PLOTEXTENSION}"
    
done

# ----------------------------------------------------------------------------------------
# Generate a .tex file with frames for each plot found, for inclusion in the final presentation.
# ----------------------------------------------------------------------------------------
log "Generating TeX file for plots: ${texFile}"

# Create the main .tex file for this section with a subsection header
tQLTYPE=$(echo "$QLTYPE" | sed 's/_/\\_/g')
cat > "$texFile" <<EOF
%===============================================================================
\subsection{${tQLTYPE} -- ${mDate} (${TIME_AVERAGE})}
EOF

# Loop through the found plot files and generate a TeX frame for each
if [ -s "$texPlotsfile" ]; then
  # Read from the ordered file list
  while IFS= read -r plot_path; do
    plot_filename=$(basename -- "$plot_path")
    var_name_tex=""
    title_prefix=""

    # Extract the variable name for the title
    for var in "${myvar_list_array[@]}"; do
        if [[ "$plot_filename" == *"${var}"* ]]; then
            var_name_tex=$(echo "$var" | sed 's/_/\\_/g')
            break
        fi
    done

    # Use a case statement for robust title generation
    case "$plot_filename" in
        *regional_bias*)
            title_prefix="Collocation time series bias" ;;
        *stats_plot_Error_Metrics*)
            title_prefix="Collocation error stats" ;;
        *stats_plot_Correlation_Metrics*)
            title_prefix="Collocation correlation stats" ;;
        *stats_plot_Descriptive_Statistics*)
            title_prefix="Collocation descriptive stats" ;;
        *val.*)
            title_prefix="Collocation map value plot" ;;
        *regional_mean*)
            title_prefix="Collocation time series" ;;
        *)
            title_prefix="Collocation station plot" ;;
    esac
    
    title_final="${title_prefix} for ${var_name_tex} of ${exp1} vs ${exp2}"

    # Append the frame to the main .tex file
    cat >> "$texFile" <<EOF
%===============================================================================
\frame{
\frametitle{${title_final}}
\vspace{0mm}
\centering
\includegraphics[width=0.9\textwidth]{${plot_path}}
}
EOF
    log "Generated TeX frame for $plot_filename"
  done < "$texPlotsfile"
  log "Finished generating TeX file."
  log "${texFile}"
  cat  "${texFile}"
else
  log "No plots found to generate TeX file."
fi

# ----------------------------------------------------------------------------------------
# End of TeX file generation
# ----------------------------------------------------------------------------------------

log "$ANALYSIS_DIRECTORY"
log "$PLOTS_DIRECTORY"

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0
