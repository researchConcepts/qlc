# Third-Party Data and Licenses

This document describes third-party data sources that can be processed using QLC tools.

---

## GHOST Observation Data

**Globally Harmonised Observations in Space and Time (GHOST)**

### Citation

Bowdalo, D. R., Mozaffar, A., Witt, M. L. I., Arteta, J., Bañón, G., Bennouna, Y., Bevacqua, C., Blechschmidt, A.-M., Boldeanu, M., Darras, S., Dominko, N., Eskes, H., Guevara, M., Karolien, N., Langerock, B., Liu, J., Marquardt, T., Meissen, M., Munro, R., Paschalidi, Z., Rodwell, M., Selvaratnam, V., Signorini, M., Souza, C., Swain, S., Veefkind, P., Wagner, A., Whyatt, J. D., Boersma, K. F., and Bennouna, Y.: Globally Harmonised Observations in Space and Time (GHOST), Earth Syst. Sci. Data, 16, 4417–4441, https://doi.org/10.5194/essd-16-4417-2024, 2024.

### Data Access

- **Primary Source**: https://zenodo.org/records/15075961
- **DOI**: 10.5281/zenodo.15075961
- **Format**: NetCDF files organized by network and frequency

### License

**CC BY 4.0** (Creative Commons Attribution 4.0 International)

- **Full Text**: https://creativecommons.org/licenses/by/4.0/
- **Summary**: You are free to share and adapt the data, with appropriate credit to the authors
- **Requirements**: 
  - Attribution must be given to the creators
  - Indicate if changes were made
  - No additional restrictions may be applied

### QLC Tools for GHOST Data

QLC provides convenience tools to organize GHOST data for air quality model evaluation:

- `qlc/bin/tools/qlc_extract_all_ghost_networks.sh` - Batch extraction for all GHOST networks
- `qlc/bin/tools/qlc_extract_all_station_metadata.sh` - Station metadata extraction (all networks)
- `qlc/bin/tools/qlc_generate_all_station_locations.sh` - Station location file generation

**Important Notes**:
1. These tools are part of QLC (MIT License) and are NOT part of the GHOST project
2. The tools process GHOST data but do not contain or redistribute GHOST data
3. Users must download GHOST data separately from Zenodo
4. Users must comply with CC BY 4.0 license terms when using GHOST data
5. **Users MUST cite GHOST** (Bowdalo et al., 2024) when publishing results using GHOST data

### Supported GHOST Networks

QLC tools support extraction and organization of 25 GHOST networks:

**Main Network**:
- GHOST Harmonized (200+ aerosol optical properties)

**Regional Networks** (7):
- ghost-ebas (European monitoring, 89 variables)
- ghost-aqs (US EPA, 43 variables)
- ghost-airbase (European airbase, 57 variables)
- ghost-castnet (US CASTNET, 10 variables)
- ghost-naps (Canadian, 42 variables)
- ghost-uk_air (UK, 31 variables)
- ghost-japan_nies (Japanese, 10 variables)

**Additional Networks** (17):
- AERONET (2 levels), EBAS variants (12 networks), EEA, INDAAF, WMO_WDCPC

---

## How to Cite

If you use QLC with GHOST data in your research, please cite both:

### 1. QLC Tool

```
QLC (Quick Look Content) v1.0.2, 2026,
An Automated Model-Observation Comparison Suite Optimized for CAMS,
qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>,
ResearchConcepts io GmbH, https://docs.researchconcepts.io/qlc/
```

### 2. GHOST Data

```
Bowdalo, D. R., et al. (2024): Globally Harmonised Observations in Space and 
Time (GHOST), Earth Syst. Sci. Data, 16, 4417-4441, 
https://doi.org/10.5194/essd-16-4417-2024
```

### Example Acknowledgment

```
Observational data for model evaluation was obtained from the GHOST database 
(Bowdalo et al., 2024) and processed using the QLC tool [citation].
```

---

## Evaltools (Statistical Analysis)

**CNRM Open Source Site by CNRS and Météo-France**

### About

Evaltools is a statistical analysis package developed by CNRM (Centre National de Recherches Météorologiques) for model evaluation and scoring.

### References

- **Project Page**: https://redmine.umr-cnrm.fr/projects/evaltools/wiki
- **Developer**: CNRS and Météo-France
- **QLC Integration**: Available via `qlc-install-extras --evaltools`
- **Workflow**: `~/qlc/config/workflows/evaltools/`

### QLC Usage

QLC integrates evaltools for advanced statistical analysis including:
- Time series comparisons
- Station score maps
- Taylor diagrams
- Scatter plots
- Diurnal cycle analysis
- Exceedance plots

**Note**: Evaltools is an optional component. Install separately: `qlc-install-extras --evaltools`

---

## PyFerret (Advanced Visualization)

**The PyFerret program and Python module from NOAA/PMEL**

### About

PyFerret is a Python-based version of Ferret, a powerful analysis and visualization tool developed by NOAA's Pacific Marine Environmental Laboratory (PMEL).

### References

- **GitHub**: https://github.com/NOAA-PMEL/PyFerret
- **Website**: https://ferret.pmel.noaa.gov/Ferret/
- **Developer**: NOAA/PMEL (National Oceanic and Atmospheric Administration / Pacific Marine Environmental Laboratory)
- **QLC Integration**: Available via `qlc-install-extras --pyferret`
- **Workflow**: `~/qlc/config/workflows/pyferret/`

### QLC Usage

QLC integrates PyFerret for advanced 3D visualization and analysis:
- Three-dimensional quick-look plots
- Model comparison visualization
- Advanced data analysis capabilities

**Note**: PyFerret is an optional component. Install separately: `qlc-install-extras --pyferret`

---

## Other Data Sources

QLC also supports processing data from:

- **AirNow** (US EPA real-time air quality)
- **EBAS** (European monitoring, daily and hourly)
- **AirBase** (European air quality database)
- **AMoN, CastNet, NNDMN** (US observation networks)
- **Brazil INMET** (National meteorological stations)
- **Brazil AQ / São Paulo CETESB** (Brazilian air quality networks)

Each data source has its own license and citation requirements. Please consult the respective data providers for licensing details.

---

## Documentation

**Complete QLC documentation available at:**
- https://docs.researchconcepts.io/qlc/latest/
- https://docs.researchconcepts.io/qlc/latest/user-guide/usage/
- https://github.com/researchConcepts/qlc
- https://pypi.org/project/rc-qlc/

---

## Questions

For questions about:
- **GHOST data**: Contact GHOST project team via Zenodo
- **Evaltools** : Contact CNRM via https://redmine.umr-cnrm.fr/projects/evaltools
- **PyFerret**  : Contact NOAA/PMEL via GitHub or https://ferret.pmel.noaa.gov/Ferret/
- **QLC tools** : Contact qlc Team @ ResearchConcepts io GmbH <qlc@researchconcepts.io>

---

**Last Updated**: March 2026

