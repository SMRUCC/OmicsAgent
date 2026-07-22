Imports Microsoft.VisualBasic.CommandLine
Imports OmicsAgent.AppRuntime

' ============================================================================
' 主程序入口 - 命令行参数解析与主流程编排
' ============================================================================

Module Program

    ''' <summary>命令行参数帮助文本</summary>
    Friend Const HelpText As String = "
Omics Data Analysis LLM Agent
============================
基于 Ollama 大语言模型的组学数据分析 Agent

用法:
  research [options]

必需参数:
  --research,-r=<path>    研究主题描述文件路径（txt 纯文本）
  --expression,-e=<path>  表达矩阵 CSV 文件路径，或包含多组学矩阵的文件夹路径
  --annotation,-a=<path>  分子注释信息 CSV 文件路径
  --sampleinfo,-s=<path>  样本元数据 CSV 文件路径，或包含多组学元数据的文件夹路径

可选参数:
  --reference,-k=<path>   参考文献文件夹路径（文件夹内为 txt 文件）
  --workspace,-w=<path>   工作区文件夹路径（默认在表达矩阵所在位置创建 analysis 文件夹）
  --config,-c=<path>      INI 配置文件路径（默认为 ./config.ini）
  --skip-literature       跳过文献检索步骤
  --skip-kb               跳过知识库构建步骤
  --module=<n>            仅执行指定模块（1-9），多个模块用逗号分隔
 
  --check_r               用于测试R脚本调用

  --help,-h               显示帮助信息

示例:
  research --research=research.txt --expression=data.csv --annotation=anno.csv --sampleinfo=sample.csv
  research --research=research.txt --expression=omics_folder/ --annotation=anno.csv --sampleinfo=sample_folder/ --reference=refs/

表格格式：
  
  表达矩阵 - 行为基因表达数据，列为样本数据
  分子注释 - ['id', 'type', 'name', 'kegg']
  样本信息 - ['id', 'sample_name', 'sample_info']

"

    ''' <summary>程序主入口</summary>
    Function Main(args As String()) As Integer
        ' 解析命令行参数
        Dim parsed As Opts = CommandLine.BuildFromArguments(args, NoSubCommand:=True).CreateOpts(Of Opts)

        If parsed.help Then
            Console.WriteLine(HelpText)
            Return 0
        ElseIf parsed.check_interop Then
            Dim interop As New ShellTool(parsed.LoadConfig, workspaceRoot:=App.SysTemp)
            Dim test As String = $"{AgentConfig.RScriptsDir}/__agent_check.R"
            Dim stdout As String = interop.run_rscript(test)

            Call Console.WriteLine("Rscript output:")
            Call Console.WriteLine(stdout)

            Return 0
        End If

        ' 验证必需参数
        If Not parsed.ValidateRequiredArgs() Then
            Return 1
        End If

        Try
            Return Workflow.Run(parsed).GetAwaiter.GetResult
        Catch ex As Exception
            Console.Error.WriteLine($"FATAL ERROR: {ex.Message}")
            Console.Error.WriteLine(ex.StackTrace)
            Return -1
        End Try
    End Function
End Module
