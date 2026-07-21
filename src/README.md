# Omics Data Analysis LLM Agent

基于 Ollama 大语言模型的组学数据分析 Agent，能够根据用户的研究主题自动设计分析方案，编写 R 脚本代码实现整个组学生物信息学数据分析流程。

## 项目概述

本项目是一个 VB.NET 项目，基于 .NET 10 环境，使用本地安装的 Ollama 大语言模型服务提供 LLM 接入能力。Agent 会根据用户的研究主题，设计分析方案，然后编写 R 脚本代码实现整个组学生物信息学数据分析流程，包括：

1. 表达矩阵数据预处理
2. 总体样本 PCA/PLSDA/OPLSDA 分析
3. 差异分析比对组别设计
4. LIMMA 差异比较分析
5. KEGG 生物学功能分析（富集 + GSVA）
6. 生物学性状关联分析（WGCNA）
7. 进阶分析（CMeans 模糊聚类 + bnlearn 动态贝叶斯网络 + PLS-PM 因果路径）
8. 结果表格整理（xlsx）
9. 论文初稿撰写（PDF）

## 项目结构

```
OmicsAgent/
├── OmicsAgent.vbproj          ' VB.NET 项目文件
├── app.manifest               ' 应用程序清单
├── Program.vb                 ' 主程序入口
├── Config/
│   └── AgentConfig.vb         ' INI 配置管理
├── Environment/
│   └── EnvironmentChecker.vb  ' 运行环境检查
├── Models/
│   └── AnalysisContext.vb     ' 数据模型
├── Utils/
│   ├── CsvUtils.vb            ' CSV 工具类
│   └── PathUtils.vb           ' 路径工具类
├── Tools/
│   ├── FileTool.vb            ' 文件操作 Function Calling 工具
│   └── ShellTool.vb           ' 命令行执行 Function Calling 工具
├── Knowledge/
│   └── KnowledgeBaseBuilder.vb ' 知识库构建模块
├── Modules/
│   ├── AnalysisModuleBase.vb   ' 分析模块基类
│   ├── Module1_Preprocessing.vb
│   ├── Module2_PCA.vb
│   ├── Module3_ComparisonDesign.vb
│   ├── Module4_Limma.vb
│   ├── Module5_KEGG.vb
│   ├── Module6_WGCNA.vb
│   ├── Module7_Advanced.vb
│   ├── Module8_ResultTables.vb
│   └── Module9_Report.vb
├── rscript/                    ' R 语言工具函数脚本
│   ├── preprocess_expression.R
│   ├── pca_plsda_analysis.R
│   ├── limma_diff_analysis.R
│   ├── kegg_gsva_analysis.R
│   ├── wgcna_analysis.R
│   ├── cmeans_clustering.R
│   ├── bnlearn_analysis.R
│   └── plspm_analysis.R
├── gcmodeller/                 ' R# 语言工具函数脚本
│   ├── kegg_background.R
│   └── matrix_io.R
├── python/                     ' Python 命令行工具脚本
│   └── pubmed_search.py
├── data/                       ' KEGG 通路背景模型等数据文件
├── config.ini.template         ' INI 配置文件模板
└── README.md
```

## 依赖项

### 外部工具

1. **Rscript** - R 语言脚本解释器（必需）
   - 安装 R 4.0+，并确保 Rscript 在 PATH 中或在 INI 配置中指定路径
   - 需要的 R 包：limma, ggplot2, pheatmap, VennDiagram, clusterProfiler, GSVA, WGCNA, e1071, bnlearn, igraph, plspm

2. **wkhtmltopdf** - HTML 转 PDF 工具（必需）
   - 下载地址：https://wkhtmltopdf.org/
   - 用于将 HTML 报告转换为 PDF 文件

3. **Rsharp** - R# 语言解释器（必需）
   - GCModeller 项目提供的 R 语言变体解释器
   - 用于执行 R# 脚本

4. **Python** - Python 脚本解释器（必需）
   - Python 3.10+
   - 需要的 Python 包：biopython（用于 PubMed 在线检索）

### NuGet 包

- MySql.Data - MySQL 数据库连接
- Newtonsoft.Json - JSON 序列化
- DocumentFormat.OpenXml - xlsx 表格生成

## 编译与运行

### 编译

```bash
dotnet build -c Release
```

编译后的可执行文件位于 `bin/x64/Release/net10.0/research.exe`。

### 部署目录结构

将编译后的可执行文件及其依赖项部署到以下目录结构：

```
deploy/
├── bin/
│   └── research.exe            ' 编译后的可执行程序
├── rscript/                    ' R 语言工具函数脚本
├── gcmodeller/                 ' R# 语言工具函数脚本
├── python/                     ' Python 命令行工具脚本
├── data/                       ' KEGG 通路背景模型等数据文件
└── config.ini                  ' INI 配置文件（从 config.ini.template 复制）
```

### 配置

1. 从 `config.ini.template` 复制一份 `config.ini`
2. 根据实际环境填写配置信息：
   - `[tools]` 节：填写 Rscript、wkhtmltopdf、Rsharp、Python 的路径
   - `[llm]` 节：填写 Ollama 服务 URL、模型名称、API Key
   - `[mysql]` 节：填写 PubMed 本地镜像 MySQL 数据库连接参数
   - `[literature]` 节：配置文献检索策略
   - `[analysis]` 节：配置分析参数

### 运行

```bash
research.exe --research=research.txt --expression=data.csv --annotation=anno.csv --sampleinfo=sample.csv
```

## 命令行参数

### 必需参数

- `--research=<path>` - 研究主题描述文件路径（txt 纯文本）
- `--expression=<path>` - 表达矩阵 CSV 文件路径，或包含多组学矩阵的文件夹路径
- `--annotation=<path>` - 分子注释信息 CSV 文件路径
- `--sampleinfo=<path>` - 样本元数据 CSV 文件路径，或包含多组学元数据的文件夹路径

### 可选参数

- `--reference=<path>` - 参考文献文件夹路径（文件夹内为 txt 文件）
- `--workspace=<path>` - 工作区文件夹路径（默认在表达矩阵所在位置创建 analysis 文件夹）
- `--config=<path>` - INI 配置文件路径（默认为 ./config.ini）
- `--skip-literature` - 跳过文献检索步骤
- `--skip-kb` - 跳过知识库构建步骤
- `--module=<n>` - 仅执行指定模块（1-9），多个模块用逗号分隔
- `--help` - 显示帮助信息

## 输入文件格式要求

### research 文件

纯文本文件，描述研究主题和样本数据基础信息，例如：

```
研究主题：肝癌发生发展过程中的代谢重编程机制
物种：人类（Homo sapiens）
组织来源：肝组织
样本类型：肝癌组织 vs 癌旁正常组织
研究目的：通过代谢组学分析揭示肝癌发生发展过程中的代谢通路变化，
        识别关键的差异代谢物和异常调控的代谢通路，
        为肝癌的早期诊断和治疗提供潜在的生物标志物。
```

### expression 文件

CSV 格式，行为分子表达数据，列为样本数据：
- 第一行为样本 ID
- 第一列为分子 ID
- 其他单元格为表达值

```
id,sample1,sample2,sample3,sample4
M0001,1.23,2.34,0.98,1.56
M0002,4.56,3.21,5.67,4.32
...
```

### annotation 文件

CSV 格式，分子注释信息表：
- `id` 列：分子 ID（与表达矩阵第一列对应）
- `type` 列：分子类别（rna/protein/metabolite/lipid 等）
- `name` 列：分子名称
- `class` 或 `category` 列：分子分类类别
- `kegg` 列：KEGG 数据库 ID

### sampleinfo 文件

CSV 格式，样本元数据信息表：
- `ID` 列：样本 ID（与表达矩阵第一行对应）
- `sample_name` 列：样本显示标签
- `sample_info` 列：样本分组标签
- 其他可选列：`line`（品种/菌株）、`time`（采集时间点）等

## 工作区输出结构

```
analysis/
├── research_kb/                ' 生物学知识信息
│   ├── kb.json
│   ├── reference1.txt
│   └── ...
├── analysis_modules_1/         ' 模块 1 分析结果
│   ├── conclusion.txt
│   ├── tables/
│   └── figures/
├── analysis_modules_2/         ' 模块 2 分析结果
│   ├── conclusion.txt
│   ├── tables/
│   └── figures/
├── ...
├── analysis_modules_9/         ' 模块 9 分析结果
│   ├── conclusion.txt
│   ├── tables/
│   └── figures/
└── report.pdf                  ' 最终结果报告 PDF 文件
tmp/                            ' 临时 csv 表格文件
scripts/                        ' Agent 编写的 R/Rsharp 脚本
```

## 分析模块说明

### 模块 1：表达矩阵数据预处理

预处理流程：
1. 按行做分子表达数据最小阳性值的一半做缺失值填充
2. 按列总和归一化转化为相对表达量
3. 如有必要，针对归一化后的值做 log 转换
4. 按行做中位数缩放

### 模块 2：总体样本 PCA/PLSDA/OPLSDA 分析

- PCA 主成分分析
- PLSDA 偏最小二乘判别分析
- OPLSDA 正交偏最小二乘判别分析
- 表达矩阵总体 F 检验
- 表达矩阵总体多因素 ANOVA 检验
- 基于 PCA 结果的样本重复性质量评估

### 模块 3：差异分析比对组别设计

根据用户研究主题设计差异分析的比对组别，参考 kb.json 中的生物学知识生成阶段性研究总结文件。

### 模块 4：LIMMA 差异比较分析

- 多因素 ANOVA 检验
- limma 总体 F 检验
- limma 两两比较差异分析
- 时间序列数据：将时间因素作为协变量
- 火山图（显示 top5 差异分子名称）
- 文氏图（不同比较间的差异内容）
- 差异分子热图（列按样本分组排序，行做层次聚类，颜色块标记分子分类）

### 模块 5：KEGG 生物学功能分析

- KEGG 通路富集分析
- GSVA 分析
- 富集结果条形图（按 KEGG 大分类分组）
- GSVA 总体热图（列=样本按分组排序，行=KEGG 通路按大分类分组+层次聚类+聚类树）
- GSVA 差异分析火山图、得分图

### 模块 6：生物学性状关联分析（WGCNA）

- 按 MAD 值降序排序取 top 20000 个分子
- WGCNA 共表达网络构建
- 模块与生物学性状关联分析
- 共表达模块与生物学性状值的线性回归分析
- 共表达模块分子的 KEGG 功能富集分析
- 多组学数据：下游组学 GSVA 结果作为表型数据

### 模块 7：进阶分析

- CMeans 模糊聚类
- 聚类簇 KEGG 富集分析
- 聚类簇与 WGCNA 模块关联分析
- 时间序列数据：bnlearn 动态贝叶斯网络
- 多组学数据：PLS-PM 因果路径分析

### 模块 8：结果表格整理

将中间结果 csv 表格按分析主题写入 xlsx 文件，样式要求：
- 全局 Cambria Math 11 号字体，缩放 90%
- 第一列（id 列）：浅灰色背景，斜体，黑色字体
- 第一行（注释说明）：草绿色字体
- 第二行（列标题）：深蓝色背景，白色加粗字体
- 第一列 + 第二行 freeze panes 冻结

### 模块 9：论文初稿撰写

- 以中文撰写分析结果报告
- 每章插图和表格编写图注（先中文后英文翻译）
- A3 大小 HTML 文件
- 使用 wkhtmltopdf 转换为 PDF

## 注意事项

1. **每个分析模块都会创建一个新的 LLMClient 实例**，以防止 token 累积。

2. **生物学知识优先级**：阶段性生物学机制结论解读优先采用用户提供的参考文献内容（kb.json），当参考文献不存在或不足时，再使用 LLM 自身训练知识，严禁杜撰生物学知识。

3. **图表文本语言**：所有图表的图注文本内容都应该是英文的。

4. **结果文件语言**：xlsx 表格的文件名、注释文本、表格标题、列标题等所有文本信息均为英文。

5. **报告语言**：最终 PDF 报告以中文撰写，图注文本先中文后英文翻译。

## 许可证

MIT License
