# 図解ライブラリの操作改善

2026-10-10。ユーザーの「全体が使いづらい」という指摘に対し、一覧→閲覧→保存を再設計。改善版を既存iPhoneへ更新した。

## 変更

- 形式別ボタンの詳細画面を削除。サムネイル・タイトル・ページ数・保存済み表示のカード一覧へ変更。
- カードを1タップするとPDFを優先して開く。なければ先頭PNG、SVG、PPTXの順で既存表示処理を使用。
- 閲覧中の保存ボタンで、現在のファイルをSHA256照合して永続保存。再ダウンロードしない。documentのID／表示URLを変更せず、読み続けられる。
- 形式・PNGページ・版／SHA256は補助メニュー／資料情報へ移動。クラウド閲覧時の回転・ページ一覧・プレゼン操作も表示設定にまとめた。
- 保存済みはID・版でまとめ、同じカード一覧から通信なしで閲覧する。保存単位は選択形式／PNGページで、既定PDFは資料全体。
- 入力中は読み込み済み資料を即時絞込。検索確定時はAPI検索。キャッシュ削除はその他メニューへ移動。

## 検証

Simulatorビルド・XCTest **21件合格**（既存19＋PDF優先／先頭PNG選択、APIが使えない状態での閲覧中保存・オフライン再読取の2件）。署名実機ビルド成功。iOS 17.4 Simulatorでカードサムネイル／保存済みバッジと、1タップPDF表示／簡素化したツールバーを目視確認。

既存iPhone「Vespera」へ同Bundle ID・同Apple IDで更新インストールと起動が成功。実機での操作感はユーザーによる確認待ち。モック接続を維持し、本番API・AWS変更なし。

証跡：Git管理外outputs/ux-refresh/final-tests.log、device-build.log、device-install.log、device-launch.log。画面はSimulator上で操作して確認した。変更：CloudLibraryView.swift、CloudLibraryStore.swift、DocumentViewer.swift（任意の追加操作とクラウド時の表示設定）、CloudLibraryTests.swift。新規依存なし。

ローカルフォルダのLibraryView／FileAccessService／LibraryStoreは変更しない。DocumentViewerの既存呼出しは追加操作nilで従来のツールバーを維持。保存のSHA256・不変版・キャッシュ分離を維持する。

## 残課題

実機での操作感、SVG/PPTXの画面品質、機内モード手動確認、OIDC・本番HTTPSは引き続き別途。PPTX Quick Lookの折り返し差は今回修正していない。SVGのみの資料は安全な汎用アイコンで表示し、PNG／PDFのサムネイルを使える資料は実プレビューを表示する。
