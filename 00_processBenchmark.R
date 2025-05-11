library(lidR)
library(CloudGeometry)
library(lasR)

dGeom <- function(chunk, rgbmap) # user defined function
{
  las <- readLAS(chunk)                  # read the chunk
  if (is.empty(las)) return(NULL)        # check if it actually contain points

  lasG <- CloudGeometry::calcGF(las@data[,1:3],rk = 1, threads = 32)  # apply computation of interest
  for(i in names(lasG)){
    las <- lidR::add_lasattribute_manual(las, lasG[,i], name=i, desc=i, type="float")
  }
  lasG <- CloudGeometry::calcGF(las@data[,1:3],rk = 0.5, threads = 32)  # apply computation of interest
  for(i in names(lasG)){
    las <- lidR::add_lasattribute_manual(las, lasG[,i], name=i, desc=i, type="float")
  }
  return(las) # output
}

file <- "data/cloud_merged2.laz"
ctg <- readLAScatalog(file)
opt_chunk_size(ctg) <- 100
opt_chunk_buffer(ctg) <- 3
opt_output_files(ctg) <- paste0("data/{ID}_geom")


output <- catalog_apply(ctg, dGeom )
writeLAS( output[[1]], "data/output.laz")

# class = classify_with_csf(FALSE, 1 ,0.1, rigidness = 2) +
#   write_las(ofile = "data/tempfiles/*.las"  ) +
#   write_lax()
#
# tri  <- triangulate(filter = keep_ground())
# dtm  <- rasterize(1, tri) # input is a triangulation stage
# # norm <-  normalize() +  write_las(ofile = "data/tempfiles/norm*.las"  )
# pipeline <- class + tri + dtm #+ norm
# ans2 = exec(pipeline, on = ctg, progress = TRUE, ncores=64)
#
# ans2 <- list.files("data/tempfiles/")
# ctg2 <- readLAScatalog(ans2)
# opt_chunk_size(ctg2) <- 0
# opt_chunk_buffer(ctg2) <- 3
# opt_output_files(ctg) <- paste0("data/{ID}_")

# chm1 <- rasterize(1, "max")
# chm2 <- rasterize(1, "min", filter = "Classification == 2" )

# ans <- exec(pipeline, on = ctg2,  with = list(progress = TRUE,  ncores=64))

terra::writeRaster(ans2$rasterize, "data/dtm.tif", overwrite=T)
# terra::writeRaster(ans[[1]], "data/max.tif", overwrite=T)
# rlas::writelax(file)


# lidR::index(ctg)
# Step 2: Define a bounding box for spatial filtering

las <- lidR::clip_circle(ctg,  288900, 5091400, 10)

opt_output_files(las) <- ""
opt_chunk_size(las) <- 0
opt_chunk_buffer(las) <- 0

output <- catalog_apply(las, dGeom )
writeLAS( output[[1]], "data/output.laz")

plot(ctg, chunk = TRUE)
