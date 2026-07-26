# =============================================================================
# Module4: LIMMA Differential Analysis
# =============================================================================

# ---------------------------------------------------------------------------
#0. Configuration
# ---------------------------------------------------------------------------
WORK_DIR <- "G:/OmicsWorks/test/metabolism/demo/tmp/4_limma_differential_analysis"
TABLES_DIR <- file.path(WORK_DIR, "tables")
FIGURES_DIR <- "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/figures"
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
dir.create(FIGURES_DIR, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
#1. Package Installation / Loading
# ---------------------------------------------------------------------------
cat("=================================================================\n")
cat("Module4: LIMMA Differential Analysis\n")
cat("=================================================================\n\n")
cat("[1/8] Installing/loading required R packages...\n")

cran_pkgs <- c("ggplot2", "ggrepel", "ggVennDiagram", "pheatmap",
 "RColorBrewer", "UpSetR", "jsonlite")
for (pkg in cran_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
 library(pkg, character.only = TRUE)
}

bio_pkgs <- c("limma", "mixOmics")
for (pkg in bio_pkgs) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cloud.r-project.org", quiet = TRUE)
 BiocManager::install(pkg, ask = FALSE, update = FALSE, quiet = TRUE)
 }
 library(pkg, character.only = TRUE)
}

library(grDevices); library(stats)
cat(" All packages loaded successfully.\n\n")

# ---------------------------------------------------------------------------
#2. Source helper functions
# ---------------------------------------------------------------------------
cat("[2/8] Loading helper functions...\n")
source(file.path(AGENT_RSCRIPT, "data_io.R"))
source(file.path(AGENT_RSCRIPT, "differential.R"))
source(file.path(AGENT_RSCRIPT, "multivariate.R"))
source(file.path(AGENT_RSCRIPT, "visualization.R"))
cat(" Helper functions loaded.\n\n")

# ===========================================================================
#3. Data Loading and Validation
# ===========================================================================
cat("[3/8] Loading input data...\n")

expr_raw <- load_expression_matrix(PREPROCESSED_EXPR)
cat(" Expression:", nrow(expr_raw), "x", ncol(expr_raw), "\n")

sample_meta_all <- load_sample_metadata(SAMPLE_INFO)

metab_anno <- read.csv(METABOLITES_ANNO, stringsAsFactors = FALSE, check.names = FALSE)
colnames(metab_anno)[1] <- "ID"
metab_anno$ID <- as.character(metab_anno$ID)

# Match by compound name (expression rownames = compound names)
name_to_anno <- metab_anno[match(rownames(expr_raw), metab_anno$name), , drop = FALSE]
rownames(name_to_anno) <- rownames(expr_raw)
cat(" Annotation match rate:", sum(!is.na(name_to_anno$ID)), "/", nrow(expr_raw), "\n")

name_map <- setNames(name_to_anno$name, rownames(expr_raw))
name_map[is.na(name_map)] <- rownames(expr_raw)[is.na(name_map)]

if ("class" %in% colnames(metab_anno)) {
 class_map <- setNames(name_to_anno$class, rownames(expr_raw))
} else if ("kegg_category" %in% colnames(metab_anno)) {
 class_map <- setNames(name_to_anno$kegg_category, rownames(expr_raw))
} else {
 class_map <- setNames(rep("Unknown", nrow(expr_raw)), rownames(expr_raw))
}
class_map[is.na(class_map)] <- "Unknown"

# Comparison design
design_list <- jsonlite::fromJSON(DESIGN_JSON, simplifyVector = FALSE)
cat(" Comparisons:", length(design_list), "\n")
for (d in design_list) cat(" -", d$name, ":", d$treatment, "vs", d$control, "\n")

# Filter QC, drop unused levels
bio_samples <- intersect(colnames(expr_raw), sample_meta_all$ID)
expr_raw <- expr_raw[, bio_samples, drop = FALSE]
sample_meta <- sample_meta_all[sample_meta_all$ID %in% bio_samples, , drop = FALSE]
sample_meta <- sample_meta[match(colnames(expr_raw), sample_meta$ID), , drop = FALSE]
rownames(sample_meta) <- NULL
sample_meta$sample_info <- droplevels(sample_meta$sample_info)

cat(" Biological samples:", ncol(expr_raw), "\n")
cat(" Groups:", paste(levels(sample_meta$sample_info), collapse = ", "), "\n")
print(table(sample_meta$sample_info))
cat(" Data loading complete.\n\n")

# ===========================================================================
#4. Single-factor ANOVA
# ===========================================================================
cat("[4/8] Performing single-factor ANOVA...\n")

group_vector <- sample_meta$sample_info[match(colnames(expr_raw), sample_meta$ID)]

anova_list <- apply(expr_raw,1, function(row_vals) {
 df <- data.frame(value = as.numeric(row_vals), group = group_vector)
 fit <- aov(value ~ group, data = df)
 s <- summary(fit)[[1]]
 c(F_stat = s$`F value`[1], df_group = s$Df[1], df_resid = s$Df[2], pvalue = s$`Pr(>F)`[1])
})

anova_result <- data.frame(
 Feature = rownames(expr_raw), name = name_map[rownames(expr_raw)],
 F_statistic = anova_list["F_stat", ], Df_group = anova_list["df_group", ],
 Df_residual = anova_list["df_resid", ], pvalue = anova_list["pvalue", ],
 stringsAsFactors = FALSE
)
anova_result$pvalue_adj <- p.adjust(anova_result$pvalue, method = "BH")
write.csv(anova_result, OUT_ANOVA, row.names = FALSE)
cat(" ANOVA:", basename(OUT_ANOVA), "| Sig:", sum(anova_result$pvalue_adj <0.05, na.rm = TRUE), "\n\n")

# ===========================================================================
#5. Overall F-test using limma
# ===========================================================================
cat("[5/8] Performing overall F-test (limma)...\n")

design_all <- model.matrix(~0 + group_vector)
valid_grp_names <- make.names(levels(group_vector))
colnames(design_all) <- valid_grp_names

cat(" Design matrix rank:", qr(design_all)$rank, "vs", ncol(design_all), "\n")

cm_str <- paste0(valid_grp_names[2], " - ", valid_grp_names[1], ",",
 valid_grp_names[3], " - ", valid_grp_names[1])
cm <- eval(parse(text = paste0("makeContrasts(", cm_str, ", levels=design_all)")))

fit_all <- lmFit(expr_raw, design_all)
fit_all <- contrasts.fit(fit_all, cm)
fit_all <- eBayes(fit_all)
ftest_top <- topTable(fit_all, number = Inf, sort.by = "F", adjust.method = "BH")

ftest_result <- data.frame(
 Feature = rownames(ftest_top), name = name_map[rownames(ftest_top)],
 F_statistic = ftest_top$F, pvalue = ftest_top$P.Value,
 pvalue_adj = ftest_top$adj.P.Val, stringsAsFactors = FALSE
)
write.csv(ftest_result, OUT_FTEST, row.names = FALSE)
cat(" F-test:", basename(OUT_FTEST), "| Sig:", sum(ftest_result$pvalue_adj <0.05, na.rm = TRUE), "\n\n")

# ===========================================================================
#6. Pairwise LIMMA with VIP
# ===========================================================================
cat("[6/8] Performing pairwise LIMMA + VIP...\n")

GROUP_CD <- "Clostridium difficile infection"
GROUP_FE <- "high iron diet before"
GROUP_NC <- "Standard (control)"

comparisons <- list(
 list(name = "FE_vs_CD", t = GROUP_FE, c = GROUP_CD, f = OUT_FE_VS_CD, p = "FE_vs_CD",
 title = "FE (High-Iron + CDI) vs CD (CDI only)"),
 list(name = "CD_vs_NC", t = GROUP_CD, c = GROUP_NC, f = OUT_CD_VS_NC, p = "CD_vs_NC",
 title = "CD (CDI only) vs NC (Healthy Control)"),
 list(name = "FE_vs_NC", t = GROUP_FE, c = GROUP_NC, f = OUT_FE_VS_NC, p = "FE_vs_NC",
 title = "FE (High-Iron + CDI) vs NC (Healthy Control)")
)

all_de_lists <- list()
all_results <- list()

for (comp in comparisons) {
 comp_name <- comp$name
 cat(" ---", comp_name, "(", comp$t, "vs", comp$c, ") ---\n")

 # Subset
 sid <- sample_meta$ID[sample_meta$sample_info %in% c(comp$t, comp$c)]
 ce <- expr_raw[, sid, drop = FALSE]
 cm <- sample_meta[sample_meta$ID %in% sid, , drop = FALSE]
 cm <- cm[match(colnames(ce), cm$ID), ]
 cm$sample_info <- droplevels(cm$sample_info)

 cat(" Samples:", ncol(ce), "\n")

 # LIMMA
 g <- cm$sample_info
 d <- model.matrix(~0 + g)
 colnames(d) <- make.names(levels(g))
 cstr <- paste0(make.names(comp$t), " - ", make.names(comp$c))
 cmat <- eval(parse(text = paste0("makeContrasts(", cstr, ", levels=d)")))

 fit <- lmFit(ce, d)
 fit <- contrasts.fit(fit, cmat)
 fit <- eBayes(fit)
 tt <- topTable(fit, number = Inf, adjust.method = "BH", sort.by = "none")

 res <- data.frame(Feature = rownames(tt), logFC = tt$logFC,
 pvalue = tt$P.Value, pvalue_adj = tt$adj.P.Val,
 stringsAsFactors = FALSE)

 # VIP using mixOmics::plsda (note: no 'center' parameter)
 X <- t(ce); Y <- cm$sample_info
 plsda_fit <- mixOmics::plsda(X, Y, ncomp =2, scale = TRUE)
 vip_m <- mixOmics::vip(plsda_fit)
 vip_v <- vip_m[,1]; names(vip_v) <- rownames(ce)
 res$VIP <- vip_v[res$Feature]

 # Filter: p.adj <0.05 -> VIP >1 -> top500 by |logFC|
 sig_p <- res$pvalue_adj <0.05 & !is.na(res$pvalue_adj)
 cat(" After p.adj<0.05:", sum(sig_p), "\n")
 sig_v <- sig_p & !is.na(res$VIP) & res$VIP >1
 cat(" After VIP>1:", sum(sig_v), "\n")

 idx <- which(sig_v)
 if (length(idx) >0) {
 idx <- idx[order(-abs(res$logFC[idx]))]
 idx <- idx[1:min(500, length(idx))]
 }

 res$significant <- FALSE; res$significant[idx] <- TRUE
 res$direction <- "Not Significant"
 res$direction[res$significant & res$logFC >0] <- "Up"
 res$direction[res$significant & res$logFC <0] <- "Down"
 res$name <- name_map[res$Feature]
 res$class <- class_map[res$Feature]

 cat(" Final DE:", sum(res$significant), "(Up:", sum(res$direction == "Up"),
 "Down:", sum(res$direction == "Down"), ")\n")

 write.csv(res, comp$f, row.names = FALSE)
 cat(" Saved:", basename(comp$f), "\n\n")

 all_results[[comp_name]] <- res
 all_de_lists[[comp_name]] <- res$Feature[res$significant]
}

# Consolidate
cat(" Consolidating results...\n")
consolidated <- data.frame(Feature = rownames(expr_raw),
 name = name_map[rownames(expr_raw)], stringsAsFactors = FALSE)
for (comp in comparisons) {
 r <- all_results[[comp$name]]
 m <- merge(consolidated, r[, c("Feature", "logFC", "pvalue_adj", "VIP", "significant", "direction")],
 by = "Feature", all.x = TRUE)
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
cat(" Consolidated:", basename(OUT_CONSOLIDATED),
 "| Features sig in >=1 comparison:", sum(consolidated$n_significant >0), "\n\n")

# ===========================================================================
#7. Visualization
# ===========================================================================
cat("[7/8] Generating visualizations...\n")

#7a. Volcano plots
cat(" --- Volcano Plots ---\n")
for (comp in comparisons) {
 res <- all_results[[comp$name]]
 cat(" ", comp$name, "\n")

 pd <- res
 pd$neg_log10_p <- -log10(pmax(pd$pvalue_adj,1e-300))
 pd$color_group <- "Not Significant"
 pd$color_group[pd$direction == "Up"] <- "Up"
 pd$color_group[pd$direction == "Down"] <- "Down"
 pd$color_group <- factor(pd$color_group, levels = c("Up", "Down", "Not Significant"))

 # Top5 labels
 sidx <- which(pd$significant)
 if (length(sidx) >0) {
 pd$score <- abs(pd$logFC) * pd$neg_log10_p
 t5 <- sidx[order(-pd$score[sidx])][1:min(5, length(sidx))]
 } else { t5 <- integer(0) }

 nu <- sum(pd$direction == "Up", na.rm = TRUE)
 nd <- sum(pd$direction == "Down", na.rm = TRUE)

 p <- ggplot(pd, aes(x = logFC, y = neg_log10_p, color = color_group)) +
 geom_point(alpha =0.6, size =1.5) +
 scale_color_manual(values = c(Up = "#E64B35", Down = "#4DBBD5", "Not Significant" = "grey75"),
 labels = c(Up = paste0("Up (", nu, ")"), Down = paste0("Down (", nd, ")"),
 "Not Significant" = paste0("NS (", sum(!pd$significant), ")"))) +
 geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "grey50", linewidth =0.5) +
 labs(title = comp$title,
 subtitle = paste0("p.adj<0.05 + VIP>1 | ", sum(pd$significant), " DE metabolites"),
 x = expression(log[2]~Fold~Change),
 y = expression(-log[10]~(adjusted~P~value)), color = "Regulation") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 legend.position = "right", panel.grid.minor = element_blank())

 if (length(t5) >0) {
 p <- p + geom_text_repel(data = pd[t5, ], aes(label = name),
 size =3.2, max.overlaps =15, color = "black",
 box.padding =0.5, point.padding =0.3, fontface = "italic",
 segment.color = "grey50", segment.size =0.3)
 }

 pf <- file.path(FIGURES_DIR, paste0("Volcano_", comp$p, ".pdf"))
 pn <- file.path(FIGURES_DIR, paste0("Volcano_", comp$p, ".png"))
 pdf(pf, width =9, height =7); print(p); dev.off()
 png(pn, width =2700, height =2100, res =300); print(p); dev.off()
 cat(" Saved\n")
}

#7b. Venn diagram
cat(" --- Venn Diagram ---\n")
vs <- all_de_lists[sapply(all_de_lists, length) >0]
if (length(vs) >=2 && length(vs) <=3) {
 names(vs) <- c(FE_vs_CD = "FE vs CD", CD_vs_NC = "CD vs NC", FE_vs_NC = "FE vs NC")[names(vs)]

 pv <- ggVennDiagram(vs, label = "count", label_geom = "text") +
 scale_fill_gradient(low = "white", high = "steelblue") +
 labs(title = "Differential Metabolites Overlap Across Comparisons") +
 theme_bw() + theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 legend.position = "none")

 pdf(file.path(FIGURES_DIR, "Venn_diagram.pdf"), width =8, height =7); print(pv); dev.off()
 png(file.path(FIGURES_DIR, "Venn_diagram.png"), width =2400, height =2100, res =300); print(pv); dev.off()
 cat(" Saved\n")
} else {
 cat(" Skipped (need2-3 sets). Sizes:", paste(sapply(vs, length), collapse = ", "), "\n")
}

#7c. Heatmap
cat(" --- Heatmap ---\n")
asf <- unique(unlist(all_de_lists))
cat(" Unique significant metabolites:", length(asf), "\n")

if (length(asf) >0) {
 hmx <- expr_raw[asf, , drop = FALSE]
 hmz <- t(scale(t(hmx)))
 hmz[is.nan(hmz)] <-0

 # Order samples: NC -> CD -> FE
 go <- c(GROUP_NC, GROUP_CD, GROUP_FE)
 so <- unlist(lapply(go, function(g) sample_meta$ID[sample_meta$sample_info == g]))
 so <- intersect(so, colnames(hmz)); hmz <- hmz[, so, drop = FALSE]

 ca <- data.frame(Group = factor(sample_meta$sample_info[match(so, sample_meta$ID)], levels = go),
 row.names = so)

 gcols <- c("Standard (control)" = "#4DBBD5", "Clostridium difficile infection" = "#E64B35",
 "high iron diet before" = "#00A087")
 ac <- list(Group = gcols)

 rc <- class_map[rownames(hmz)]; rc[is.na(rc)] <- "Unknown"
 uc <- unique(rc); nc <- length(uc)
 cp <- if (nc <=12) RColorBrewer::brewer.pal(max(nc,3), "Set3")[1:nc] else rainbow(nc)
 names(cp) <- uc
 ra <- data.frame(Class = factor(rc), row.names = rownames(hmz))
 rac <- list(Class = cp)

 rl <- name_map[rownames(hmz)]
 srn <- length(asf) <=100
 fsize <- ifelse(srn,7,1)

 hcol <- colorRampPalette(c("#4DBBD5", "white", "#E64B35"))(100)
 hh <- max(6, min(24, nrow(hmz) *0.25 +3))

 pdf(file.path(FIGURES_DIR, "Heatmap_diff_metabolites.pdf"), width =10, height = hh)
 pheatmap(hmz, annotation_col = ca, annotation_row = ra,
 annotation_colors = c(ac, rac), cluster_rows = TRUE, cluster_cols = FALSE,
 show_rownames = srn, show_colnames = TRUE, labels_row = rl,
 color = hcol, fontsize_row = fsize, fontsize_col =8,
 border_color = NA, main = "Differential Metabolites Heatmap (Z-score)", scale = "none")
 dev.off()

 png(file.path(FIGURES_DIR, "Heatmap_diff_metabolites.png"), width =3000, height = hh *300, res =300)
 pheatmap(hmz, annotation_col = ca, annotation_row = ra,
 annotation_colors = c(ac, rac), cluster_rows = TRUE, cluster_cols = FALSE,
 show_rownames = srn, show_colnames = TRUE, labels_row = rl,
 color = hcol, fontsize_row = fsize, fontsize_col =8,
 border_color = NA, main = "Differential Metabolites Heatmap (Z-score)", scale = "none")
 dev.off()
 cat(" Heatmap saved.\n")
} else {
 cat(" No significant metabolites. Skipping heatmap.\n")
}

# ===========================================================================
#8. Summary
# ===========================================================================
cat("\n[8/8] Summary\n")
cat("=================================================================\n")
cat("Module4: LIMMA Differential Analysis - COMPLETED\n")
cat("=================================================================\n")
cat(" Input:", nrow(expr_raw), "metabolites x", ncol(expr_raw), "samples\n")
cat(" Groups:", paste(levels(sample_meta$sample_info), collapse = ", "), "\n\n")
cat(" Output files:\n")
cat(" ", basename(OUT_ANOVA), "\n")
cat(" ", basename(OUT_FTEST), "\n")
for (comp in comparisons) {
 cat(" ", basename(comp$f), "(",
 sum(all_results[[comp$name]]$significant, na.rm = TRUE), "DE)\n")
}
cat(" ", basename(OUT_CONSOLIDATED), "\n")
cat("\n Figures:", FIGURES_DIR, "\n")
cat("3 Volcano plots (FE_vs_CD, CD_vs_NC, FE_vs_NC)\n")
cat("1 Venn diagram\n")
cat("1 Heatmap\n")
cat("=================================================================\n")
