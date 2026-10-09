# Phase 11B-1：実装・検証記録

2026-10-09。**モック図解ライブラリの実装とMacビルド・自動テストを完了。実API／実S3・OIDC・iPhone実機は未検証。**

## 変更と既存機能

CloudLibrary/に共通APIモデル、Mock/HTTPSアダプター、SHA256付きファイル保存actor、画面用store、一覧／検索／詳細／保存済み画面を追加。App入口をTabViewにして既存LibraryViewと分離した。Xcodeプロジェクトへ5ソース・1テスト・モック資源folderを登録。新規依存なし。

既存LibraryView、FileAccessService、LibraryStore、PDF/SVG/画像/PPTXのDocumentViewerと表示コンポーネント、Info.plist、署名・Bundle IDは変更していない。既存iCloud／フォルダの保存データを移行・削除しない。クラウド資料は新しいApplication Support／Caches領域だけで扱う。

## 実施済み

- 構造チェック：73プロジェクトobjects、22 Swiftファイルの登録合格。git diff --check合格。
- Xcode 26.6（17F113）、Simulator SDKで署名なしDebug build成功。
- 最終XCTest：iPhone 15 Pro／iOS 17.4、**19件合格・失敗0**。既存ファイルアクセス6＋表示状態7＋新規クラウド6。最初のiOS 26.5での18件も合格。
- 新規テスト：モックの検索・詳細・PNG8ページ/PDF/PPTX/SVGのbytes／SHA256、PDF8ページ・画像decode、保存後のstore再作成、キャッシュ削除後のPDF読取、破損保存・オフライン改ざん拒否、同ID/版の内容変更拒否、不正パス・20 MB以上・HTTP・未許可取得host拒否、実APIのミリ秒付き有効期限・旧JSON成果物の除外。
- iOS 17.4 Simulator画面操作：既存ローカル資料タブ、新しい図解ライブラリ2件の一覧、RAG詳細・形式別ボタン、PDFの永続保存と既存PDFビューアー表示、PNGの一時取得と表示、PPTXのQuick Look表示を確認。

証跡はGit管理外 `outputs/phase11b1/`：build.log、tests.log、final-tests.log、Tests.xcresult、FinalTests.xcresult、structure.log、pdf-saved.png、pptx-quicklook.png。最終19件を記録する正本はfinal-tests.log／FinalTests.xcresult。Simulator画面取得はiOS 26.5で一時応答せず黒画像になったため、画面確認にはiOS 17.4を使用した。

## 課題と未検証

PPTXはQuick Lookで開けたが、このRAGサンプルの日本語見出しや本文に折り返しの差がある。**PPTXのレイアウト品質は未合格**。詳細UIにPDF利用の案内を追加し、共通生成側は変更していない。次工程でiPhone実機／PowerPointと比較し、資料固有・Quick Look・生成互換性を切り分ける。

SVGのダウンロード／SHA256はテスト済み、追加経路からのSVG画面操作は未確認。オフライン再読取と再起動相当の保存復元は自動テスト済みだが、機内モード実機・アプリ強制終了後の手動操作は未確認。iCloud実通信・外部ディスプレイ・全端末／全ページ目視・アクセシビリティ詳細は今回再検証していない。既存13テスト成功をこれらの実機成功とは扱わない。

HTTPSCloudAPIは未接続のアダプターで、本番HTTP応答・redirect拒否の実通信・401再ログイン・OIDC/Keychainは未検証／未実装。モックは同梱fixtureであって外部HTTPサーバーではない。実S3、本番API、AWSリソース、外部公開、実機インストールは今回実施していない。

次：Simulator／実機のSVGとオフライン操作確認、OIDC・HTTPS共通API、ユーザー別保存・ログアウト方針、署名設定を確認して既存アプリへ更新インストール。設計は [cloud-library](cloud-library.md)。

## 追記：既存iPhoneへの更新インストール

2026-10-09、ユーザーが既存署名用Apple IDを指定した後、接続済みiPhone「Vespera」向けのDebug署名ビルドが成功。同じBundle ID `com.example.PresentationViewer` の更新インストールとdevicectlによる起動が成功した。証跡：outputs/phase11b1/device-build.log、device-install.log、device-launch.log。署名Teamはビルド引数だけで指定し、プロジェクト設定へ固定していない。初回のTeam指定は証明書識別子との取り違えで失敗し、証明書のOUでTeam IDを確認して修正した。

この追記は上記の「実機インストール未実施」を更新する。実機画面・保存済みフォルダの保持・機内モードでの読取・各形式の手動確認は未確認。モック資料のみで、本番S3接続は行っていない。
