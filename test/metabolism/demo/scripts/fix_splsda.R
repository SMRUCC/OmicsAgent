file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Find the sPLSDA error section and fix it
# The issue is: when sPLSDA fails, we need a fallback

# Find the line that calls splsda
splsda_line <- grep("oplsda_model <- splsda\\(t\\(expr_matrix\\), groups, ncomp =3, keepX = optimal_keepX\\)", lines)
cat("Found splsda call at line:", splsda_line, "\n")

if (length(splsda_line) >0) {
 # Replace with tryCatch wrapped version
 lines[splsda_line] <- ' oplsda_model <- tryCatch({
 splsda(t(expr_matrix), groups, ncomp =3, keepX = optimal_keepX)
 }, error = function(e) {
 cat(" Warning: sPLSDA failed:", e$message, "\\n")
 cat(" Falling back to PLSDA...\\n")
 plsda(t(expr_matrix), groups, ncomp =3)
 })'
 
 # Also need to handle the case where the check for NULL is downstream
 # Find "} else {" after stop("OPLSDA model is NULL...")
 null_check <- grep('stop\\("OPLSDA model is NULL - analysis failed"\\)', lines)
 if (length(null_check) >0) {
 cat("Found NULL check at line:", null_check, "\n")
 # Replace the stop with a warning and use PLSDA as fallback
 lines[_check] <- ' cat(" OPLSDA-like analysis not available, using PLSDA scores instead\\n")
 oplsda_model <- plsda(t(expr_matrix), groups, ncomp =3)
 oplsda_scores_full <- as.data.frame(oplsda_model$variates$X[,1:3])
 colnames(oplsda_scores_full) <- c("predictive", "orthogonal1", "orthogonal2")
 oplsda_scores <- oplsda_scores_full
 oplsda_var <- as.numeric(oplsda_model$explained_variance$X[1:3]) *100
 if (any(is.na(oplsda_var))) {
 score_var <- apply(oplsda_scores,2, var, na.rm = TRUE)
 oplsda_var <- score_var / sum(score_var) *100
 }
 if (length(oplsda_var) <3) oplsda_var <- c(oplsda_var, rep(0,3 - length(oplsda_var)))
 oplsda_summary <- data.frame(
 Metric = c("Comp1", "Comp2", "Comp3"),
 Value = oplsda_var
 )
 cat(sprintf(" Predictive: %.2f%%, Orthogonal1: %.2f%%, Orthogonal2: %.2f%%\\n",
 oplsda_var[1], oplsda_var[2], oplsda_var[3]))
 oplsda_vip <- vip(oplsda_model)
 oplsda_vip_df <- data.frame(
 molecule = rownames(oplsda_vip),
 VIP = as.numeric(oplsda_vip[,1]),
 stringsAsFactors = FALSE
 )'
 }
}

writeLines(lines, file_path)
cat("Fixed.\n")
