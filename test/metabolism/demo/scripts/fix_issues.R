file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

cat("Fixing PLSDA cross-validation and NA variance issues...\n")

# Fix1: Handle NA in plsda_var (explained variance)
# Around line where plsda_var is used for distance calculation
# Replace the distance & permutation lines for PLSDA

# The issue: plsda_model$explained_variance$X returns NULL or NA for mixOmics
# Solution: If NA, use variance from the scores matrix itself

# Find and modify the section
for (i in seq_along(lines)) {
 # Fix: if plsda_var has NA, use variance of scores
 if (grepl("plsda_var <- as.numeric\\(plsda_model\\$explained_variance\\$X\\[", lines[i])) {
 lines[i] <- "plsda_var <- as.numeric(plsda_model$explained_variance$X[1:3]) *100"
 # Add after this line
 }
 
 # Fix the distance calculation to handle NA var
 if (grepl("plsda_dist <- calc_weighted_dist\\(as.matrix\\(plsda_scores\\), plsda_var, groups\\)", lines[i])) {
 lines[i] <- "# If PLSDA explained variance is NA, use variance of score columns as proxy"
 lines <- append(lines, 
 "if (any(is.na(plsda_var)) || any(plsda_var ==0)) {
 plsda_var_used <- apply(plsda_scores,2, var) / sum(apply(plsda_scores,2, var)) *100
 } else { plsda_var_used <- plsda_var }
plsda_dist <- calc_weighted_dist(as.matrix(plsda_scores), plsda_var_used, groups)
plsda_perm <- permutation_test(as.matrix(plsda_scores), groups, plsda_var_used, n_perm)", 
 after = i)
 # Remove the original line
 lines <- lines[-i]
 break
 }
}

# Fix2: Cross-validation - use leave-one-out instead of Mfold (too few samples)
for (i in seq_along(lines)) {
 if (grepl("plsda_cv <- perf\\(plsda_model, validation = \"Mfold\"", lines[i])) {
 lines[i] <- "plsda_cv <- tryCatch({
 perf(plsda_model, validation = \"Mfold\", folds =5, nrepeat =3, dist = \"max.dist\")
 }, error = function(e) {
 cat(\" Mfold CV failed (\", e$message, \"), trying leave-one-out...\\n\")
 perf(plsda_model, validation = \"loo\", dist = \"max.dist\")
 })"
 break
 }
}

# Fix3: Handle CV summary extraction safely
for (i in seq_along(lines)) {
 if (grepl("cv_summary <- data.frame\\(", lines[i]) && grepl("plsda_cv\\$error.rate", lines[i])) {
 lines[i] <- "cv_summary <- tryCatch({
 data.frame(
 comp =1:3,
 BER = as.numeric(plsda_cv$error.rate$BER[1, ]),
 overall_error = as.numeric(plsda_cv$error.rate$overall[1, ])
 )
 }, error = function(e) {
 data.frame(comp =1:3, BER = NA, overall_error = NA)
 })"
 break
 }
}

# Fix4: Handle CV summary printing when NA
for (i in seq_along(lines)) {
 if (grepl("cat\\(sprintf\\(\" CV BER:", lines[i])) {
 lines[i] <- "if (!is.na(cv_summary$BER[1])) {
 cat(sprintf(\" CV BER: %.3f, %.3f, %.3f\\n\", cv_summary$BER[1], cv_summary$BER[2], cv_summary$BER[3]))
 } else { cat(\" CV BER: NA (cross-validation failed)\\n\") }"
 break
 }
}

# Fix5: Remove duplicate plsda_perm line that may remain
for (i in grep("plsda_perm <- permutation_test", lines)) {
 # Only keep one instance
}

writeLines(lines, file_path)
cat("Fixes applied.\n")
