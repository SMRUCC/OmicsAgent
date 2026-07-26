#将HTML报告转换为PDF
html_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/report.html"
pdf_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/report.pdf"

#检查HTML文件是否存在
if (!file.exists(html_path)) {
 stop(paste("HTML文件不存在:", html_path))
}

cat(paste("HTML文件大小:", file.info(html_path)$size, "字节\n"))

#尝试直接调用wkhtmltopdf
cmd <- sprintf(
 'wkhtmltopdf --page-size A3 --margin-top15mm --margin-bottom15mm --margin-left15mm --margin-right15mm --enable-local-file-access --encoding UTF-8 "%s" "%s"',
 html_path, pdf_path
)

cat(paste("执行命令:\n", cmd, "\n\n"))

#使用system执行
exit_code <- system(cmd, intern = FALSE, ignore.stdout = FALSE, ignore.stderr = FALSE, wait = TRUE)
cat(paste("退出码:", exit_code, "\n"))

#检查PDF是否生成
if (file.exists(pdf_path)) {
 cat(paste("\nPDF成功生成:", pdf_path, "\n"))
 cat(paste("PDF文件大小:", file.info(pdf_path)$size, "字节\n"))
} else {
 cat("\nPDF生成失败，尝试其他方法...\n")
 
 #尝试用R的webshot包
 if (require(webshot, quietly = TRUE)) {
 cat("使用webshot包...\n")
 webshot::webshot(url = html_path, file = pdf_path, vwidth =1400, vheight =900)
 } else {
 cat("webshot包不可用\n")
 }
 
 if (file.exists(pdf_path)) {
 cat(paste("\nPDF成功生成:", pdf_path, "\n"))
 cat(paste("PDF文件大小:", file.info(pdf_path)$size, "字节\n"))
 } else {
 cat("所有方法均失败\n")
 }
}
