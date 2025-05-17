pacman::p_load("lidR", "data.table", "h2o", "parallel", "pbmcapply")
library(CloudGeometry)
library(lasR)

#global variables
tilesize <- 50
buffsize <- 1
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


force=F

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
if(!file.exists(outf2) || force==T){
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
tiles.norm <- list.files("data/out/tilesNorm",  pattern="\\.la[sz]$")
if(length(tiles.norm)==0 || force==T){
  pipeline = sprintf('lasheight64 -store_as_extra_bytes -ground_points %s -i data/out/tiles/*.laz  -cores 64 ',
                     outf2b)
  ret = system(pipeline)
  fl <- list.files("data/out/tiles", pattern="*._1\\.las$", full.names = T)

}


## 5. calcolo feature geometriche ----
outf5 <- "data/out/lowerPoints1mClassifiedNormGeom.laz"
CloudGeometry::calcGF(outf5, 5)
get_parallel_strategy()
pipeline <- geometry_features(r = 4, features = "apslocei") + write_las(ofile = outf5)
ans <- exec(pipeline, on =outf4)




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
output4 <-  pbmclapply(all, getStats, mc.cores = 10)
saveRDS(output4, "output4.rds")
output4 <- readRDS("output4.rds")
stats <- data.table::rbindlist(output4)
all2 <- sweep( sweep(all, 2, stats$q50, "-"), 2, stats$mad, "/")
rm(all)
gc()

ss <- sample(1:nrow(all2),size=3e6, replace = F)
all3 <- all2[ss,]


## h2o model kmeans ----------
h2o.init(ice_root="/archivio02/tmp")
# df <- h2o::as.h2o(all3)
# h2o::h2o.save_frame(df, "threeMpoints.frame")

df <- h2o.load_frame(basename("frames/threeMpoints.frame/all3_sid_a652_5"), dir = "frames/threeMpoints.frame")
remCols <- -1*(grep("pointDensity", colnames(df)))
# colnames( df[,remCols] )
# segModel3m <- h2o::h2o.kmeans(df[,remCols], k=24, nfolds=0)
# h2o::h2o.saveModel(segModel3m, "models/3Mpts_kmeans10k")

segModel3m <- h2o::h2o.loadModel("models/3Mpts_kmeans10k/KMeans_model_R_1747151150972_8")

## loop tiles ------
### and normalize with MAD and median and then kmeans
for(chunk in vv){
  message(chunk$f)

  area <- sf::st_buffer(chunk$p, -3 )
  bb <- sf::st_bbox(area)

  h2o.removeAll(retained_elements = segModel3m@model_id)

  load <-  function(data) {
    if(ncol(data)<20 || nrow(data)<1){
      return(data)
    }
    message("sweep start")
    all2 <- sweep( sweep(data[,-31], 2, stats$q50, "-"), 2, stats$mad, "/")
    message("sweep finished")
    remCols <- (grep("pointDensity", colnames(all2)))
    all2[,remCols] <- NULL
    message("col removed")
    message("conv to h2o start")
    dd <- as.h2o(all2)
    message("conv to h2o end")
    message("predict start")
    clusters <- as.data.frame(h2o.predict(segModel3m, dd))
    message("predict end")
    data$segment <- clusters$predict
    return(data)
  }
  # read <- reader()
  # # read <- reader( )
  read <- reader_rectangles(xmin = bb[["xmin"]],
                            xmax = bb[["xmax"]],
                            ymin = bb[["ymin"]],
                            ymax = bb[["ymax"]] )
  calle <-
    add_extrabytes("char", "segment", "k-means cluster") +
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
