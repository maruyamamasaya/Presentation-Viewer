# 大容量資料のiOS読込修正

2026-10-15 JST。本人の「資料が開けませんでした」報告を受け調査。API側の承認済み例外とは別に、iOSのCloudFile.validateとHTTPSCloudAPI.downloadへ1ファイル20,000,000 bytes未満の制限が残存していた。CloudDetailは全形式を検査するため、29,640,691 bytesのPDFと20,067,274 bytesのPPTXがある資料では、画像での閲覧開始も拒否された。

CloudArtifactSizePolicyを同じコンパイル済みCloudModels.swiftに追加。UUID4f2af5d0-86c9-4709-9dad-9f6a67e5ac10・版1・40ページ・presentationの原本PDF/PPTXだけ、名前・Content-Type・サイズ・SHA256の完全一致で許可する。署名URLのダウンロードでは同じ2ファイルの名前/Content-Type/サイズ/ハッシュに限定して許可。ID/版は詳細情報の検査で確認する。通常20MB上限・HTTPS/ホスト許可・期限/GET・認証ヘッダー非送信・実サイズ/保存時ハッシュ検査は維持。一般的な上限緩和やAWS変更ではない。

検証：Swiftの許可値が送信承認済みPDF/PPTXと一致。iPhone17e/iOS26.5 Simulatorで53 XCTest全件合格。新規2件は別資料/別版/ページ数/サイズ/ハッシュの拒否と、実際の29.64MB PDFの40ページ読込・キャッシュ・保存・キャッシュ削除後のストア再生成/オフライン再表示を検証。実PDF試験は任意のローカルfixture（outputs/large-presentation-fixture/document.pdf）を使用し、この実行ではskipせず合格。構造検査・diff検査・既存Team/Bundle IDの署名build/codesign合格。ログ /private/tmp/zukan-large-test.log、/private/tmp/zukan-large-device-build.log。

既存の保存料金シミュレーション等の未コミット変更は保持。本件でCloudFiles/CloudLibraryViewを変更していない。既存端末資料やログイン情報を削除しない。実機反映/操作の結果は以下へ追記。

実機反映：2026-10-15 JST、Vesperaへ同Team U29GY347DY/Bundle ID com.example.PresentationViewerの修正版更新インストール成功。17:00 JSTに更新版起動成功。アンインストール・保存資料削除なし。本人の資料表示操作は未確認。ログ /private/tmp/zukan-large-device-{install,launch}.log。
