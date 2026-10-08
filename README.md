# Presentation Viewer

iPhone用の資料閲覧専用SwiftUIアプリ。iOS 17以降。外部ライブラリ、サーバー、認証、データベースなし。

## 開く・実行する

MacのXcode 15以降で `PresentationViewer.xcodeproj` を開き、`PresentationViewer` SchemeとiPhone Simulatorを選択してRunします。実機ではSigning & Capabilitiesで自分のTeamと固有のBundle Identifierを設定してください。現状のBundle Identifierは `com.example.PresentationViewer` です。

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
- 起動・フォアグラウンド復帰、更新ボタン、下に引く操作で再スキャンします。常時監視やバックグラウンド同期はありません。
- フォルダ管理では追加、スワイプまたは編集による登録解除、アクセスできないフォルダの再選択ができます。登録解除は参照情報だけを削除します。

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
|PDF|PDFKit|連続ページスクロール・ピンチ拡大。破損・ロックされたPDFはエラー表示。パスワード入力機能なし。|
|SVG|WKWebView|ピンチ拡大・スクロール。XML構文確認、JavaScript無効、外部リソース読み込み無効、ローカル読取範囲は選択ファイルのみ。単体のSVGが対象。外部画像・フォント・スクリプト依存の表示は非対応。|
|PNG/JPG/JPEG|SwiftUI Image|ピンチ拡大（1〜5倍）、スクロール、ダブルタップ。破損画像はエラー表示。|

標準システム色でライト／ダークに対応し、iPhoneの縦画面・左右の横画面を許可しています。資料自体の背景や色は変更しません。iPad・編集・検索・タグ・クラウド基盤は対象外です。

閲覧中に別アプリが元ファイルを更新・移動・削除した場合、標準ビューアーの再読み込み挙動に依存します。閉じてライブラリを更新し、開き直してください。全形式のライブ更新や完全な読み取りスナップショットは提供しません。非常に大きな画像・PDFは標準デコーダーがメモリを使用します。Quick Look内部の描画失敗をアプリ側からすべて検知するAPIはありません。

## 検証状況

開発環境はWindowsです。Xcode、Apple SDK、Swiftコンパイラー、iOS Simulator、実機がなく、iOSビルド・XCTest・アプリ実行は未実施です。起動や各形式の表示、ブックマークの再起動後の有効性、iCloud取得、縦横画面、ダークモードが成功したとは報告していません。

Windowsで実行できるプロジェクトの構造チェックは `python tools/verify_project.py` です。これはXcodeビルドやSwiftの型チェックを代替しません。

`PresentationViewerTests/FileAccessServiceTests.swift` はMacで実行するXCTestです。対応形式・隠しファイル・サブフォルダの除外、ブックマーク復元、追加・削除・更新の再スキャン、空ファイル、削除フォルダ、重複排除、元ファイル保持、UserDefaults復元・登録解除を検証します。テスト内の簡易ファイルはスキャン／アクセス検証用で、各フォーマットの描画検証には使いません。

実機での確認項目と結果記録欄は [VALIDATION.md](VALIDATION.md) を参照してください。次回はMacでビルド・テストし、実際の資料で一連の操作を検証することを優先します。配布時のApp Icon、署名・App Store設定はまだありません。

参考: [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)、[NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)、[WKWebViewのローカルファイル読み込み](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:))。
