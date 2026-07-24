---
name: extract_pdf_text_metadata_update
overview: 更新 python/extract_pdf_text.py，将提取字段扩展为 title/doi/year/journal/abstract/keywords/reference_list/fulltext，并按指定四行+全文格式输出 txt 结果。所有新字段均用纯正则启发式从 PDF 离线解析，fulltext 含参考文献章节。
todos:
  - id: add-extractors
    content: 新增 extract_year/extract_journal/extract_keywords/extract_reference_list 四个离线正则解析函数
    status: completed
  - id: extend-process-pdf
    content: 修改 process_pdf，加入 year/journal/keywords/reference_list 字段并调用新函数
    status: completed
    dependencies:
      - add-extractors
  - id: rewrite-output
    content: 重写 write_output_txt 为新四行+空白行+全文格式并用 json 输出
    status: completed
    dependencies:
      - extend-process-pdf
  - id: update-docs
    content: 更新脚本 docstring 与 main() argparse 说明新输出格式
    status: completed
    dependencies:
      - rewrite-output
  - id: verify
    content: 用示例 PDF 文件夹运行脚本，校验 txt 各 JSON 行可解析且格式正确
    status: completed
    dependencies:
      - update-docs
---

## 用户需求

更新 `python/extract_pdf_text.py` 脚本，将其提取的文献元数据字段扩展为：title、doi、year、journal、abstract、keywords、reference_list、fulltext。

## 产品概述

一个离线批量 PDF 文献信息提取工具（基于 PyMuPDF），对指定文件夹内的每个 PDF 生成同名 `.txt` 结果文件，且结果严格按用户指定格式排版。

## 核心特性

- 提取字段扩展：在原有 title/doi/abstract/full_text 基础上，新增 year、journal、keywords、reference_list 四个字段，全部采用离线正则启发式解析（不联网）。
- 固定输出格式：结果 txt 第一行写 title；第二行写文献元数据 `{doi, year, journal, keywords[]}` 的 JSON 字符串；第三行写 `reference: {title, doi, year, journal}[]` 参考文献数组的 JSON 字符串；第四行为空白行；第五行起为经过格式化、清理乱码后的文献全文（含参考文献章节）。
- 兼容处理：各字段允许为空/缺失，解析失败时回退为可解析的安全默认值，保证 JSON 行始终可被 `json.loads` 解析。

## 技术栈

- 语言：Python 3（保留现有脚本结构）
- 核心依赖：PyMuPDF（`fitz`，已存在），标准库 `re`、`json`、`argparse`、`pathlib`
- 全部为离线启发式解析，不引入任何联网/外部服务依赖，沿用现有工程约定

## 实现方案

整体策略：在现有 `process_pdf` / `write_output_txt` 流程上扩展，复用既有 `clean_text`、`extract_doi`、`extract_title`、`extract_abstract`、`extract_full_text` 函数，新增 4 个提取函数与重写输出函数，保持单一文件内聚、不改变命令行入口。

关键决策与权衡：

- year/journal/keywords/reference_list 均采用正则启发式，符合用户"纯离线、不联网"选择；准确率低但稳健，解析失败不抛异常，回退为空值或原始文本。
- reference_list 解析为 `{title, doi, year, journal}` 字典数组；对无法结构化拆分的条目退化为 `{title: 原始条目, doi: "", year: "", journal: ""}`，确保数组结构稳定、JSON 始终可解析。
- fulltext 保留参考文献章节（用户确认包含），直接复用 `extract_full_text` + `clean_text`，不截断。

性能与可靠性：

- 正则集中在编译期（模块级），避免重复编译；各提取函数对空文本做早返回，时间复杂度 O(n)（n 为全文长度），瓶颈在 PDF 文本抽取本身，属既有开销，无新增性能风险。
- 每个提取函数单独 try/except 包裹，单字段失败不影响其余字段与整体写入。

## 实现要点

- 新增 `import json`（模块顶部）。
- `extract_year(full_text)`：按优先级匹配 `© YYYY`、`Published YYYY`、`Received/Accepted YYYY`、首个 `19xx/20xx` 四位年份，返回字符串（如 "2021"）或 `""`。
- `extract_journal(full_text, first_page_text, doc)`：从第一页页眉/页脚文本、`Journal of ...` 模式、版权行 `© … <期刊名>` 启发式提取，返回字符串或 `""`。
- `extract_keywords(full_text)`：定位 `Keywords:`/`Key words:`/`Index Terms:` 行，按分号、逗号切分并去空白，返回 `list[str]`（无则 `[]`）。
- `extract_reference_list(full_text)`：定位 `References`/`Bibliography` 章节，按条目编号（`1.`、`[1]`、`(1)`、`1]` 等）切分条目；逐条用 `DOI_PATTERN` 取 doi、四位年份取 year、做尽力而为的 title/journal 切分，返回 `list[dict]`。
- 修改 `process_pdf` 的 `result` dict：新增 `year`、`journal`、`keywords`、`reference_list`，并依次调用上述函数；保留 `error` 字段。
- 重写 `write_output_txt`：按行拼接——

1. `result["title"]`
2. `json.dumps({"doi":..,"year":..,"journal":..,"keywords":[..]}, ensure_ascii=False)`
3. `json.dumps([{"title":..,"doi":..,"year":..,"journal":..}, ...], ensure_ascii=False)`
4. 空行
5. 清理后的 `full_text`
以 `utf-8` 写入同名 `.txt`。

- 更新文件头 docstring、`main()` 中 argparse 的 `description`/`epilog`，说明新输出格式。

## 架构设计

单文件脚本，沿用现有"提取函数 → process_pdf 聚合 → write_output_txt 输出 → main 批量调度"的线性结构，仅在数据字典与输出层扩展字段，无新增架构模式，改动范围局部可控。

## 目录结构

```
g:/OmicsWorks/agent/python/extract_pdf_text.py   # [MODIFY]
  - 顶部新增 import json
  - 新增 extract_year / extract_journal / extract_keywords / extract_reference_list 四个启发式解析函数
  - 修改 process_pdf：result 增加 year/journal/keywords/reference_list 字段并调用新函数
  - 重写 write_output_txt：改为 标题/元数据JSON/参考文献JSON/空行/全文 的固定四行+正文格式
  - 更新文件头 docstring 与 main() argparse 说明
```

## 验证方式

在任意含 PDF 的文件夹运行 `python extract_pdf_text.py <文件夹>`，检查生成的 `.txt`：

- 第一行是否为 title
- 第二、三行是否可用 `json.loads` 成功解析，且字段结构符合要求
- 第四行为空行，第五行起为清理后的全文（含参考文献）