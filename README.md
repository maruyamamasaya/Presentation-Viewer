# Presentation Viewer

iPhone・iPad用の資料閲覧専用SwiftUIユニバーサルアプリ。iOS / iPadOS 17以降。外部ライブラリなし。既存フォルダ閲覧に加え、図解ライブラリのモック連携に対応。本番クラウド認証・接続は未設定。

## 開く・実行する

MacのXcode 15以降（iOS 17 SDK以降）で `PresentationViewer.xcodeproj` を開き、`PresentationViewer` SchemeとiPhone / iPad Simulatorを選択してRunします。実機ではSigning & Capabilitiesで自分のTeamと固有のBundle Identifierを設定してください。現状のBundle Identifierは `com.example.PresentationViewer` です。WindowsにApple SDKはなく、実際に採用・ビルドしたXcode SDKバージョンは未確定です。

```sh
xcodebuild -project PresentationViewer.xcodeproj -scheme PresentationViewer \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PresentationViewer.xcodeproj -scheme PresentationViewer \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

テスト先は `xcodebuild -showdestinations -project PresentationViewer.xcodeproj -scheme PresentationViewer` で利用可能なSimulatorに置き換えてください。Simulator名の例は必須条件ではありません。

## 操作

- 「フォルダを追加」で「このiPhone内」またはiCloud Driveのフォルダを登録します。
- 登録フォルダ直下のPPTX/PDF/SVG/PNG/JPG/JPEGを一覧表示します。大文字拡張子も対応。隠しファイル、サブフォルダ、パッケージ内は対象外です。
- 資料をタップして閲覧し、「閉じる」でライブラリに戻ります。資料ごとのファイルピッカーは表示しません。
- ビューワーの回転アイコンから「横画面にする」「縦画面にする」を選べます。プレゼン中・ツールバー非表示中も利用できます。端末の回転ロックを変更せず、閲覧中の画面にOSの向き変更を要求します。iPadのマルチタスクなどで変更を拒否された場合は案内を表示します。固定状態は保存しません。
- 起動・フォアグラウンド復帰、更新ボタン、下に引く操作で再スキャンします。常時監視やバックグラウンド同期はありません。
- フォルダ管理では追加、スワイプまたは編集による登録解除、アクセスできないフォルダの再選択ができます。登録解除は参照情報だけを削除します。
- グリッドはウィンドウ幅・Size Class・Dynamic Typeに合わせて列数と余白を調整します。サムネイルは縦横比を維持し、長いファイル名は2行で中央省略します。資料IDをスクロール位置として保持し、回転・サイズ変更時の位置維持をSwiftUIに任せます。完全に同じピクセル位置の維持は保証しません。
- キーボードは⌘Oでフォルダ追加、⌘Rで更新、Escで閲覧終了（プレゼン中はモード終了）。標準Buttonとポインターのハイライトを使用します。サイドバーは追加していません。

## 実装とファイルアクセス

`LibraryView` / `FolderManagementView` は標準NavigationStack、LazyVGrid、List、ContentUnavailableViewを使用。`FolderPicker` は `UIDocumentPickerViewController` と `UTType.folder` を使用します。

`LibraryStore` はフォルダ名・ID・ブックマークだけをUserDefaultsに保存します。iOSではAppleのディレクトリアクセス手順に従い `.minimalBookmark` を使用し、暗黙のsecurity scopeを保持します。macOS用の `.withSecurityScope` オプションは使用しません。復元時に古いブックマークを更新し、失敗したフォルダは再選択を案内します。

`FileAccessService` は列挙・初期読み取りをNSFileCoordinatorで調整し、処理中または閲覧中のフォルダのsecurity scopeを保持します。終了・エラー時に解放します。元ファイルへの書き込み・削除・複製は行いません。ビューアーはOSが提供する元URLを直接読み取ります。アプリ独自の一時ファイルやディスクキャッシュは作りません。OS側のQuick Look、WebKit、File Providerの内部キャッシュはOSが管理します。

iCloudの未ダウンロード資料は、開く際のcoordinated readでFile Providerに取得を要求します。処理はメインスレッド外で実施し、進捗表示とエラー案内を行います。取得にはOSによるネットワーク接続が必要な場合があります。アプリ独自のネットワークAPIはありません。

サムネイルはQuickLookThumbnailingで生成し、最大60件・8MiB目安のNSCacheに保持します。更新日時またはサイズが変わると再生成します。未取得のiCloud資料と生成失敗時は形式ごとのSF Symbolを表示します。画面外になったセルの生成結果は表示に反映しません。生成済みUIImageは可視セルでも保持され、8MiBはアプリ全体のメモリ上限ではありません。サードパーティのFile Providerによる取得挙動は各プロバイダーに依存します。

## 表示と制約

|形式|標準コンポーネント|操作・制約|
|---|---|---|
|PPTX|Quick Look|ページ・ズーム等はOSの対応範囲。編集無効。アニメーションやレイアウトの完全再現は保証しません。|
|PDF|PDFKit|連続ページスクロール・ピンチ拡大。幅と高さの両方に合わせて1ページ全体を表示（異なるサイズが混在するPDFは全ページが収まる倍率）。回転・ウィンドウ変更時は全体表示へ戻ります。PDFThumbnailViewによるページ一覧と選択の同期。破損・ロックPDFはエラー表示。パスワード入力なし。|
|SVG|WKWebView|ピンチ拡大・スクロール。XML構文確認、JavaScript無効、外部リソース読み込み無効、ローカル読取範囲は選択ファイルのみ。単体のSVGが対象。外部画像・フォント・スクリプト依存の表示は非対応。|
|PNG/JPG/JPEG|SwiftUI内のUIScrollView / UIImageView|標準のピンチ拡大（全体表示〜5倍）、パン、ダブルタップ。回転・ウィンドウ変更時は1枚全体が収まる倍率へ戻します。単タップでツールバー切替。VoiceOverの拡大・全体表示操作。|

標準システム色でライト／ダークに対応。iPhoneは縦と左右の横画面、iPadは上下の縦と左右の横画面に対応設定しています。フルスクリーン必須を無効にし、Split View / Stage Manager等のウィンドウサイズ変更を妨げません。複数の対話型アプリウィンドウは対象外です。操作ボタンはSafe Area内に保持します。資料自体の背景や色は変更しません。編集・検索・タグ・クラウド基盤は対象外です。

## PDFページ一覧・プレゼンモード

ページ一覧ボタンでPDFThumbnailViewを表示／非表示にします。初期表示はregular幅で左側、compact幅では非表示（表示すると下側）です。表示中のページの選択状態とタップによる移動はPDFKitが管理します。全ページの画像配列を作成・保存する処理や並べ替え操作は追加していません。大量ページのメモリ利用とスクロール性能はOSの実装に依存し、実機での計測が必要です。

「プレゼン」メニューは対応範囲を「PDF・画像」と明示しています。PDFは黒背景の単一ページ表示へ切り替え、サムネイル・ナビゲーションバーを隠します。前後ボタンと左右矢印キーでページ移動できます。終了時は同じPDFビューで連続スクロールへ戻り、ページ位置と拡大率を可能な限り保持します。PDFReadingSessionが資料・ページ番号・ページ数・モードを共有し、PDFViewPageChanged通知でスクロール／サムネイル選択も反映します。

画像のプレゼンは黒背景・全体表示に切り替え、ピンチ・パンは継続利用できます。終了すると通常閲覧の倍率へ戻します（画面サイズ変更時は全体表示）。画像は単一ページのため前後ページ操作はありません。プレゼンの終了・ページ移動ボタンは資料と重ならない領域に配置します。終了ボタンは常に利用可能にし、閉じ込めを防ぎます。PPTX / SVGのプレゼンモードは非対応で、メニュー項目を無効にしています。Quick Look内部の操作や回転を変更する処理は追加していません。

## 外部ディスプレイ

iOS / iPadOS 17〜26の非対話型外部シーン `windowExternalDisplayNonInteractive` とUIWindowSceneを使用します。Info.plistに専用シーンデリゲートを登録し、SwiftUIの主画面のライフサイクルは維持します。HDMI / USB-C / AirPlayの接続と出力先の選択はOSに任せます。アプリ独自のAirPlay選択画面はありません。

OSから外部シーンが提供されたとき、PDFプレゼン中だけ専用UIWindowを割り当てます。本体はページ操作、外部は同じPDFReadingSessionの現在ページを黒背景・縦横比維持で表示します。外部画面には操作UIを載せません。独立した別のページ番号は保持しません。プレゼン終了・閲覧終了・接続解除時にwindowSceneを解放します。独立出力中はOSのミラーリングを置き換え、専用ウィンドウがない場合はOS標準のミラーリング／拡張デスクトップへ任せます。接続先がなくても本体で閲覧・プレゼンを続けられます。

独立出力の初期対応はPDFのみです。画像・PPTX・SVGは標準ミラーリングを利用してください。外部シーンが提供されるかどうかは端末・OS・接続先・Stage Manager等の設定に依存します。メニューの接続状態は独立表示用シーンの有無を示し、物理的なケーブルの検出を保証するものではありません。

Appleの現在のドキュメントではiOS 27以降にUISceneAccessoryによる登録が必要とされています。本実装はXcode 15 / iOS 17 SDKで利用可能なAPIを基準とし、その将来APIを先行導入していません。iOS 27以降の独立表示は対象外・未検証です。その環境ではOS標準ミラーリングを利用し、SDK更新時にシーン登録方式を見直してください。

閲覧中に別アプリが元ファイルを更新・移動・削除した場合、標準ビューアーの再読み込み挙動に依存します。閉じてライブラリを更新し、開き直してください。全形式のライブ更新や完全な読み取りスナップショットは提供しません。非常に大きな画像・PDFは標準デコーダーがメモリを使用します。Quick Look内部の描画失敗をアプリ側からすべて検知するAPIはありません。

## アプリアイコン

独自のスライド／グラフ図案を `PresentationViewer/Assets.xcassets/AppIcon.appiconset` に配置。1024pxの不透明RGB原稿からiOSの各サイズをAsset Catalogで生成します。再生成は `swift tools/render-app-icon.swift PresentationViewer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`。2026-10-08 JSTに署名なしSimulator Debug／実機向けReleaseビルドを確認しました。検証の範囲は [VALIDATION.md](VALIDATION.md)。

## 検証状況

初期開発環境はWindowsでした。2026-10-08 JSTのアイコン追加でMacの署名なしiOSビルドは成功しました。XCTest・アプリ実行は未実施です。起動や各形式の表示、ブックマークの再起動後の有効性、iCloud取得、縦横画面、ダークモードが成功したとは報告していません。

Windowsで実行できるプロジェクトの構造チェックは `python tools/verify_project.py` です。これはXcodeビルドやSwiftの型チェックを代替しません。

既存の `PresentationViewerTests/FileAccessServiceTests.swift` の6件は変更せず維持しています。`ViewerStateTests.swift` にページ境界、モード終了後のページ位置、空の資料、外部表示の共有状態・解除、画像回転時の全体表示、PDFモード・サイズ変更を確認する6件を追加しました。これら13件は当時未実行でした。2026-10-09には新規クラウド6件と合わせてMacで19件が合格しています。横向きでのPDF全体表示の回帰テスト1件を追加しています。既存テスト内の簡易ファイルはアクセス検証用で、描画検証には使いません。

実機での確認項目と結果記録欄は [VALIDATION.md](VALIDATION.md) を参照してください。次回はMacでビルド・テストし、実際の資料で一連の操作を検証することを優先します。配布時のApp Icon、署名・App Store設定はまだありません。

参考: [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)、[NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)、[WKWebViewのローカルファイル読み込み](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:))。

外部表示の参考: [Apple TN3187: シーンとミラーリングの復帰](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle)、[Presenting content on a connected display](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)。

## Phase 11B-1：図解ライブラリ

「ローカル資料」と「図解ライブラリ」をタブで切り替える。既存のフォルダ登録・iCloud Drive閲覧は維持する。図解ライブラリではモック2資料の一覧・タイトル／タグ検索・詳細・PNGページ選択・SVG/PNG/PDF/PPTX取得を利用できる。「開く」は一時キャッシュ、「アプリ内に保存」は永続保存。保存済み資料は通信なしで開け、キャッシュ削除後も残る。取得・保存・オフライン読取時にSHA256とサイズを照合する。

検索窓は一覧上部に常時表示。「すべて／タイトル／タグ」で検索対象を切り替え、入力中に一覧を絞り込む。検索は取得済み一覧が対象（現在は同梱モック全件）。「保存済み」で永続資料を選ぶ。PPTXはQuick Lookで日本語の折り返しが変わる場合があり、見た目を保つ閲覧はPDFを推奨する。公開OIDC・Keychain・実API接続・実機への更新インストールは次工程。AWS認証情報をアプリへ追加していない。

[設計・保存仕様](docs/cloud-library.md)／[今回の検証](docs/phase11b1-validation.md)。モックは同梱fixtureのprotocol実装で、外部HTTPモックサーバーではない。

2026-10-10操作改善：図解ライブラリはサムネイルカードから1タップでPDFを開く方式へ変更。閲覧中の保存ボタンで現在の資料を保存し、そのまま読み続けられる。形式・版情報は補助メニューへ集約。保存済みも同じカードで表示。[変更・検証](docs/ux-refresh-validation.md)。

2026-10-10追加：図解ライブラリを起動時トップ、ローカル資料を第2タブへ変更。SVG表示は廃止。現在形式のPDF/PNG/PPTXから直接形式選択。プレゼン中は全画面資料＋右側の小さな前後・終了操作のみ。[変更・検証](docs/presentation-focus-validation.md)。

## Phase 11B-2（ローカル実装・公開承認待ち）

モックを既定として維持し、本番設定切替、Cognito Code+PKCE、Keychain、refresh/logout、利用者別保存、期限切れURL再発行を追加。接続設定はライブラリ右上のその他メニュー。本番URLは未設定で実S3には未接続。[設定と検証](docs/phase11b2-validation.md)、[現在地](CURRENT.md)。承認後の公開値だけをconfig/cloud-connection.example.jsonに沿って別JSONへ記入し、`python3 tools/configure-cloud.py <approved-settings.json>`でInfoへ反映して再ビルドする。AWSキー／client secretは設定しない。

公開APIは承認後デプロイ済み、公開設定を反映済み。[接続の現在地](docs/phase11b2-deployment.md)。本人のCognito登録／owner設定前は資料アクセス拒否。
