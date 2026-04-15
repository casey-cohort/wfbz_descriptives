"""abstract.py — Compute population exposure and generate abstract text.

Reads the WFBZ geojson + GHS population rasters, estimates 10km-buffered
population exposure per year/region, writes pop_affected.csv, and prints
the abstract with computed statistics.

Prerequisites
-------------
- data/raw/wfbz_disasters_2000-2025.geojson
- data/processed/regions.geojson (render main.qmd first)
- data/raw/ghs_pop/{2000,2005,2010,2015,2020}/*.tif (built by prep_population.R)
"""

import math
import os
import sys
from pathlib import Path

_proj_data = Path(sys.prefix) / "share" / "proj"
if _proj_data.exists():
    os.environ["PROJ_DATA"] = str(_proj_data)
    os.environ["PROJ_LIB"] = str(_proj_data)

import geopandas as gpd
import numpy as np
import pandas as pd
import popexposure as pe

ROOT = Path(__file__).parent.parent

# ── Load data ────────────────────────────────────────────────────────────────

wfbz_all = gpd.read_file(ROOT / "data/raw/wfbz_disasters_2000-2025.geojson")
wfbz_all = wfbz_all[wfbz_all["wildfire_community_intersect"] == True]
usfs_regions = gpd.read_file(ROOT / "data/processed/regions.geojson")

wfbz = wfbz_all[~wfbz_all.geometry.is_empty].copy()
wfbz = gpd.sjoin(wfbz, usfs_regions, how="left")

wfbz["ID_hazard"] = wfbz["wildfire_id"]
wfbz["buffer_dist_10km"] = 10_000
wfbz = {
    group_name: group_data
    for group_name, group_data in wfbz.groupby(["wildfire_year", "usfs_region"])
}

pop = {
    yr: pe.PopEstimator(
        pop_data=str(
            ROOT
            / f"data/raw/ghs_pop/{yr}/GHS_POP_E{yr}_GLOBE_R2023A_54009_100_V1_0.tif"
        )
    )
    for yr in [2000, 2005, 2010, 2015, 2020]
}

# ── Estimate exposed population ──────────────────────────────────────────────

pop_impacted = dict()
for yr in range(2000, 2026):
    print(yr)
    for region in usfs_regions["usfs_region"].unique():
        print(f"  {region}")
        if (yr, region) in wfbz.keys():
            pop_impacted[(yr, region)] = pop[
                min(math.floor(yr / 5) * 5, 2020)
            ].est_exposed_pop(hazard_data=wfbz[(yr, region)], hazard_specific=False)
        else:
            print("    skip")

pop_impacted_all = pd.concat(pop_impacted.values(), ignore_index=True)
pop_impacted_all["year"] = [x[0] for x in pop_impacted.keys()]
pop_impacted_all["region"] = [x[1] for x in pop_impacted.keys()]

# ── Export ────────────────────────────────────────────────────────────────────

pop_impacted_all.to_csv(ROOT / "data/processed/pop_affected.csv", index=False)
print(f"\nWrote data/processed/pop_affected.csv ({len(pop_impacted_all)} rows)")

# ── Abstract text ─────────────────────────────────────────────────────────────

burned_km2 = (
    wfbz_all.to_crs(3857).dissolve().area / 1000 / 1000
).iloc[0]
mean_exposed = pop_impacted_all.exposed_10km.mean()
pct_increase = 100 * (
    (pop_impacted_all.exposed_10km / pop_impacted_all.exposed_10km.shift(1)).mean()
    - 1
)
ca_hi_fatalities = wfbz_all[wfbz_all["wildfire_states"].isin(["CA", "HI"])][
    "wildfire_max_civil_fatalities"
].sum()
total_fatalities = wfbz_all["wildfire_max_civil_fatalities"].sum()
pct_fatalities = 100 * ca_hi_fatalities / total_fatalities
ca_struct = wfbz_all[wfbz_all["wildfire_states"] == "CA"][
    "wildfire_struct_destroyed"
].sum()
total_struct = wfbz_all["wildfire_struct_destroyed"].sum()
pct_struct = 100 * ca_struct / total_struct

abstract = f"""\
Studies document increasing wildfire smoke exposure in the United States, but no
research has characterized the locations of wildfires that impact human populations (i.e.,
wildfire burn zone disasters [WFBZ disasters]). Here, we leverage a novel dataset of WFBZ
disasters by harmonizing six existing national or California-specific datasets to
characterize spatiotemporal trends in WFBZ disaster occurrence, size, and severity,
populations impacted, intersection with the wildland-urban interface, and FEMA disaster
declarations. Between 2000-2025, we identified {len(wfbz_all):,.0f} WFBZ disasters in the United States.
These WFBZ disasters burned a cumulative {burned_km2:,.0f} km2, with the burned area exceeding
20,000km2 in Texas, Idaho, Oregon, and California. On average, {mean_exposed:,.0f} people lived within 10km
of a WFBZ annually, with a {pct_increase:,.0f}% average increase in count annually during the study
period. California and Hawaii WFBZ disasters accounted for {pct_fatalities:,.0f}% (n={ca_hi_fatalities}) of civilian
fatalities and California alone accounted for the majority of structures destroyed ({pct_struct:,.0f}%,
n={ca_struct:,.0f}). We find that certain states were more likely to receive a FEMA disaster declaration
for WFBZ disasters. For example, Hawaii and New Hampshire received FEMA disaster
declarations for >85% of identified WFBZ disasters, while California, Montana, and Texas
received one for 20-30% of WFBZ disasters. Understanding trends in WFBZ locations,
severity, and populations exposed can aid in disaster preparedness and recovery efforts."""

print("\n" + abstract)

# Write abstract text to file
with open(ROOT / "data/processed/abstract.txt", "w") as f:
    f.write(abstract + "\n")
print("\nWrote data/processed/abstract.txt")
