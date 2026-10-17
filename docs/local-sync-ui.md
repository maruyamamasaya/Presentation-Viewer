# 整理同期のローカル検証画面

2026-10-17。右下ライブラリ→管理・設定→同期の検証。共有LibraryOrganizationUIのSyncLabView/Sessionを利用する。CloudLibraryStore.makeSyncLabは利用者別の既存フォルダ/分類/タグ/まとめをURLのないOrganizationDocumentへ読取専用で変換し、別のsync-lab/checkpoint.jsonへ保存する。元の本棚への書戻し・通常画面での編集の自動送信は行わない。

初回統合の確認、送信待ち/競合/最終同期、両案表示と採用、オフライン再送、検証コピーの解除に対応。接続はhttp://127.0.0.1のみ。MacとiOS Simulatorで検証し、実機iPhoneへのLAN公開・TLS/ATS例外・AWS変更は行わない。模擬サーバーはSwiftのOrganizationDocumentを使い、資料本体/認証情報/ファイルURLを送信しない。

正本は隣接diagram-design-system/docs/organization-sync-ui.md。共有19・Mac24・iOS60 XCTest合格。iOS取込テストで元のorganization/classifications/collectionsファイルのバイト不変を確認。共有画面セッションは実loopback HTTPで競合/解決/復元/オフライン再送/後片付けまで成功。iOS新画面も新規の使い捨てSimulator/iOS26.5で専用ツールから実操作確認済み。同一IDフォルダの初回両案確認と端末案選択、接続拒否後の1件保持と再送、サーバー採用/端末採用して再送の両競合解決、版5で送信待ち0/競合0、検証コピー解除まで成功。元organization.jsonのバイト不変とcheckpoint解除を照合。Simulatorへの接続タイムアウトはSimulatorアプリだけを終了して専用ツールで起動し直して復旧（内部根因は未特定）。新規検証デバイス/模擬サーバーは後片付け済み。実装修正・実機配布・既存データ/AWS変更なし。詳細は隣接diagram-design-system/sessions/2026-10-17-ios-sync-ui-validation.md。
