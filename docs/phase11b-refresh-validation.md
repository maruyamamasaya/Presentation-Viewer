# Phase 11B Mac再検証（2026-10-10）

## 現行実装
SwiftUIのローカル資料と図解ライブラリをTabViewで分離。CloudLibraryAPI／MockCloudAPI／HTTPSCloudAPI、CloudFileStore actor、CloudLibraryStoreを既存実装として確認。最新viewer-api.mdの一覧、版指定詳細、access-url、PNGページ指定に対応。アプリは同梱モックのみを使用し、本番API・S3へ接続しない。上部のタイトル／タグ検索は取得済み一覧のローカル絞込。

PDFKit、Quick Look、画像ビューアーを再利用し、サイズ／SHA256を保存前・オフライン閲覧前に確認。保存先はApplication Support、一時取得はCaches。ユーザー確認によりSVGの閲覧除外を維持する（取得契約と既存SVGソースは残す）。

## 今回の検証
- Xcode 26.6（17F113）、iOS 17.4 iPhone 15 Pro Simulatorを利用可能と確認。
- Simulator Debugビルド成功、XCTest23件成功・失敗0。既存表示状態・ファイルアクセス、モック全形式取得・SHA256、保存領域再作成／キャッシュ消去後のオフラインPDF、改ざん・不正パス・取得host拒否を含む。
- 構造検査（22 Swiftファイル）・git diff --check成功。
- Simulatorへ更新・起動成功。library.pngを目視し、上部検索欄、対象切替、RAGカード・保存済み表示、ローカル資料タブを確認。
- 接続済みiPhone Vesperaへ既存Team・Bundle IDで署名ビルド、更新インストール、起動成功。データ削除なし。

証跡：outputs/phase11b-refresh/Tests.xcresult、tests.log、library.png、device-build.log、device-install.log、device-launch.log。

## 未実施と次工程
Simulator UI操作ツールは2回タイムアウト。検索入力・対象切替・形式変更・保存・再起動の今回の手動操作は未実施。実機画面・機内モード閲覧・iCloud実通信・外部画面も未検証。以前の画面検証はphase11b1-validation.mdを参照し、今回の検証と区別する。PPTX Quick Lookの日本語折返し差は残る。

公開接続にはPKCE/OIDC、Keychain、issuer/subject別保存領域、ログアウト時の扱い、実API契約・未取得ページ検索・401復帰試験が必要。HTTPSアダプターは用意済みだが本番接続完了ではない。AWS変更・認証リソース作成・ホスティング・本番S3接続は実施していない。設計はdiagram-design-systemのdocs/phase11b-public-api-plan.md。
