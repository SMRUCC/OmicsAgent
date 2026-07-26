lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Fix line379: pcorr_pair is a vector, not matrix
lines[379] <- " pcorr = as.numeric(pcorr_pair),"
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Line379 fixed.\n")
