# ============================================================
# PLS-PM Causal Path Analysis Script v4
# Module9: PLS-PM Causal Path Analysis
# ============================================================
# Two complementary PLS-PM models:
# Model A:6 WGCNA Module Eigengenes (LVs) with BN-derived paths
# Model B:5 KEGG GSVA pathway aggregates (LVs)
# ============================================================

# ---- Install packages ----
for (pkg in c("plspm", "igraph", "ggplot2", "ggrepel", "psych",
 "grid", "grDevices", "reshape2", "jsonlite")) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
 suppressPackageStartupMessages(library(pkg, character.only = TRUE))
}

source("G:/OmicsWorks/agent/rscript/data_io.R")

# ---- Paths ----
BD <- "G:/OmicsWorks/test/metabolism/demo"
TD <- file.path(BD, "tmp", "9_pls_pm_causal_path_analysis")
AD <- file.path(BD, "analysis", "9_pls_pm_causal_path_analysis")
FD <- file.path(AD, "figures")
TB <- file.path(TD, "tables")
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
dir.create(AD, recursive = TRUE, showWarnings = FALSE)
dir.create(FD, recursive = TRUE, showWarnings = FALSE)
dir.create(TB, recursive = TRUE, showWarnings = FALSE)

cat("===== PLS-PM Causal Path Analysis =====\n")
cat("Tables:", TB, "\nFigures:", FD, "\n")

# ============================================================
# STEP1: Load data
# ============================================================
cat("\n[1] Loading input data...\n")

meta <- load_sample_metadata(file.path(BD, "tmp", "1_expression_matrix_preprocessing", "sampleinfo.csv"))
meta <- meta[meta$sample_info != "QC", ]
rownames(meta) <- meta$ID

me <- read.csv(file.path(BD, "tmp", "6_wgcna_trait_association_analysis", "tables", "wgcna_module_eigengenes.csv"),
 stringsAsFactors = FALSE)
colnames(me)[1] <- "Sample"
rownames(me) <- me$Sample
me$Sample <- NULL
cs <- intersect(rownames(me), rownames(meta))
me <- me[cs, ]; meta <- meta[cs, ]

gsva_raw <- read.csv(file.path(BD, "tmp", "6_wgcna_trait_association_analysis", "tables", "wgcna_gsva_scores.csv"),
 stringsAsFactors = FALSE, check.names = FALSE, row.names =1)
gsva <- as.data.frame(t(gsva_raw))
gsva <- gsva[cs, ]
cat("Samples:", nrow(meta), "MEs:", ncol(me), "GSVA:", ncol(gsva), "\n")

gm <- c("Clostridium difficile infection" = "CD", "high iron diet before" = "FE", "Standard (control)" = "NC")
grp <- factor(gm[meta$sample_info], levels = c("NC", "CD", "FE"))
names(grp) <- rownames(meta)
cat("Groups:", paste(names(table(grp)), table(grp), sep = "=", collapse = ", "), "\n")

# ============================================================
# STEP2: Model A - Module-level PLS-PM
# ============================================================
cat("\n[2] Model A (Module-level PLS-PM)...\n")

lvA <- c("PurpleModule", "RedModule", "BlueModule", "BlackModule", "TurquoiseModule", "MagentaModule")
me_map <- c(MEpurple = "PurpleModule", MEred = "RedModule", MEblue = "BlueModule",
 MEblack = "BlackModule", MEturquoise = "TurquoiseModule", MEmagenta = "MagentaModule")
datA <- me[, names(me_map)]
colnames(datA) <- me_map

nA <- length(lvA)
pA <- matrix(0, nA, nA, dimnames = list(lvA, lvA))
pA["BlackModule", "PurpleModule"] <-1 # row4->col1
pA["TurquoiseModule", "BlueModule"] <-1 # row5->col3
pA["TurquoiseModule", "RedModule"] <-1 # row5->col2
pA["MagentaModule", "BlueModule"] <-1 # row6->col3
pA["MagentaModule", "RedModule"] <-1 # row6->col2
pA["BlueModule", "RedModule"] <-1 # row3->col2
cat("Model A upper.tri sum:", sum(pA[upper.tri(pA)]), "(must be0)\n")

set.seed(42)
mA <- plspm::plspm(datA, pA, blocks = as.list(1:nA), modes = rep("A", nA),
 scaled = TRUE, boot.val = TRUE, br =1000)
gofA <- if (is.nan(mA$gof)) NA else mA$gof

# R2 - stored in inner_model as attributes or in $R2
r2A <- mA$R2
if (length(r2A) >0) {
 names(r2A) <- lvA[as.integer(names(r2A))]
 cat("R2 values:")
 for (nm in names(r2A)) cat("", nm, "=", round(r2A[nm],3))
 cat("\n")
} else {
 cat("R2: empty (single-indicator LVs may not produce R2)\n")
 # Extract R2 from inner model
 r2_from_inner <- c()
 for (nm in names(mA$inner_model)) {
 im <- mA$inner_model[[nm]]
 if ("R2" %in% colnames(im)) {
 r2_from_inner[nm] <- im[1, "R2"]
 }
 }
 if (length(r2_from_inner) >0) {
 r2A <- r2_from_inner
 cat("R2 from inner model:", paste(names(r2A), round(r2A,3), sep = "="), "\n")
 }
}

# Save Model A
write.csv(as.data.frame(mA$path_coefs), file.path(TB, "plspm_module_path_coefficients.csv"))
il <- list()
for (i in seq_along(mA$inner_model)) {
 df <- as.data.frame(mA$inner_model[[i]]); df$Dependent <- names(mA$inner_model)[i]; df$Predictor <- rownames(df)
 il[[i]] <- df
}
write.csv(do.call(rbind, il), file.path(TB, "plspm_module_inner_model.csv"), row.names = FALSE)
write.csv(mA$outer_model, file.path(TB, "plspm_module_outer_model.csv"), row.names = FALSE)
sc <- as.data.frame(mA$scores); sc$Sample <- rownames(sc); sc$Group <- grp[rownames(sc)]
write.csv(sc, file.path(TB, "plspm_module_latent_scores.csv"), row.names = FALSE)
if (!is.null(mA$unidim) && nrow(mA$unidim) >0) write.csv(mA$unidim, file.path(TB, "plspm_module_unidimensionality.csv"))
write.csv(as.data.frame(mA$effects), file.path(TB, "plspm_module_total_effects.csv"), row.names = FALSE)
write.csv(data.frame(GoF = gofA), file.path(TB, "plspm_module_gof.csv"), row.names = FALSE)

# ============================================================
# STEP3: Model B - Pathway-level PLS-PM
# ============================================================
cat("\n[3] Model B (Pathway-level PLS-PM)...\n")

pw_groups <- list(
 Iron_Metabolism = c("09110 Biosynthesis of other secondary metabolites", "09175 Drug resistance: antimicrobial", "09111 Xenobiotics biodegradation and metabolism"),
 Lipid_Metabolism = c("09103 Lipid metabolism", "09101 Carbohydrate metabolism", "09106 Metabolism of other amino acids"),
 Signal_Transduction = c("09132 Signal transduction", "09161 Cancer: overview", "09171 Infectious disease: bacterial", "09143 Cell growth and death"),
 Energy_Metabolism = c("09102 Energy metabolism", "09108 Metabolism of cofactors and vitamins", "09149 Aging", "09104 Nucleotide metabolism"),
 Excretory_System = c("09155 Excretory system", "09154 Digestive system", "09131 Membrane transport", "09152 Endocrine system")
)

lvB <- c("Excretory_System", "Signal_Transduction", "Lipid_Metabolism", "Energy_Metabolism", "Iron_Metabolism")
datB <- data.frame(row.names = rownames(gsva))
for (lv in lvB) {
 av <- intersect(pw_groups[[lv]], colnames(gsva))
 datB[[lv]] <- if (length(av) ==1) gsva[[av[1]]] else rowMeans(gsva[, av, drop = FALSE], na.rm = TRUE)
}
datB <- na.omit(datB)

nB <- length(lvB)
pB <- matrix(0, nB, nB, dimnames = list(lvB, lvB))
pB["Iron_Metabolism", "Excretory_System"] <-1
pB["Iron_Metabolism", "Signal_Transduction"] <-1
pB["Iron_Metabolism", "Lipid_Metabolism"] <-1
pB["Iron_Metabolism", "Energy_Metabolism"] <-1
pB["Lipid_Metabolism", "Signal_Transduction"] <-1
pB["Energy_Metabolism", "Excretory_System"] <-1
cat("Model B upper.tri sum:", sum(pB[upper.tri(pB)]), "(must be0)\n")

set.seed(42)
mB <- plspm::plspm(datB, pB, blocks = as.list(1:nB), modes = rep("A", nB),
 scaled = TRUE, boot.val = TRUE, br =1000)
gofB <- if (is.nan(mB$gof)) NA else mB$gof

r2B <- mB$R2
if (length(r2B) >0) {
 names(r2B) <- lvB[as.integer(names(r2B))]
 cat("R2 values:")
 for (nm in names(r2B)) cat("", nm, "=", round(r2B[nm],3))
 cat("\n")
} else {
 cat("R2: empty\n")
 r2_from_inner <- c()
 for (nm in names(mB$inner_model)) {
 im <- mB$inner_model[[nm]]
 if ("R2" %in% colnames(im)) r2_from_inner[nm] <- im[1, "R2"]
 }
 if (length(r2_from_inner) >0) { r2B <- r2_from_inner; cat("R2 from inner model:", paste(names(r2B), round(r2B,3), sep = "="), "\n") }
}

write.csv(as.data.frame(mB$path_coefs), file.path(TB, "plspm_pathway_path_coefficients.csv"))
ilB <- list()
for (i in seq_along(mB$inner_model)) {
 df <- as.data.frame(mB$inner_model[[i]]); df$Dependent <- names(mB$inner_model)[i]; df$Predictor <- rownames(df)
 ilB[[i]] <- df
}
write.csv(do.call(rbind, ilB), file.path(TB, "plspm_pathway_inner_model.csv"), row.names = FALSE)
write.csv(mB$outer_model, file.path(TB, "plspm_pathway_outer_model.csv"), row.names = FALSE)
scB <- as.data.frame(mB$scores); scB$Sample <- rownames(scB); scB$Group <- grp[rownames(scB)]
write.csv(scB, file.path(TB, "plspm_pathway_latent_scores.csv"), row.names = FALSE)
if (!is.null(mB$unidim) && nrow(mB$unidim) >0) write.csv(mB$unidim, file.path(TB, "plspm_pathway_unidimensionality.csv"))
write.csv(as.data.frame(mB$effects), file.path(TB, "plspm_pathway_total_effects.csv"), row.names = FALSE)
write.csv(data.frame(GoF = gofB), file.path(TB, "plspm_pathway_gof.csv"), row.names = FALSE)

# ============================================================
# STEP4: Cronbach's Alpha
# ============================================================
cat("\n[4] Cronbach's alpha...\n")
alpha_df <- data.frame(LV = character(), N_Ind = integer(), Alpha = character(), stringsAsFactors = FALSE)
for (i in seq_along(lvA)) {
 v <- NA
 if (!is.null(mA$unidim) && nrow(mA$unidim) >= i) {
 tmp <- mA$unidim[i, "Cronbach.alpha"]
 if (is.numeric(tmp)) v <- round(tmp,4)
 }
 alpha_df <- rbind(alpha_df, data.frame(LV = paste0("A_", lvA[i]), N_Ind =1, Alpha = if (is.na(v)) "NA" else as.character(v), stringsAsFactors = FALSE))
}
for (lv in lvB) {
 av <- intersect(pw_groups[[lv]], colnames(gsva))
 a_str <- "NA"
 if (length(av) >=2) {
 a <- psych::alpha(gsva[, av, drop = FALSE], check.keys = TRUE)$total$raw_alpha
 a_str <- as.character(round(a,4))
 }
 alpha_df <- rbind(alpha_df, data.frame(LV = paste0("B_", lv), N_Ind = length(av), Alpha = a_str, stringsAsFactors = FALSE))
}
write.csv(alpha_df, file.path(TB, "plspm_cronbach_alpha.csv"), row.names = FALSE)
print(alpha_df)

# ============================================================
# STEP5: Path Diagrams
# ============================================================
cat("\n[5] Generating path diagrams...\n")

draw_path_diagram <- function(res, lv_vec, r2_list, col_map, sz_map, title_str, gof_val, prefix, fig_dir) {
 pc <- res$path_coefs; n <- length(lv_vec)
 # Edges
 edges <- data.frame(from = character(), to = character(), w = numeric(), stringsAsFactors = FALSE)
 for (i in seq_len(n)) for (j in seq_len(n)) if (pc[i,j] !=0) edges <- rbind(edges, data.frame(from = lv_vec[i], to = lv_vec[j], w = round(pc[i,j],3), stringsAsFactors = FALSE))
 if (nrow(edges) ==0) { cat(" No edges.\n"); return(invisible(NULL)) }
 # Bootstrap p-values
 bp <- res$boot$paths; edges$sig <- ""; edges$pv <-1
 for (k in seq_len(nrow(edges))) {
 ft <- paste0(edges$from[k], " -> ", edges$to[k])
 if (ft %in% rownames(bp)) {
 pv <- bp[ft, "p.value"]
 edges$pv[k] <- if (is.na(pv))1 else pv
 edges$sig[k] <- if (pv <0.001) "***" else if (pv <0.01) "**" else if (pv <0.05) "*" else "ns"
 }
 }
 # Labels
 nlabs <- lv_vec
 for (i in seq_len(n)) {
 lab <- gsub("Module", "", lv_vec[i]); lab <- gsub("_", " ", lab)
 if (lv_vec[i] %in% names(r2_list) && !is.na(r2_list[[lv_vec[i]]])) nlabs[i] <- paste0(lab, "\n(R2=", round(r2_list[[lv_vec[i]]],3), ")") else nlabs[i] <- lab
 }
 # Layout
 g <- igraph::graph_from_data_frame(edges[, c("from", "to")], directed = TRUE, vertices = lv_vec)
 set.seed(42); lay <- igraph::layout_with_fr(g, niter =5000)
 sz_vec <- if (!is.null(sz_map)) sqrt(sz_map[lv_vec]) *0.8 else rep(18, n)
 nd <- data.frame(Node = lv_vec, x = lay[,1], y = lay[,2], Color = col_map[lv_vec], Size = sz_vec, Label = nlabs, stringsAsFactors = FALSE)
 # Edge coords
 edf <- do.call(rbind, lapply(seq_len(nrow(edges)), function(k) {
 f <- edges$from[k]; t <- edges$to[k]
 data.frame(x = nd$x[nd$Node == f], y = nd$y[nd$Node == f], xend = nd$x[nd$Node == t], yend = nd$y[nd$Node == t], w = edges$w[k], sig = edges$sig[k], pv = edges$pv[k], stringsAsFactors = FALSE)
 }))
 edf$color <- ifelse(edf$w >=0, "#CC3333", "#3366CC"); edf$lty <- ifelse(edf$pv <0.05, "solid", "dashed")
 # Plot
 p <- ggplot() +
 geom_segment(data = edf, aes(x = x, y = y, xend = xend, yend = yend, linewidth = abs(w)*2, color = color, linetype = lty),
 arrow = arrow(length = unit(0.15, "inches"), type = "closed"), alpha =0.8) +
 geom_text_repel(data = edf, aes(x = (x+xend)/2, y = (y+yend)/2, label = paste0(w, sig)),
 size =3.5, fontface = "bold", box.padding =0.3, point.padding =0.2, bg.color = "white", bg.r =0.1, force =2) +
 geom_point(data = nd, aes(x = x, y = y, fill = Color), shape =21, size = nd$Size, color = "black", stroke =1.5) +
 geom_text(data = nd, aes(x = x, y = y, label = Label), size =3.2, fontface = "bold", color = "black") +
 scale_color_identity() + scale_fill_identity() + scale_linetype_identity() +
 scale_linewidth_continuous(range = c(0.5,3)) +
 labs(title = title_str, subtitle = paste0("GoF = ", if (is.na(gof_val)) "N/A" else round(gof_val,4)), x = "", y = "") +
 theme_minimal(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =13, face = "bold"), plot.subtitle = element_text(hjust =0.5, size =10, color = "grey40"),
 axis.text = element_blank(), axis.ticks = element_blank(), panel.grid = element_blank(), legend.position = "none")
 pdf(file.path(fig_dir, paste0(prefix, "_path_diagram.pdf")), width =12, height =10); print(p); dev.off()
 png(file.path(fig_dir, paste0(prefix, "_path_diagram.png")), width =3600, height =3000, res =300); print(p); dev.off()
 cat(" Saved:", file.path(fig_dir, paste0(prefix, "_path_diagram.pdf")), "\n")
}

r2A_list <- if (length(r2A) >0) as.list(r2A) else list()
draw_path_diagram(mA, lvA, r2A_list,
 c(PurpleModule="#9933CC", RedModule="#FF4444", BlueModule="#3366CC", BlackModule="#8B4513", TurquoiseModule="#CC3333", MagentaModule="#33AA33"),
 c(PurpleModule=37, RedModule=116, BlueModule=511, BlackModule=577, TurquoiseModule=539, MagentaModule=279),
 "PLS-PM Causal Path Model A: Module-level\n(BN-derived path structure)", gofA, "PLSPM_module", FD)

r2B_list <- if (length(r2B) >0) as.list(r2B) else list()
draw_path_diagram(mB, lvB, r2B_list,
 c(Excretory_System="#3366CC", Signal_Transduction="#CC3333", Lipid_Metabolism="#339933", Energy_Metabolism="#FF9900", Iron_Metabolism="#CC6633"),
 NULL, "PLS-PM Causal Path Model B: Pathway-level\n(Diet-Microbiome-Host causal chain)", gofB, "PLSPM_pathway", FD)

# ============================================================
# STEP6: Bootstrap Stability
# ============================================================
cat("\n[6] Bootstrap stability plots...\n")

draw_bootstrap <- function(res, mname, prefix, fig_dir) {
 bp <- as.data.frame(res$boot$paths)
 if (is.null(bp) || nrow(bp) ==0) { cat(" No bootstrap for", mname, "\n"); return(invisible(NULL)) }
 bp$Path <- rownames(bp)
 bp <- bp[!is.na(bp$Original), ]
 if (nrow(bp) ==0) return(invisible(NULL))
 
 # Handle different column name conventions for CI bounds
 lo_col <- if ("X2.5." %in% colnames(bp)) "X2.5." else if ("perc.025" %in% colnames(bp)) "perc.025" else if ("X2.5" %in% colnames(bp)) "X2.5" else colnames(bp)[grep("2\\.5|025", colnames(bp))[1]]
 hi_col <- if ("X97.5." %in% colnames(bp)) "X97.5." else if ("perc.975" %in% colnames(bp)) "perc.975" else if ("X97.5" %in% colnames(bp)) "X97.5" else colnames(bp)[grep("97\\.5|975", colnames(bp))[1]]
 
 if (is.na(lo_col) || is.na(hi_col)) {
 cat(" Could not find CI columns in bootstrap output. Available:", paste(colnames(bp), collapse = ", "), "\n")
 return(invisible(NULL))
 }
 
 p <- ggplot(bp, aes(x = reorder(Path, Original), y = Original)) +
 geom_pointrange(aes(ymin = .data[[lo_col]], ymax = .data[[hi_col]]), color = "#3366CC", size =0.8) +
 geom_hline(yintercept =0, linetype = "dashed", color = "red", alpha =0.5) +
 labs(title = paste0("Bootstrap Path Coefficients (", mname, ")"), subtitle = "95% bootstrap CI", x = "Path", y = "Coefficient") +
 theme_minimal(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"), axis.text.x = element_text(angle =45, hjust =1)) +
 coord_flip()
 pdf(file.path(fig_dir, paste0(prefix, "_bootstrap.pdf")), width =10, height =8); print(p); dev.off()
 png(file.path(fig_dir, paste0(prefix, "_bootstrap.png")), width =3000, height =2400, res =300); print(p); dev.off()
 cat(" Saved:", file.path(fig_dir, paste0(prefix, "_bootstrap.pdf")), "\n")
}

draw_bootstrap(mA, "Model A (Module-level)", "PLSPM_module", FD)
draw_bootstrap(mB, "Model B (Pathway-level)", "PLSPM_pathway", FD)

# ============================================================
# STEP7: Model Comparison
# ============================================================
cat("\n[7] Model comparison...\n")

mod_boot <- as.data.frame(mA$boot$paths)
pat_boot <- as.data.frame(mB$boot$paths)

cmp <- data.frame(Model = c("Model A (Module-level)", "Model B (Pathway-level)"),
 LVs = c(nA, nB),
 GoF = c(if (is.na(gofA)) "NaN" else round(gofA,4), if (is.na(gofB)) "NaN" else round(gofB,4)),
 Sig_Paths = c(sum(mod_boot$p.value <0.05, na.rm = TRUE), sum(pat_boot$p.value <0.05, na.rm = TRUE)),
 stringsAsFactors = FALSE)
print(cmp)
write.csv(cmp, file.path(TB, "plspm_model_comparison.csv"), row.names = FALSE)

# ============================================================
# STEP8: result.json
# ============================================================
cat("\n[8] Writing result.json...\n")

build_path_list <- function(pc, bp_df) {
 pl <- list()
 for (i in seq_len(nrow(pc))) for (j in seq_len(ncol(pc))) if (pc[i,j] !=0) {
 pn <- paste0(rownames(pc)[i], "->", colnames(pc)[j])
 pv <- NA; if (pn %in% rownames(bp_df)) pv <- round(bp_df[pn, "p.value"],4)
 pl[[pn]] <- list(coefficient = round(pc[i,j],4), p_value = pv)
 }
 pl
}

r2A_out <- if (length(r2A) >0) lapply(r2A, round,4) else list()
r2B_out <- if (length(r2B) >0) lapply(r2B, round,4) else list()

result <- list(
 module_name = "PLS-PM Causal Path Analysis",
 goal = "构建模块级和通路级PLS-PM因果路径模型",
 model_a = list(lv_order = lvA, gof = gofA, r2 = r2A_out, paths = build_path_list(mA$path_coefs, mod_boot)),
 model_b = list(lv_order = lvB, gof = gofB, r2 = r2B_out, paths = build_path_list(mB$path_coefs, pat_boot)),
 model_comparison = cmp, cronbach_alpha = alpha_df
)
jsonlite::write_json(result, file.path(TD, "result.json"), pretty = TRUE, auto_unbox = TRUE)

cat("\n===== PLS-PM Analysis Complete! =====\n")
cat("Tables:", TB, "\n"); for (f in list.files(TB, pattern = ".csv$")) cat(" ", f, "\n")
cat("Figures:", FD, "\n"); for (f in list.files(FD, pattern = ".(png|pdf)$")) cat(" ", f, "\n")
