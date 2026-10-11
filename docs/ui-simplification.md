# 一覧UIの簡素化

2026-10-10。本人との議論で合意した検索アイコン化、全て/保存済み切替の撤去、保存マーク表示を実装。対象はCloudLibraryViewのプレゼン資料・図解ライブラリ。分類タブと別画面の閲覧は維持。

検索は右上から開閉し、閉じると入力/検索対象をリセット。クラウド一覧と保存資料をID・版で統合し、保存だけの版は端末ファイルを開く。保存状態はbookmark.fill、閲覧中の保存はbookmarkで表現。既存の形式/ページ単位保存を維持し、保存解除は追加していない。AWS/API変更なし。

検証：iPhone 15/iOS17.4 Simulatorで39 XCTest合格（0 failures）、Swiftコンパイル成功。一覧スクリーンショットを目視し、右上検索アイコン、切替撤去、小さい見出し、カード配置に崩れがないことを確認。検索開閉・保存の対話操作、オフライン統合一覧の手動操作、実機の画面操作は未確認。

証跡：outputs/ui-simplification/build/Logs/Testのxcresult、outputs/ui-simplification/library.png。仕様は[cloud-library](cloud-library.md)。

実機反映：本人の依頼で既存Teamの署名Debugビルド・codesign検証に合格し、Vesperaへ同Bundle IDで更新インストール。更新版の起動成功。証跡はoutputs/ui-simplification/device-build.log、device-install.log、device-launch.log。検索・保存の実機操作は本人確認待ち。
