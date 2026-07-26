###############################################################
# WGCNA Step3: KEGG Enrichment Analysis for Each Module
###############################################################

base_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis"
tables_dir <- file.path(base_dir, "tables")
figures_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/6_wgcna_trait_association_analysis/figures"

for (d in c(tables_dir, figures_dir)) {
 if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

cat("=== WGCNA Step3: KEGG Enrichment for Modules ===\n")

library(ggplot2)
library(grDevices)
library(stats)

# ----1. Load data ----
rdata_file <- file.path(base_dir, "wgcna_step1_data.RData")
load(rdata_file)
rdata_file2 <- file.path(base_dir, "wgcna_step2_data.RData")
load(rdata_file2)

cat("Data loaded.\n")

# ----2. Load metabolite annotation ----
metabolites_file <- "G:/OmicsWorks/test/metabolism/metabolites.csv"
metab_anno <- read.csv(metabolites_file, row.names =1, check.names = FALSE)

clean_name <- function(x) {
 x <- gsub("&gamma;", "gamma", x)
 x <- gsub("&delta;", "delta", x)
 x <- gsub("&beta;", "beta", x)
 x <- gsub("&alpha;", "alpha", x)
 x <- gsub("&kappa;", "kappa", x)
 x <- gsub("&lt;", "<", x)
 x <- gsub("&gt;", ">", x)
 x <- gsub("&amp;", "&", x)
 x <- gsub("<[^>]+>", "", x)
 x <- gsub("\\s+", " ", x)
 trimws(x)
}
metab_anno$name_clean <- clean_name(metab_anno$name)

expr_rownames <- rownames(expr_matrix)
overlap_name <- sum(expr_rownames %in% metab_anno$name_clean)
overlap_id <- sum(expr_rownames %in% as.character(metab_anno$id))

if (overlap_name >= overlap_id && overlap_name >0) {
 map_col <- "name_clean"
} else if (overlap_id >0) {
 map_col <- "id"
} else {
 overlap_rn <- sum(expr_rownames %in% rownames(metab_anno))
 if (overlap_rn >0) {
 metab_anno$mapping_id <- rownames(metab_anno)
 map_col <- "mapping_id"
 } else {
 stop("Cannot map!")
 }
}

match_idx <- match(expr_rownames, metab_anno[[map_col]])
anno_matched <- metab_anno[match_idx, ]
rownames(anno_matched) <- expr_rownames

# ----3. Build pathway background ----
kegg_cat_col <- "kegg_category"
if (!kegg_cat_col %in% colnames(anno_matched)) {
 alt_names <- grep("kegg|pathway|KEGG", colnames(anno_matched), value = TRUE, ignore.case = TRUE)
 kegg_cat_col <- alt_names[1]
}

all_features <- expr_rownames
kegg_raw <- as.character(anno_matched[[kegg_cat_col]])
kegg_raw[is.na(kegg_raw)] <- ""

# Build pathway -> features mapping
pathway_to_features <- list()
for (i in seq_along(kegg_raw)) {
 if (kegg_raw[i] == "") next
 cats <- trimws(strsplit(kegg_raw[i], ";")[[1]])
 cats <- cats[cats != ""]
 feat <- all_features[i]
 for (pw in cats) {
 if (is.null(pathway_to_features[[pw]])) {
 pathway_to_features[[pw]] <- c()
 }
 pathway_to_features[[pw]] <- c(pathway_to_features[[pw]], feat)
 }
}
pathway_to_features <- lapply(pathway_to_features, unique)

cat("Total pathways:", length(pathway_to_features), "\n")

# Save pathway background
pw_bg <- data.frame(
 Pathway = names(pathway_to_features),
 FeatureCount = sapply(pathway_to_features, length),
 Features = sapply(pathway_to_features, paste, collapse = ";"),
 stringsAsFactors = FALSE
)
pw_bg_file <- file.path(tables_dir, "wgcna_pathway_background.csv")
write.csv(pw_bg, pw_bg_file, row.names = FALSE)
cat("Pathway background saved to:", pw_bg_file, "\n")

# ----4. Run Fisher enrichment for each module ----
cat("Running Fisher enrichment for each module...\n")

unique_modules <- unique(merged_colors)
n_bg <- length(all_features)

enrich_results <- list()

for (mod in unique_modules) {
 cat(" Module:", mod, "\n")
 
 sig_features <- all_features[merged_colors == mod]
 n_sig <- length(sig_features)
 
 if (n_sig <2) {
 cat(" Too few features (<2), skipping.\n")
 next
 }
 
 mod_results <- list()
 
 for (pw in names(pathway_to_features)) {
 features_in_pw <- intersect(pathway_to_features[[pw]], all_features)
 
 a <- length(intersect(features_in_pw, sig_features))
 b <- length(features_in_pw) - a
 c <- n_sig - a
 d <- n_bg - length(features_in_pw) - c
 
 if (a ==0) next
 
 cont_table <- matrix(c(a, b, c, d), nrow =2)
 ft <- fisher.test(cont_table, alternative = "greater")
 
 mod_results[[pw]] <- data.frame(
 Module = mod,
 Pathway = pw,
 Count_in_module = a,
 Pathway_size = length(features_in_pw),
 Module_size = n_sig,
 Bg_size = n_bg,
 Ratio = round(a / n_sig *100,2),
 pvalue = ft$p.value,
 stringsAsFactors = FALSE
 )
 }
 
 if (length(mod_results) >0) {
 mod_df <- do.call(rbind, mod_results)
 mod_df$p_adj <- p.adjust(mod_df$pvalue, method = "BH")
 mod_df$enriched <- mod_df$p_adj <0.05
 mod_df <- mod_df[order(mod_df$pvalue), ]
 enrich_results[[mod]] <- mod_df
 }
}

if (length(enrich_results) >0) {
 all_enrich <- do.call(rbind, enrich_results)
} else {
 all_enrich <- data.frame(
 Module = character(), Pathway = character(),
 Count_in_module = integer(), Pathway_size = integer(),
 Module_size = integer(), Bg_size = integer(),
 Ratio = numeric(), pvalue = numeric(),
 p_adj = numeric(), enriched = logical(),
 stringsAsFactors = FALSE
 )
}

cat("Total enrichment results:", nrow(all_enrich), "rows\n")
cat("Significant enrichments (p_adj<0.05):", sum(all_enrich$enriched), "\n")

enrich_file <- file.path(tables_dir, "wgcna_kegg_enrichment_all_modules.csv")
write.csv(all_enrich, enrich_file, row.names = FALSE)
cat("Enrichment results saved to:", enrich_file, "\n")

# ----5. KEGG Enrichment Dotplot ----
cat("Plotting KEGG enrichment dotplot...\n")

if (nrow(all_enrich) >0) {
 # For each module, take top5 pathways by p-value
 plot_data_list <- list()
 for (mod in unique(all_enrich$Module)) {
 mod_sub <- all_enrich[all_enrich$Module == mod, ]
 top_n <- min(5, nrow(mod_sub))
 plot_data_list[[mod]] <- head(mod_sub[order(mod_sub$pvalue), ], top_n)
 }
 plot_data <- do.call(rbind, plot_data_list)
 
 # Truncate pathway names
 plot_data$Pathway_short <- gsub("^\\d+\\s+", "", plot_data$Pathway)
 plot_data$Pathway_short <- substr(plot_data$Pathway_short,1,40)
 plot_data$neg_log10_padj <- -log10(plot_data$p_adj +1e-10)
 
 p_dot <- ggplot(plot_data, aes(
 x = Pathway_short,
 y = Module,
 size = Count_in_module,
 color = neg_log10_padj
 )) +
 geom_point(alpha =0.8) +
 scale_size_continuous(range = c(3,10), name = "Count in Module") +
 scale_color_gradient(low = "blue", high = "red",
 name = expression(-log[10](p[adj]))) +
 labs(title = "KEGG Pathway Enrichment by WGCNA Module",
 x = "Pathway", y = "Module") +
 theme_bw(base_size =11) +
 theme(plot.title = element_text(hjust =0.5, size =14, face = "bold"),
 axis.text.x = element_text(angle =45, hjust =1, size =8),
 axis.text.y = element_text(size =10))
 
 pdf_dot <- file.path(figures_dir, "KEGG_enrichment_dotplot.pdf")
 pdf(pdf_dot, width =14, height = max(6, length(unique(plot_data$Module)) *0.5))
 print(p_dot)
 dev.off()
 cat("Dotplot PDF:", pdf_dot, "\n")
 
 png_dot <- file.path(figures_dir, "KEGG_enrichment_dotplot.png")
 png(png_dot, width =14 *300, height = max(6, length(unique(plot_data$Module)) *0.5) *300, 
 res =300)
 print(p_dot)
 dev.off()
 cat("Dotplot PNG:", png_dot, "\n")
} else {
 cat("No enrichment results to plot.\n")
}

# ----6. Summary ----
cat("\n=== Final Summary ===\n")
cat("Module sizes:\n")
print(table(merged_colors))

cat("\nTop module-trait associations (|cor|>0.5, p<0.05):\n")
sig_cor <- cor_df[abs(cor_df$Correlation) >0.5 & cor_df$pvalue <0.05, ]
if (nrow(sig_cor) >0) {
 print(sig_cor[order(sig_cor$pvalue), ])
}

cat("\nTop KEGG enrichments (p_adj<0.05):\n")
sig_enrich <- all_enrich[all_enrich$enriched, ]
if (nrow(sig_enrich) >0) {
 print(sig_enrich[order(sig_enrich$p_adj), ])
} else {
 cat("(None at p_adj<0.05)\n")
 top5 <- head(all_enrich[order(all_enrich$pvalue), ],5)
 if (nrow(top5) >0) print(top5)
}

cat("\n=== WGCNA Analysis Completed! ===\n")
cat("All results saved to:", tables_dir, "\n")
cat("All figures saved to:", figures_dir, "\n")
