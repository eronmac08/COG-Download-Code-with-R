#**Landsat 8 and 9 Cloud Optimized GeoTIFF Downloader**

This R script demonstrates how to download multiple Landsat 8 and 9 **Cloud Optimized GeoTIFFs** (COGs) from an online **STAC** (SpatioTemporal Asset Catalog). The example is set up to pull Level 2, Tier 1, TIR Band 10, and its associated QA_pixel. However, the code is highly customizable and can be easily adapted to pull different bands or assets from the STAC.

**Features:**
**Customizable Band Selection:** By default, it pulls TIR Band 10, but you can change it to any band or asset available in the STAC.
**Pixel Extraction:** The script allows you to extract specific pixels from the images based on points, lines, or polygons.
**Save as CSV:** Extracted pixel data can be saved as a CSV file for further analysis.

This is useful for users who need a subset of an image or data associated with specific geographical features, such as points or polygons, without having to download the entire image.
