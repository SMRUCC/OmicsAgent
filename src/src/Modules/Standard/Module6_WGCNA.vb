Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 6: 生物学性状关联分析（WGCNA）
' ============================================================================

''' <summary>
''' 生物学性状关联分析模块（WGCNA）。
''' 
''' 分析内容：
''' 1. 默认按 MAD 值降序排序取 top 20000 个分子做 WGCNA 分析
''' 2. 根据用户研究主题和样本分组信息、元数据信息构建 WGCNA 的生物表型关联性状数据
''' 3. 多组学数据：可将下游组学数据的 GSVA 分析结果作为表型数据，
'''    与上游组学数据的分子表达数据做关联分析
''' 4. 共表达模块与生物学性状值的线性回归分析
''' 5. 共表达模块分子的 KEGG 功能富集分析
''' </summary>
Public Class WGCNAModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "WGCNA Trait Association Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 6

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "wgcna_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    ''' <summary>多组学场景下的 WGCNA 补充要求</summary>
    Private Function MultiOmicsSection() As String
        If Not _context.IsMultiOmics Then
            Return ""
        End If

        Dim datasets = _context.Datasets
        Dim list As String = datasets _
            .Select(Function(d) $"  - [{d.Id}] {d.DisplayName}（{d.OmicsType}）：tmp/{d.PreprocessedFileName}") _
            .JoinBy(vbLf)

        Dim example As String = ""

        If datasets.Count >= 2 Then
            example = $"例如：以 [{datasets(0).Id}] 的分子表达矩阵构建共表达网络，" &
                      $"以 [{datasets(1).Id}] 的 GSVA 通路得分矩阵作为性状数据；反过来再做一次。"
        End If

        Return $"
# 多组学关联分析要求（重要）
本模块在多组学场景下的核心价值，是把一个组学的共表达模块与另一个组学的功能状态关联起来。

- 分别以每个组学的表达矩阵构建各自的 WGCNA 共表达网络：
{list}
- 性状数据的构建有两个来源，都需要纳入：
  1) 样本元数据中的分组、品系、时间等列（做数值编码）
  2) **其他组学**的 GSVA 通路得分矩阵（来自模块 5），作为跨组学的功能性状
- {example}
- 列对齐要求：模块特征基因矩阵与性状矩阵的样本必须按 subject_id 对齐后再求相关，
  各矩阵列名已统一为 subject_id（共 {If(_context.SubjectIDs Is Nothing, 0, _context.SubjectIDs.Length)} 个共有个体），
  求相关前请显式按 subject_id 取交集并重排，不要依赖列的默认顺序
- 输出的模块-性状相关性热图需要清楚标明性状来自哪个组学
- 结果文件带上组学标识，如 'wgcna_<组学id>_modules.csv'、'wgcna_<组学id>_trait_cor.csv'
"
    End Function

    Protected Overrides Function GeneratePlanPromptText() As String
        Return $"为 WGCNA 共表达网络分析设计计划，包括以下内容：
1. 按 MAD（中位数绝对偏差）降序选取 top 20000 个分子
2. 构建 WGCNA 共表达网络
   - 确定软阈值幂次（soft threshold power）
   - 构建网络并识别模块
   - 计算模块特征基因（module eigengene）
3. 构建生物学性状数据（使用样本元数据中的分组、品系、时间等）
4. 分析共表达模块与生物学性状的关联
5. 模块与性状值的线性回归分析
6. 模块分子的 KEGG 功能富集分析
{MultiOmicsSection()}
# 上下游衔接说明
- 上游输入：{PreprocessedInputHint()}
- 上游输入：读取样本元数据（分组、品系、时间等列）
- 上游输入：读取模块 5 的 GSVA 得分作为表型性状数据
- 下游输出：共表达模块结果将供模块 7(CMeans) 做关联对比，模块特征基因可供模块 10(随机森林) 与模块 11(回归分析) 作为降维后的特征，结果表供模块 {If(_context.IsMultiOmics, "12(跨组学整合)、", "")}13(表格) 和模块 14(报告) 引用

# 实现要求
- 按上方「上游输入」所列路径读取预处理后的表达矩阵
- 按 MAD 降序选取 top 20000 个分子（若总数不足则全选）
- 使用 pickSoftThreshold 确定软阈值幂次
- 构建 WGCNA 网络：
  - 分块构建网络（block-wise）
  - 模块识别
  - 模块特征基因计算
- 从样本元数据构建性状数据：
  - 对 group、line、time 等列做数值编码
  - 从模块 5 加载 GSVA 得分作为性状
- 计算模块特征基因与性状的相关性（Pearson 相关 + pvalue）
- 对显著相关的性状执行模块 vs 性状的线性回归
- 对每个模块的分子执行 KEGG 富集分析
- 生成以下图形（PNG + PDF，300 dpi，英文标签）：
  - 软阈值幂次选择图
  - 模块聚类树（dendrogram）
  - 模块-性状相关性热图
  - 模块特征基因条形图
  - Hub 基因网络可视化（针对关键模块）
  - 各显著模块的 KEGG 富集点图
- 将模块结果、模块-性状相关性、KEGG 富集结果保存为 CSV

# 绘图要求
- 使用 WGCNA、ggplot2、ComplexHeatmap、clusterProfiler
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- WGCNA 内存消耗较大，必要时使用分块处理"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Dim items As String = "1. WGCNA 网络构建的整体情况（soft threshold power、模块数量、模块大小分布）
2. 模块与生物学性状的关联分析结果（哪些模块与哪些性状显著相关）
3. 关键模块的生物学功能（KEGG 富集结果，参考 kb.json 知识库）
4. Hub 基因/分子的识别
5. 共表达模块与生物学性状的线性回归分析结果
6. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关"

        If _context.IsMultiOmics Then
            items &= "
7. 逐个组学分别报告网络构建情况与关键模块（须标明组学来源）
8. 跨组学关联结果：某个组学的共表达模块与另一个组学的通路功能状态之间的显著关联，
   以及这些关联所提示的跨组学调控关系"
        End If

        Return items
    End Function

End Class
