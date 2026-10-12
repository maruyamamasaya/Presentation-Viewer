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
