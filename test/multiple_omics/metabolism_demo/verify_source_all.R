# ==============================================================================
# 模块加载连通性验证脚本
# ==============================================================================
# 职责：单独执行 agent/rscript/source_all_scripts.R，捕获加载汇总（成功/失败清单），
#       记录哪些模块脚本无法被 source。用于测试加载器本身并暴露语法级错误。
# ==============================================================================

source("g:/OmicsWorks/test/multiple_omics/metabolism_demo/config.R", encoding = "UTF-8")

section("验证 source_all_scripts.R 加载器")

loader <- file.path(RSCRIPT_ROOT, "source_all_scripts.R")
step("加载器路径: ", loader)
step("当前工作目录: ", getwd())

source(loader, encoding = "UTF-8")

section("加载结果汇总", 2)
if (!exists("omicsflow_loaded")) {
  stop("加载器未生成 omicsflow_loaded 对象")
}

cat(sprintf("成功: %d 个\n", length(omicsflow_loaded$loaded)))
cat(sprintf("失败: %d 个\n", length(omicsflow_loaded$failed)))
if (length(omicsflow_loaded$failed) > 0) {
  for (f in omicsflow_loaded$failed) cat("  [fail]", f, "\n")
}

res <- data.frame(
  script = c(omicsflow_loaded$loaded, omicsflow_loaded$failed),
  status = c(rep("ok", length(omicsflow_loaded$loaded)),
             rep("fail", length(omicsflow_loaded$failed))),
  stringsAsFactors = FALSE
)

src_export <- file.path(RSCRIPT_ROOT, "utils/export.R")
source(src_export, encoding = "UTF-8")
export_table(res, RESULT_DIR, "00_source_all_status", use_rownames = FALSE)
step("已导出 00_source_all_status.csv")

cat("\n[done] 加载器验证完成。\n")
