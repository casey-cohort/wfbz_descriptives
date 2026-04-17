# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Quarto website project producing descriptive visualizations of U.S. wildfire burn zone disasters (WFBZ) from 2000–2024, published at https://casey-cohort.github.io/wfbz_descriptives/. The site is organized around USFS regions and analyzes metrics like fatalities, structures destroyed, burned area, FEMA declarations, and WUI (wildland-urban interface) intersections.

## Commands

**Local preview:**
```
quarto preview
```

**Publish to GitHub Pages:**
```
quarto publish gh-pages --no-prompt
```

**Python environment setup (first time):**
```
conda create -n wfbz numpy pandas geopandas jupyter
conda activate wfbz
pip install popexposure
```

The `_quarto.yml` specifies `jupyter: wfbz` as the Python kernel for notebooks.

## Data Setup

The primary dataset must be manually downloaded from https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/DWILBW and unzipped to `data/raw/`. The setup code in `reports/_setup.qmd` checks for this file and will throw an error if it's missing.

Other data (Census geometry, USFS region shapefiles) is downloaded automatically on first render and cached in `data/raw/` and `data/processed/`.

## Architecture

### Quarto site structure
- `_quarto.yml` — site config; renders everything under `reports/`, outputs to `rendered/`
- `reports/_setup.qmd` — included by `main_*.qmd` and `fema.qmd` via `{{< include _setup.qmd >}}`; loads R packages, sets the global ggplot theme, reads/caches all data, defines `plotme()`, and builds core aggregated data frames (`wfbz`, `wfbz_crit`, `wfbz_crit_all`, `by_state`, `regions`)
- `reports/_pop_setup.qmd` — included by `pop_*.qmd`; loads packages, defines `REGION_ORDER`, `region_colors`, and `pop_theme`
- `reports/main_tables.qmd` — summary tables by USFS region
- `reports/main_timeseries.qmd` — stacked bar/line plots of events, fatalities, structures, FEMA, burned area, fire size, WUI over time
- `reports/main_correlations.qmd` — scatter matrix, boxplots, and heatmap of fire characteristics
- `reports/main_geography.qmd` — fire season timing boxplots and USFS region reference map
- `reports/fema.qmd` — FEMA declaration analyses
- `reports/pop_exposure.qmd` — population exposure over time (log-scale, stacked, area plots)
- `reports/pop_demographics.qmd` — demographic time series (vehicle access, race, poverty, housing cost) with IQR error bars
- `reports/pop_diverging.qmd` — diverging bar charts comparing fire-affected vs. high-risk reference populations
- `staging/abstract.py` — computes population exposure stats and generates abstract text

### Staging scripts (run before rendering)
- `staging/prep_tracts.R` — downloads Census tract geometries (2000/2010/2020) via `tigris`
- `staging/prep_whp.py` — downloads USFS Wildfire Hazard Potential rasters, computes per-tract zonal stats
- `staging/prep_population.R` — pulls NHGIS Census data via IPUMS API, builds demographic parquets
- `staging/prep_spatial_join.R` — runs expensive 10km spatial join of fires to tracts, writes `*_by_wf.parquet` files
- `staging/abstract.py` — computes population exposure via `popexposure`, writes `pop_affected.csv` and abstract text

### Key data objects (created in `_setup.qmd`)
- `wfbz` — raw spatial dataset filtered to non-empty geometries, excluding flood events
- `wfbz_crit` — grouped by USFS region × year, filtered to `wildfire_community_intersect == TRUE`
- `wfbz_crit_all` — same grouping but without the community intersect filter
- `by_state` — grouped by state, filtered to community-intersecting fires, ordered by FEMA declaration rate
- `regions` — USFS administrative region geometries (cached at `data/processed/regions.geojson`)
- `REGION_ORDER` — tibble defining consistent plot ordering for the 10 USFS regions
- `region_colors` — named color palette (khroma 'light' scheme) keyed to region names

### Region handling note
The "Pacific Southwest" USFS region is split into "California" and "Hawaii" for this analysis. "Northern" → "Northern Rockies" and "Rocky Mountain" → "Southern Rockies" are also renamed. Fires are assigned to regions by `st_nearest_feature()` (centroid-based spatial join).

### Mixed R/Python
`population.qmd` uses both R (for spatial data prep via `ipumsr`, `duckdb`, `sf`) and Python (via the `popexposure` package). The Quarto project uses the `wfbz` conda environment as the Jupyter kernel.
