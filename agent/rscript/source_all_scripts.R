# =============================================================================
# source_all_scripts.R
# -----------------------------------------------------------------------------
# OmicsFlow 分析流程引导脚本
#
# 功能：扫描 rscript/ 目录下（含所有子目录）的全部 R 脚本，并通过
#       source() 将其中的函数/对象统一加载到当前 R 环境中，供分析流程调用。
#
# 设计要点：
#   1. 自动递归扫描 *.R / *.r 文件，无需手工维护文件清单；
#   2. 自动跳过本脚本自身（source_all_scripts.R）和安装脚本
#      （install_packages.R），避免重复触发安装/加载逻辑；
#   3. 支持指定依赖顺序：被依赖的底层工具脚本（utils/）优先加载，
#      可通过 source_order 定制；其余脚本按文件名排序后加载；
#   4. 逐文件 source()，单文件出错不中断整体，尾部给出加载汇总；
#   5. 仅 source 函数/对象定义，不执行任何分析（脚本均不含顶层执行代码）。
#
# 用法：
#   # 在 R 中（建议先运行 install_packages.R 安装依赖）
#   source("rscript/source_all_scripts.R")
#   或
#   Rscript -e 'source("rscript/source_all_scripts.R")'
# =============================================================================

# -----------------------------------------------------------------------------
# 0. 准备工作：定位本脚本所在目录（即 rscript/ 根目录）
# -----------------------------------------------------------------------------
# 鲁棒定位本脚本真实路径，需覆盖三种调用场景：
#   a) Rscript -e 'source(".../source_all_scripts.R")'          —— 顶层 source
#   b) Rscript xxx/verify.R 内部再 source(".../source_all_scripts.R")  —— 嵌套 source
#   c) 交互式 source()
# 之前仅用 sys.frame(1)$ofile 或 --file=，在场景 (b) 下会把"调用方脚本"误判
# 为本脚本，导致 script_dir 指向调用方目录、递归扫描并无限递归 source 自身，
# 触发 "evaluation nested too deeply: infinite recursion"。
# 修复：回溯整个调用栈 (sys.frames) 找到 ofile 以本文件名为结尾的 frame。
this_file <- tryCatch(
  {
    self_name <- "source_all_scripts.R"
    # 1) 在调用栈中查找本脚本自身被 source 的 frame
    nframes <- sys.nframe()
    found <- NULL
    if (nframes >= 1) {
      for (i in seq_len(nframes)) {
        of <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
        if (!is.null(of) && tolower(basename(of)) == tolower(self_name)) {
          found <- of
          break
        }
      }
    }
    if (!is.null(found)) {
      found
    } else {
      # 2) 退而使用 --file= 命令行参数（仅直接 Rscript 运行时有效）
      args <- commandArgs(trailingOnly = FALSE)
      file_arg <- grep("^--file=", args, value = TRUE)
      if (length(file_arg) > 0) {
        sub("^--file=", "", file_arg[1])
      } else {
        # 3) 最后回退：使用当前工作目录下的 rscript 目录
        file.path(getwd(), "rscript", self_name)
      }
    }
  },
  error = function(e) file.path(getwd(), "rscript", "source_all_scripts.R")
)

script_dir <- dirname(normalizePath(this_file))
cat(sprintf("[init] 脚本根目录: %s\n", script_dir))

# -----------------------------------------------------------------------------
# 1. 递归扫描所有 R 脚本（*.R / *.r）
# -----------------------------------------------------------------------------
all_r_files <- list.files(
  path = script_dir,
  pattern = "\\.[Rr]$",
  recursive = TRUE,
  full.names = TRUE
)

if (length(all_r_files) == 0) {
  stop("[scan] 在 ", script_dir, " 下未找到任何 R 脚本。")
}

# 标准化为相对路径，便于过滤与排序展示
# 注意：normalizePath 在 Windows 上返回反斜杠，统一转为正斜杠后再剥离根目录前缀，
#       否则 rel_files 会退化为绝对路径，导致后续按 "^utils/" 排序的规则失效。
norm_root <- gsub("\\\\", "/", normalizePath(script_dir, winslash = "/"))
norm_all <- gsub("\\\\", "/", normalizePath(all_r_files, winslash = "/"))
rel_files <- sub(paste0("^", norm_root, "/?"), "", norm_all)

cat(sprintf("[scan] 共发现 %d 个 R 脚本文件。\n", length(all_r_files)))

# -----------------------------------------------------------------------------
# 2. 过滤：跳过引导/安装类脚本（自身、install_packages.R）
# -----------------------------------------------------------------------------
# 需要排除的文件名（不含路径，大小写不敏感）
# install_packages.R 含顶层安装逻辑，source 时会触发联网安装，必须排除
exclude_names <- c(
  "source_all_scripts.R",
  "install_packages.R"
)

to_exclude <- function(rel_path) {
  base <- basename(rel_path)
  tolower(base) %in% tolower(exclude_names)
}

keep_idx <- !sapply(rel_files, to_exclude)
script_files <- all_r_files[keep_idx]
rel_keep <- rel_files[keep_idx]

cat(sprintf("[filter] 排除引导脚本后，待加载 %d 个文件。\n", length(script_files)))

# -----------------------------------------------------------------------------
# 3. 加载顺序调整：底层工具脚本优先
#    utils/ 目录中的函数被其他脚本依赖（如 load_expression_matrix、
#    make_group_colors 等），优先 source 可减少运行时未定义风险。
# -----------------------------------------------------------------------------
source_order_prefix <- c("^utils/", "^qcqa/")

ordered_rel <- c()
for (pat in source_order_prefix) {
  hit <- rel_keep[grep(pat, rel_keep)]
  ordered_rel <- c(ordered_rel, hit)
}
# 其余脚本按相对路径排序补充
rest <- setdiff(rel_keep, ordered_rel)
ordered_rel <- c(ordered_rel, sort(rest))

# 映射到完整路径，保持与 ordered_rel 对应
ordered_full <- file.path(script_dir, ordered_rel)

# -----------------------------------------------------------------------------
# 4. 逐文件 source()，容错加载
# -----------------------------------------------------------------------------
sourced_ok <- c()
sourced_fail <- c()

for (i in seq_along(ordered_full)) {
  f <- ordered_full[i]
  r <- ordered_rel[i]
  ok <- tryCatch({
    # 使用绝对路径 source，避免依赖调用方的工作目录
    source(f, local = FALSE, echo = FALSE, keep.source = TRUE,
           encoding = "UTF-8")
    TRUE
  }, error = function(e) {
    message(sprintf("[source] 错误: 加载 '%s' 失败 -> %s", r, conditionMessage(e)))
    FALSE
  }, warning = function(w) {
    # 警告不阻断，记录但继续
    message(sprintf("[source] 警告: 加载 '%s' -> %s", r, conditionMessage(w)))
    TRUE
  })
  
  if (isTRUE(ok)) {
    sourced_ok <- c(sourced_ok, r)
  } else {
    sourced_fail <- c(sourced_fail, r)
  }
}

# -----------------------------------------------------------------------------
# 5. 加载汇总
# -----------------------------------------------------------------------------
cat("\n==================== 脚本加载汇总 ====================\n")
cat(sprintf("扫描到脚本   : %d 个\n", length(all_r_files)))
cat(sprintf("已成功加载   : %d 个\n", length(sourced_ok)))
if (length(sourced_ok) > 0) {
  for (r in sourced_ok) cat(sprintf("  [ok]   %s\n", r))
}
cat(sprintf("加载失败     : %d 个\n", length(sourced_fail)))
if (length(sourced_fail) > 0) {
  for (r in sourced_fail) cat(sprintf("  [fail] %s\n", r))
}
cat("======================================================\n")

# 导出加载结果对象，便于后续流程检查
omicsflow_loaded <- list(
  loaded = sourced_ok,
  failed = sourced_fail,
  script_dir = script_dir
)
# 仅在全局环境中赋值（local = FALSE 时本就在全局）
if (!exists("omicsflow_loaded", envir = .GlobalEnv, inherits = FALSE)) {
  .GlobalEnv$omicsflow_loaded <- omicsflow_loaded
} else {
  assign("omicsflow_loaded", omicsflow_loaded, envir = .GlobalEnv)
}

if (length(sourced_fail) > 0) {
  warning(sprintf("有 %d 个脚本加载失败，请检查上方错误日志。", length(sourced_fail)))
} else {
  cat("[done] 全部 R 脚本已成功加载到当前环境，可调用其中函数运行分析流程。\n")
}
