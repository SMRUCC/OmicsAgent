Imports Ollama

' ============================================================================
' 模块 8: 整理结果文件（生成 xlsx 表格）
' ============================================================================

''' <summary>
''' 结果表格整理模块。
''' 
''' 将分析得到的多个中间结果 csv 表格文件，按照分析的内容主题，
''' 写入到对应的 xlsx 文件之中。
''' 
''' xlsx 表格样式要求：
''' - 全局采用 Cambria Math 11 号字体
''' - 表格缩放 90%
''' - 背景色为默认的白色
''' - 第一列（id 列）：浅灰色背景色，斜体，黑色字体颜色
''' - 第一行（注释说明文本行）：默认背景色，草绿色字体颜色
''' - 第二行（列标题行）：深蓝色背景色，白色字体颜色，加粗字体
''' - 第一列 + 第二行进行 freeze panes 冻结
''' - 所有文本信息（文件名、注释、标题、列标题）均为英文
''' </summary>
Public Class ResultTablesModule
    Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Result Tables Compilation"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 8

    Public Sub New(config As AgentConfig, context As AnalysisContext, llmFactory As Func(Of LLMClient), Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, llmFactory, logger)
    End Sub

    Protected Overrides Async Function GeneratePlanAsync(cancellationToken As CancellationToken) As Task(Of ModulePlan)
        Using llm = _llmFactory()
            RegisterTools(llm)

            Dim prompt = $"
You are a bioinformatics data analyst. Design a plan to compile result tables.

{BuildContextInfo()}

# Your Task
Design a plan to compile all intermediate CSV result tables into organized XLSX files.
1. Scan all CSV files in tmp/ and analysis_modules_*/tables/ directories
2. Group them by analysis theme:
   - Preprocessing results
   - PCA/PLSDA/OPLSDA results
   - Differential analysis results (limma)
   - KEGG enrichment and GSVA results
   - WGCNA module results
   - Advanced analysis results (CMeans, Bayesian, PLS-PM)
3. For each group, create an XLSX file with multiple sheets
4. Each sheet should have:
   - Row 1: Description/annotation text (forest green font)
   - Row 2: Column headers (dark blue background, white bold font)
   - Row 3+: Data
   - First column: light gray background, italic, black font
   - Freeze panes at B3

Return your plan as JSON:
{{
  ""module_name"": ""Result Tables Compilation"",
  ""goal"": ""<brief description>"",
  ""input_files"": [""<input file paths>""],
  ""output_files"": [""<expected output file paths>""],
  ""notes"": ""<special considerations>""
}}
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = ExtractJsonFromResponse(resp.output)
            Dim plan As ModulePlan
            If Not String.IsNullOrEmpty(json) Then
                plan = Newtonsoft.Json.JsonConvert.DeserializeObject(Of ModulePlan)(json)
            Else
                plan = New ModulePlan() With {.ModuleName = ModuleName, .Goal = resp.output}
            End If
            plan.ModuleName = ModuleName
            Return plan
        End Using
    End Function

    Protected Overrides Async Function GenerateAndRunScriptAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task
        ' 这个模块直接由 VB.NET 代码生成 xlsx 文件，不需要调用 LLM 编写脚本
        LogInfo("Compiling result tables into XLSX files...")

        ' 收集所有 CSV 结果文件
        Dim csvFiles = CollectResultCsvFiles()

        ' 按主题分组
        Dim groupedFiles = GroupCsvByTheme(csvFiles)

        ' 为每个主题生成 xlsx 文件
        For Each group In groupedFiles
            Dim xlsxPath = Path.Combine(_context.WorkspaceDir, "analysis", $"{group.Key.Replace(" "c, "_"c)}.xlsx")
            Await CreateXlsxAsync(xlsxPath, group.Value, group.Key, cancellationToken)
            LogInfo($"Created XLSX: {xlsxPath} with {group.Value.Count} sheets")
        Next

        ' 同时让 LLM 生成英文的表格注释说明
        Using llm = _llmFactory()
            Dim prompt = $"
You are a bioinformatics data analyst. Generate English descriptions for result tables.

{BuildContextInfo()}

# Your Task
For each of the following analysis themes, write a brief English description (1-2 sentences) 
that explains what data the table contains, what each column means, and what biological insights 
users can gain from the table.

Themes:
1. Preprocessing Results
2. PCA/PLSDA/OPLSDA Results
3. LIMMA Differential Analysis Results
4. KEGG Functional Analysis Results
5. WGCNA Module Results
6. Advanced Analysis Results

Return as JSON:
{{
  ""descriptions"": {{
    ""Preprocessing Results"": ""<description>"",
    ""PCA/PLSDA/OPLSDA Results"": ""<description>"",
    ...
  }}
}}
"
            Dim resp = Await llm.Chat(prompt, cancellationToken)
            Dim json = ExtractJsonFromResponse(resp.output)
            If Not String.IsNullOrEmpty(json) Then
                PathUtils.WriteAllText(Path.Combine(_context.WorkspaceDir, "analysis", "table_descriptions.json"), json)
            End If
        End Using
    End Function

    Protected Overrides Async Function GenerateConclusionAsync(plan As ModulePlan, cancellationToken As CancellationToken) As Task(Of String)
        Return "结果表格已整理完成，所有中间结果 CSV 文件已按分析主题写入对应的 XLSX 文件中。每个 XLSX 文件包含多个工作表，每个工作表的第一行为表格注释说明（草绿色字体），第二行为列标题（深蓝色背景白色加粗字体），第一列为分子 ID（浅灰色背景斜体），并已冻结窗格。"
    End Function

    ''' <summary>收集所有结果 CSV 文件</summary>
    Private Function CollectResultCsvFiles() As List(Of String)
        Dim result As New List(Of String)()
        Dim analysisDir = Path.Combine(_context.WorkspaceDir, "analysis")
        If Not Directory.Exists(analysisDir) Then Return result

        ' 收集 tmp/ 目录下的 CSV 文件
        Dim tmpDir = Path.Combine(_context.WorkspaceDir, "tmp")
        If Directory.Exists(tmpDir) Then
            result.AddRange(Directory.GetFiles(tmpDir, "*.csv"))
        End If

        ' 收集各模块 tables/ 目录下的 CSV 文件
        For Each dir As String In Directory.GetDirectories(analysisDir, "analysis_modules_*")
            Dim tablesDir = Path.Combine(dir, "tables")
            If Directory.Exists(tablesDir) Then
                result.AddRange(Directory.GetFiles(tablesDir, "*.csv"))
            End If
        Next

        Return result
    End Function

    ''' <summary>按分析主题分组 CSV 文件</summary>
    Private Function GroupCsvByTheme(csvFiles As List(Of String)) As Dictionary(Of String, List(Of String))
        Dim groups As New Dictionary(Of String, List(Of String)) From {
            {"Preprocessing_Results", New List(Of String)},
            {"PCA_Results", New List(Of String)},
            {"LIMMA_Differential_Results", New List(Of String)},
            {"KEGG_Functional_Results", New List(Of String)},
            {"WGCNA_Module_Results", New List(Of String)},
            {"Advanced_Analysis_Results", New List(Of String)}
        }

        For Each csv In csvFiles
            Dim name = Path.GetFileName(csv).ToLower()
            If name.Contains("preprocess") Or name.Contains("normalized") Then
                groups("Preprocessing_Results").Add(csv)
            ElseIf name.Contains("pca") Or name.Contains("plsda") Or name.Contains("oplsda") Then
                groups("PCA_Results").Add(csv)
            ElseIf name.Contains("diff") Or name.Contains("limma") Or name.Contains("anova") Or name.Contains("volcano") Then
                groups("LIMMA_Differential_Results").Add(csv)
            ElseIf name.Contains("kegg") Or name.Contains("gsva") Or name.Contains("enrich") Then
                groups("KEGG_Functional_Results").Add(csv)
            ElseIf name.Contains("wgcna") Or name.Contains("module") Or name.Contains("eigengene") Then
                groups("WGCNA_Module_Results").Add(csv)
            ElseIf name.Contains("cmeans") Or name.Contains("cluster") Or name.Contains("bayesian") Or name.Contains("plspm") Or name.Contains("bnlearn") Then
                groups("Advanced_Analysis_Results").Add(csv)
            Else
                ' 默认放入 LIMMA 差异分析结果
                groups("LIMMA_Differential_Results").Add(csv)
            End If
        Next

        ' 移除空组
        Dim toRemove = groups.Where(Function(g) g.Value.Count = 0).Select(Function(g) g.Key).ToList()
        For Each key In toRemove
            groups.Remove(key)
        Next

        Return groups
    End Function

    ''' <summary>创建 XLSX 文件</summary>
    Private Async Function CreateXlsxAsync(xlsxPath As String, csvFiles As List(Of String), themeName As String, cancellationToken As CancellationToken) As Task
        Await Task.Run(Sub()
                           PathUtils.EnsureDirectory(Path.GetDirectoryName(xlsxPath))
                           Using doc As SpreadsheetDocument = SpreadsheetDocument.Create(xlsxPath, SpreadsheetDocumentType.Workbook)
                               Dim wbPart = doc.AddWorkbookPart()
                               wbPart.Workbook = New Workbook()

                               ' 添加共享字符串表
                               Dim sharedStrPart = wbPart.AddNewPart(Of SharedStringTablePart)()
                               sharedStrPart.SharedStringTable = New SharedStringTable()

                               ' 添加样式表
                               Dim stylesPart = wbPart.AddNewPart(Of WorkbookStylesPart)()
                               stylesPart.Stylesheet = CreateStylesheet()

                               Dim sheets = New Sheets()
                               wbPart.Workbook.Append(sheets)

                               Dim sheetIndex = 1
                               For Each csv In csvFiles
                                   Dim sheetName = Path.GetFileNameWithoutExtension(csv)
                                   If sheetName.Length > 31 Then sheetName = sheetName.Substring(0, 31)
                                   ' 移除非法字符
                                   sheetName = sheetName.Replace(":"c, "_"c).Replace("\"c, "_"c).Replace("/"c, "_"c).Replace("?"c, "_"c).Replace("*"c, "_"c).Replace("["c, "_"c).Replace("]"c, "_"c)

                                   Dim wsPart = wbPart.AddNewPart(Of WorksheetPart)()
                                   wsPart.Worksheet = New Worksheet()

                                   Dim sd = New Sheet() With {
                                       .Id = wbPart.GetIdOfPart(wsPart),
                                       .SheetId = CType(sheetIndex, UInt32Value),
                                       .Name = sheetName
                                   }
                                   sheets.Append(sd)

                                   Dim sheetData = CreateSheetData(csv, themeName)
                                   wsPart.Worksheet.Append(sheetData)

                                   ' 添加冻结窗格
                                   Dim pane As New Pane() With {
                                       .VerticalSplit = New VerticalSplit(1),
                                       .HorizontalSplit = New HorizontalSplit(1),
                                       .TopLeftCell = New TopLeftCell("B3"),
                                       .ActivePane = PaneValues.BottomRight,
                                       .State = PaneStateValues.Frozen
                                   }
                                   wsPart.Worksheet.Append(pane)

                                   sheetIndex += 1
                               Next

                               wbPart.Workbook.Save()
                           End Using
                       End Sub)
    End Function

    ''' <summary>创建样式表</summary>
    Private Function CreateStylesheet() As Stylesheet
        Dim styles As New Stylesheet()

        ' 字体
        Dim fonts As New Fonts()
        ' 默认字体
        fonts.Append(New Font(New FontSize(New FontSize() With {.Val = 11}), New Color(New Color() With {.RGB = "FF000000"}), New FontName(New FontName() With {.Val = "Cambria Math"})))
        ' 标题字体（加粗白色）
        fonts.Append(New Font(New FontSize(New FontSize() With {.Val = 11}), New Color(New Color() With {.RGB = "FFFFFFFF"}), New FontName(New FontName() With {.Val = "Cambria Math"}), New Bold()))
        ' 注释字体（草绿色）
        fonts.Append(New Font(New FontSize(New FontSize() With {.Val = 11}), New Color(New Color() With {.RGB = "FF228B22"}), New FontName(New FontName() With {.Val = "Cambria Math"})))
        ' ID 列字体（斜体黑色）
        fonts.Append(New Font(New FontSize(New FontSize() With {.Val = 11}), New Color(New Color() With {.RGB = "FF000000"}), New FontName(New FontName() With {.Val = "Cambria Math"}), New Italic()))
        fonts.Count = CType(4, UInt32Value)

        ' 填充
        Dim fills As New Fills()
        fills.Append(New Fill(New PatternFill() With {.PatternType = PatternValues.None}))
        fills.Append(New Fill(New PatternFill() With {.PatternType = PatternValues.Gray125}))
        ' 深蓝色背景
        fills.Append(New Fill(New PatternFill(New ForegroundColor(New ForegroundColor() With {.RGB = "FF1F4E79"}) With {.Auto = True}) With {.PatternType = PatternValues.Solid}))
        ' 浅灰色背景
        fills.Append(New Fill(New PatternFill(New ForegroundColor(New ForegroundColor() With {.RGB = "FFD9D9D9"}) With {.Auto = True}) With {.PatternType = PatternValues.Solid}))
        fills.Count = CType(4, UInt32Value)

        ' 边框
        Dim borders As New Borders()
        borders.Append(New Border())
        borders.Count = CType(1, UInt32Value)

        ' 单元格格式
        Dim cellFormats As New CellFormats()
        ' 0: 默认
        cellFormats.Append(New CellFormat() With {.FontId = 0, .FillId = 0, .BorderId = 0, .ApplyFont = True})
        ' 1: 标题行（深蓝色背景，白色加粗字体）
        cellFormats.Append(New CellFormat() With {.FontId = 1, .FillId = 2, .BorderId = 0, .ApplyFont = True, .ApplyFill = True})
        ' 2: 注释行（草绿色字体）
        cellFormats.Append(New CellFormat() With {.FontId = 2, .FillId = 0, .BorderId = 0, .ApplyFont = True})
        ' 3: ID 列（浅灰色背景，斜体）
        cellFormats.Append(New CellFormat() With {.FontId = 3, .FillId = 3, .BorderId = 0, .ApplyFont = True, .ApplyFill = True})
        cellFormats.Count = CType(4, UInt32Value)

        styles.Append(fonts)
        styles.Append(fills)
        styles.Append(borders)
        styles.Append(cellFormats)

        Return styles
    End Function

    ''' <summary>从 CSV 文件创建 SheetData</summary>
    Private Function CreateSheetData(csvPath As String, themeName As String) As SheetData
        Dim data As New SheetData()
        Dim rows = CsvUtils.ReadCsv(csvPath)
        If rows.Length = 0 Then Return data

        Dim numCols = rows.Max(Function(r) r.Length)

        ' 第 1 行：注释说明文本（草绿色字体）
        Dim annotationRow = New Row() With {.RowIndex = 1}
        Dim annotationText = $"This table contains {themeName} data from the omics analysis pipeline. " &
                             $"Source: {Path.GetFileName(csvPath)}. " &
                             $"Each row represents a molecule/feature, and each column represents a sample or metric. " &
                             $"Refer to column headers below for detailed meanings."
        annotationRow.Append(CreateTextCell(1, annotationText, 2))
        For c = 2 To numCols
            annotationRow.Append(New Cell() With {.CellReference = GetCellRef(c, 1), .DataType = CellValues.String, .StyleIndex = 2})
        Next
        data.Append(annotationRow)

        ' 第 2 行：列标题（深蓝色背景，白色加粗字体）
        Dim headerRow = New Row() With {.RowIndex = 2}
        For c = 1 To numCols
            Dim value = If(c <= rows(0).Length, rows(0)(c - 1), "")
            headerRow.Append(CreateTextCell(c, value, 1, isHeader:=True))
        Next
        data.Append(headerRow)

        ' 数据行
        For r = 1 To rows.Length - 1
            Dim row = New Row() With {.RowIndex = CType(r + 2, UInt32Value)}
            For c = 1 To numCols
                Dim value = If(c <= rows(r).Length, rows(r)(c - 1), "")
                If c = 1 Then
                    ' 第一列：浅灰色背景，斜体
                    row.Append(CreateTextCell(c, value, 3))
                Else
                    ' 尝试作为数字
                    Dim num As Double
                    If Double.TryParse(value, num) Then
                        row.Append(CreateNumericCell(c, num))
                    Else
                        row.Append(CreateTextCell(c, value, 0))
                    End If
                End If
            Next
            data.Append(row)
        Next

        Return data
    End Function

    Private Function CreateTextCell(col As Integer, value As String, styleIndex As Integer, Optional isHeader As Boolean = False) As Cell
        Return New Cell() With {
            .CellReference = GetCellRef(col, If(isHeader, 2, 0)),
            .DataType = CellValues.String,
            .styleIndex = CType(styleIndex, UInt32Value),
            .CellValue = New CellValue(value)
        }
    End Function

    Private Function CreateTextCell(col As Integer, row As Integer, value As String, styleIndex As Integer) As Cell
        Return New Cell() With {
            .CellReference = GetCellRef(col, row),
            .DataType = CellValues.String,
            .styleIndex = CType(styleIndex, UInt32Value),
            .CellValue = New CellValue(value)
        }
    End Function

    Private Function CreateNumericCell(col As Integer, value As Double) As Cell
        Return New Cell() With {
            .CellReference = GetCellRef(col, 0),
            .DataType = CellValues.Number,
            .StyleIndex = 0,
            .CellValue = New CellValue(value.ToString(System.Globalization.CultureInfo.InvariantCulture))
        }
    End Function

    Private Function GetCellRef(col As Integer, row As Integer) As String
        Dim colName As String
        If col <= 26 Then
            colName = Chr(Asc("A"c) + col - 1)
        Else
            colName = Chr(Asc("A"c) + (col - 1) \ 26 - 1) & Chr(Asc("A"c) + (col - 1) Mod 26 - 1)
        End If
        Return $"{colName}{row}"
    End Function

    Private Function ExtractJsonFromResponse(text As String) As String
        If String.IsNullOrEmpty(text) Then Return ""
        Dim match = System.Text.RegularExpressions.Regex.Match(text, "```(?:json)?\s*([\s\S]*?)```")
        If match.Success Then Return match.Groups(1).Value.Trim()
        Dim startIdx = text.IndexOf("{"c)
        Dim endIdx = text.LastIndexOf("}"c)
        If startIdx >= 0 AndAlso endIdx > startIdx Then Return text.Substring(startIdx, endIdx - startIdx + 1)
        Return ""
    End Function

End Class
