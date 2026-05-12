# Read flood aggregate settings from fathom maps.yml
.flood_maps <- tryCatch(yaml::read_yaml(here("tasks/fathom/maps.yml")), error = function(e) list())
.flood_agg_mode <- .flood_maps$aggregate_mode %||% (city_params$aggregate_mode %||% "none")
.flood_agg_size <- .flood_maps$aggregate_size %||% (city_params$aggregate_size %||% 1000)
.flood_agg_fun <- .flood_maps$aggregate_fun %||% "max"
.flood_min_coverage <- .flood_maps$min_coverage %||% 0
.flood_smooth_cfg <- .flood_maps$smoothing  # NULL when smoothing off

plot_flooding <- function(flood_type) {
  tryCatch_named(flood_type, {
    file <- fuzzy_read(spatial_dir, glue("{flood_type}_2020.tif$"), paste)
    if (is.na(file)) return(NULL)
    message(glue("  Loading {flood_type}: {file}"))
    flood_rast <- rast(file)[[1]]
    message(glue("  nlyr: {nlyr(flood_rast)}, dim: {nrow(flood_rast)}x{ncol(flood_rast)}"))
    message("  Cropping to AOI...")
    flood_data <- terra::crop(flood_rast, aoi, mask = TRUE)
    message(glue("  After crop: {nrow(flood_data)}x{ncol(flood_data)}"))
    if (.flood_agg_mode == "resample") {
      message(glue("  Aggregating to {.flood_agg_size}m with {.flood_agg_fun}"))
      flood_data <- cell_aggregate(flood_data, target_m = .flood_agg_size, fun = .flood_agg_fun)
      message(glue("  After aggregate: {nrow(flood_data)}x{ncol(flood_data)}"))
    }
    # Temporary fix for if layer is all NAs
    if (all(is.na(values(flood_data)))) values(flood_data)[1] <- 0
    # Lobito: downsample too-fine flood raster before plot to avoid 22GB OOM
    flood_data <- aggregate_if_too_fine(flood_data, threshold = 1e6, fun = "max")
    message(glue("  After aggregate_if_too_fine: {nrow(flood_data)}x{ncol(flood_data)}"))
    message("  Plotting...")
    plots[[flood_type]] <<- plot_static_layer(
      flood_data, yaml_key = flood_type,
      plot_aoi = T, plot_wards = !is.null(wards))
    message(glue("  {flood_type} plot done"))
    # Smoothed version of flood (optional, fathom maps.yml `smoothing:` block).
    # Wrapped in tryCatch so any failure skips smoothing for this flood_type
    # without breaking the rest of the render.
    flood_smoothed <- NULL
    if (!is.null(.flood_smooth_cfg)) {
      method <- .flood_smooth_cfg$method %||% "gaussian"
      message(glue("  Smoothing: {flood_type} | {method}"))
      flood_smoothed <- tryCatch(
        smooth_raster(
          flood_data,
          method = method,
          window = .flood_smooth_cfg$window %||% 3,
          sigma  = .flood_smooth_cfg$sigma  %||% 1
        ),
        error = function(e) {
          message(glue("  Smooth error: {flood_type} - {e$message}"))
          NULL
        })
      if (!is.null(flood_smoothed)) {
        plots[[glue("{flood_type}_smooth")]] <<- plot_static_layer(
          flood_smoothed, yaml_key = flood_type,
          plot_aoi = T, plot_wards = !is.null(wards))
        message(glue("  {flood_type} smooth done"))
      }
    }
    flood_for_overlay <- if (!is.null(flood_smoothed)) flood_smoothed else flood_data
    # Hex version of flood (fed from smoothed raster when smoothing is on).
    # Gated by fathom's own maps.yml (.flood_agg_mode) so a task can opt out
    # of hex even when city_params turns it on for other layers.
    if (.flood_agg_mode != "none") {
      hex_size <- .flood_agg_size
      gpkg_path <- file.path(spatial_dir, paste0(flood_type, "_hex.gpkg"))
      flood_hex <- tryCatch(
        run_aggregate(flood_for_overlay, aoi, "hexbin", hex_size, .flood_agg_fun, gpkg_path,
                      min_coverage = .flood_min_coverage),
        error = function(e) { message(glue("  Flood hex error: {e$message}")); NULL })
      if (!is.null(flood_hex) && nrow(flood_hex) > 0) {
        # hexbin_aggregate names its output column "value", but layers.yml for
        # fluvial/pluvial/coastal selects data_variable="max_probability" — rename
        # so plot_static_layer finds the expected column.
        dv <- layer_params[[flood_type]]$data_variable
        if (!is.null(dv) && "value" %in% names(flood_hex)) {
          names(flood_hex)[names(flood_hex) == "value"] <- dv
        }
        # Build hex_subtitle the same way as maps-static.R: yaml subtitle + bin-size note.
        .area_km2 <- (sqrt(3) / 2) * (hex_size / 1000)^2
        .hex_label <- paste0(signif(.area_km2, 2), " km²")
        .yaml_sub <- layer_params[[flood_type]]$subtitle
        .bin_note <- paste0(.hex_label, " hexbins")
        flood_hex_subtitle <- if (!is.null(.yaml_sub) && nzchar(.yaml_sub)) {
          paste0(.yaml_sub, " (", .bin_note, ")")
        } else {
          paste0(.flood_agg_fun, " per ", .hex_label, " hex")
        }
        plots[[glue("{flood_type}_hex")]] <<- plot_static_layer(
          flood_hex, yaml_key = flood_type,
          subtitle = flood_hex_subtitle,
          plot_aoi = T, plot_wards = !is.null(wards))
        message(glue("  {flood_type} hex done"))
      }
    }
    # Composites use the ORIGINAL flood raster (not smoothed, not hexed) —
    # per spec: "flood should not be hexed" in combos; smoothed output stays
    # on the standalone _smooth plot only.
    for (pop_key in grep("^population", names(plots), value = TRUE)) {
      plots[[glue("{flood_type}_{pop_key}")]] <<-
        plot_static_layer(flood_data, yaml_key = flood_type, baseplot = plots[[pop_key]])
    }
    # WSF composites: flood raster over every wsf* plot (base, _hex, _smooth,
    # wsf_harmonized, wsf_tracker, etc.) — mirrors the population loop above.
    for (wsf_key in grep("^wsf", names(plots), value = TRUE)) {
      wsf_ordered <- plots[[wsf_key]] + guides(fill = guide_legend(order = 2))
      p_flood_wsf <- plot_static_layer(flood_data, yaml_key = flood_type, baseplot = wsf_ordered)
      p_flood_wsf <- p_flood_wsf + guides(fill = guide_legend(order = 1))
      plots[[glue("{flood_type}_{wsf_key}")]] <<- p_flood_wsf
    }
    if (!is.null(plots$infrastructure)) plots[[glue("{flood_type}_infrastructure")]] <<-
      plot_static_layer(flood_data, yaml_key = flood_type, baseplot = plots$infrastructure)
    # Built-up area 2025 hatch overlay on flood maps
    if (exists("builtup_extent_2025") && !is.null(builtup_extent_2025)) {
      builtup_clipped <- sf::st_intersection(sf::st_as_sf(builtup_extent_2025), sf::st_as_sf(aoi))
      plots[[glue("{flood_type}_builtup")]] <<- plots[[flood_type]] +
        ggpattern::geom_sf_pattern(
          data = builtup_clipped, color = NA, fill = NA,
          aes(pattern = "2025 built-up area"),
          pattern_spacing = 0.0125, pattern_fill = NA,
          pattern_density = 0.5, pattern_size = 0.25) +
        ggpattern::scale_pattern_manual(values = "stripe", name = "") +
        coord_3857_bounds(static_map_bounds)
    }
  })
}

flooding_yaml_keys <- c("fluvial", "pluvial", "coastal", "combined_flooding")
walk(flooding_yaml_keys, plot_flooding)
