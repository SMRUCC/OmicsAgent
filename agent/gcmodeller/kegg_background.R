' ============================================================================
' R# 工具函数脚本 - KEGG 通路背景模型加载
' ============================================================================
' 该脚本用于加载 KEGG 通路背景模型，供富集分析和 GSVA 计算使用。
' R# 是 GCModeller 项目提供的 R 语言变体解释器。
'
' 使用方式：
'   source("kegg_background.R")
'   background <- load_kegg_background("data/kegg_pathways.xml")
' ============================================================================

imports "KEGG" from "GCModeller";
imports "background" from "phenotype_kit";

load_kegg_background <- function(file) {
    ' 加载 KEGG 通路背景模型
    ' 支持 XML 或 JSON 格式
    if (file.endsWith(".xml")) {
        background <- KEGG::loadXml(file);
    } else if (file.endsWith(".json")) {
        background <- KEGG::loadJson(file);
    } else {
        stop("Unsupported file format. Only XML and JSON are supported.");
    }
    
    cat("Loaded KEGG background with", length(background$pathways), "pathways\n");
    return(background);
}

get_pathway_categories <- function(background) {
    ' 获取 KEGG 通路的大分类信息
    ' 用于富集结果条形图按大分类分组
    categories <- list();
    for (pathway in background$pathways) {
        category <- pathway$category;
        if (is.null(categories[[category]])) {
            categories[[category]] <- c();
        }
        categories[[category]] <- c(categories[[category]], pathway$id);
    }
    return(categories);
}

if (sys.nframe() == 0) {
    args <- commandArgs(trailingOnly = TRUE);
    if (length(args) >= 1) {
        bg <- load_kegg_background(args[1]);
        cat("KEGG background loaded successfully\n");
    } else {
        cat("Usage: Rscript kegg_background.R <background_file>\n");
    }
}
