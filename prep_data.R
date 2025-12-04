# Prep data for reports
#
# - wfbz: lightly cleaned version of the research data set (spatial)
# - regions: Modified version of the USFS regions with separate California, Hawaii (spatial)
# - counties_pop: counties with population (spatial)
#

library(sf)
library(tidyverse)
library(tidycensus)

if (!file.exists('data/raw/wfbz_disasters_2000-2025.geojson')) {
  stop(
    "Manually download data set from https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/DWILBW and unzip to data/raw."
  )
}

unzip_url <- function(url, dst) {
  download.file(
    url = url,
    destfile = t <- tempfile(fileext = ".zip")
  )
  unzip(t, overwrite = TRUE, exdir = dst)
  unlink(t, recursive = TRUE)
  dst
}

wfbz <- read_sf("data/raw/wfbz_disasters_2000-2025.geojson") %>%
  filter(!st_is_empty(geometry))
wfbz <- wfbz %>%
  filter(!str_detect(wildfire_complex_names, '(FLOOD$|FLOOD 2013$)')) # remove some colorado floods that snuck in

states_sf <- tigris::states(progress_bar = FALSE)

regions <- read_sf(unzip_url(
  "https://data.fs.usda.gov/geodata/edw/edw_resources/shp/S_USA.AdministrativeRegion.zip",
  dst = tempfile(fileext = ".shp")
)) %>%
  select(usfs_region = REGIONNAME) %>%
  mutate(usfs_region = str_replace(usfs_region, " Region", ""))

regions <- bind_rows(
  regions,
  st_filter(
    regions %>%
      filter(usfs_region == 'Pacific Southwest') %>%
      st_cast("POLYGON"),
    states_sf %>% filter(STUSPS == 'HI')
  ) %>%
    group_by(usfs_region) %>%
    summarize(geometry = st_combine(geometry)) %>%
    mutate(usfs_region = 'Hawaii'),
  st_filter(
    regions %>%
      filter(usfs_region == 'Pacific Southwest') %>%
      st_cast("POLYGON"),
    states_sf %>% filter(STUSPS == 'CA')
  ) %>%
    group_by(usfs_region) %>%
    summarize(geometry = st_combine(geometry)) %>%
    mutate(usfs_region = 'California')
) %>%
  filter(usfs_region != 'Pacific Southwest') %>%
  mutate(
    usfs_region = if_else(
      usfs_region == 'Northern',
      'Northern Rockies',
      usfs_region
    )
  ) %>%
  mutate(
    usfs_region = if_else(
      usfs_region == 'Rocky Mountain',
      'Southern Rockies',
      usfs_region
    )
  )

counties_pop <- get_decennial(
  geography = "county",
  variables = "P1_001N", # Total population variable in 2020 Census
  year = 2020,
  geometry = TRUE,
  output = "wide",
  progress_bar = FALSE
) %>%
  rename(population = P1_001N) %>%
  select(population, geometry)

regions$usfs_region_pop <- aggregate(
  st_centroid(counties_pop),
  regions,
  FUN = sum
)$population # centroid more or less ensures counties only end up in one region


save(file = 'data/processed/report_source_data.rda', list = c('counties_pop', 'regions', 'states_sf', 'wfbz'))
