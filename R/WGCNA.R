const call_wgcna_setup = function() {
    # 加载所需R包
    library(WGCNA); # 用于加权基因共表达网络分析
    library(tidyverse); # 用于数据处理与可视化
    library(limma); # 用于相关性分析等统计功能
    library(RColorBrewer); # 用于颜色设置

    # 启用多线程加速计算
    allowWGCNAThreads();
}

const phenotype_associates = function(data.mat, MEs_cols, phenotypes, outputdir = "./") {
    for(name in names(phenotypes)) {
        # 读取表型数据
        let use.clin <-  resolve_dataframe(phenotypes[[name]]);
        let name <- tools::file_path_sans_ext(name);

        dir.create(name);

        # 模块与表型关联分析
        # 确保样本名一致（关键修改）
        let common_samples <- intersect(rownames(MEs_cols), rownames(use.clin));
        let MEs_col <- MEs_cols[common_samples, ];
        use.clin <- use.clin[common_samples, ];

        # 计算模块与表型的相关性
        let modTraitCor <- cor(MEs_col, use.clin, use = "p");
        let modTraitP <- corPvalueStudent(modTraitCor, nrow(use.clin));

        # 保存相关性结果
        write.table(
            modTraitCor,
            file = file.path(name,  "moduleTraitCor.txt"),
            quote = FALSE,
            sep = "\t"
        );
        write.table(
            modTraitP,
            file = file.path(name, "moduleTraitPvalue.txt"),
            quote = FALSE,
            sep = "\t"
        );

        # 保存模块-表型关联热图为PDF
        pdf(file.path(name, "module_trait_heatmap.pdf"), width = 20, height = 8)
        par(mfrow = c(1, 1), mar = c(5, 8, 4, 2) + 0.1)
        let colors <- colorRampPalette(c("blue", "white", "red"))(50)
        let textMatrix <- paste0(signif(modTraitCor, 2), "\n(", signif(modTraitP, 1), ")")
        dim(textMatrix) <- dim(modTraitCor)

        labeledHeatmap(
            Matrix = modTraitCor,
            xLabels = colnames(use.clin),
            yLabels = colnames(MEs_col),
            cex.lab = 0.8,  # 增大标签大小
            ySymbols = gsub("ME", "", colnames(MEs_col)),
            colorLabels = FALSE,
            colors = colors,
            textMatrix = textMatrix,
            setStdMargins = FALSE,
            cex.text = 0.6,  # 调整文本大小
            zlim = c(-1, 1),
            main = "Module-trait relationships"
        )
        dev.off()

        # 基因与模块/表型关联分析
        let nSamples <- nrow(data.mat)
        let geneModuleMembership <- cor(data.mat, MEs_col, use = "p")
        let MMPvalue <- corPvalueStudent(geneModuleMembership, nSamples)

        let geneSignificanceCor <- cor(data.mat, use.clin, use = "p")
        let geneSignificanceP <- corPvalueStudent(geneSignificanceCor, nSamples)

        # 可视化目标模块中基因的MM与GS关系
        # 选择与表型最相关的模块
        for(target_trait in colnames(use.clin)) {
            let module_trait_cor <- modTraitCor[, target_trait]
            let target_module <- rownames(modTraitCor)[which.max(abs(module_trait_cor))]
            
            # 提取目标模块信息
            let module_color <- gsub("ME", "", target_module)
            let moduleGenes <- names(net$colors)[which(moduleColors == module_color)]
            
            # 计算MM和GS
            let MM <- geneModuleMembership[moduleGenes, target_module]
            let GS <- geneSignificanceCor[moduleGenes, target_trait]
            
            dir = file.path(name,  sprintf("target_trait/%s", target_trait));
            dir.create( dir,recursive=TRUE);
            
            # 保存散点图为PDF
            pdf(file.path(dir, "module_membership_vs_gene_significance.pdf"), width = 10, height = 8)
            verboseScatterplot(
                MM,
                GS,
                xlab = paste("Module Membership in", module_color, "module"),
                ylab = paste("Gene significance for", target_trait),
                main = paste("Module membership vs. gene significance\n"),
                abline = TRUE,
                pch = 21,
                cex.main = 1.2,
                cex.lab = 1.2,
                cex.axis = 1.2,
                col = "black",
                bg = module_color
            )
            dev.off()
        }
    }
}

const wgcna_analysis = function(data, phenotypes = list(), outputdir = "./") {
    call_wgcna_setup();

    # 数据预处理：转换为矩阵并处理重复基因
    let exp <- as.matrix(resolve_dataframe(data));
    # 合并重复基因（对重复基因的表达量取平均值）
    let gene_exp <- avereps(exp); # avereps函数来自limma包

    # 基因筛选：选择MAD值最大的前10000个基因
    # mad_values <- apply(gene_exp, 1, mad)
    # sorted_genes <- order(mad_values, decreasing = TRUE)
    # top_genes <- sorted_genes; #[1:min(10000, length(sorted_genes))] # 防止基因数不足10000
    # data.mat <- t(gene_exp[top_genes, ])
    let data.mat <- t(gene_exp);

    # 检查样本和基因质量
    let gsg <- goodSamplesGenes(data.mat, verbose = 3);
    if (!gsg$allOK) {
        # 可选：移除异常样本或基因
        data.mat <- data.mat[gsg$goodSamples, gsg$goodGenes];
    }

    # 样本聚类检测离群值
    let sampleTree <- hclust(dist(data.mat), method = "average");

    # 保存样本聚类图为PDF
    pdf("sample_clustering.pdf", width = 24, height = 8);
    par(mfrow = c(1, 1));
    plot(sampleTree,
        main = "Sample clustering to detect outliers",
        sub = "",
        xlab = "");
    dev.off();

    # 软阈值选择
    let type <- "unsigned";
    let powers <- c(1:10, seq(from = 12, to = 30, by = 2));
    let sft <- pickSoftThreshold(
        data.mat,
        powerVector = powers,
        networkType = type,
        verbose = 5
    );
    let power = 0;

    # 保存软阈值选择图为PDF
    pdf("soft_threshold_selection.pdf", width = 14, height = 12);
    par(mfrow = c(1, 2));
    let cex1 <- 0.85;

    # 绘制无标度拓扑拟合指数
    plot(sft$fitIndices[, 1], 
        sft$fitIndices[, 2],  # 直接使用R²值
        xlab = "Soft Threshold (power)",
        ylab = "Scale Free Topology Model Fit, R²",
        type = "n",
        main = "Scale independence");
    text(sft$fitIndices[, 1], 
        sft$fitIndices[, 2],
        labels = powers,
        cex = cex1,
        col = "red");
    abline(h = 0.85, col = "red");  # 推荐阈值线

    # 绘制平均连通性
    plot(sft$fitIndices[, 1], 
        sft$fitIndices[, 5],
        xlab = "Soft Threshold (power)",
        ylab = "Mean Connectivity",
        type = "n",
        main = "Mean connectivity");
    text(sft$fitIndices[, 1], 
        sft$fitIndices[, 5],
        labels = powers,
        cex = cex1,
        col = "red");
    dev.off();

    # 确定最佳软阈值
    if (is.na(sft$powerEstimate)) {
        power <- ifelse(type == "unsigned", 6, 12);  # 默认值
        warning("自动选择软阈值失败，使用默认值: ", power);
    } else {
        power <- sft$powerEstimate;
    }

    # 构建共表达网络
    let net <- blockwiseModules(
        data.mat,
        power = power,
        maxBlockSize = 5000,
        TOMType = type,
        minModuleSize = 30,  # 降低最小模块大小
        reassignThreshold = 0,
        mergeCutHeight = 0.25,
        deepSplit = 2,
        numericLabels = TRUE,
        pamRespectsDendro = FALSE,
        saveTOMs = TRUE,
        saveTOMFileBase = "TOM",  # 更明确的文件前缀
        verbose = 3
    );

    # 可视化模块分配结果
    let moduleColors <- labels2colors(net$colors);

    # 保存模块分配结果
    let wgcna_result <- data.frame(
        gene_id = names(net$colors),
        module = net$colors,
        color = moduleColors
    );
    write.table(wgcna_result,
                file = "wgcna_result.txt",
                quote = FALSE,
                sep = "\t");

    # 保存网络结果
    save(net, file = "wgcna_network.RData");

    # 模块特征基因分析
    let MEs_col <- net$MEs;
    colnames(MEs_col) <- paste0("ME", labels2colors(as.numeric(gsub("ME", "", colnames(MEs_col)))));
    MEs_col <- orderMEs(MEs_col);

    # 保存模块特征基因热图为PDF
    pdf("eigengene_network_heatmap.pdf", width = 10, height = 10);
    plotEigengeneNetworks(
        MEs_col,
        "Eigengene adjacency heatmap",
        marDendro = c(3, 3, 2, 4),
        marHeatmap = c(3, 4, 2, 2),
        plotDendrograms = TRUE,
        xLabelsAngle = 90
    );
    dev.off();

    for(mod_id in 1:length(net$TOMFiles)) {
        let dir = sprintf("module_%s", mod_id);
        dir.create(dir);
        
        # 保存模块树状图为PDF
        pdf(file.path(dir, "module_dendrogram.pdf"), width = 20, height = 8);
        plotDendroAndColors(
            net$dendrograms[[mod_id]],
            moduleColors[net$blockGenes[[mod_id]]],
            "Module colors",
            dendroLabels = FALSE,
            hang = 0.03,
            addGuide = TRUE,
            guideHang = 0.05
        );
        dev.off();
        
        # 加载TOM矩阵（仅第一块）
        load(net$TOMFiles[mod_id], verbose = TRUE);
        
        # 绘制网络热图（仅第一块基因）
        let dissTOM <- 1 - TOM;
        let plotTOM <- as.matrix(dissTOM^7);  # 增强差异
        diag(plotTOM) <- NA;
        
        # 保存网络热图为PDF
        pdf(file.path(dir, "network_heatmap.pdf"), width = 20, height = 20);
        TOMplot(
            plotTOM,
            net$dendrograms[[mod_id]],
            moduleColors[net$blockGenes[[mod_id]]],
            main = sprintf("Network heatmap plot (block_%s)", mod_id)
        );
        dev.off();
        
        # 导出网络到Cytoscape（仅第一块）
        let file <- "network";
        let genes <- names(net$colors[net$blockGenes[[mod_id]]]);
        
        # 检查TOM类型并转换为矩阵（如果需要）
        if(!is.matrix(TOM)) {
            TOM <- as.matrix(TOM);
        }
        
        dimnames(TOM) <- list(genes, genes);
        
        exportNetworkToCytoscape(
            TOM,
            edgeFile = file.path(dir,  paste0(file, ".edges.txt")),
            nodeFile = file.path(dir, paste0(file, ".nodes.txt")),
            weighted = TRUE,
            threshold = 0.02,  # 设置最小阈值
            nodeNames = genes,
            nodeAttr = moduleColors[net$blockGenes[[mod_id]]]
        );
    }

    # 保存模块编号与颜色的对应关系
    let module_numbers <- unique(net$colors);
    let module_colors <- labels2colors(module_numbers);
    let number_colors <- data.frame(
        Module_Number = module_numbers,
        Module_Color = module_colors
    );
    write.csv(number_colors, "module_color_mapping.csv", row.names = FALSE);

    phenotype_associates(data.mat, MEs_col, phenotypes, outputdir);
}

