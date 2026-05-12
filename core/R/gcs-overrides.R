# GCS Override Functions
# This file is only called when GCS is true and authenticaed. It will override the original functions to return both local AND GCS file paths.  

# Save originals FIRST
list.files_orig <- base::list.files
read_csv_orig <- readr::read_csv
read_yaml_orig <- yaml::read_yaml
file.exists_orig <- base::file.exists
rast_orig <- terra::rast
vect_orig <- terra::vect
read_sf_orig <- sf::read_sf
st_read_orig <- sf::st_read


# create lookup tables for GCS and local files
if (exists("USE_GCS") && USE_GCS) {
  message("\n=== GCS OVERRIDES DEBUG ===")
  message("Building file lookups for scan_id: ", scan_id)

  # Scan-specific files from GCS (may not exist if running locally)
  gcs_file_lookup <- tryCatch({
    gcs_all_files <- gcs_list_objects(GCS_BUCKET, prefix = paste0(scan_id, "/"))
    if (is.null(gcs_all_files) || nrow(gcs_all_files) == 0) character(0)
    else gcs_all_files$name
  }, error = function(e) { message("No scan files on GCS (local mode)"); character(0) })

  # Global private data files from GCS
  gcs_global_file_lookup <- tryCatch({
    gcs_global_files <- gcs_list_objects(GLOBAL_DATA_BUCKET)
    if (is.null(gcs_global_files) || nrow(gcs_global_files) == 0) character(0)
    else gcs_global_files$name
  }, error = function(e) { message("Could not list global data bucket"); character(0) })

  # Global public data files from GCS
  gcs_public_file_lookup <- tryCatch({
    gcs_public_files <- gcs_list_objects("city-scan-global-public")
    if (is.null(gcs_public_files) || nrow(gcs_public_files) == 0) character(0)
    else gcs_public_files$name
  }, error = function(e) { message("Could not list public bucket"); character(0) })

  # Local files
  local_file_lookup <- if (exists("city_dir") && city_dir != ".") {
    list.files_orig(city_dir, recursive = TRUE, full.names = FALSE)
  } else {
    character(0)
  }

  message("Available: ", length(gcs_file_lookup), " scan files, ",
          length(gcs_global_file_lookup), " global private files, ",
          length(gcs_public_file_lookup), " global public files, ",
          length(local_file_lookup), " local files")

  # Show first few scan files for debugging
  if (length(gcs_file_lookup) > 0) {
    message("First 3 scan files: ", paste(head(gcs_file_lookup, 3), collapse = ", "))
  }
}


# Helper: strip city_dir prefix from absolute paths to get relative path for GCS lookup
make_relative <- function(path) {
  if (exists("city_dir") && city_dir != "." && startsWith(path, city_dir)) {
    rel <- sub(paste0("^", gsub("([.])", "\\\\\\1", city_dir), "/?"), "", path)
    if (nchar(rel) == 0) return(".")
    return(rel)
  }
  return(path)
}

# Override list.files
list.files <- function(path = ".", pattern = NULL, all.files = FALSE, full.names = FALSE, recursive = FALSE, ...) {

  # Get local files — use absolute path for local
  local_path <- if (exists("city_dir") && city_dir != "." && !startsWith(path, city_dir)) {
    file.path(city_dir, path)
    } else {
    path
    }

  local_files <- list.files_orig(local_path, pattern, all.files, full.names, recursive, ...)

  # Get GCS scan-specific files — use relative path for GCS
  path_clean <- gsub("/+$", "", make_relative(path))
  search_prefix <- paste0(scan_id, "/", path_clean, "/")
  gcs_matches <- gcs_file_lookup[startsWith(gcs_file_lookup, search_prefix)]
  gcs_scan_files <- sub(paste0("^", search_prefix), "", gcs_matches)
  gcs_scan_files <- gcs_scan_files[nchar(gcs_scan_files) > 0]

  # Apply recursive filter
  if (!recursive) {
    gcs_scan_files <- gcs_scan_files[!grepl("/", gcs_scan_files)]
  }

  # Apply pattern
  if (!is.null(pattern)) {
    gcs_scan_files <- gcs_scan_files[grepl(pattern, gcs_scan_files)]
  }

  # Apply full.names
  if (full.names) {
    gcs_scan_files <- file.path(path_clean, gcs_scan_files)
  }

  # Get GCS global files
  global_search_prefix <- paste0(path_clean, if (path_clean != ".") "/" else "")
  gcs_global_matches <- gcs_global_file_lookup[startsWith(gcs_global_file_lookup, global_search_prefix)]
  gcs_global_files <- sub(paste0("^", global_search_prefix), "", gcs_global_matches)
  gcs_global_files <- gcs_global_files[nchar(gcs_global_files) > 0]

  # Apply recursive filter for global
  if (!recursive) {
    gcs_global_files <- gcs_global_files[!grepl("/", gcs_global_files)]
  }

  # Apply pattern for global
  if (!is.null(pattern)) {
    gcs_global_files <- gcs_global_files[grepl(pattern, gcs_global_files)]
  }

  # Apply full.names for global
  if (full.names && path_clean != ".") {
    gcs_global_files <- file.path(path_clean, gcs_global_files)
  }

  # Combine all sources
  return(unique(c(local_files, gcs_scan_files, gcs_global_files)))
}


# Override file.exists - check local, scan GCS, and global GCS
  file.exists <- function(...) {
    files <- c(...)

    results <- sapply(files, function(filepath) {
      if (is.na(filepath) || is.null(filepath)) return(FALSE)
      # Build full local path with city_dir
      local_path <- if (exists("city_dir") && city_dir != "." && !startsWith(filepath, city_dir)) {
        file.path(city_dir, filepath)
      } else {
        filepath
      }

      # Check local first
      if (file.exists_orig(local_path)) return(TRUE)

      # Check GCS if enabled
      if (exists("USE_GCS") && USE_GCS) {
        # Use relative path for GCS lookup
        rel_path <- make_relative(filepath)

        # Check scan-specific GCS
        if (exists("gcs_file_lookup")) {
          gcs_path <- paste0(scan_id, "/", rel_path)
          gcs_path <- gsub("//", "/", gcs_path)
          if (gcs_path %in% gcs_file_lookup) return(TRUE)
        }

        # Check global private GCS
        if (exists("gcs_global_file_lookup")) {
          if (filepath %in% gcs_global_file_lookup) return(TRUE)
        }

        # Check global public GCS
        if (exists("gcs_public_file_lookup")) {
          if (filepath %in% gcs_public_file_lookup) return(TRUE)
        }
      }

      return(FALSE)
    })

    return(results)
  }


# Helper function to create a CSV parser with col_types support for gcs_get_object
# Usage: gcs_get_object(path, bucket, parseFunction = make_csv_parser(col_types = "ccd"))
make_csv_parser <- function(col_types = NULL, ...) {
  function(x) {
    read_csv_orig(x, col_types = col_types, ...)
  }
}

# Override read_csv - download from GCS to temp and read with original read_csv
read_csv <- function(file, ...) {
  # Check local first
  local_path <- if (exists("city_dir") && city_dir != "." && !startsWith(file, city_dir)) {
    file.path(city_dir, file)
  } else {
    file
  }

  if (file.exists_orig(local_path)) {
    return(read_csv_orig(local_path, ...))
  }

  # Check GCS if enabled
  if (USE_GCS) {
    rel_path <- make_relative(file)
    # Check if in scan-specific GCS
    if (exists("gcs_file_lookup")) {
      gcs_path <- paste0(scan_id, "/", rel_path)
      gcs_path <- gsub("//", "/", gcs_path)
      if (gcs_path %in% gcs_file_lookup) {
        tmp <- tempfile(fileext = ".csv")
        suppressMessages(gcs_get_object(gcs_path, bucket = GCS_BUCKET, saveToDisk = tmp))
        return(read_csv_orig(tmp, ...))
      }
    }

    # Check if in global private GCS
    if (exists("gcs_global_file_lookup") && rel_path %in% gcs_global_file_lookup) {
      tmp <- tempfile(fileext = ".csv")
      suppressMessages(gcs_get_object(rel_path, bucket = GLOBAL_DATA_BUCKET, saveToDisk = tmp))
      return(read_csv_orig(tmp, ...))
    }

    # Check if in global public GCS
    if (exists("gcs_public_file_lookup") && rel_path %in% gcs_public_file_lookup) {
      tmp <- tempfile(fileext = ".csv")
      suppressMessages(gcs_get_object(rel_path, bucket = "city-scan-global-public", saveToDisk = tmp))
      return(read_csv_orig(tmp, ...))
    }
  }

  # Fall back to original (will error if file doesn't exist)
  read_csv_orig(file, ...)
}

# Override read_yaml - download to temp and read
read_yaml <- function(file, ...) {
  # Check local first
  local_path <- if (exists("city_dir") && city_dir != "." && !startsWith(file, city_dir)) {
    file.path(city_dir, file)
  } else {
    file
  }

  if (file.exists_orig(local_path)) {
    return(read_yaml_orig(local_path, ...))
  }

  # Check GCS if enabled
  if (USE_GCS) {
    rel_path <- make_relative(file)
    # Check if in scan-specific GCS
    if (exists("gcs_file_lookup")) {
      gcs_path <- paste0(scan_id, "/", rel_path)
      gcs_path <- gsub("//", "/", gcs_path)
      if (gcs_path %in% gcs_file_lookup) {
        tmp <- tempfile(fileext = ".yml")
        suppressMessages(gcs_get_object(gcs_path, bucket = GCS_BUCKET, saveToDisk = tmp))
        return(read_yaml_orig(tmp, ...))
      }
    }

    # Check if in global GCS (though unlikely for YAML files)
    if (exists("gcs_global_file_lookup") && rel_path %in% gcs_global_file_lookup) {
      tmp <- tempfile(fileext = ".yml")
      suppressMessages(gcs_get_object(rel_path, bucket = GLOBAL_DATA_BUCKET, saveToDisk = tmp))
      return(read_yaml_orig(tmp, ...))
    }
  }

  # Fall back to original (will error if file doesn't exist)
  read_yaml_orig(file, ...)
}



# Override rast - try /vsigs/ path if local file doesn't exist
rast <- function(x, ...) {
  # If x is not a character (file path), just use original
  if (!is.character(x) || length(x) == 0) {
    return(rast_orig(x, ...))
  }

  # Try original first (suppress warnings for missing local files)
  result <- suppressWarnings(tryCatch(rast_orig(x, ...), error = function(e) NULL))
  if (!is.null(result)) return(result)

  # If failed and USE_GCS is enabled, try /vsigs/ paths
  if (USE_GCS) {
    rel_path <- make_relative(x)
    # Try scan-specific GCS path
    if (exists("gcs_file_lookup")) {
      gcs_path <- paste0(scan_id, "/", rel_path)
      gcs_path <- gsub("//", "/", gcs_path)
      if (gcs_path %in% gcs_file_lookup) {
        vsigs_path <- paste0("/vsigs/", GCS_BUCKET, "/", gcs_path)
        result <- tryCatch(rast_orig(vsigs_path, ...), error = function(e) NULL)
        if (!is.null(result)) return(result)
      }
    }

    # Try global GCS path (less common for rasters)
    if (exists("gcs_global_file_lookup") && rel_path %in% gcs_global_file_lookup) {
      vsigs_path <- paste0("/vsigs/", GLOBAL_DATA_BUCKET, "/", rel_path)
      result <- tryCatch(rast_orig(vsigs_path, ...), error = function(e) NULL)
      if (!is.null(result)) return(result)
    }
  }

  # Fall back to original (will error)
  rast_orig(x, ...)
}

# Override vect - try /vsigs/ path if local file doesn't exist
vect <- function(x, ...) {
  # If x is not a character (file path), just use original
  if (!is.character(x) || length(x) == 0) {
    return(vect_orig(x, ...))
  }

  # Try original first (suppress warnings for missing local files)
  result <- suppressWarnings(tryCatch(vect_orig(x, ...), error = function(e) NULL))
  if (!is.null(result)) return(result)

  # If failed and USE_GCS is enabled, try /vsigs/ paths
  if (USE_GCS) {
    rel_path <- make_relative(x)
    # Try scan-specific GCS path
    if (exists("gcs_file_lookup")) {
      gcs_path <- paste0(scan_id, "/", rel_path)
      gcs_path <- gsub("//", "/", gcs_path)
      if (gcs_path %in% gcs_file_lookup) {
        vsigs_path <- paste0("/vsigs/", GCS_BUCKET, "/", gcs_path)
        result <- tryCatch(vect_orig(vsigs_path, ...), error = function(e) NULL)
        if (!is.null(result)) return(result)
      }
    }

    # Try global GCS path
    if (exists("gcs_global_file_lookup") && rel_path %in% gcs_global_file_lookup) {
      vsigs_path <- paste0("/vsigs/", GLOBAL_DATA_BUCKET, "/", rel_path)
      result <- tryCatch(vect_orig(vsigs_path, ...), error = function(e) NULL)
      if (!is.null(result)) return(result)
    }
  }

  # Fall back to original (will error)
  vect_orig(x, ...)
}

# Override read_sf - try /vsigs/ path if local file doesn't exist
read_sf <- function(dsn, ...) {
  # If dsn is not a character (file path), just use original
  if (!is.character(dsn) || length(dsn) == 0) {
    return(read_sf_orig(dsn, ...))
  }

  # Try original first (suppress warnings for missing local files)
  result <- suppressWarnings(tryCatch(read_sf_orig(dsn, ...), error = function(e) NULL))
  if (!is.null(result)) return(result)

  # If failed and USE_GCS is enabled, try /vsigs/ paths
  if (USE_GCS) {
    rel_path <- make_relative(dsn)
    # Try scan-specific GCS path
    if (exists("gcs_file_lookup")) {
      gcs_path <- paste0(scan_id, "/", rel_path)
      gcs_path <- gsub("//", "/", gcs_path)
      if (gcs_path %in% gcs_file_lookup) {
        vsigs_path <- paste0("/vsigs/", GCS_BUCKET, "/", gcs_path)
        result <- suppressWarnings(tryCatch(read_sf_orig(vsigs_path, ...), error = function(e) NULL))
        if (!is.null(result)) return(result)
      }
    }

    # Try global GCS path
    if (exists("gcs_global_file_lookup") && rel_path %in% gcs_global_file_lookup) {
      vsigs_path <- paste0("/vsigs/", GLOBAL_DATA_BUCKET, "/", rel_path)
      result <- tryCatch(read_sf_orig(vsigs_path, ...), error = function(e) NULL)
      if (!is.null(result)) return(result)
    }
  }

  # Fall back to original (will error)
  read_sf_orig(dsn, ...)
}

# Override st_read - try /vsigs/ path if local file doesn't exist
st_read <- function(dsn, ...) {
  # If dsn is not a character (file path), just use original
  if (!is.character(dsn) || length(dsn) == 0) {
    return(st_read_orig(dsn, ...))
  }

  # Try original first (suppress warnings for missing local files)
  result <- suppressWarnings(tryCatch(st_read_orig(dsn, ...), error = function(e) NULL))
  if (!is.null(result)) return(result)

  # If failed and USE_GCS is enabled, try /vsigs/ paths
  if (USE_GCS) {
    rel_path <- make_relative(dsn)
    # Try scan-specific GCS path
    if (exists("gcs_file_lookup")) {
      gcs_path <- paste0(scan_id, "/", rel_path)
      gcs_path <- gsub("//", "/", gcs_path)
      if (gcs_path %in% gcs_file_lookup) {
        vsigs_path <- paste0("/vsigs/", GCS_BUCKET, "/", gcs_path)
        result <- tryCatch(st_read_orig(vsigs_path, ...), error = function(e) NULL)
        if (!is.null(result)) return(result)
      }
    }

    # Try global GCS path
    if (exists("gcs_global_file_lookup") && rel_path %in% gcs_global_file_lookup) {
      vsigs_path <- paste0("/vsigs/", GLOBAL_DATA_BUCKET, "/", rel_path)
      result <- tryCatch(st_read_orig(vsigs_path, ...), error = function(e) NULL)
      if (!is.null(result)) return(result)
    }
  }

  # Fall back to original (will error)
  st_read_orig(dsn, ...)
}


# Upload outputs to GCS
upload_outputs_to_gcs <- function() {
  if (USE_GCS && exists("GCS_UPLOAD") && GCS_UPLOAD) {
    message("Uploading outputs to GCS...")
    gcs_upload("03-render-output",
               bucket = GCS_BUCKET,
               name = paste0(scan_id, "/03-render-output/"),
               predefinedAcl = "bucketLevel")
    message("✓ Outputs uploaded")
  }
}
