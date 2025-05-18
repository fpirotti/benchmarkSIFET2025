pacman::p_load("lidR", "data.table", "h2o", "parallel", "pbmcapply")
library(CloudGeometry)
library(lasR)

float: left;

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
ctg <- readLAScatalog(file)
opt_chunk_size(ctg) <- tilesize
opt_chunk_buffer(ctg) <- buffsize
opt_output_files<-""
plot(ctg, chunk=TRUE)
tiles <- list.files("data/out/tiles",  pattern="\\.la[sz]$")
if(length(tiles)==0 || force==T){
  pipeline = sprintf('lastile64 -i %s -tile_size %f -buffer %f  -o "data/out/tiles/tile.laz"  -cores 64 ',
                     file, tilesize, buffsize)
  ret = system(pipeline)
  tiles <- list.files("data/out/tiles",  pattern="\\.la[sz]$")
  ctg <- readLAScatalog("data/out/tiles")
  opt_chunk_size(ctg) <- 0
  opt_chunk_buffer(ctg) <- 0
  opt_output_files<-""
  plot(ctg, chunk=TRUE)
  pipeline = sprintf("lasindex64 -i data/out/tiles/*.laz -cores 64")
  ret = system(pipeline)
}


## 1. THIN ----
outf1 <- "data/out/lowerPoints_thin.laz"
if(!file.exists(outf1) || force==T){
  pipeline = sprintf("lasthin64 -i %s -o %s  -step 0.5 -cores 32", file, outf1)
  ret = system(pipeline, intern=T)
}

## 2. GROUND ----
### ps have to find OS ground classifier
outf2a <- "data/out/lowerPoints1mClassified_ground.laz"
outf2b <- "data/out/lowerPoints1mOnly_ground.laz"
if(!file.exists(outf2a) || !file.exists(outf2b) || force==T){
  pipeline = sprintf("lasground_new64 -compute_height -metro -odix _ground -olaz  -i %s -o %s", outf1, outf2a)
  ret = system(pipeline)
  pipeline = sprintf("las2las64 -keep_class 2 -i %s -o %s", outf2a, outf2b)
  ret = system(pipeline)
}


## 3. GRID GROUND ----
outf3 <- "data/out/lowerPoints1mClassified.tif"
if(!file.exists(outf3) || force==T){
  pipeline = sprintf("las2dem64 -keep_class 2 -step 0.5  -i %s -o %s", outf2, outf3)
  ret = system(pipeline, intern=T)
}

## 4. NORMALIZE ----
tiles.norm <-  list.files("data/out/tiles", pattern="*._1\\.las$", full.names = T)
if(length(tiles.norm)==0 || force==T){
  pipeline = sprintf('lasheight64 -store_as_extra_bytes -ground_points %s -i data/out/tiles/*.laz  -cores 64 ',
                     outf2b)
  ret = system(pipeline)
  tiles.norm <- list.files("data/out/tiles", pattern="*._1\\.las$", full.names = T)
}


## 5. GEOMETRIC FEATURES ----
outf5 <- "data/out/geom/*.laz"
load <-  function(data) {
  if(nrow(data)<1){
    return(data)
  }
  lasG1 <- CloudGeometry::calcGF(data[,1:3],rk = 0.5, threads = 60)  # apply computation of interest
  lasG2 <- CloudGeometry::calcGF(data[,1:3],rk = 0.25, threads = 60)  # apply computation of interest
  # lasG <- cbind(lasG1, lasG2)
  return(cbind(lasG1, lasG2))
}
read <- reader()
calle <-  callback(load, expose = "xyE", no_las_update = TRUE)

## dummy first run to get column names
cc<-    exec(read + calle, on = tiles.norm[[1]]  )

read <- reader()
for(i in names(cc)){
  read <- read + add_extrabytes(data_type = "float", i,i)
}
calle <-  callback(load, expose = "xyE", no_las_update = FALSE)

ee <- {}
for(f in tiles.norm){
  ee[[basename(f)]] <- tryCatch({
    exec(read + calle + write_las(outf5), on = f  )
  }, error = function(e) {
    list(file=f, error=e$message)
  })
}

## 5.1 LIST GEOM TILES ----
ff <- list.files("data/out/geom/", pattern="\\.la[zs]$",ignore.case = T, full.names = T)
ctg2 <- readLAScatalog( ff )
opt_chunk_size(ctg2) <- 0
opt_chunk_buffer(ctg2) <- -1
vv <- apply(ctg2@data , 1, function(x){ list(f=x[["filename"]], p=x[["geometry"]]) })



## 6. SAMPLING PER MODELLO K-MEANS ----
getSamples <- function(chunk)
{
  area <- sf::st_buffer(chunk$p, ctg2@chunk_options$buffer )
  bb <- sf::st_bbox(area)
  load <-  function(data) { return(data) }
  read <- reader_rectangles(xmin = bb[["xmin"]],
                            xmax = bb[["xmax"]],
                            ymin = bb[["ymin"]],
                            ymax = bb[["ymax"]]
  )
  # read <- reader( )
  calle <- callback(load, expose = "E", no_las_update = TRUE)

  ee <- tryCatch({
  ff<-  exec(read + calle, on = chunk$f )
  }, error = function(e) {
    list(file = basename(chunk$f), error = e$message)  # ritorna errore e file
  })

  max_rows <- 5e4
  if(!is.data.frame(ee) || ncol(ee)==0  ) return(list(file = basename(chunk$f), error = "No rows or cols"))
  if(nrow(ee) < max_rows*2 ) return(list(file = basename(chunk$f), error = "too few rows, skipping"))

  dt <- as.data.table(ee)
  dt_sampled <- dt[sample(.N, max_rows)]

  return ( dt_sampled )
}

sampledData <-  pbmclapply(vv, getSamples, mc.cores = 24)
sampledData <- sampledData[sapply(sampledData, function(x){ class(x[[1]])=="numeric" } )]
sampledData.all <- data.table::rbindlist(sampledData)

## MAD e statistiche per normalizzare ----
getStats <- function(v){
  # message(length(v))
  v <- na.omit(v)
  v2 <- sample(v, min(length(v),10e6))
  q <- quantile(v2, c(0.1,0.25,0.5, 0.75, 0.9)  )
  return(list(mad=mad(v2),
              mean=mean(v2),
              q01=q[[1]], q25=q[[2]],
              q50=q[[3]], q75=q[[4]],
              q90=q[[5]] ) )
}

## apply loop for stats ------
# output4 <-  pbmclapply(sampledData.all, getStats, mc.cores = 32)
# saveRDS(output4, "output4b.rds")
output4a <- readRDS("output4.rds")
output4b <- readRDS("output4b.rds")
statsA <- data.table::rbindlist(output4a, idcol = "metric")
statsB <- data.table::rbindlist(output4b, idcol = "metric")
statsDiff <- (statsA[16:30,-1] - statsB[2:16,-1])/statsA[16:30,-1] * 100


stats <- data.table::rbindlist(output4b, idcol = "metric")
setkey(stats, metric)
norm <- function(nv){
  v <- sampledData.all[[nv]]
  q50 <- stats["height above ground"][["q50"]]
  mad <- stats["height above ground"][["mad"]]
  v-q50/mad
  }
sampledData.all.normMAD <-  pbmclapply( names(sampledData.all), norm, mc.cores = 32)
names(sampledData.all.normMAD) <- names(sampledData.all)
rm(sampledData)
gc()



## h2o model kmeans ----------
h2o.init(ice_root="/archivio02/tmp" )

# sampledData.all<-as.data.frame(sampledData.all)
# sampledData.all.normMAD<-as.data.frame(sampledData.all.normMAD)
# names(sampledData.all) <- names(sampledData.all.normMAD)
# df <- h2o::as.h2o(sampledData.all)
# dfNorm <- h2o::as.h2o(sampledData.all.normMAD)
# h2o::h2o.save_frame(df, "frames/benchFrame")
# h2o::h2o.save_frame(dfNorm, "frames/benchFrameNorm")

dir = "frames/benchFrame"
df     <- h2o.load_frame(list.files(dir)[[1]],
                         dir = dir)
dir = "frames/benchFrameNorm"
dfNorm <- h2o.load_frame(list.files(dir)[[1]],
                     dir = dir)
# remCols <- -1*(grep("pointDensity", colnames(df)))
# colnames( df[,remCols] )
segModelNotNorm <- h2o::h2o.kmeans(df, k=10, nfolds=0, standardize = FALSE)
h2o::h2o.saveModel(segModelNotNorm, "models/segModelNotNorm")
segModelNorm <- h2o::h2o.kmeans(df, k=10, nfolds=0, standardize = TRUE)
h2o::h2o.saveModel(segModelNorm, "models/segModelNorm")

segModelNormMAD <- h2o::h2o.kmeans(dfNorm, k=10, nfolds=0, standardize = FALSE)
h2o::h2o.saveModel(segModelNormMAD, "models/segModelNormMAD")


## loop tiles ------
### and normalize with MAD and median and then kmeans
for(chunk in vv){
  message(chunk$f)

  area <- sf::st_buffer(chunk$p, ctg2@chunk_options$buffer )
  bb <- sf::st_bbox(area)

  h2o.removeAll(retained_elements = c(segModelNotNorm@model_id,
                                      segModelNorm@model_id,
                                      segModelNormMAD@model_id) )

  load <-  function(data) {
    names(data)[1] <- gsub(" ",".", names(data)[1])

    message("sweep start")
    dataN <- sweep( sweep(data[,1:31], 2, stats$q50, "-"), 2, stats$mad, "/")
    message("sweep finished")
    message("conv to h2o start")
    dd <- as.h2o(data)
    message("conv to h2o end")
    message("predict start")
    clusters <- as.data.frame(h2o.predict(segModelNotNorm, dd ))
    data$segmentNotNorm <- clusters$predict
    clusters <- as.data.frame(h2o.predict(segModelNorm, dd))
    data$segmentNorm <- clusters$predict


    dd <- as.h2o(dataN)
    clusters <- as.data.frame(h2o.predict(segModelNormMAD, dd))
    data$segModelNormMAD <- clusters$predict

    message("predict end")
    return(data[, c("segmentNotNorm","segmentNorm","segmentNormMAD")])
  }
  # read <- reader()
  # # read <- reader( )
  read <- reader_rectangles(xmin = bb[["xmin"]],
                            xmax = bb[["xmax"]],
                            ymin = bb[["ymin"]],
                            ymax = bb[["ymax"]] )
  calle <-
    add_extrabytes("char", "segmentNotNorm", "k-means not Normalized cluster") +
    add_extrabytes("char", "segmentNorm", "k-means Norm cluster") +
    add_extrabytes("char", "segmentNormMAD", "k-means Norm MAD cluster") +
    callback(load, expose = "E", no_las_update = FALSE)

  ee <- tryCatch({
    exec(read + calle + write_las(ofile = "data/outputcluster/*.laz"), on = chunk$f )
  }, error = function(e) {
    list(file = basename(chunk$f), error = e$message)  # ritorna errore e file
  })

  # if(is.character(ee)){
  #   system(sprintf("/archivio/software/PotreeConverter/build/PotreeConverter %s", ee) )
  # }

    message(ee)
    message("================")
}

h2o.shutdown(F)
#### merge dei tiles -----
ff <- list.files("data/outputcluster/", pattern="\\.laz$", full.names = T)
# ctg2 <- readLAScatalog( ff )
# opt_chunk_size(ctg2) <- 0
# opt_chunk_buffer(ctg2) <- -3
