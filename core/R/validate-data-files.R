# Validate required data files from slide-list.csv

if (file.exists("slide-list.csv")) {
  message("\nValidating required data files from slide-list.csv...")

  slide_list <- read_csv("slide-list.csv", show_col_types = FALSE)
  required_sources <- slide_list$data_sources %>% na.omit() %>% unique()

  missing_spatial <- c()
  missing_csv <- c()
  empty_csv <- c()
  checked_files <- c()

  for (source in required_sources) {
    files <- str_split(source, " \\| ")[[1]]

    for (file_pattern in files) {
      if (file_pattern %in% checked_files) next
      checked_files <- c(checked_files, file_pattern)

      # Replace {city} placeholder
      file_pattern_expanded <- str_replace_all(file_pattern, "\\{city\\}", tolower(city))

      # Skip global vsigs files and AOI/wards (already validated by loading)
      if (grepl("^/vsigs/", file_pattern_expanded)) next
      if (grepl("AOI|wards", file_pattern_expanded)) next

      # Convert wildcard to regex
      pattern_regex <- gsub("\\.", "\\\\.", file_pattern_expanded)
      pattern_regex <- gsub("\\*", ".*", pattern_regex)

      # Check if file exists
      if (USE_GCS) {
        objects <- gcs_list_objects(GCS_BUCKET, prefix = paste0(scan_id, "/"))
        full_paths <- sub(paste0("^", scan_id, "/"), "", objects$name)
        matched_files <- full_paths[grepl(pattern_regex, full_paths)]
      } else {
        city_dir <- dirname(user_input_dir)
        all_files <- list.files(city_dir, recursive = TRUE, full.names = FALSE)
        matched_files <- all_files[grepl(pattern_regex, all_files)]
      }

      if (length(matched_files) == 0) {
        # File doesn't exist
        if (grepl("\\.csv$", file_pattern_expanded)) {
          missing_csv <- c(missing_csv, file_pattern)
        } else {
          missing_spatial <- c(missing_spatial, file_pattern)
        }
      } else if (grepl("\\.csv$", file_pattern_expanded)) {
        # For CSVs, check if they have data (same as scan-calculations.Rmd)
        csv_filename <- basename(file_pattern_expanded)
        is_empty <- tryCatch({
          # Read exactly like scan-calculations does: paste0("tabular/", filename)
          data <- suppressMessages(read_csv(paste0("tabular/", csv_filename), show_col_types = FALSE))
          is.na(data) || nrow(data) == 0 || ncol(data) == 0
        }, error = function(e) TRUE, warning = function(w) FALSE)

        if (is_empty) {
          empty_csv <- c(empty_csv, file_pattern)
        }
      }
    }
  }

  # Report results
  total_missing <- length(missing_spatial) + length(missing_csv) + length(empty_csv)
  if (total_missing > 0) {
    message("\n⚠ Warning: ", total_missing, " required data files not found or empty:")
    if (length(missing_spatial) > 0) {
      message("\nMissing spatial files:")
      message(paste("  -", head(missing_spatial, 10), collapse = "\n"))
    }
    if (length(missing_csv) > 0) {
      message("\nMissing CSV files:")
      message(paste("  -", head(missing_csv, 10), collapse = "\n"))
    }
    if (length(empty_csv) > 0) {
      message("\nEmpty CSV files:")
      message(paste("  -", head(empty_csv, 10), collapse = "\n"))
    }
  } else {
    message("✓ All required data files found and valid")
  }
}
