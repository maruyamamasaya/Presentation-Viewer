# Phase 11B-3：本番実機確認

2026-10-10。公開設定とモックの既定値を維持。本人Cognito登録・承認された招待メール送信・owner限定設定が完了。本人報告で本番ログイン・資料一覧表示成功。AWSでCONFIRMEDを確認。手順と実AWS読取結果の正本はdiagram-design-system/docs/phase11b3-validation.md。

本人がiPhoneのロック解除とCognito画面でのパスワード入力を行う。その他→接続設定→本番APIでログイン後、PDF/PNG/PPTXの取得・SHA256検査・保存・閲覧を確認。機内モード＋Wi-Fi無効で保存済み3形式を開く。

iPhone Vesperaでアプリ起動成功。

本人報告で本番PDF/PNG/PPTXの取得・表示・端末保存成功。保存成功はサイズ／SHA256検査を通過する実装と照合。本人報告で機内モード＋Wi-Fi無効でも保存済み3形式を開き直して閲覧成功。Phase 11B-3完了。前段Simulatorの合格と混同しない。秘密値・トークン・署名URLは記録しない。
