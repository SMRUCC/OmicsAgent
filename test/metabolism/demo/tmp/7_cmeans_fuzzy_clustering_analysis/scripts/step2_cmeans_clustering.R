#!/usr/bin/env Rscript
# Step2: CMeans Clustering & Visualization
# =============================================================================
work_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis"
fig_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/7_cmeans_fuzzy_clustering_analysis/figures"
rscript_dir <- "G:/OmicsWorks/agent/rscript"
dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

for (pkg in c("e1071","ggplot2","reshape2","RColorBrewer","gridExtra","pheatmap","cluster")) {
 if (!requireNamespace(pkg, quietly = TRUE))
 install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
}
if (!requireNamespace("ComplexHeatmap", quietly = TRUE)) {
 if (!requireNamespace("BiocManager", quietly = TRUE))
 install.packages("BiocManager", repos = "https://cloud.r-project.org")
 BiocManager::install("ComplexHeatmap", ask = FALSE, update = FALSE)
}
library(e1071); library(ggplot2); library(reshape2); library(RColorBrewer)
library(gridExtra); library(pheatmap); library(cluster)
suppressPackageStartupMessages(library(ComplexHeatmap))
source(file.path(rscript_dir,"data_io.R"))
source(file.path(rscript_dir,"clustering.R"))
cat("Ready.\n\n")

# Read data
cat("Reading expression matrix...\n")
expr_data <- load_expression_matrix(
 "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv")
cat(sprintf(" %d x %d\n", nrow(expr_data), ncol(expr_data)))
sg <- data.frame(Sample = colnames(expr_data),
 Group = factor(ifelse(grepl("^Fc16YH_CD",colnames(expr_data)),"CD",
 ifelse(grepl("^Fc16YH_FE",colnames(expr_data)),"FE","NC")),
 levels = c("NC","CD","FE")), stringsAsFactors = FALSE)

# Z-score
cat("Z-score normalization...\n")
ez <- t(scale(t(expr_data)))
ok <- complete.cases(ez)
if (sum(!ok) >0) { ez <- ez[ok,,drop=FALSE]; expr_data <- expr_data[ok,,drop=FALSE] }
cat(sprintf(" Final: %d x %d\n\n", nrow(ez), ncol(ez)))

# ====== Step1: Optimal k ======
cat("=== Step1: Optimal k ===\n")
set.seed(42)
kr <-2:15
val <- data.frame(k = kr, FPC = NA_real_, PE = NA_real_, Sil = NA_real_)
for (k in kr) {
 res <- e1071::cmeans(ez, centers = k, m =2, iter.max =100)
 mem <- res$membership
 fpc <- sum(mem^2) / nrow(ez)
 pe <- -sum(mem * log(mem +1e-15)) / nrow(ez)
 sil <- tryCatch(mean(cluster::silhouette(res$cluster, dist(ez))[,3]), error = function(e) NA)
 val$FPC[val$k == k] <- fpc
 val$PE[val$k == k] <- pe
 val$Sil[val$k == k] <- sil
 cat(sprintf(" k=%2d FPC=%.4f PE=%.4f Sil=%.4f\n", k, fpc, pe, sil))
}
d <- abs(diff(val$FPC)); dn <- d / max(d)
ek <- kr[which(dn <0.45)[1] +1]; if (is.na(ek) || ek <3) ek <-6
sk <- kr[kr >=3][which.max(val$Sil[kr >=3])]
ca <- kr[kr >=3 & kr <=10]
cs <- val$Sil[match(ca, kr)]
ce <-1 - abs(ca - ek) / max(1, max(ca) - min(ca))
cn <- (cs - min(cs, na.rm = TRUE)) / max(1, max(cs, na.rm = TRUE) - min(cs, na.rm = TRUE))
ok <- ca[which.max(0.6 * cn +0.4 * ce)]
cat(sprintf(" Elbow=%d, Sil-best=%d, Final k=%d\n", ek, sk, ok))
write.csv(val, file.path(work_dir, "cmeans_validation_metrics.csv"), row.names = FALSE)
ml <- rbind(data.frame(k=val$k,v=val$FPC,M="FPC"),
 data.frame(k=val$k,v=val$PE,M="PE"),
 data.frame(k=val$k,v=val$Sil,M="Silhouette"))
p_met <- ggplot(ml, aes(k,v)) + geom_line(color="steelblue") +
 geom_point(color="steelblue",size=2) +
 geom_point(data=subset(ml,k==ok),color="red",size=3) +
 facet_wrap(~M,scales="free_y",ncol=1) + scale_x_continuous(breaks=kr) +
 labs(title="Cluster Validation",subtitle=paste0("Optimal k = ", ok),x="k",y="") +
 theme_bw() + theme(plot.title=element_text(hjust=0.5,face="bold"),
 plot.subtitle=element_text(hjust=0.5,color="red"))
ggsave(file.path(fig_dir,"CMeans_validation_metrics.pdf"),p_met,width=8,height=8)
ggsave(file.path(fig_dir,"CMeans_validation_metrics.png"),p_met,width=8,height=8,dpi=300)
cat(" Done.\n\n")

# ====== Step2: CMeans clustering ======
cat(sprintf("=== Step2: CMeans (k=%d) ===\n", ok))
set.seed(42)
cr <- e1071::cmeans(ez, centers = ok, m =2, iter.max =100)
ne <- sort(unique(cr$cluster)); na <- length(ne)
if (na < ok) cat(sprintf(" %d non-empty (of %d)\n", na, ok))
cl <- setNames(seq_len(na), ne)[as.character(cr$cluster)]
names(cl) <- names(cr$cluster)
mem <- cr$membership[, ne, drop = FALSE]
colnames(mem) <- paste0("C", seq_len(na))
ctr <- cr$centers[ne, , drop = FALSE]
rownames(ctr) <- paste0("C", seq_len(na))
cat(" Sizes:\n"); print(table(cl))
saveRDS(list(cluster=cl, membership=mem, centers=ctr, iter=cr$iter,
 converged=cr$converged, optimal_k=na, validation=val),
 file.path(work_dir, "cmeans_result.rds"))
cd <- data.frame(Metabolite=names(cl), Cluster=cl,
 MaxMembership=apply(mem,1,max), stringsAsFactors=FALSE)
write.csv(cd, file.path(work_dir, "cmeans_cluster_assignments.csv"), row.names=FALSE)
cat(" Saved.\n\n")

# ====== Step3: Expression profile plots ======
cat("=== Step3: Profile plots ===\n")
so <- c()
for (g in c("NC","CD","FE")) so <- c(so, sg$Sample[sg$Group == g])
pl <- list()
for (k in seq_len(na)) {
 ms <- names(cl)[cl == k]
 if (length(ms) ==0) next
 es <- ez[ms, , drop = FALSE]
 el <- melt(es); colnames(el) <- c("Metabolite","Sample","Expression")
 el$Membership <- mem[ms[el$Metabolite], k]
 ct <- data.frame(Metabolite="Center", Sample=colnames(ez),
 Expression=as.numeric(ctr[k,]), Membership=1, stringsAsFactors=FALSE)
 pd <- rbind(el, ct); pd$Sample <- factor(pd$Sample, levels=so)
 p <- ggplot() +
 geom_line(data=subset(pd,Metabolite!="Center"),
 aes(x=Sample,y=Expression,group=Metabolite,color=Membership),
 alpha=0.25, linewidth=0.3) +
 geom_line(data=subset(pd,Metabolite=="Center"),
 aes(x=Sample,y=Expression,group=1), color="black", linewidth=1.5) +
 scale_color_gradient(low="grey80", high="darkred", limits=c(0,1)) +
 labs(title=paste0("Cluster ",k," (n=",length(ms),")"),
 x="Sample", y="z-score Expression", color="Membership") +
 theme_bw(base_size=10) +
 theme(plot.title=element_text(hjust=0.5,face="bold",size=11),
 axis.text.x=element_text(angle=45,hjust=1,size=7), legend.position="right")
 pl[[k]] <- p
}
if (na <=4) {
 ncp <-2
} else if (na <=6) {
 ncp <-3
} else {
 ncp <-4
}
nrp <- ceiling(na / ncp)
pp <- gridExtra::marrangeGrob(pl, nrow=nrp, ncol=ncp, top=NULL)
ggsave(file.path(fig_dir,"CMeans_profiles.pdf"), pp, width=4*ncp, height=3.5*nrp)
ggsave(file.path(fig_dir,"CMeans_profiles.png"), pp, width=4*ncp, height=3.5*nrp, dpi=300)
cat(" Saved.\n\n")

# ====== Step4: Membership heatmap ======
cat("=== Step4: Membership heatmap ===\n")
ord <- order(cl, -apply(mem,1,max))
mo <- mem[ord, , drop = FALSE]
cc <- factor(cl[ord], levels=seq_len(na)); names(cc) <- rownames(mo)
co <- setNames(brewer.pal(max(na,3),"Set2")[seq_len(na)], as.character(seq_len(na)))
mf <- circlize::colorRamp2(c(0,0.5,1), c("white","orange","darkred"))
ha_col <- HeatmapAnnotation(Cluster=cc, col=list(Cluster=co), show_annotation_name=FALSE)
ha_row <- rowAnnotation(Cluster=as.character(seq_len(na)), col=list(Cluster=co),
 show_annotation_name=TRUE)

pdf(file.path(fig_dir,"CMeans_membership_heatmap.pdf"), width=12, height=max(4,na*1.2))
ht <- Heatmap(t(mo), name="Membership", col=mf,
 top_annotation=ha_col, left_annotation=ha_row,
 show_row_names=TRUE, show_column_names=FALSE,
 row_names_gp=gpar(fontsize=10,fontface="bold"),
 cluster_rows=TRUE, cluster_columns=FALSE,
 column_split=cc, column_title_gp=gpar(fontsize=9),
 heatmap_legend_param=list(direction="vertical"))
draw(ht); dev.off()
png(file.path(fig_dir,"CMeans_membership_heatmap.png"), width=3600, height=max(1200,na*360), res=300)
draw(ht); dev.off()
cat(" Saved.\n\n")

# Summary
cat("========================================\n")
cat("CMeans Step2 Complete\n")
cat("========================================\n")
cat(sprintf(" Requested k : %d\n", ok))
cat(sprintf(" Actual clusters : %d\n", na))
cat(sprintf(" Metabolites : %d\n", nrow(ez)))
cat(sprintf(" Sizes : %s\n", paste(table(cl), collapse=", ")))
cat(sprintf(" CSV : %s\n", file.path(work_dir,"cmeans_cluster_assignments.csv")))
cat(sprintf(" RDS : %s\n", file.path(work_dir,"cmeans_result.rds")))
cat(sprintf(" Figures : %s\n\n", fig_dir))
for (f in list.files(fig_dir, pattern="\\.(pdf|png)$"))
 cat(sprintf(" %s\n", file.path(fig_dir,f)))
cat("\nDone.\n")
