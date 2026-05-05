# Bootstrap CIs for the diverging-plot diffs in reports/pop_diverging.qmd.
#
# Resamples wildfire_ids with replacement and recomputes the fire-side and
# reference-side fracs each iteration. Two scopes:
#   - national: resample fires from the full pool (drives the national plot;
#     also drives the 'Overall' facet of the regional plot)
#   - regional: resample fires within each USFS region (one stratum per
#     region; drives the regional plot)
#
# Output: data/processed/diverge_bootstrap.parquet — one row per
# (b, scope, stat[, usfs_region]) iterate of `diff`. Quantiles are computed
# downstream in pop_diverging.qmd so CI level can be changed without rerun.
#
# Usage:
#   Rscript staging/prep_diverge_bootstrap.R           # B from $WFBZ_BOOT_B (default 100)
#   WFBZ_BOOT_B=1000 Rscript staging/prep_diverge_bootstrap.R

suppressPackageStartupMessages({
  library(tidyverse)
  library(sf)
  library(arrow)
  library(here)
  library(furrr)
  library(future)
  library(parallelly)
})

B <- 1000
SEED <- 8675309
N_WORKERS <- max(1L, availableCores() - 1L)
OUT_PATH <- here('data/processed/diverge_bootstrap.parquet')

message(sprintf("Bootstrap: B=%d, workers=%d -> %s", B, N_WORKERS, OUT_PATH))

# -- Load inputs (mirrors the load_data + high_risk_tracts chunks of the qmd)

by_wf_dir <- here('data/processed/nhgis')
race_by_wf <- read_parquet(file.path(by_wf_dir, 'race_by_wf.parquet'))
poverty_by_wf <- read_parquet(file.path(by_wf_dir, 'poverty_by_wf.parquet'))
vehicle_avail_by_wf <- read_parquet(file.path(
  by_wf_dir,
  'vehicle_avail_by_wf.parquet'
))
housing_cost_by_wf <- read_parquet(file.path(
  by_wf_dir,
  'housing_cost_by_wf.parquet'
))

tract_sf <- bind_rows(
  read_sf(here('data/processed/tract_WHP_AK.geojson')) %>%
    filter(substr(GEOID, 1, 2) == '02'),
  read_sf(here('data/processed/tract_WHP_HI.geojson')) %>%
    filter(substr(GEOID, 1, 2) == '15'),
  read_sf(here('data/processed/tract_WHP_CONUS.geojson')) %>%
    filter(!(substr(GEOID, 1, 2) %in% c('02', '15')))
)

tract_pop <- read_parquet(here('data/processed/nhgis/population.parquet')) %>%
  group_by(GEOID) %>%
  filter(start_year == max(start_year)) %>%
  filter(end_year == max(end_year)) %>%
  ungroup() %>%
  select(GEOID, pop)

tract_sf <- tract_sf %>% left_join(tract_pop, by = 'GEOID')

regions <- read_sf(here('data/processed/regions.geojson'))
wfbz <- read_sf(here('data/raw/wfbz_disasters_2000-2025.geojson')) %>%
  filter(wildfire_year < 2025) %>%
  filter(wildfire_community_intersect)

wfbz_region <- wfbz %>%
  filter(!st_is_empty(geometry)) %>%
  select(wildfire_id) %>%
  mutate(
    usfs_region = regions$usfs_region[st_nearest_feature(geometry, regions)]
  ) %>%
  st_drop_geometry()

tract_risk <- tract_sf %>%
  filter(!is.na(whp_mean), !is.na(pop), pop > 0) %>%
  mutate(
    usfs_region = regions$usfs_region[st_nearest_feature(
      geometry,
      st_transform(regions, 4326)
    )]
  ) %>%
  st_drop_geometry()

high_risk_tracts <- tract_risk %>%
  filter(whp_mean > 75) %>%
  distinct(GEOID, census_year, usfs_region)

# -- Per-fire summands

per_fire_ses <- function(df, ind_col) {
  df %>%
    group_by(wildfire_id) %>%
    summarize(
      num = sum(count[.data[[ind_col]] == TRUE], na.rm = TRUE),
      den = sum(count, na.rm = TRUE),
      .groups = 'drop'
    )
}
per_fire_vehicle <- per_fire_ses(vehicle_avail_by_wf, 'no_vehicle')
per_fire_poverty <- per_fire_ses(poverty_by_wf, 'poverty_lt_100')
per_fire_housing <- per_fire_ses(housing_cost_by_wf, 'cost_burdened')

per_fire_race <- race_by_wf %>%
  mutate(
    race_group = if_else(
      ethnicity == "Hispanic or Latino",
      "Hispanic (any)",
      race
    )
  ) %>%
  group_by(wildfire_id, race_group) %>%
  summarize(count = sum(count, na.rm = TRUE), .groups = 'drop')

fire_strata <- race_by_wf %>%
  distinct(wildfire_id, census_year, period) %>%
  inner_join(wfbz_region, by = 'wildfire_id')

all_fire_ids <- fire_strata$wildfire_id

# -- Per-stratum reference summands

ref_per_stratum_ses <- function(parquet_path, ind_col, by_region) {
  df <- high_risk_tracts %>%
    inner_join(
      read_parquet(here(parquet_path)),
      by = 'GEOID',
      relationship = 'many-to-many'
    )
  grp <- if (by_region) {
    c('usfs_region', 'census_year', 'period')
  } else {
    c('census_year', 'period')
  }
  df %>%
    group_by(across(all_of(grp))) %>%
    summarize(
      ref_num = sum(count[.data[[ind_col]] == TRUE], na.rm = TRUE),
      ref_den = sum(count, na.rm = TRUE),
      .groups = 'drop'
    )
}

ref_nat_vehicle <- ref_per_stratum_ses(
  'data/processed/nhgis/vehicle_avail.parquet',
  'no_vehicle',
  FALSE
)
ref_nat_poverty <- ref_per_stratum_ses(
  'data/processed/nhgis/poverty_lt_100.parquet',
  'poverty_lt_100',
  FALSE
)
ref_nat_housing <- ref_per_stratum_ses(
  'data/processed/nhgis/housing_cost_burden.parquet',
  'cost_burdened',
  FALSE
)

ref_reg_vehicle <- ref_per_stratum_ses(
  'data/processed/nhgis/vehicle_avail.parquet',
  'no_vehicle',
  TRUE
)
ref_reg_poverty <- ref_per_stratum_ses(
  'data/processed/nhgis/poverty_lt_100.parquet',
  'poverty_lt_100',
  TRUE
)
ref_reg_housing <- ref_per_stratum_ses(
  'data/processed/nhgis/housing_cost_burden.parquet',
  'cost_burdened',
  TRUE
)

ref_race_per_stratum <- function(by_region) {
  df <- high_risk_tracts %>%
    inner_join(
      read_parquet(here('data/processed/nhgis/race.parquet')),
      by = 'GEOID',
      relationship = 'many-to-many'
    ) %>%
    mutate(
      race_group = if_else(
        ethnicity == "Hispanic or Latino",
        "Hispanic (any)",
        race
      )
    )
  grp <- if (by_region) {
    c('usfs_region', 'census_year', 'period', 'race_group')
  } else {
    c('census_year', 'period', 'race_group')
  }
  df %>%
    group_by(across(all_of(grp))) %>%
    summarize(count = sum(count, na.rm = TRUE), .groups = 'drop')
}
ref_nat_race <- ref_race_per_stratum(FALSE)
ref_reg_race <- ref_race_per_stratum(TRUE)

add_overall <- function(ref_reg, has_race) {
  grp <- c('census_year', 'period')
  if (has_race) {
    grp <- c(grp, 'race_group')
  }
  overall <- ref_reg %>%
    group_by(across(all_of(grp))) %>%
    summarize(across(where(is.numeric), sum), .groups = 'drop') %>%
    mutate(usfs_region = 'Overall')
  bind_rows(ref_reg, overall)
}
ref_reg_vehicle <- add_overall(ref_reg_vehicle, FALSE)
ref_reg_poverty <- add_overall(ref_reg_poverty, FALSE)
ref_reg_housing <- add_overall(ref_reg_housing, FALSE)
ref_reg_race <- add_overall(ref_reg_race, TRUE)

collapse_race <- function(df) {
  df %>%
    mutate(
      stat = case_when(
        str_detect(race_group, "Black or African American") ~ "NH Black",
        str_detect(
          race_group,
          "American Indian|Asian|Pacific Islander|Native Hawaiian"
        ) ~ "NH AIAN, Asian,\nor Pacific Islander",
        str_detect(race_group, "Some Other Race") ~ "NH Other",
        str_detect(race_group, "White") ~ "NH White",
        str_detect(race_group, "Two or More Races") ~ "NH Two or\nMore Races",
        TRUE ~ race_group
      )
    )
}

# -- Bootstrap iteration body

national_one <- function(boot_ids) {
  fw <- tibble(wildfire_id = boot_ids) %>%
    inner_join(fire_strata, by = 'wildfire_id') %>%
    count(census_year, period, name = 'n_fires_b')

  ses_one <- function(per_fire, ref_nat, label) {
    f <- tibble(wildfire_id = boot_ids) %>%
      inner_join(per_fire, by = 'wildfire_id') %>%
      summarize(num = sum(num), den = sum(den)) %>%
      mutate(frac = num / den)
    p <- ref_nat %>%
      inner_join(fw, by = c('census_year', 'period')) %>%
      summarize(
        frac_pop = sum(n_fires_b * ref_num) / sum(n_fires_b * ref_den)
      )
    tibble(stat = label, diff = f$frac - p$frac_pop)
  }

  ses <- bind_rows(
    ses_one(per_fire_vehicle, ref_nat_vehicle, "No vehicle"),
    ses_one(per_fire_poverty, ref_nat_poverty, "Below poverty line"),
    ses_one(per_fire_housing, ref_nat_housing, "Housing cost\nburdened")
  )

  race_fire <- tibble(wildfire_id = boot_ids) %>%
    inner_join(per_fire_race, by = 'wildfire_id', relationship = 'many-to-many') %>%
    group_by(race_group) %>%
    summarize(count = sum(count), .groups = 'drop') %>%
    mutate(frac = count / sum(count))

  race_pop <- ref_nat_race %>%
    inner_join(fw, by = c('census_year', 'period')) %>%
    group_by(race_group) %>%
    summarize(count = sum(n_fires_b * count), .groups = 'drop') %>%
    mutate(frac_pop = count / sum(count))

  race <- left_join(
    race_fire %>% select(race_group, frac),
    race_pop %>% select(race_group, frac_pop),
    by = 'race_group'
  ) %>%
    collapse_race() %>%
    group_by(stat) %>%
    summarize(diff = sum(frac) - sum(frac_pop), .groups = 'drop')

  bind_rows(ses, race)
}

regional_one <- function(boot_ids_by_region, national_boot_ids) {
  ids_with_overall <- c(
    boot_ids_by_region,
    list(Overall = national_boot_ids)
  )

  do_region <- function(region, boot_ids) {
    fw <- tibble(wildfire_id = boot_ids) %>%
      inner_join(fire_strata, by = 'wildfire_id') %>%
      count(census_year, period, name = 'n_fires_b')

    ses_one <- function(per_fire, ref_reg, label) {
      f <- tibble(wildfire_id = boot_ids) %>%
        inner_join(per_fire, by = 'wildfire_id') %>%
        summarize(num = sum(num), den = sum(den)) %>%
        mutate(frac = num / den)
      p <- ref_reg %>%
        filter(usfs_region == region) %>%
        inner_join(fw, by = c('census_year', 'period')) %>%
        summarize(
          frac_pop = sum(n_fires_b * ref_num) / sum(n_fires_b * ref_den)
        )
      tibble(usfs_region = region, stat = label, diff = f$frac - p$frac_pop)
    }

    ses <- bind_rows(
      ses_one(per_fire_vehicle, ref_reg_vehicle, "No vehicle"),
      ses_one(per_fire_poverty, ref_reg_poverty, "Below poverty line"),
      ses_one(per_fire_housing, ref_reg_housing, "Housing cost\nburdened")
    )

    race_fire <- tibble(wildfire_id = boot_ids) %>%
      inner_join(per_fire_race, by = 'wildfire_id', relationship = 'many-to-many') %>%
      group_by(race_group) %>%
      summarize(count = sum(count), .groups = 'drop') %>%
      mutate(frac = count / sum(count))
    race_pop <- ref_reg_race %>%
      filter(usfs_region == region) %>%
      inner_join(fw, by = c('census_year', 'period')) %>%
      group_by(race_group) %>%
      summarize(count = sum(n_fires_b * count), .groups = 'drop') %>%
      mutate(frac_pop = count / sum(count))
    race <- left_join(
      race_fire %>% select(race_group, frac),
      race_pop %>% select(race_group, frac_pop),
      by = 'race_group'
    ) %>%
      collapse_race() %>%
      group_by(stat) %>%
      summarize(diff = sum(frac) - sum(frac_pop), .groups = 'drop') %>%
      mutate(usfs_region = region)

    bind_rows(ses, race)
  }

  imap_dfr(ids_with_overall, ~ do_region(.y, .x))
}

fire_ids_by_region <- split(wfbz_region$wildfire_id, wfbz_region$usfs_region)

# -- Run in parallel

plan(multisession, workers = N_WORKERS)
on.exit(plan(sequential), add = TRUE)

t0 <- Sys.time()
boot_results <- future_map_dfr(
  seq_len(B),
  function(b) {
    national_ids <- sample(
      all_fire_ids,
      length(all_fire_ids),
      replace = TRUE
    )
    regional_ids <- map(
      fire_ids_by_region,
      ~ sample(.x, length(.x), replace = TRUE)
    )
    bind_rows(
      national_one(national_ids) %>% mutate(scope = 'national'),
      regional_one(regional_ids, national_ids) %>% mutate(scope = 'regional')
    ) %>%
      mutate(b = b)
  },
  .options = furrr_options(seed = SEED),
  .progress = TRUE
)
t1 <- Sys.time()
message(sprintf(
  "Bootstrap done in %.1f s (%.2f s/iter, B=%d)",
  as.numeric(t1 - t0, units = 'secs'),
  as.numeric(t1 - t0, units = 'secs') / B,
  B
))

dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)
write_parquet(boot_results, OUT_PATH)
message(sprintf("Wrote %s (%d rows)", OUT_PATH, nrow(boot_results)))
