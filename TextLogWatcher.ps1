[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#実行パラメータ#######################################################################################################################
#ポーリングサイクル(秒)
$jobCycleTimeSec = 5
#監視対象ファイルのニックネーム/パス/ファイル名/検索条件/文字コード
#[System.Text.Encoding]::GetEncoding("UTF-8") で取得できる文字コードを指定
$watchList = @( 
    ,@(
        "LoggerName",
        "FolderPath",
        "FileName",
        "SearchWords(Reg)",
        "TextCode"
    )
    ,@(
        "SampleLogWatcher",
        "C:\sources\Apps",
        "application.log",
        "Error\s+\d{2}/\d{2}/\d{4}",
        "UTF-8"
    )
)
#前回解析位置保存ファイルパス
$sizeLocationStorePath = "C:\sources\LogWatcher\Var"

#ログ設定
$logFilePath = "C:\sources\LogWatcher\Var"
$logFileName = "watcher.log"
$logFullPath = Join-Path -Path $logFilePath -ChildPath $logFileName
$maxDataSize = 10 #単位はMB
$logHoldDays = 90 #ログの保管期間

#監視メールの発報先
$mailTo = "test_distination@local"
$maxMailRows = 50 #最大メール行数
$ommit = $false #変更しない

#SMTP サーバーと資格情報を設定
$smtpServer = "stmp.test.local"
$smtpPort = 587
$username = "test@local"
$password = "passw0rd"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

########################################################################################################################

#ログファイルのローテーション
function RotateLog {
    $newLogFileName = "_$(Get-Date -Format 'yyyyMMddHHmmss').log"
    # 新しいログファイル名を生成
    $newLogFilePath = $logFullPath -replace '\.log$', $newLogFileName
    # ログファイルをリネームしてローテーション
    Rename-Item -Path $logFullPath -NewName $newLogFilePath
    # 空のログファイルを作成して新しいログの記録を開始
    New-Item -Path $logFullPath -ItemType File | Out-Null
    # ログローテーションのタイミングで90日を経過したファイルを削除する
    $cutDate = (Get-Date).AddDays($logHoldDays)
    $filesToDelete = Get-ChildItem -Path $logFilePath | Where-Object { $_.LastWriteTime -lt $cutDate }
    # ファイルを削除
    foreach ($file in $filesToDelete) {
        Remove-Item $file.FullName -Force
    }
}

#ログとターミナルの出力
function Write-Log {
    param (
        [string]$Message
    )

    # ログファイルのサイズを取得
    if (Test-Path -Path $logFullPath -PathType Leaf) {
        $logFileSizeMB = [math]::Round((Get-Item $logFullPath).Length / 1MB, 2)
    }

    # 既定のデータサイズに達した場合はローテーションを実行
    if ($logFileSizeMB -ge $maxDataSize) {
        Write-Log -Message "ログローテーション"
        RotateLog
    }

    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $logEntry

    if (-not (Test-Path -Path $logFilePath -PathType Container)) {
        New-Item -ItemType Directory -Path $logFilePath | Out-Null
    }

    Add-Content -Path $logFullPath -Value $logEntry
}

#最終読み取り位置の記録ファイル
function ExportLastWatchPosition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$nickName, #読み取り位置保存パス
        [Parameter(Mandatory = $true)]
        [array]$sotreData #読み取り位置データ
    )
    
    #読み取り位置保存パスが存在しない場合は作成する
    if (-not (Test-Path -Path $sizeLocationStorePath -PathType Container)) {
        New-Item -ItemType Directory -Path $sizeLocationStorePath | Out-Null
    }

    $storePath = $sizeLocationStorePath + "\." + $nickName
    #配列データを強制的に上書きする
    $sotreData | Out-File -FilePath $storePath -Encoding utf8 -Force
}

#監視対象のコンフィグが存在するか確認する
function ImportLastWatchPosition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$nickName #読み取り位置保存パス
    )

    #配列で返す
    $returnLines = @()

    #最終読み取り位置ファイル
    $storePath = $sizeLocationStorePath + "\." + $nickName

    # ファイルが存在するか確認する
    if (-not (Test-Path $storePath -PathType Leaf)) {
        Write-Log "最終読み取り位置のファイルが見つかりません。"
        return $returnLines
    }

    # テキストファイルを読み取り配列で返す
    Get-Content $storePath | ForEach-Object {
        $returnLines += $_
    }
    return $returnLines
}

#メール発報
function Send-Mail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$title, #監視タイトル
        [Parameter(Mandatory = $true)]
        [string]$body #本文
    )

    Write-Log "メール発報"

    try {
        # メール送信実行
        Send-MailMessage -From $username -To $mailTo -Encoding utf8 -Subject $title -Body $body -SmtpServer $smtpServer -Port $smtpPort -Credential $credential -UseSsl
    }
    catch{
        Write-Log -Message "メール送信エラー: $($_.Exception.Message)"
    }
}

#本処理
#監視対象毎にFileSystemWatcherオブジェクトを作成する
#https://learn.microsoft.com/ja-jp/dotnet/api/system.io.filesystemwatcher?view=net-8.0
for ($wachTarget = 0; $wachTarget -lt $watchList.Length; $wachTarget++) {

    Write-Log "ファイル監視オブジェクトの作成: $($watchList[$wachTarget][0])"
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $watchList[$wachTarget][1] #監視するファイルのパスを設定
    $watcher.Filter = $watchList[$wachTarget][2]  #監視するファイル名を設定
    $watcher.IncludeSubdirectories = $true #指定したパスのサブディレクトリを監視するかどうか
    $watcher.EnableRaisingEvents = $true #コンポーネントが有効かどうかを示す値を取得または設定します。

    #変更ファイルを検知したときの挙動
    $action = {

        $watcherNickName     = $null #監視対象のニックネーム
        $watcherSearchWord   = $null #監視対象の検索文字(正規表現可能)
        $watcherEncofing     = $null #監視対象の文字コード
        $lastPosition        = 0     #前回読み取り位置
        $lastCreatedDate     = $null #前回ファイル作成日

        #利用できるのは以下 $Event.SourceEventArgs.FullPath / $Event.SourceEventArgs.Changed / $Event.SourceEventArgs.Name
        Write-Log "ファイルの変更を検知しました。対象:$($Event.SourceEventArgs.FullPath)"
        
        #監視対象の各種条件を取得する
        for ($watchConfig = 0; $watchConfig -lt $watchList.Length; $watchConfig++) {
            #検知したファイルと変数で定義した監視条件で一致したパラメータを取得する
            if($Event.SourceEventArgs.FullPath -eq $watchList[$watchConfig][1] + "\" + $watchList[$watchConfig][2]){
                $watcherNickName     = $watchList[$watchConfig][0]
                $watcherSearchWord   = $watchList[$watchConfig][3]
                $watcherEncofing     = $watchList[$watchConfig][4]
                Write-Log "監視条件が見つかりました。$watcherNickName"
                break
            }
        }

        #検索対象ファイルの取得
        $searchFile = Get-Item $Event.SourceEventArgs.FullPath

        #格納された読み取り位置データを取得する
        $storedLastByteData = ImportLastWatchPosition -nickName $watcherNickName

        #読み取り位置データから検知ファイルデータの格納情報を取得する
        #1行目: 最終バイト 2行目: 作成日
        if($storedLastByteData -ne $null)
        {
            $lastPosition = $storedLastByteData[0]
            $lastCreatedDate = $storedLastByteData[1]
            Write-Log "監視対象ファイルの前回記録時情報は以下です。`n最終位置: $lastPosition`n作成日: $lastCreatedDate"

            #ファイル作成日に差異がある場合、監視対象ファイルがローリングされている or 別ファイルと判定し初回処理扱いにする
            if($searchFile.CreationTime.ToString().Trim() -ne $lastCreatedDate){
                Write-Log "ファイルのローリングを確認しました。初回処理として扱います。"
                $lastPosition = 0
                $lastCreatedDate = $searchFile.CreationTime.ToString().Trim() #最後に作成日を保管するためにデータを保持する
            }
            #前回読み取り位置がファイルサイズより大きい場合は、データが消されたと判定し初回処理扱いにする
            if($lastPosition -gt $searchFile.Length){
                Write-Log "ファイルサイズが前回読み取り位置よりも小さくなりました。初回処理として扱います。"
                $lastPosition = 0
                $lastCreatedDate = $searchFile.CreationTime.ToString().Trim()
            }
        }
        else{
            #取得できない場合は初回処理として判定する
            Write-Log "初回の監視対象です。"
            $lastPosition = 0
            $lastCreatedDate = $searchFile.CreationTime.ToString().Trim() 
        }

        #前回読み取り位置から検索対象の文字列を探索する
        try{
            $searchFileStream = $searchFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $searchFileStream.Seek($lastPosition,[System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($searchFileStream, [System.Text.Encoding]::GetEncoding($watcherEncofing))
            $newData = $reader.ReadToEnd()
            $reader.Close()
            $searchFileStream.Close()

            #検索文字列の探索を行う
            if($newData.Length -gt 0){
                Write-Log "以下の条件で探索を行います。`n対象: $watcherNickName `n検索文字: $watcherSearchWord `nエンコード: $watcherEncofing `n開始位置: $lastPosition `n"
                
                $searchArray = $newData -split "`r`n"
                $detectedRow = -1;

                #一行ずつ探索し検索文字が特定できたらその行番号を保持してBreakする
                for($i = 0; $i -lt $searchArray.Length; $i++){
                    If(($searchArray[$i] | Select-String -Pattern $watcherSearchWord -CaseSensitive -SimpleMatch:$false).Count -gt 0){
                        $detectedRow = $i
                        break
                    }
                }

                if ($detectedRow -gt -1) {
                    Write-Log -Message "指定された文字列を検出しました。$($detectedRow.Count) 行目"

                    #検出行以降を再結合する。但しメール発報行数を超過する場合は省略する
                    if($maxMailRows -lt ($searchArray.Length - $detectedRow)){
                        #上限を超える場合は送信データを制限する
                        $matchData = $searchArray[$detectedRow..($detectedRow + $maxMailRows -1)]
                        $ommit = $true
                    }
                    else{
                        #上限を超えない場合は全てのデータを送る
                        $matchData = $searchArray[$detectedRow..($searchArray.Length -1)]
                        $ommit = $false
                    }    
                    
                    #メール送信用にログデータを再結合する
                    $context = $matchData -join "`r`n"
                    $mailTitle = "[監視通知] 対象: $watcherNickName 検索条件: $watcherSearchWord "
                    
                    if($ommit){
                        $mailBody = "監視対象ファイル: $($Event.SourceEventArgs.FullPath)`r`n" + `
                                    "ログ取得範囲: $lastPosition から $($searchFile.Length)`r`n" +
                                    "******************ログ詳細******************`r`n" + `
                                    "$context`r`n以下省略($maxMailRows 行迄)`r`n" + `
                                    "********************************************`r`n";
                    }
                    else{
                        $mailBody = "監視対象ファイル: $($Event.SourceEventArgs.FullPath)`r`n" + `
                                    "ログ取得範囲: $lastPosition から $($searchFile.Length)`r`n" +
                                    "******************ログ詳細******************`r`n" + `
                                    "$context`r`n" + `
                                    "********************************************`r`n";
                    }

                    Send-Mail -title $mailTitle -body $mailBody
                }

                #今回探索した最終位置をストアする
                $lastPosition = $searchFile.Length
            }
        }
        catch
        {
            Write-Log -Message "変更を検知しましたが予期しないエラーにより中断されました"
            Write-Log -Message $_.Exception.Message
            Write-Log -Message "発生個所:"
            Write-Log -Message $_.InvocationInfo.ScriptLineNumber
            Write-Log -Message "スタックトレース:"
            Write-Log -Message $_.Exception.StackTrace
        }
        finally
        {
            # 事後処理（今回更新分と何も変更されなかったデータを配列として保持してcsvファイルに書き戻す）
            # ファイルパス/最終読み取り位置/ファイル作成日
            $updatedStoredData = @($lastPosition, $lastCreatedDate)
            # 監視対象のコンフィグに書き込む
            ExportLastWatchPosition -nickName $watcherNickName -sotreData $updatedStoredData
        }
    }

    #イベントの追加
    Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $action
    Write-Log "監視を開始しました。 $watcherNickName"
}

#一定時間でポーリングする
try {
    while ($true) {
        Start-Sleep -Seconds $jobCycleTimeSec
        Write-Log "$jobCycleTimeSec 秒でポーリングします。"
    }
}
finally { 
    #スクリプト終了時にイベントを解除
    Unregister-Event -SourceIdentifier $watcher #-ErrorAction SilentlyContinue
    $watcher.Dispose()
}
