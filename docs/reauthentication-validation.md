# 再ログインとタブ選択の復帰

2026-10-12 JST。本人から認証エラー時に復帰操作がない、ローカル資料から図解ライブラリへ戻るとプレゼン資料になるとの報告。

一覧・閲覧の認証エラーに「ログインし直す」、その他メニューにも同操作を追加。成功時のみログイン世代を更新してクラウド画面を再作成する。ログアウト不要、端末コピーと利用者別設定を保持。TabViewへ明示的な選択状態と3タブの固定タグを追加。タブ不具合は本人報告に基づく修正で、実機再現・解消確認は未実施。

検証：認証導線変更後のSimulator XCTest 46件合格、失敗0。閲覧画面のコールバック接続後build成功。タブ追加後の最終Simulator buildも成功。認証ブラウザーによる実ログイン・キャンセル、タブの実機操作、実機更新は未実施。AWS/API変更なし。ログ：/tmp/presentation-reauth-test.log、/tmp/presentation-reauth-final-build.log。

実機反映（2026-10-12 JST）：本人のデプロイ依頼後、既存Teamで署名Debug buildとcodesign検証合格。Vesperaへ同Bundle IDで更新インストールし、10:49 JSTに既存プロセス終了・更新版起動成功。端末資料の削除やアンインストールなし。本人の再ログイン/タブ操作確認は未実施。証跡：outputs/reauthentication/device-{build,install,launch}.log。
