# 整理同期のローカル検証画面

2026-10-17。右下ライブラリ→管理・設定→同期の検証。共有LibraryOrganizationUIのSyncLabView/Sessionを利用する。CloudLibraryStore.makeSyncLabは利用者別の既存フォルダ/分類/タグ/まとめをURLのないOrganizationDocumentへ読取専用で変換し、別のsync-lab/checkpoint.jsonへ保存する。元の本棚への書戻し・通常画面での編集の自動送信は行わない。

初回統合の確認、送信待ち/競合/最終同期、両案表示と採用、オフライン再送、検証コピーの解除に対応。接続はhttp://127.0.0.1のみ。MacとiOS Simulatorで検証し、実機iPhoneへのLAN公開・TLS/ATS例外・AWS変更は行わない。模擬サーバーはSwiftのOrganizationDocumentを使い、資料本体/認証情報/ファイルURLを送信しない。

正本は隣接diagram-design-system/docs/organization-sync-ui.md。共有19・Mac24・iOS60 XCTest合格。iOS取込テストで元のorganization/classifications/collectionsファイルのバイト不変を確認。共有画面セッションは実loopback HTTPで競合/解決/復元/オフライン再送/後片付けまで成功。iOS新画面も新規の使い捨てSimulator/iOS26.5で専用ツールから実操作確認済み。同一IDフォルダの初回両案確認と端末案選択、接続拒否後の1件保持と再送、サーバー採用/端末採用して再送の両競合解決、版5で送信待ち0/競合0、検証コピー解除まで成功。元organization.jsonのバイト不変とcheckpoint解除を照合。Simulatorへの接続タイムアウトはSimulatorアプリだけを終了して専用ツールで起動し直して復旧（内部根因は未特定）。新規検証デバイス/模擬サーバーは後片付け済み。実装修正・実機配布・既存データ/AWS変更なし。詳細は隣接diagram-design-system/sessions/2026-10-17-ios-sync-ui-validation.md。


## 通常本棚のテスト接続

Simulatorのサンプルモードを`--test-library-sync`で明示起動した場合だけ、通常のフォルダ/所属/分類/タグ/まとめの保存を送信待ちへ投影し、手動同期の受信結果をCloudFileStoreへ反映する。既定の起動/実機/本番画面は従来の検証コピー。初回統合は従来の両案確認を使用し、解決後は手動同期で本棚へ反映する。

接続前の管理3JSONはtest-library-sync/recovery.jsonへバイト保存し、受信反映途中はtest-sync-apply.jsonのジャーナルを各読込前に回復する。元のフォルダ画像参照・資料保存ファイル・非表示・キャッシュ・認証は変更しない。同期中の新規通常編集要求は拒否し、送受信前後で通常保存差分を確認する。常時/自動送受信や実データ移行は未実装。

使い捨てSimulatorと別IDのMacテストアプリを専用ツールで操作し、Macフォルダ→iOS通常一覧、iOS通常フォルダ作成と資料移動→Mac通常本棚、Mac通常タグ編集→iOS通常タグ一覧を確認。版5/待ち0/競合0と保存JSON一致を照合。iOS62テストはまとめ保存/受信/再読込とジャーナル回復も含む。既存データ/AWS/実機/Applications版は変更せず、検証用デバイスと模擬サーバーは片付け済み。

正本：隣接diagram-design-system/docs/organization-sync-bound.md、作業記録：同sessions/2026-10-17-normal-library-sync.md。


## 管理データの保護と画面復元

テスト起動の初回接続前に管理JSONだけを自動バックアップし、日時/本棚への追加変更解除/サーバーへの追加変更解除/未解決競合を共通画面へ表示する。PDF/画像/PPTX/保存済み資料本体/キャッシュ/S3オブジェクトはバックアップしない。競合確認後に有効化し、失敗時は「同期を止めてバックアップから復元」から確認して戻せる。

復元は先に同期停止状態を保存し、旧3JSONを元のバイト/不存在へ戻してcheckpointを解除する。management-restore.jsonで復元途中の中断を回復し、古い受信反映ジャーナルを除去する。失敗時/再起動後も同期と通常編集を停止し、復元を再試行できる。サーバーは変更せず、再接続は初回確認から行う。共通24/Mac26/iOS64テストと専用ツールの両画面で通信失敗→復元→元JSON一致を確認した。実機/既存データ/AWS変更なし。

正本は隣接diagram-design-system/docs/organization-sync-recovery.md。今後のAWS変更は必ず事前料金シミュレーション（同docs/cost-policy.md）を提示して承認後に行う。


## 同期回数と今回だけの追加

明示テスト起動の通常本棚に、Mac/iPhone合計で直近1時間5回の予約制限を追加した。ローカル模擬サーバーの--limited-serveを使う。上限中の編集は保存し、前回確認時の回数/残り/通常同期を再確認できる時刻を表示する。追加は「今回の1回だけ追加で同期…」の確認後だけで、恒久解除しない。

初回取得/確定/送信は10分の同じ予約内で1回扱い。分割データ要求12個、各要求の送信は初回込み3回まで。再起動/切断/管理復元で利用者台帳を消さず、サーバーが最終判定する。正規アプリの同意は1回専用challengeで予約し、使い回さない。模擬は単一利用者であり、Cognito subとS3 CASによる本番判定は次段階。

共通28/Mac26/iOS64、実HTTPの2端末合算/ACK喪失/再起動/追加/10並行5許可と専用ツールの両画面を確認。AWS/普段の本棚/実機iPhoneは変更なし。正本：隣接diagram-design-system/docs/organization-sync-quota.md。料金見積もりでは5回をHTTP5要求とせず、制御通信/再試行/台帳書込を加えてAWS変更前に再計算する。
