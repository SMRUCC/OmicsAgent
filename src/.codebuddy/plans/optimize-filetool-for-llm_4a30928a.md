---
name: optimize-filetool-for-llm
overview: 为 FileTool.vb 添加更多文件系统相关的 LLM 工具函数（文件增删改查、目录操作、大文件分页读取、内容搜索等），并同步更新 AnalysisModuleBase.vb 中的工具注册。
---

现在我已经掌握了足够的信息来制定计划。让我总结关键发现并生成最终方案。

**关键发现总结：**

- `FileTool.vb` 当前有 7 个函数，使用 `<Description>` / `<Argument>` 特性标注
- 全局导入已配置 `System.IO`, `System.Linq`, `Microsoft.VisualBasic` 等
- sciBASIC 扩展方法：`.IterateAllLines`（流式逐行读取）、`.ExtensionSuffix()`、`.JoinBy()`、`.GetJson`
- 工具注册在 `AnalysisModuleBase.RegisterTools` 中，仅 `write_file` 受 `allowWriteFile` 控制
- `ResolvePath` 存在安全漏洞：注释说写入必须在工作区内，但代码未强制执行
- `peek_file` 行数硬编码为 15，无法自定义

<plan_result>
<req>

## 产品概述

扩展 OmicsAgent 项目中 `FileTool.vb` 模块的文件系统工具集，为 LLM agent 提供更完整的文件操作能力，使其能够更自主地管理工作区内的文件与目录。

## 核心功能

- **文件操作增强**：删除文件、复制文件、移动/重命名文件
- **文件信息查询**：获取文件元数据（大小、修改时间、扩展名等）
- **高级文件读取**：按行范围读取（处理大文件）、读取末尾 N 行（查看日志）、文件内容搜索（grep 风格）
- **目录操作增强**：列举子目录、检查目录存在性、删除目录、递归目录树列举
- **ZIP 压缩包操作**：压缩目录为 zip、解压 zip 到目录、列出 zip 内文件列表、读取 zip 内单个文件内容
- **现有功能改进**：`peek_file` 支持自定义行数、`ResolvePath` 强制写入边界安全检查
</req>

<tech>

## 技术栈

- 语言：VB.NET (.NET 10)
- 核心框架：sciBASIC# (Microsoft.VisualBasic.Core) — 提供扩展方法 `.IterateAllLines`, `.ExtensionSuffix()`, `.JoinBy()`, `.GetJson`
- LLM 集成：通过 `LLMClient.AddFunction(obj, functionName)` 注册函数调用工具
- 特性标注：`<Description>` / `<Argument>` (来自 `Microsoft.VisualBasic.CommandLine.Reflection`)
- 编码：UTF-8 Without BOM (`Encodings.UTF8WithoutBOM.CodePage`)

## 实现方案

### 总体策略

在 `FileTool.vb` 中新增 15 个工具函数，并改进 2 个现有函数/方法。所有新函数严格遵循现有模式：`<Description>` 特性标注、`<Argument>` 参数描述、Try-Catch 异常处理返回 JSON、通过 `ResolvePath` 解析路径、通过 `EscapeJson` 转义输出。

### 关键技术决策

1. **ResolvePath 安全强化**：添加 `enforceWorkspace` 可选参数，写入类操作（delete/copy/move）传入 `True`，读取类操作保持 `False`。当 `enforceWorkspace=True` 且路径越界时抛出 `UnauthorizedAccessException`。

2. **tail_file 内存优化**：使用 `Queue(Of String)` 作为环形缓冲区，仅保留最后 N 行在内存中，避免将整个大文件读入内存。时间复杂度 O(n)，空间复杂度 O(lineCount)。

3. **read_file_lines 流式读取**：利用 sciBASIC 的 `.IterateAllLines` 流式迭代器配合 `.Skip()` / `.Take()`，仅读取所需行范围，不加载整个文件。

4. **search_in_file 结果限制**：添加 `max_results` 参数（默认 50），使用 `.IterateAllLines` 流式逐行扫描，匹配到指定数量后停止，避免返回过多数据。

5. **list_tree 深度限制**：添加 `max_depth` 参数（默认 3），递归列举时限制深度，防止遍历超大目录树。

6. **工具注册策略**：破坏性写入操作（`delete_file`, `move_file`, `delete_directory`, `copy_file`, `create_zip`, `extract_zip`）受 `allowWriteFile` 控制；所有只读操作始终注册。

7. **ZIP 操作使用 `System.IO.Compression`**：.NET 10 内置 `System.IO.Compression` 命名空间（`ZipArchive` / `ZipArchiveEntry`），无需额外 NuGet 包。在 `FileTool.vb` 文件顶部添加 `Imports System.IO.Compression` 即可。`create_zip` 使用 `ZipFile.CreateFromDirectory` 简化实现，`extract_zip` 使用 `ZipFile.ExtractToDirectory`；`list_zip_contents` 和 `read_zip_entry` 使用 `ZipArchive` 逐条目操作。注意：`ZipFile` 便捷类位于 `System.IO.Compression.FileSystem` 程序集，需在 `.vbproj` 添加 `<PackageReference Include="System.IO.Compression.ZipFile" Version="6.0.0" />`（若 .NET 10 框架已内置则可省略）。若编译报找不到 `ZipFile`，则改用 `ZipArchive` 手动遍历实现。

## 实现注意事项

- 全局 Imports 已配置 `System.IO`, `System.Linq`, `Microsoft.VisualBasic`，无需在文件内显式导入
- `write_file` 中的 R 脚本修复逻辑（`.ExtensionSuffix("r")` → `RScriptFixer.FixEntireRScript`）保持不变
- `copy_file` 需确保目标目录存在（复用 `Directory.CreateDirectory` 模式）
- `get_file_info` 需处理文件和目录两种情况
- 所有 JSON 返回值保持与现有格式一致：`{"success": true, ...}` 或 `{"error": "..."}`
- `list_tree` 的 JSON 输出需嵌套结构表示目录层级
- ZIP 操作需在 `FileTool.vb` 顶部添加 `Imports System.IO.Compression`
- `create_zip` 若目标 zip 文件已存在则覆盖；源目录不存在时返回错误
- `extract_zip` 若目标目录已存在且非空，需注意 `ZipFile.ExtractToDirectory` 默认会抛异常，应先检查或使用 `Overwrite` 参数
- `read_zip_entry` 使用 `ZipArchiveEntry.Open()` 流式读取单个条目内容，避免整体解压
- `list_zip_contents` 返回每个条目的名称、大小、压缩后大小

## 架构设计

无新增架构模式。所有改动在现有 `FileTool` 类内完成，仅在 `AnalysisModuleBase.RegisterTools` 中新增注册调用。

## 目录结构

```
g:\OmicsWorks\src\
├── Utils\
│   └── Tools\
│       └── FileTool.vb          # [MODIFY] 核心修改文件
│           - 改进 ResolvePath: 添加 enforceWorkspace 参数
│           - 改进 peek_file: 添加可选 line_count 参数
│           - 新增 delete_file(path)
│           - 新增 copy_file(src_path, dest_path)
│           - 新增 move_file(src_path, dest_path)
│           - 新增 get_file_info(path)
│           - 新增 read_file_lines(path, start_line, line_count)
│           - 新增 tail_file(path, line_count)
│           - 新增 search_in_file(path, pattern, max_results)
│           - 新增 list_directories(dir_path)
│           - 新增 directory_exists(dir_path)
│           - 新增 delete_directory(dir_path, recursive)
│           - 新增 list_tree(dir_path, max_depth)
│           - 新增 create_zip(source_dir, zip_path)
│           - 新增 extract_zip(zip_path, dest_dir)
│           - 新增 list_zip_contents(zip_path)
│           - 新增 read_zip_entry(zip_path, entry_name)
├── Modules\
│   └── Base\
│       └── AnalysisModuleBase.vb # [MODIFY] 第402-422行 RegisterTools 方法
│           - 在 allowWriteFile 分支注册 delete_file, copy_file, move_file, delete_directory, create_zip, extract_zip
│           - 在始终注册区域注册 get_file_info, read_file_lines, tail_file, search_in_file, list_directories, directory_exists, list_tree, list_zip_contents, read_zip_entry
```

</tech>

<todolist>
<item id="fix-existing" deps="">改进 ResolvePath 添加 enforceWorkspace 安全参数，改进 peek_file 支持自定义行数参数</item>
<item id="add-file-ops" deps="fix-existing">新增文件操作工具：delete_file、copy_file、move_file、get_file_info</item>
<item id="add-file-read" deps="fix-existing">新增高级读取工具：read_file_lines、tail_file、search_in_file</item>
<item id="add-dir-ops" deps="fix-existing">新增目录操作工具：list_directories、directory_exists、delete_directory、list_tree</item>
<item id="add-zip-ops" deps="fix-existing">新增 ZIP 压缩包工具：create_zip、extract_zip、list_zip_contents、read_zip_entry（需添加 Imports System.IO.Compression）</item>
<item id="register-tools" deps="add-file-ops,add-file-read,add-dir-ops,add-zip-ops">更新 AnalysisModuleBase.RegisterTools 注册所有新工具并设置 allowWriteFile 分组</item>
</todolist>
</plan_result>