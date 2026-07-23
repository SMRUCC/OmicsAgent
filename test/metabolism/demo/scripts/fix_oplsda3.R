file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Fix1: OPLSDA section - better handling of sPLSDA failure
# Find the sPLSDA tryCatch and add a more robust fallback
splsda_line <- grep("oplsda_model <- tryCatch\\(splsda\\(t\\(expr_matrix\\)", lines)
cat("Found sPLSDA tryCatch at line:", splsda_line, "\n")

if (length(splsda_line) >0) {
 # Replace from this line to the closing parenthesis of tryCatch
 # Current code:
 # oplsda_model <- tryCatch(splsda(...), error = function(e) { ... plsda(...) })
 
 # Replace with:
 new_lines <- c(
 ' oplsda_model <- tryCatch({',
 ' splsda(t(expr_matrix), groups, ncomp =3, keepX = pmin(keepX, nrow(expr_matrix)))',
 ' }, error = function(e) {',
 ' cat(" sPLSDA failed:", e$message, "\\n")',
 ' cat(" Trying PLSDA instead...\\n")',
 ' plsda(t(expr_matrix), groups, ncomp =3)',
 ' })',
 ' # If model still fails (e.g., all variance=0), use regular PLSDA explicitly',
 ' if (inherits(oplsda_model, "mixo_plsda") || inherits(oplsda_model, "mixo_splsda")) {',
 ' # Check if scores have zero variance',
 ' score_check <- apply(oplsda_model$variates$X[,1:3],2, var, na.rm = TRUE)',
 ' if (any(score_check ==0, na.rm = TRUE) || all(is.na(score_check))) {',
 ' cat(" sPLSDA scores have zero variance, falling back to PLSDA\\n")',
 ' oplsda_model <- plsda(t(expr_matrix), groups, ncomp =3)',
 ' }',
 ' }'
 )
 
 lines <- c(lines[1:(splsda_line-1)], new_lines, lines[(splsda_line+6):length(lines)])
 cat("Fixed.\n")
}

# Fix2: Permutation histogram - handle NaN
hist_line <- grep("plot_perm_hist <- function\\(perm_res, method, prefix\\)", lines)
cat("Found plot_perm_hist at line:", hist_line, "\n")

if (length(hist_line) >0) {
 # Find the function body and wrap with NA check
 # Add a check at the beginning of the function
 insert_line <- hist_line +1 # After the opening {
 lines[insert_line] <- ' if (is.na(perm_res$p_value) || any(is.na(perm_res$permuted_ratios))) {
 cat(" Warning: Skipping permutation histogram for", method, "- NA values\\n")
 return(invisible(NULL))
 }'
 cat("Added NA check at line", insert_line, "\n")
}

writeLines(lines, file_path)
cat("All fixes applied.\n")
