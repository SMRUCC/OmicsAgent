# ============================================================
# Module1 Step3: Log2 Transformation + Median Scaling
# Description: Apply log2(x+1) transformation and feature-median
# scaling to the column-sum normalized expression matrix.
# ============================================================

# --- Load required libraries ---
library(utils)
library(ggplot2)

# --- Source helper scripts ---
source("G:/OmicsWorks/agent/rscript/data_io.R")
source("G:/OmicsWorks/agent/rscript/normalization.R")

# --- Define paths ---
input_norm_file <- "G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing/preprocess_step2_normalized.csv"
input_meta_file <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing"
figures_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing/figures"
output_preprocessed <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"

output_log_file <- file.path(output_dir, "preprocess_step3_log2.csv")
output_scaled_file <- file.path(output_dir, "preprocess_step3_scaled.csv")
output_final_file <- file.path(output_dir, "preprocessed_expression.csv")

# Create directories
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(figures_dir, showWarnings = FALSE, recursive = TRUE)

cat("============================================================\n")
cat("Module1 Step3: Log2 Transformation + Median Scaling\n")
cat("============================================================\n\n")

# ============================================================
# Step3.1: Load normalized expression data
# ============================================================
cat("[Step3.1] Loading column-sum normalized (ppm) expression matrix...\n")
expr_norm <- load_expression_matrix(input_norm_file)
cat(" Dimensions:", nrow(expr_norm), "features x", ncol(expr_norm), "samples\n")
cat(" Expression range: [", min(expr_norm), ", ", max(expr_norm), "]\n", sep = "")
cat("\n")

# ============================================================
# Step3.2: Check if log transformation is needed (max >100)
# ============================================================
max_val <- max(expr_norm)
cat("[Step3.2] Checking log transformation requirement...\n")
cat(" Current max value:", max_val, "\n")

needs_log <- max_val >100
cat(" Max >100?", needs_log, "(data not log-transformed)\n\n")

# ============================================================
# Step3.3: Log2(x+1) Transformation
# ============================================================
if (needs_log) {
 cat("[Step3.3] Applying log2(x+1) transformation...\n")
 
 # Save distribution before log transform
 vals_before <- as.vector(expr_norm)
 
 expr_log <- transform_log(expr_norm, base =2, pseudo_count =1)
 
 vals_after <- as.vector(expr_log)
 
 cat(" After log2: value range [", min(expr_log), ", ", max(expr_log), "]\n", sep = "")
} else {
 cat("[Step3.3] Max <=100, data appears already log-transformed. Skipping.\n")
 expr_log <- expr_norm
 vals_before <- as.vector(expr_norm)
 vals_after <- as.vector(expr_norm)
}

# Save log-transformed matrix
write.csv(
 cbind(rownames(expr_log), as.data.frame(expr_log)),
 file = output_log_file,
 row.names = FALSE
)
cat(" Log-transformed matrix saved:", output_log_file, "\n\n")

# ============================================================
# Step3.4: Median Scaling by Feature (Row)
# ============================================================
cat("[Step3.4] Performing feature-median scaling...\n")

# Calculate feature medians
feature_medians <- apply(expr_log,1, median, na.rm = TRUE)
cat(" Feature medians (range): [", min(feature_medians), ", ", max(feature_medians), "]\n", sep = "")

expr_scaled <- scale_feature_median(expr_log, log_transform = FALSE)

cat(" After scaling: value range [", min(expr_scaled), ", ", max(expr_scaled), "]\n", sep = "")
cat(" Each feature median is now ~1.0\n\n")

# Save scaled matrix
write.csv(
 cbind(rownames(expr_scaled), as.data.frame(expr_scaled)),
 file = output_scaled_file,
 row.names = FALSE
)
cat(" Scaled matrix saved:", output_scaled_file, "\n")

# ============================================================
# Step3.5: Distribution Visualization
# ============================================================
cat("[Step3.5] Generating distribution visualizations...\n")

# Load sample metadata
sample_meta <- load_sample_metadata(input_meta_file)
meta_match <- sample_meta[match(colnames(expr_norm), sample_meta$ID), ]

# --- Figure1: Value distribution before vs after log2 transformation ---
df_dist <- data.frame(
 value = c(sample(vals_before, min(50000, length(vals_before))),
 sample(vals_after, min(50000, length(vals_after)))),
 stage = factor(rep(c("Before log2 (ppm)", "After log2(x+1)"),
 c(min(50000, length(vals_before)), min(50000, length(vals_after)))),
 levels = c("Before log2 (ppm)", "After log2(x+1)"))
)

p1 <- ggplot(df_dist, aes(x = value, fill = stage)) +
 geom_histogram(alpha =0.6, bins =80, color = "black", size =0.2) +
 facet_wrap(~stage, scales = "free", ncol =1) +
 scale_fill_manual(values = c("Before log2 (ppm)" = "#E64B35",
 "After log2(x+1)" = "#4DBBD5")) +
 labs(title = "Expression Value Distribution: Before vs After log2(x+1)",
 x = "Expression Value", y = "Count") +
 theme_bw(base_size =13) +
 theme(legend.position = "none",
 plot.title = element_text(hjust =0.5))

ggsave(file.path(figures_dir, "step3_log2_distribution.png"),
 p1, width =10, height =7, dpi =150)
cat(" Saved:", file.path(figures_dir, "step3_log2_distribution.png"), "\n")

# --- Figure2: Distribution after median scaling ---
vals_scaled <- as.vector(expr_scaled)
# Sample to avoid memory issues
if (length(vals_scaled) >50000) {
 set.seed(123)
 vals_scaled_display <- sample(vals_scaled,50000)
} else {
 vals_scaled_display <- vals_scaled
}

df_scaled <- data.frame(value = vals_scaled_display)

p2 <- ggplot(df_scaled, aes(x = value)) +
 geom_histogram(fill = "#00A087", color = "black", bins =80, alpha =0.8) +
 geom_vline(xintercept =1, linetype = "dashed", color = "red", size =1) +
 annotate("text", x =1.05, y = Inf, label = "Median =1", 
 vjust =2, hjust =0, color = "red", size =4.5) +
 labs(title = "Expression Distribution After Median Scaling",
 subtitle = "Each feature divided by its median; median becomes ~1",
 x = "Relative Expression (scaled to median)", y = "Count") +
 theme_bw(base_size =13) +
 theme(plot.title = element_text(hjust =0.5),
 plot.subtitle = element_text(hjust =0.5))

ggsave(file.path(figures_dir, "step3_median_scaling_distribution.png"),
 p2, width =10, height =6, dpi =150)
cat(" Saved:", file.path(figures_dir, "step3_median_scaling_distribution.png"), "\n")

# --- Figure3: Boxplot by sample before vs after (log2 vs scaled) ---
# Prepare data for boxplot (sample-wise distribution)
set.seed(123)
n_sample_features <-500 # sample features for boxplot clarity
sampled_features <- sample(1:nrow(expr_log), n_sample_features)

df_box_before <- data.frame(
 value = as.vector(expr_log[sampled_features, ]),
 sample = rep(colnames(expr_log), each = n_sample_features),
 group = rep(as.character(meta_match$sample_info), each = n_sample_features),
 stage = "After log2(x+1)"
)

df_box_after <- data.frame(
 value = as.vector(expr_scaled[sampled_features, ]),
 sample = rep(colnames(expr_log), each = n_sample_features),
 group = rep(as.character(meta_match$sample_info), each = n_sample_features),
 stage = "After Median Scaling"
)

df_box <- rbind(df_box_before, df_box_after)
df_box$stage <- factor(df_box$stage, levels = c("After log2(x+1)", "After Median Scaling"))

p3 <- ggplot(df_box, aes(x = sample, y = value, fill = group)) +
 geom_boxplot(outlier.size =0.5, outlier.alpha =0.3) +
 facet_wrap(~stage, ncol =1, scales = "free_y") +
 scale_fill_manual(values = c("Clostridium difficile infection" = "#E64B35",
 "high iron diet before" = "#4DBBD5",
 "Standard (control)" = "#00A087")) +
 labs(title = "Sample-wise Expression Distribution: log2 vs Median Scaling",
 x = "Sample", y = "Expression Value", fill = "Group") +
 theme_bw(base_size =11) +
 theme(axis.text.x = element_text(angle =45, hjust =1),
 plot.title = element_text(hjust =0.5))

ggsave(file.path(figures_dir, "step3_boxplot_by_sample.png"),
 p3, width =12, height =8, dpi =150)
cat(" Saved:", file.path(figures_dir, "step3_boxplot_by_sample.png"), "\n\n")

# ============================================================
# Step3.6: Save Final Preprocessed Matrix
# ============================================================
cat("[Step3.6] Saving final preprocessed expression matrix...\n")

# Save to module output dir
write.csv(
 cbind(rownames(expr_scaled), as.data.frame(expr_scaled)),
 file = output_final_file,
 row.names = FALSE
)
cat(" Saved (module):", output_final_file, "\n")

# Save to shared tmp dir for downstream modules
write.csv(
 cbind(rownames(expr_scaled), as.data.frame(expr_scaled)),
 file = output_preprocessed,
 row.names = FALSE
)
cat(" Saved (shared):", output_preprocessed, "\n\n")

# ============================================================
# Summary
# ============================================================
cat("============================================================\n")
cat("STEP3 SUMMARY - Log2 Transformation + Median Scaling\n")
cat("============================================================\n")
cat(" Input features :", nrow(expr_norm), "\n")
cat(" Output features :", nrow(expr_scaled), "\n")
cat(" Samples :", ncol(expr_scaled), "\n")
cat(" Log2 transform :", ifelse(needs_log, "log2(x+1) applied", "skipped (already log)"), "\n")
cat(" Before log2 range : [", round(min(expr_norm),2), ", ", round(max(expr_norm),2), "]\n", sep = "")
cat(" After log2 range : [", round(min(expr_log),2), ", ", round(max(expr_log),2), "]\n", sep = "")
cat(" After scaling range: [", round(min(expr_scaled),4), ", ", round(max(expr_scaled),4), "]\n", sep = "")
cat(" Median per feature : ~1.0 (after division by median)\n")
cat(" Output files :", output_final_file, "\n")
cat(" ", output_preprocessed, "\n")
cat(" Figures :", file.path(figures_dir, "step3_log2_distribution.png"), "\n")
cat(" ", file.path(figures_dir, "step3_median_scaling_distribution.png"), "\n")
cat(" ", file.path(figures_dir, "step3_boxplot_by_sample.png"), "\n")
cat("============================================================\n")
cat("Step3 completed successfully.\n")
