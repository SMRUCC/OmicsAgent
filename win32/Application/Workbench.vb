Imports Fluteway
Imports OmicsWorks.Settings

Module Workbench

    Public ReadOnly Property wwwroot As String
    Public ReadOnly Property config As AppConfig

    Public ReadOnly Property port As Integer
        Get
            If Not http Is Nothing Then
                Return http.port
            Else
                Return -1
            End If
        End Get
    End Property

    Dim WithEvents http As HttpServices

    Public Sub StartHttp()
        http = New HttpServices(GetWebRoot)
        http.StartHttp()
    End Sub

    Public Sub KillHttp()
        If Not http Is Nothing Then
            Call http.Dispose()
        End If
    End Sub

    Private Function GetWebRoot() As String
        If CheckDevelopmentMode() Then
            _wwwroot = "G:\OmicsWorks\agent\apps"
        Else
            _wwwroot = App.HOME & "/apps"
        End If

        Return wwwroot
    End Function

    Private Function CheckDevelopmentMode() As Boolean
        Dim home As String = App.HOME.ToLower.Replace("\", "/").Replace("//", "/")

        If home.StartsWith("g:/omicsworks/agent/bin") Then
            Return True
        Else
            Return False
        End If
    End Function

    Public Function LoadConfig() As AppConfig
        _config = AppConfig.Load
        Return config
    End Function

End Module
