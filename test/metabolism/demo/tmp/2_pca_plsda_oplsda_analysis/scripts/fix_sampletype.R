lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Add SampleType after SampleName (line363)
line363 <- grep("scores_pair\\$SampleName", lines)
cat("SampleName at line", line363, "\n")
# Insert SampleType after line363
new_line <- ' scores_pair$SampleType <- sample_meta[rownames(scores_pair), "sample_info"]'
lines <- append(lines, new_line, after = line363)
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Added SampleType line.\n")
