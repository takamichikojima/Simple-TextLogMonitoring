# Simple-TextLogMonitoring(Windows)

## 概要
TextLogWatcher.ps1 は、指定したログファイルをリアルタイムで監視し、特定のキーワードや正規表現に一致するログが出力された際に、メールで通知する PowerShell スクリプトです。ファイルの変更を検知し、検出内容や監視状況をログファイルに記録します。
（監視ツールを購入する余裕がない等の苦しい事情がある際に手軽に監視する目的で開発しました）

## 主な機能
- 複数ファイル・複数条件の同時監視
- ファイルの変更（追記）をリアルタイムで検知
- 正規表現によるキーワード検出
- 検出時にメールで自動通知
- ログファイルの自動ローテーション・保管期間管理
- 監視ごとの最終読み取り位置を保存し、再起動時も継続監視

## 使い方
1. **パラメータ設定**
   - `$watchList` に監視対象のニックネーム、パス、ファイル名、検索条件（正規表現）、文字コードを設定します。
   - SMTP サーバーや送信先メールアドレスなどもスクリプト冒頭で設定します。

2. **Windowsタスクスケジューラへの登録**
   - タスクスケジューラを開き、「タスクの作成」を選択します。
   - 「全般」タブで任意の名前を設定します。
   - 「トリガー」タブで「新規」をクリックし、「スタートアップ時」を選択します。
   - 「操作」タブで「新規」をクリックし、
     - プログラム/スクリプト：`powershell.exe`
     - 引数の追加（オプション）：`-ExecutionPolicy Bypass -File "<LogWatcher.ps1のフルパス>"`
     - 開始（オプション）：スクリプトのあるフォルダパス
   - 「OK」でタスクを保存します。

3. **スクリプトの手動実行（テスト用）**
   - PowerShell でスクリプトを直接実行することも可能です。
   - 例: `powershell.exe -ExecutionPolicy Bypass -File LogWatcher.ps1`

4. **監視・通知**
   - 指定したファイルに変更があると、条件に一致した場合にメール通知されます。
   - 監視状況や検出内容はログファイル（`watcher.log`）に記録されます。

## 主な設定項目
- `$watchList` : 監視対象のリスト（ニックネーム/パス/ファイル名/検索条件/文字コード）
- `$mailTo` : 通知先メールアドレス
- `$smtpServer`, `$smtpPort`, `$username`, `$password` : SMTP サーバー情報
- `$logFilePath`, `$logFileName` : ログファイルの保存先
- `$maxDataSize`, `$logHoldDays` : ログのローテーション・保管期間

## 注意事項
- PowerShell 5.1 以降での動作を推奨します。
- SMTP サーバーの設定やメール送信に必要な権限が必要です。
- 監視対象ファイルのパスや権限に注意してください。
- **メール送信時の注意**
    - ご利用のSMTPサーバーが認証不要の場合、`Send-MailMessage` コマンドの `-Credential` や `-UseSsl` オプションは不要です。
    - 認証が必要な場合は、`-Credential` および `-UseSsl` オプションを指定してください。
    - 例：
        - 認証あり：
          ```powershell
          Send-MailMessage -From ... -To ... -Subject ... -Body ... -SmtpServer ... -Port ... -Credential $credential -UseSsl
          ```
        - 認証なし：
          ```powershell
          Send-MailMessage -From ... -To ... -Subject ... -Body ... -SmtpServer ... -Port ...
          ```

## 参考
- [FileSystemWatcher クラス (Microsoft Docs)](https://learn.microsoft.com/ja-jp/dotnet/api/system.io.filesystemwatcher)
- [Send-MailMessage コマンドレット (Microsoft Docs)](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.utility/send-mailmessage)

## ライセンス
このリポジトリのコードは [MITライセンス](LICENSE) のもとで公開されています。

Copyright (c) 2025 [takamichikojima]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
