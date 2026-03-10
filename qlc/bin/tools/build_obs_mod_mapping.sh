#!/usr/bin/env bash
# ============================================================================
# build_obs_mod_mapping.sh
# ============================================================================
# Generates an obs-model variable mapping reference for all (or one) QLC
# observation networks.  For each obs variable it runs 'qlc-vars search' to
# find matching IFS variables and writes the results to:
#   ~/qlc/config/tables/obs_mod_mapping_examples.conf
#
# Usage:
#   ./build_obs_mod_mapping.sh [network_name|all]
#
# Examples:
#   ./build_obs_mod_mapping.sh all
#   ./build_obs_mod_mapping.sh nc_brazil_inmet
#   ./build_obs_mod_mapping.sh ver0d_ebas_daily
#
# The output file is a plain-text reference – it is NOT sourced by QLC at
# runtime.  Use it to review suggested mappings and copy the relevant
# REGION_*_VARIABLES lines into the workflow config.
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths (output file resolved after argument parsing below)
# ---------------------------------------------------------------------------
OBS_DB_DIR="${HOME}/qlc/config/tables/obs_database"
TABLES_DIR="${HOME}/qlc/config/tables"
VENV_ACTIVATE="${HOME}/venv/qlc-dev/bin/activate"

# ---------------------------------------------------------------------------
# Known-good obs_native_name → IFS variable mappings
# Verified against qlc-vars and the QLC variable table.
# Format: obs_native_name:ifs_var_name
# These take priority over the generic qlc-vars search result.
# ---------------------------------------------------------------------------
declare -A KNOWN_MAPPING=(
    # Meteorological - 2m / surface
    ["temp"]="2t"
    ["temperature"]="2t"
    ["TEMP"]="2t"
    ["T2"]="2t"
    ["rh"]="2rhw"
    ["RHUM"]="2rhw"
    ["relative_humidity"]="2rhw"
    ["dewpoint"]="2d"
    ["dew_point"]="2d"
    ["dewpoint_temperature"]="2d"
    ["pressure"]="sp"
    ["BARPR"]="sp"
    ["station_pressure"]="sp"
    ["mslp"]="msl"
    ["radiation"]="ssrd"
    ["SRAD"]="ssrd"
    ["solar_radiation"]="ssrd"
    ["wind_speed"]="10si"
    ["WS"]="10si"
    ["wind_gust"]="10fg"
    ["wind_dir"]=""           # vector/directional: no scalar IFS field
    ["WD"]=""
    ["precip"]="tp"
    ["PRECIP"]="tp"
    ["precipitation"]="tp"
    # AQ gases - surface mass mixing ratio
    ["O3"]="go3"
    ["o3"]="go3"
    ["ozone"]="go3"
    ["OZONE"]="go3"
    ["NO2"]="no2"
    ["no2"]="no2"
    ["nitrogen_dioxide_density"]="no2"
    ["SO2"]="so2"
    ["so2"]="so2"
    ["sulphur_dioxide_density"]="so2"
    ["CO"]="co"
    ["co"]="co"
    ["carbon_monoxide"]="co"
    ["NO"]="no"
    ["no"]="no"
    ["NOX"]=""                # derived: NO+NO2, no direct MARS field
    ["NOx"]=""
    ["NOY"]=""                # total reactive nitrogen, no single field
    ["NOY_NO"]=""
    ["NO2Y"]=""
    ["NH3"]="nh3"
    ["nh3"]="nh3"
    ["ammonia_density"]="nh3"
    ["HNO3"]="hno3"
    ["hno3"]="hno3"
    ["nitric_acid_density"]="hno3"
    ["PAN"]="pan"
    # AQ aerosols - surface mass concentration (kg/m3 → ug/m3 via *,1e9)
    ["PM2.5"]="pm2p5"
    ["pm2p5"]="pm2p5"
    ["PM10"]="pm10"
    ["pm10"]="pm10"
    ["PM1"]="pm1"
    ["pm1"]="pm1"
    ["PM2.5_density"]="pm2p5"
    ["PM10_density"]="pm10"
    ["PM1_density"]="pm1"
    # Aerosol optical depth
    ["AOD"]="aod550"
    ["AOD550"]="aod550"
    ["aod"]="aod550"
    # CASTNET / NNDMN / EBAS dry aerosol components (all kg/m3 → ug/m3)
    ["NH4_CONC"]="nh4"
    ["dry_aerosol_ammonium_density"]="nh4"
    ["NH4_as"]="nh4"
    ["NO3_CONC"]="no3_a"
    ["dry_aerosol_nitrate_density"]="no3_a"
    # SO4 aerosol: IFS AER=aermr11, HAMM7 has different code - no clean single entry, leave REVIEW
    ["SO4_CONC"]=""           # SO4 aerosol: REVIEW - IFS AER=aermr11, no single canonical name
    ["dry_aerosol_sulphate_corrected_density"]=""  # REVIEW - same issue as SO4_CONC
    ["HNO3_CONC"]="hno3"
    ["BC"]=""                 # black carbon: IFS aermr09+aermr10 (combined) - REVIEW
    # EBAS additional
    ["nitrogen_monoxide_density"]="no"
    ["ozone_density"]="go3"
    ["ozone_mole_fraction"]="go3"
    ["nitrogen_dioxide_mole_fraction"]="no2"
    ["sulphur_dioxide_mole_fraction"]="so2"
    ["carbon_monoxide_mole_fraction"]="co"
    ["nitric_acid_density"]="hno3"
)

# ---------------------------------------------------------------------------
# Activate venv so that qlc-vars is available
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
source "${VENV_ACTIVATE}" 2>/dev/null || {
    echo "[ERROR] Failed to activate venv: ${VENV_ACTIVATE}" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------
NETWORK_FILTER="${1:-all}"

# Output file: per-network when a specific network is given, combined for "all"
if [[ "${NETWORK_FILTER}" == "all" ]]; then
    OUTPUT_FILE="${TABLES_DIR}/obs_mod_mapping_examples.conf"
else
    OUTPUT_FILE="${TABLES_DIR}/obs_mod_mapping_examples_${NETWORK_FILTER}.conf"
fi

# ---------------------------------------------------------------------------
# Collect CSV files to process
# ---------------------------------------------------------------------------
declare -a CSV_FILES=()
if [[ "${NETWORK_FILTER}" == "all" ]]; then
    while IFS= read -r -d '' f; do
        CSV_FILES+=("$f")
    done < <(find "${OBS_DB_DIR}" -maxdepth 1 -name "*_variables.csv" -print0 | sort -z)
else
    target="${OBS_DB_DIR}/${NETWORK_FILTER}_variables.csv"
    [[ -f "${target}" ]] || {
        echo "[ERROR] Obs variable file not found: ${target}" >&2
        exit 1
    }
    CSV_FILES+=("${target}")
fi

[[ ${#CSV_FILES[@]} -gt 0 ]] || {
    echo "[ERROR] No obs variable CSV files found in: ${OBS_DB_DIR}" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Helper: suggest unit conversion field from obs unit + IFS unit
# Returns: empty string (no conversion) or ",op,value"
# ---------------------------------------------------------------------------
suggest_model_transform() {
    local obs_unit="$1"
    local ifs_unit="$2"
    # Pressure: Pa → hPa (IFS unit contains "Pa" and obs is hPa/mbar)
    if [[ "${obs_unit}" =~ ^(hPa|mbar|millibar)$ ]] && [[ "${ifs_unit}" =~ Pa ]]; then
        echo "*,0.01"
        return
    fi
    # Mass concentration: kg m-3 → ug/m3 (IFS stores PM as kg m-3)
    # Match "kg m-3" as full unit string
    if [[ "${obs_unit}" =~ ^(ug/m3|µg/m3|ug\ m-3)$ ]] && [[ "${ifs_unit}" == "kg m-3" ]]; then
        echo "*,1e9"
        return
    fi
    # Radiation: J m-2 → kJ/m2
    if [[ "${obs_unit}" =~ ^(kJ/m2|kJ\ m-2)$ ]] && [[ "${ifs_unit}" == "J m-2" ]]; then
        echo "*,0.001"
        return
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Helper: suggest target unit (what the output should be in)
# ---------------------------------------------------------------------------
suggest_target_unit() {
    local obs_unit="$1"
    case "${obs_unit}" in
        degC|celsius|Celsius)    echo "degC" ;;
        percent|pct|"%" )        echo "%" ;;
        hPa|mbar|millibar)       echo "hPa" ;;
        "kJ/m2"|"kJ m-2")        echo "kJ/m2" ;;
        "m/s"|"m s-1")           echo "m/s" ;;
        "ug/m3"|"µg/m3"|"ug m-3") echo "ug/m3" ;;
        K)                       echo "K" ;;
        ppb)                     echo "ppb" ;;
        ppm)                     echo "ppm" ;;
        *)                       echo "N/A" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: capitalise first letter for a display name
# ---------------------------------------------------------------------------
display_name_from_native() {
    local native="$1"
    # Capitalise first char; keep rest; replace underscores with nothing
    python3 -c "
n = '${native}'
parts = n.split('_')
out = ''.join(p.capitalize() for p in parts)
print(out)
" 2>/dev/null || echo "${native}"
}

# ---------------------------------------------------------------------------
# Helper: extract unit field from a fixed-width qlc-vars output line.
# Column layout (0-indexed): ID=0-25, Source=26-45, Param=46-61, Unit=62-77, Desc=78+
# Using cut (1-indexed): Unit = columns 63-78.
# Trims leading/trailing whitespace.
# ---------------------------------------------------------------------------
extract_unit_field() {
    echo "$1" | cut -c63-78 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# Helper: parse one fixed-width qlc-vars output line into globals.
# ---------------------------------------------------------------------------
parse_ifs_line() {
    local line="$1"
    MATCH_ID="$(    echo "${line}" | awk '{print $1}')"
    MATCH_PARAM="$( echo "${line}" | awk '{print $3}')"
    MATCH_UNIT="$(  extract_unit_field "${line}")"
    MATCH_DESC="$(  echo "${line}" | cut -c79- | sed 's/^[[:space:]]*//')"
}

# ---------------------------------------------------------------------------
# Helper: look up an IFS variable by exact name.
# Strategy: run 'qlc-vars search <name>' and find the line whose first column
# exactly matches <name> in the ifs source.  Falls back to first ifs hit.
# Sets globals: MATCH_ID, MATCH_PARAM, MATCH_UNIT, MATCH_DESC, MATCH_ALT_LINES
# Returns 0 on match, 1 when not found.
# ---------------------------------------------------------------------------
lookup_ifs_info() {
    local ifs_name="$1"
    MATCH_ID="" ; MATCH_PARAM="" ; MATCH_UNIT="" ; MATCH_DESC="" ; MATCH_ALT_LINES=""
    [[ -z "${ifs_name}" ]] && return 1

    # First: try exact name match in IFS tables only (fast O(1) lookup, no obs tables loaded)
    local exact_raw
    exact_raw="$(qlc-vars search "${ifs_name}" --exact --source ifs 2>/dev/null)" || true

    local ifs_lines=""
    if [[ -n "${exact_raw}" ]]; then
        ifs_lines="$(echo "${exact_raw}" | grep -E '\s+ifs\s+' || true)"
    fi

    # Fallback: fuzzy search in IFS tables only when exact fails (e.g. name not in index)
    if [[ -z "${ifs_lines}" ]]; then
        local fuzzy_raw
        fuzzy_raw="$(qlc-vars search "${ifs_name}" --source ifs 2>/dev/null)" || true
        ifs_lines="$(echo "${fuzzy_raw}" | grep -E '\s+ifs\s+' || true)"
    fi

    [[ -n "${ifs_lines}" ]] || return 1

    # Within fuzzy results prefer the line whose column-1 equals ifs_name exactly
    local exact_line
    exact_line="$(echo "${ifs_lines}" | awk -v name="${ifs_name}" '$1 == name' | head -1 || true)"
    local best_line="${exact_line:-$(echo "${ifs_lines}" | head -1)}"

    parse_ifs_line "${best_line}"
    MATCH_ALT_LINES="$(echo "${ifs_lines}" | head -3)"
    [[ -n "${MATCH_ID}" ]] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# Helper: generic search in qlc-vars, returns first IFS hit.
# Sets globals: MATCH_ID, MATCH_PARAM, MATCH_UNIT, MATCH_DESC, MATCH_ALT_LINES
# Returns 0 on match, 1 when nothing found.
# ---------------------------------------------------------------------------
search_ifs_match() {
    local term="$1"
    MATCH_ID="" ; MATCH_PARAM="" ; MATCH_UNIT="" ; MATCH_DESC="" ; MATCH_ALT_LINES=""
    local raw
    # Restrict to ifs source: avoids loading obs tables and prevents obs-table false positives
    raw="$(qlc-vars search "${term}" --source ifs 2>/dev/null)" || true
    local ifs_lines
    ifs_lines="$(echo "${raw}" | grep -E '\s+ifs\s+' || true)"
    [[ -n "${ifs_lines}" ]] || return 1
    MATCH_ALT_LINES="$(echo "${ifs_lines}" | head -3)"
    local first_line
    first_line="$(echo "${ifs_lines}" | head -n1)"
    parse_ifs_line "${first_line}"
    [[ -n "${MATCH_ID}" ]] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# Write output header
# ---------------------------------------------------------------------------
write_header() {
    cat > "${OUTPUT_FILE}" << 'HEADER'
# ============================================================================
# QLC Obs-Model Variable Mapping Reference
# ============================================================================
# Auto-generated by build_obs_mod_mapping.sh
# DO NOT source this file in QLC scripts – it is a human-readable reference.
#
# Format of each suggested mapping line:
#   REGION_<NETWORK>_VARIABLES="DisplayName|modVar[,op,val]|obsVar|targetUnit"
#
# Where:
#   DisplayName : label used in plot titles and file names
#   modVar      : IFS variable name (optionally with ,op,val for scaling)
#   obsVar      : native obs variable name (from obs network CSV)
#   targetUnit  : desired output unit for both model and obs
#   op,val      : transform applied to model field before unit comparison
#                 *,1e9  = multiply by 1e9  (kg/m3 → ug/m3)
#                 *,0.01 = multiply by 0.01 (Pa    → hPa)
#                 *,0.001= multiply by 0.001(J/m2  → kJ/m2)
#
# Variables with no IFS match are listed as comments under # NO_MATCH.
# Variables needing model-side unit conversion beyond a simple factor
# (e.g. kg/kg → ug/m3 via mol-weight) are flagged # REVIEW_UNITS.
#
# Station file convention:
#   ${QLC_HOME}/config/station_locations/<dataset_type>_stations-<filter>.csv
#   where filter = all | rural | urban | test
# ============================================================================

HEADER
    echo "[INFO] Writing to: ${OUTPUT_FILE}"
}

# ---------------------------------------------------------------------------
# Process one obs network CSV
# ---------------------------------------------------------------------------
process_network() {
    local csv_file="$1"
    local basename
    basename="$(basename "${csv_file}" _variables.csv)"

    # Count variables (exclude header)
    local var_count
    var_count="$(tail -n +2 "${csv_file}" | grep -c '.' || true)"

    {
        echo ""
        echo "# ============================================================================"
        echo "# NETWORK: ${basename}  (${var_count} variables)"
        echo "# OBS_DATASET_TYPE: ${basename}"
        echo "# STATION_FILE: \${QLC_HOME}/config/station_locations/${basename}_stations-{all|rural|urban|test}.csv"
        echo "# ============================================================================"
        echo "#"
        printf "# %-26s %-12s %-18s %-10s %-14s %s\n" "obs_var" "obs_unit" "ifs_var" "grib" "ifs_unit" "suggested_mapping"
        echo "# $(printf '%.0s-' {1..105})"

        declare -a MAPPABLE=()
        declare -a NO_MATCH=()
        declare -a REVIEW_UNITS=()

        # Read CSV: skip header
        while IFS=',' read -r var native unit rest; do
            [[ "${var}" == "variable" ]] && continue  # skip CSV header
            [[ -z "${var}" ]] && continue

            # 1. Check known-good lookup table first
            local known_ifs="${KNOWN_MAPPING[${native}]:-}"
            [[ -z "${known_ifs}" ]] && known_ifs="${KNOWN_MAPPING[${var}]:-}"

            local matched=0
            local source_note=""

            if [[ -n "${known_ifs}" ]]; then
                # Explicit skip (empty string in table = no IFS counterpart)
                if [[ "${known_ifs}" == "" ]]; then
                    NO_MATCH+=("${var}")
                    printf "# %-26s %-12s %-18s %-10s %-14s %s\n" \
                        "${var}" "${unit}" "-" "-" "-" "# NO_MATCH (directional/derived)"
                    continue
                fi
                if lookup_ifs_info "${known_ifs}"; then
                    matched=1
                    source_note="[known]"
                fi
            fi

            # 2. Fallback: generic search by native name, then var name
            if [[ "${matched}" -eq 0 ]]; then
                for search_term in "${native}" "${var}"; do
                    if search_ifs_match "${search_term}"; then
                        matched=1
                        source_note="[search]"
                        break
                    fi
                done
            fi

            if [[ "${matched}" -eq 0 ]]; then
                NO_MATCH+=("${var}")
                printf "# %-26s %-12s %-18s %-10s %-14s %s\n" \
                    "${var}" "${unit}" "-" "-" "-" "# NO_MATCH"
                continue
            fi

            # Print alternative IFS matches as context (indented under the main line)
            if [[ -n "${MATCH_ALT_LINES}" ]]; then
                while IFS= read -r alt_line; do
                    local alt_id alt_param alt_unit
                    alt_id="$(   echo "${alt_line}" | awk '{print $1}')"
                    alt_param="$(echo "${alt_line}" | awk '{print $3}')"
                    alt_unit="$( echo "${alt_line}" | awk '{print $4}')"
                    [[ "${alt_id}" != "${MATCH_ID}" ]] && \
                        printf "#   alt: %-22s param=%-10s unit=%s\n" "${alt_id}" "${alt_param}" "${alt_unit}"
                done <<< "${MATCH_ALT_LINES}"
            fi

            # Determine transform and target unit
            local transform
            transform="$(suggest_model_transform "${unit}" "${MATCH_UNIT}")"
            local target_unit
            target_unit="$(suggest_target_unit "${unit}")"

            # Build mod_var field (with optional transform)
            local mod_field="${MATCH_ID}"
            [[ -n "${transform}" ]] && mod_field="${MATCH_ID},${transform}"

            # Display name from native variable name
            local display
            display="$(display_name_from_native "${native}")"

            local mapping="${display}|${mod_field}|${native}|${target_unit}"

            # Flag cases where kg/kg IFS needs mol-weight conversion (gas → ug/m3 or ppb/ppm)
            local flag=""
            local needs_review=0
            if [[ "${unit}" =~ ^(ug/m3|µg/m3)$ ]] && [[ "${MATCH_UNIT}" == "kg kg-1" ]]; then
                needs_review=1
            elif [[ "${unit}" =~ ^(ppb|ppm)$ ]] && [[ "${MATCH_UNIT}" == "kg kg-1" ]]; then
                needs_review=1
            fi
            if [[ "${needs_review}" -eq 1 ]]; then
                flag="# REVIEW_UNITS: IFS kg/kg - unit conv via convert_units (mol-weight)"
                REVIEW_UNITS+=("${var}")
                MAPPABLE+=("${mapping}")  # still include in suggestion, needs runtime unit conv
            else
                MAPPABLE+=("${mapping}")
            fi

            printf "# %-26s %-12s %-18s %-10s %-14s %s %s %s\n" \
                "${var}" "${unit}" "${MATCH_ID}" "${MATCH_PARAM}" "${MATCH_UNIT}" \
                "${mapping}" "${source_note}" "${flag}"
        done < "${csv_file}"

        echo "#"

        # Suggested active VARIABLES line (mappable only)
        if [[ ${#MAPPABLE[@]} -gt 0 ]]; then
            local IFS_SEP=";"
            local joined
            joined="$(IFS=";"; echo "${MAPPABLE[*]}")"
            echo "# Suggested (mappable variables only):"
            echo "#REGION_$(echo "${basename}" | tr '[:lower:]' '[:upper:]')_VARIABLES=\"${joined}\""
        fi

        # Report skipped
        if [[ ${#NO_MATCH[@]} -gt 0 ]]; then
            echo "# NO_MATCH (no IFS counterpart found): ${NO_MATCH[*]}"
        fi
        if [[ ${#REVIEW_UNITS[@]} -gt 0 ]]; then
            echo "# REVIEW_UNITS (mol-weight conversion needed): ${REVIEW_UNITS[*]}"
        fi

    } >> "${OUTPUT_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
write_header

echo "[INFO] Processing ${#CSV_FILES[@]} network(s) ..."
for csv in "${CSV_FILES[@]}"; do
    net="$(basename "${csv}" _variables.csv)"
    echo "[INFO] -> ${net}"
    process_network "${csv}"
done

echo ""
echo "[INFO] Done. Output: ${OUTPUT_FILE}"
