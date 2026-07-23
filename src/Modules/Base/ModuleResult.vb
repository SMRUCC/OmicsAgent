Public Class ModuleResult
    Public Property ModuleName As String
    Public Property ModuleIndex As Integer
    Public Property Conclusion As String
    ''' <summary>
    ''' Analysis result dir located in analysis/
    ''' </summary>
    ''' <returns></returns>
    Public Property OutputDir As String
    ''' <summary>
    ''' Workspace dir located in tmp/
    ''' </summary>
    ''' <returns></returns>
    Public Property Workdir As String
End Class