# ----2b. Membership heatmap ----
cat(" Generating membership heatmap...\n")
ord <- order(cluster_labels, -apply(membership_mat,1, max))
mo <- membership_mat[ord, , drop = FALSE] # n_metabolites x n_clusters

# Column annotation (for columns of t(mo) = metabolites): cluster assignment
# t(mo) has n_metabolites columns, so we need n_metabolites annotation values
col_cluster <- factor(cluster_labels[ord], levels = seq_len(actual_k))
names(col_cluster) <- rownames(mo)

# Row annotation (for rows of t(mo) = clusters): cluster names
row_cluster <- paste0("C", seq_len(actual_k))

cc <- setNames(brewer.pal(max(actual_k,3), "Set2")[seq_len(actual_k)],
 as.character(seq_len(actual_k)))
mcf <- circlize::colorRamp2(c(0,0.5,1), c("white", "orange", "darkred"))

# Column annotation (metabolite cluster)
ha_col <- HeatmapAnnotation(
 Cluster = col_cluster,
 col = list(Cluster = cc),
 show_annotation_name = FALSE
)

# Row annotation (cluster names)
ha_row <- rowAnnotation(
 Cluster = row_cluster,
 col = list(Cluster = cc),
 show_annotation_name = TRUE,
 annotation_label = "CMeans"
)

pdf(file.path(fig_dir, "CMeans_membership_heatmap.pdf"),
 width =12, height = max(4, actual_k *1.2))
ht <- Heatmap(t(mo), name = "Membership", col = mcf,
 top_annotation = ha_col,
 left_annotation = ha_row,
 show_row_names = TRUE,
 show_column_names = FALSE,
 row_names_gp = gpar(fontsize =10, fontface = "bold"),
 cluster_rows = TRUE,
 cluster_columns = FALSE,
 column_split = col_cluster,
 column_title_gp = gpar(fontsize =9),
 heatmap_legend_param = list(direction = "vertical"))
draw(ht)
dev.off()

png(file.path(fig_dir, "CMeans_membership_heatmap.png"),
 width =3600, height = max(1200, actual_k *360), res =300)
draw(ht)
dev.off()
cat(" Membership heatmap saved.\n")
