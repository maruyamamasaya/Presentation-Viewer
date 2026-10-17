# 整理共通パッケージ

LibraryGroup/LibraryClassificationはLibraryOrganizationのalias、CloudCollectionはReadingCollection<CloudDiagram>のalias。既存の分類・タグ・まとめJSONキーと値、順序とオフラインスナップショットをそのまま保持する。CloudDiagramの検証・最新版解決・非表示・閲覧はiOS extensionで維持。保存ファイルの一括変換は行わない。

Xcodeのローカル依存は ../diagram-design-system/packages/LibraryOrganization。同じ親に2リポジトリが必要。仕様の正本は同repo docs/library-organization.md。同期・Macの実パス・認証情報は共有しない。今回iOSへのフォルダUI追加・実機配布は行わない。

検証：2026-10-17、generic iOS Simulator build成功。arm64・通常Simulator署名で既存57 XCTest合格/失敗0。署名なし実行のKeychain失敗は通常署名で解消。実機配布/操作は今回実施なし。
