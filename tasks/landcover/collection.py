from core.py.log_module import setup_logger
logger = setup_logger(__name__)

import os

import ee

from core.py import gee_fns as fns


def datacollection(
    aoi,
    city_name,
    output_dir,
    return_raster=False
    ):

    logger.info("Starting Land Cover data collection...")

    # ------------------------------------------------------------------
    # 1. Load AOI as EE Geometry and Image Source
    # ------------------------------------------------------------------

    lc = ee.ImageCollection('ESA/WorldCover/v200').first().select('Map')

    spatial_dir = os.path.join(output_dir, "spatial")
    os.makedirs(spatial_dir, exist_ok=True)
    tif_path = os.path.join(spatial_dir, f"{city_name}_lc.tif")

    from rasterio.enums import Resampling
    lc_rio = fns.tiled_collection(lc, aoi, scale=10, resampling=Resampling.nearest)
    lc_rio.rio.to_raster(tif_path)

    logger.info(f"Land cover raster saved to: {tif_path}")

    if return_raster:
        return lc_rio

    return None
