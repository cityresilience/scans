# Set up session for running maps.R
# Uses `here` package for project-root-relative paths (like Python's config/paths.py)

# 1. Load packages
# 2. Load functions
# 3. Set directories
# 4. Load map layer parameters
# 5. Load city parameters
# 6. Read AOI & wards

if (!"here" %in% installed.packages()) install.packages("here")
library(here)

message("\n=== Starting Setup ===")
message("Project root: ", here())

# 1. Load packages -------------------------------------------------------------
# Install packages from CRAN using librarian

if (!"librarian" %in% installed.packages()) install.packages("librarian")
librarian::shelf(quiet = T,
  # Read-in
  readxl,
  readr,
  yaml, 

  # Basic
  stringr,
  glue,
  tidyr,
  purrr,
  forcats,
  units,
  dplyr,
  zoo,
  lubridate,

  # Plots
  ggplot2, # 4.0+
  ggrepel,
  directlabels,
  ggh4x,
  ggtext,
  plotly, 
  cowplot,
  ggpackets,
  ggridges,
  ggpattern,

  # Spatial
  sf,
  rspatial/terra, # Only the github version of leaflet supports terra, in place of raster, which is now required as sp (on which raster depends) is being deprecated
  tidyterra,
  leaflet,
  leafem,
  ggspatial,
  jsonlite,
  geojsonsf,
  exactextractr,
  h3o,


  # Web
  curl,
  rvest,

  # GCS access
  googleCloudStorageR, 
  gargle
  )

librarian::stock(quiet = T,
  ggnewscale, # 4.10 or higher
  prettymapr
)

if (packageVersion("ggplot2") < "4.0.0") {
  message("Updating ggplot2 to 4.0+...")
  install.packages("ggplot2")
  library(ggplot2)
}

# 2. Load functions ------------------------------------------------------------
source(here("core/R/fns.R"), local = T)

if (!exists("USE_GCS", where = .GlobalEnv)) {
    USE_GCS <<- Sys.getenv("USE_GCS", "false") == "true"
  }

# USE_GCS <<- TRUE

# 3.A Set directories -----------------------------------------------------------
city_dir <- here()

# subdirectorie pattern
user_input_dir <-     here("01-user-input")
process_output_dir <- here("02-process-output")
output_dir <-         here("03-render-output")

spatial_dir <- here("02-process-output/spatial")
fgb_dir <- here("02-process-output/spatial-fgb")
tabular_dir <- here("02-process-output/tabular")

styled_maps_dir <- here("03-render-output/maps")
charts_dir <- here("03-render-output/plots")

if (!dir.exists(user_input_dir)) dir.create(user_input_dir, recursive = T)
if (!dir.exists(spatial_dir)) dir.create(spatial_dir, recursive = T) 
if (!dir.exists(tabular_dir)) dir.create(tabular_dir, recursive = T) 
if (!dir.exists(fgb_dir)) dir.create(fgb_dir, recursive = T)
if (!dir.exists(styled_maps_dir)) dir.create(styled_maps_dir, recursive = T)
if (!dir.exists(charts_dir)) dir.create(charts_dir, recursive = T)


# 3.B Check GCS -----------------------------------------------------------
# assigning scan-id - can remove if we add scan_id to city_input.yml
scan_id <- Sys.getenv("SCAN_ID", "")

if (scan_id == "") {
  scan_id <- basename(here())
}

# Validate format and fall back to user-inputs.R if invalid
if (!grepl("^[0-9]{4}-[0-9]{2}-[a-z_-]+$", tolower(scan_id)) ||
    scan_id == "" || is.na(scan_id)) {

  if (file.exists(here("core/R/user-inputs.R"))) {
    invisible(source(here("core/R/user-inputs.R"), local = F))
  } else {
    stop("\nCannot determine valid scan_id")
  }
}

message("\nInitializing for ", scan_id)
invisible(NULL)

# If USE GCS, authenticate and use gcs-overrides
message(paste('USE GCS:', USE_GCS))

message("spatial_dir: ", spatial_dir)
message("spatial files count: ", length(list.files(spatial_dir)))
# Note: auto-switching to GCS removed — USE_GCS must be explicitly set in the Rmd


if(USE_GCS) { 
  
  source(here("core/R/gcs-auth.R"))

  } else  {
  # Paths already absolute via here() — no reassignment needed
}

# setup directories for global data path
source(here("core/R/global-data-paths.R"))


# 4. Load map layer parameters -------------------------------------------------
# this should be a local file 
layer_params_file <- here('source/layers.yml') # Also used by fns.R
layer_params <- read_yaml(layer_params_file)


# 5. Load city parameters ------------------------------------------------------
city_params <- read_yaml(file.path(user_input_dir, "city_inputs.yml"))
city <- str_to_title(city_params$city_name)
message(glue("City set to {city} (City directory: {city_dir})"))
city_string <- tolower(city) %>% stringr::str_replace_all(" ", "_")
country <- str_to_title(city_params$country_name)
if (length(country) == 0 || is.null(country) || country == "") {
  country <- str_match(scan_id, "\\d{4}-\\d{2}-([a-z]+)-")[1, 2] %>% str_to_title()
}

bm_cities_manual <- c(city_params$bm_cities_manual)
nearby_countries_string <- city_params$nearby_countries

basic_info <- fuzzy_read(tabular_dir, "basic_info.yml", read_yaml)
if (length(country) == 0 && is.list(basic_info)) country <- basic_info$country


# 6. Read AOI & wards ----------------------------------------------------------
message("\nReading AOI and wards data...")
# Defining layer because of bug where AOI always includes South Jakarta shapefile;
# ideally would not need to specify like this, for greater flexibility
aoi <- fuzzy_read(user_input_dir, "AOI", layer = city_params$AOI_shp_name) %>%
  project("epsg:4326")
message("AOI Ready!")

wards <- tryCatch(fuzzy_read(user_input_dir, "wards") %>% project("epsg:4326"), error = \(e) NULL)

# Greedy 4-coloring of wards so neighboring ADM2 polygons get different fill shades.
# Used for the very-light fill ward style (no stroke). No external dep — pure R.
if (!is.null(wards) && nrow(wards) > 0) {
  tryCatch({
    ward_sf <- sf::st_as_sf(wards)
    touch <- sf::st_relate(ward_sf, ward_sf, pattern = "F***T****")  # touches but not equal
    palette4 <- c("grey85", "grey80", "grey75", "grey70")
    n <- nrow(ward_sf); idx <- rep(NA_integer_, n)
    for (i in seq_len(n)) {
      used <- idx[touch[[i]]]; used <- used[!is.na(used)]
      avail <- setdiff(seq_along(palette4), used)
      idx[i] <- if (length(avail) > 0) avail[1] else ((i - 1) %% length(palette4)) + 1
    }
    wards$ward_fill <- palette4[idx]
    # Detect a label column for in-polygon ADM2 labels
    label_col <- intersect(names(wards),
      c("shapeName", "WARD_NO", "NAME", "name", "Name", "WARD", "ADM2_EN", "ADM2_NAME"))[1]
    if (!is.na(label_col)) {
      wards$ward_label <- as.data.frame(wards)[[label_col]]
      message("Ward labels from column: ", label_col)
    }
    message("Ward 4-coloring complete: ", n, " polygons, ",
            length(unique(idx)), " distinct color slots used")
  }, error = function(e) message("Ward coloring failed: ", e$message))
}

# Lobito corridor cities (UCDB-derived) — used by add_city_labels() to overlay
# city names outside the AOI on each map. Lobito-specific input.
city_labels <- tryCatch(
  sf::st_read(file.path(user_input_dir, "AOI", "lobito_corridor_cities_drc_ucdb.gpkg"),
              quiet = TRUE) %>%
    sf::st_transform("EPSG:4326"),
  error = function(e) { message("city_labels not loaded: ", e$message); NULL })

# Major roads (trunk/primary, 419 features) — used by add_roads() to overlay
# the road network on each map. From accessibility/filter_major_roads output.
# Loaded as terra SpatVector to match the rest of the plotting pipeline (geom_spatvector).
road_network <- tryCatch(
  vect(file.path(spatial_dir, paste0(city_string, "_major_roads.gpkg")),
       layer = "major_roads") %>%
    project("epsg:4326"),
  error = function(e) { message("road_network not loaded: ", e$message); NULL })

writeVector(aoi, file.path(fgb_dir, "aoi.fgb"), overwrite = T, filetype = "FlatGeobuf")

message("Setup complete.\n")