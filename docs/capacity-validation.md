# 登録資料の容量（2026-10-10）

要求：iOSで登録資料の最新版の合計容量と件数・更新日時を表示し、S3全体の容量はCLIで別途確認する。

変更：CloudAPI.swiftのcapacityで空検索/all scopeの全一覧ページを取得、ID別最新版を選び、詳細の既知成果物サイズを合算。旧版・管理ファイルは除外。カーソル循環、詳細不正、途中失敗、キャンセル時は部分合計を返さない。CloudLibraryView.swiftに「その他」→「登録資料の容量」のsheetと更新操作を追加。初回は未取得、更新失敗時は前回値の日時を維持して案内する。毎秒1リクエストの公開APIに合わせた通信間隔。ファイル本体取得・AWS設定変更・公開API改修はない。

検証：tools/verify_project.py合格、git diff --check合格。XcodeのiPhone 15 Pro/iOS 17.4 Simulator通常署名testで29件、失敗0。追加2件は全ページ/最新版/全形式/空一覧、途中失敗/カーソル循環、成果物の取得禁止を確認。署名なしの初回試行では既存Keychain関連テストが失敗し、通常Simulator署名で再検証した。Apple側資産の更新は行っていない。結果は/private/tmp/presentation-capacity-build/Logs/Test配下。

Simulatorに更新版を入れ、その他メニュー→容量sheetを開いて目視確認。サンプル2件・2.4 MB・2026年10月10日10:02、更新ボタンと対象説明が表示され、重なりなし。これはモックの表示検証であり、実S3容量の測定ではない。

未実施：本番ログイン後の容量集計、実iPhoneへの更新、実機容量画面、Dynamic Type/iPad、新機能でのオフラインエラー操作。API catalogの最大60秒キャッシュと、集計途中の更新に対するスナップショットがない制約は[仕様](cloud-library.md)参照。
