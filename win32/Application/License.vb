Imports Galaxy.Workbench
Imports Galaxy.Workbench.LicenseFramework.Client
Imports Galaxy.Workbench.LicenseFramework.[Shared]

Module License

    ReadOnly licenseManager As LicenseManager

    Public Function IsLicensed() As Boolean
        If licenseManager Is Nothing Then
            Return False
        Else
            Return licenseManager.IsLicensed
        End If
    End Function

    Public Function GetCurrentLicense() As LicenseData
        If licenseManager Is Nothing Then
            Return Nothing
        Else
            Return licenseManager.CurrentLicense
        End If
    End Function

    Sub New()
        Call CommonRuntime.SetSeed(&HA7)

        ' ===== 第一步：初始化授权管理器 =====
        licenseManager = New LicenseManager(
            publicKeyXml:=GetEmbeddedPublicKey(),
            productName:="我的商业软件",
            productVersion:="1.0.0",
            serverUrl:="https://license.example.com/api/activate",
            hmacKey:=GetEmbeddedHmacKey()
        )
    End Sub

    ''' <summary>
    ''' 获取嵌入的RSA公钥
    ''' 实际项目中应将公钥硬编码或混淆后嵌入
    ''' </summary>
    Private Function GetEmbeddedPublicKey() As String
        ' 请将以下数组和密钥复制到你的正式项目代码中：
        Dim keyParts() As String = {
           "m/X05uzC3vHGy9LCmZvqyMPSy9LUmdOW8eLml+Lm7szj8+jw9Pf+lpT31M7U4Jft7+XJz5HJxub+8+jJ4u/W38qTyNb38sH95IiSlZTelc7L5uDw1enr483oxsvJzMyV6Z/QxMqQydO",
           "e/e3zkun3kN315N6SyNHUzNKQ15KR05Hw4pLO8M/29PLtkcPf5ObW0Orx/v3KleX1yOHNkM7m0vHQ/s7+w/XWl8L0k8HkxMzEkfLj1tLP8cqRlP7xzvLtyZT0z87C9J/m3d3XxcDg1Z",
           "7Vku/e3sKIn+WV7Pfq9P39lfbp95bg14zU1pHEyJXD5eHFlebp4vXR/ZTL4YjJyujewZGUzJfVw/TIze706dPD/uiMnubw7ub/0OvB6MOT9/aIwO/R4O/M5tDAyc7+4cv+lf/J3ZfC7",
           "crS1cjeyerVwfXmxvLg4pXN85SX/8OT5OL20ff27PKM/c/pw8ze0fGe8dPV/tH29cL/9pqam4jqyMPSy9LUmZvi39fIycLJ05nm9ublm4ji39fIycLJ05mbiPX05uzC3vHGy9LCmQ=="
        }

        CommonRuntime.SetSeed(&HA7)

        Return CommonRuntime.AssembleKey(keyParts)
    End Function

    ''' <summary>
    ''' 获取嵌入的HMAC密钥
    ''' 实际项目中应混淆后嵌入
    ''' </summary>
    Private Function GetEmbeddedHmacKey() As String
        ' 此处替换为实际的HMAC密钥（Base64编码）
        Return "YOUR_HMAC_KEY_BASE64_HERE"
    End Function

    Public Function CheckLicense() As Boolean
        ' ===== 第二步：执行授权验证 =====
        Dim result As LicenseValidationResult = licenseManager.Validate()

        If Not result.IsValid Then
            ' ===== 第三步：验证失败，显示授权对话框 =====
            Dim dialogResult As LicenseValidationResult = licenseManager.ValidateWithDialog

            If Not licenseManager.IsLicensed Then
                ' 用户未完成授权，退出程序
                MessageBox.Show("软件未授权，某些程序功能模块的使用将会受到限制。",
                                "授权验证失败", MessageBoxButtons.OK, MessageBoxIcon.Warning)
                Return False
            End If
        End If

        Return True
    End Function

    Public Sub OpenLicenseDialog()
        Call licenseManager.OpenLicenseDialog()
    End Sub
End Module
