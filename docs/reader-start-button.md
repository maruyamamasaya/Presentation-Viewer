# 閲覧画面の中央開始ボタン

2026-10-10。資料を開いた通常閲覧画面の中央に開始ボタンを追加。プレゼン資料は再生アイコンで横画面プレゼンへ、一枚図は拡大アイコンで全画面表示へ入る。分類はCloudLibraryKindに従い、1ページだけのプレゼンを一枚図と推測しない。

一枚図の向きはPDFの表示ページのサイズ、画像はUIImageのサイズから判断。横長はlandscape、縦長・正方形・サイズ不明はportrait。全画面中は中央ボタンと通常ツールバーを隠し、一枚図は前後ページボタンを出さない。終了ボタンから通常閲覧・縦画面に戻る。PDF・画像の既存拡大/保存/形式切替を維持。PPTXのQuick Lookはプレゼン非対応のため中央ボタンを出さない。OSが向き変更を拒否した場合は既存の案内を表示。

検証：40 XCTest合格（縦横・正方形・サイズ不明・プレゼン向き判定を追加）。Simulatorでプレゼン中央再生ボタン→横画面全画面→終了→縦画面復帰、一枚図中央拡大ボタン→横画面全画面（ページ操作なし）を操作・目視確認。縦長図解のUI手動確認、実機操作は未実施。証跡はoutputs/ui-simplification/reader-tests.logと同build/Logs/Testのxcresult。AWS/API変更なし。

実機反映：既存Teamの署名buildとcodesign検証合格。Vesperaへ同Bundle IDで更新インストール、更新版起動成功。本人の実機操作は確認待ち。証跡はoutputs/ui-simplification/reader-device-{build,install,launch}.log。
