library(lidR)
parallel::detectCores()

ctg <- readLAScatalog("data/cloud_merged2.laz")
ctg
opt_chunk_size(ctg) <- 100
opt_chunk_buffer(ctg) <- 3
plot(ctg, chunk = TRUE)
