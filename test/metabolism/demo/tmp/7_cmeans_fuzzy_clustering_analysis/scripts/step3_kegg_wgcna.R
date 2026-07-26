#!/usr/bin/env Rscript
# =============================================================================
# Step3: KEGG Enrichment Analysis & WGCNA Module Comparison
# Module:7_CMeans_Fuzzy_Clustering
# Description:
# (a) For each CMeans cluster, perform KEGG pathway enrichment (Fisher)
# (b) Load WGCNA module assignments from RData
# (c) Build contingency table + Fisher test linking CMeans -> WGCNA
# (d) Alluvial/Sankey diagram and stacked bar plot
# =============================================================================

cat("========================================\n")
cat("Step3: KEGG Enrichment & WGCNA Comparison\n")
cat("========================================\n\n")

work_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis"
fig_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/7_cmeans_fuzzy_clustering_analysis/figures"
rscript_dir <- "G:/OmicsWorks/agent/rscript"
dir.create(work_dir, showWarnings=FALSE, recursive=TRUE)
dir.create(fig_dir, showWarnings=FALSE, recursive=TRUE)

# ----1. Install & Load Packages ----
for (pkg in c("e1071","ggplot2","reshape2","RColorBrewer","cluster")) {
 if (!requireNamespace(pkg, quietly=TRUE))
 install.packages(pkg, repos="https://cloud.r-project.org", quiet=TRUE)
}
# ggalluvial for Sankey diagram
if (!requireNamespace("ggalluvial", quietly=TRUE))
 install.packages("ggalluvial", repos="https://cloud.r-project.org", quiet=TRUE)

library(e1071); library(ggplot2); library(reshape2); library(RColorBrewer)
library(cluster); library(ggalluvial)

source(file.path(rscript_dir,"data_io.R"))
source(file.path(rscript_dir,"enrichment.R"))
cat("Packages & helpers ready.\n\n")

# ----2. Load CMeans Result ----
cmeans_rds <- file.path(work_dir, "cmeans_result.rds")
if (file.exists(cmeans_rds)) {
 cres <- readRDS(cmeans_rds)
 cluster_labels <- cres$cluster
 membership_mat <- cres$membership
 actual_k <- cres$optimal_k
 cat(sprintf("CMeans result loaded: %d metabolites, %d clusters\n",
 length(cluster_labels), actual_k))
 cat("Cluster sizes:\n"); print(table(cluster_labels))
} else {
 # Fallback: read CSV assignment
 cat("RDS not found, reading CSV...\n")
 cl_df <- read.csv(file.path(work_dir,"cmeans_cluster_assignments.csv"),
 stringsAsFactors=FALSE)
 cluster_labels <- setNames(cl_df$Cluster, cl_df$Metabolite)
 actual_k <- length(unique(cluster_labels))
 membership_mat <- NULL
 cat(sprintf(" %d metabolites, %d clusters\n", length(cluster_labels), actual_k))
}

# ----3. Read Expression Matrix (for metabolite IDs) & Annotation ----
expr_path <- "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv"
expr_data <- load_expression_matrix(expr_path)
all_features <- intersect(rownames(expr_data), names(cluster_labels))
cat(sprintf("Expression matrix loaded: %d total features\n", nrow(expr_data)))

anno_path <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
anno_raw <- read.csv(anno_path, stringsAsFactors=FALSE, check.names=FALSE)

# Build feature_anno: matching key is the 'id' column (metabolite name)
feature_anno <- data.frame(
 ID = as.character(anno_raw$id),
 name = as.character(anno_raw$name),
 type = "metabolite",
 kegg = as.character(anno_raw$kegg),
 stringsAsFactors = FALSE)
# Also keep raw kegg_class & kegg_category if available
if ("kegg_class" %in% colnames(anno_raw))
 feature_anno$kegg_class <- as.character(anno_raw$kegg_class)
if ("kegg_category" %in% colnames(anno_raw))
 feature_anno$kegg_category <- as.character(anno_raw$kegg_category)

# Match IDs
common_ids <- intersect(all_features, feature_anno$ID)
if (length(common_ids) ==0) {
 # Try name column
 feature_anno <- data.frame(
 ID = as.character(anno_raw$name),
 name = as.character(anno_raw$name),
 type = "metabolite",
 kegg = as.character(anno_raw$kegg),
 stringsAsFactors = FALSE)
 common_ids <- intersect(all_features, feature_anno$ID)
}
cat(sprintf("Matched %d metabolites with annotation\n", length(common_ids)))

# Subset to common
cluster_labels <- cluster_labels[common_ids]
all_features <- common_ids
feature_anno <- feature_anno[match(common_ids, feature_anno$ID),,drop=FALSE]

# ----4. KEGG Enrichment per Cluster ----
cat("\n==========4a. KEGG Enrichment (Fisher test) ==========\n")

kegg_enrich_list <- list()
for (k in seq_len(actual_k)) {
 sig <- names(cluster_labels)[cluster_labels == k]
 cat(sprintf(" Cluster %d: %d metabolites\n", k, length(sig)))
 if (length(sig) <3) { cat(" Too few, skip.\n"); next }

 er <- tryCatch(
 perform_fisher_enrichment(
 all_features = all_features,
 sig_features = sig,
 feature_anno = feature_anno,
 category_col = "kegg",
 pvalue_threshold =1,
 p_adjust_method = "BH"),
 error = function(e) {
 cat(" Error:", conditionMessage(e), "\n")
 data.frame()
 })

 if (nrow(er) >0) {
 er$Cluster <- paste0("Cluster", k)
 kegg_enrich_list[[k]] <- er
 n_sig <- sum(er$enriched)
 if (n_sig >0) {
 cat(sprintf(" %d enriched pathways (p.adj<0.05)\n", n_sig))
 } else {
 cat(sprintf(" Top pathway: %s (p=%.4f)\n", er$Category[1], er$pvalue[1]))
 }
 }
}

# Combine & save
if (length(kegg_enrich_list) >0) {
 enrich_all <- do.call(rbind, kegg_enrich_list)
 write.csv(enrich_all,
 file.path(work_dir, "cmeans_cluster_kegg_enrichment.csv"),
 row.names = FALSE)
 cat(sprintf(" Combined enrichment saved: %d rows\n", nrow(enrich_all)))

 # ----4b. Enrichment Barplot (top5 per cluster) ----
 top_list <- lapply(kegg_enrich_list, function(d) {
 if (is.null(d) || nrow(d) ==0) return(NULL)
 head(d[order(d$pvalue), ], min(5, nrow(d)))
 })
 top_enrich <- do.call(rbind, top_list[!sapply(top_list, is.null)])

 if (nrow(top_enrich) >0 && length(unique(top_enrich$Cluster)) >0) {
 top_enrich$neg_log10 <- -log10(top_enrich$pvalue)
 top_enrich$cat_short <- substr(top_enrich$Category,1,60)

 p_enrich <- ggplot(top_enrich,
 aes(x = reorder(cat_short, Count_in_sig),
 y = Count_in_sig, fill = neg_log10)) +
 geom_bar(stat = "identity") +
 coord_flip() +
 facet_wrap(~ Cluster, scales = "free_y", ncol =2) +
 scale_fill_gradient(low = "lightblue", high = "darkred",
 name = expression(-log[10](P))) +
 labs(title = "KEGG Pathway Enrichment by CMeans Cluster",
 x = "KEGG Pathway", y = "Metabolite Count") +
 theme_bw(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"),
 strip.text = element_text(face = "bold"),
 axis.text.y = element_text(size =8))

 n_cl <- length(unique(top_enrich$Cluster))
 ggsave(file.path(fig_dir, "CMeans_cluster_kegg_enrichment.pdf"),
 p_enrich, width =12, height = max(6,3 * n_cl))
 ggsave(file.path(fig_dir, "CMeans_cluster_kegg_enrichment.png"),
 p_enrich, width =12, height = max(6,3 * n_cl), dpi =300)
 cat(" Enrichment barplot saved.\n")
 }
} else {
 cat(" No KEGG enrichment results obtained.\n")
 write.csv(data.frame(), file.path(work_dir, "cmeans_cluster_kegg_enrichment.csv"))
}

# ----5. WGCNA Module Comparison ----
cat("\n==========5. WGCNA Module Comparison ==========\n")

# Helper: load WGCNA module colors from RData
load_wgcna_colors <- function(rdata_path) {
 if (!file.exists(rdata_path)) return(NULL)
 e <- new.env()
 load(rdata_path, envir = e)
 # Try common variable names from WGCNA output
 for (vn in c("mergedColors", "moduleColors", "dynamicColors")) {
 if (exists(vn, envir = e)) return(get(vn, envir = e))
 }
 # Try net$colors
 if (exists("net", envir = e) && !is.null(e$net$colors))
 return(e$net$colors)
 NULL
}

mc <- load_wgcna_colors(
 "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData")
if (is.null(mc)) {
 mc <- load_wgcna_colors(
 "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step1_data.RData")
}

found_wgcna <- !is.null(mc)

if (found_wgcna) {
 cat(" WGCNA module colors loaded successfully.\n")
 cat(sprintf(" Number of colored metabolites: %d\n", length(mc)))

 # Find common metabolites
 common_mets <- intersect(all_features, names(mc))
 cat(sprintf(" Overlap with CMeans: %d metabolites\n", length(common_mets)))

 if (length(common_mets) >=10) {
 # Build contingency table
 # Map colours to readable names
 unique_cols <- unique(mc[common_mets])
 color_names <- ifelse(unique_cols == "grey", "Grey",
 paste0(toupper(substr(unique_cols,1,1)),
 substr(unique_cols,2,nchar(unique_cols))))
 names(color_names) <- unique_cols

 cmeans_cl <- cluster_labels[common_mets]
 wgcna_mod <- color_names[mc[common_mets]]

 # ----5a. Contingency Table ----
 contingency <- table(CMeans_Cluster = cmeans_cl, WGCNA_Module = wgcna_mod)
 cat("\n Contingency table (CMeans clusters vs WGCNA modules):\n")
 print(contingency)
 write.csv(as.data.frame.matrix(contingency),
 file.path(work_dir, "cmeans_vs_wgcna_contingency.csv"))

 # ----5b. Global Fisher Test ----
 fisher_global <- tryCatch(
 fisher.test(contingency, simulate.p.value = TRUE, B =10000),
 error = function(e) list(p.value = NA))
 cat(sprintf("\n Global Fisher exact test p-value = %s\n",
 ifelse(is.na(fisher_global$p.value), "NA",
 format(fisher_global$p.value, digits =4))))

 # ----5c. Pairwise Fisher Tests ----
 fp <- data.frame()
 for (ci in rownames(contingency)) {
 for (mj in colnames(contingency)) {
 a <- contingency[ci, mj]
 b <- sum(contingency[ci, ]) - a
 c <- sum(contingency[, mj]) - a
 d <- sum(contingency) - a - b - c
 if (a >0) {
 ft <- fisher.test(matrix(c(a,b,c,d),2), alternative = "greater")
 expected <- sum(contingency[ci,]) * sum(contingency[,mj]) / sum(contingency)
 fp <- rbind(fp, data.frame(
 CMeans_Cluster = ci,
 WGCNA_Module = mj,
 Count = a,
 Expected = round(expected,1),
 Fold_Enrichment = round(a / max(1, expected),2),
 p_value = ft$p.value,
 stringsAsFactors = FALSE))
 }
 }
 }
 if (nrow(fp) >0) {
 fp$p_adjusted <- p.adjust(fp$p_value, "BH")
 fp <- fp[order(fp$p_value), ]
 write.csv(fp, file.path(work_dir, "cmeans_vs_wgcna_fisher.csv"),
 row.names = FALSE)
 cat(sprintf(" Pairwise Fisher results: %d significant (p.adj<0.05)\n",
 sum(fp$p_adjusted <0.05)))
 }

 # ----5d. Stacked Proportion Bar Plot ----
 fd <- as.data.frame(contingency)
 colnames(fd) <- c("CMeans", "WGCNA", "Count")
 uniq_mods <- sort(unique(fd$WGCNA))
 mod_colors <- setNames(
 c(brewer.pal(min(12, length(uniq_mods)), "Set3"),
 "grey60")[seq_along(uniq_mods)],
 uniq_mods)

 p_bar <- ggplot(fd, aes(x = CMeans, y = Count, fill = WGCNA)) +
 geom_bar(stat = "identity", position = "fill") +
 scale_fill_manual(values = mod_colors) +
 labs(title = "CMeans Clusters vs WGCNA Modules (Proportion)",
 x = "CMeans Cluster", y = "Proportion", fill = "WGCNA Module") +
 theme_bw(base_size =12) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"),
 legend.position = "bottom") +
 guides(fill = guide_legend(nrow =2))

 ggsave(file.path(fig_dir, "CMeans_vs_WGCNA_proportion.pdf"),
 p_bar, width =9, height =6)
 ggsave(file.path(fig_dir, "CMeans_vs_WGCNA_proportion.png"),
 p_bar, width =9, height =6, dpi =300)
 cat(" Proportion bar plot saved.\n")

 # ----5e. Alluvial/Sankey Plot ----
 # Prepare alluvial data
 flow_data <- fd
 # Add a dummy 'alluvium' identifier column
 flow_data$Metabolite_ID <- paste0(flow_data$CMeans, "_", flow_data$WGCNA)

 # Filter to keep only top flows for readability (keep80% of total)
 flow_data <- flow_data[order(-flow_data$Count), ]
 total_count <- sum(flow_data$Count)
 cum_sum <- cumsum(flow_data$Count)
 keep_idx <- which(cum_sum <= total_count *0.90)
 if (length(keep_idx) <5) keep_idx <- seq_len(min(15, nrow(flow_data)))
 flow_main <- flow_data[keep_idx, , drop = FALSE]

 if (nrow(flow_main) >2) {
 p_sankey <- ggplot(flow_main,
 aes(y = Count,
 axis1 = CMeans, axis2 = WGCNA,
 fill = after_stat(stratum))) +
 geom_alluvium(aes(fill = CMeans), width =1/12, alpha =0.7) +
 geom_stratum(width =1/6, fill = "grey90", color = "grey40") +
 geom_text(stat = "stratum",
 aes(label = after_stat(stratum)),
 size =3) +
 scale_fill_manual(values = c(
 setNames(brewer.pal(max(actual_k,3),"Set2")[seq_len(actual_k)],
 paste0(seq_len(actual_k))),
 mod_colors)) +
 labs(title = "Flow of Metabolites: CMeans Clusters vs WGCNA Modules",
 y = "Number of Metabolites",
 fill = "CMeans Cluster") +
 theme_minimal(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, face = "bold"),
 axis.text.x = element_text(size =10, face = "bold"),
 legend.position = "bottom")

 ggsave(file.path(fig_dir, "CMeans_vs_WGCNA_alluvial.pdf"),
 p_sankey, width =10, height =7)
 ggsave(file.path(fig_dir, "CMeans_vs_WGCNA_alluvial.png"),
 p_sankey, width =10, height =7, dpi =300)
 cat(" Alluvial (Sankey) diagram saved.\n")
 } else {
 cat(" Not enough flow data for alluvial plot.\n")
 }

 } else {
 cat(" Too few overlapping metabolites for comparison (<10).\n")
 write.csv(data.frame(), file.path(work_dir, "cmeans_vs_wgcna_contingency.csv"))
 write.csv(data.frame(), file.path(work_dir, "cmeans_vs_wgcna_fisher.csv"))
 }

} else {
 cat(" WGCNA module colors NOT found in RData files.\n")
 cat(" Checked: wgcna_step1_data.RData and wgcna_step2_data.RData\n")
 cat(" Writing empty comparison files.\n")
 write.csv(data.frame(), file.path(work_dir, "cmeans_vs_wgcna_contingency.csv"))
 write.csv(data.frame(), file.path(work_dir, "cmeans_vs_wgcna_fisher.csv"))
}

# ----6. Summary ----
cat("\n========================================\n")
cat("Step3 Complete\n")
cat("========================================\n")
cat(sprintf(" CMeans clusters : %d\n", actual_k))
cat(sprintf(" KEGG enrichment results : %s\n",
 ifelse(file.exists(file.path(work_dir,"cmeans_cluster_kegg_enrichment.csv")),
 "Yes", "No/Empty")))
cat(sprintf(" WGCNA modules found : %s\n", ifelse(found_wgcna,
 paste(length(unique(mc)), "colors"),
 "Not found")))
cat(sprintf(" WGCNA contingency : %s\n",
 ifelse(file.exists(file.path(work_dir,"cmeans_vs_wgcna_contingency.csv")),
 "Yes", "No")))
cat(sprintf(" Work dir : %s\n", work_dir))
cat(sprintf(" Figure dir : %s\n\n", fig_dir))

cat("Output files:\n")
for (f in list.files(work_dir, pattern="\\.csv$"))
 cat(sprintf(" %s\n", file.path(work_dir, f)))
for (f in list.files(fig_dir, pattern="\\.(pdf|png)$"))
 cat(sprintf(" %s\n", file.path(fig_dir, f)))
cat("\nDone.\n")
