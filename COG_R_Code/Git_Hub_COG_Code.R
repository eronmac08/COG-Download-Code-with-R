library(rstac)
library(httr)
library(rvest)
library(sf)
library(terra)
library(raster)
library(stringr)

# General configuration for date range and years
# The date range defines the start and end dates for querying satellite images.
# The 'start_month' and 'end_month' are in MM-DD format, and the 'years' vector defines which years to query.

start_month <- "01-01"  # Start date for the date range (Month-Day format)
end_month <- "05-31"    # End date for the date range (Month-Day format)
years <- 2014:2024      # A range of years to query, e.g., from 2014 to 2024

# Login session setup
# This section sets up a login session using a website URL. 
# Replace 'login_url' with the URL of the website where you need to authenticate.

login_url <- "https://example.com/login"  # Replace this with the actual login URL
h <- handle(login_url)

# Extract CSRF token (if needed) from the login page to ensure the session is valid
response <- httr::GET(handle = h)  # Get the login page content
html <- content(response)  # Parse the HTML content of the page
csrf_val <- html %>% html_elements("input") %>% html_attr("value")  # Extract the CSRF token from the page's input fields
csrf_val <- csrf_val[3]  # Typically, the CSRF token is the 3rd input field, but confirm this for your site

# Replace the credentials with your login details. Alternatively, you could prompt for user input.
credentials <- list(
  username = "your_username_here",  # Replace with your username or ask for input
  password = "your_password_here",  # Replace with your password or ask for input
  csrf = csrf_val  # CSRF token value retrieved earlier
)

# Send the login request to authenticate
login_response <- httr::POST(handle = h, body = credentials)
if (login_response$status_code != 200) {
  stop("Login failed. Please check your credentials.")  # Stop if login fails
}

# Initialize lists to store URLs for Band 10 and QA_PIXEL data
# These lists will hold the URLs of the data needed for further processing
B10_urls <- list()
qa_pixel_urls <- list()

# Loop over the years to construct the datetime range and query the satellite data
for (year in years) {
  # Construct the datetime range string for each year using the format: year-start_monthT00:00:00Z/year-end_monthT00:00:00Z
  datetime_range <- sprintf("%s-%sT00:00:00Z/%s-%sT00:00:00Z", year, start_month, year, end_month)
  
  # Query the STAC server to search for satellite images for each year in the specified date range
  # Replace the STAC server URL and collection name with appropriate ones for your use case
  s_obj <- stac("https://example-stac-server.com")  # Replace with actual STAC server URL
  
  it_obj <- s_obj %>%
    stac_search(
      collections = "your_collection_name",  # Modify this to reflect the collection name you are querying (e.g., "landsat-c2l2-st")
      bbox = c(-123.417194816, 49.543223663, -123.027327057, 49.735960665),  # Adjust bounding box for the area of interest
      datetime = datetime_range,  # Use the datetime range constructed earlier
      limit = 2000  # Limit the number of results returned (modify if necessary)
    ) %>%
    get_request()  # Get the response from the server
  
  # Loop through the returned items to extract the necessary URLs
  for (i in seq_along(it_obj$features)) {
    item <- it_obj$features[[i]]
    
    # Skip unwanted data items (e.g., certain satellites like LE07) based on asset URLs
    # Modify conditions to exclude other types if needed
    if (grepl("LE07", item$assets$lwir11$href) || grepl("LE07", item$assets$qa_pixel$href)) {
      next  # Skip this item if it's from the LE07 satellite (can add other conditions if necessary)
    }
    
    # Extract URLs for Band 10 and QA_PIXEL for LC08 or LC09 satellites
    if (grepl("LC08", item$assets$lwir11$href) | grepl("LC09", item$assets$lwir11$href)) {
      B10_urls <- append(B10_urls, item$assets$lwir11$href)  # Add Band 10 URL
      qa_pixel_urls <- append(qa_pixel_urls, item$assets$qa_pixel$href)  # Add QA_PIXEL URL
    }
  }
}

# Set the output directory where the raw raster data will be saved
# Make sure to update this path to where you want the downloaded images to be stored
output_dir <- "D:/Raw_Raster_Images/"  # Replace with your preferred directory

# Combine all URLs (Band 10 and QA_PIXEL) into a single list and loop through them to download each file
all_urls <- c(B10_urls, qa_pixel_urls)

# Loop through all the URLs and download the corresponding files
for(url in all_urls) {
  print(url)  # Print the current URL for tracking
  
  # Send GET request to download the file
  response <- httr::GET(url, handle = h)
  
  # Ensure the request was successful (status code 200)
  if (response$status_code != 200) {
    stop("Failed to retrieve data from the URL")  # Stop if the data couldn't be downloaded
  }
  
  # Create a unique filename based on the URL
  # This step helps avoid overwriting files and makes it easier to identify the downloaded file
  match_string <- "LC0"  # Adjust this part based on the unique string pattern in the URL
  unique_id <- sub(paste0(".*(", match_string, ".*)"), "\\1", url)  # Extract the unique ID from the URL
  file_path <- paste0(output_dir, unique_id)  # Combine the directory and unique ID for the file path
  
  # Save the raw data (binary) to a file
  writeBin(content(response, "raw"), file_path)
}

# Raster masking and processing
# In this section, we apply a mask to Band 10 data using QA_PIXEL data based on predefined values.
# The purpose is to mask out areas that don't meet certain criteria, like 'clear land' and 'clear water'.

raster_folder <- 'D:/Raw_Raster_Images'  # Replace with your raster data folder

# List all the QA_PIXEL and Band 10 files in the folder
qa_pixel_files <- list.files(raster_folder, pattern = "QA_PIXEL.*\\.TIF$", full.names = TRUE, recursive = FALSE)
band_10_files <- list.files(raster_folder, pattern = "ST_B10.*\\.TIF$", full.names = TRUE, recursive = FALSE)

# Sort the QA_PIXEL and Band 10 files to ensure the correct pairing
qa_pixel_files <- sort(qa_pixel_files)
band_10_files <- sort(band_10_files)

# Loop through each pair of QA_PIXEL and Band 10 files to apply the mask
for (i in 1:length(qa_pixel_files)) {
  qa_pixel_raster <- raster(qa_pixel_files[i])  # Load the QA_PIXEL raster
  band_10_raster <- raster(band_10_files[i])    # Load the Band 10 raster
  
  # Create a mask based on QA_PIXEL values (e.g., 21952 for clear water and 21824 for clear land)
  mask <- qa_pixel_raster
  mask[!qa_pixel_raster %in% c(21952, 21824)] <- NA  # Set all values except 21952 and 21824 to NA (NoData)
  
  # Apply the mask to Band 10 raster (this step removes unwanted data outside the mask)
  band_10_masked <- mask(band_10_raster, mask)
  
  # Define the output path for the masked Band 10 raster
  output_file <- file.path("D:/Masked_B10_Images", paste0("masked_B10_", basename(band_10_files[i])))
  
  # Save the masked raster data to disk
  writeRaster(band_10_masked, output_file, format = "GTiff", overwrite = TRUE)  # Allow overwriting if the file exists
  print(paste("Processed and masked:", basename(band_10_files[i])))
}

# Extract raster values at specified points (from a shapefile)
# This section allows you to extract pixel values from the masked Band 10 rasters at specific points.
# You need a shapefile containing the points (e.g., a CSV with coordinates or a polygon shapefile).

shapefile <- vect("path_to_your_shapefile.shp")  # Replace with the actual path to your shapefile

# Define the directory to store CSV files with extracted values
csv_output_dir <- "D:/CSV_TempValues"  # Replace with desired output directory for CSV files

# Ensure the CSV output directory exists
if (!dir.exists(csv_output_dir)) {
  dir.create(csv_output_dir)
}

# List the raster files in the masked images directory
list_rasters <- list.files(path = "D:/Masked_B10_Images", pattern = "*.TIF", full.names = TRUE)

# Loop through each raster file and extract values at the points in the shapefile
for (raster_name in list_rasters) {
  r <- rast(raster_name)  # Read the raster file
  projected_sf <- terra::project(shapefile, r)  # Project the shapefile to match the raster's coordinate reference system
  dt <- terra::extract(r, shapefile, bind = TRUE)  # Extract raster values at shapefile points
  
  # Create a unique CSV filename based on the raster filename
  out_name <- file.path(csv_output_dir, gsub(".TIF", ".csv", basename(raster_name)))
  
  # Write the extracted values to a CSV file
  tryCatch({
    write.csv(dt, out_name, row.names = FALSE)  # Write the data to CSV
  }, error = function(e) {
    message(paste("Error writing file:", out_name, "-", e$message))  # Handle errors if writing fails
  })
}

# Combine all extracted CSV files into a single data frame
csv_files <- list.files(path = csv_output_dir, pattern = "*.csv", full.names = TRUE)
csv_list <- list()

for (csv_file in csv_files) {
  df <- read.csv(csv_file)  # Read each CSV file
  
  # Extract date information from the filename (adjust based on naming convention)
  date <- substr(basename(csv_file), 29, 36)  # Modify indices to match your filename format
  date <- as.Date(date, format = "%Y%m%d")  # Convert the extracted string into a Date object
  
  # Add the 'Date' column to the dataframe
  df$Date <- date
  
  # Rename columns to ensure consistency across files (e.g., 'masked_B10' column renamed to 'pixel_values')
  masked_b10_column <- grep("masked_B10", names(df), value = TRUE)
  if (length(masked_b10_column) > 0) {
    df$pixel_values <- df[[masked_b10_column]]  # Create a 'pixel_values' column
    df <- df[, c("POINT_ID", "pixel_values", "Date")]  # Select relevant columns
  }
  
  # Add the data frame to the list
  csv_list[[csv_file]] <- df
}

# Combine all CSV data frames into one large data frame
final_df <- do.call(rbind, csv_list)

# Save the combined data frame to a CSV file
output_file <- "D:/Combined_CSV_Output/combined_output.csv"  # Specify the final CSV output file path
write.csv(final_df, output_file, row.names = FALSE)

cat("Combined CSV saved to:", output_file, "\n")
