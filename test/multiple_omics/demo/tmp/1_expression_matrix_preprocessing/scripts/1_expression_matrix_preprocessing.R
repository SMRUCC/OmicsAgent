# =============================================================================
#1_expression_matrix_preprocessing.R
# -----------------------------------------------------------------------------
# Module1: Expression Matrix Preprocessing (5 omics, independent)
#
# Standard4-step pipeline applied INDEPENDENTLY to each omics:
#1) Row-wise imputation: NA /0 replaced by min-positive/2 of that row
# (fallback tiny value if a row is entirely non-positive)
#2) Column-sum normalization -> relative abundance (col sum =1, x1e4 scaled)
#3) log2 transform IF raw max >100 (i.e., data judged as NOT log-transformed)
# -> decided per-omics from its own raw data, never a global threshold
#4) Row median scaling (median centering: subtract row median)
#
# Constraints:
# -5 omics fully independent: no cross-omics normalization/scaling factors
# - Only numeric values change; feature rows & subject_id columns preserved
# - Column names & order kept identical to the aligned input
# =============================================================================

suppressPackageStartupMessages({
 library(data.table)
 library(ggplot2)
 library(reshape2)
})

# -----------------------------------------------------------------------------
#0. Configuration -----------------------------------------------------------
# -----------------------------------------------------------------------------
root_dir <- "G:/OmicsWorks/test/multiple_omics/demo"
aligned_dir <- file.path(root_dir, "aligned")
out_dir <- file.path(root_dir, "tmp", "1_expression_matrix_preprocessing")
fig_dir <- file.path(root_dir, "analysis", "1_expression_matrix_preprocessing", "figures")
root_tmp_dir <- file.path(root_dir, "tmp") # downstream modules expect preprocessed_*.csv here

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# Per-omics configuration
omics_cfg <- list(
 rna = list(file = "aligned_rna.csv", sampleinfo = "aligned_sampleinfo_rna.csv",
 unit = "FPKM", expected_features =2000),
 proteome = list(file = "aligned_proteome.csv", sampleinfo = "aligned_sampleinfo_proteome.csv",
 unit = "LFQ intensity", expected_features =1000),
 metabolome = list(file = "aligned_metabolome.csv", sampleinfo = "aligned_sampleinfo_metabolome.csv",
 unit = "peak area", expected_features =1000),
 microbiome = list(file = "aligned_microbiome.csv", sampleinfo = "aligned_sampleinfo_microbiome.csv",
 unit = "TPM", expected_features =131),
 volatilome = list(file = "aligned_volatilome.csv", sampleinfo = "aligned_sampleinfo_volatilome.csv",
 unit = "peak area", expected_features =300)
)

NORM_SCALE <-1e4 # amplification factor after column-sum normalization
LOG_THRESHOLD <-100 # raw max >100 -> judged as not-log -> apply log2
LOG_BASE <-2

# -----------------------------------------------------------------------------
#1. Helper: unified ggplot theme
# -----------------------------------------------------------------------------
theme_pub <- function(base_size =13) {
 theme_bw(base_size = base_size) +
 theme(
 panel.grid = element_blank(),
 panel.border = element_rect(color = "black", linewidth =0.6),
 plot.title = element_text(face = "bold", hjust =0.5, size = base_size +1),
 plot.subtitle = element_text(hjust =0.5),
 axis.text = element_text(color = "black"),
 axis.title = element_text(color = "black"),
 legend.title = element_text(face = "bold"),
 legend.text = element_text(color = "black"),
 strip.text = element_text(face = "bold"),
 strip.background = element_rect(fill = "grey92"),
 legend.key = element_blank()
 )
}
theme_set(theme_pub())

save_plot <- function(plot, filename, width =8, height =6, dpi =300) {
 ggsave(file.path(fig_dir, paste0(filename, ".pdf")), plot, width = width,
 height = height, device = cairo_pdf)
 ggsave(file.path(fig_dir, paste0(filename, ".png")), plot, width = width,
 height = height, dpi = dpi, type = "cairo")
}

cat("=== Module1: Expression Matrix Preprocessing ===\n")
cat("Output dir:", out_dir, "\n")
cat("Figure dir:", fig_dir, "\n\n")

# -----------------------------------------------------------------------------
#2. Main preprocessing function (per omics) ---------------------------------
# -----------------------------------------------------------------------------
preprocess_omics <- function(omics_id, cfg) {
 cat(sprintf("\n########## [%s]##########\n", omics_id))
 in_path <- file.path(aligned_dir, cfg$file)
 si_path <- file.path(aligned_dir, cfg$sampleinfo)

 # ---- read expression matrix (first column = feature id) -----------------
 mat <- fread(in_path, header = TRUE, check.names = FALSE, data.table = FALSE)
 id_col <- names(mat)[1]
 feat_ids <- as.character(mat[[1]])
 subj_ids <- names(mat)[-1]
 X <- as.matrix(mat[, -1, drop = FALSE])
 storage.mode(X) <- "double"

 n_feat <- nrow(X); n_samp <- ncol(X)
 cat(sprintf("Input : %s\n", cfg$file))
 cat(sprintf("Dim : %d features x %d samples (first col header = '%s')\n",
 n_feat, n_samp, id_col))

 # ---- sanity checks --------------------------------------------------------
 if (!is.null(cfg$expected_features) && n_feat != cfg$expected_features) {
 warning(sprintf("[%s] feature count %d != expected %d", omics_id, n_feat,
 cfg$expected_features))
 }
 n_na <- sum(is.na(X)); n_inf <- sum(is.infinite(X)); n_zero <- sum(X ==0, na.rm = TRUE)
 n_nonpos <- sum(X <=0, na.rm = TRUE)
 cat(sprintf("NA cells: %d | Inf cells: %d | zero cells: %d | non-positive cells: %d\n",
 n_na, n_inf, n_zero, n_nonpos))
 if (n_na + n_inf + n_nonpos ==0) cat(" -> matrix is fully dense & positive; imputation step is a no-op.\n")

 raw_max <- max(X, na.rm = TRUE); raw_min <- min(X, na.rm = TRUE)
 raw_median <- median(X, na.rm = TRUE)

 # ---- read sample info & verify subject_id alignment -----------------------
 si <- fread(si_path, header = TRUE, check.names = FALSE, data.table = FALSE)
 cat(sprintf("Sampleinfo: %d rows x %d cols\n", nrow(si), ncol(si)))
 idcol_si <- if ("ID" %in% names(si)) "ID" else names(si)[1]
 si_ids <- as.character(si[[idcol_si]])
 if (length(si_ids) == n_samp && all(si_ids == subj_ids)) {
 cat(" [ok] sampleinfo IDs match matrix subject_id order exactly.\n")
 } else if (length(si_ids) == n_samp && all(sort(si_ids) == sort(subj_ids))) {
 cat(" [warn] sampleinfo IDs match as set but NOT in same order; reordering matrix columns.\n")
 X <- X[, si_ids, drop = FALSE]; subj_ids <- names(X)
 } else {
 warning(sprintf("[%s] sampleinfo IDs do not match matrix subject_ids!", omics_id))
 }

 # ---- STEP1: row-wise imputation (min-positive /2) -----------------------
 X_imp <- X
 for (i in seq_len(n_feat)) {
 row <- X_imp[i, ]
 pos <- row[row >0 & !is.na(row)]
 if (length(pos) >0) {
 fill <- min(pos) /2
 } else {
 fill <- NA_real_ # no positive value -> fallback below
 }
 bad <- is.na(row) | row <=0
 if (any(bad)) X_imp[i, bad] <- fill
 }
 # fallback for rows with no positive value at all
 still_bad <- !is.finite(X_imp)
 if (any(still_bad)) {
 fb <- if (is.finite(raw_min) && raw_min >0) raw_min /2 else 1e-6
 cat(sprintf(" [info] %d cells filled with fallback value %g (rows with no positive value)\n",
 sum(still_bad), fb))
 X_imp[still_bad] <- fb
 }
 stopifnot(all(is.finite(X_imp)), all(X_imp >0))

 # ---- STEP2: column-sum normalization -> relative abundance --------------
 col_sums <- colSums(X_imp)
 X_norm <- sweep(X_imp,2, col_sums, "/") * NORM_SCALE
 stopifnot(all(is.finite(X_norm)))

 # ---- STEP3: log transform (per-omics decision on RAW max) ---------------
 do_log <- raw_max > LOG_THRESHOLD
 if (do_log) {
 X_tr <- log(X_norm) / log(LOG_BASE) # log2(x)
 log_note <- sprintf("log2 applied (raw max %.2f > %d, judged as not log-transformed)",
 raw_max, LOG_THRESHOLD)
 } else {
 X_tr <- X_norm
 log_note <- sprintf("NO log transform (raw max %.2f <= %d, judged as already log-scaled)",
 raw_max, LOG_THRESHOLD)
 }
 stopifnot(all(is.finite(X_tr)))

 # ---- STEP4: row median scaling (median centering) -----------------------
 row_med <- apply(X_tr,1, median, na.rm = TRUE)
 X_scaled <- sweep(X_tr,1, row_med, "-")
 stopifnot(all(is.finite(X_scaled)))

 # ---- QC stats after -------------------------------------------------------
 n_imputed <- n_na + n_inf + n_nonpos
 cat(sprintf("raw : min=%.4g max=%.4g median=%.4g\n", raw_min, raw_max, raw_median))
 cat(sprintf("impute : %d cells imputed (NA/0/non-positive)\n", n_imputed))
 cat(sprintf("log dec : %s\n", log_note))
 cat(sprintf("median scale: row-median centering (subtract row median)\n"))
 cat(sprintf("out : min=%.4g max=%.4g median=%.4g\n",
 min(X_scaled), max(X_scaled), median(X_scaled)))

 # ---- verify no row/col added or dropped, order preserved ------------------
 stopifnot(nrow(X_scaled) == n_feat, ncol(X_scaled) == n_samp)
 stopifnot(identical(colnames(X_scaled), subj_ids))

 # ---- write preprocess_<omics>.csv (module dir) ----------------------------
 out_df <- data.frame(X_scaled, check.names = FALSE)
 out_df <- cbind(rep(NA_character_, n_feat), out_df, stringsAsFactors = FALSE)
 names(out_df) <- c(id_col, subj_ids)
 out_df[[1]] <- feat_ids
 out_file <- file.path(out_dir, sprintf("preprocess_%s.csv", omics_id))
 fwrite(out_df, out_file, row.names = FALSE)
 # ---- also write tmp/preprocessed_<omics>.csv for downstream modules ------
 out_file2 <- file.path(root_tmp_dir, sprintf("preprocessed_%s.csv", omics_id))
 fwrite(out_df, out_file2, row.names = FALSE)
 cat(sprintf("wrote: %s\n", out_file))
 cat(sprintf("wrote: %s\n", out_file2))

 # ---- collect report row ----------------------------------------------------
 report_row <- data.frame(
 omics = omics_id,
 unit = cfg$unit,
 n_samples = n_samp,
 n_features = n_feat,
 na_cells = n_na,
 inf_cells = n_inf,
 zero_cells = n_zero,
 nonpos_cells= n_nonpos,
 imputed_cells = n_imputed,
 raw_min = round(raw_min,6),
 raw_max = round(raw_max,6),
 raw_median = round(raw_median,6),
 log_transform = do_log,
 log_base = if (do_log) LOG_BASE else NA_integer_,
 log_note = log_note,
 normalization = sprintf("column-sum to1 then x%.0f", NORM_SCALE),
 median_scale = "subtract row median (median centering)",
 out_min = round(min(X_scaled),6),
 out_max = round(max(X_scaled),6),
 out_median = round(median(X_scaled),6),
 stringsAsFactors = FALSE
 )

 # ---- figure: value distribution before vs after ---------------------------
 samp_idx <- sort(sample(seq_len(n_samp), min(n_samp,30))) # subsample for plotting
 feat_idx <- sort(sample(seq_len(n_feat), min(n_feat,500)))
 df_plot <- rbind(
 data.frame(stage = "raw", value = as.vector(X[feat_idx, samp_idx])),
 data.frame(stage = "preprocessed", value = as.vector(X_scaled[feat_idx, samp_idx]))
 )
 # raw on log10 axis for readability
 df_plot$value_plot <- ifelse(df_plot$stage == "raw", log10(pmax(df_plot$value,1e-8)),
 df_plot$value)
 xlab_txt <- if (do_log) "value (raw: log10; preprocessed: log2-centered)"
 else "value (raw: log10; preprocessed: scaled)"
 p <- ggplot(df_plot, aes(x = value_plot, fill = stage)) +
 geom_density(alpha =0.5) +
 scale_fill_manual(values = c("raw" = "#E64B35", "preprocessed" = "#4DBBD5")) +
 labs(title = sprintf("Value distribution - %s", omics_id),
 subtitle = log_note, x = xlab_txt, y = "density") +
 theme_pub()
 save_plot(p, sprintf("preprocess_distribution_%s", omics_id), width =8, height =5)

 return(report_row)
}

# -----------------------------------------------------------------------------
#3. Run for all5 omics -----------------------------------------------------
# -----------------------------------------------------------------------------
reports <- lapply(names(omics_cfg), function(id) preprocess_omics(id, omics_cfg[[id]]))
report_df <- do.call(rbind, reports)
rownames(report_df) <- NULL

# -----------------------------------------------------------------------------
#4. Write combined report ---------------------------------------------------
# -----------------------------------------------------------------------------
report_file <- file.path(out_dir, "preprocess_report.csv")
report_file2 <- file.path(root_tmp_dir, "preprocessing_report.csv")
fwrite(report_df, report_file, row.names = FALSE)
fwrite(report_df, report_file2, row.names = FALSE)
cat("\nReport written:\n ", report_file, "\n ", report_file2, "\n")

# -----------------------------------------------------------------------------
#5. Summary figure: per-omics log decision & raw max ------------------------
# -----------------------------------------------------------------------------
sum_df <- data.frame(
 omics = report_df$omics,
 raw_max = report_df$raw_max,
 log_transform = ifelse(report_df$log_transform, "log2 applied", "no log"),
 stringsAsFactors = FALSE
)
p2 <- ggplot(sum_df, aes(x = reorder(omics, raw_max), y = raw_max, fill = log_transform)) +
 geom_col(width =0.6) +
 geom_hline(yintercept =100, linetype =2, color = "grey40") +
 geom_text(aes(label = sprintf("%.1f", raw_max)), vjust = -0.3, size =3.5) +
 annotate("text", x =3, y =100, label = "threshold =100", color = "grey40", vjust = -0.5) +
 scale_fill_manual(values = c("log2 applied" = "#00A087", "no log" = "#8491B4")) +
 labs(title = "Raw max value & log-transform decision (per omics)",
 x = "Omics", y = "Raw max value", fill = "Decision") +
 theme_pub()
save_plot(p2, "preprocess_summary_log_decision", width =8, height =5)

cat("\n=== Module1 preprocessing completed successfully ===\n")
print(report_df)
