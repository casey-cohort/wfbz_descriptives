# Run once from project root to build data/processed/tiger_tracts.rds
# Downloads Census tract geometries for all states + PR + DC, years 2000/2010/2020

library(here)
library(tidyverse)
library(sf)
library(tigris)

tract_sf <- map(
  c(state.abb, 'PR', 'DC'),
  function(state) {
    bind_rows(
      tracts(
        state = state,
        cb = TRUE,
        year = 2000,
        progress_bar = FALSE
      ) %>%
        transmute(
          census_year = 2000,
          GEOID = paste0(STATE, COUNTY, TRACT)
        ),
      tracts(
        state = state,
        cb = TRUE,
        year = 2010,
        progress_bar = FALSE
      ) %>%
        transmute(
          census_year = 2010,
          GEOID = paste0(STATE, COUNTY, TRACT)
        ),
      tracts(
        state = state,
        cb = TRUE,
        year = 2020,
        progress_bar = FALSE
      ) %>%
        transmute(
          census_year = 2020,
          GEOID
        )
    )
  }
) %>%
  bind_rows()

st_write(tract_sf, here('data/processed/tiger_tracts.geojson'), delete_dsn = TRUE)
cat("Done. Tract geometries written to data/processed/tiger_tracts.geojson\n")
