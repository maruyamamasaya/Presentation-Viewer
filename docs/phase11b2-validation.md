# Phase 11B-2 local（2026-10-10）

公開API/OIDC接続準備をローカル実装。既定モック・ローカル資料・SVG除外を維持。図解repoとは独立Gitを維持。

CloudOIDC.swiftにCode+PKCE S256、state／callback検査、ASWebAuthenticationSession、Keychain（WhenUnlockedThisDeviceOnly）、期限前refresh、logout/revokeを追加。ID tokenを本人判定に使用せず、署名検証／owner認可済みAPIの/v1/meをidentityに使用する。HTTPSCloudAPIはAPI tokenを署名URLへ付けず、host許可リスト・redirect拒否・SHA256保存を維持。URL期限切れ／取得403で1回再取得。

本番はInfo.plistのCloudConnectionJSONとUIの接続設定で有効化。未設定時は通信せず案内。config/cloud-connection.example.jsonは公開値のひな形、tools/configure-cloud.pyは承認済みの実URL/client IDをInfoへ設定するローカルツール。secret／AWSキーを含めない。設定スイッチはライブラリ右上の「その他」→「接続設定」。

保存領域はissuer/client/API＋subjectのSHA256単位。モックの既存領域を移行しない。ログアウトはKeychain削除・保存資料非表示、同じ本人の再ログインで保存資料を再利用できる。オフラインは最後に認可済みの本人の保存領域から読む。ログアウトした本人の資料は再ログインするまで表示しない。

検索はモック／保存済みがローカル、本番が入力後300msでscope=all/title/tags付き共通API（全catalog検索）。旧結果はTask取消時に反映しない。

## 検証
- Simulator iOS17.4/iPhone15 Pro：最終27テスト合格。PKCE公式例／callback改ざん・重複code拒否、Keychain保存／削除、不正HTTPS設定拒否、取得期限切れの再発行→保存→cache削除→オフライン読取、既存23回帰。ローカルHTTP応答でrefresh→認可済みidentity→Keychain更新→logout/revokeも検証（実IDP通信ではない）。
- 署名なしSimulatorではKeychainテスト拒否。署名付きで全件成功。署名なしの初回失敗を消さず記録する。
- プロジェクト構造（23 Swiftファイル）・diff検査成功。端末署名build成功、接続iPhone Vesperaの同Bundle ID更新成功。直前版は起動成功、最終版は端末Lockedで起動拒否。
- Simulatorのモック一覧をlibrary.pngで目視確認。UI操作ツールtimeoutで検索／接続設定／保存の今回の手動操作は未実施。

証跡：outputs/phase11b2/OIDCTests.xcresult、oidc-tests.log、device-build.log、device-install.log、device-launch.log、library.png。APIテストとAWS読取は別repoのdocs/phase11b2-validation.mdを正本とする。

## 未完了
AWS公開リソースは未作成、実URL/client ID/owner未設定のためiOSはモックのまま。Cognito実ログイン／refresh／logout、実API／実S3、実機画面・機内モード・ユーザー切替は未検証。Keychain実通信とIDP連携は自動テストの範囲外。PPTX Quick Look日本語折返し差は既知。

承認後：公開API作成・本人の認証・公開設定を反映し、iPhoneで基本操作を実施。revoke後のstateless access tokenは最大5分、S3 URLは300秒残存し得る。通信失敗時も端末tokenを先に削除しrevoke未確認を表示する。

最終の検索条件／cursor保持修正後、クラウド関連12テストだけを再実行し成功（iOS側outputs/phase11b2/cloud-final-tests.log）。最終実機install成功・launchはLockedで拒否（同device-*.log）。
