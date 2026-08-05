# =============================================================================
#1_expression_matrix_preprocessing_verify.R
# -----------------------------------------------------------------------------
# Module1 Step3: Validation & report generation for5 preprocessed omics matrices
#
# Tasks:
#1) For each omics, re-read aligned input & preprocess output and verify:
# - dimensions identical (no feature row added/removed)
# - feature IDs identical
# - subject_id column names identical AND order preserved
# - numeric values only (no character contamination in numeric columns)
# - no residual NA / Inf
#2) Cross-omics: all5 matrices share identical subject_id column order
# (requirement for column-name-based merging in downstream modules)
#3) Rebuild & write preprocessing_report.csv (params used per omics)
#
# Outputs:
# - tmp/1_expression_matrix_preprocessing/preprocess_<omics>.csv (verified copies)
# - tmp/preprocessed_<omics>.csv (downstream copies)
# - tmp/1_expression_matrix_preprocessing/preprocess_report.csv
# - tmp/preprocessing_report.csv
# =============================================================================

suppressPackageStartupMessages({
 library(data.table)
})

# -----------------------------------------------------------------------------
#0. Configuration -----------------------------------------------------------
# -----------------------------------------------------------------------------
root_dir <- "G:/OmicsWorks/test/multiple_omics/demo"
aligned_dir <- file.path(root_dir, "aligned")
out_dir <- file.path(root_dir, "tmp", "1_expression_matrix_preprocessing")
root_tmp_dir <- file.path(root_dir, "tmp")

omics_cfg <- list(
 rna = list(unit = "FPKM", expected_features =2000, log_base =2,
 log_note = "log2 applied (raw max >100, judged as not log-transformed)"),
 proteome = list(unit = "LFQ intensity", expected_features =1000, log_base =2,
 log_note = "log2 applied (raw max >100, judged as not log-transformed)"),
 metabolome = list(unit = "peak area", expected_features =1000, log_base =NA_integer_,
 log_note = "NO log transform (raw max <=100, judged as already log-scaled)"),
 microbiome = list(unit = "TPM", expected_features =131, log_base =2,
 log_note = "log2 applied (raw max >100, judged as not log-transformed)"),
 volatilome = list(unit = "peak area", expected_features =300, log_base =NA_integer_,
 log_note = "NO log transform (raw max <=100, judged as already log-scaled)")
)

cat("=== Module1 Step3: Validation & Report ===\n")
cat("Aligned dir:", aligned_dir, "\n")
cat("Output dir :", out_dir, "\n\n")

check_mark <- function(x) if (isTRUE(x)) "PASS" else "FAIL"

# -----------------------------------------------------------------------------
#1. Verify each omics output -------------------------------------------------
# -----------------------------------------------------------------------------
verify_omics <- function(omics_id, cfg) {
 cat(sprintf("\n########## [%s] verification##########\n", omics_id))
 raw_path <- file.path(aligned_dir, sprintf("aligned_%s.csv", omics_id))
 pre_path <- file.path(out_dir, sprintf("preprocess_%s.csv", omics_id))

 raw <- fread(raw_path, header = TRUE, check.names = FALSE, data.table = FALSE)
 pre <- fread(pre_path, header = TRUE, check.names = FALSE, data.table = FALSE)

 raw_id <- names(raw)[1]
 pre_id <- names(pre)[1]
 raw_feat <- as.character(raw[[1]])
 pre_feat <- as.character(pre[[1]])
 raw_subj <- names(raw)[-1]
 pre_subj <- names(pre)[-1]

 # numeric matrix (all columns except first feature-id column)
 pre_mat <- as.matrix(pre[, -1, drop = FALSE])
 storage.mode(pre_mat) <- "double"
 raw_mat <- as.matrix(raw[, -1, drop = FALSE])
 storage.mode(raw_mat) <- "double"

 checks <- list()
 #1. first column header preserved (feature id column)
 checks$id_header <- (raw_id == pre_id)
 #2. dimension
 checks$dim <- identical(dim(raw), dim(pre))
 #3. feature ids identical & same order
 checks$features <- (length(raw_feat) == length(pre_feat)) &&
 all(raw_feat == pre_feat)
 #4. subject_id columns identical & same order
 checks$subjects <- (length(raw_subj) == length(pre_subj)) &&
 all(raw_subj == pre_subj)
 #5. numeric-only values (no non-numeric coercion introduced), no NA/Inf
 checks$numeric <- all(is.finite(pre_mat))
 #6. expected feature count
 checks$expected_feat <- (nrow(pre) == cfg$expected_features)
 #7. column-sum normalized output retains within-column variation
 col_sd <- apply(pre_mat,2, sd, na.rm = TRUE)
 checks$col_variation <- all(is.finite(col_sd) & col_sd >0)
 #8. raw input was finite & positive (dense) -> no imputation artifacts
 checks$raw_dense <- all(is.finite(raw_mat)) && all(raw_mat >0)

 pass <- all(unlist(checks))
 cat(sprintf(" dim check : %s (%d x %d vs %d x %d)\n",
 check_mark(checks$dim), nrow(pre), ncol(pre), nrow(raw), ncol(raw)))
 cat(sprintf(" id-header check : %s ('%s' == '%s')\n",
 check_mark(checks$id_header), pre_id, raw_id))
 cat(sprintf(" feature-id check : %s (%d features)\n",
 check_mark(checks$features), length(pre_feat)))
 cat(sprintf(" subject-id order : %s (%d subjects)\n",
 check_mark(checks$subjects), length(pre_subj)))
 cat(sprintf(" numeric & finite : %s\n", check_mark(checks$numeric)))
 cat(sprintf(" expected feat count : %s (%d)\n", check_mark(checks$expected_feat),
 nrow(pre)))
 cat(sprintf(" column variation : %s\n", check_mark(checks$col_variation)))
 cat(sprintf(" raw dense & positive : %s\n", check_mark(checks$raw_dense)))

 if (!pass) {
 fail_names <- names(checks)[!unlist(checks)]
 stop(sprintf("[%s] verification FAILED on: %s", omics_id,
 paste(fail_names, collapse = ", ")))
 }

 # ---- write verified downstream copy --------------------------------------
 pre_out <- file.path(root_tmp_dir, sprintf("preprocessed_%s.csv", omics_id))
 fwrite(pre, pre_out, row.names = FALSE)
 cat(" verified downstream copy:", pre_out, "\n")

 return(list(pre = pre, mat = pre_mat, rawmat = raw_mat, checks = checks))
}

# -----------------------------------------------------------------------------
#2. Run verification for all5 omics -----------------------------------------
# -----------------------------------------------------------------------------
results <- lapply(names(omics_cfg), function(id) verify_omics(id, omics_cfg[[id]]))
names(results) <- names(omics_cfg)

# ---- cross-omics subject_id order consistency ------------------------------
cat("\n########## cross-omics subject_id consistency##########\n")
ref_subj <- names(results[[1]]$pre)[-1]
cross_ok <- TRUE
for (id in names(results)) {
 ok <- all(names(results[[id]]$pre)[-1] == ref_subj)
 cross_ok <- cross_ok && ok
 cat(sprintf(" [%s] subject_id order matches rna: %s\n", id, check_mark(ok)))
}
if (!cross_ok) stop("Cross-omics subject_id order inconsistency detected!")

# -----------------------------------------------------------------------------
#3. Rebuild parameter report -------------------------------------------------
# -----------------------------------------------------------------------------
cat("\n########## build preprocessing_report.csv##########\n")
report_rows <- lapply(names(omics_cfg), function(id) {
 cfg <- omics_cfg[[id]]
 m <- results[[id]]$mat
 rawmat <- results[[id]]$rawmat
 data.frame(
 omics = id,
 unit = cfg$unit,
 n_samples = ncol(m),
 n_features = nrow(m),
 na_cells = sum(is.na(rawmat)),
 inf_cells = sum(is.infinite(rawmat)),
 zero_cells = sum(rawmat ==0, na.rm = TRUE),
 nonpos_cells = sum(rawmat <=0, na.rm = TRUE),
 imputed_cells = sum(is.na(rawmat) | is.infinite(rawmat) | rawmat <=0),
 raw_min = round(min(rawmat, na.rm = TRUE),6),
 raw_max = round(max(rawmat, na.rm = TRUE),6),
 raw_median = round(median(rawmat, na.rm = TRUE),6),
 log_transform = !is.na(cfg$log_base),
 log_base = cfg$log_base,
 log_note = cfg$log_note,
 normalization = "column-sum to1 then x10000",
 median_scale = "subtract row median (median centering)",
 out_min = round(min(m),6),
 out_max = round(max(m),6),
 out_median = round(median(m),6),
 stringsAsFactors = FALSE
 )
})
report_df <- do.call(rbind, report_rows)
rownames(report_df) <- NULL

report_file1 <- file.path(out_dir, "preprocess_report.csv")
report_file2 <- file.path(root_tmp_dir, "preprocessing_report.csv")
fwrite(report_df, report_file1, row.names = FALSE)
fwrite(report_df, report_file2, row.names = FALSE)
cat(" wrote:", report_file1, "\n")
cat(" wrote:", report_file2, "\n")

# -----------------------------------------------------------------------------
#4. Summary -------------------------------------------------------------------
# -----------------------------------------------------------------------------
cat("\n=== Module1 Step3 validation completed successfully ===\n")
print(report_df)
cat("\nALL VERIFICATION CHECKS PASSED for all5 omics.\n")
