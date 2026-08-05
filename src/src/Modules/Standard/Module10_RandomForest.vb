Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 10: 随机森林分组预测分析（randomForest）
' ============================================================================

''' <summary>
''' 随机森林机器学习分组预测模块。
''' 
''' 分析内容：
''' 1. 单 feature 逐一评估：对每个分子单独建模，筛选具备分组判别能力的候选分子
''' 2. 多 feature 组合建模：使用筛选后的分子集合构建随机森林分类模型
''' 3. 交叉验证与性能评估：K 折交叉验证，输出 ROC/AUC、准确率、灵敏度、特异度、混淆矩阵
''' 4. 特征重要性排序：MeanDecreaseAccuracy 与 MeanDecreaseGini，输出候选生物标志物清单
''' 5. 多组学场景下支持跨组学特征联合建模，并标注每个特征的来源组学
''' </summary>
Public Class RandomForestModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Random Forest Classification"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 10

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "randomforest_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    ''' <summary>
    ''' 多组学场景下的随机森林补充要求。
    ''' </summary>
    ''' <remarks>
    ''' 基类的 OmicsScopeHint 会要求「每个组学分别独立分析」，这对多数模块成立，
    ''' 但机器学习分组预测的核心价值之一恰恰是跨组学特征联合建模。
    ''' 因此此处显式追加联合建模的要求，避免 LLM 只做各组学独立建模而遗漏联合模型。
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
  1. **组学内建模**：对每个组学分别独立建立随机森林模型，输出文件带各自的组学标识
  2. **跨组学联合建模**：把各组学筛选出的重要特征合并成一张特征矩阵，建立联合随机森林模型，
     输出文件统一命名为 '{CsvFileNamePrefix}combined.csv' 形式
- 参与联合建模的各组学矩阵如下：
{list}
- 各组学矩阵的样本列名已统一为 subject_id（共 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个共有个体），
  合并特征矩阵时按列名对齐即可，无需任何样本 ID 转换
- **每个特征必须标注其来源组学**：在所有特征重要性表中增加 omics_id 与 omics_label 两列；
  联合建模时建议特征名采用 '<组学id>:<分子id>' 的形式以避免不同组学间的分子 ID 冲突
- 特征重要性图中按来源组学对柱子着色，以直观展示各组学对分组判别的贡献
- 结论中需比较：联合模型的预测性能相对各组学单独模型是否有提升，
  以及各组学在联合模型重要特征中的占比
- 合并前必须对各组学分别做标准化（如 z-score），避免不同组学量纲差异主导模型
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为随机森林（Random Forest）机器学习分组预测分析设计计划，使用 randomForest R 包。
本模块的目标是基于单个分子特征或多个分子特征的组合，构建样本分组的预测模型，
并从中筛选出具备判别能力的候选生物标志物。
{MultiOmicsSection()}
# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入：读取样本信息表中的 sample_info 列作为分组标签（即模型的响应变量 y）
- 上游输入（可选）：读取模块 4(LIMMA 差异分析) 的差异分子列表作为候选特征的初筛来源，
  这样可显著降低特征维度并提升模型稳定性
- 上游输入（可选）：读取模块 6(WGCNA) 的模块特征基因作为降维后的特征
- 下游输出：预测模型性能与候选标志物结果供模块 {If(_context.IsMultiOmics, "12(跨组学整合)、", "")}13(表格) 和模块 14(报告) 引用

# 实现要求

## 1. 分组标签准备
- 从样本信息表的 sample_info 列提取分组标签，转换为 R 的 factor 类型
- 明确报告各分组的样本数量；若某组样本数过少（如少于 3 个），需在结论中说明并谨慎解读
- 若分组数大于 2，randomForest 原生支持多分类，无需转换为多个二分类问题

## 2. 单 feature 逐一评估
- 对每个分子单独建立随机森林模型（或计算其单变量判别指标），逐一评估其分组判别能力
- 输出单特征评估结果表，至少包含：分子 ID、分子名称、AUC、准确率、袋外误差（OOB error）
- 按 AUC 降序排列，给出 Top N（建议 20）单特征判别能力最强的分子
- 分子数量很多时（如超过 5000），为控制运行时间，可先用模块 4 的差异分子或按方差排序取高变分子做初筛，
  并在计划与结论中明确说明初筛策略

## 3. 多 feature 组合建模
- 使用筛选后的特征集合构建随机森林分类模型
- 设置 ntree（建议 500-1000）与 mtry（建议用 tuneRF 或交叉验证寻优）
- 使用递归特征消除（如 caret 的 rfe，或按重要性迭代剔除）确定最优特征子集规模
- 报告最优特征组合及其对应的模型性能

## 4. 交叉验证与性能评估
- 进行 K 折交叉验证（建议 5 折或 10 折；样本量少时使用留一法 LOOCV）
- 交叉验证必须在**特征筛选之外**进行，即特征选择须包含在交叉验证循环内部，
  否则会因信息泄漏导致性能被严重高估——这一点非常重要，请务必遵守
- 输出以下性能指标：AUC、准确率（Accuracy）、灵敏度（Sensitivity）、特异度（Specificity）、
  精确率（Precision）、F1 分数、Kappa 系数
- 输出混淆矩阵
- 多分类场景下使用 one-vs-rest 方式计算各类别的 AUC，并给出宏平均值

## 5. 特征重要性与生物标志物筛选
- 建模时设置 importance = TRUE，输出 MeanDecreaseAccuracy（MDA）与 MeanDecreaseGini 两种重要性度量
- 输出特征重要性排序表，需通过注释表把分子 ID 映射为可读的分子名称
- 综合重要性排序与交叉验证性能，给出候选生物标志物清单，并说明筛选阈值的依据

# 绘图要求
- 使用 randomForest、pROC、caret、ggplot2
- 必须绘制以下图形：
  - 特征重要性排序条形图（Top 20-30，按 MDA 排序）
  - ROC 曲线图（标注 AUC 值及其 95% 置信区间）
  - 混淆矩阵热图
  - 袋外误差（OOB error）随决策树数量增加的收敛曲线，用于验证 ntree 设置是否充分
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）：randomForest、pROC、caret
- 建模前使用 set.seed() 固定随机数种子，确保结果可重复
- 表达矩阵是「行=分子、列=样本」，而 randomForest 要求「行=样本、列=特征」，
  务必先做转置，并确认转置后的样本顺序与分组标签严格一致
- 类别不平衡时（各组样本数差异较大），使用 classwt 参数或分层抽样（sampsize）加以处理，
  并在结论中说明；此时不能只看准确率，须重点关注 AUC、F1 与 Kappa
- 样本量明显少于特征数是组学数据的常态，务必警惕过拟合：
  以交叉验证性能而非训练集性能作为模型评价依据
- 若总样本量过少（如少于 20），交叉验证结果的方差会很大，需在结论中明确说明该局限性
- 重点产出：具备分组预测能力的最小特征组合及其候选生物标志物意义"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. 分组标签的构成情况（各分组名称与样本数量），以及类别是否平衡
2. 单 feature 评估结果：判别能力最强的 Top 分子及其 AUC，说明单个分子能否独立完成分组预测
3. 多 feature 组合模型的构成：最优特征子集包含哪些分子、特征数量及其筛选依据
4. 交叉验证性能评估：AUC、准确率、灵敏度、特异度、F1 等指标的具体数值，以及混淆矩阵的解读
5. 特征重要性排序结果（MeanDecreaseAccuracy 与 MeanDecreaseGini），Top 分子的生物学意义
6. 候选生物标志物清单及其筛选阈值依据
7. 模型的可靠性评估：是否存在过拟合风险、样本量是否充足、袋外误差是否已收敛
8. 分析结果是否支持用户的研究主题，筛选出的标志物与研究背景的生物学关联性
9. 与前面模块分析结果的一致性和补充性（特别是与模块 4 差异分析所得分子的重合情况）"

        If _context.IsMultiOmics Then
            items &= "
10. 跨组学联合模型与各组学单独模型的预测性能对比，联合建模是否带来性能提升
11. 联合模型的重要特征中各组学的占比，说明哪个组学层次对分组判别的贡献最大"
        End If

        Return items
    End Function

End Class
