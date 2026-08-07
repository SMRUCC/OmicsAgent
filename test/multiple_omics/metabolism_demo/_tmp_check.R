neg <- 'g:/OmicsWorks/test/multiple_omics/metabolism_demo/cache/kegg/kegg_no_pathway_ids.txt'
cat('负结果文件存在:', file.exists(neg), '\n')
if (file.exists(neg)) {
  n <- readLines(neg, warn = FALSE)
  cat('记录的无通路化合物数:', length(n), '(预期 17)\n')
}
cat('缓存映射行数:', nrow(read.csv(
  'g:/OmicsWorks/test/multiple_omics/metabolism_demo/cache/kegg/kegg_pathway_mapping.csv')), '\n\n')

# 三套体系路径系数边界校验
for (tag in c('wgcna_module', 'kegg_pathway', 'metabolite_class')) {
  f <- sprintf('g:/OmicsWorks/test/multiple_omics/metabolism_demo/results/40_plspm_%s_inner_model.csv', tag)
  im <- read.csv(f, check.names = FALSE)
  key <- apply(cbind(pmin(im$from, im$to), pmax(im$from, im$to)), 1, paste, collapse = '||')
  sym <- sapply(split(im$path_coeff, key), function(x) if (length(x) == 2) abs(diff(x)) else 0)
  cat(sprintf('%-18s 路径数=%3d  max|beta|=%.4f  越界数=%d  最大不对称=%.2e\n',
              tag, nrow(im), max(abs(im$path_coeff)),
              sum(abs(im$path_coeff) > 1 + 1e-9), max(sym)))
}
