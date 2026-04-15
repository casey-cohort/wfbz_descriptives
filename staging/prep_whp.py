"""prep_whp.py — Python port of prep_whp.R

Downloads USFS Wildfire Hazard Potential (WHP) rasters and computes per-tract
zonal statistics (mean and max WHP) using popexposure / exactextract.

Prerequisites
-------------
- Run staging/prep_tracts.R first to generate data/processed/tiger_tracts.geojson.

Dependencies (conda wfbz env)
------------------------------
    pip install popexposure geopandas
"""

import io
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

# Force PROJ to use this env's database, not the base miniconda installation.
# Must be set before importing any geo libraries.
_proj_data = Path(sys.prefix) / "share" / "proj"
if _proj_data.exists():
    os.environ["PROJ_DATA"] = str(_proj_data)
    os.environ["PROJ_LIB"] = str(_proj_data)

import geopandas as gpd
import popexposure as ex

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT = Path(__file__).parent.parent
DST = ROOT / "data" / "raw" / "wildfire_risk"
TRACTS_GEOJSON = ROOT / "data" / "processed" / "tiger_tracts.geojson"

# Three USFS WHP zip archives (CONUS, AK, HI)
WHP_URLS = [
    "https://usfs-public.box.com/shared/static/fyv3pecykr26juimm2h1th4own1ehdj7.zip",
    "https://usfs-public.box.com/shared/static/jh6l2x2blct82hbtmu4n6dvoe9bz25ap.zip",
    "https://usfs-public.box.com/shared/static/jz74xh0eqdezblhexwu2s2at7fqgom8n.zip",
]


# ── Helpers ───────────────────────────────────────────────────────────────────
def unzip_url(url: str, dst: Path) -> None:
    """Stream-download a zip archive and extract it to dst."""
    dst.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url} …")
    with urllib.request.urlopen(url) as resp:
        with zipfile.ZipFile(io.BytesIO(resp.read())) as zf:
            zf.extractall(dst)


def load_tracts() -> gpd.GeoDataFrame:
    """Load census tract geometries from the GeoJSON written by prep_tracts.R."""
    if not TRACTS_GEOJSON.exists():
        raise FileNotFoundError(
            f"{TRACTS_GEOJSON} not found. Run staging/prep_tracts.R from the project root first."
        )
    gdf = gpd.read_file(TRACTS_GEOJSON)
    # popexposure requires a column whose name contains "ID"
    gdf["ID_admin_unit"] = gdf["GEOID"].astype(str)
    return gdf


def summarize_whp(raster_path: Path, tracts: gpd.GeoDataFrame) -> None:
    """Compute per-tract mean WHP via popexposure and write to GeoJSON."""
    name = raster_path.stem  # e.g. WHP_HI
    out_path = ROOT / "data" / "processed" / f"tract_{name}.geojson"

    print(f"  computing mean via popexposure …")
    pop_est = ex.PopEstimator(pop_data=str(raster_path), admin_data=tracts)
    mean_df = pop_est.est_total_pop(stat="mean").rename(
        columns={"population": "whp_mean"}
    )

    out = tracts.merge(mean_df, on="ID_admin_unit").drop(columns="ID_admin_unit")
    out.to_file(str(out_path), driver="GeoJSON")
    print(f"  → {out_path}")


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    # Download rasters only if not already present
    if not any(DST.glob("*WHP*.tif")):
        for url in WHP_URLS:
            unzip_url(url, DST)

    tracts = load_tracts()

    for raster_path in sorted(DST.glob("*WHP*.tif")):
        print(f"Processing {raster_path.name} …")
        summarize_whp(raster_path, tracts)
