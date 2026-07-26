#!/usr/bin/env Rscript
# run_cmeans.R - CMeans Fuzzy Clustering Analysis
# =============================================================================
work_dir <- "G:/OmicsWorks/test/metabolism/demo/tmp/7_cmeans_fuzzy_clustering_analysis"
fig_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/7_cmeans_fuzzy_clustering_analysis/figures"
rscript_dir <- "G:/OmicsWorks/agent/rscript"
dir.create(work_dir, showWarnings=FALSE, recursive=TRUE)
dir.create(fig_dir, showWarnings=FALSE, recursive=TRUE)

for (pkg in c("e1071","ggplot2","reshape2","RColorBrewer","gridExtra","pheatmap","cluster")) {
 if (!requireNamespace(pkg, quietly=TRUE))
 install.packages(pkg, repos="https://cloud.r-project.org", quiet=TRUE)
}
if (!requireNamespace("ComplexHeatmap", quietly=TRUE)) {
 if (!requireNamespace("BiocManager", quietly=TRUE))
 install.packages("BiocManager", repos="https://cloud.r-project.org")
 BiocManager::install("ComplexHeatmap", ask=FALSE, update=FALSE)
}
library(e1071); library(ggplot2); library(reshape2); library(RColorBrewer)
library(gridExtra); library(pheatmap); library(cluster)
suppressPackageStartupMessages(library(ComplexHeatmap))
source(file.path(rscript_dir,"data_io.R"))
source(file.path(rscript_dir,"clustering.R"))
source(file.path(rscript_dir,"enrichment.R"))
cat("Setup complete.\n\n")

# Read data
cat("Reading data...\n")
expr_data <- load_expression_matrix(
 "G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv")
cat(sprintf(" Expression: %d x %d\n", nrow(expr_data), ncol(expr_data)))
anno_raw <- read.csv("G:/OmicsWorks/test/metabolism/metabolites.csv",
 stringsAsFactors=FALSE, check.names=FALSE)
feature_anno <- data.frame(ID=as.character(anno_raw$id),
 name=as.character(anno_raw$name), type="metabolite",
 kegg=as.character(anno_raw$kegg), stringsAsFactors=FALSE)
common_ids <- intersect(rownames(expr_data), feature_anno$ID)
if (length(common_ids)==0) {
 feature_anno <- data.frame(ID=as.character(anno_raw$name),
 name=as.character(anno_raw$name), type="metabolite",
 kegg=as.character(anno_raw$kegg), stringsAsFactors=FALSE)
 common_ids <- intersect(rownames(expr_data), feature_anno$ID)
}
expr_data <- expr_data[common_ids,,drop=FALSE]
feature_anno <- feature_anno[match(common_ids,feature_anno$ID),,drop=FALSE]
cat(sprintf(" Annotated: %d metabolites\n", nrow(expr_data)))
sample_groups <- data.frame(Sample=colnames(expr_data),
 Group=factor(ifelse(grepl("^Fc16YH_CD",colnames(expr_data)),"CD",
 ifelse(grepl("^Fc16YH_FE",colnames(expr_data)),"FE","NC")),
 levels=c("NC","CD","FE")), stringsAsFactors=FALSE)

cat("Z-score normalization...\n")
expr_z <- t(scale(t(expr_data)))
ok <- complete.cases(expr_z)
if (sum(!ok)>0) { expr_z <- expr_z[ok,,drop=FALSE]; expr_data <- expr_data[ok,,drop=FALSE]
 feature_anno <- feature_anno[ok,,drop=FALSE] }
cat(sprintf(" Final: %d x %d\n", nrow(expr_z), ncol(expr_z)))

# ============ STEP1: Optimal k ============
cat("\n========== STEP1: Optimal k ==========\n")
set.seed(42)
k_range <-2:15
val <- data.frame(k=k_range, FPC=NA_real_, PE=NA_real_, Sil=NA_real_)
for (k in k_range) {
 res <- e1071::cmeans(expr_z, centers=k, m=2, iter.max=100)
 mem <- res$membership
 fpc <- sum(mem^2)/nrow(expr_z)
 pe <- -sum(mem*log(mem+1e-15))/nrow(expr_z)
 sil <- tryCatch(mean(cluster::silhouette(res$cluster,dist(expr_z))[,3]), error=function(e) NA)
 val$FPC[val$k==k] <- fpc; val$PE[val$k==k] <- pe; val$Sil[val$k==k] <- sil
 cat(sprintf(" k=%2d FPC=%.4f PE=%.4f Sil=%.4f\n", k, fpc, pe, sil))
}
diffs <- abs(diff(val$FPC)); diffs_norm <- diffs/max(diffs)
elbow_k <- k_range[which(diffs_norm<0.45)[1]+1]; if (is.na(elbow_k)|elbow_k<3) elbow_k<-6
k3 <- val$k[val$k>=3]; sil_best_k <- k3[which.max(val$Sil[val$k>=3])]
cand <- k_range[k_range>=3 & k_range<=10]
csil <- val$Sil[match(cand,k_range)]
celb <-1 - abs(cand-elbow_k)/max(1,max(cand)-min(cand))
csil_n <- (csil-min(csil,na.rm=TRUE))/max(1,max(csil,na.rm=TRUE)-min(csil,na.rm=TRUE))
optimal_k <- cand[which.max(0.6*csil_n+0.4*celb)]
cat(sprintf(" Elbow=%d, Sil-best=%d, Final k=%d\n", elbow_k, sil_best_k, optimal_k))
write.csv(val, file.path(work_dir,"cmeans_validation_metrics.csv"), row.names=FALSE)

ml <- rbind(data.frame(k=val$k,v=val$FPC,M="FPC"),
 data.frame(k=val$k,v=val$PE,M="PE"),
 data.frame(k=val$k,v=val$Sil,M="Silhouette"))
p_met <- ggplot(ml, aes(k,v)) + geom_line(color="steelblue") + geom_point(color="steelblue",size=2) +
 geom_point(data=subset(ml,k==optimal_k),color="red",size=3) +
 facet_wrap(~M,scales="free_y",ncol=1) + scale_x_continuous(breaks=k_range) +
 labs(title="Cluster Validation",subtitle=paste0("Optimal k = ",optimal_k),x="k",y="") + theme_bw()
ggsave(file.path(fig_dir,"CMeans_validation_metrics.pdf"),p_met,width=8,height=8)
ggsave(file.path(fig_dir,"CMeans_validation_metrics.png"),p_met,width=8,height=8,dpi=300)
cat(" Step1 done.\n")

# ============ STEP2: CMeans ============
cat("\n========== STEP2: CMeans k =",optimal_k,"==========\n")
set.seed(42)
cres <- e1071::cmeans(expr_z, centers=optimal_k, m=2, iter.max=100)
nonempty <- sort(unique(cres$cluster)); n_ne <- length(nonempty)
if (n_ne<optimal_k) cat(sprintf(" %d non-empty (of %d)\n",n_ne,optimal_k))
cluster_labels <- setNames(seq_len(n_ne),nonempty)[as.character(cres$cluster)]
names(cluster_labels) <- names(cres$cluster)
membership_mat <- cres$membership[,nonempty,drop=FALSE]
colnames(membership_mat) <- paste0("C",seq_len(n_ne))
centers_mat <- cres$centers[nonempty,,drop=FALSE]
rownames(centers_mat) <- paste0("C",seq_len(n_ne))
actual_k <- n_ne
cat(" Sizes:\n"); print(table(cluster_labels))
saveRDS(list(cluster=cluster_labels,membership=membership_mat,centers=centers_mat,
 iter=cres$iter,converged=cres$converged,optimal_k=actual_k,validation=val),
 file.path(work_dir,"cmeans_result.rds"))
cluster_df <- data.frame(Metabolite=names(cluster_labels),Cluster=cluster_labels,
 MaxMembership=apply(membership_mat,1,max), stringsAsFactors=FALSE)
write.csv(cluster_df,file.path(work_dir,"cmeans_cluster_assignments.csv"),row.names=FALSE)

#2a: Profile plots
cat("Profile plots...\n")
samp_ord <- c()
for (g in c("NC","CD","FE")) samp_ord <- c(samp_ord,sample_groups$Sample[sample_groups$Group==g])
plist <- list()
for (k in seq_len(actual_k)) {
 mems <- names(cluster_labels)[cluster_labels==k]
 if (length(mems)==0) next
 esub <- expr_z[mems,,drop=FALSE]; elong <- melt(esub)
 colnames(elong) <- c("Metabolite","Sample","Expression")
 elong$Cluster <- paste0("Cluster ",k)
 elong$Membership <- membership_mat[mems[elong$Metabolite],k]
 ctr <- data.frame(Metabolite="Center",Sample=colnames(expr_z),
 Expression=as.numeric(centers_mat[k,]),Cluster=paste0("Cluster ",k),Membership=1,
 stringsAsFactors=FALSE)
 pd <- rbind(elong,ctr); pd$Sample <- factor(pd$Sample,levels=samp_ord)
 p <- ggplot() +
 geom_line(data=subset(pd,Metabolite!="Center"),
 aes(x=Sample,y=Expression,group=Metabolite,color=Membership),alpha=0.25,linewidth=0.3) +
 geom_line(data=subset(pd,Metabolite=="Center"),
 aes(x=Sample,y=Expression,group=1),color="black",linewidth=1.5) +
 scale_color_gradient(low="grey80",high="darkred",limits=c(0,1)) +
 labs(title=paste0("Cluster ",k," (n=",length(mems),")"),x="Sample",y="z-score",color="Mem") +
 theme_bw(base_size=10) +
 theme(plot.title=element_text(hjust=0.5,face="bold",size=11),
 axis.text.x=element_text(angle=45,hjust=1,size=7),legend.position="right")
 plist[[k]] <- p
}
ncp <- ifelse(actual_k <=4,2, ifelse(actual_k <=6,3,4))
nrp <- ceiling(actual_k/ncp)
pp <- gridExtra::marrangeGrob(plist, nrow=nrp, ncol=ncp, top=NULL)
ggsave(file.path(fig_dir,"CMeans_profiles.pdf"),pp,width=4*ncp,height=3.5*nrp)
ggsave(file.path(fig_dir,"CMeans_profiles.png"),pp,width=4*ncp,height=3.5*nrp,dpi=300)
cat(" Profiles saved.\n")

#2b: Membership heatmap
cat("Membership heatmap...\n")
ord <- order(cluster_labels,-apply(membership_mat,1,max))
mo <- membership_mat[ord,,drop=FALSE]
col_cl <- factor(cluster_labels[ord],levels=seq_len(actual_k)); names(col_cl) <- rownames(mo)
cc <- setNames(brewer.pal(max(actual_k,3),"Set2")[seq_len(actual_k)],as.character(seq_len(actual_k)))
mcf <- circlize::colorRamp2(c(0,0.5,1),c("white","orange","darkred"))
ha_col <- HeatmapAnnotation(Cluster=col_cl,col=list(Cluster=cc),show_annotation_name=FALSE)
ha_row <- rowAnnotation(Cluster=as.character(seq_len(actual_k)),col=list(Cluster=cc),show_annotation_name=TRUE)

pdf(file.path(fig_dir,"CMeans_membership_heatmap.pdf"),width=12,height=max(4,actual_k*1.2))
ht <- Heatmap(t(mo),name="Membership",col=mcf,top_annotation=ha_col,left_annotation=ha_row,
 show_row_names=TRUE,show_column_names=FALSE,
 row_names_gp=gpar(fontsize=10,fontface="bold"),
 cluster_rows=TRUE,cluster_columns=FALSE,column_split=col_cl,
 column_title_gp=gpar(fontsize=9),heatmap_legend_param=list(direction="vertical"))
draw(ht); dev.off()
png(file.path(fig_dir,"CMeans_membership_heatmap.png"),width=3600,height=max(1200,actual_k*360),res=300)
draw(ht); dev.off()
cat(" Heatmap saved.\n")

# ============ STEP3: KEGG & WGCNA ============
cat("\n========== STEP3: KEGG & WGCNA ==========\n")
all_feat <- rownames(expr_z)
kegg_res <- list()
for (k in seq_len(actual_k)) {
 sig <- names(cluster_labels)[cluster_labels==k]
 cat(sprintf(" C%d: %d\n",k,length(sig)))
 if (length(sig)<3) { cat(" Skip.\n"); next }
 er <- tryCatch(perform_fisher_enrichment(all_feat,sig,feature_anno,"kegg",
 pvalue_threshold=1,p_adjust_method="BH"),
 error=function(e){cat(" Error:",conditionMessage(e),"\n");data.frame()})
 if (nrow(er)>0) {
 er$Cluster <- paste0("Cluster",k); kegg_res[[k]] <- er
 ns <- sum(er$enriched)
 if (ns>0) cat(sprintf(" %d enriched\n",ns)) else
 cat(sprintf(" Top: %s (p=%.4f)\n",er$Category[1],er$pvalue[1]))
 }
}
if (length(kegg_res)>0) {
 ec <- do.call(rbind,kegg_res)
 write.csv(ec,file.path(work_dir,"cmeans_cluster_kegg_enrichment.csv"),row.names=FALSE)
 tl <- lapply(kegg_res,function(d) if(nrow(d)>0) head(d[order(d$pvalue),],5) else NULL)
 te <- do.call(rbind,tl[!sapply(tl,is.null)])
 if (nrow(te)>0 && length(unique(te$Cluster))>0) {
 te$nlog <- -log10(te$pvalue); te$cat_short <- substr(te$Category,1,60)
 pe <- ggplot(te,aes(x=reorder(cat_short,Count_in_sig),y=Count_in_sig,fill=nlog)) +
 geom_bar(stat="identity")+coord_flip()+facet_wrap(~Cluster,scales="free_y",ncol=2) +
 scale_fill_gradient(low="lightblue",high="darkred",name=expression(-log[10](P))) +
 labs(title="KEGG Enrichment by CMeans Cluster",x="Pathway",y="Count")+theme_bw(base_size=11)+
 theme(plot.title=element_text(hjust=0.5,face="bold"),strip.text=element_text(face="bold"))
 ggsave(file.path(fig_dir,"CMeans_cluster_kegg_enrichment.pdf"),pe,width=12,height=6)
 ggsave(file.path(fig_dir,"CMeans_cluster_kegg_enrichment.png"),pe,width=12,height=6,dpi=300)
 cat(" Enrichment plot saved.\n")
 }
} else { write.csv(data.frame(),file.path(work_dir,"cmeans_cluster_kegg_enrichment.csv")) }

#3b: WGCNA comparison
cat("3b. WGCNA...\n")
load_wgcna <- function(f) {
 if (!file.exists(f)) return(NULL)
 e <- new.env(); load(f,envir=e)
 for (vn in c("mergedColors","moduleColors","dynamicColors"))
 if (exists(vn,envir=e)) return(get(vn,envir=e))
 if (exists("net",envir=e) && !is.null(e$net$colors)) return(e$net$colors)
 NULL
}
mc <- load_wgcna("G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData")
if (is.null(mc)) mc <- load_wgcna("G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step1_data.RData")
found_wgcna <- !is.null(mc)
if (found_wgcna) {
 cat(" WGCNA loaded.\n"); cm <- intersect(all_feat,names(mc))
 cat(sprintf(" Shared: %d\n",length(cm)))
 if (length(cm)>=10) {
 uc <- unique(mc[cm])
 cn <- ifelse(uc=="grey","Grey",paste0(toupper(substr(uc,1,1)),substr(uc,2,nchar(uc))))
 names(cn) <- uc; cl <- cluster_labels[cm]; wm <- cn[mc[cm]]
 ct <- table(CMeans=cl,WGCNA=wm); cat(" Contingency:\n"); print(ct)
 write.csv(as.data.frame.matrix(ct),file.path(work_dir,"cmeans_vs_wgcna_contingency.csv"))
 fg <- tryCatch(fisher.test(ct,simulate.p.value=TRUE,B=10000),error=function(e) list(p.value=NA))
 cat(sprintf(" Fisher p = %s\n",ifelse(is.na(fg$p.value),"NA",format(fg$p.value,digits=4))))
 fp <- data.frame()
 for (ci in rownames(ct)) for (mj in colnames(ct)) {
 a <- ct[ci,mj]; b <- sum(ct[ci,])-a; c <- sum(ct[,mj])-a; d <- sum(ct)-a-b-c
 if (a>0) {
 ft <- fisher.test(matrix(c(a,b,c,d),2),alternative="greater")
 ex <- sum(ct[ci,])*sum(ct[,mj])/sum(ct)
 fp <- rbind(fp,data.frame(CMeans=ci,WGCNA=mj,Count=a,Expected=round(ex,1),
 Fold=round(a/max(1,ex),2),p_value=ft$p.value,stringsAsFactors=FALSE))
 }
 }
 if (nrow(fp)>0) { fp$p_adj <- p.adjust(fp$p_value,"BH"); fp <- fp[order(fp$p_value),]
 write.csv(fp,file.path(work_dir,"cmeans_vs_wgcna_fisher.csv"),row.names=FALSE) }
 fd <- as.data.frame(ct); colnames(fd) <- c("CMeans","WGCNA","Count")
 um <- unique(fd$WGCNA); mcols <- setNames(c(brewer.pal(12,"Set3"),"grey60")[seq_along(um)],um)
 pb <- ggplot(fd,aes(x=CMeans,y=Count,fill=WGCNA)) +
 geom_bar(stat="identity",position="fill")+scale_fill_manual(values=mcols)+
 labs(title="CMeans vs WGCNA",x="CMeans",y="Proportion",fill="Module")+theme_bw(base_size=12)+
 theme(plot.title=element_text(hjust=0.5,face="bold"),legend.position="bottom")+
 guides(fill=guide_legend(nrow=2))
 ggsave(file.path(fig_dir,"CMeans_vs_WGCNA_proportion.pdf"),pb,width=9,height=6)
 ggsave(file.path(fig_dir,"CMeans_vs_WGCNA_proportion.png"),pb,width=9,height=6,dpi=300)
 cat(" WGCNA plot saved.\n")
 }
} else {
 cat(" WGCNA not found.\n")
 write.csv(data.frame(),file.path(work_dir,"cmeans_vs_wgcna_contingency.csv"))
 write.csv(data.frame(),file.path(work_dir,"cmeans_vs_wgcna_fisher.csv"))
}

# Summary
cat("\n========================================\n")
cat("CMeans Complete\n")
cat("========================================\n")
cat(sprintf(" k=%d, clusters=%d, metabolites=%d, WGCNA=%s\n",
 optimal_k,actual_k,nrow(expr_z),ifelse(found_wgcna,"Yes","No")))
cat(sprintf(" %s\n %s\n",work_dir,fig_dir))
for (f in list.files(work_dir,pattern="\\.(csv|rds)$")) cat(sprintf(" %s\n",file.path(work_dir,f)))
for (f in list.files(fig_dir,pattern="\\.(pdf|png)$")) cat(sprintf(" %s\n",file.path(fig_dir,f)))
cat("Done.\n")
