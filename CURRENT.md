# 現在地

2026-10-10。既存ローカル資料とモック図解ライブラリを維持。Phase 11B-2のPKCE/Keychain・本番設定切替・利用者別保存・URL再取得をローカル実装。署名付きSimulator27テスト合格。接続iPhone更新成功、最終起動は端末Lockedで未確認。AWS公開APIは承認後にデプロイ済み。iOSに公開接続設定を反映、既定モックは維持。本人のメール／owner設定は回答待ち。[適用記録](docs/phase11b2-deployment.md)。実Cognito／実API／iOS実S3・実機操作は未検証。

正本：[検証](docs/phase11b2-validation.md)、[ライブラリ](docs/cloud-library.md)、[README](README.md)。このrepoにAGENTS.mdはなく、diagram-design-system側のAWS承認境界と今回のユーザー指示を適用する。

Phase 11B-3：実Cognito設定・S3公開ブロックを読取確認。本人登録・招待メール送信・owner限定更新が完了。本人の本番ログイン・資料一覧表示成功。本人報告で実機PDF/PNG/PPTXの取得・表示・保存成功。機内モード＋Wi-Fi無効のオフライン閲覧も3形式成功。Phase 11B-3完了。[手順と未実施事項](docs/phase11b3-validation.md)。
