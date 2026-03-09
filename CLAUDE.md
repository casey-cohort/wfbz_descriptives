# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Quarto website project producing descriptive visualizations of U.S. wildfire burn zone disasters (WFBZ) from 2000–2025, published at https://casey-cohort.github.io/wfbz_descriptives/. The site is organized around USFS regions and analyzes metrics like fatalities, structures destroyed, burned area, FEMA declarations, and WUI (wildland-urban interface) intersections.

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
- `reports/_setup.qmd` — included by `main.qmd` and `fema.qmd` via `{{< include _setup.qmd >}}`; loads all R packages, sets the global ggplot theme, reads/caches all data, and builds the core aggregated data frames (`wfbz`, `wfbz_crit`, `wfbz_crit_all`, `by_state`, `regions`)
- `reports/_helpers.qmd` — included by `population.qmd`; provides the `unzip_url()` helper for streaming large downloads
- `reports/main.qmd` — main descriptive summaries by USFS region and variable over time
- `reports/fema.qmd` — FEMA declaration analyses
- `reports/population.qmd` — population exposure summaries (uses R + Python via `popexposure`)
- `reports/abstract.ipynb` / `reports/abstract.qmd` — abstract-level summary

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
