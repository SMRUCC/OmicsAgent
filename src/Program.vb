Imports Microsoft.VisualBasic.ApplicationServices
Imports Microsoft.VisualBasic.CommandLine
Imports Microsoft.VisualBasic.CommandLine.InteropService.SharedORM
Imports Microsoft.VisualBasic.CommandLine.Reflection
Imports OmicsAgent.AppRuntime

' ============================================================================
' 主程序入口 - 命令行参数解析与主流程编排
' ============================================================================

<CLI> Module Program

    ''' <summary>命令行参数帮助文本</summary>
    Friend Const HelpText As String = "
Omics Data Analysis LLM Agent [OmicsWorks]
==========================================
基于 Ollama 大语言模型的组学数据分析 Agent

用法:
  research [options]

必需参数:
  --research,-r=<path>    研究主题描述文件路径（txt 纯文本）

数据输入（以下两种模式互斥，必须二选一）:

  [模式一] 数据集定义文件（推荐，支持多组学）
  --dataset,-d=<path>     多组学数据集定义 JSON 文件路径

  [模式二] 传统参数（单组学）
  --expression,-e=<path>  表达矩阵 CSV 文件路径，或包含多组学矩阵的文件夹路径
  --annotation,-a=<path>  分子注释信息 CSV 文件路径
  --sampleinfo,-s=<path>  样本元数据 CSV 文件路径，或包含多组学元数据的文件夹路径

可选参数:
  --reference,-k=<path>   参考文献文件夹路径（文件夹内为 txt 文件）
  --workspace,-w=<path>   工作区文件夹路径（默认在表达矩阵所在位置创建 analysis 文件夹）
  --config,-c=<path>      INI 配置文件路径（默认为 ./config.ini）
  --skip-literature       跳过文献检索步骤
  --skip-kb               跳过知识库构建步骤
  --module=<n>            仅执行指定分析模块（1-12），多个模块用逗号分隔
                          1=预处理 2=PCA 3=比较组设计 4=差异分析 5=KEGG功能
                          6=WGCNA 7=CMeans 8=贝叶斯网络 9=PLS-PM
                          10=随机森林 11=回归分析 12=跨组学整合（仅多组学）
                          注：结果表(13)与报告(14)为必要的收尾模块，
                          每次分析结束后必定执行，不受本参数影响
  --custom-modules=<path> 自定义分析模块 JSON 文件夹路径（默认为程序根目录下的 custom_modules/ 文件夹）
  --report-format=<fmt>   报告输出格式：pdf（默认）/ docx / both，优先级高于配置文件中的 [report] format
 
  --debug-cache           [agent调试用] 程序会跳过已经存在result.json结果文件的模块的执行
  --make-report           [agent调试用] 用于调试程序的报告模块 

  --check                 [调试用] 用于测试R脚本调用

  --help,-h               显示帮助信息

示例:
  research /agent --research=research.txt --expression=data.csv --annotation=anno.csv --sampleinfo=sample.csv --reference=refs/
  research /agent --research=research.txt --dataset=input.json --reference=refs/ -w=./workspace/
  research --help

表格格式：
  
  表达矩阵 - 行为基因表达数据，列为样本数据
  分子注释 - ['id', 'type', 'name', 'kegg']
  样本信息 - ['id', 'sample_name', 'sample_info']

数据集定义文件（--dataset）格式：

  {
    ""datasets"": [
      {
        ""id"":         ""rna"",                  // 组学标识，须唯一，同时作为样本对齐宽表的列名
        ""type"":       ""transcriptome"",        // 组学类型：transcriptome/proteome/metabolome/lipidome
        ""label"":      ""肝脏转录组"",            // 展示名称（可选）
        ""expression"": ""./rna/counts.csv"",     // 表达矩阵（必需）
        ""annotation"": ""./rna/gene_anno.csv"",  // 该组学专属的分子注释表
        ""sampleinfo"": ""./meta/sample_rna.csv"",// 该组学的样本元数据
        ""unit"":       ""TPM""                   // 数据单位（可选）
      },
      {
        ""id"":         ""metab"",
        ""type"":       ""metabolome"",
        ""label"":      ""血浆代谢组(正离子)"",
        ""expression"": ""./metab/pos_matrix.csv"",
        ""annotation"": ""./metab/compound_anno.csv"",
        ""sampleinfo"": ""./meta/sample_metab.csv"",
        ""unit"":       ""peak area""
      }
    ],
    ""sample_alignment"": { ""mapping_file"": ""./meta/subject_map.csv"" }
  }

  * JSON 内的相对路径均相对该 JSON 文件所在目录解析。
  * sample_alignment 用于把不同组学的样本 ID 对齐到同一生物学个体，支持三种写法：
      1) <missing>      —— 在默认缺省的情况下认为各组学样本 ID 已一致，按同名直接一一匹配；
      2) mapping_file   —— 指定一张宽表 CSV，首列为 subject_id，其余列名与各 dataset 的 id 对应：
                             subject_id,rna,metab
                             P001,S1_R,M_001
                             P002,S2_R,M_002
      3) subject_map    —— 以内联 JSON 对象数组直接给出映射：

         ""subject_map"": [
             { ""subject_id"": ""P001"", ""rna"": ""S1_R"", ""metab"": ""M_001"" }
         ]

  * 对齐后，程序会把各组学矩阵的样本列名统一替换为 subject_id、仅保留各组学共有的个体，
    并将新矩阵写入工作区的 aligned/ 目录，后续所有分析模块均引用这些对齐后的文件。
"

    ''' <summary>程序主入口</summary>
    Public Function Main(args As String()) As Integer
        Return GetType(Program).RunCLI(App.CommandLine, executeEmpty:=AddressOf Help)
    End Function

    <ExportAPI("--check")>
    <Description("For debugging purposes, used to check if the GNU R script runtime environment is available.")>
    <Usage("--check --R=""C:\Program Files\R\R-4.5.0\bin\x64\Rscript.exe""")>
    Public Function CheckInterop(R As String, args As CommandLine) As Integer
        Dim assert As String = "Hello World!"
        Dim rscript As String = $"message('{assert}');"
        Dim testfile As String = TempFileSystem.GetAppSysTempFile(".R")
        Dim interop As New ShellTool(New AgentConfig With {.Tools = New ToolConfig With {.RscriptPath = R}}, workspaceRoot:=App.SysTemp)
        Dim stdout As String = interop.run_rscript(testfile)

        Call rscript.SaveTo(testfile)

        Call Console.WriteLine("Rscript output:")
        Call Console.WriteLine(stdout)

        If assert = stdout Then
            Call Console.WriteLine("Check success!")
        Else
            Call Console.WriteLine("Check failure!")
        End If

        Return 0
    End Function

    <ExportAPI("/report")>
    <Description("")>
    <Usage("")>
    Public Async Function Reporter(args As CommandLine) As Task(Of Integer)

    End Function

    <ExportAPI("/agent")>
    <Description("Run omics data analysis LLM agent workflow.")>
    <Usage("")>
    Public Async Function AgentMode(args As CommandLine) As Task(Of Integer)
        ' 解析命令行参数
        Dim parsed As Opts = args.CreateOpts(Of Opts)

        ' 验证必需参数
        If Not parsed.ValidateRequiredArgs() Then
            Return 1
        Else
            Return Await Workflow.Run(parsed)
        End If
    End Function

    <ExportAPI("--help")>
    <Description("Show help information about this commandline omics analysis LLM agent tool.")>
    Public Function Help() As Integer
        Console.WriteLine(HelpText)
        Return 0
    End Function
End Module
