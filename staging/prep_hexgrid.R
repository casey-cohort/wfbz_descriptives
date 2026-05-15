# Run once from project root to build data/processed/hexgrid.geojson
#
# Builds the shared 500x500 hex grid used by both the R time-series maps
# (main_timeseries.qmd, pop_exposure.qmd, fema.qmd) and the Python population
# exposure script (staging/abstract.py). Persisting the grid once guarantees
# the cells (and their hexids) are identical across languages -- reproducing
# sf::st_make_grid's hexagon math in geopandas would be fragile.
#
# hexid is assigned on the FULL grid before st_filter so the ids are stable
# regardless of which cells happen to intersect land.

library(here)
library(tidyverse)
library(sf)

states_path <- here('data/raw/tiger_states.geojson')
if (!file.exists(states_path)) {
  stop(
    states_path,
    " not found. Render a report that includes _setup.qmd once first ",
    "(it caches tiger_states.geojson)."
  )
}

states_pop <- read_sf(states_path)

hexgrid <- st_make_grid(states_pop, square = FALSE, n = c(500, 500)) %>%
  st_as_sf() %>%
  mutate(hexid = row_number()) %>%
  st_filter(states_pop)

st_write(
  hexgrid,
  here('data/processed/hexgrid.geojson'),
  delete_dsn = TRUE
)
cat(
  "Done. ",
  nrow(hexgrid),
  " hex cells written to data/processed/hexgrid.geojson\n",
  sep = ""
)
