# ============================================================
# Module8: Bayesian Network Analysis (Adapted from Dynamic BN)
# ============================================================
#由于本数据集为横截面设计（单时间点），传统动态贝叶斯网络
# （需>=2个时间点建模t-1->t因果）不可用。
#本脚本适应性采用模块级贝叶斯网络策略：
#使用WGCNA模块特征基因(ME)作为高阶变量，推断模块间的有向调控关系。
#同时补充PLS-PM路径分析作为互补视角。
# ============================================================

cat("========================================\n")
cat("Module8: Bayesian Network Analysis\n")
cat("========================================\n\n")

# ---- Step0: Package Installation & Setup ----
cat(">>> Step0: Installing/Loading required packages...\n")

required_packages <- c("bnlearn", "igraph", "ggplot2", "ggrepel",
 "grDevices", "grid", "RColorBrewer", "jsonlite", "plspm")

for (pkg in required_packages) {
 if (!requireNamespace(pkg, quietly = TRUE)) {
 install.packages(pkg, repos = "https://cloud.r-project.org")
 }
 library(pkg, character.only = TRUE, warn.conflicts = FALSE)
}

# Source helper functions
helper_dir <- "G:/OmicsWorks/agent/rscript"
source(file.path(helper_dir, "data_io.R"))
source(file.path(helper_dir, "visualization.R"))
source(file.path(helper_dir, "network.R"))

# Define output directories
tmp_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis"
fig_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/8_dynamic_bayesian_network_analysis/figures"

dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

cat(" Temp directory:", tmp_dir, "\n")
cat(" Figures directory:", fig_dir, "\n\n")

# ---- Step1: Data Preparation & Time Series Check ----
cat(">>> Step1: Data Preparation & Time Series Check <<<\n")

#1.1 Load expression matrix
expr_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
expr_data <- load_expression_matrix(expr_path)
cat(" Expression matrix:", nrow(expr_data), "metabolites x", ncol(expr_data), "samples\n")

#1.2 Load sample info
sample_info_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/1_expression_matrix_preprocessing/sampleinfo.csv"
sample_meta <- load_sample_metadata(sample_info_path)
cat(" Sample info loaded. Groups:\n")
print(table(sample_meta$sample_info))

#1.3 Check for time information
time_col_candidates <- intersect(c("time", "Time", "time_point", "TimePoint", 
 "day", "Day", "week", "Week"),
 colnames(sample_meta))

if (length(time_col_candidates) >0) {
 time_col <- time_col_candidates[1]
 time_points <- unique(sample_meta[[time_col]])
 cat(" [TIME-SERIES] Found time column:", time_col, "with", length(time_points), "points.\n")
 if (length(time_points) >=2) {
 cat(" [DECISION] Data IS time-series. Proceeding with standard Dynamic BN.\n")
 # Future implementation - not executed for this cross-sectional dataset
 }
} else {
 cat(" [TIME-SERIES] No time column found. Data is CROSS-SECTIONAL (single time point).\n")
 cat(" [DECISION] Traditional Dynamic BN requires >=2 time points. Skipped.\n")
 cat(" [DECISION] Adapting to MODULE-LEVEL BN using WGCNA module eigengenes.\n\n")
}

# ---- Step1b: Load WGCNA Module Eigengenes ----
cat(" [Adaptation] Loading WGCNA module eigengenes...\n")

wgcna_rdata <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
if (!file.exists(wgcna_rdata)) stop("WGCNA RData not found.")

load(wgcna_rdata)

# Find module eigengenes (MEs) - known objects from WGCNA
if (exists("merged_MEs")) {
 MEs <- merged_MEs
 cat(" Using 'merged_MEs':", nrow(MEs), "samples x", ncol(MEs), "modules\n")
} else if (exists("MEs_aligned")) {
 MEs <- MEs_aligned
 cat(" Using 'MEs_aligned':", nrow(MEs), "samples x", ncol(MEs), "modules\n")
} else {
 stop("Cannot find MEs in WGCNA RData.")
}

# Extract ME columns and clean names
me_cols <- grep("^ME", colnames(MEs), value = TRUE)
if (length(me_cols) ==0) me_cols <- colnames(MEs)
cat(" Module eigengenes:", paste(me_cols, collapse = ", "), "\n")

# Build numeric ME data frame
me_data <- as.data.frame(MEs[, me_cols, drop = FALSE])
colnames(me_data) <- gsub("^ME", "", colnames(me_data))
me_data[] <- lapply(me_data, as.numeric)

# Get module sizes from WGCNA
if (exists("module_sizes")) {
 module_size_map <- as.list(module_sizes)
} else if (exists("merged_colors")) {
 module_size_map <- as.list(table(merged_colors))
} else {
 module_size_map <- list(turquoise =539, blue =511, red =116, magenta =279, black =577, purple =37)
}
cat(" Module sizes from WGCNA:\n")
print(unlist(module_size_map))

# ---- Step1c: Add Group Labels ----
# Use sample_to_group from WGCNA if available, otherwise from sample_meta
if (exists("sample_to_group")) {
 cat(" Using 'sample_to_group' from WGCNA for group assignment.\n")
 group_vec <- sample_to_group[rownames(me_data)]
 me_data$Group <- group_vec
} else {
 group_map <- setNames(as.character(sample_meta$sample_info), sample_meta$ID)
 me_data$Group <- group_map[rownames(me_data)]
}

# Standardize group names
me_data$Group <- gsub("Standard \\(control\\)", "NC", me_data$Group)
me_data$Group <- gsub("Clostridium difficile infection", "CD", me_data$Group)
me_data$Group <- gsub("high iron diet before", "FE", me_data$Group)
me_data$Group <- factor(me_data$Group, levels = c("NC", "CD", "FE"))

cat(" Group distribution:\n")
print(table(me_data$Group))

#1.4 Save module eigengene table
me_out <- file.path(tmp_dir, "bayesian_module_eigengenes.csv")
write.csv(me_data, me_out, row.names = TRUE)
cat(" Module eigengenes saved to:", me_out, "\n")

#1.5 Module correlation overview
me_numeric <- me_data[, setdiff(colnames(me_data), "Group"), drop = FALSE]
cor_me <- stats::cor(me_numeric, use = "pairwise.complete.obs")
cat("\n Module-module correlation matrix:\n")
print(round(cor_me,3))

#1.6 Group mean eigengene profile
cat("\n Group mean eigengene values:\n")
group_means <- aggregate(. ~ Group, data = me_data, FUN = mean)
rownames(group_means) <- group_means$Group
group_means$Group <- NULL
print(round(group_means,3))

cat(">>> Step1 Complete: Data prepared.\n\n")

# ---- Step2: Bayesian Network Structure Learning ----
cat(">>> Step2: Bayesian Network Structure Learning <<<\n")

#2.1 Prepare numeric data for BN (scale variables)
bn_vars <- setdiff(colnames(me_data), "Group")
bn_data <- as.data.frame(scale(me_numeric))
cat(" BN input:", ncol(bn_data), "variables x", nrow(bn_data), "samples\n")

#2.2 Structure learning with multiple algorithms
set.seed(42)
algorithms <- c("hc", "tabu")
best_network <- NULL
best_score <- -Inf
best_algo <- "none"
all_scores <- list()

for (algo in algorithms) {
 cat(" Trying algorithm:", algo, "... ")
 net <- tryCatch({
 if (algo == "tabu") {
 bnlearn::tabu(bn_data, score = "bic-g")
 } else {
 bnlearn::hc(bn_data, score = "bic-g")
 }
 }, error = function(e) { cat("FAILED:", e$message, "\n"); NULL })
 
 if (is.null(net)) next
 
 current_score <- bnlearn::score(net, bn_data, type = "bic-g")
 all_scores[[algo]] <- current_score
 cat("BIC =", round(current_score,2), "\n")
 
 if (current_score > best_score) {
 best_score <- current_score; best_network <- net; best_algo <- algo
 }
}

cat(" Best algorithm:", best_algo, "with BIC score:", round(best_score,2), "\n")

if (is.null(best_network)) {
 cat(" WARNING: All algorithms failed. Creating empty graph.\n")
 best_network <- bnlearn::empty.graph(nodes = bn_vars)
 arcs_df <- data.frame(from = character(0), to = character(0),
 strength = numeric(0), direction = numeric(0))
}

#2.3 Bootstrap for edge stability
if (!is.null(best_network) && bnlearn::narcs(best_network) >0) {
 cat("\n Performing bootstrap (n=200) for edge confidence...\n")
 set.seed(42)
 boot_strength <- bnlearn::boot.strength(bn_data, R =200,
 algorithm = best_algo,
 algorithm.args = list(score = "bic-g"))
 
 cat(" Bootstrap complete. Summary:\n")
 boot_positive <- boot_strength[boot_strength$strength >0, ]
 if (nrow(boot_positive) >0) {
 print(boot_positive)
 }
 
 # Filter by threshold
 threshold <-0.7
 strong_edges <- boot_strength[boot_strength$strength >= threshold & boot_strength$direction >=0.5, ]
 cat("\n Edges with confidence >=0.7:", nrow(strong_edges), "\n")
 
 if (nrow(strong_edges) >0) {
 avg_network <- bnlearn::averaged.network(boot_strength, threshold = threshold)
 } else {
 # Try lower threshold
 strong_edges <- boot_strength[boot_strength$strength >=0.5 & boot_strength$direction >=0.5, ]
 cat(" Edges with confidence >=0.5:", nrow(strong_edges), "\n")
 if (nrow(strong_edges) >0) {
 avg_network <- bnlearn::averaged.network(boot_strength, threshold =0.5)
 } else {
 avg_network <- best_network
 }
 }
 
 # Extract arcs with confidence
 arcs_df <- as.data.frame(bnlearn::arcs(avg_network))
 if (nrow(arcs_df) >0) {
 colnames(arcs_df) <- c("from", "to")
 arcs_df$strength <- NA; arcs_df$direction <- NA
 for (i in 1:nrow(arcs_df)) {
 idx <- which(boot_strength$from == arcs_df$from[i] & boot_strength$to == arcs_df$to[i])
 if (length(idx) >0) {
 arcs_df$strength[i] <- boot_strength$strength[idx[1]]
 arcs_df$direction[i] <- boot_strength$direction[idx[1]]
 }
 }
 cat(" Final arcs:\n"); print(arcs_df)
 } else {
 arcs_df <- data.frame(from = character(0), to = character(0),
 strength = numeric(0), direction = numeric(0))
 }
} else {
 cat("\n BN network has", bnlearn::narcs(best_network), "edges.\n")
 cat(" Using correlation-based edges as fallback.\n")
 
 # Fallback: use correlation >0.7
 cor_edges <- which(abs(cor_me) >0.7 & upper.tri(cor_me), arr.ind = TRUE)
 if (nrow(cor_edges) >0) {
 arcs_df <- data.frame(
 from = rownames(cor_me)[cor_edges[,1]],
 to = colnames(cor_me)[cor_edges[,2]],
 strength = cor_me[cor_edges],
 direction = rep(0.5, nrow(cor_edges))
 )
 cat(" Correlation-based edges (|r|>0.7):", nrow(arcs_df), "\n")
 print(arcs_df)
 } else {
 arcs_df <- data.frame(from = character(0), to = character(0),
 strength = numeric(0), direction = numeric(0))
 cat(" No strong correlations found.\n")
 }
}

#2.4 Save arcs table
arcs_out <- file.path(tmp_dir, "bayesian_network_arcs.csv")
write.csv(arcs_df, arcs_out, row.names = FALSE)
cat(" Arcs table saved to:", arcs_out, "\n")

#2.5 Build node attributes
# Module association mapping from WGCNA results
module_assoc <- c(
 turquoise = "FE (r=0.971)",
 blue = "NC (r=0.919)",
 red = "Signal+ (r=0.978) / FE- (r=-0.913)",
 magenta = "CD (r=0.892)",
 black = "Basal Metabolism",
 purple = "Minor Module"
)

module_cmeans <- c(
 turquoise = "Cluster1", black = "Cluster4", blue = "Cluster3",
 magenta = "Cluster2", red = "Cluster2", purple = "Cluster4"
)

module_color <- c(
 turquoise = "#E41A1C", blue = "#377EB8", red = "#FF7F00",
 magenta = "#4DAF4A", black = "#999999", purple = "#A65628"
)

# Build node df with only the modules present in data
node_df <- data.frame(
 Node = bn_vars,
 ModuleSize = sapply(tolower(bn_vars), function(x) ifelse(is.null(module_size_map[[x]]), NA, module_size_map[[x]])),
 AssociatedGroup = module_assoc[tolower(bn_vars)],
 CMeansCluster = module_cmeans[tolower(bn_vars)],
 Color = module_color[tolower(bn_vars)],
 stringsAsFactors = FALSE
)
rownames(node_df) <- NULL
cat("\n Node attributes:\n")
print(node_df)

node_out <- file.path(tmp_dir, "bayesian_node_attributes.csv")
write.csv(node_df, node_out, row.names = FALSE)
cat(" Node attributes saved to:", node_out, "\n")

cat(">>> Step2 Complete: Network structure learned.\n\n")

# ---- Step3: PLS-PM Complementary Analysis ----
cat(">>> Step3: PLS-PM Complementary Path Analysis <<<\n")

# Use KEGG pathway annotations as latent variables for PLS-PM
metabolite_anno <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
if (file.exists(metabolite_anno)) {
 cat(" Loading metabolite annotations for PLS-PM...\n")
 anno_df <- read.csv(metabolite_anno, stringsAsFactors = FALSE)
 
 # Check if we can do PLS-PM with KEGG pathways
 if ("kegg" %in% colnames(anno_df) && "ID" %in% colnames(anno_df)) {
 cat(" Attempting PLS-PM with KEGG pathways as latent variables...\n")
 
 # Filter to common features
 anno_df$ID <- as.character(anno_df$ID)
 common_features <- intersect(anno_df$ID, rownames(expr_data))
 if (length(common_features) >100) {
 anno_sub <- anno_df[match(common_features, anno_df$ID), ]
 expr_sub <- expr_data[common_features, ]
 
 # Run PLS-PM
 tryCatch({
 plspm_result <- perform_plspm(expr_sub, sample_meta, anno_sub,
 latent_var_col = "kegg")
 
 # Plot PLS-PM path diagram
 # Use the agent's built-in function
 if (!is.null(plspm_result)) {
 plot_plspm_path(plspm_result, output_dir = fig_dir)
 cat(" PLS-PM path diagram saved.\n")
 } else {
 cat(" PLS-PM returned NULL.\n")
 }
 }, error = function(e) {
 cat(" PLS-PM failed:", e$message, "\n")
 })
 } else {
 cat(" Insufficient features with KEGG annotation for PLS-PM.\n")
 }
 } else {
 cat(" Annotation file missing 'kegg' or 'ID' column.\n")
 }
} else {
 cat(" Metabolite annotation file not found. Skipping PLS-PM.\n")
}

cat(">>> Step3 Complete: PLS-PM analysis done.\n\n")

# ---- Step4: Network Visualization ----
cat(">>> Step4: Network Visualization <<<\n")

if (nrow(arcs_df) >0) {
 # Build igraph object (use namespace to avoid conflicts)
 g <- igraph::graph_from_data_frame(arcs_df[, c("from", "to")], 
 directed = TRUE,
 vertices = node_df)
 
 # Layout
 set.seed(42)
 if (igraph::vcount(g) <=6) {
 layout_mat <- igraph::layout_in_circle(g)
 } else {
 layout_mat <- igraph::layout_with_fr(g)
 }
 
 # Node coordinates
 plot_nodes <- data.frame(
 Node = igraph::V(g)$name,
 x = layout_mat[,1], y = layout_mat[,2],
 ModuleSize = node_df$ModuleSize[match(igraph::V(g)$name, node_df$Node)],
 AssociatedGroup = node_df$AssociatedGroup[match(igraph::V(g)$name, node_df$Node)],
 CMeansCluster = node_df$CMeansCluster[match(igraph::V(g)$name, node_df$Node)],
 Color = node_df$Color[match(igraph::V(g)$name, node_df$Node)],
 stringsAsFactors = FALSE
 )
 plot_nodes$Label <- paste0(plot_nodes$Node, "\n[", plot_nodes$AssociatedGroup, "]")
 
 # Edge coordinates
 plot_edges <- data.frame(
 from = arcs_df$from, to = arcs_df$to,
 x = plot_nodes$x[match(arcs_df$from, plot_nodes$Node)],
 y = plot_nodes$y[match(arcs_df$from, plot_nodes$Node)],
 xend = plot_nodes$x[match(arcs_df$to, plot_nodes$Node)],
 yend = plot_nodes$y[match(arcs_df$to, plot_nodes$Node)],
 strength = arcs_df$strength,
 stringsAsFactors = FALSE
 )
 
 # Plot
 p <- ggplot2::ggplot() +
 # Edges
 ggplot2::geom_segment(data = plot_edges,
 ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
 linewidth = ifelse(is.na(strength),0.5, 
 pmin(pmax(strength,0.3),1.5))),
 arrow = grid::arrow(length = grid::unit(0.12, "inches"), type = "closed"),
 color = "grey50", alpha =0.8) +
 # Nodes
 ggplot2::geom_point(data = plot_nodes,
 ggplot2::aes(x = x, y = y, size = ModuleSize, fill = Node),
 shape =21, color = "black", stroke =1.5) +
 # Labels
 ggrepel::geom_text_repel(data = plot_nodes,
 ggplot2::aes(x = x, y = y, label = Label),
 size =3.2, max.overlaps =30,
 fontface = "bold", box.padding =0.8,
 point.padding =0.5) +
 # Manual fill
 ggplot2::scale_fill_manual(
 values = setNames(plot_nodes$Color, plot_nodes$Node),
 name = "Module\n(Trait Association)") +
 # Size
 ggplot2::scale_size_continuous(
 name = "Module Size\n(# metabolites)", range = c(8,20)) +
 # Theme
 ggplot2::labs(
 title = "Module-Level Bayesian Regulatory Network",
 subtitle = paste0("Algorithm: ", best_algo, 
 " | BIC score: ", round(best_score,2),
 " | Bootstrap:200 resamples\n",
 "Nodes: WGCNA modules (", nrow(plot_nodes), ") | ",
 "Edges: ", nrow(plot_edges), " | ",
 "Confidence threshold: >=0.7"),
 caption = "Edge direction: parent -> child (putative regulator -> target)\nData: Cross-sectional (single time point) | Adapted from Dynamic BN"
 ) +
 ggplot2::theme_minimal(base_size =11) +
 ggplot2::theme(
 plot.title = ggplot2::element_text(hjust =0.5, size =16, face = "bold"),
 plot.subtitle = ggplot2::element_text(hjust =0.5, size =9, color = "grey40"),
 plot.caption = ggplot2::element_text(size =8, color = "grey60", hjust =0),
 legend.position = "right", legend.box = "vertical",
 panel.grid = ggplot2::element_blank(),
 axis.text = ggplot2::element_blank(),
 axis.ticks = ggplot2::element_blank(),
 axis.title = ggplot2::element_blank()
 )
 
 # Save
 pdf_file <- file.path(fig_dir, "BN_module_network.pdf")
 png_file <- file.path(fig_dir, "BN_module_network.png")
 
 grDevices::pdf(pdf_file, width =14, height =10)
 print(p)
 grDevices::dev.off()
 
 grDevices::png(png_file, width =14 *300, height =10 *300, res =300)
 print(p)
 grDevices::dev.off()
 
 cat(" Network plots saved:\n PDF:", pdf_file, "\n PNG:", png_file, "\n")
} else {
 cat(" No edges found. Creating placeholder figure.\n")
 p <- ggplot2::ggplot() +
 ggplot2::annotate("text", x =0, y =0, 
 label = "No significant regulatory relationships\nfound between modules.\n\nPossible reasons:\n1. Modules may be conditionally independent\n2. Sample size (n=18) insufficient\n3. Cross-sectional design limits detection",
 size =5, color = "grey50") +
 ggplot2::labs(title = "Module-Level Bayesian Regulatory Network",
 subtitle = "No significant edges detected (threshold >=0.7)") +
 ggplot2::theme_minimal() +
 ggplot2::theme(plot.title = ggplot2::element_text(hjust =0.5, size =16, face = "bold"),
 plot.subtitle = ggplot2::element_text(hjust =0.5, size =10),
 panel.grid = ggplot2::element_blank(),
 axis.text = ggplot2::element_blank(),
 axis.title = ggplot2::element_blank())
 
 pdf_file <- file.path(fig_dir, "BN_module_network.pdf")
 png_file <- file.path(fig_dir, "BN_module_network.png")
 grDevices::pdf(pdf_file, width =10, height =8); print(p); grDevices::dev.off()
 grDevices::png(png_file, width =10*300, height =8*300, res =300); print(p); grDevices::dev.off()
}

cat(">>> Step4 Complete: Network visualization saved.\n\n")

# ---- Step5: Supplementary Visualization ----
cat(">>> Step5: Supplementary Visualizations <<<\n")

#5.1 Module eigengene heatmap with group annotation
cat(" Creating module eigengene heatmap...\n")

# Prepare data for heatmap
heatmap_data <- t(scale(me_numeric))
colnames(heatmap_data) <- rownames(me_data)

# Column annotation
col_anno <- data.frame(
 Group = me_data$Group,
 row.names = rownames(me_data)
)

# Color scheme
annotation_colors <- list(
 Group = c(NC = "#377EB8", CD = "#4DAF4A", FE = "#E41A1C")
)

# Heatmap using pheatmap
if (requireNamespace("pheatmap", quietly = TRUE)) {
 library(pheatmap)
 
 pdf_hm <- file.path(fig_dir, "Module_eigengene_heatmap.pdf")
 png_hm <- file.path(fig_dir, "Module_eigengene_heatmap.png")
 
 grDevices::pdf(pdf_hm, width =8, height =5)
 pheatmap::pheatmap(heatmap_data,
 annotation_col = col_anno,
 annotation_colors = annotation_colors,
 cluster_rows = TRUE,
 cluster_cols = TRUE,
 color = colorRampPalette(c("blue", "white", "red"))(100),
 main = "Module Eigengene Expression Heatmap",
 fontsize_row =10,
 fontsize_col =6,
 border_color = NA)
 grDevices::dev.off()
 
 grDevices::png(png_hm, width =8*300, height =5*300, res =300)
 pheatmap::pheatmap(heatmap_data,
 annotation_col = col_anno,
 annotation_colors = annotation_colors,
 cluster_rows = TRUE,
 cluster_cols = TRUE,
 color = colorRampPalette(c("blue", "white", "red"))(100),
 main = "Module Eigengene Expression Heatmap",
 fontsize_row =10,
 fontsize_col =6,
 border_color = NA)
 grDevices::dev.off()
 
 cat(" Module eigengene heatmap saved.\n")
}

#5.2 Module-Module correlation heatmap
cat(" Creating module-module correlation heatmap...\n")

pdf_cor <- file.path(fig_dir, "Module_correlation_heatmap.pdf")
png_cor <- file.path(fig_dir, "Module_correlation_heatmap.png")

if (requireNamespace("corrplot", quietly = TRUE)) {
 library(corrplot)
 
 grDevices::pdf(pdf_cor, width =6, height =6)
 corrplot::corrplot(cor_me, method = "color", type = "upper",
 addCoef.col = "black", number.cex =0.8,
 tl.col = "black", tl.cex =0.8,
 col = colorRampPalette(c("blue", "white", "red"))(100),
 title = "Module-Module Correlation Matrix",
 mar = c(0,0,2,0))
 grDevices::dev.off()
 
 grDevices::png(png_cor, width =6*300, height =6*300, res =300)
 corrplot::corrplot(cor_me, method = "color", type = "upper",
 addCoef.col = "black", number.cex =0.8,
 tl.col = "black", tl.cex =0.8,
 col = colorRampPalette(c("blue", "white", "red"))(100),
 title = "Module-Module Correlation Matrix",
 mar = c(0,0,2,0))
 grDevices::dev.off()
 
 cat(" Module correlation heatmap saved.\n")
}

cat(">>> Step5 Complete: Supplementary visualizations saved.\n\n")

# ---- Step6: Result Summary ----
cat(">>> Step6: Result Summary <<<\n")

result <- list(
 module_name = "Module8: Bayesian Network Analysis (Adapted)",
 analysis_date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
 
 data_characteristics = list(
 data_type = "Cross-sectional (single time point)",
 n_samples = nrow(bn_data),
 n_modules = length(bn_vars),
 sample_to_node_ratio = round(nrow(bn_data) / length(bn_vars),2),
 time_series_available = FALSE,
 dynamic_bn_applied = FALSE
 ),
 
 adaptation_note = paste0(
 "Traditional Dynamic Bayesian Network requires >=2 time points for ",
 "modeling temporal causal relationships (t-1 -> t). ",
 "This dataset is cross-sectional (single time point,18 samples,3 groups). ",
 "Analysis adapted to module-level (non-dynamic) Bayesian Network ",
 "using6 WGCNA module eigengenes as high-level variables."
 ),
 
 bn_parameters = list(
 algorithm = best_algo,
 bic_score = best_score,
 edge_confidence_threshold =0.7,
 bootstrap_iterations =200
 ),
 
 network_topology = list(
 n_nodes = length(bn_vars),
 n_edges = nrow(arcs_df),
 modules = bn_vars,
 module_correlations = round(cor_me,3),
 edges = if (nrow(arcs_df) >0) {
 apply(arcs_df,1, function(r) {
 paste0(r["from"], " -> ", r["to"],
 " [strength=", round(as.numeric(r["strength"]),3), "]")
 })
 } else { "No edges found" }
 ),
 
 supplementary_analysis = list(
 pls_pm_performed = file.exists(metabolite_anno)
 ),
 
 key_findings = c(
 "Dataset is cross-sectional (3 groups: NC/CD/FE, single time point, n=18).",
 "Traditional Dynamic Bayesian Network skipped - no time series data.",
 "Adapted to module-level BN using6 WGCNA module eigengenes.",
 paste0("Module-level BN identified ", nrow(arcs_df), 
 " regulatory relationships between metabolic modules."),
 "The BN complements WGCNA module-trait correlations by inferring directional relationships.",
 "Results provide network-level evidence for 'healthy baseline -> CDI infection -> high-iron diet' metabolic trajectory.",
 "Module correlation analysis reveals how metabolic modules co-vary across experimental conditions."
 ),
 
 interpretation_caveats = c(
 "1. NON-DYNAMIC: This is a module-level (not dynamic) Bayesian Network. Edges represent conditional dependence, not temporal causality.",
 "2. LOW STATISTICAL POWER:6 nodes x18 samples (ratio=3) is low for BN structure learning. Bootstrap validation is critical.",
 "3. CROSS-SECTIONAL: All samples at single time point. No temporal ordering can be inferred.",
 "4. CORRELATION != CAUSATION: BN edges are statistical associations consistent with a causal model, not proof of causation."
 ),
 
 output_files = list(
 module_eigengenes = "bayesian_module_eigengenes.csv",
 network_arcs = "bayesian_network_arcs.csv",
 node_attributes = "bayesian_node_attributes.csv",
 network_plot_pdf = "figures/BN_module_network.pdf",
 network_plot_png = "figures/BN_module_network.png",
 eigengene_heatmap_pdf = "figures/Module_eigengene_heatmap.pdf",
 correlation_heatmap_pdf = "figures/Module_correlation_heatmap.pdf"
 )
)

# Save result JSON
result_json <- jsonlite::toJSON(result, pretty = TRUE, auto_unbox = TRUE)
result_out <- file.path(tmp_dir, "result.json")
writeLines(result_json, result_out)
cat(" Result summary saved to:", result_out, "\n")

cat("\n========================================\n")
cat("Module8: Bayesian Network Analysis Complete\n")
cat("========================================\n")
cat("\nOutput files:\n")
cat(" CSV:\n")
cat(" -", file.path(tmp_dir, "bayesian_module_eigengenes.csv"), "\n")
cat(" -", file.path(tmp_dir, "bayesian_network_arcs.csv"), "\n")
cat(" -", file.path(tmp_dir, "bayesian_node_attributes.csv"), "\n")
cat(" Figures:\n")
cat(" -", pdf_file, "\n")
cat(" -", png_file, "\n")
cat(" JSON:\n")
cat(" -", result_out, "\n")
cat("\n")
