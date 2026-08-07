---
name: omics-ml-modules-and-workflow-refactor
overview: 在 src\Modules\Standard 中新增随机森林与线性/逻辑回归两个机器学习分析模块（索引 10、11），跨组学及后续模块索引顺延；同时将结果表格模块与报告模块从 Workflow.vb 的 modulesToRun 循环中移除，改为循环结束后强制执行的必要收尾模块。
---

## 用户需求

对基于 LLM 的组学数据分析 Agent 命令行程序进行分析流程升级，包含两项改动。

## 产品概述

在现有标准分析模块体系中新增两个机器学习分析模块，用于基于单特征或多特征组合进行样本分组预测；同时调整流程编排，把结果表格整理与论文报告撰写变为每次分析必定执行的收尾环节。

## 核心功能

### 一、新增随机森林分析模块（模块 10）

- **单特征与多特征组合建模**：既做单变量逐一评估筛选，也构建多特征组合的随机森林分类模型
- **交叉验证与性能评估**：K 折交叉验证，输出 ROC 曲线与 AUC、准确率、灵敏度、特异度、混淆矩阵
- **特征重要性与标志物筛选**：输出 MeanDecreaseAccuracy（MDA）与 MeanDecreaseGini 重要性排序，给出候选生物标志物清单
- **多组学支持**：多组学场景下可合并跨组学特征联合建模，结果表中标注每个特征的来源组学
- **可视化**：重要性排序条形图、ROC 曲线图、混淆矩阵热图、袋外误差收敛曲线，同时输出 PNG（300 dpi）与 PDF

### 二、新增回归分析模块（模块 11）

- **逻辑回归**：面向二分类/多分类的分组预测，导出具体的回归方程表达式、各特征回归系数与显著性 p 值、优势比（OR）及其置信区间
- **线性回归**：面向连续型性状，导出具体的线性方程表达式、R² 与调整 R²、F 检验统计量
- **量化指标输出**：AUC 值、相关性系数、相关性 p-value、R² 等指标统一汇总为结果表
- **单特征与多特征组合**：先做单变量回归逐一评估，再构建多特征组合模型
- **多组学支持**：跨组学特征联合建模，方程中标注特征来源组学
- **可视化**：ROC 曲线图、系数森林图、回归拟合散点图、预测值与实测值对比图

### 三、模块索引重排

新的执行编号为：1-9 保持不变，10 = 随机森林，11 = 回归分析，12 = 跨组学整合（原 10），13 = 结果表格（原 11），14 = 报告（原 12），自定义 JSON 模块从 15 起（原 13）。

### 四、流程编排调整

- 结果表格整理与论文报告撰写两个模块从主循环中移除
- 改为在主循环执行完毕后按「结果表格 → 报告」顺序强制执行
- `--module` 参数不再影响这两个模块，无论指定哪些模块，二者每次都会执行
- 用户仅指定部分模块时，收尾模块需对缺失产出具备容错能力

## 技术栈

沿用现有项目技术栈，不引入任何新框架：

- **语言/平台**：VB.NET（`.vb`），项目文件 `src/OmicsAgent.vbproj`
- **架构模式**：模板方法模式。所有分析模块继承 `src/Modules/Base/AnalysisModuleBase.vb`
- **LLM 交互**：`Ollama.LLMClient`，通过 `_config.CreateLLMClient(...)` 创建，每模块独立实例以避免 token 累积
- **分析执行**：LLM 通过 `ShellTool` 的 `run_rscript` 函数调用工具编写并执行 R 脚本
- **新增 R 包依赖**（由 LLM 生成的脚本按现有惯例自动检测安装）：`randomForest`、`pROC`、`caret`、`glmnet`、`broom`

## 实现方案

### 核心策略

两个新模块完全复刻现有标准模块的实现范式：仅需重写 `ModuleName`、`ModuleIndex`、`CsvFileNamePrefix`、`GeneratePlanPromptText()`、`GetConclusionItems()` 五个成员，全部实际计算逻辑由基类驱动 LLM 生成 R 脚本完成。这是本项目既定的架构约定，不新增任何抽象层。

参考范本为 `src/Modules/Standard/Module9_PLSPM.vb` 与 `Module8_Bayesian.vb`：二者均通过私有方法（如 `MultiOmicsSection()`）拼装多组学专属提示词片段，并在提示词中显式声明「上下游衔接说明」。新模块沿用此写法。

### 关键技术决策

**决策 1：索引重排采用「全量检索 + 集中改号」而非兼容层**

新增模块占用 10、11，导致跨组学、结果表格、报告、自定义模块四者依次顺延。项目中模块索引以三种形式散布：

- `ModuleIndex` 属性值（各模块类内）
- `Workflow.CreateModule()` 的 `Select Case` 分支
- 各模块提示词文本中的「供模块 11(表格) 和模块 12(报告) 引用」等自然语言描述

提示词中的索引描述虽不影响编译，但会误导 LLM 对上下游关系的判断，必须同步修正。已确认需改动的提示词位置：`Module2_PCA.vb:69`、`Module4_Limma.vb:55,72`、`Module5_KEGG.vb:75`、`Module6_WGCNA.vb:85`、`Module7_CMeans.vb:61`、`Module8_Bayesian.vb:61`、`Module9_PLSPM.vb:67`。

不引入索引映射兼容层，因为 `--module` 是调试参数，且模块产出目录名（`FolderBaseName` = `{ModuleIndex}_{name}`）本就随索引变化，加兼容层反而制造隐式状态。

**决策 2：收尾模块通过独立方法执行，与主循环共享单次执行逻辑**

将主循环体内的「创建模块 → 缓存判断 → 执行 → 异常捕获」抽取为一个私有方法 `RunModuleAsync(moduleIdx, opts, cancellationToken)`，主循环与收尾阶段共同调用。这样避免复制粘贴出两套执行逻辑，符合 DRY，也保证 `--debug-cache`、`--make-report` 两个调试开关在收尾模块上行为一致。

**决策 3：`ParseModulesToRun` 只返回循环内模块，收尾模块硬编码**

`Opts.ParseModulesToRun()` 默认值从 `{1..12}` 改为 `{1,2,3,4,5,6,7,8,9,10,11,12}`（即含新增的 10、11 与顺延后的跨组学 12），不再包含 13、14。同时需过滤掉用户误传的 13/14，防止收尾模块被执行两次——这是本次改动最易出错的点。

**决策 4：自定义模块插入位置改为「追加到循环末尾」**

原逻辑在 `modulesToRun` 中查找索引 11 或 12 的位置并在其前插入自定义模块索引。收尾模块移出循环后，该查找逻辑失去锚点，应简化为直接追加到 `modulesToRun` 末尾——语义上等价（自定义模块仍在结果表格与报告之前执行），且代码更简单。

### 性能与可靠性

- 索引改号为纯静态字符串/常量替换，无运行时开销
- 新增两个模块使流程默认执行的模块数由 12 增至 14，每模块约 3 次 LLM 调用，需在文档中提示分析耗时相应增加
- 收尾模块的容错性已由现有代码保障：`ResultTablesModule` 在 `_context.ModuleResults.IsNullOrEmpty` 时直接跳过，逐模块 `Try/Catch` 且单模块失败不中断（`Module10_ResultTables.vb:98-118`）；`ReportModule` 的 `CollectModuleConclusions/CollectAllFigures/CollectAllTables` 均遍历 `_context.ModuleResults`，部分模块缺失时自然产出较短报告。**但 `CollectAllFigures` 与 `CollectAllTables` 直接调用 `Directory.GetFiles` 而未判断目录是否存在**，在 `--module` 只跑少量模块时可能抛 `DirectoryNotFoundException`，需补加存在性判断。

### 避免技术债

- 不新建基类、接口或配置项，完全复用 `AnalysisModuleBase`
- 不改动 `AnalysisModuleBase`、`ModuleResult`、`AnalysisContext` 的公开契约
- 文件命名沿用 `ModuleN_<Name>.vb`，但因 10、