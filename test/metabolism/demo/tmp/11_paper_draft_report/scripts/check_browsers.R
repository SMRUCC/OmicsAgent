cat("检查已安装的浏览器...\n")

#检查常见浏览器路径
browsers <- c(
 "C:/Program Files/Google/Chrome/Application/chrome.exe",
 "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
 "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
 "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
 "C:/Program Files/Chromium/Application/chrome.exe",
 "C:/Users/*/AppData/Local/Google/Chrome/Application/chrome.exe",
 "C:/Users/*/AppData/Local/Microsoft/Edge/Application/msedge.exe"
)

for (browser in browsers) {
 #展开通配符
 files <- Sys.glob(browser)
 if (length(files) >0) {
 cat(sprintf("找到: %s\n", files[1]))
 }
}

#检查用户目录下的浏览器
user_home <- Sys.getenv("USERPROFILE", "")
if (user_home != "") {
 chrome_path <- file.path(user_home, "AppData", "Local", "Google", "Chrome", "Application", "chrome.exe")
 if (file.exists(chrome_path)) {
 cat(sprintf("找到Chrome: %s\n", chrome_path))
 }
 edge_path <- file.path(user_home, "AppData", "Local", "Microsoft", "Edge", "Application", "msedge.exe")
 if (file.exists(edge_path)) {
 cat(sprintf("找到Edge: %s\n", edge_path))
 }
}

cat("\n检查完成\n")
