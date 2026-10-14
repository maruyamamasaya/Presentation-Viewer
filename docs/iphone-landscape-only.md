# iPhone横向き専用

2026-10-14 JST。本人の依頼でiPhoneアプリ全体を左右の横向きに限定。

- Debug/Releaseの対応方向からPortraitを除去。iPadの4方向は維持。
- AppOrientationPolicyはiPhoneで縦向きや自由回転の要求を横向きへ正規化。閲覧終了や縦長図解でも縦向きを許可しない。
- 起動/再表示と対象UIWindowSceneのアクティブ復帰で横向きを要求。外部表示シーンへ要求しない。
- 縦長資料は既存の縦横比を維持する表示で閲覧。端末の回転ロック設定は変更しない。

検証：Xcode 26.6、iPhone 17e Simulator/iOS 26.5で通常署名buildと49 XCTest合格。構造検査とgit diff --check合格。生成Info.plistのiPhone対応方向が左右の横向きだけであることを確認。署名なし初回検証は既存Keychainテスト2件で認証エラー（3 assertions）となり、通常署名で全件合格。シミュレーター起動要求は成功したが、画面キャプチャは安定せず横向きの目視確認は未完了。実機更新/操作・回転ロック中・復帰時の実機確認は未実施。


## 実機更新（2026-10-14 JST）

本人依頼によりVespera（iPhone 17e、UDID末尾0E33401C）へ、既存Team U29GY347DY・Bundle ID com.example.PresentationViewerで署名Debug build、codesign検証、同Bundle ID更新インストール成功。11:11 JSTに既存プロセスを終了して更新版起動成功。生成Info.plistのiPhone方向は左右Landscapeのみ。保存資料の削除やアンインストールなし。実機の表示/復帰/回転ロック中の操作は本人確認待ち。ログ：outputs/iphone-landscape-only/device-{build,install,launch}.log。
