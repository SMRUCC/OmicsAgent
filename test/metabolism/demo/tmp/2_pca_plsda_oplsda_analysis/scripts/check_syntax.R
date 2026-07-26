# Check syntax only
err <- try(parse("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R"), silent=TRUE)
if (inherits(err, "try-error")) {
 cat("Syntax error:\n")
 cat(attr(err, "condition")$message, "\n")
} else {
 cat("No syntax errors found.\n")
}
