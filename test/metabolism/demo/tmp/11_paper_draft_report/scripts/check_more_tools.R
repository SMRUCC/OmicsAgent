cat("检查pandoc:\n")
pandoc_path <- Sys.which("pandoc")
if (pandoc_path != "") {
 cat(sprintf("找到 pandoc: %s\n", pandoc_path))
 cat(system("pandoc --version", intern = TRUE)[1], "\n")
} else {
 cat("未找到 pandoc\n")
}

cat("\n检查pdfcairo:\n")
if (capabilities("cairo")) {
 cat("cairo可用\n")
} else {
 cat("cairo不可用\n")
}

cat("\n检查pagedown包:\n")
if (require(pagedown, quietly = TRUE)) {
 cat("pagedown可用\n")
} else {
 cat("pagedown不可用\n")
}

cat("\n检查可能存在的PDF工具:\n")
more_tools <- c("pandoc", "pdflatex", "xelatex", "lualatex", "tectonic", "node", "npm", "yarn")
for (tool in more_tools) {
 result <- Sys.which(tool)
 if (result != "") {
 cat(sprintf("找到 %s: %s\n", tool, result))
 }
}
