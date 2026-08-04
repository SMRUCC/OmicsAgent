Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 5: KEGG 生物学功能分析（富集 + GSVA）
' ============================================================================

''' <summary>
''' KEGG 生物学功能分析模块。
''' 
''' 分析内容：
''' 1. 基于差异分析结果，使用 kegg id 进行富集分析
''' 2. GSVA 分析，并按相同组别设计进行差异分析
''' 3. 富集结果条形图（按 KEGG 大分类分组）
''' 4. GSVA 总体热图（列=样本按分组排序，行=KEGG 通路按大分类分组+层次聚类+聚类树）
''' 5. GSVA 差异分析火山图、得分图
''' </summary>
Public Class KeggFunctionModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "KEGG Functional Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 5

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "kegg_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    ''' <summary>多组学场景下的 KEGG 功能分析补充要求</summary>
    Private Function MultiOmicsSection() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Dim annoList As String = _context.Datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}（{d.OmicsType}）：{If(d.AnnotationFile.FileExists, d.AnnotationFile, "(未提供注释表)")}") _
            .JoinBy(vbLf)

        Return $"
# 多组学功能分析要求（重要）
- 每个组学必须使用**自己专属的注释表**做 KEGG 映射，不同组学的分子编号体系不同，
  绝不能混用其他组学的注释表：
{annoList}
- 不同组学映射到 KEGG 的方式不同：基因/蛋白类走 KEGG ORTHOLOGY(K number) 或基因 ID，
  代谢物类走 KEGG COMPOUND(C number)，请按组学类型分别处理
- 富集分析与 GSVA 必须对每个组学分别独立执行，结果表带上组学标识（如 'kegg_<组学id>_enrich.csv'）
- 在各组学分别完成富集后，额外做一次**通路层面的跨组学联合映射**：
  - 统计每条 KEGG 通路分别被哪些组学显著富集或覆盖
  - 找出被两个及以上组学共同富集的通路，这些是多组学共同响应的关键通路
  - 绘制通路 x 组学的对比图（如分面条形图或点图），直观展示各通路在不同组学中的富集强度
- GSVA 得分矩阵的列名保持为 subject_id，供模块 6(WGCNA) 作为跨组学性状数据使用
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为 KEGG 生物学功能分析设计计划，包括以下内容：
1. 基于差异分子（来自模块 4）进行 KEGG 通路富集分析
   - 使用 data/ 目录中的 KEGG 背景 XML/JSON 文件
   - 使用 clusterProfiler 或类似 R 包
2. 对表达矩阵进行 GSVA（基因集变异分析）
   - 以 KEGG 通路作为基因集
   - 应用与差异分析相同的比对设计
3. 可视化：
   - 富集结果条形图（按 KEGG 大分类分组）
   - GSVA 热图（列=样本按分组排序，行=KEGG 通路按大分类分组+层次聚类+聚类树）
   - GSVA 差异分析火山图和得分图

# 上下游衔接说明
- 上游输入：读取模块 4 的差异分析结果（tables/ 目录，前缀 'limma_'）
- 上游输入：读取 data/ 目录中的 KEGG 背景数据
- 上游输入：读取模块 3 的比对设计（用于 GSVA 差异分析）
- 下游输出：GSVA 分析结果将作为模块 6(WGCNA) 的表型性状数据，结果表供模块 {If(_context.IsMultiOmics, "10(跨组学整合)、", "")}11(表格) 和模块 12(报告) 引用
{MultiOmicsSection()}
# 实现要求
- 读取模块 4 的差异分析结果（tables/ 目录）
- 读取 data/ 目录中的 KEGG 背景数据（XML 或 JSON 文件）
- 使用 clusterProfiler 执行 KEGG 通路富集分析
- 使用 GSVA 包执行 GSVA 分析
- 使用 limma 对 GSVA 得分执行差异分析（比对设计与模块 4 一致）
- 生成以下图形（PNG + PDF，300 dpi，英文标签）：
  - 富集条形图：
    * 富集通路的条形图
    * 按 KEGG 大分类分组（Metabolism、Genetic Information Processing 等）
    * 按分类着色，按基因数量调整点大小
  - GSVA 热图：
    * 列 = 样本，按样本分组排序
    * 行 = KEGG 通路
    * 按 KEGG 大分类对行分组
    * 每个分类内做层次聚类
    * 在左侧为每个分类绘制聚类树
  - GSVA 差异分析火山图
  - 显著差异通路的 GSVA 得分图
- 将富集和 GSVA 结果表保存为 CSV

# 绘图要求
- 使用 ggplot2、ComplexHeatmap、clusterProfiler、GSVA
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. KEGG 富集分析的整体结果（显著富集的通路数量、分类分布）
2. 关键富集通路的生物学意义（参考 kb.json 知识库）
3. GSVA 分析结果（通路得分在不同组别间的差异）
4. GSVA 差异分析结果（差异显著的通路）
5. 通路得分热图所展示的样本聚类模式
6. 生物学通路分析结果如何支持用户的研究主题
7. 与差异分析结果的关联性"

        If _context.IsMultiOmics Then
            items &= "
8. 逐个组学分别报告显著富集的通路（须标明组学来源与所用注释表）
9. 被两个及以上组学共同富集的通路清单，及其作为多组学共同响应枢纽的生物学解读"
        End If

        Return items
    End Function

End Class
