# Fix heatmap color mapping
library(stringi)
fpath <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis/scripts/run_cmeans.R"
txt <- readLines(fpath)
# Find the line with ha_row annotation and fix the color mapping
# The issue: cc has names "1","2","3","4" but ha_row uses "C1","C2","C3","C4"
line_idx <- grep("ha_row <- rowAnnotation\\(Cluster=paste0", txt)
if (length(line_idx) >0) {
 # Fix: use numeric cluster labels matching cc names
 txt[line_idx] <- 'ha_row <- rowAnnotation(Cluster=as.character(seq_len(actual_k)),col=list(Cluster=cc),show_annotation_name=TRUE)'
 cat("Fixed row annotation line.\n")
}
writeLines(txt, fpath)
cat("Done.\n")
