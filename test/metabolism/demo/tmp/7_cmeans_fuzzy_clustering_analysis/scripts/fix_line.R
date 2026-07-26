# Fix the line
library(stringi)
fpath <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis/scripts/run_cmeans.R"
txt <- readLines(fpath)
# Replace the bad line
txt[grep("else4", txt)] <- "ncp <- ifelse(actual_k <=4,2, ifelse(actual_k <=6,3,4))"
writeLines(txt, fpath)
cat("Fixed.\n")
