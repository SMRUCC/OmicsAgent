Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 11: 回归分析分组预测（逻辑回归 / 线性回归）
' ============================================================================

''' <summary>
''' 回归分析分组预测模块。
''' 
''' 分析内容：
''' 1. 逻辑回归：面向分类型分组标签的分组预测，导出具体的回归方程与优势比
''' 2. 线性回归：面向连续型性状/指标，导出具体的线性方程
''' 3. 单 feature 逐一回归与多 feature 组合回归建模
''' 4. 量化指标：AUC、相关性系数、相关性 p-value、R² 与调整 R²
''' 5. 多组学场景下支持跨组学特征联合建模，方程中标注特征来源组学
''' </summary>
Public Class RegressionModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Regression Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 11

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "regression_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    ''' <summary>
    ''' 多组学场景下的回归建模补充要求。
    ''' </summary>
    ''' <remarks>
    ''' 与随机森林模块同理：基类默认要求各组学独立分析，
    ''' 但回归建模同样需要跨组学联合建模才能体现多组学分析的价值，故此处显式补充。
    ''' </remarks>
    Private Function MultiOmicsSection() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Dim list As String = _context.Datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}（{d.OmicsType}）：tmp/{d.PreprocessedFileName}") _
            .JoinBy(vbLf)

        Return $"
# 多组学建模要求（重要）
- 本模块在多组学场景下需要完成**两个层次**的建模，缺一不可：
  1. **组学内建模**：对每个组学分别独立建立回归模型，输出文件带各自的组学标识
  2. **跨组学联合建模**：把各组学筛选出的显著特征合并成一张特征矩阵，建立联合回归模型，
     输出文件统一命名为 '{CsvFileNamePrefix}combined.csv' 形式
- 参与联合建模的各组学矩阵如下：
{list}
- 各组学矩阵的样本列名已统一为 subject_id（共 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个共有个体），
  合并特征矩阵时按列名对齐即可，无需任何样本 ID 转换
- **每个特征必须标注其来源组学**：在所有系数表中增加 omics_id 与 omics_label 两列；
  导出的回归方程中，变量名须采用 '<组学id>:<分子id>' 的形式，使方程能直接体现特征来源
- 合并前必须对各组学分别做标准化（z-score），这样回归系数才具备跨组学可比性，
  可据此判断哪个组学层次的贡献更大
- 系数森林图中按来源组学对点着色
- 结论中需比较：联合模型的 AUC / R² 相对各组学单独模型是否有提升
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为回归分析设计计划，涵盖**逻辑回归**与**线性回归**两种方法。
本模块的目标是基于单个分子特征或多个分子特征的组合建立回归模型，
用于样本分组预测，并**导出具体的回归方程表达式**及 AUC、相关性、R² 等量化指标。
{MultiOmicsSection()}
# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入：读取样本信息表中的 sample_info 列作为分组标签（逻辑回归的响应变量 y）
- 上游输入（可选）：样本信息表中若存在连续型的表型/性状/时间列，则作为线性回归的响应变量
- 上游输入（可选）：读取模块 4(LIMMA 差异分析) 的差异分子列表作为候选特征的初筛来源
- 上游输入（可选）：读取模块 10(随机森林) 筛选出的重要特征，用回归方法加以验证并给出可解释的方程
- 下游输出：回归方程与预测性能结果供模块 {If(_context.IsMultiOmics, "12(跨组学整合)、", "")}13(表格) 和模块 14(报告) 引用

# 实现要求

## 1. 逻辑回归（Logistic Regression）—— 用于分组预测
- 响应变量为 sample_info 分组标签，使用 glm(family = binomial) 建模
- 分组数大于 2 时，使用多分类逻辑回归（nnet::multinom）或 one-vs-rest 策略，并说明所采用的方式
- **单变量逻辑回归**：对每个分子逐一建立单变量模型，输出结果表，至少包含：
  分子 ID、分子名称、回归系数 beta、标准误、Wald 统计量、p 值、FDR 校正后的 q 值、
  优势比 OR 及其 95% 置信区间、AUC
- **多变量逻辑回归**：使用逐步回归（step，基于 AIC）或 LASSO（glmnet）筛选特征后建立组合模型
  - 必须检查多重共线性（计算 VIF，剔除 VIF > 10 的变量）
  - 组学数据特征数常远超样本数，此时优先使用 glmnet 的 LASSO/Elastic Net 做正则化筛选，
    再用筛选后的少量特征建立可解释的普通逻辑回归模型
- **必须导出具体的回归方程表达式**，形如：
  logit(P) = ln(P/(1-P)) = beta0 + beta1*X1 + beta2*X2 + ...
  方程中的系数须填入实际估计值（保留 4 位有效数字），变量名使用可读的分子名称，
  并将该方程以纯文本形式单独保存为一个输出文件，同时在结论中完整给出
- 输出模型的 AUC 值及其 95% 置信区间、准确率、灵敏度、特异度、混淆矩阵
- 输出模型拟合优度指标：AIC、BIC、残差偏差（residual deviance）、Nagelkerke R²
- 进行 K 折交叉验证（建议 5 折或 10 折），报告交叉验证后的 AUC，避免性能高估

## 2. 线性回归（Linear Regression）—— 用于连续型响应变量
- 先检查样本信息表中是否存在连续型的表型/性状/时间列
  - 若存在，则以其为响应变量建立线性回归模型
  - 若不存在，则将分组标签按有序水平编码为数值（如对照=0、处理=1）后建立线性回归模型，
    并在结论中明确说明此编码方式及其局限性
- **单变量线性回归**：对每个分子逐一建模，输出结果表，至少包含：
  分子 ID、分子名称、斜率 beta、截距、标准误、t 统计量、p 值、FDR 校正后的 q 值、
  R²、调整 R²、Pearson 相关系数 r 及其 p 值、Spearman 相关系数 rho 及其 p 值
- **多变量线性回归**：使用逐步回归或 LASSO 筛选特征后建立组合模型，同样需检查 VIF 多重共线性
- **必须导出具体的线性方程表达式**，形如：
  Y = beta0 + beta1*X1 + beta2*X2 + ...
  方程中的系数须填入实际估计值（保留 4 位有效数字），变量名使用可读的分子名称，
  并将该方程以纯文本形式单独保存为一个输出文件，同时在结论中完整给出
- 输出 R²、调整 R²、F 统计量及其 p 值、残差标准误、AIC/BIC
- 进行残差诊断：残差正态性检验（Shapiro-Wilk）、残差与拟合值散点图检查同方差性

## 3. 量化指标汇总表
- 把上述两类模型的关键指标汇总为一张总表，便于横向比较，列至少包括：
  模型类型（logistic / linear）、建模层次（单变量 / 多变量）、组学来源、纳入特征数、
  AUC、相关性系数、相关性 p-value、R²、调整 R²、p 值、AIC
- 该汇总表是本模块的核心产出之一，文件名请使用 '{CsvFileNamePrefix}metrics_summary.csv' 形式

# 绘图要求
- 使用 ggplot2、pROC、glmnet、broom
- 必须绘制以下图形：
  - ROC 曲线图（逻辑回归模型，标注 AUC 及 95% 置信区间）
  - 系数森林图（各特征的回归系数或 OR 及其置信区间）
  - 回归拟合散点图（线性回归，含拟合直线、置信带，并在图中标注回归方程、R² 与 p 值）
  - 预测值与实测值对比图
  - 使用 LASSO 时，additionally 绘制正则化路径图与交叉验证曲线
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）：pROC、glmnet、broom、car、nnet
- 建模前使用 set.seed() 固定随机数种子，确保结果可重复
- 表达矩阵是「行=分子、列=样本」，回归建模要求「行=样本、列=特征」，
  务必先做转置，并确认转置后的样本顺序与响应变量严格一致
- 建模前对特征做标准化（z-score），使不同分子的回归系数具备可比性；
  但导出方程时须说明系数对应的是标准化后的变量
- 逻辑回归在完全分离（perfect separation）时系数会发散，
  须检测该情况并改用 Firth 惩罚回归（logistf）或正则化回归，不可直接报告发散的系数
- 单变量分析涉及大量假设检验，必须做 FDR 多重检验校正，报告 q 值
- 样本量远小于特征数是组学数据的常态，多变量普通回归此时不可直接使用，
  必须先做特征筛选或改用正则化回归，否则模型无法识别
- 重点产出：可解释的回归方程、以及方程中各分子对分组判别的量化贡献"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. 响应变量的构成情况：逻辑回归所用的分组标签及各组样本数；线性回归所用的连续型变量来源（或编码方式）
2. 单变量逻辑回归结果：显著相关的 Top 分子及其优势比 OR、95% 置信区间、p 值与 FDR 校正后的 q 值
3. 多变量逻辑回归模型：纳入了哪些分子、特征筛选方法（逐步回归/LASSO）及其依据
4. **逻辑回归方程的完整表达式**（须写出含实际系数估计值的完整方程），以及各系数的生物学解读
5. 逻辑回归模型性能：AUC 值及其 95% 置信区间、准确率、灵敏度、特异度、交叉验证后的 AUC
6. 单变量线性回归结果：与响应变量显著相关的 Top 分子及其相关系数、相关性 p-value、R²
7. 多变量线性回归模型的构成及其特征筛选依据
8. **线性回归方程的完整表达式**（须写出含实际系数估计值的完整方程），以及各系数的生物学解读
9. 线性回归模型的拟合优度：R²、调整 R²、F 统计量及其 p 值，以及残差诊断结论
10. 量化指标汇总表的解读：哪一类模型、哪一组特征组合的预测性能最优
11. 模型可靠性评估：多重共线性检查结果、是否存在过拟合、是否发生完全分离、样本量是否充足
12. 分析结果是否支持用户的研究主题，方程中的关键分子与研究背景的生物学关联性
13. 与前面模块分析结果的一致性和补充性（特别是与模块 4 差异分析、模块 10 随机森林所得分子的重合情况）"

        If _context.IsMultiOmics Then
            items &= "
14. 跨组学联合回归模型与各组学单独模型的 AUC / R² 对比，联合建模是否带来性能提升
15. 联合模型方程中各组学特征的系数大小对比，说明哪个组学层次的贡献最大"
        End If

        Return items
    End Function

End Class
