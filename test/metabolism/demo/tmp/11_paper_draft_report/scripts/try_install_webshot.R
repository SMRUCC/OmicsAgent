#尝试安装webshot包并使用它转换HTML到PDF
html_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/report.html"
pdf_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/report.pdf"

cat("尝试安装webshot包...\n")
install.packages("webshot", repos = "https://cloud.r-project.org", quiet = TRUE)

cat("加载webshot...\n")
if (require(webshot, quietly = TRUE)) {
 cat("webshot加载成功\n")
 webshot::install_phantomjs()
 cat("phantomjs安装完成\n")
 webshot::webshot(url = html_path, file = pdf_path, vwidth =1400, vheight =900)
 if (file.exists(pdf_path)) {
 cat(paste("PDF成功生成:", pdf_path, "\n"))
 cat(paste("PDF文件大小:", file.info(pdf_path)$size, "字节\n"))
 } else {
 cat("PDF生成失败\n")
 }
} else {
 cat("webshot安装失败\n")
 
 #尝试使用rmarkdown
 cat("尝试使用rmarkdown生成PDF...\n")
 if (require(rmarkdown, quietly = TRUE)) {
 #将HTML转为Rmd然后渲染
 rmd_content <- paste0('---
title: "报告"
output: pdf_document
---

```{r, echo=FALSE, results="asis"}
html_content <- readLines("', html_path, '")
cat(html_content, sep = "\n")
```
')
 tmp_rmd <- tempfile(fileext = ".Rmd")
 writeLines(rmd_content, tmp_rmd)
 tryCatch({
 rmarkdown::render(tmp_rmd, output_file = pdf_path)
 if (file.exists(pdf_path)) {
 cat(paste("PDF成功生成:", pdf_path, "\n"))
 cat(paste("PDF文件大小:", file.info(pdf_path)$size, "字节\n"))
 } else {
 cat("rmarkdown渲染失败\n")
 }
 }, error = function(e) {
 cat(paste("rmarkdown错误:", e$message, "\n"))
 })
 }
}
