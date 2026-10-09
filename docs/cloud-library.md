# 図解ライブラリ：Phase 11B-1

既存ローカルフォルダ機能と、図解ライブラリをTabViewで分離する。図解ライブラリの「クラウド（モック）」は同梱資料をAPI契約に従って取得する実装であり、ネットワークAPIや実S3への接続ではない。

## APIと認証の境界

共通契約はdiagram-design-systemの `docs/viewer-api.md`（2026-10-09 Phase 11A）。CloudLibraryAPIは一覧・検索・cursor・詳細・形式／ページ指定access-url・ダウンロードを分離。MockCloudAPIとHTTPSCloudAPIが同じprotocolを実装する。旧API詳細のJSON input/validationを表示対象から除外し、detailにContent-Typeがない場合は許可形式の固定MIMEを使う。取得grantのMIME・サイズ・ハッシュ・ファイル名・有効期限をdetailと照合する。

HTTPSCloudAPIは将来の接続用アダプターで、現在のアプリは使わない。APIはHTTPS・Bearerのみ、AWSキーなし。token providerを注入し、署名付きartifact取得にはAPIトークンを付けない。署名URLの取得先hostは設定側の許可リストに限定し、redirect・cookie・URLCacheを無効化する。JSONは1 MB、成果物は20 MB未満に限定し、ストリームが期待サイズを超えれば停止する。署名URLはメモリのみでindexへ保存しない。

OIDC Authorization Code＋PKCE、Keychain、更新／ログアウト、issuer/subject別保存領域、公開HTTPS APIの設定は次工程。アプリにパスワード交換や長期キーを追加していない。公開サービスは今回作成しない。

## ファイル管理

- 一時閲覧：Library/Caches/DiagramLibrary。ID・版・形式・PNGページ・SHA256を使う名前。キャッシュ削除対象。
- 永続保存：Library/Application Support/DiagramLibrary。index.jsonと成果物を原子的に保存。アプリ削除時はOSにより削除される。iOSバックアップの標準動作に従う。
- indexには資料ID・版・タイトル・形式・ページ・サイズ・SHA256を保存。ローカル絶対パス・署名URL・トークンは保存しない。パスをAPIのファイル名から直接構成しない。
- 書込前とオフラインopen前にサイズ／SHA256を検査する。同じID・版・形式・ページの異なるハッシュは上書き拒否する。旧版は別ファイルとして保持する。
- ファイル保護はcompleteUntilFirstUserAuthentication。永続保存と一時キャッシュは別のrootで、キャッシュ削除は永続保存へ影響しない。

保存単位は形式／PNGページごと。全形式・全ページの一括保存、保存資料削除UI、容量上限／LRU、自動更新は今回未実装。検索窓を一覧上部に常時表示し、すべて／タイトル／タグで対象を切り替える。入力中に取得済み一覧をローカルで絞り込む。保存済みも同じ検索を利用する。前後の空白を除き、大文字小文字を区別しない部分一致。現在のモックは全件取得で、将来の実API接続時は未取得ページを含む検索方式を別途設計する。

## 表示と互換性

CloudFileStoreから取得したローカルURLをOpenedDocumentへ渡し、既存DocumentViewerを再利用。PDF→PDFKit、PNG→画像ビューアー、SVG→既存のscript／remote resourceを制限したWKWebView、PPTX→Quick Look。PDF/PPTXは全資料、PNGは選択ページ。SVGはモックの単一図解だけで、Phase 7.6のプレゼン保存対象へ追加していない。

iOS 17.4 Quick LookではRAG PPTXの日本語書体・折り返しがPowerPoint/PDFと異なった。形式を取得して開く機能は動作するが、PPTXのレイアウト一致を保証しない。資料詳細でPDFを案内する。生成側の修正は別Development課題に分離する。

モック：RAG8枚のPDF/PPTX/ページPNGはPhase 7.5の公開可能サンプル。SVGは外部参照なしの小さな独自テスト図。原資料や顧客情報・認証情報を同梱しない。ID・版・SHA256を元成果物から維持している。モック版を本番へ切り替えるときはモック／本番データの識別と移行方針を決める。

## 現行UI（2026-10-10更新）

上記の「資料詳細でPDFを案内する」は初期UIの説明。現在はサムネイルカード→PDF優先の直接閲覧→閲覧中の保存。形式・ページ・版／ハッシュとPPTXの注意は補助メニューの資料情報にまとめた。保存済みも資料ID・版でまとめる。[UX改善](ux-refresh-validation.md)が現行の操作仕様。

## Phase 11B-2追加（2026-10-10）

OIDC/Keychain・本番モード切替・利用者別保存・URL再取得はローカル実装済み。[現行検証](phase11b2-validation.md)が今回の正本。上記の未実装記述はPhase 11B-1時点の状態。公開リソースは未作成のため、実Cognitoと本番API／iOS実S3の接続は未検証。
