# =============================================================================
# Module4 Step2: Multi-factor ANOVA, Overall F-test & Pairwise LIMMA + VIP
# =============================================================================
# (2a) Single-factor ANOVA
# (2b) Overall F-test (limma)
# (2c) Pairwise LIMMA differential analysis
# (2d) VIP calculation via PLS-DA (mixOmics)
# (2e) Filtering: p.adj<0.05 -> VIP>1 -> top500 by |logFC|
# (2f) Results consolidation
# =============================================================================

# ---------------------------------------------------------------------------
#0. Configuration
# ---------------------------------------------------------------------------
WORK_DIR <- "G:/OmicsWorks/test/metabolism/demo/tmp/4_limma_differential_analysis"
TABLES_DIR <- file.path(WORK_DIR, "tables")
AGENT_RSCRIPT <- "G:/OmicsWorks/agent/rscript"

PREPROCESSED_EXPR <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
SAMPLE_INFO <- "G:/OmicsWorks/test/metabolism/sampleinfo.csv"
DESIGN_JSON <- "G:/OmicsWorks/test/metabolism/demo/analysis/design.json"
METABOLITES_ANNO <- "G:/OmicsWorks/test/metabolism/metabolites.csv"

OUT_ANOVA <- file.path(TABLES_DIR, "limma_multifactor_anova.csv")
OUT_FTEST <- file.path(TABLES_DIR, "limma_overall_ftest.csv")
OUT_FE_VS_CD <- file.path(TABLES_DIR, "limma_FE_vs_CD.csv")
OUT_CD_VS_NC <- file.path(TABLES_DIR, "limma_CD_vs_NC.csv")
OUT_FE_VS_NC <- file.path(TABLES_DIR, "limma_FE_vs_NC.csv")
OUT_CONSOLIDATED <- file.path(TABLES_DIR, "limma_all_comparisons_consolidated.csv")

dir.create(TABLES_DIR, recursive = TRUE, showWarnings = FALSE)

sep_line <- paste(rep("=",63), collapse = "")

# ---------------------------------------------------------------------------
#1. Package Loading
# ---------------------------------------------------------------------------
cat(sep_line, "\n")
cat("Module4 Step2: ANOVA + LIMMA + VIP Analysis\n")
cat(sep_line, "\n\n")

cat("[1] Loading packages...\n")
for (pkg in c("limma", "mixOmics", "jsonlite")) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cloud.r-project.org", quiet = TRUE)
 BiocManager::install(pkg, ask = FALSE, update = FALSE, quiet = TRUE)
 }
 library(pkg, character.only = TRUE)
}
library(stats)
source(file.path(AGENT_RSCRIPT, "data_io.R"))
source(file.path(AGENT_RSCRIPT, "differential.R"))
cat(" Packages & helpers loaded.\n\n")

# ---------------------------------------------------------------------------
#2. Data Loading
# ---------------------------------------------------------------------------
cat("[2] Loading data...\n")

expr_raw <- load_expression_matrix(PREPROCESSED_EXPR)
cat(" Expression matrix:", nrow(expr_raw), "metabolites x", ncol(expr_raw), "samples\n")

sample_meta_all <- load_sample_metadata(SAMPLE_INFO)

metab_anno <- read.csv(METABOLITES_ANNO, stringsAsFactors = FALSE, check.names = FALSE)
colnames(metab_anno)[1] <- "ID"
metab_anno$ID <- as.character(metab_anno$ID)

# Match by compound name
name_to_anno <- metab_anno[match(rownames(expr_raw), metab_anno$name), , drop = FALSE]
rownames(name_to_anno) <- rownames(expr_raw)
cat(" Annotation match rate:", sum(!is.na(name_to_anno$ID)), "/", nrow(expr_raw), "\n")

name_map <- setNames(name_to_anno$name, rownames(expr_raw))
name_map[is.na(name_map)] <- rownames(expr_raw)[is.na(name_map)]

# Comparison design
design_list <- jsonlite::fromJSON(DESIGN_JSON, simplifyVector = FALSE)
cat(" Comparisons:", length(design_list), "\n")

# Filter QC samples
bio_samples <- intersect(colnames(expr_raw), sample_meta_all$ID)
expr_raw <- expr_raw[, bio_samples, drop = FALSE]
sample_meta <- sample_meta_all[sample_meta_all$ID %in% bio_samples, , drop = FALSE]
sample_meta <- sample_meta[match(colnames(expr_raw), sample_meta$ID), , drop = FALSE]
rownames(sample_meta) <- NULL
sample_meta$sample_info <- droplevels(sample_meta$sample_info)

cat(" Biological samples:", ncol(expr_raw), "\n")
cat(" Groups:", paste(levels(sample_meta$sample_info), collapse = ", "), "\n")
print(table(sample_meta$sample_info))
cat(" Data ready.\n\n")

GROUP_CD <- "Clostridium difficile infection"
GROUP_FE <- "high iron diet before"
GROUP_NC <- "Standard (control)"

# ===========================================================================
#3. (2a) Single-factor ANOVA
# ===========================================================================
cat("[3] (2a) Performing single-factor ANOVA...\n")

group_vector <- sample_meta$sample_info[match(colnames(expr_raw), sample_meta$ID)]

anova_list <- apply(expr_raw,1, function(row_vals) {
 df <- data.frame(value = as.numeric(row_vals), group = group_vector)
 fit <- aov(value ~ group, data = df)
 s <- summary(fit)[[1]]
 c(F_stat = s$`F value`[1], df_group = s$Df[1],
 df_resid = s$Df[2], pvalue = s$`Pr(>F)`[1])
})

anova_result <- data.frame(
 Feature = rownames(expr_raw),
 name = name_map[rownames(expr_raw)],
 F_statistic = anova_list["F_stat", ],
 Df_group = anova_list["df_group", ],
 Df_residual = anova_list["df_resid", ],
 pvalue = anova_list["pvalue", ],
 stringsAsFactors = FALSE
)
anova_result$pvalue_adj <- p.adjust(anova_result$pvalue, method = "BH")
write.csv(anova_result, OUT_ANOVA, row.names = FALSE)
cat(" Saved:", basename(OUT_ANOVA), "\n")
cat(" Significant (FDR<0.05):", sum(anova_result$pvalue_adj <0.05, na.rm = TRUE), "\n\n")

# ===========================================================================
#4. (2b) Overall F-test (limma)
# ===========================================================================
cat("[4] (2b) Performing overall F-test via limma...\n")

design_all <- model.matrix(~0 + group_vector)
valid_grp_names <- make.names(levels(group_vector))
colnames(design_all) <- valid_grp_names

cm_str <- paste0(valid_grp_names[2], " - ", valid_grp_names[1], ",",
 valid_grp_names[3], " - ", valid_grp_names[1])
cm <- eval(parse(text = paste0("makeContrasts(", cm_str, ", levels=design_all)")))

fit_all <- lmFit(expr_raw, design_all)
fit_all <- contrasts.fit(fit_all, cm)
fit_all <- eBayes(fit_all)
ftest_top <- topTable(fit_all, number = Inf, sort.by = "F", adjust.method = "BH")

ftest_result <- data.frame(
 Feature = rownames(ftest_top),
 name = name_map[rownames(ftest_top)],
 F_statistic = ftest_top$F,
 pvalue = ftest_top$P.Value,
 pvalue_adj = ftest_top$adj.P.Val,
 stringsAsFactors = FALSE
)
write.csv(ftest_result, OUT_FTEST, row.names = FALSE)
cat(" Saved:", basename(OUT_FTEST), "\n")
cat(" Significant (FDR<0.05):", sum(ftest_result$pvalue_adj <0.05, na.rm = TRUE), "\n\n")

# ===========================================================================
#5. (2c-2e) Pairwise LIMMA + VIP for each comparison
# ===========================================================================
cat("[5] (2c-2e) Performing pairwise LIMMA + VIP...\n")

comparisons <- list(
 list(name = "FE_vs_CD", t = GROUP_FE, c = GROUP_CD, f = OUT_FE_VS_CD),
 list(name = "CD_vs_NC", t = GROUP_CD, c = GROUP_NC, f = OUT_CD_VS_NC),
 list(name = "FE_vs_NC", t = GROUP_FE, c = GROUP_NC, f = OUT_FE_VS_NC)
)

all_results <- list()
all_de_lists <- list()

for (comp in comparisons) {
 comp_name <- comp$name
 cat(" ---", comp_name, "(", comp$t, "vs", comp$c, ") ---\n")

 # Subset to two groups
 sid <- sample_meta$ID[sample_meta$sample_info %in% c(comp$t, comp$c)]
 ce <- expr_raw[, sid, drop = FALSE]
 cm <- sample_meta[sample_meta$ID %in% sid, , drop = FALSE]
 cm <- cm[match(colnames(ce), cm$ID), ]
 cm$sample_info <- droplevels(cm$sample_info)
 cat(" Samples:", ncol(ce), "\n")

 # (2c) LIMMA
 g <- cm$sample_info
 d <- model.matrix(~0 + g)
 colnames(d) <- make.names(levels(g))
 cstr <- paste0(make.names(comp$t), " - ", make.names(comp$c))
 cmat <- eval(parse(text = paste0("makeContrasts(", cstr, ", levels=d)")))

 fit <- lmFit(ce, d)
 fit <- contrasts.fit(fit, cmat)
 fit <- eBayes(fit)
 tt <- topTable(fit, number = Inf, adjust.method = "BH", sort.by = "none")

 res <- data.frame(
 Feature = rownames(tt),
 logFC = tt$logFC,
 AveExpr = tt$AveExpr,
 t_statistic = tt$t,
 pvalue = tt$P.Value,
 pvalue_adj = tt$adj.P.Val,
 B_statistic = tt$B,
 stringsAsFactors = FALSE
 )

 # (2d) VIP via PLS-DA (mixOmics, no center param)
 X <- t(ce); Y <- cm$sample_info
 plsda_fit <- mixOmics::plsda(X, Y, ncomp =2, scale = TRUE)
 vip_m <- mixOmics::vip(plsda_fit)
 vip_v <- vip_m[,1]
 names(vip_v) <- rownames(ce)
 res$VIP <- vip_v[res$Feature]

 # (2e) Filter: p.adj <0.05 -> VIP >1 -> top500 by |logFC|
 sig_p <- res$pvalue_adj <0.05 & !is.na(res$pvalue_adj)
 cat(" After p.adj<0.05:", sum(sig_p), "\n")
 sig_v <- sig_p & !is.na(res$VIP) & res$VIP >1
 cat(" After VIP>1:", sum(sig_v), "\n")

 idx <- which(sig_v)
 if (length(idx) >0) {
 idx <- idx[order(-abs(res$logFC[idx]))]
 idx <- idx[1:min(500, length(idx))]
 }

 # Mark significant and direction
 res$significant <- FALSE
 res$significant[idx] <- TRUE
 res$direction <- "Not Significant"
 res$direction[res$significant & res$logFC >0] <- "Up"
 res$direction[res$significant & res$logFC <0] <- "Down"
 res$name <- name_map[res$Feature]

 n_up <- sum(res$direction == "Up", na.rm = TRUE)
 n_down <- sum(res$direction == "Down", na.rm = TRUE)
 cat(" Final DE:", sum(res$significant), "(Up:", n_up, "Down:", n_down, ")\n")

 write.csv(res, comp$f, row.names = FALSE)
 cat(" Saved:", basename(comp$f), "\n")

 all_results[[comp_name]] <- res
 all_de_lists[[comp_name]] <- res$Feature[res$significant]
 cat("\n")
}

# ===========================================================================
#6. (2f) Consolidate results
# ===========================================================================
cat("[6] (2f) Consolidating all comparison results...\n")

consolidated <- data.frame(
 Feature = rownames(expr_raw),
 name = name_map[rownames(expr_raw)],
 stringsAsFactors = FALSE
)

for (comp in comparisons) {
 r <- all_results[[comp$name]]
 sub_r <- r[, c("Feature", "logFC", "pvalue_adj", "VIP", "significant", "direction")]
 m <- merge(consolidated, sub_r, by = "Feature", all.x = TRUE)
 colnames(m)[colnames(m) == "logFC"] <- paste0("logFC_", comp$name)
 colnames(m)[colnames(m) == "pvalue_adj"] <- paste0("pval_adj_", comp$name)
 colnames(m)[colnames(m) == "VIP"] <- paste0("VIP_", comp$name)
 colnames(m)[colnames(m) == "significant"] <- paste0("sig_", comp$name)
 colnames(m)[colnames(m) == "direction"] <- paste0("direction_", comp$name)
 consolidated <- m
}

sc <- grep("^sig_", colnames(consolidated))
consolidated$n_significant <- rowSums(consolidated[, sc, drop = FALSE], na.rm = TRUE)
write.csv(consolidated, OUT_CONSOLIDATED, row.names = FALSE)
cat(" Saved:", basename(OUT_CONSOLIDATED), "\n")
cat(" Features sig in >=1 comparison:", sum(consolidated$n_significant >0), "\n\n")

# ===========================================================================
#7. Summary
# ===========================================================================
cat(sep_line, "\n")
cat("Step2 COMPLETED SUCCESSFULLY\n")
cat(sep_line, "\n\n")

cat("Output files:\n")
cat(" ANOVA :", basename(OUT_ANOVA),
 "|", sum(anova_result$pvalue_adj <0.05, na.rm = TRUE), "significant\n")
cat(" F-test :", basename(OUT_FTEST),
 "|", sum(ftest_result$pvalue_adj <0.05, na.rm = TRUE), "significant\n")
for (comp in comparisons) {
 n_sig <- sum(all_results[[comp$name]]$significant, na.rm = TRUE)
 n_up <- sum(all_results[[comp$name]]$direction == "Up", na.rm = TRUE)
 n_down <- sum(all_results[[comp$name]]$direction == "Down", na.rm = TRUE)
 cat(" ", comp$name, ":", basename(comp$f),
 "|", n_sig, "DE (Up:", n_up, "Down:", n_down, ")\n")
}
cat(" Consolidated :", basename(OUT_CONSOLIDATED), "\n\n")
cat("Ready for downstream module (KEGG enrichment, reports, tables).\n")
