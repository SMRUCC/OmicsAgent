import re

with open(r"G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R", "r") as f:
 content = f.read()

# Find the PART B section and replace it
part_b_marker = "# =========================================================================\\n# PART B: OPLSDA"
part_b_end = "# =========================================================================\\n# SUMMARY OUTPUT"

new_part_b = """# =========================================================================
# PART B: OPLSDA (pairwise binary comparisons)
# Note: ropls OPLS-DA only supports binary classification.
# We run3 pairwise comparisons: FE_vs_NC, CD_vs_NC, FE_vs_CD
# =========================================================================
cat("\\n========================================================\\n")
cat(" PART B: OPLSDA - Pairwise Comparisons\\n")
cat("========================================================\\n\\n")

pairwise_list <- list(
 c("FE", "NC"),
 c("CD", "NC"),
 c("FE", "CD")
)
pairwise_names <- c("FE_vs_NC", "CD_vs_NC", "FE_vs_CD")

all_opls_scores <- list()
all_splot_data <- list()
all_opls_params <- list()

for (pw_idx in seq_along(pairwise_list)) {
 pw <- pairwise_list[[pw_idx]]
 pw_name <- pairwise_names[pw_idx]
 cat(sprintf("\\n[B%d] Running OPLSDA: %s\\n", pw_idx, pw_name))
  
 # Subset data for this pair
 keep_samples <- rownames(X)[sample_meta[rownames(X), "group_label"] %in% pw]
 X_pair <- X[keep_samples, , drop = FALSE]
 Y_pair <- factor(as.character(sample_meta[keep_samples, "group_label"]))
  
 cat(" Samples:", nrow(X_pair), " Features:", ncol(X_pair), "\\n")
 cat(" Groups:", paste(levels(Y_pair), collapse=" vs "), "\\n")
  
 # Run OPLSDA
 set.seed(42)
 opls_pair <- ropls::opls(X_pair, Y_pair, predI =1, orthoI =1,
 fig.pdfC = "none", info.txtC = "none",
 permI =0)
  
 # Extract parameters
 mdl_df <- opls_pair@modelDF
 r2x_pred <- ifelse(nrow(mdl_df) >=1, mdl_df[1, "R2X"], NA)
 r2x_orth <- ifelse(nrow(mdl_df) >=2, mdl_df[2, "R2X"], NA)
 r2y <- ifelse(nrow(mdl_df) >=1, mdl_df[1, "R2Y"], NA)
 q2 <- ifelse(nrow(mdl_df) >=1, mdl_df[1, "Q2"], NA)
 cat(sprintf(" R2X(pred)=%.3f, R2X(orth)=%.3f, R2Y=%.3f, Q2=%.3f\\n",
 r2x_pred, r2x_orth, r2y, q2))
  
 all_opls_params[[pw_name]] <- data.frame(
 Comparison = pw_name,
 R2X_pred = r2x_pred, R2X_orth = r2x_orth,
 R2Y = r2y, Q2 = q2,
 stringsAsFactors = FALSE
 )
  
 # Scores
 scores_pair <- as.data.frame(ropls::getScoreMN(opls_pair))
 ncol_sp <- ncol(scores_pair)
 colnames(scores_pair) <- paste0("Comp",1:ncol_sp)
 if (ncol_sp ==1) scores_pair$Comp2 <- rep(0, nrow(scores_pair))
 scores_pair$SampleID <- rownames(scores_pair)
 scores_pair$Group <- sample_meta[rownames(scores_pair), "group_label"]
 scores_pair$SampleName <- sample_meta[rownames(scores_pair), "sample_name"]
 scores_pair$Comparison <- pw_name
 all_opls_scores[[pw_name]] <- scores_pair
  
 # VIP
 vip_pair <- ropls::getVipVn(opls_pair)
  
 # S-plot data
 load_pair <- ropls::getLoadingMN(opls_pair)
 pcorr_pair <- opls_pair@suppLs[["mc"]]
  
 splot_pair <- data.frame(
 Feature = rownames(load_pair),
 Loading = as.numeric(load_pair[,1]),
 pcorr = as.numeric(pcorr_pair[,1]),
 Comparison = pw_name,
 stringsAsFactors = FALSE
 )
 splot_pair$VIP <- vip_pair[splot_pair$Feature]
 splot_pair$abs_loading <- abs(splot_pair$Loading)
 splot_pair$abs_pcorr <- abs(splot_pair$pcorr)
 splot_pair$Importance <- ifelse(
 splot_pair$VIP >1 & splot_pair$abs_pcorr >0.5,
 "High (VIP>1 & |p(corr)|>0.5)",
 ifelse(splot_pair$VIP >1, "Medium (VIP>1)", "Low")
 )
 all_splot_data[[pw_name]] <- splot_pair
 cat(sprintf(" Important metabolites (VIP>1 & |p(corr)|>0.5): %d\\n",
 sum(splot_pair$Importance == "High (VIP>1 & |p(corr)|>0.5)")))
}

# Combine and save
opls_params_all <- do.call(rbind, all_opls_params)
write.csv(opls_params_all, file.path(OUTPUT_DIR, "oplsda_model_params.csv"), row.names = FALSE)
cat("\\n oplda_model_params.csv saved.\\n")

opls_scores_all <- do.call(rbind, all_opls_scores)
write.csv(opls_scores_all, file.path(OUTPUT_DIR, "oplsda_scores.csv"), row.names = FALSE)
cat(" oplda_scores.csv saved.\\n")

splot_all <- do.call(rbind, all_splot_data)
write.csv(splot_all, file.path(OUTPUT_DIR, "oplsda_s_plot.csv"), row.names = FALSE)
cat(" oplda_s_plot.csv saved.\\n")

# ----B3. OPLSDA Score Plot (combining all pairwise for visualization) ----
cat("[B3] Generating OPLSDA score plots...\\n")
for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 sc_df <- all_splot_data[[pw_name]]
  
 # Color for the two groups in this comparison
 comp_colors <- group_colors[names(group_colors) %in% unique(as.character(sc$Group))]
  
 p_opls <- ggplot(sc, aes(x = Comp1, y = Comp2,
 color = Group, shape = SampleType)) +
 geom_point(size =4, alpha =0.9) +
 stat_ellipse(level =0.95, type = "t", linewidth =0.8) +
 geom_text_repel(aes(label = SampleName), size =3.0,
 max.overlaps =20, box.padding =0.5, show.legend = FALSE) +
 scale_color_manual(values = comp_colors) +
 scale_shape_manual(values = shape_vals) +
 labs(title = paste0("OPLS-DA Score Plot (", pw_name, ")"),
 x = "Predictive Component (p1)",
 y = "Orthogonal Component (o1)",
 color = "Group", shape = "Condition",
 subtitle = paste0("R2Y=", round(all_opls_params[[pw_name]]$R2Y,3),
 ", Q2=", round(all_opls_params[[pw_name]]$Q2,3))) +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, size =13, face = "bold"),
 legend.position = "right", panel.grid.minor = element_blank())
  
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_score_plot_", pw_name, ".png")),
 p_opls, width =8, height =6, dpi =300)
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_score_plot_", pw_name, ".pdf")),
 p_opls, width =8, height =6)
 cat(" OPLSDA score plot saved for", pw_name, "\\n")
}

# ----B4. OPLSDA S-plots ----
cat("[B4] OPLSDA S-plot for each pairwise comparison...\\n")
for (pw_name in pairwise_names) {
 sp <- all_splot_data[[pw_name]]
 sp$label <- ifelse(sp$Importance == "High (VIP>1 & |p(corr)|>0.5)", sp$Feature, "")
  
 p_splot <- ggplot(sp, aes(x = Loading, y = pcorr, color = Importance)) +
 geom_point(size =1.8, alpha =0.7) +
 geom_text_repel(aes(label = label), size =2.8, max.overlaps =12,
 box.padding =0.4, show.legend = FALSE) +
 geom_hline(yintercept =0, linetype = "dashed", color = "grey50", linewidth =0.5) +
 geom_vline(xintercept =0, linetype = "dashed", color = "grey50", linewidth =0.5) +
 scale_color_manual(values = c("High (VIP>1 & |p(corr)|>0.5)" = "#E64B35",
 "Medium (VIP>1)" = "#00A087", "Low" = "grey70")) +
 labs(title = paste0("OPLS-DA S-Plot (", pw_name, ")"),
 x = "Loading (p[1])", y = "Correlation (p(corr)[1])",
 color = "Importance") +
 theme_bw(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, size =12, face = "bold"),
 legend.position = "right")
  
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_S_plot_", pw_name, ".png")),
 p_splot, width =9, height =7, dpi =300)
 ggsave(file.path(FIGURE_DIR, paste0("OPLSDA_S_plot_", pw_name, ".pdf")),
 p_splot, width =9, height =7)
 cat(" OPLSDA S-plot saved for", pw_name, "\\n")
}

# ----B5. OPLSDA Weighted Distances ----
cat("[B5] Calculating OPLSDA weighted distances...\\n")
w_opls <- c(0.6,0.4)

# Reconstruct full opls scores for distance calculation
# Use FE_vs_NC comparison as base for all samples (most comprehensive)
opls_base <- all_opls_scores[["FE_vs_NC"]]
opls_base_all <- opls_base[match(sample_meta$ID, opls_base$SampleID), ]

# But we have scores only for FE and NC samples, not CD
# Let's compute distances per pairwise comparison
opls_dist_list <- list()
for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 grps <- unique(as.character(sc$Group))
  
 cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx <- which(sc$Group == g)
 cent[g, ] <- colMeans(sc[idx, c("Comp1", "Comp2")])
 }
  
 dist_df <- data.frame(SampleID = sc$SampleID, Group = sc$Group,
 Comparison = pw_name, stringsAsFactors = FALSE)
 for (i in1:nrow(sc)) {
 g <- as.character(sc$Group[i])
 vec <- as.numeric(sc[i, c("Comp1", "Comp2")])
 dist_df$Distance[i] <- sqrt(sum(w_opls * (vec - cent[g, ])^2))
 }
 opls_dist_list[[pw_name]] <- dist_df
}
opls_dist_all <- do.call(rbind, opls_dist_list)
write.csv(opls_dist_all, file.path(OUTPUT_DIR, "oplsda_weighted_distances.csv"), row.names = FALSE)
cat(" oplda_weighted_distances.csv saved.\\n")

# ----B6. OPLSDA Permutation Test (per comparison) ----
cat("[B6] OPLSDA permutation test (n=1000 per pair)...\\n")
set.seed(42)
n_perm <-1000
opls_perm_list <- list()

for (pw_name in pairwise_names) {
 sc <- all_opls_scores[[pw_name]]
 grps <- unique(as.character(sc$Group))
  
 # Observe centroids
 cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx <- which(sc$Group == g)
 cent[g, ] <- colMeans(sc[idx, c("Comp1", "Comp2")])
 }
  
 # Observed within distance
 obs_within <- mean(sapply(1:nrow(sc), function(i) {
 g <- as.character(sc$Group[i])
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - cent[g, ])^2))
 }))
  
 # Observed between distance
 obs_between <- mean(unlist(lapply(1:nrow(sc), function(i) {
 g <- as.character(sc$Group[i])
 og <- setdiff(grps, g)
 sapply(og, function(og2) {
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - cent[og2, ])^2))
 })
 })))
 obs_ratio <- obs_within / obs_between
  
 # Permutation
 perm_ratios <- numeric(n_perm)
 for (p in1:n_perm) {
 perm_lab <- sample(sc$Group)
 perm_cent <- matrix(NA, nrow = length(grps), ncol =2,
 dimnames = list(grps, c("Comp1", "Comp2")))
 for (g in grps) {
 idx2 <- which(perm_lab == g)
 perm_cent[g, ] <- colMeans(sc[idx2, c("Comp1", "Comp2")])
 }
 pw_perm <- sapply(1:nrow(sc), function(i) {
 g <- as.character(perm_lab[i])
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - perm_cent[g, ])^2))
 })
 pb_perm <- unlist(lapply(1:nrow(sc), function(i) {
 g <- as.character(perm_lab[i])
 sapply(setdiff(grps, g), function(og2) {
 sqrt(sum(w_opls * (as.numeric(sc[i, c("Comp1", "Comp2")]) - perm_cent[og2, ])^2))
 })
 }))
 perm_ratios[p] <- mean(pw_perm) / mean(pb_perm)
 }
  
 p_val <- sum(perm_ratios <= obs_ratio) / n_perm
 cat(sprintf(" %s: ratio=%.4f, p=%.4f\\n", pw_name, obs_ratio, p_val))
  
 opls_perm_list[[pw_name]] <- data.frame(
 Comparison = pw_name,
 Observed_Ratio = obs_ratio,
 Mean_Permuted_Ratio = mean(perm_ratios),
 Perm_2.5 = quantile(perm_ratios,0.025),
 Perm_97.5 = quantile(perm_ratios,0.975),
 P_Value = p_val,
 stringsAsFactors = FALSE
 )
}

opls_perm_all <- do.call(rbind, opls_perm_list)
write.csv(opls_perm_all, file.path(OUTPUT_DIR, "oplsda_permutation_test_results.csv"), row.names = FALSE)
cat(" oplda_permutation_test_results.csv saved.\\n")

# ----B7. Summary of best pairwise comparison ----
cat("[B7] OPLSDA comparison summary...\\n")
best_q2 <- which.max(opls_params_all$Q2)
cat(sprintf(" Best OPLSDA model: %s (Q2=%.3f)\\n",
 opls_params_all$Comparison[best_q2], opls_params_all$Q2[best_q2]))
"""

# Replace PART B
old_part_b = content[content.find(part_b_marker.replace("\\n", "\n")):content.find(part_b_end.replace("\\n", "\n"))]
new_content = content.replace(old_part_b, new_part_b)

with open(r"G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R", "w") as f:
 f.write(new_content)

print("PART B replaced successfully!")
print(f"Old size: {len(content)}, New size: {len(new_content)}")
