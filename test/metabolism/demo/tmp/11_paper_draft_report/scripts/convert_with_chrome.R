#使用Chrome headless模式将HTML转换为PDF
html_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/report.html"
pdf_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/report.pdf"
chrome_path <- "C:/Program Files/Google/Chrome/Application/chrome.exe"

#检查文件
cat(paste("HTML文件:", html_path, "\n"))
cat(paste("HTML文件大小:", file.info(html_path)$size, "字节\n"))
cat(paste("Chrome路径:", chrome_path, "\n"))
cat(paste("Chrome存在:", file.exists(chrome_path), "\n"))

#构建命令 -使用Chrome headless打印到PDF
cmd <- sprintf(
 '"%s" --headless --disable-gpu --print-to-pdf="%s" --no-margins --enable-local-file-access "%s"',
 chrome_path,
 pdf_path,
 html_path
)

cat(paste("执行命令:\n", cmd, "\n\n"))

#执行
exit_code <- system(cmd, intern = FALSE, ignore.stdout = FALSE, ignore.stderr = FALSE, wait = TRUE)
cat(paste("退出码:", exit_code, "\n"))

#检查PDF是否生成
if (file.exists(pdf_path)) {
 cat(paste("\nPDF成功生成:", pdf_path, "\n"))
 cat(paste("PDF文件大小:", file.info(pdf_path)$size, "字节\n"))
} else {
 cat("\n第一次尝试失败，尝试使用替代参数...\n")
 
 #使用不同的参数
 cmd2 <- sprintf(
 '"%s" --headless --print-to-pdf="%s" --window-size=1920,1080 --virtual-time-budget=5000 "file:///%s"',
 chrome_path,
 pdf_path,
 gsub("/", "\\\\", html_path)
 )
 
 cat(paste("执行命令:\n", cmd2, "\n\n"))
 exit_code2 <- system(cmd2, intern = FALSE, ignore.stdout = FALSE, ignore.stderr = FALSE, wait = TRUE)
 cat(paste("退出码:", exit_code2, "\n"))
 
 if (file.exists(pdf_path)) {
 cat(paste("\nPDF成功生成:", pdf_path, "\n"))
 cat(paste("PDF文件大小:", file.info(pdf_path)$size, "字节\n"))
 } else {
 cat("\n所有方法均失败\n")
 }
}
