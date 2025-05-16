pacman::p_load("lidR", "data.table", "h2o", "parallel", "pbmcapply")
# library(CloudGeometry)
library(lasR)
## THIN ----
outf <- "data/out/lowerPoints1m.laz"
if(!file.exists(outf)){
  low <- filter_with_grid(0.5, operator = "min")
  ff <- list.files("data/", pattern="\\.las$", full.names = T)
  ctg2 <- readLAScatalog( ff )
  opt_chunk_size(ctg2) <- 0
  opt_chunk_buffer(ctg2) <- -1
  pipeline = reader() + low +  write_las(ofile = outf)
  outf = exec(pipeline, on = ctg2, ncores = nested(4, 2) )
}

## GROUND ----  ps have to find better ground classifier
outf2 <- "data/out/lowerPoints1mClassified.laz"
pipeline = sprintf("lasground64 -i %s -o %s", outf, outf2)
ret = system(pipeline)

## GRID GROUND ----
outf3 <- "data/out/lowerPoints1mClassified.tif"
read <- reader()
tri  <- triangulate(filter = keep_ground())
dtm  <- rasterize(1, tri)
pipeline <- read + tri + dtm + avgi + chm
ans <- exec(pipeline, on = f)


## NORMALIZE ----

trans <- transform_with(mesh)

## calcolo feature geometriche ----
dGeom <- function(chunk) # user defined function
{
  las <- readLAS(chunk)                  # read the chunk
  if (is.empty(las)) return(NULL)        # check if it actually contain points
  browser()
  # lasG <- CloudGeometry::calcGF(las@data[,1:3],rk = 1, threads = 32)  # apply computation of interest
  # for(i in names(lasG)){
  #   las <- lidR::add_lasattribute_manual(las, lasG[,i], name=i, desc=i, type="float")
  # }
  lasG <- CloudGeometry::calcGF(las@data[,1:3],rk = 0.5, threads = 32)  # apply computation of interest
  for(i in names(lasG)){
    las <- lidR::add_lasattribute_manual(las, lasG[,i], name=i, desc=i, type="float")
  }
  lasG <- CloudGeometry::calcGF(las@data[,1:3],rk = 0.25, threads = 32)  # apply computation of interest
  for(i in names(lasG)){
    las <- lidR::add_lasattribute_manual(las, lasG[,i], name=i, desc=i, type="float")
  }
  return(las) # output
}


ff <- list.files("data/", pattern="\\.las$", full.names = T)
load <-  function(data) {
  if(nrow(data)<1){
    return(data)
  }
  lasG <- CloudGeometry::calcGF(data,rk = 0.5, threads = 54)  # apply computation of interest

  lasG2 <- CloudGeometry::calcGF(data,rk = 0.25, threads = 54)  # apply computation of interest

  return(cbind(lasG, lasG2))
}

read <- reader()
calle <-  callback(load, expose = "xyz", no_las_update = TRUE)

ee <- tryCatch({
  exec(read + calle, on = ff[[70]] )
}, error = function(e) {
  list(file = basename(chunk$f), error = e$message)  # ritorna errore e file
})
View(ee[1:20,])
# file <- "data/cloud_merged2.laz"
# ctg <- readLAScatalog(file)
# opt_chunk_size(ctg) <- 100
# opt_chunk_buffer(ctg) <- 3
# opt_output_files(ctg) <- paste0("data/{ID}_geom")
# output <- catalog_apply(ctg, dGeom )

getExtraMatrix <- function(chunk)
{
  # las <- readLAS(chunk$f)
  # if (is.empty(las))  return(NULL)

  area <- sf::st_buffer(chunk$p, -3 )
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
    exec(read + calle, on = chunk$f )
  }, error = function(e) {
    list(file = basename(chunk$f), error = e$message)  # ritorna errore e file
  })

  if(!is.data.frame(ee) || ncol(ee)==0 || nrow(ee)==0) return(list(file = basename(chunk$f), error = "No rows or cols"))

  dt <- as.data.table(ee)
  max_rows <- 1e6
  dt_sampled <- if (nrow(dt) > max_rows) {
    dt[sample(.N, max_rows)]
  } else {
    dt
  }
  return ( dt_sampled )
}

## estraggo valori delle feature ----
ff <- list.files("data/", pattern="\\.las$", full.names = T)
ctg2 <- readLAScatalog( ff )
opt_chunk_size(ctg2) <- 0
opt_chunk_buffer(ctg2) <- -3

vv <- apply(ctg2@data , 1, function(x){ list(f=x[["filename"]], p=x[["geometry"]]) })

output2 <-  pbmclapply(vv, getExtraMatrix, mc.cores = 12)

parallel::mcparallel(NULL)  # should return NULL
gc()                        # force garbage collection


output3 <- output2[sapply(output2, function(x){ class(x[[1]])=="numeric" } )]
all <- data.table::rbindlist(output3)
rm(output2)
rm(output3)
gc()


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
