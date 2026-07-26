#!/usr/bin/env Rscript
# =============================================================================
# Step3b (v2): WGCNA Module Comparison - using module_df
# =============================================================================
cat("========================================\n")
cat("Step3b: WGCNA Module Comparison (v2)\n")
cat("========================================\n\n")

work_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis"
fig_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/7_cmeans_fuzzy_clustering_analysis/figures"
dir.create(work_dir, showWarnings=FALSE, recursive=TRUE)
dir.create(fig_dir, showWarnings=FALSE, recursive=TRUE)

for (pkg in c("ggplot2","RColorBrewer","ggalluvial")) {
 if (!requireNamespace(pkg, quietly=TRUE))
 install.packages(pkg, repos="https://cloud.r-project.org", quiet=TRUE)
}
library(ggplot2); library(RColorBrewer); library(ggalluvial)

# ----1. Load CMeans ----
cat("Loading CMeans clusters...\n")
cres <- readRDS(file.path(work_dir, "cmeans_result.rds"))
cluster_labels <- cres$cluster
actual_k <- cres$optimal_k
cat(sprintf(" %d metabolites, %d clusters\n", length(cluster_labels), actual_k))
cat(" Sizes:", paste(table(cluster_labels), collapse=", "), "\n")

# ----2. Load WGCNA module_df ----
rdata <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
cat("Loading WGCNA module_df...\n")
env <- new.env()
load(rdata, envir=env)
module_df <- env$module_df

# module_df: Feature (metabolite name) + Module (color)
cat(sprintf(" module_df: %d rows\n", nrow(module_df)))
cat(" First few:\n")
print(head(module_df,5))
cat("\n Module sizes:\n")
print(table(module_df$Module))

# Build named vector: names = Feature (metabolite name), values = Module (color)
wgcna_colors <- setNames(module_df$Module, module_df$Feature)
cat(sprintf(" WGCNA named vector: %d metabolites\n", length(wgcna_colors)))

# ----3. Overlap ----
common_mets <- intersect(names(cluster_labels), names(wgcna_colors))
cat(sprintf("\n Overlap between CMeans and WGCNA: %d / %d metabolites\n",
 length(common_mets), length(cluster_labels)))

if (length(common_mets) <10) {
 cat("Too few overlapping metabolites. Stopping.\n")
 write.csv(data.frame(), file.path(work_dir,"cmeans_vs_wgcna_contingency.csv"))
 write.csv(data.frame(), file.path(work_dir,"cmeans_vs_wgcna_fisher.csv"))
 quit(save="no")
}

# ----4. Contingency Table ----
cmeans_cl <- cluster_labels[common_mets]
wgcna_cl <- wgcna_colors[common_mets]

clean_name <- function(x) {
 ifelse(x=="grey","Grey", paste0(toupper(substr(x,1,1)),substr(x,2,nchar(x))))
}
wgcna_named <- clean_name(wgcna_cl)

ct <- table(CMeans = cmeans_cl, WGCNA = wgcna_named)
cat("\n Contingency table (CMeans x WGCNA):\n")
print(ct)

write.csv(as.data.frame.matrix(ct),
 file.path(work_dir, "cmeans_vs_wgcna_contingency.csv"))

# ----5. Fisher test ----
fg <- tryCatch(fisher.test(ct, simulate.p.value=TRUE, B=10000),
 error=function(e) list(p.value=NA))
cat(sprintf(" Global Fisher p = %s\n",
 ifelse(is.na(fg$p.value),"NA",format(fg$p.value,digits=4))))

fp <- data.frame()
for (ci in rownames(ct)) {
 for (mj in colnames(ct)) {
 a <- ct[ci,mj]; b <- sum(ct[ci,])-a
 c <- sum(ct[,mj])-a; d <- sum(ct)-a-b-c
 if (a>0) {
 ft <- fisher.test(matrix(c(a,b,c,d),2), alternative="greater")
 ex <- sum(ct[ci,])*sum(ct[,mj])/sum(ct)
 fp <- rbind(fp, data.frame(
 CMeans=ci, WGCNA=mj, Count=a,
 Expected=round(ex,1),
 Fold=round(a/max(1,ex),2),
 p_value=ft$p.value, stringsAsFactors=FALSE))
 }
 }
}
if (nrow(fp)>0) {
 fp$p_adj <- p.adjust(fp$p_value,"BH")
 fp <- fp[order(fp$p_value),]
 write.csv(fp, file.path(work_dir,"cmeans_vs_wgcna_fisher.csv"), row.names=FALSE)
 cat(sprintf(" Pairwise Fisher: %d tests, %d significant (p.adj<0.05)\n",
 nrow(fp), sum(fp$p_adj<0.05)))
 sig <- fp[fp$p_adj<0.05,]
 if (nrow(sig)>0) {
 cat(" Top enrichments:\n")
 print(head(sig,10))
 }
}

# ----6. Stacked Bar Plot ----
fd <- as.data.frame(ct); colnames(fd) <- c("CMeans","WGCNA","Count")
um <- sort(unique(as.character(fd$WGCNA)))
mcols <- setNames(c(brewer.pal(min(12,length(um)),"Set3"),"grey60")[seq_along(um)], um)

p_bar <- ggplot(fd, aes(x=CMeans, y=Count, fill=WGCNA)) +
 geom_bar(stat="identity", position="fill") +
 scale_fill_manual(values=mcols) +
 labs(title="CMeans Clusters vs WGCNA Modules",
 x="CMeans Cluster", y="Proportion", fill="WGCNA Module") +
 theme_bw(base_size=12) +
 theme(plot.title=element_text(hjust=0.5,face="bold"),
 legend.position="bottom") +
 guides(fill=guide_legend(nrow=2))
ggsave(file.path(fig_dir,"CMeans_vs_WGCNA_proportion.pdf"), p_bar, width=10, height=7)
ggsave(file.path(fig_dir,"CMeans_vs_WGCNA_proportion.png"), p_bar, width=10, height=7, dpi=300)
cat(" Proportion plot saved.\n")

# ----7. Alluvial (Sankey) Plot ----
fd_s <- fd[order(-fd$Count),]
cum <- cumsum(fd_s$Count)
keep <- which(cum <= sum(fd_s$Count)*0.90)
if (length(keep)<5) keep <- seq_len(min(20,nrow(fd_s)))
fd_m <- fd_s[keep,,drop=FALSE]

if (nrow(fd_m)>2) {
 fd_m$CMeans <- factor(fd_m$CMeans, levels=sort(unique(as.character(fd_m$CMeans))))
 fd_m$WGCNA <- factor(fd_m$WGCNA, levels=sort(unique(as.character(fd_m$WGCNA))))

 p_sankey <- ggplot(fd_m, aes(y=Count, axis1=CMeans, axis2=WGCNA)) +
 geom_alluvium(aes(fill=CMeans), width=1/12, alpha=0.7) +
 geom_stratum(width=1/6, fill="grey90", color="grey40") +
 geom_text(stat="stratum", aes(label=after_stat(stratum)), size=3) +
 scale_fill_manual(
 values=setNames(brewer.pal(max(actual_k,3),"Set2")[seq_len(actual_k)],
 as.character(sort(unique(fd_m$CMeans))))) +
 labs(title="Flow: CMeans vs WGCNA Modules", y="Metabolites", fill="CMeans") +
 theme_minimal(base_size=11) +
 theme(plot.title=element_text(hjust=0.5,face="bold"),
 axis.text.x=element_text(size=10,face="bold"), legend.position="bottom")
 ggsave(file.path(fig_dir,"CMeans_vs_WGCNA_alluvial.pdf"), p_sankey, width=10, height=7)
 ggsave(file.path(fig_dir,"CMeans_vs_WGCNA_alluvial.png"), p_sankey, width=10, height=7, dpi=300)
 cat(" Alluvial plot saved.\n")
} else {
 cat(" Not enough flows.\n")
}

# ----8. Summary ----
cat("\n========================================\n")
cat("Step3b Complete\n")
cat("========================================\n")
cat(sprintf(" Overlap: %d metabolites\n", length(common_mets)))
cat(sprintf(" CMeans clusters: %d\n", actual_k))
cat(sprintf(" WGCNA modules: %d\n", length(unique(wgcna_named))))
cat(sprintf(" Fisher global p: %s\n",
 ifelse(is.na(fg$p.value),"NA",format(fg$p.value,digits=4))))
cat(sprintf(" Fisher pairwise: %d tests\n", nrow(fp)))
for (f in list.files(fig_dir, pattern="\\.(pdf|png)$"))
 cat(sprintf(" %s\n", file.path(fig_dir, f)))
cat("\nDone.\n")
