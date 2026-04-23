library(tidyverse)
library(arrow)
read_parquet('data/processed/nhgis/race.parquet') -> race

race_summ <- race %>%
  group_by(start_year, end_year, race, ethnicity) %>%
  summarize(
    n = n(),
    count = sum(count, na.rm = TRUE),
    frac = sum(frac, na.rm = TRUE),
    ct_na = sum(is.na(count))
  )

ggplot(data = race_summ) +
  geom_col(aes(x = interaction(start_year, end_year), y = n)) +
  facet_grid(race ~ ethnicity) +
  theme_light()


## seeing roughly double the count of each race in year 2010

#source("/Users/loganap/sandbox/wfbz_viz/staging/prep_population.R", echo = FALSE, local = TRUE)

# this goes into making the parquet:
z <- read_rds('debug.rds')
