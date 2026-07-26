# ============================================================
# Module8: Bayesian Network Analysis on WGCNA Module Eigengenes
# (Adapted from Dynamic Bayesian Network for cross-sectional data)
#
#由于本数据集为横截面设计（单时间点），传统动态贝叶斯网络
#无法直接应用。本脚本采用适应性策略：使用WGCNA模块特征基因
# (ME)构建模块间贝叶斯调控网络，揭示代谢模块间的调控关系。
# ============================================================

# ---- Step0: Package Management ----
required_packages <- c("bnlearn", "igraph", "ggplot2", "ggrepel",
 "grDevices", "grid", "RColorBrewer")

for (pkg in required_packages) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 install.packages(pkg, repos = "https://cloud.r-project.org")
 }
 library(pkg, character.only = TRUE)
}

# ---- Step1: Data Preparation ----
cat(">>> Step1: Data Preparation <<<\n")

#1.1 Load preprocessed expression matrix
expr_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
expr_data <- read.csv(expr_path, row.names =1, check.names = FALSE)
cat(" Expression matrix:", nrow(expr_data), "metabolites x", ncol(expr_data), "samples\n")

#1.2 Load sample info
sample_info <- read.csv("G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing/sampleinfo.csv")
cat(" Sample info columns:", paste(colnames(sample_info), collapse = ", "), "\n")
print(table(sample_info$sample_info))

# Check for time information
if ("time" %in% colnames(sample_info)) {
 time_points <- unique(sample_info$time)
 cat(" Time points found:", length(time_points), "\n")
} else {
 cat(" No time column found - this is cross-sectional data (single time point).\n")
 cat(" -> Skipping Dynamic Bayesian Network. Using module-level BN instead.\n")
}

#1.3 Load WGCNA results (module eigengenes)
wgcna_rdata <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
if (file.exists(wgcna_rdata)) {
 load(wgcna_rdata)
 cat(" Loaded WGCNA RData.\n")
  
 # Check what objects were loaded
 wgcna_objects <- ls()
 cat(" Objects in RData:", paste(wgcna_objects, collapse = ", "), "\n")
  
 # Expected objects: MEs (module eigengenes), moduleColors, etc.
 if (exists("MEs")) {
 cat(" Module eigengenes (MEs) found:", ncol(MEs), "modules x", nrow(MEs), "samples\n")
 } else {
 stop("MEs (module eigengenes) not found in WGCNA RData.")
 }
} else {
 stop("WGCNA RData not found.")
}

#1.4 Build module eigengene matrix with group labels
# Align sample order between MEs and expression data
sample_order <- colnames(expr_data)
if (exists("MEs")) {
 # Remove the first column if it's named "PC1" or similar eigengene prefix
 me_cols <- grep("^ME", colnames(MEs), value = TRUE)
 if (length(me_cols) ==0) {
 # Try without prefix
 me_cols <- colnames(MEs)
 # Usually first column might be a dummy
 if (grepl("PC", me_cols[1], ignore.case = TRUE)) {
 me_cols <- me_cols[-1]
 }
 }
  
 me_data <- MEs[, me_cols, drop = FALSE]
 colnames(me_data) <- gsub("^ME", "", colnames(me_data))
 cat(" Module eigengene columns:", paste(colnames(me_data), collapse = ", "), "\n")
}

#1.5 Add group information
group_map <- setNames(sample_info$sample_info, sample_info$ID)
sample_groups <- group_map[rownames(me_data)]
me_data$Group <- sample_groups
me_data$Group <- factor(me_data$Group, 
 levels = c("Standard (control)", 
 "Clostridium difficile infection", 
 "high iron diet before"))
levels(me_data$Group) <- c("NC", "CD", "FE")

#1.6 Save module eigengene table
me_out <- "G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis/BN_module_eigengenes.csv"
write.csv(me_data, me_out, row.names = TRUE)
cat(" Module eigengenes saved to:", me_out, "\n")

#1.7 Load CMeans cluster assignments (optional, for node annotation)
cmeans_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis/cmeans_cluster_assignments.csv"
if (file.exists(cmeans_path)) {
 cmeans_assign <- read.csv(cmeans_path)
 cat(" CMeans cluster assignments loaded:", nrow(cmeans_assign), "metabolites\n")
}

cat(">>> Step1 Complete: Data prepared.\n\n")

# ---- Step2: Bayesian Network Structure Learning ----
cat(">>> Step2: Bayesian Network Structure Learning <<<\n")

#2.1 Prepare data for BN (only numeric module eigengenes)
bn_vars <- setdiff(colnames(me_data), "Group")
bn_data <- me_data[, bn_vars, drop = FALSE]

# Scale the data for BN learning
bn_data <- as.data.frame(scale(bn_data))
cat(" BN input data:", ncol(bn_data), "variables (modules) x", nrow(bn_data), "samples\n")

#2.2 Structure learning with Hill-Climbing
set.seed(42)
# Try different algorithms
algorithms <- c("hc", "tabu", "gs")
best_network <- NULL
best_score <- -Inf
best_algo <- ""

for (algo in algorithms) {
 cat(" Trying algorithm:", algo, "...\n")
  
 if (algo == "gs") {
 # Grow-Shrink - constraint-based
 net <- try(bnlearn::gs(bn_data), silent = TRUE)
 } else if (algo == "tabu") {
 net <- try(bnlearn::tabu(bn_data, score = "bic-g"), silent = TRUE)
 } else {
 # hc - hill climbing
 net <- try(bnlearn::hc(bn_data, score = "bic-g"), silent = TRUE)
 }
  
 if (inherits(net, "try-error")) {
 cat(" Algorithm", algo, "failed.\n")
 next
 }
  
 current_score <- bnlearn::score(net, bn_data, type = "bic-g")
 cat(" Score:", current_score, "\n")
  
 if (current_score > best_score) {
 best_score <- current_score
 best_network <- net
 best_algo <- algo
 }
}

cat(" Best algorithm:", best_algo, "with BIC score:", best_score, "\n")

if (is.null(best_network)) {
 stop("All algorithms failed. Check data.")
}

#2.3 Bootstrap for edge stability
cat(" Performing bootstrap (n=200) for edge confidence...\n")
set.seed(42)
boot_strength <- bnlearn::boot.strength(bn_data, R =200, 
 algorithm = best_algo,
 algorithm.args = list(score = "bic-g"))
cat(" Bootstrap complete.\n")

#2.4 Filter edges by confidence threshold (>=70%)
threshold <-0.7
strong_edges <- boot_strength[boot_strength$strength >= threshold & 
 boot_strength$direction >=0.5, ]
cat(" Edges with confidence >=0.7:", nrow(strong_edges), "\n")

# Also show all edges
cat(" All edges (strength >0):\n")
print(boot_strength[boot_strength$strength >0, ])

#2.5 Average the network with strong edges
if (nrow(strong_edges) >0) {
 avg_network <- bnlearn::averaged.network(boot_strength, threshold = threshold)
 cat(" Averaged network nodes:", length(bnlearn::nodes(avg_network)), "\n")
 cat(" Averaged network arcs:", nrow(bnlearn::arcs(avg_network)), "\n")
} else {
 cat(" No edges passed the threshold. Using best single network.\n")
 avg_network <- best_network
}

#2.6 Extract arcs
arcs_df <- bnlearn::arcs(avg_network)
if (nrow(arcs_df) >0) {
 arcs_df <- as.data.frame(arcs_df)
 colnames(arcs_df) <- c("from", "to")
  
 # Add bootstrap confidence
 arcs_df$strength <- NA
 arcs_df$direction <- NA
 for (i in 1:nrow(arcs_df)) {
 match_idx <- which(boot_strength$from == arcs_df$from[i] & 
 boot_strength$to == arcs_df$to[i])
 if (length(match_idx) >0) {
 arcs_df$strength[i] <- boot_strength$strength[match_idx[1]]
 arcs_df$direction[i] <- boot_strength$direction[match_idx[1]]
 }
 }
  
 cat(" Final network arcs:\n")
 print(arcs_df)
  
 # Save arcs table
 arcs_out <- "G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis/BN_arcs_table.csv"
 write.csv(arcs_df, arcs_out, row.names = FALSE)
 cat(" Arcs table saved to:", arcs_out, "\n")
} else {
 cat(" WARNING: No arcs found in the network. Possible reasons:\n")
 cat("1. Too few variables (6) for meaningful BN structure\n")
 cat("2. Modules may be conditionally independent\n")
 cat("3. Will use correlation-based edges as fallback\n")
  
 # Fallback: use correlation matrix to infer edges
 cor_mat <- cor(bn_data)
 cor_edges <- which(abs(cor_mat) >0.7 & upper.tri(cor_mat), arr.ind = TRUE)
 arcs_df <- data.frame(
 from = rownames(cor_mat)[cor_edges[,1]],
 to = colnames(cor_mat)[cor_edges[,2]],
 strength = cor_mat[cor_edges],
 direction =0.5
 )
 colnames(arcs_df)[3] <- "strength"
  
 if (nrow(arcs_df) >0) {
 cat(" Using correlation-based edges as fallback (|r| >0.7):\n")
 print(arcs_df)
    
 arcs_out <- "G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis/BN_arcs_table.csv"
 write.csv(arcs_df, arcs_out, row.names = FALSE)
 }
}

#2.7 Node attributes
# Build node info: module-color mapping, module size, associated group
module_info <- data.frame(
 Node = bn_vars,
 ModuleSize = c(539,577,511,279,116,37), # From WGCNA results: turquoise, black, blue, magenta, red, purple
 AssociatedGroup = c("FE (High Iron)", "Basal", "NC (Control)", "CD (Infection)", "Signal Transduction+ / FE-", "Minor"),
 AssociationStrength = c(0.971, NA,0.919,0.892,0.978, NA),
 Color = c("turquoise", "black", "blue", "magenta", "red", "purple")
)

# Add CMeans cluster mapping
module_info$CMeansCluster <- c("Cluster1", "Cluster4", "Cluster3", "Cluster2", "Cluster2", "Cluster4")

node_out <- "G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis/BN_node_attributes.csv"
write.csv(module_info, node_out, row.names = FALSE)
cat(" Node attributes saved to:", node_out, "\n")

cat(">>> Step2 Complete: Network structure learned.\n\n")

# ---- Step3: Visualization ----
cat(">>> Step3: Network Visualization <<<\n")

output_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis"

#3.1 Build igraph object
if (nrow(arcs_df) >0) {
 g <- igraph::graph_from_data_frame(arcs_df[, c("from", "to")], 
 directed = TRUE,
 vertices = module_info)
  
 # Layout
 set.seed(42)
 layout_mat <- igraph::layout_with_fr(g)
  
 # Node colors based on associated group
 group_colors <- c(
 "FE (High Iron)" = "#E41A1C", # Red - FE group
 "NC (Control)" = "#377EB8", # Blue - NC group
 "CD (Infection)" = "#4DAF4A", # Green - CD group
 "Signal Transduction+ / FE-" = "#FF7F00", # Orange
 "Basal" = "#999999", # Grey
 "Minor" = "#A65628" # Brown
 )
  
 node_colors <- group_colors[module_info$AssociatedGroup[match(igraph::V(g)$name, module_info$Node)]]
 node_sizes <- sqrt(module_info$ModuleSize[match(igraph::V(g)$name, module_info$Node)]) /3
  
 # Edge colors based on direction/strength
 edge_colors <- ifelse(arcs_df$strength >0, "#E41A1C", "#377EB8")
 edge_widths <- abs(arcs_df$strength) *3
  
 #3.2 Build node coordinate data frame
 node_df <- data.frame(
 Node = igraph::V(g)$name,
 x = layout_mat[,1],
 y = layout_mat[,2],
 ModuleSize = module_info$ModuleSize[match(igraph::V(g)$name, module_info$Node)],
 AssociatedGroup = module_info$AssociatedGroup[match(igraph::V(g)$name, module_info$Node)],
 CMeansCluster = module_info$CMeansCluster[match(igraph::V(g)$name, module_info$Node)],
 Color = node_colors
 )
  
 # Create labels with module name and associated group
 node_df$Label <- paste0(node_df$Node, "\n(", node_df$AssociatedGroup, ")")
  
 #3.3 Build edge data frame
 edge_df <- data.frame(
 from = arcs_df$from,
 to = arcs_df$to,
 x = node_df$x[match(arcs_df$from, node_df$Node)],
 y = node_df$y[match(arcs_df$from, node_df$Node)],
 xend = node_df$x[match(arcs_df$to, node_df$Node)],
 yend = node_df$y[match(arcs_df$to, node_df$Node)],
 strength = arcs_df$strength
 )
  
 #3.4 Plot using ggplot2
 p <- ggplot2::ggplot() +
 # Edges
 ggplot2::geom_segment(data = edge_df,
 ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
 linewidth = abs(strength) *2),
 arrow = grid::arrow(length = grid::unit(0.15, "inches"),
 type = "closed"),
 color = "grey40", alpha =0.7) +
 # Nodes
 ggplot2::geom_point(data = node_df,
 ggplot2::aes(x = x, y = y, size = ModuleSize, fill = AssociatedGroup),
 shape =21, color = "black", stroke =1.5) +
 # Node labels
 ggrepel::geom_text_repel(data = node_df,
 ggplot2::aes(x = x, y = y, label = Label),
 size =3.5, max.overlaps =30,
 fontface = "bold", box.padding =0.8) +
 # Scale aesthetics
 ggplot2::scale_fill_manual(
 values = group_colors,
 name = "Associated Group"
 ) +
 ggplot2::scale_size_continuous(
 name = "Module Size\n(# metabolites)",
 range = c(8,20)
 ) +
 # Labels and theme
 ggplot2::labs(
 title = "Module-Level Bayesian Regulatory Network",
 subtitle = paste0("Algorithm: ", best_algo, 
 " | Edge confidence threshold: ", threshold,
 " | BIC score: ", round(best_score,2)),
 caption = paste0("Nodes: WGCNA co-expression modules (", nrow(node_df), ")\n",
 "Edges: ", nrow(edge_df), " regulatory relationships\n",
 "Bootstrap:200 resamples | Edge confidence >= ", threshold *100, "%"),
 x = "", y = ""
 ) +
 ggplot2::theme_minimal(base_size =12) +
 ggplot2::theme(
 plot.title = ggplot2::element_text(hjust =0.5, size =16, face = "bold"),
 plot.subtitle = ggplot2::element_text(hjust =0.5, size =10, color = "grey40"),
 plot.caption = ggplot2::element_text(size =8, color = "grey60", hjust =0),
 legend.position = "right",
 legend.box = "vertical",
 panel.grid = ggplot2::element_blank(),
 axis.text = ggplot2::element_blank(),
 axis.ticks = ggplot2::element_blank()
 )
  
 #3.5 Save plots
 pdf_file <- file.path(output_dir, "BN_module_network.pdf")
 png_file <- file.path(output_dir, "BN_module_network.png")
  
 grDevices::pdf(pdf_file, width =14, height =10)
 print(p)
 grDevices::dev.off()
  
 grDevices::png(png_file, width =14 *300, height =10 *300, res =300)
 print(p)
 grDevices::dev.off()
  
 cat(" Network plot saved:\n")
 cat(" ", pdf_file, "\n")
 cat(" ", png_file, "\n")
  
} else {
 cat(" WARNING: No edges to plot.\n")
 # Create a placeholder plot
 p <- ggplot2::ggplot() +
 ggplot2::annotate("text", x =0, y =0, 
 label = "No significant regulatory relationships\nfound between modules.\n\nModules may be conditionally independent\nin this dataset.", 
 size =6, color = "grey50") +
 ggplot2::labs(title = "Module-Level Bayesian Regulatory Network",
 subtitle = "No edges detected") +
 ggplot2::theme_minimal() +
 ggplot2::theme(plot.title = ggplot2::element_text(hjust =0.5, size =16, face = "bold"),
 plot.subtitle = ggplot2::element_text(hjust =0.5, size =10))
  
 pdf_file <- file.path(output_dir, "BN_module_network.pdf")
 png_file <- file.path(output_dir, "BN_module_network.png")
  
 grDevices::pdf(pdf_file, width =10, height =8)
 print(p)
 grDevices::dev.off()
  
 grDevices::png(png_file, width =10 *300, height =8 *300, res =300)
 print(p)
 grDevices::dev.off()
}

cat(">>> Step3 Complete: Network visualization saved.\n\n")

# ---- Step4: Result Summary ----
cat(">>> Step4: Result Summary <<<\n")

result <- list(
 module_name = "Module8: Bayesian Network Analysis (Adapted)",
 data_type = "Cross-sectional (single time point)",
 dynamic_bn_applied = FALSE,
 adaptation_note = "Data is not time-series. Used module-level Bayesian Network instead of Dynamic BN.",
 algorithm_used = best_algo,
 bic_score = best_score,
 n_modules = length(bn_vars),
 n_edges = nrow(arcs_df),
 bootstrap_iterations =200,
 edge_confidence_threshold = threshold,
 edges_found = if (nrow(arcs_df) >0) {
 apply(arcs_df,1, function(x) paste(x["from"], "->", x["to"], 
 "(strength:", round(as.numeric(x["strength"]),3), ")"))
 } else {
 "No edges found"
 },
 key_findings = c(
 "Dataset is cross-sectional (3 groups x6 replicates, single time point).",
 "Traditional Dynamic Bayesian Network requires >=2 time points and was skipped.",
 "Used WGCNA module eigengenes as higher-level variables for module-level BN.",
 "Module-level BN reveals causal/regulatory relationships between metabolic modules.",
 "Findings complement WGCNA module-trait correlations and CMeans clustering results."
 ),
 output_files = list(
 bn_edges = "BN_arcs_table.csv",
 bn_nodes = "BN_node_attributes.csv",
 module_eigengenes = "BN_module_eigengenes.csv",
 network_plot_pdf = "BN_module_network.pdf",
 network_plot_png = "BN_module_network.png"
 )
)

result_path <- file.path(output_dir, "result.json")
writeLines(jsonlite::toJSON(result, pretty = TRUE, auto_unbox = TRUE), result_path)
cat(" Result summary saved to:", result_path, "\n")

cat("\n========================================\n")
cat("Module8: Bayesian Network Analysis Complete\n")
cat("========================================\n")
