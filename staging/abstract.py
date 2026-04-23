"""abstract.py — Compute population exposure and generate abstract text.

Reads the WFBZ geojson + GHS population rasters, estimates 10km-buffered
population exposure, writes six CSVs (unioned by year+region and per-fire by
year, each against the full/WUI-masked/non-WUI-masked pop raster), and prints
the abstract with computed statistics.

Prerequisites
-------------
- data/raw/wfbz_disasters_2000-2025.geojson
- data/processed/regions.geojson (render main.qmd first)
- data/raw/ghs_pop/{2000,2005,2010,2015,2020}/*.tif (built by prep_population.R)
- data/raw/wui/*.tif (built by prep_wui.R)
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
import rasterio
from rasterio.warp import Resampling, reproject
from rasterio.windows import Window

ROOT = Path(__file__).parent.parent
POP_YEARS = [2000, 2005, 2010, 2015, 2020]


def raster_year(yr):
    return min(math.floor(yr / 5) * 5, 2020)


# ── Load data ────────────────────────────────────────────────────────────────

wfbz_all = gpd.read_file(ROOT / "data/raw/wfbz_disasters_2000-2025.geojson")
wfbz_all = wfbz_all[wfbz_all["wildfire_community_intersect"] == 1]
usfs_regions = gpd.read_file(ROOT / "data/processed/regions.geojson")

wfbz = wfbz_all[~wfbz_all.geometry.is_empty].copy()
wfbz = gpd.sjoin(wfbz, usfs_regions, how="left")

wfbz["ID_hazard"] = wfbz["wildfire_id"]
wfbz["buffer_dist_10km"] = 10_000

wfbz_by_yr_region = {
    group_name: group_data
    for group_name, group_data in wfbz.groupby(["wildfire_year", "usfs_region"])
}
wfbz_by_yr = {
    group_name: group_data
    for group_name, group_data in wfbz.groupby("wildfire_year")
}

pop_raw_paths = {
    yr: ROOT / f"data/raw/ghs_pop/{yr}/GHS_POP_E{yr}_GLOBE_R2023A_54009_100_V1_0.tif"
    for yr in POP_YEARS
}

# ── Build WUI-masked pop rasters ─────────────────────────────────────────────

pop_wui_dir = ROOT / "data/processed/ghs_pop_wui"
pop_non_wui_dir = ROOT / "data/processed/ghs_pop_non_wui"
pop_wui_dir.mkdir(parents=True, exist_ok=True)
pop_non_wui_dir.mkdir(parents=True, exist_ok=True)


def build_masked_rasters():
    # Silvis ships ~3k 1° tiles plus a GDAL VRT that stitches them seamlessly.
    wui_path = ROOT / "data/raw/wui/NA/mosaic/WUI.vrt"
    if not wui_path.exists():
        raise FileNotFoundError(
            f"{wui_path} not found. Run staging/prep_wui.R first."
        )
    print(f"Using WUI mask from {wui_path.relative_to(ROOT)}")

    # Restrict to the fire bbox (+10km buffer) so we don't mask all of NA.
    fire_bounds = wfbz.to_crs("ESRI:54009").total_bounds
    bbox = (
        fire_bounds[0] - 10_000,
        fire_bounds[1] - 10_000,
        fire_bounds[2] + 10_000,
        fire_bounds[3] + 10_000,
    )
    chunk = 4096

    for yr in POP_YEARS:
        out_in = pop_wui_dir / f"{yr}.tif"
        out_out = pop_non_wui_dir / f"{yr}.tif"
        if out_in.exists() and out_out.exists():
            continue
        print(f"  masking pop {yr}…")

        with rasterio.open(pop_raw_paths[yr]) as src_pop:
            full_window = src_pop.window(*bbox).round_offsets().round_lengths()
            win_h, win_w = int(full_window.height), int(full_window.width)
            win_transform = src_pop.window_transform(full_window)
            profile = src_pop.profile.copy()
            profile.update(
                height=win_h,
                width=win_w,
                transform=win_transform,
                tiled=True,
                blockxsize=512,
                blockysize=512,
                compress="lzw",
            )

            with (
                rasterio.open(out_in, "w", **profile) as dst_in,
                rasterio.open(out_out, "w", **profile) as dst_out,
                rasterio.open(wui_path) as src_wui,
            ):
                for y in range(0, win_h, chunk):
                    for x in range(0, win_w, chunk):
                        h = min(chunk, win_h - y)
                        w = min(chunk, win_w - x)
                        read_window = Window(
                            full_window.col_off + x,
                            full_window.row_off + y,
                            w,
                            h,
                        )
                        pop_chunk = src_pop.read(1, window=read_window)
                        chunk_transform = src_pop.window_transform(read_window)

                        wui_chunk = np.zeros(pop_chunk.shape, dtype=np.uint8)
                        reproject(
                            source=rasterio.band(src_wui, 1),
                            destination=wui_chunk,
                            src_nodata=src_wui.nodata,
                            dst_transform=chunk_transform,
                            dst_crs=src_pop.crs,
                            dst_nodata=0,
                            resampling=Resampling.nearest,
                        )
                        # Silvis global WUI: classes 1–4 are WUI, any other
                        # value (including 0 and nodata) is non-WUI.
                        mask = np.isin(wui_chunk, [1, 2, 3, 4])
                        write_window = Window(x, y, w, h)
                        dst_in.write(
                            np.where(mask, pop_chunk, 0).astype(pop_chunk.dtype),
                            1,
                            window=write_window,
                        )
                        dst_out.write(
                            np.where(~mask, pop_chunk, 0).astype(pop_chunk.dtype),
                            1,
                            window=write_window,
                        )


build_masked_rasters()


def make_estimators(paths):
    return {yr: pe.PopEstimator(pop_data=str(paths[yr])) for yr in POP_YEARS}


pop_full = make_estimators(pop_raw_paths)
pop_wui = make_estimators({yr: pop_wui_dir / f"{yr}.tif" for yr in POP_YEARS})
pop_non_wui = make_estimators({yr: pop_non_wui_dir / f"{yr}.tif" for yr in POP_YEARS})


# ── Estimator loops ──────────────────────────────────────────────────────────


def exposed_by_yr_region(estimators, out_name):
    results = dict()
    for yr in range(2000, 2026):
        print(yr)
        for region in usfs_regions["usfs_region"].unique():
            if (yr, region) in wfbz_by_yr_region:
                results[(yr, region)] = estimators[raster_year(yr)].est_exposed_pop(
                    hazard_data=wfbz_by_yr_region[(yr, region)], hazard_specific=False
                )
    df = pd.concat(results.values(), ignore_index=True)
    df["year"] = [k[0] for k in results.keys()]
    df["region"] = [k[1] for k in results.keys()]
    out_path = ROOT / "data/processed" / out_name
    df.to_csv(out_path, index=False)
    print(f"\nWrote data/processed/{out_name} ({len(df)} rows)")
    return df


def exposed_per_fire_by_yr(estimators, out_name):
    results = dict()
    for yr in range(2000, 2026):
        print(yr)
        if yr in wfbz_by_yr:
            result = estimators[raster_year(yr)].est_exposed_pop(
                hazard_data=wfbz_by_yr[yr], hazard_specific=True
            )
            result["year"] = yr
            results[yr] = result
    df = pd.concat(results.values(), ignore_index=True)
    out_path = ROOT / "data/processed" / out_name
    df.to_csv(out_path, index=False)
    print(f"\nWrote data/processed/{out_name} ({len(df)} rows)")
    return df


# ── Run all six outputs ──────────────────────────────────────────────────────

pop_impacted_all = exposed_by_yr_region(pop_full, "pop_affected.csv")
exposed_by_yr_region(pop_wui, "pop_affected_wui.csv")
exposed_by_yr_region(pop_non_wui, "pop_affected_non_wui.csv")
exposed_per_fire_by_yr(pop_full, "pop_affected_per_fire.csv")
exposed_per_fire_by_yr(pop_wui, "pop_affected_per_fire_wui.csv")
exposed_per_fire_by_yr(pop_non_wui, "pop_affected_per_fire_non_wui.csv")

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
declarations. Between 2000-2024, we identified {len(wfbz_all):,.0f} WFBZ disasters in the United States.
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
