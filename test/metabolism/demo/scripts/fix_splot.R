# Fix S-plot section - loadings might be NULL in splsda model
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)

# Find the S-plot section and wrap in tryCatch
splot_start <- grep("# OPLSDA S-plot", lines)
splot_end <- grep("# ===========", lines)
splot_end <- splot_end[splot_end > splot_start][1]

if (length(splot_start) >0 && length(splot_end) >0) {
 cat("S-plot section from line", splot_start, "to", splot_end, "\n")
 
 # Replace the loadings extraction with a safe version
 # Find the line that assigns loadings
 load_line <- grep("loadings <- oplsda_model\\$loadings", lines)
 if (length(load_line) >0) {
 cat("Found loadings line at", load_line, "\n")
 }
 
 # Find the data.frame creation for splot_df
 splot_df_line <- grep("splot_df <- data.frame", lines)
 if (length(splot_df_line) >0) {
 cat("Found splot_df line at", splot_df_line[1], "\n")
 }
}
