import os
import ee
from core.py.log_module import setup_logger

logger = setup_logger(__name__)

GEE_PROJECT = os.environ.get("GEE_PROJECT", "city-scan-gee-test")


def _on_cloud_run():
    return os.environ.get("K_SERVICE") is not None


def init_gee():
    """Initialize Google Earth Engine.

    - Cloud Run: uses the service account's ADC automatically.
    - Local: tries existing credentials first, falls back to
      ee.Authenticate(auth_mode='gcloud') if not authenticated.
    """
    try:
        ee.Initialize(project=GEE_PROJECT)
    except Exception:
        logger.info("GEE credentials not found, authenticating via gcloud...")
        ee.Authenticate(auth_mode="gcloud",  scopes=[
                "https://www.googleapis.com/auth/earthengine",
                "https://www.googleapis.com/auth/cloud-platform",
                "https://www.googleapis.com/auth/devstorage.full_control",
            ],)
        ee.Initialize(project=GEE_PROJECT)
    logger.info(f"GEE initialized (project={GEE_PROJECT})")


def init_gcs():
    """Ensure GCS access is available.

    - Cloud Run: ADC is injected by the runtime (nothing to do).
    - Local: relies on `gcloud auth application-default login`.
      google.cloud.storage.Client() picks up ADC automatically.
    """
    if _on_cloud_run():
        logger.info("GCS: running on Cloud Run, using service account ADC")
        return

    # Local: just verify ADC exists so we can give a helpful error early
    if os.name == "nt":  # Windows
        adc_path = os.path.join(os.environ["APPDATA"], "gcloud", "application_default_credentials.json")
    else:
        adc_path = os.path.expanduser("~/.config/gcloud/application_default_credentials.json")
    if not os.path.exists(adc_path):
        raise RuntimeError(
            "GCS credentials not found. Run:\n"
            "  gcloud auth application-default login"
        )
    # Configure GDAL to use the same ADC for /vsigs/ access
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = adc_path
    logger.info("GCS: using local ADC credentials")
