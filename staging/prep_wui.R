# Run once from project root to download Silvis global WUI data (North America).
# Source: https://silvis.forest.wisc.edu/globalwui/

library(here)

out_dir <- here("data", "raw", "wui")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

zip_path <- file.path(out_dir, "NA.zip")
url <- "https://geoserver.silvis.forest.wisc.edu/geodata/globalwui/NA.zip"

if (!file.exists(zip_path)) {
  options(timeout = max(1800, getOption("timeout")))
  download.file(url, zip_path, mode = "wb")
}

unzip(zip_path, exdir = out_dir)

cat(sprintf("Done. WUI data extracted to %s\n", out_dir))
