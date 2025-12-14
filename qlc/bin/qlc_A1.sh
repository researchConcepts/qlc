#!/bin/bash -e

# Source the configuration file to load the settings
. "$CONFIG_FILE"
# Include common functions
source $FUNCTIONS

SCRIPT="$0"
 log  "________________________________________________________________________________________"
 log  "Start ${SCRIPT} at `date`"
 log  "Retrieve grib data from MARS archive considering selected nml files (see $CONFIG_FILE)  "
#log  "----------------------------------------------------------------------------------------"
#log  "Copyright (c) 2021-2025 ResearchConcepts io GmbH. All Rights Reserved.                  "
#log  "Questions / comments to: Swen M. Metzger <sm@researchconcepts.io>                       "
 log  "----------------------------------------------------------------------------------------"

log "$0 MARS_RETRIEVALS = $CONFIG_DIR nml files: ${MARS_RETRIEVALS[*]}"
pwd -P

# ----------------------------------------------------------------------------------------
# Parse command line arguments: <exp1> <exp2> ... <expN> <start_date> <end_date> [config]
# ----------------------------------------------------------------------------------------
# Use common parsing function from qlc_common_functions.sh
# Sets: experiments (array), sDat, eDat, config_arg
parse_qlc_arguments "$@" || exit 1

myOS="`uname -s`"

# Process each experiment
for exp in "${experiments[@]}"; do
  log "Processing experiment: $exp - class: ${XCLASS}"

  # Create experiment directory if not existent
  if [ ! -d "$MARS_RETRIEVAL_DIRECTORY/$exp" ]; then
    mkdir -p $MARS_RETRIEVAL_DIRECTORY/$exp
  fi

  # Map the experiment prefix to the corresponding ECMWF MARS class.
  # This is required for retrieving data from the MARS archive.
  EXPCLASS=$(echo "${exp}" | cut -c 1)
 
  # For experiments other than 'nl', 'be', or 'rd', please uncomment the corresponding XCLASS line.
  case "${EXPCLASS}" in
    a) XCLASS="be" ;;  # Belgium
    b) XCLASS="nl" ;;  # Netherlands
#     c) XCLASS="fr" ;;  # France
#     d) XCLASS="de" ;;  # Germany
#     e) XCLASS="es" ;;  # Spain
#     f) XCLASS="fi" ;;  # Finland
#     g) XCLASS="gr" ;;  # Greece
#     h) XCLASS="hu" ;;  # Hungary
#     i) XCLASS="it" ;;  # Italy
#     k) XCLASS="dk" ;;  # Denmark
#     l) XCLASS="pt" ;;  # Portugal
#     m) XCLASS="at" ;;  # Austria
#     n) XCLASS="no" ;;  # Norway
#     s) XCLASS="se" ;;  # Sweden
#     t) XCLASS="tr" ;;  # Turkey
#     u) XCLASS="uk" ;;  # United Kingdom
#     w) XCLASS="ch" ;;  # Switzerland
    *) XCLASS="rd" ;;  # Default to Research Department
  esac
 
  # --------------------------------------------------------------------
  # 2. MARS request for sfc data
  for name in "${MARS_RETRIEVALS[@]}"; do
    nml_name="mars_${name}.nml"
    log "Processing subscript: $nml_name"

    if [ -f "$NAMELIST_DIR/$nml_name" ]; then
      nml_template="$NAMELIST_DIR/$nml_name"
      nml_file="$MARS_RETRIEVAL_DIRECTORY/$exp/$nml_name"

      # Create a unique flag for this experiment and time period
      data_retrieved_flag="$MARS_RETRIEVAL_DIRECTORY/$exp/data_retrieved_${exp}_${sDat}-${eDat}_${name}.flag"

      # Replace placeholders in the namelist file to extract target information
      # EXP, SDATE, EDATE, MYPATH, MYFILE
      temp_nml=$(mktemp)
      sed -e "s/= EXP,/= $exp,/g" \
          -e "s/= XCLASS/= $XCLASS/g" \
          -e "s/= SDATE/= $sDat/g" \
          -e "s|o/EDATE|o/$eDat|g" \
          -e "s/MYFILE_/$exp\_${sDat//[-:]/}-${eDat//[-:]/}_/g" \
          -e "s|MYPATH/|${MARS_RETRIEVAL_DIRECTORY}/$exp/|g" \
           "$nml_template" > "$temp_nml"
      
      # Extract the 'target' value to check if files exist
      target=$(awk -F'=' '/target/ {gsub("\"", "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' "$temp_nml")
      
      # Check for the control file and actual data files in the mars retrieval directory
      if [ -f "$data_retrieved_flag" ]; then
        ls -lh "$data_retrieved_flag"
        
        # Check if the actual grb files exist (support wildcards in target path)
        grb_files_exist=false
        if [ -n "$target" ]; then
          # Check for files matching the target pattern
          if ls $target 2>/dev/null | head -n 1 | grep -q .; then
            grb_files_exist=true
            log "Data files found: $target"
            ls -lh $target 2>/dev/null | head -5
          fi
        fi
        
        if [ "$grb_files_exist" = true ]; then
          log "Data retrieval completed for experiment $exp and namelist case $name"
          log "Found existing grb files. Skipping retrieval for case $name"
        else
          log "Data retrieval in progress for experiment $exp and namelist case $name"
          log "Flag exists but grb files not yet available. Skipping re-submission for case $name"
        fi
      else
        log "Data has not been retrieved. Calling script:"
        log "$0 for data retrieval for experiment $exp and namelist case $name"
        
        # Use the already processed namelist
        nml_file="$MARS_RETRIEVAL_DIRECTORY/$exp/$nml_name"
        cp "$temp_nml" "$nml_file"
        log "$nml_file" 
        cat "$nml_file"  # Print the modified namelist
        log MARS_RETRIEVAL_DIRECTORY $MARS_RETRIEVAL_DIRECTORY
		  log "mars target file: $target"

        # Create a batch job script
        MARS_BATCH_SCRIPT="$MARS_RETRIEVAL_DIRECTORY/$exp/mars_$exp_$name.sh"
        cat > "$MARS_BATCH_SCRIPT" <<EOF
#!/bin/ksh -e
#SBATCH --job-name=mars_$exp_$name.sh
#SBATCH --output=log-%J.out
#SBATCH --error=err-%J.out
mars < "$nml_file"
EOF

        log "----------------------------------------------------------------------------------------"
        cat  "$MARS_BATCH_SCRIPT"
        log "----------------------------------------------------------------------------------------"
        log " $MARS_BATCH_SCRIPT"
        
        # Check if pdflatex exists
        if ! command_exists sbatch; then
          log "Caution: sbatch command not found" >&2
          log "Not submitting MARS request on $myOS ..."
#         exit 1
        else
          log  "Success: sbatch command found"
          log  "Submitting MARS request on $myOS:"
          which sbatch mars squeue scancel
          sbatch "$MARS_BATCH_SCRIPT"
          squeue -u "$USER"
        fi

        # Create the control file in the retrieval directory
        touch $data_retrieved_flag
        log "----------------------------------------------------------------------------------------"
      fi
      
      # Cleanup temporary namelist file
      rm -f "$temp_nml"
    else
      log "Error: $nml_name not found in $CONFIG_DIR"
    fi
  done # name
  log "$MARS_RETRIEVAL_DIRECTORY/$exp"
done # exps

log  "----------------------------------------------------------------------------------------"
log  "End ${SCRIPT} at `date`"
log  "________________________________________________________________________________________"

exit 0

