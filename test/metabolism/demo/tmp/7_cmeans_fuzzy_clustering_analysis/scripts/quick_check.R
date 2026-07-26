# Quick check script
expr_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
anno_path <- "G:/OmicsWorks/test/metabolism/metabolites.csv"

# Read expression
raw <- read.csv(expr_path, check.names = FALSE)
cat("Expression header:", colnames(raw)[1], "\n")
cat("First few rownames:", paste(head(raw[,1]), collapse=", "), "\n")
cat("Expression dims:", nrow(raw), "x", ncol(raw), "\n")

# Read annotation
anno <- read.csv(anno_path, check.names = FALSE)
cat("\nAnnotation column names:", colnames(anno), "\n")
cat("First few col1:", paste(head(anno[,1]), collapse=", "), "\n")
cat("First few id col:", paste(head(anno$id), collapse=", "), "\n")
