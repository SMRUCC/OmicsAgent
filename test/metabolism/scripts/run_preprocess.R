# Preprocessing script for expression matrix
# Using the standard preprocessing tool from the rscript library

source("G:/OmicsWorks/agent/rscript/preprocess_expression.R")

input_file <- "G:/OmicsWorks/test/metabolism/expression.csv"
output_file <- "G:/OmicsWorks/test/metabolism/tmp/preprocessed_expression.csv"

result <- preprocess_expression(
 input_file = input_file,
 output_file = output_file,
 do_log = TRUE,
 do_median_scale = TRUE,
 fill_na_method = "half_min_positive"
)

cat("\n=== Preprocessing Summary ===\n")
cat("Input molecules:", result$n_molecules, "\n")
cat("Input samples:", result$n_samples, "\n")
cat("Output file:", result$output_file, "\n")
cat("Log transformation: TRUE (max value >100 indicates non-log scale)\n")
cat("Median scaling: TRUE\n")
cat("============================\n")
