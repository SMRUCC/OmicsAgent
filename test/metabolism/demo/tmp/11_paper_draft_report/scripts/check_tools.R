cat("检查系统中可用的HTML转PDF工具:\n\n")

#检查wkhtmltopdf
tools <- c("wkhtmltopdf", "weasyprint", "chromium", "chrome", "google-chrome", "msedge", "edge")
for (tool in tools) {
 result <- Sys.which(tool)
 if (result != "") {
 cat(sprintf("找到 %s: %s\n", tool, result))
 } else {
 cat(sprintf("未找到: %s\n", tool))
 }
}

#检查R包
cat("\n检查R包:\n")
pkgs <- c("webshot", "htmltools", "rmarkdown", "knitr")
for (pkg in pkgs) {
 if (require(pkg, quietly = TRUE, character.only = TRUE)) {
 cat(sprintf(" %s:可用\n", pkg))
 } else {
 cat(sprintf(" %s:不可用\n", pkg))
 }
}
