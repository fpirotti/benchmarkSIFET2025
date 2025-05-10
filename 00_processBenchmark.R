library(lidR)
library(CloudGeometry)

parallel::detectCores()


dGeom <- function(chunk, rgbmap) # user defined function
{
  las <- readALSLAS(chunk)                  # read the chunk
  if (is.empty(las)) return(NULL)        # check if it actually contain points
  browser()
  nlasrgb <- CloudGeometry()  # apply computation of interest
  return(nlasrgb) # output
}

file <- "data/cloud_merged2.laz"
ctg <- readLAScatalog(file)
rlas::writelax(file)
las_file <- index_create(ctg)
opt_chunk_size(ctg) <- 100
opt_chunk_buffer(ctg) <- 3
opt_output_files(ctg) <- paste0(tempdir(), "/{ID}_norm_rgb") # write to disk
lidR::index(ctg)
# Step 2: Define a bounding box for spatial filtering
bbox <- matrix(c(288500, 5091400, 288550, 5091450), ncol = 2, byrow = TRUE)

# Step 3: Apply spatial filter to the catalog
las_subset <- catalog_apply(ctg, filter = bbox)

output <- catalog_apply(ctg, dGeom ) # implement user-defined function using catalog_apply
str(output)

plot(ctg, chunk = TRUE)
