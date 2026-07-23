file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)
# Fix: abs(splot_df$p_corr, na.rm=TRUE) -> abs(splot_df$p_corr)
lines <- gsub("abs\\(splot_df\\$p_corr, na\\.rm=TRUE\\)", "abs(splot_df$p_corr)", lines)
writeLines(lines, file_path)
cat("Fixed abs() call.\n")
