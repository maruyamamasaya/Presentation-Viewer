# 公開接続設定（2026-10-10）

AWS公開APIはdiagram-design-system側でデプロイ済み。公開URL・Cognito issuer/public client ID・署名URLhost許可リストをconfig/cloud-connection.jsonとInfo.plistへ反映。これらは秘密ではない。client secret、AWSキー、tokenをGitへ保存しない。

既定モックを維持し、「その他→接続設定→本番APIを使用」で切り替える。Cognito利用者のメール回答待ちで、API ownerはUNCONFIGURED。本人登録／owner設定前は資料アクセスを許可しない。実パラメーター正本は別repoのinfra/phase11b2-deployment.jsonとdocs/phase11b2-deployment.md。

公開設定を含む実機署名buildと同Bundle IDの更新インストールを実施。認証後の基本操作、保存／オフライン、ログイン／ログアウトは本人設定後に実機で確認する。従来のローカル検証はdocs/phase11b2-validation.md。
