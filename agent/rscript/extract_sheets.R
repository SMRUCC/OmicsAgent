#!/usr/bin/env Rscript

# 加载必要的包
if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("所需的 'readxl' 包未安装。请运行 install.packages('readxl') 进行安装。")
}
library(readxl)

# 获取命令行参数 (过滤掉Rscript默认传入的前缀参数)
args <- commandArgs(trailingOnly = TRUE)

# 检查参数数量
if (length(args) < 1) {
  stop("用法: Rscript extract_sheets.R <xlsx文件路径> [输出文件夹路径]\n
       参数1: xlsx文件路径 (必填)
       参数2: 输出文件夹路径 (可选，默认为xlsx文件所在目录)")
}

# 解析参数
xlsx_path <- args[1]

# 设置默认输出目录或使用用户指定的目录
if (length(args) >= 2) {
  output_dir <- args[2]
} else {
  output_dir <- dirname(xlsx_path)
}

# 检查输入的xlsx文件是否存在
if (!file.exists(xlsx_path)) {
  stop("找不到指定的xlsx文件: ", xlsx_path)
}

# 如果输出目录不存在，则创建它
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat("已创建输出目录:", output_dir, "\n")
}

# 获取xlsx文件中的所有sheet名称
sheet_names <- excel_sheets(xlsx_path)

cat(sprintf("在文件 '%s' 中找到 %d 个sheet表格。\n", basename(xlsx_path), length(sheet_names)))

# 遍历每个sheet，读取并保存为CSV
for (sheet_name in sheet_names) {
  tryCatch({
    # 读取当前sheet的数据
    df <- read_excel(xlsx_path, sheet = sheet_name)
    
    # 构造CSV文件的完整保存路径
    csv_filename <- paste0(sheet_name, ".csv")
    csv_filepath <- file.path(output_dir, csv_filename)
    
    # 写入CSV文件 (使用UTF-8编码，防止中文乱码，不写入行名)
    write.csv(df, file = csv_filepath, row.names = FALSE, fileEncoding = "UTF-8")
    
    cat(sprintf("成功导出: %s -> %s\n", sheet_name, csv_filepath))
  }, error = function(e) {
    # 捕获并打印读取或写入过程中的错误，跳过当前sheet继续下一个
    cat(sprintf("导出sheet '%s' 时出错: %s\n", sheet_name, e$message))
  })
}

cat("所有操作已完成！\n")
