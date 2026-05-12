# Lobito Corridor — Custom Scripts

>The scan was done before the reorg of `core/R`, but functionally should be the same. 

#### Road network — `tasks/accessibility/`

Merge manuallly edited roadnetwork with OSM data via HDX

**Files:** `tasks/accessibility/__init__.py`, `tasks/accessibility/analysis.py`

**Adds:**
- `merge_custom_roads(graph, fgb_paths, snap_tol_m=50)` — snaps FGB lines onto OSM nodes within tolerance, adds them as new edges
- `write_custom_major_roads_basemap(...)` — writes the FGB-only basemap underlay for the static map
- `__init__.py` collect step appends `drc_highways-edit.fgb` and `additional-connector-roads.fgb` after the OSM road download



#### PBF road-graph helper — `core/py/osm_pbf.py`
 Adds `fetch_network(aoi_4326, network_type, cache_dir)` — multi-country PBF download + pyrosm parse + `networkx.compose_all`. Same idea I patched into zambia inline, but generalized. 



#### `source/layers.yml` (+32 lines vs root)
Corridor-tuned color ramps, breakpoints, and labels for layers rendered at corridor scale. Likely contains lobito-specific scale tweaks.

#### Per-task maps.yml — hex aggregation params

Mostly tuning the hex aggregation: aggregate_fun (mean/sum/q25/q33), aggregate_mode: hexbin, aggregate_size, min_coverage. A few add smoothing config (gaussian/median/modal).
#### Map-rendering R scripts — `core/R/map-*.R`

Corridor-scale rasters force extra aggregation/masking before plotting.

- **`map-flooding.R`** — reads `aggregate_mode` / `aggregate_size` / `aggregate_fun` / `min_coverage` / `smoothing` from `tasks/fathom/maps.yml`; crops with `mask = TRUE`; conditionally calls `cell_aggregate()` when `aggregate_mode == "resample"`.
- **`map-gdp-flood.R`** and **`map-sectoral-gdp-flood.R`** — crop with `mask = TRUE` and call `aggregate_if_too_fine(flood_data, threshold = 1e6, fun = "max")` to downsample huge rasters before plotting. 
- **`map-schools-health-proximity.R`** — calls `add_builtup_hatch(plots$..., underlay = TRUE)`






### Stale files — port from root when syncing

Lobito predates the unified refactor — most of core/R, core/config, core/py/raster_module.py, tasks/__main__.py, and tasks/*/collection.py (basic_info, coastal_erosion, fathom, landcover, water_risk, wsf) are just older versions


