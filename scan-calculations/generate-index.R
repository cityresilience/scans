#!/usr/bin/env Rscript
# Pre-render script: reads order.yml for section order, menu.yml for enabled tasks,
# generates index.qmd with include directives

library(yaml)
library(here)

# Detect if here() resolves to scan-calculations/ or city root
in_sc <- file.exists(here("sections.yml"))
city_root <- if (in_sc) normalizePath(here("..")) else here()
sc_dir <- if (in_sc) here() else here("scan-calculations")

order <- read_yaml(file.path(sc_dir, "sections.yml"))
menu <- read_yaml(file.path(city_root, "01-user-input", "menu.yml"))
city_inputs <- read_yaml(file.path(city_root, "01-user-input", "city_inputs.yml"))
city_name <- city_inputs$city_name

lines <- c(
  "---",
  paste0("title: \"", city_name, " City Scan\""),
  "engine: knitr",
  "execute:",
  "  echo: false",
  "  warning: false",
  "  message: false",
  "---",
  "",
  "```{r}",
  "#| label: setup",
  "#| include: false",
  "USE_GCS <<- FALSE",
  "here::i_am(\"scan-calculations/index.qmd\")",
  "source(here::here(\"core/R/setup.R\"))",
  "source(here::here(\"core/R/fns.R\"))",
  "source(here::here(\"core/R/pre-charting.R\"))",
  "dir.create(here(\"03-render-output\", \"plots\"), recursive = TRUE, showWarnings = FALSE)",
  "knitr::opts_chunk$set(error = TRUE)",
  "```",
  ""
)

# Read basic_info.yml for conditional sections
basic_info_path <- list.files(file.path(city_root, "02-process-output", "tabular"), pattern = "basic_info\\.yml$", full.names = TRUE)
basic_info <- if (length(basic_info_path) > 0) read_yaml(basic_info_path[1]) else list()

n_tasks <- 0
for (task in order$sections) {
  # Check if task is enabled in menu (some tasks may not have a menu entry — include anyway)
  menu_enabled <- isTRUE(menu[[task]]) || !(task %in% names(menu))

  if (!menu_enabled) next

  # Skip oxford if city is not in Oxford Economics
  if (task == "oxford" && !isTRUE(basic_info$in_oxford)) next

  # Check charts/index.qmd exists for this task
  task_qmd <- file.path(city_root, "tasks", task, "charts", "index.qmd")
  if (!file.exists(task_qmd)) next

  lines <- c(lines, paste0("{{< include ../tasks/", task, "/charts/index.qmd >}}"), "")
  n_tasks <- n_tasks + 1
}

output_file <- file.path(sc_dir, "index.qmd")
writeLines(lines, output_file)
message("Generated ", output_file, " with ", n_tasks, " task sections")
