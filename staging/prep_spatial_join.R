# Run once from project root to build data/processed/nhgis/*_by_wf.parquet
# These are the expensive spatial join outputs consumed by pop_demographics.qmd
# and pop_diverging.qmd.
#
# Prerequisites:
#   - staging/prep_tracts.R (builds tiger_tracts.geojson)
#   - staging/prep_whp.py   (builds tract_WHP_*.geojson)
#   - staging/prep_population.R (builds nhgis/*.parquet)
#   - data/raw/wfbz_disasters_2000-2025.geojson

library(here)
library(tidyverse)
library(sf)
library(arrow)

cat("Loading tract geometries...\n")
tract_sf <- bind_rows(
  read_sf(here('data/processed/tract_WHP_AK.geojson')) %>%
    filter(substr(GEOID, 1, 2) == '02'),
  read_sf(here('data/processed/tract_WHP_HI.geojson')) %>%
    filter(substr(GEOID, 1, 2) == '15'),
  read_sf(here('data/processed/tract_WHP_CONUS.geojson')) %>%
    filter(!(substr(GEOID, 1, 2) %in% c('02', '15')))
)

cat("Loading census parquets...\n")
race <- read_parquet(here('data/processed/nhgis/race.parquet'))
poverty <- read_parquet(here('data/processed/nhgis/poverty_lt_100.parquet'))
vehicle_avail <- read_parquet(here(
  'data/processed/nhgis/vehicle_avail.parquet'
))
housing_cost <- read_parquet(here(
  'data/processed/nhgis/housing_cost_burden.parquet'
))

cat("Loading WFBZ data...\n")
wfbz <- read_sf(here('data/raw/wfbz_disasters_2000-2025.geojson')) %>%
  filter(wildfire_year < 2025) %>%
  filter(wildfire_community_intersect)


# ── Spatial join: wildfire_id -> GEOID mappings ──────────────────────────────

cat("Running spatial join (10km buffer)... this may take a while.\n")
wf_tract_matches <- st_join(
  wfbz %>% select(wildfire_id, wildfire_year),
  tract_sf %>% select(GEOID, census_year),
  join = st_is_within_distance,
  dist = units::as_units(10, 'km')
) %>%
  st_drop_geometry() %>%
  filter(10 * floor(wildfire_year / 10) == census_year)

# ── Join census data to matched tracts ───────────────────────────────────────

# NHGIS nominal geography: each row's GEOIDs come from the boundaries in use
# when the data were tabulated. Decennial 2000 → 2000 boundaries; decennial 2010
# and ACS 2006-2010 through 2015-2019 → 2010 boundaries; decennial 2020 and
# ACS 2016-2020 onward → 2020 boundaries. Joining a tract GEOID from one
# vintage to NHGIS rows from another vintage silently drops any tract that was
# re-drawn, so we constrain period selection to the fire's tract vintage.
period_vintage <- function(end_year) {
  dplyr::case_when(
    end_year < 2010 ~ 2000L,
    end_year < 2020 ~ 2010L,
    TRUE ~ 2020L
  )
}

join_census <- function(matches, census_data) {
  periods <- census_data %>%
    distinct(period, start_year, end_year) %>%
    mutate(vintage = period_vintage(end_year))

  best_period_by_year <- matches %>%
    distinct(wildfire_year, census_year) %>%
    inner_join(
      periods,
      by = c('census_year' = 'vintage'),
      relationship = 'many-to-many'
    ) %>%
    group_by(wildfire_year) %>%
    slice_min(
      abs(wildfire_year - (start_year + end_year) / 2),
      n = 1,
      with_ties = FALSE
    ) %>%
    ungroup() %>%
    select(wildfire_year, period)
  matches %>%
    inner_join(best_period_by_year, by = 'wildfire_year') %>%
    inner_join(
      census_data,
      by = c('GEOID', 'period'),
      relationship = 'many-to-many'
    )
}

cat("Joining census variables...\n")
race_by_wf <- join_census(wf_tract_matches, race)
poverty_by_wf <- join_census(wf_tract_matches, poverty)
vehicle_avail_by_wf <- join_census(wf_tract_matches, vehicle_avail)
housing_cost_by_wf <- join_census(wf_tract_matches, housing_cost)

# ── Write outputs ────────────────────────────────────────────────────────────

dst <- here('data/processed/nhgis')
write_parquet(race_by_wf, file.path(dst, 'race_by_wf.parquet'))
write_parquet(poverty_by_wf, file.path(dst, 'poverty_by_wf.parquet'))
write_parquet(
  vehicle_avail_by_wf,
  file.path(dst, 'vehicle_avail_by_wf.parquet')
)
write_parquet(housing_cost_by_wf, file.path(dst, 'housing_cost_by_wf.parquet'))

cat("Done. Wrote *_by_wf.parquet files to", dst, "\n")
