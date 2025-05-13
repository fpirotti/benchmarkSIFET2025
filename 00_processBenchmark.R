pacman::p_load("lidR", "data.table", "parallel", "pbmcapply")

# library(CloudGeometry)
library(lasR)
## calcolo feature geometriche ----

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

## estratto valori delle feature ----
ff <- list.files("data/", pattern="\\.las$", full.names = T)
ctg2 <- readLAScatalog( ff )
opt_chunk_size(ctg2) <- 0
opt_chunk_buffer(ctg2) <- -3

vv <- apply(ctg2@data , 1, function(x){ list(f=x[["filename"]], p=x[["geometry"]]) })

output2 <-  pbmclapply(vv, getExtraMatrix, mc.cores = 12)
gc()

output3 <- output2[sapply(output2, function(x){ class(x)=="data.frame" } )]
all <- data.table::rbindlist(output3)
rm(output2)
rm(output3)
gc()

# write_fst(all, "all.fst")

## MAD e statistiche per normalizzare ----
getStats <- function(v){
  message(length(v))
  v <- na.omit(v)
  v2 <- sample(v, min(length(v),10e6))
  q2 <- quantile(v2, c(0.1,0.25,0.5, 0.75, 0.9)  )
  return(list(mad=mad(v2),
              mean=mean(v2),
              q01=q[[1]], q25=q[[2]],
              q50=q[[3]], q75=q[[4]],
              q90=q[[5]] ) )
}

## MAD e statistiche per normalizzare ----
getStats <- function(v){
  v <- na.omit(v)
  q <- quantile(v, c(0.1,0.25,0.5, 0.75, 0.9),na.rm=T )
  browser()
  return(list(mad=mad(v,na.rm=T), mean=mean(v,na.rm=T), q01=q[[1]], q25=q[[2]], q50=q[[3]], q75=q[[4]], q90=q[[5]] ))
}
output4 <-  mclapply(all[1:1000,1:3], getStats, mc.cores = 1)

