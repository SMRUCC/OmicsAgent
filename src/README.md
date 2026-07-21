# OmicsAgent - LLM 驱动的组学数据分析 Agent

基于本地 Ollama 大语言模型服务的组学数据分析智能体，能够自主设计分析方案、编写 R 脚本代码、执行完整的生物信息学分析流程，并生成研究报告。

## 环境要求

- **.NET 10 SDK** 或更高版本
- **R 环境**（4.0+），需安装以下 R 包：
  - `limma`, `clusterProfiler`, `WGCNA`, `e1071`, `bnlearn`, `plspm`, `impute`
  - `ggplot2`, `pheatmap`, `FactoMineR`, `RColorBrewer`, `showtext`
  - `ropls`（用于 OPLS-DA）
- **wkhtmltopdf**（用于 HTML 转 PDF）
- **Python 3.8+**（用于 NCBI 在线检索，仅在线检索模式需要）
- **Ollama** 本地服务，已拉取支持 function calling 的模型（如 `llama3.1`, `qwen2.5`）
- **MySQL**（可选，仅本地 PubMed 镜像检索模式需要）
- **GCModeller** 的 Rsharp 工具（PubMedQueryTool 依赖）

## 项目结构

```
OmicsAgent/
├── OmicsAgent.vbproj          # VB.NET 工程文件（.NET 10）
├── Program.vb                  # 主入口，命令行参数解析
├── Config/
│   ├── AppConfig.vb            # 应用配置数据模型
│   └── EnvironmentChecker.vb   # 运行环境检查器
├── IO/
│   ├── IniFile.vb              # INI 文件读写
│   ├── CsvValidator.vb         # CSV 格式验证
│   └── WorkspaceManager.vb     # 工作区文件夹管理
├── Models/
│   └── ResearchInput.vb        # 输入数据模型
├── Knowledge/
│   ├── KnowledgeBaseBuilder.vb # 知识库构建器
│   ├── PubMedLocalSearcher.vb  # 本地 MySQL 检索
│   └── NcbiOnlineSearcher.vb   # NCBI 在线检索
├── Agent/
│   ├── OmicsAnalysisAgent.vb   # 主编排器
│   ├── AnalysisModuleBase.vb   # 分析模块基类
│   ├── RScriptRunner.vb        # R 脚本执行器
│   ├── ReportGenerator.vb      # 报告生成器
│   └── Modules/
│       ├── PreprocessingModule.vb    # 模块1: 数据预处理
│       ├── MultivariateModule.vb     # 模块2: PCA/PLSDA/OPLSDA
│       ├── DifferentialModule.vb     # 模块3: LIMMA 差异分析
│       ├── KeggEnrichmentModule.vb   # 模块4: KEGG 富集 + GSVA
│       ├── WgcnaModule.vb            # 模块5: WGCNA 共表达网络
│       ├── CMeansModule.vb           # 模块6: CMeans 软聚类
│       ├── BnlearnModule.vb          # 模块7: bnlearn 动态贝叶斯网络
│       └── PlspmModule.vb            # 模块8: PLS-PM 因果路径分析
├── Tools/
│   ├── PubMedQueryTool.vb      # PubMed 查询工具（用户提供）
│   ├── FileReadTool.vb         # 文件读取工具（LLM 函数调用）
│   ├── ShellTool.vb            # Shell 命令执行工具
│   └── RScriptTool.vb          # R 脚本执行工具
├── Utils/
│   ├── JsonHelper.vb           # JSON 辅助工具
│   └── Logger.vb               # 日志工具
├── rscript/
│   └── omics_tools.R           # R 工具函数库
├── python/
│   └── ncbi_search.py          # NCBI 在线检索脚本
└── bin/
    └── config.ini.example      # 配置文件模板
```

## 编译

```bash
cd OmicsAgent
dotnet build -c Release
```

编译产物位于 `bin/Release/net10.0/`，可执行文件名为 `research.exe`（Windows）或 `research`（Linux/macOS）。

## 使用方法

### 命令行参数

```
research --research <path> --expression <path> --annotation <path>
         --sampleinfo <path> --workspace <path>
         [--references <dir>] [--config <ini_path>]
```

| 参数 | 说明 |
|------|------|
| `--research <path>` | 研究主题描述文本文件（必填） |
| `--expression <path>` | 表达矩阵 CSV 文件或目录（必填） |
| `--annotation <path>` | 分子注释 CSV 文件（必填） |
| `--sampleinfo <path>` | 样本元数据 CSV 文件或目录（必填） |
| `--workspace <path>` | 输出工作区目录（必填） |
| `--references <dir>` | 参考文献文本文件目录（可选） |
| `--config <ini_path>` | INI 配置文件路径（可选，默认 `config.ini`） |

### 输入文件格式

#### 1. 研究主题文件（research.txt）

纯文本文件，描述研究主题、疾病、物种、组织、组学类型、是否时间序列设计等。例如：

```
研究主题：非酒精性脂肪肝病（NAFLD）的转录组学分析
疾病：NAFLD
物种：Homo sapiens
组织：肝脏活检
组学类型：转录组（RNA-seq）
实验设计：正常对照 vs 早期脂肪肝 vs 晚期纤维化，每组 10 例
时间序列：否
特殊说明：关注脂质代谢和炎症通路
```

#### 2. 表达矩阵 CSV（expression.csv）

第一列为分子 ID，其余列为样本表达值：

```csv
ID,S1,S2,S3,C1,C2,C3
gene1,5.2,5.5,5.1,4.8,4.9,5.0
gene2,7.1,7.3,7.0,6.5,6.7,6.6
...
```

#### 3. 注释文件 CSV（annotation.csv）

```csv
id,type,name,class,kegg
gene1,rna,GeneSymbol1,Enzyme,hsa:1234
gene2,rna,GeneSymbol2,Transporter,hsa:5678
...
```

#### 4. 样本信息 CSV（sampleinfo.csv）

```csv
sample_id,sample_info,time
S1,Treatment,0
S2,Treatment,0
C1,Control,0
...
```

`sample_info` 列为分组信息，`time` 列为时间点（时间序列设计时需要）。

### 运行示例

```bash
research \
  --research ./data/research.txt \
  --expression ./data/expression.csv \
  --annotation ./data/annotation.csv \
  --sampleinfo ./data/sampleinfo.csv \
  --workspace ./workspace \
  --references ./data/references \
  --config ./config.ini
```

## 工作区输出结构

```
workspace/
├── agent.log                          # Agent 运行日志
├── research_kb/
│   ├── kb.json                        # 知识库（LLM 提取的结构化知识）
│   ├── reference_01.txt               # 参考文献文本
│   └── ...
├── analysis_modules_1_preprocessing/
│   ├── conclusion.txt                 # 模块结论
│   ├── tables/                        # 结果表格 CSV
│   ├── figures/                       # 结果图 PNG
│   └── scripts/                       # 生成的 R 脚本
├── analysis_modules_2_multivariate/
│   └── ...
├── analysis_modules_3_differential/
│   └── ...
├── ...（其他模块）
├── scripts/                           # 所有 R 脚本副本
├── tmp/                               # 临时文件
├── report.html                        # HTML 报告
└── report.pdf                         # PDF 研究报告
```

## 分析流程

Agent 按以下顺序执行 8 个分析模块，每个模块创建独立的 LLM 客户端实例：

1. **数据预处理**：缺失值处理、归一化、对数转换、质量控制
2. **多元统计分析**：PCA、PLS-DA、OPLS-DA（VIP 评分）
3. **差异分析**：LIMMA 差异分子分析（含比较组设计）
4. **KEGG 富集分析**：ORA 富集 + GSVA 通路活性评分
5. **WGCNA**：加权基因共表达网络分析
6. **CMeans 软聚类**：时间序列表达模式聚类
7. **bnlearn 动态贝叶斯网络**：时间序列调控网络（仅时间序列数据）
8. **PLS-PM 因果路径分析**：通路间因果关系建模

每个模块完成后：
- 生成 R 脚本到 `scripts/` 目录
- 执行 R 脚本，输出表格到 `tables/`，图到 `figures/`
- LLM 基于结果生成 `conclusion.txt`

所有模块完成后，Agent 汇总各模块结论，生成中文研究报告（HTML + PDF）。

## LLM 函数调用工具

Agent 向 LLM 注册以下函数工具，使其具备本地操作能力：

| 工具 | 说明 |
|------|------|
| `read_file` | 读取本地文件内容 |
| `write_file` | 写入文本到文件 |
| `list_files` | 列出目录文件 |
| `run_shell` | 执行 Shell 命令 |
| `run_rscript` | 执行 R 脚本文件 |
| `write_rscript` | 保存 R 脚本到文件 |
| `list_rscript_tools` | 列出可用 R 工具脚本 |
| `search_papers` | 检索 PubMed（本地 MySQL） |
| `get_full_text` | 获取文献全文（本地 MySQL） |

## 配置说明

复制 `bin/config.ini.example` 为 `config.ini`，根据实际环境修改：

- `[tools]`：Rscript、wkhtmltopdf、Rsharp、Python 路径
- `[llm]`：Ollama 服务地址和模型名称
- `[mysql]`：PubMed 本地镜像 MySQL 配置
- `[literature]`：文献检索模式（none / local_mysql / ncbi_online）
- `[workspace]`：工具脚本目录
- `[analysis]`：分析参数阈值

## 注意事项

1. **LLM 模型选择**：推荐使用支持 function calling 的模型，如 `llama3.1`、`qwen2.5`、`mistral` 等。
2. **R 包安装**：首次运行前请确保所需 R 包已安装，可参考 `rscript/omics_tools.R` 中的 `safe_load` 函数自动安装。
3. **PubMedQueryTool 依赖**：该工具依赖 GCModeller 框架的 `Microsoft.VisualBasic.CommandLine.Reflection`、`Oracle.LinuxCompatibility.MySQL.Scripting` 等程序集，请确保 GCModeller 环境已正确配置。
4. **超时设置**：R 脚本执行默认超时 15 分钟，可在 `RScriptRunner.vb` 和 `RScriptTool.vb` 中调整。
5. **中文支持**：R 图表中文标签使用 `showtext` 包，HTML 报告使用 UTF-8 编码。
6. **PDF 生成**：使用 wkhtmltopdf 将 HTML 转为 A3 大小 PDF，确保 wkhtmltopdf 已安装并配置路径。

## 许可证

MIT License
