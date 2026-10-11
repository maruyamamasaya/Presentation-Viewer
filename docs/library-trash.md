# クラウド資料のゴミ箱

2026-10-10。クラウド資料カード「…」→「ゴミ箱に移動」で確認。右上の「その他」→「ゴミ箱」で一覧、カード「…」→「復元」。資料種別ごとに表示する。保存済みの端末コピーは保持。全版が対象、完全削除・自動削除なし。

CloudLibraryAPIへlistTrash/setTrashed、HTTPSCloudAPIへstate=trashedとtrash/restoreリクエストを追加。既存のHTTPS/認証を利用し、AWSキーは配布しない。失敗時に一覧から消さない。ゴミ箱からの閲覧・サムネイル新規取得は行わない。

APIとAWSの正本はdiagram-design-system/docs/library-trash.md。本人承認後、本番APIへのコード・state専用権限・環境設定反映がUPDATE_COMPLETE。既存Vesperaへ同Bundle IDで署名更新インストール・更新版起動が成功。iPhone 15 / iOS 17.4 Simulatorでビルド・38 XCTest合格。ゴミ箱移動/復元・通信失敗時一覧維持・端末保存保持を確認。最初の2試行は容量検証で中断し失敗、分離実行で全件合格。新しい画面の目視と実機操作は未実施。本番の認証済み移動/復元と新UIの実機操作は未確認。
