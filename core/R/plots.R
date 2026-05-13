# Plots for City Scan

source(here("core/R/setup.R"), local = T)

# 1. Standard City Scan Plots --------------------------------------------------

# tryCatch(source(here("core/R/population-growth.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/urban-extent.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/flooding.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/landcover.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/elevation.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/slope.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/solar-pv.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/fwi.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/age-sex-distribution.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/flood-archive.R"), local = T), error = \(e) warning(e))
tryCatch(source(here("core/R/earthquakes.R"), local = T), error = \(e) warning(e))
