# 現在地

2026-10-10。既存ローカル資料とモック図解ライブラリを維持。Phase 11B-2のPKCE/Keychain・本番設定切替・利用者別保存・URL再取得をローカル実装。署名付きSimulator27テスト合格。接続iPhone更新成功、最終起動は端末Lockedで未確認。AWS公開APIは承認後にデプロイ済み。iOSに公開接続設定を反映、既定モックは維持。本人のメール／owner設定は回答待ち。[適用記録](docs/phase11b2-deployment.md)。実Cognito／実API／iOS実S3・実機操作は未検証。

正本：[検証](docs/phase11b2-validation.md)、[ライブラリ](docs/cloud-library.md)、[README](README.md)。このrepoにAGENTS.mdはなく、diagram-design-system側のAWS承認境界と今回のユーザー指示を適用する。

Phase 11B-3：実Cognito設定・S3公開ブロックを読取確認。本人登録・招待メール送信・owner限定更新が完了。本人の本番ログイン・資料一覧表示成功。本人報告で実機PDF/PNG/PPTXの取得・表示・保存成功。機内モード＋Wi-Fi無効のオフライン閲覧も3形式成功。Phase 11B-3完了。[手順と未実施事項](docs/phase11b3-validation.md)。

2026-10-10：登録資料の容量画面を追加。「その他」から全ライブラリ最新版の件数・成果物容量・取得完了日時を確認・更新できる。既存認証APIを使用し、AWS/API変更なし。Simulatorの29 XCTest合格とサンプル2件・2.4 MBの画面目視を確認。実S3集計・実機更新は未実施。[検証](docs/capacity-validation.md)。

独立一枚図対応：プレゼン資料／図解ライブラリ／ローカル資料の3タブ、オンライン/保存済みtype分類、共通認証を追加。最終31テスト合格、Simulator初期画面目視、既存iPhone Vespera更新/起動成功。本番APIも本人承認後UPDATE_COMPLETE・コードハッシュ一致。本人の新図解表示/拡大操作は確認待ち。[証跡](docs/illustration-validation.md)。

本番設定の誤表示修正：設定済みでも保存ログイン復元失敗を「未設定」と表示する処理を修正。設定/復元を分け、アクティブ復帰時再読取と再試行を追加。32 XCTest・署名build合格。本人の再表示確認待ち。[記録](docs/illustration-validation.md)。

接続準備のままになる続報へ対応：タブごとに共有認証のPublished初期化結果を直接監視するgateへ変更。iOS26の33テスト合格、既存iPhone更新/起動成功。[記録](docs/illustration-validation.md)。

2026-10-10：オンライン閲覧・サムネイルを端末キャッシュ優先へ変更。版別詳細を再利用し、アクティブ復帰で一覧の最新版を確認する。保存済みの旧版は維持。[仕様](docs/cloud-library.md)、[検証](docs/cache-validation.md)。

クラウド資料のゴミ箱移動・復元のUI/APIクライアントをローカル実装。端末保存コピーを保持。本人承認後、本番API/AWSのstate専用権限を反映し、Vespera更新/起動成功。実機移動/復元操作は未確認。[仕様](docs/library-trash.md)。

最新の資料整理：本人の希望でクラウドゴミ箱UIをiPhone内の非表示に切替。非表示/再表示はローカル保存のみ、全版と保存済み一覧へ適用、再起動/キャッシュ削除で維持。既存AWS/APIへの変更なし。[仕様](docs/local-hidden-documents.md)。

端末非表示の検証・反映：39 XCTest、署名build/codesign合格。Vesperaへ更新・起動成功。本人実機の非表示/再表示操作は未確認。

2026-10-10：検索を右上のアイコンへ移動、全て/保存済み切替を廃止し統合一覧へ変更。保存はマーク表示。39 XCTest合格・Simulator一覧目視済み。実機更新と対話操作は未実施。[記録](docs/ui-simplification.md)。

一覧UI簡素化の実機反映：署名build/codesign合格、Vespera更新インストールと更新版起動成功。実機操作は本人確認待ち。[記録](docs/ui-simplification.md)。

2026-10-10：閲覧中央の再生/全画面ボタン、一枚図の縦横比による向き選択を追加。40 XCTest合格・Simulator操作確認。[記録](docs/reader-start-button.md)。

中央開始ボタン版の署名build/codesign合格、Vespera更新/起動成功。実機操作は本人確認待ち。

2026-10-10：図解の端末内「まとめ」を追加。複数資料を1カードに整理し、名前/読む順番の編集・まとめ解除・全画面前後移動・使用ページの一括保存に対応。利用者別の設定を再起動/キャッシュ削除後も保持。AWS/API変更なし。[仕様・検証](docs/diagram-collections.md)。

図解まとめの検証・反映：最終44 XCTestと署名build/codesign合格。Simulatorで作成/順番編集/再起動保持/横画面全画面のページ移動を確認し、Vesperaへ更新・起動成功。本人の実機操作は確認待ち。[証跡](docs/diagram-collections.md)。

2026-10-12：一時コピーのオフライン再起動一覧を追加。取得済み形式だけで開き、通信復帰時は通常一覧へ戻る。確認付きの端末資料一括削除を追加。AWS変更なし。[検証](docs/offline-copies-validation.md)。

端末コピー改善版：2026-10-12本人依頼でVesperaへ署名更新インストール・起動成功。本人の操作確認は未実施。[証跡](docs/offline-copies-validation.md)。

2026-10-12：認証エラーとその他メニューから直接再ログインできる導線、成功後の一覧再読込、タブ選択状態の明示保持を追加。端末コピーは保持。Simulator 46 XCTest合格。実認証・タブの実機確認と実機更新は未実施。[記録](docs/reauthentication-validation.md)。

実機反映（2026-10-12 JST）：本人のデプロイ依頼後、既存Teamで署名Debug buildとcodesign検証合格。Vesperaへ同Bundle IDで更新インストールし、10:49 JSTに既存プロセス終了・更新版起動成功。端末資料の削除やアンインストールなし。本人の再ログイン/タブ操作確認は未実施。証跡：outputs/reauthentication/device-{build,install,launch}.log。

2026-10-13：プレゼン中の透過縦一覧・下中央ページ数・下寄りページ送り・透過終了ボタンを実装。Windowsのproject整合性検査合格。iOSビルド/実機確認は未実施。[仕様・検証](docs/presentation-overlay.md)。

2026-10-13：横向き標準。起動時に横向きを要求し、通常画面は縦・左右横へ回転可能。プレゼン終了/閲覧終了は横向きへ戻して回転を許可。縦長図解の全画面は既存の縦向き選択を維持。Windows構造検査のみ、iOSビルド/実機更新は未実施。

2026-10-13：資料カードは端末の保存/キャッシュ版を優先し、新版がある場合だけ「更新あり」から取得。通常の保存状態マークを除去。[仕様・検証範囲](docs/local-update-notice.md)。Windows構造検査合格、iOSビルド/実機反映は未実施。

2026-10-13：iPhone横向き一覧を基本3列に統一し、表紙の余白を縮小。狭幅/アクセシビリティ文字は2列、縦向き/iPadは維持。Windows構造検査合格、iOSビルド/実機更新は未実施。[仕様](docs/landscape-library.md)。

2026-10-13：資料ごとの仕事／私用／その他と自由タグ編集、上部切替・絞り込みを追加。利用者別端末保存、全版共有。Windows構造検査のみ、iOSビルド・XCTest・実機反映は未実施。[仕様・検証](docs/library-classification.md)。

2026-10-14：最新mainのVespera更新・起動成功。LibraryViewの並行処理コンパイルエラーを最小修正。署名build/codesignとSimulator49 XCTest合格。実機操作は未確認。[記録](docs/vespera-install-20261014.md)。

2026-10-14：iPhone一覧の常設分類/タブを左下の引き出しへ集約。プレゼンの一覧と下操作を本文から分離。Simulator49 XCTestとbuild合格、横向きPNGの目視確認。実機反映は未実施。[仕様・検証](docs/library-sidebar.md)。

同UIの実機反映：本人依頼後、Vesperaの署名build/codesign・更新インストール・更新版起動成功。実機の操作感は本人確認待ち。[記録](docs/library-sidebar.md)。

2026-10-14追加改修：一覧入口を右下48pt丸ボタンへ変更し、右から左へパネル展開。資料閲覧のタイトルバーを除去し、資料名/形式/保存/閉じるを右パネルへ配置。最終Simulator/Device build・codesign、横向き目視、Vespera更新インストール成功。[記録](docs/library-sidebar.md)。

追加改修版の実機起動：端末ロック（Locked）で起動要求が拒否された。更新インストールは成功。ロック解除後の起動・操作確認は未完了。

2026-10-14：再生アイコンを除去しPNG/PDFのタップ開始へ変更。下操作行を除去、左上ページ数/右上終了/左右中央前後・横スワイプを実装。両形式のSimulator目視と最終build/codesign合格、Vespera更新インストール成功。[記録](docs/library-sidebar.md)。

タップ開始/左右操作版：Vesperaの更新版起動成功。実機の操作確認は本人確認待ち。

2026-10-14：iPhoneアプリ全体を左右の横向き専用へ変更。起動/復帰と縦長図解/閲覧終了の方向を統一。[仕様・検証](docs/iphone-landscape-only.md)。

横向き専用版の実機反映：2026-10-14 JST、Vesperaへ署名build/codesign・更新インストール・更新版起動成功。実機操作は本人確認待ち。[記録](docs/iphone-landscape-only.md)。

2026-10-14：右メニュー幅を260ptへ縮小、iPhoneの資料を閉じる操作を外出し。通常閲覧は左上、全画面は右上×で直接閉じる。実機build/codesign・Vespera更新/起動成功。本人操作確認待ち。[記録](docs/library-sidebar.md)。
