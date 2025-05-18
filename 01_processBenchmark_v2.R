pacman::p_load("lidR", "data.table", "h2o", "parallel", "pbmcapply")
library(CloudGeometry)
library(lasR)


#global variables
tilesize <- 50
buffsize <- 1
force  <-  F
## LEGGO IL FILE ----
file <- "data/in/cloud_merged.las"
## 0.1 INDEX ----
file.lax <- paste0(tools::file_path_sans_ext(file), ".lax")
if(!file.exists( file.lax )){
  pipeline = sprintf("lasindex64 -i %s ", file)
  ret = system(pipeline)
}

## 0.2 TILE ----
# ctg <- readLAScatalog(file)
# opt_chunk_size(ctg) <- tilesize
# opt_chunk_buffer(ctg) <- buffsize
# opt_output_files<-""
# plot(ctg, chunk=TRUE)
# tiles <- list.files("data/out/tiles",  pattern="\\.la[sz]$")
# if(length(tiles)==0 || force==T){
#   pipeline = sprintf('lastile64 -i %s -tile_size %f -buffer %f  -o "data/out/tiles/tile.laz"  -cores 64 ',
#                      file, tilesize, buffsize)
#   ret = system(pipeline)
#   tiles <- list.files("data/out/tiles",  pattern="\\.la[sz]$")
#   ctg <- readLAScatalog("data/out/tiles")
#   opt_chunk_size(ctg) <- 0
#   opt_chunk_buffer(ctg) <- 0
#   opt_output_files<-""
#   plot(ctg, chunk=TRUE)
#   pipeline = sprintf("lasindex64 -i data/out/tiles/*.laz -cores 64")
#   ret = system(pipeline)
# }


## 1. THIN ----
outf1 <- "data/out/lowerPoints_thin.laz"
if(!file.exists(outf1) || force==T){
  pipeline = sprintf("lasthin64 -i %s -o %s  -step 0.4 -cores 64", file, outf1)
  ret = system(pipeline, intern=T)
}

## 2. GROUND ----
### ps have to find OS ground classifier
outf2a <- "data/out/lowerPointsClassified_ground.laz"
outf2b <- "data/out/lowerPointsOnly_ground.laz"
if(!file.exists(outf2a) || !file.exists(outf2b) || force==T){
  pipeline = sprintf("lasground_new64 -compute_height -metro   -olaz  -i %s -o %s -cores 64", outf1, outf2a)
  ret = system(pipeline)
  pipeline = sprintf("las2las64 -keep_class 2 -i %s -o %s", outf2a, outf2b)
  ret = system(pipeline)
}


## 3. GRID GROUND ----
outf3 <- "data/out/dtm.tif"
if(!file.exists(outf3) || force==T){
  pipeline = sprintf("blast2dem64  -step 0.5  -i %s -o %s", outf2b, outf3)
  ret = system(pipeline, intern=T)
}

## 4. VOXELIZE TO NORMALIZE PTS ----
# done with 'data/out/VOX.laz'. took 133.82 sec
outf4 <- "data/out/VOX.laz"
if(!file.exists(outf4) || force==T){
  pipeline = sprintf("lasvoxel64 -step 0.4 -i %s -cores 64 -o %s ", file, outf4)
  ret = system(pipeline)
}

## 5. NORMALIZE ----
outf5 <- "data/out/VOXnorm.laz"
if(!file.exists(outf5)  || force==T){
  pipeline = sprintf('lasheight64 -store_as_extra_bytes -ground_points %s -i %s -o %s  -cores 64 ',
                     outf2b,outf4, outf5)
  ret = system(pipeline)
}


## 6. GEOMETRIC FEATURES ----

h2o.shutdown(F)
h2o.init(max_mem_size = "512G")

outf6 <- "data/out/VOXnormGeom.laz"
load <-  function(data) {
  if(nrow(data)<1){
    return(data)
  }
  lasG1 <- CloudGeometry::calcGF(data[,1:3],rk = 1, threads = 128)  # apply computation of interest
  lasG2 <- CloudGeometry::calcGF(data[,1:3],rk = 2, threads = 128)  # apply computation of interest
  data[,names(lasG1)] <- lasG1[,names(lasG1)]
  data[,names(lasG2)] <- lasG2[,names(lasG2)]
  message("done data")
  ss <- sample(1:nrow(data), 5e6)
  message("sampling ", length(ss))
  df <- h2o::as.h2o(data[ss,c(-1,-2)])
  h2o::h2o.save_frame(df, "frames/benchFrameVOX")
  return(data)
}

dummy_matrix <- matrix(data = sample(1:100, 30, replace = TRUE), nrow = 10, ncol = 3)
lasG1 <- CloudGeometry::calcGF(dummy_matrix,rk = 1 )  # apply computation of interest
lasG2 <- CloudGeometry::calcGF(dummy_matrix,rk = 2 )  # apply computation of interest

read <- reader()
for(i in c(names(lasG1),names(lasG2)) ){
  read <- read + add_extrabytes(data_type = "float", i,i)
}
calle <-  callback(load, expose = "xyE", no_las_update = FALSE)

ret <- tryCatch({
  exec(read + calle + write_las(outf6), on = outf5  )
}, error = function(e) {
  list(file=outf5, error=e$message)
})


## 7. MODEL kmeans ----------

# sampledData.all<-as.data.frame(sampledData.all)
# sampledData.all.normMAD<-as.data.frame(sampledData.all.normMAD)
# names(sampledData.all) <- names(sampledData.all.normMAD)

dir = "frames/benchFrameVOX"
df     <- h2o.load_frame(list.files(dir)[[1]],
                         dir = dir)

segModelNotNorm <- h2o::h2o.kmeans(df, k=10, nfolds=0 )
h2o::h2o.saveModel(segModelNotNorm, "models/segModelVOX")


  h2o.removeAll(retained_elements = c(segModelNotNorm@model_id ) )

## 8. APPLY KMEANS ----
  outf7 <- "data/out/VOXnormGeomCluster.laz"
  load <-  function(data) {
    dd <- as.h2o(data)
    clusters <- as.data.frame(h2o.predict(segModelNotNorm, dd ))
    data$cluster <- clusters$predict
    return(clusters$predict)
  }
  # read <- reader()
  # # read <- reader( )
  read <- reader()
  calle <-callback(load, expose = "E", no_las_update = T)

  ee <- tryCatch({
    exec(read + calle, on =outf6  )
  }, error = function(e) {
    list(file = basename(chunk$f), error = e$message)  # ritorna errore e file
  })

  tt <- table(ee)
  round(tt / sum(tt), 3)

  load <-  function(data) {
    data$cluster <- ee
    return(data)
  }
  read <- reader()
  read <- read + add_extrabytes(data_type = "char", "cluster", "cluster kmeans")
  calle <-callback(load, expose = "E", no_las_update = F)

  ee2 <- tryCatch({
    exec(read + calle + write_las(outf7), on =outf5  )
  }, error = function(e) {
    list(file = basename(chunk$f), error = e$message)  # ritorna errore e file
  })




h2o.shutdown(F)
#### merge dei tiles -----
ff <- list.files("data/outputcluster/", pattern="\\.laz$", full.names = T)
# ctg2 <- readLAScatalog( ff )
# opt_chunk_size(ctg2) <- 0
# opt_chunk_buffer(ctg2) <- -3
