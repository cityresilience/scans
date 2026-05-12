# Generating City Scan Maps

# if ("frontend" %in% list.files()) setwd("frontend")
if (!require("here", quietly = TRUE)) install.packages("here")
library(here)

# WARNING: Some raster plotting breaks with terra 1.8+, when reprojected, such
# as to EPSG: 3857. It results in the following error. Would upgrading tidyterra
# also solve this?
# Caused by error:
# ! [spatSample] at least one of 'values', 'cells', or 'xy' must be TRUE; or 'as.points' must be TRUE 
# 2: No shared levels found between `names(values)` of the manual scale and the data's fill values.

# Set static map visualization parameters
layer_alpha <- 0.7
map_width <- 8.77 # Width of the map itself, excluding legend
map_height <- 7.55
aspect_ratio <- map_width / map_height
map_portions <- c(7, 2) # First number is map width, second is legend width
include_captions <- FALSE

# Load libraries and pre-process rasters
source(here("core/R/setup.R"), local = T)
if (!exists("render_tasks")) source(here("core/R/pre-mapping.R"), local = T)
# source(here("core/R/pre-mapping.R"), local = T) 

# Define map extent and zoom level adjustment
# static_map_bounds <- aspect_buffer(aoi, aspect_ratio, buffer_percent = 0.05)

# Task-specific rendering: if render_tasks is set (from CLI), load maps.yml per task
# and filter to only those layers/custom scripts
render_layers <- NULL
render_custom <- NULL
if (exists("render_tasks") && length(render_tasks) > 0) {
  render_layers <- c()
  render_custom <- c()
  # Resolve task aliases (e.g. population → worldpop)
  task_aliases <- yaml::read_yaml(here("source/tasks.yml"))$aliases
  resolved_tasks <- render_tasks
  for (i in seq_along(resolved_tasks)) {
    alias <- task_aliases[[resolved_tasks[i]]]
    if (!is.null(alias) && is.character(alias)) resolved_tasks[i] <- alias
  }
  # Collect layers, custom scripts, and dependencies
  dep_layers <- c()
  for (task_name in resolved_tasks) {
    maps_yml <- here("tasks", task_name, "maps.yml")
    if (file.exists(maps_yml)) {
      task_maps <- yaml::read_yaml(maps_yml)
      if (!is.null(task_maps$layers)) render_layers <- c(render_layers, task_maps$layers)
      if (!is.null(task_maps$custom)) render_custom <- c(render_custom, task_maps$custom)
      # Resolve depends — render dependency layers (standard only, not their custom scripts)
      if (!is.null(task_maps$depends)) {
        for (dep in task_maps$depends) {
          dep_resolved <- task_aliases[[dep]] %||% dep
          if (is.list(dep_resolved)) dep_resolved <- dep_resolved$folder %||% dep
          dep_yml <- here("tasks", dep_resolved, "maps.yml")
          if (file.exists(dep_yml)) {
            dep_maps <- yaml::read_yaml(dep_yml)
            if (!is.null(dep_maps$layers)) dep_layers <- c(dep_layers, dep_maps$layers)
          }
        }
      }
    }
  }
  render_layers <- c(render_layers, dep_layers)
  message("Rendering maps for tasks: ", paste(render_tasks, collapse = ", "))
  if (length(render_layers) > 0) message("  Layers: ", paste(render_layers, collapse = ", "))
  if (length(dep_layers) > 0) message("  Dependency layers: ", paste(dep_layers, collapse = ", "))
  if (length(render_custom) > 0) message("  Custom: ", paste(render_custom, collapse = ", "))
}

message("\n=== Generating City Scan Static Maps ===")

# Autozoom: center on built-up core if <10% of AOI — disabled for now
# static_map_bounds <- tryCatch({
#     lc <- fuzzy_read(spatial_dir, "_lc\\.tif$")
#     if (!inherits(lc, "SpatRaster")) stop("No LC raster")
#     urban_mask <- lc == 50
#     ratio <- sum(values(urban_mask) == 1, na.rm = TRUE) / sum(!is.na(values(lc)))
#     cat(sprintf("\nBuilt-up ratio: %.2f\n", ratio))
#     if (ratio < 0.10) {
#       message("Centering on built-up core\n")
#       urban_extent <- get_built_extent(urban_mask)
#       aspect_buffer(vect(urban_extent, crs = crs(lc)), aspect_ratio, buffer_percent = 0.15)
#     } else {
#       message("Using full AOI (built-up > 10%)\n")
#       aspect_buffer(aoi, aspect_ratio, buffer_percent = 0.05)
#     }
#   }, error = function(e) {
#     message("Using full AOI (fallback: ", e$message, ")\n")
#     aspect_buffer(aoi, aspect_ratio, buffer_percent = 0.05)
#   })
static_map_bounds <- aspect_buffer(aoi, aspect_ratio, buffer_percent = 0.05)

zoom_adjustment <- 0

# Static maps

# Initiate plots list ----------------------------------------------------------
plots <- list()

# Plot AOI & wards -------------------------------------------------------------
plots$aoi <- plot_static_layer(aoi_only = T, plot_aoi = T, plot_wards = !is.null(wards),
  expansion = 1.5, zoom_adj = zoom_adjustment, aoi_stroke = list(color = "yellow", linewidth = 0.4),
  baseplot = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}.jpg",
  captions = include_captions)
  
if (!is.null(wards)) {
  # Find the best label column
  ward_names_col <- intersect(names(wards), c("shapeName", "WARD_NO", "NAME", "name", "Name", "WARD", "ADM2_EN", "ADM2_NAME"))[1]
  if (!is.na(ward_names_col)) {
    ward_centroids <- centroids(wards)
    ward_centroids$label <- as.data.frame(wards)[[ward_names_col]]
    ward_df <- data.frame(
      x = geom(ward_centroids)[, "x"],
      y = geom(ward_centroids)[, "y"],
      label = ward_centroids$label
    )
    plots$wards <- plot_static_layer(aoi_only = T, plot_aoi = T, plot_wards = F,
      expansion = 1.5, zoom_adj = zoom_adjustment, aoi_stroke = list(color = "yellow", linewidth = 0.4),
      baseplot = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}.jpg",
      captions = include_captions) +
      geom_spatvector(data = wards, color = "white", fill = NA, linetype = "solid", linewidth = 0.25) +
      geom_spatial_text_repel(data = ward_df, crs = "epsg:4326",
        aes(x = x, y = y, label = label),
        size = 2.5, fontface = "bold", color = "white",
        segment.size = 0.2, box.padding = 0.3, max.overlaps = 20)
  }
}

# Plot landmarks ---------------------------------------------------------------
landmarks <- fuzzy_read(user_input_dir, "Landmark")
if (inherits(landmarks, "SpatVector")) {
  landmarks <- landmarks %>% project("epsg:4326") %>% select(Name)
  landmarks_df <- mutate(landmarks, x = geom(landmarks)[,"x"], y = geom(landmarks)[,"y"])

  # Combine landmark labels, ward labels, and ward lines, to reduce text overlaps
  landmarks_and_points_to_avoid <-
    rbind(
      mutate(landmarks, label = Name, type = "landmark", fface = "italic", fsize = 1.5),
      mutate(ward_labels, label = WARD_NO, type = "ward", fface = "bold", fsize = 2),
      mutate(as.points(wards) %>% .[rep(c(T, F, F), nrow(.))], label = "", type = "perimeter")
      ) %>%
    mutate(x = geom(.)[,"x"], y = geom(.)[,"y"])
  plots$landmarks <- plot_static_layer(aoi_only = T, plot_aoi = F, plot_wards = T) +
    geom_spatial_point(data = landmarks_df, crs = "epsg:4326", aes(x = x, y = y), size = 0.25) +
    geom_spatial_text_repel(data = landmarks_and_points_to_avoid, crs = "epsg:4326",
      aes(
        x = x, y = y, fontface = fface, size = fsize,
        label = break_lines(label, width = 12, newline = "\n")),
      segment.size = 0.1, box.padding = 0.1, min.segment.length = 0.2, max.time = 2,
      force_pull = 0.8, max.overlaps = 40,
      lineheight = 0.9) +
    scale_size(range = c(1.5, 2), guide = "none")
  save_plot(plot = plots$landmarks, filename = "landmarks.png",
            directory = styled_maps_dir)
}

# Aggregation config -----------------------------------------------------------
aggregate_mode <- city_params$aggregate_mode %||% "none"
aggregate_size <- city_params$aggregate_size %||% 1000

# Build lookups: yaml_key → aggregate_fun and aggregate_mode from maps.yml per task
aggregate_fun_lookup <- list()
aggregate_mode_lookup <- list()
aggregate_size_lookup <- list()
aggregate_coverage_lookup <- list()
smoothing_lookup <- list()  # yaml_key → list(method, window, sigma) when task sets `smoothing:`
task_dirs <- list.dirs(here("tasks"), recursive = FALSE, full.names = FALSE)
for (td in task_dirs) {
  yml <- here("tasks", td, "maps.yml")
  if (file.exists(yml)) {
    task_maps <- yaml::read_yaml(yml)
    afun <- task_maps$aggregate_fun %||% "mean"
    amode <- task_maps$aggregate_mode  # NULL = inherit from city_inputs
    asize <- task_maps$aggregate_size  # NULL = inherit from city_inputs
    acov <- task_maps$min_coverage  # NULL = 0 (no filter)
    smooth_cfg <- task_maps$smoothing  # NULL = no smoothing
    for (lyr in task_maps$layers) {
      aggregate_fun_lookup[[lyr]] <- afun
      if (!is.null(amode)) aggregate_mode_lookup[[lyr]] <- amode
      if (!is.null(asize)) aggregate_size_lookup[[lyr]] <- asize
      if (!is.null(acov)) aggregate_coverage_lookup[[lyr]] <- acov
      if (!is.null(smooth_cfg)) smoothing_lookup[[lyr]] <- smooth_cfg
    }
  }
}

# Standard plots ---------------------------------------------------------------
standard_layers <- unlist(lapply(layer_params, \(x) x$fuzzy_string)) %>%
  discard_at(c("fluvial", "pluvial", "coastal", "combined_flooding", "burnt_area", "elevation",
               "coastal_erosion_baseline", "transect_coastline", "seismic_hazard"))
# Filter to task-specific layers if render_tasks is set
# (check render_tasks not render_layers — c() collapses to NULL, so a task with
# only custom: and no layers: would otherwise fall through and render everything)
if (exists("render_tasks") && length(render_tasks) > 0) {
  standard_layers <- standard_layers[names(standard_layers) %in% render_layers]
}

standard_layers %>%
  map2(names(.), \(fuzzy_string, yaml_key) {
    tryCatch_named(yaml_key, {
      data <- fuzzy_read(spatial_dir, fuzzy_string)
      if (!inherits(data, c("SpatRaster", "SpatVector"))) {
        message(paste("No data for:", yaml_key))
        return(NULL)
      }
      # Select data_variable band for multi-band rasters (e.g. air quality)
      dv <- layer_params[[yaml_key]]$data_variable
      if (!is.null(dv) && inherits(data, "SpatRaster") && nlyr(data) > 1) data <- data[dv]

      # Clip raster to AOI (GEE/XEE rasters may only be bbox-clipped)
      if (inherits(data, "SpatRaster")) data <- crop(data, aoi, mask = TRUE)

      # Lobito: downsample too-fine rasters before plot to avoid 22GB OOM.
      # Auto-detect: only aggregate dense rasters (<50% NA). Sparse rasters
      # like WSF year layers stay at pixel-level — modal of mostly-NA blocks
      # would drop sparse build pixels. Dense layers (land cover, NDVI, etc.)
      # downsample fine.
      if (inherits(data, "SpatRaster")) {
        # Multi-band rasters with no data_variable take Nx memory. Force single band.
        if (nlyr(data) > 1) {
          message(paste("  Multi-band raster (", nlyr(data), "bands), taking first band only"))
          data <- data[[1]]
        }
        afun_agg <- if (isTRUE(layer_params[[yaml_key]]$factor)) "modal" else "mean"
        data <- aggregate_if_too_fine(data, threshold = 5e5, fun = afun_agg)
      }

      # Normal raster plot (always from the untouched original)
      raster_data <- vectorize_if_coarse(data)

      if (nrow(data) > 0) {
        plot <- plot_static_layer(
          data = data, yaml_key = yaml_key,
          plot_aoi = T, plot_wards = !is.null(wards), zoom_adj = zoom_adjustment)
        # add_roads sets its own scale_linewidth_manual keyed by OSM highway
        # values, which overrides any linewidth scale the data layer set. For
        # the roads layer itself (which already maps linewidth to road_type),
        # skip the OSM underlay so the criticality scale survives.
        plot <- if (yaml_key == "roads") add_city_labels(plot) else add_city_labels(add_roads(plot))
        plots[[yaml_key]] <<- plot
        message(paste("Success:", yaml_key))
      }

      # Smoothing (per-task, optional). Produces {layer}_smooth and feeds the
      # smoothed raster into the hex path below. Wrapped in tryCatch so any
      # smoothing failure (terra focal crash, OOM, etc.) skips gracefully
      # without breaking the rest of the render.
      smooth_cfg <- smoothing_lookup[[yaml_key]]
      data_smoothed <- NULL
      if (!is.null(smooth_cfg)) {
        if (!inherits(data, "SpatRaster")) {
          message(paste("  Smoothing skipped (non-raster):", yaml_key))
        } else {
          method <- smooth_cfg$method %||% "gaussian"
          message(paste("  Smoothing:", yaml_key, "|", method))
          data_smoothed <- tryCatch(
            smooth_raster(
              data,
              method = method,
              window = smooth_cfg$window %||% 3,
              sigma  = smooth_cfg$sigma  %||% 1
            ),
            error = function(e) {
              message(paste("  Smooth error:", yaml_key, "-", e$message))
              NULL
            })
          if (!is.null(data_smoothed)) {
            smooth_plot_data <- vectorize_if_coarse(data_smoothed)
            if (nrow(smooth_plot_data) > 0) {
              plots[[paste0(yaml_key, "_smooth")]] <<- add_city_labels(add_roads(plot_static_layer(
                data = smooth_plot_data, yaml_key = yaml_key,
                plot_aoi = T, plot_wards = !is.null(wards), zoom_adj = zoom_adjustment)))
              message(paste("Success:", yaml_key, "(smooth)"))
            }
          }
        }
      }

      # Hex version if aggregate_mode is set (per-task override via maps.yml).
      # When smoothing is active, hex is computed from the smoothed raster.
      layer_agg_mode <- aggregate_mode_lookup[[yaml_key]] %||% aggregate_mode
      layer_agg_size <- aggregate_size_lookup[[yaml_key]] %||% aggregate_size
      if (layer_agg_mode != "none" && inherits(data, "SpatRaster")) {
        layer_min_cov <- aggregate_coverage_lookup[[yaml_key]] %||% 0
        message(paste("  Hexbin:", yaml_key, "| mode:", layer_agg_mode, "| size:", layer_agg_size))
        afun <- aggregate_fun_lookup[[yaml_key]] %||% "mean"
        gpkg_path <- file.path(spatial_dir, paste0(yaml_key, "_hex.gpkg"))
        hex_input <- if (!is.null(data_smoothed)) data_smoothed else data

        # builtup_projected: hex shows km² of projected new built-up per hex,
        # not the flat "Expansion" presence; computed via custom coverage-sum.
        # Re-read raw raster — the upstream aggregate_if_too_fine + "modal"
        # (because factor: TRUE) wipes the sparse 2030 pixels.
        hex_data <- if (yaml_key == "builtup_projected") {
          raw_data <- fuzzy_read(spatial_dir, fuzzy_string) %>% crop(aoi, mask = TRUE)
          pixel_m2 <- as.numeric(terra::cellSize(raw_data, unit = "m")[1, 1])
          hd <- tryCatch(
            hexbin_aggregate(raw_data, aoi, hex_size_m = layer_agg_size,
              fun = function(values, coverage_fraction) {
                built <- sum(coverage_fraction[!is.na(values)]) * pixel_m2 / 1e6
                if (built == 0) NA_real_ else built
              }, min_coverage = layer_min_cov),
            error = function(e) { message(paste("  Hex error:", e$message)); NULL })
          if (!is.null(hd)) writeVector(hd, gpkg_path, overwrite = TRUE)
          hd
        } else tryCatch(
          run_aggregate(hex_input, aoi, layer_agg_mode, layer_agg_size, afun, gpkg_path, min_coverage = layer_min_cov),
          error = function(e) { message(paste("  Hex error:", e$message)); NULL }
        )

        if (!is.null(hex_data) && nrow(hex_data) > 0) {
          # Express hex cell as area rather than flat-to-flat distance.
          # hexbin: cellsize is flat-to-flat d, so area = (sqrt(3)/2) * d^2
          # resample: square cell of side d, so area = d^2
          # h3: read area directly from the geometry (varies by resolution)
          hex_label <- if (layer_agg_mode == "hexbin") {
            area_km2 <- (sqrt(3) / 2) * (layer_agg_size / 1000)^2
            paste0(signif(area_km2, 2), " km\u00b2")
          } else if (layer_agg_mode == "resample") {
            area_km2 <- (layer_agg_size / 1000)^2
            paste0(signif(area_km2, 2), " km\u00b2")
          } else if (layer_agg_mode == "h3") {
            area_km2 <- mean(terra::expanse(hex_data, unit = "km"), na.rm = TRUE)
            paste0(signif(area_km2, 2), " km\u00b2")
          } else {
            paste0(layer_agg_size, " m")
          }
          # Keep yaml subtitle, append bin-size note; fall back to old format if no yaml subtitle
          .yaml_sub <- layer_params[[yaml_key]]$subtitle
          .bin_note <- paste0(hex_label, " hexbins")
          hex_subtitle <- if (yaml_key == "builtup_projected") {
            paste0("km² of new built-up area projected 2025–2030 (", .bin_note, ")")
          } else if (!is.null(.yaml_sub) && nzchar(.yaml_sub)) {
            paste0(.yaml_sub, " (", .bin_note, ")")
          } else {
            paste0(afun, " per ", hex_label, " hex")
          }
          # Lobito: rename hex `value` col to data_variable so plot_static_layer's lookup matches
          if (!is.null(dv) && "value" %in% names(hex_data)) {
            names(hex_data)[names(hex_data) == "value"] <- dv
          }
          # When the hex aggregator turns the values into counts (sum/count),
          # the underlying yaml's factor / breaks / labels no longer apply.
          # Override to a sequential scale derived from the layer's base color.
          .hex_extra <- list()
          if (afun %in% c("sum", "count") || yaml_key == "builtup_projected") {
            .base_cols <- unlist(layer_params[[yaml_key]]$palette)
            .base_color <- if (length(.base_cols) > 1) "#009E73" else .base_cols[[1]]
            .light_end <- {
              m <- grDevices::col2rgb(.base_color) / 255 * 0.35 + 0.65
              grDevices::rgb(m[1, 1], m[2, 1], m[3, 1])
            }
            # Quantile binning so each bin holds ~equal hex count — avoids the
            # "everything in lightest bin" problem when values are right-skewed.
            .binmethod <- if (yaml_key == "builtup_projected") "quantile" else "interval"
            .hex_labels <- if (yaml_key == "builtup_projected") scales::label_number(accuracy = 0.01) else NULL
            .hex_extra <- list(
              factor = FALSE, breaks = NULL, labels = .hex_labels,
              palette = c(.light_end, .base_color),
              bins = 4, binning_method = .binmethod)
          }
          hex_plot <- add_city_labels(add_roads(do.call(plot_static_layer, c(
            list(data = hex_data, yaml_key = yaml_key,
                 subtitle = hex_subtitle,
                 plot_aoi = T, plot_wards = !is.null(wards), zoom_adj = zoom_adjustment),
            .hex_extra))))
          plots[[paste0(yaml_key, "_hex")]] <<- hex_plot
          message(paste("Success:", yaml_key, "(hex)"))
        }
      }

      # Points hex (count): for SpatVector point layers like school_points / health_points,
      # count points per hex when aggregate_mode is enabled. Override yaml params so the
      # plot uses a sequential count fill instead of the original single-color factor scale.
      if (layer_agg_mode == "hexbin" && inherits(data, "SpatVector") &&
          terra::geomtype(data) == "points") {
        message(paste("  Points hex:", yaml_key, "| size:", layer_agg_size))
        gpkg_path <- file.path(spatial_dir, paste0(yaml_key, "_hex.gpkg"))
        hex_data <- tryCatch(
          points_hex_count(data, aoi, hex_size_m = layer_agg_size),
          error = function(e) { message(paste("  Points hex error:", e$message)); NULL }
        )
        if (!is.null(hex_data) && nrow(hex_data) > 0) {
          writeVector(hex_data, gpkg_path, overwrite = TRUE)
          .area_km2 <- (sqrt(3) / 2) * (layer_agg_size / 1000)^2
          .hex_label <- paste0(signif(.area_km2, 2), " km²")
          .yaml_sub <- layer_params[[yaml_key]]$subtitle
          .bin_note <- paste0(.hex_label, " hexbins")
          hex_subtitle <- if (!is.null(.yaml_sub) && nzchar(.yaml_sub)) {
            paste0(.yaml_sub, " (", .bin_note, ")")
          } else {
            paste0("Per ", .hex_label, " hexbin")
          }
          # Multi-category palettes (e.g. infrastructure) get a colorblind-safe
          # fallback (Okabe-Ito bluish green) instead of an averaged muted hue
          # that collapses to low chroma. Single-hue palettes use their own color.
          .base_cols <- unlist(layer_params[[yaml_key]]$palette)
          base_color <- if (length(.base_cols) > 1) "#009E73" else .base_cols[[1]]
          # Light end = base mixed 65% with white — keeps the hue, just lighter
          .light_end <- {
            m <- grDevices::col2rgb(base_color) / 255 * 0.35 + 0.65
            grDevices::rgb(m[1, 1], m[2, 1], m[3, 1])
          }
          hex_plot <- add_city_labels(add_roads(plot_static_layer(
            data = hex_data, yaml_key = yaml_key,
            data_variable = "count", factor = FALSE, labels = NULL,
            palette = c(.light_end, base_color), bins = 4,
            binning_method = "interval",
            subtitle = hex_subtitle,
            plot_aoi = T, plot_wards = !is.null(wards), zoom_adj = zoom_adjustment)))
          plots[[paste0(yaml_key, "_hex")]] <<- hex_plot
          message(paste("Success:", yaml_key, "(points hex)"))
        }
      }
    })
  }) %>% unlist() -> plot_log

# Built-up hatch overlays for hazard maps --------------------------------------
for (layer_name in c("landslides", "liquefaction")) {
  if (!is.null(plots[[layer_name]])) {
    plots[[paste0(layer_name, "_builtup")]] <- add_builtup_hatch(plots[[layer_name]])
  }
}
# Infrastructure has points — hatch goes underneath
if (!is.null(plots[["infrastructure"]])) {
  plots[["infrastructure_builtup"]] <- add_builtup_hatch(plots[["infrastructure"]], underlay = TRUE)
}

# Non-standard static plots ----------------------------------------------------

message("\nCustom maps:")
if (is.null(render_custom) && !exists("render_tasks")) {
  # No task filter — discover all custom scripts from maps.yml files
  render_custom <- c()
  task_dirs <- list.dirs(here("tasks"), recursive = FALSE, full.names = FALSE)
  for (td in task_dirs) {
    yml <- here("tasks", td, "maps.yml")
    if (file.exists(yml)) {
      task_maps <- yaml::read_yaml(yml)
      if (!is.null(task_maps$custom)) render_custom <- c(render_custom, task_maps$custom)
    }
  }
  # # Old hardcoded list (now driven by maps.yml):
  # message("  schools & health proximity"); source(here("core/R/map-schools-health-proximity.R"), local = T)
  # message("  elevation"); source(here("core/R/map-elevation.R"), local = T)
  # message("  deforestation"); source(here("core/R/map-deforestation.R"), local = T)
  # message("  flooding"); source(here("core/R/map-flooding.R"), local = T)
  # message("  historical burnt area"); source(here("core/R/map-historical-burnt-area.R"), local = T)
  # message("  seismic hazard"); source(here("core/R/map-seismic-hazard.R"), local = T)
  # message("  coastal erosion"); source(here("core/R/map-coastal-erosion.R"), local = T)
  # message("  building footprints"); source(here("core/R/plot-building-footprints.R"), local = T)
}
for (script in render_custom) {
  message("  ", basename(script))
  source(here(script), local = T)
}

# source(here("core/R/map-ghs-expansion.R"), local = T)
# source(here("core/R/map-economic-activity-freq.R"), local = T)
# source(here("core/R/map-economic-activity-kde.R"), local = T)


# Save plots -------------------------------------------------------------------
# Switched to for loop because walk required too much memory; uncertain if helps
# For Algeria, reduced time from 1,100 seconds to 1,000 seconds
message(glue("\nSaving {length(plots)} maps to {styled_maps_dir}..."))
for (name in names(plots)) {
  message(glue("  Saving: {name}.png"), appendLF = FALSE)
  tryCatch({
    save_plot(plots[[name]], filename = glue("{name}.png"), directory = styled_maps_dir,
      map_height = map_height + ifelse(include_captions, .2, 0), map_width = map_width, dpi = 200, rel_widths = map_portions)
    message(" ✔")
  },
    error = function(e) message(glue(" ✗ {e$message}"))
  )
}

# See which layers weren't successfully mapped (only show for full renders)
if (!exists("render_tasks")) {
  unmapped <- setdiff(c(names(layer_params), "aoi", "forest_deforest", "burnt_area"), names(plots))
  if (length(unmapped) > 0) warning(paste(length(unmapped), "layers not mapped (not counting flood overlays):\n-", paste(unmapped, collapse = "\n- ")))
}
