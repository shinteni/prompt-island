# Vibelsland Free

<p align="center">
  <img src="docs/assets/readme/app-icon.png" alt="Vibelsland Free app icon" width="128">
</p>

<p align="center">
  <a href="README.md">中文</a> | <a href="README.en.md">English</a> | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <strong>macOS 向けのローカル AI コーディング状態ビューア。</strong>
</p>

<p align="center">
  <a href="https://shinteni.github.io/prompt-island/ja/">公式サイト</a>
  ·
  <a href="https://github.com/shinteni/prompt-island/releases/download/v0.2.0/Vibelsland-Free-0.2.0-macos.zip">v0.2.0 をダウンロード</a>
  ·
  <a href="https://shinteni.github.io/prompt-island/ja/install.html">インストールと信頼</a>
  ·
  <a href="PRIVACY.md">プライバシー</a>
  ·
  <a href="#ソースからビルド">ソースからビルド</a>
</p>

<p align="center">
  <img src="docs/assets/readme/hero-island-light.jpg" alt="Vibelsland Free floating island interface" width="960">
</p>

`macOS 14+` `Swift` `Local-first` `No telemetry` `Claude Code` `Codex CLI` `Codex Desktop`

## Claude Code / Codex の状態を確認

Vibelsland Free は、Claude Code、Codex CLI、Codex Desktop を日常的に使う開発者向けの macOS ネイティブユーティリティです。ローカルセッション状態、ツール実行、トークン使用量の概要、承認リクエストを画面上部にまとめて表示します。

作業中は状態を画面上部に表示し、アイドル時は非表示になります。タスク実行中はコンパクトに表示し、承認が必要なときはパネルとして展開します。

## 主な特徴

- **画面上部のフローティング表示**：無タスク時は非表示、作業中はコンパクト表示、対応が必要なときは展開パネル。
- **ステータス表示**：実行中、完了、失敗、承認待ちを色と動きで区別します。
- **AI コーディングツールの統合ビュー**：Claude Code、Codex CLI、Codex Desktop を 1 つの表示にまとめます。
- **セッションサマリー**：タスク名、ツール実行、AI 応答の抜粋、トークン使用量、最近の活動を表示します。
- **承認センター**：許可、拒否、継続、キャンセルなどの承認操作をアイランド上で処理できます。
- **ヘルスダッシュボード**：設定画面から Bridge、Hooks、Codex Desktop 接続、ログ、ローカル実行状態を確認できます。
- **ローカルファーストのプライバシー**：アカウント不要、テレメトリ送信なし、クラウド同期なし。主要機能はローカルで動作します。

## 想定ユーザー

- Claude Code、Codex CLI、Codex Desktop を日常的に使う開発者。
- ウィンドウを切り替えずに AI タスク状態を確認したい人。
- 承認リクエスト、ツール実行、セッション進捗を 1 つの macOS ネイティブ画面にまとめたい人。
- 操作の邪魔になりにくい、ローカル中心の開発者向けツールを好む人。

## 技術アーキテクチャ

Vibelsland Free は Swift Package ベースの macOS ネイティブアプリです。UI 層は SwiftUI と AppKit を組み合わせ、メニューバー項目、フローティングアイランド、設定ウィンドウを構成しています。中核ロジックは `Sources/VibelslandFreeCore` にあり、セッション解析、承認マッピング、重複排除、表示ポリシー、再起動復旧、ヘルスチェックをテストしやすいポリシーモジュールに分けています。

ローカルデータフローは、Claude Code / Codex CLI Hooks と Codex Desktop のローカル状態を Bridge と reader が受け取り、`AgentEvent` / `AgentSession` に正規化し、`SessionStore` が画面上部のアイランド表示を駆動する構成です。実行時通信はローカルファイル、Unix socket、ローカル設定のみを使い、アカウントやリモートサービスを必要としません。

## 検証方針

このリポジトリには Swift 単体テスト、リリースパッケージングスクリプト、ドキュメントサイト検証、macOS ウィンドウ自動化検証が含まれています。主な入口は `zsh scripts/run-tests.sh`、`zsh scripts/verify-docs-site.sh`、`zsh scripts/verify-release-readiness.sh` です。GitHub Actions は、ソース、テスト、パッケージ設定の変更時に Swift のビルドとテストを実行します。ローカル環境が CommandLineTools のみの場合、`scripts/run-tests.sh` はテストターゲットのコンパイル/検出チェックに明示的に降格します。ドキュメント変更時には GitHub Pages のデプロイと検証を行います。

## ダウンロードとインストール

v0.2.0 は GitHub Releases からダウンロードできます。現在のリリースは ad-hoc 署名のため、初回起動前にインストールと信頼の説明を確認してください。

[v0.2.0 をダウンロード](https://github.com/shinteni/prompt-island/releases/download/v0.2.0/Vibelsland-Free-0.2.0-macos.zip)

[インストールと信頼](https://shinteni.github.io/prompt-island/ja/install.html)

ダウンロードを検証します。

```sh
curl -LO https://github.com/shinteni/prompt-island/releases/download/v0.2.0/Vibelsland-Free-0.2.0-macos.zip
curl -LO https://github.com/shinteni/prompt-island/releases/download/v0.2.0/Vibelsland-Free-0.2.0-macos.zip.sha256
shasum -a 256 -c Vibelsland-Free-0.2.0-macos.zip.sha256
```

現在の SHA-256:

```text
ce3ce10b8ba7b0e388962d660c5c416cd6c246405462c2a578be46aeadd3fab4
```

インストール手順:

1. `Vibelsland-Free-0.2.0-macos.zip` をダウンロードします。
2. 解凍し、`>_ - island.app` を `Applications` に移動します。
3. アプリを開き、メニューバーまたは設定画面から Hooks をインストールします。
4. 必要に応じてログイン時起動、サウンド、おやすみモード、表示位置を設定します。

Homebrew でもインストールできます（このリポジトリは tap を兼ねており、cask のバージョンと SHA-256 は `docs/release.json` から生成されます）:

```sh
brew tap shinteni/island https://github.com/shinteni/prompt-island.git
brew install --cask shinteni/island/vibelsland-free
```

注記：現在の無料リリースは ad-hoc codesign を使用しているため、初回起動時に Gatekeeper の確認が必要です。Developer ID 署名と notarization は今後の配布改善として対応できますが、現在の v0.2.0 はダウンロード、チェックサム、ソース、インストール手順を公開しています。

## プライバシー

Vibelsland Free はローカルファーストのツールです。アカウントを作成せず、テレメトリを送信せず、リモートサーバーへ同期しません。Claude Code、Codex CLI、Codex Desktop のローカル状態だけを読み取り、セッション状態、ツール実行、トークン使用量の概要、承認リクエストの表示に使います。

詳細は [PRIVACY.md](PRIVACY.md) を確認してください。

## ソースからビルド

```sh
swift build
zsh scripts/run-tests.sh
zsh scripts/package-release.sh
```

`scripts/package-release.sh` は [docs/release.json](docs/release.json) のパッケージ名とアプリ識別情報を読み取り、ローカル zip と `.sha256` ファイルを生成します。新しく作成したローカルパッケージの hash が `docs/release.json` と異なる場合、スクリプトは未公開候補として扱います。Web サイトの checksum だけを更新せず、対応する GitHub Release アセットのアップロードとメタデータ更新を同時に行ってください。現在のローカル `dist/` と公開リリースの一致を確認するには、次を実行します。

```sh
VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-site.sh
VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-live.sh
```

メンテナー向けの公開手順、カスタムドメインビルド、リリース前チェックの詳細は [MAINTAINER_RELEASE_CHECKLIST.md](MAINTAINER_RELEASE_CHECKLIST.md) にあります。

注記：このリポジトリは当初 `prompt-island` をリポジトリ名として使っていました。現在の製品名は Vibelsland Free で、アプリバンドル名は `>_ - island.app` です。

## プロジェクト状態

Vibelsland Free v0.2.0 は、画面上部のフローティング表示、設定画面、Hook インストール、承認 UI、ランタイムヘルスチェック、単一インスタンス保護、再起動復旧、リリースパッケージングスクリプトを含みます。現在の無料リリースは ad-hoc 署名で、公開ダウンロード、SHA-256 検証、ソース、インストール手順、サポート入口を提供しています。

## ライセンス

Vibelsland Free は [MIT License](LICENSE) の下で公開されています。

## 独立性について

Vibelsland Free は独立したユーティリティです。Anthropic、OpenAI、Claude、Codex とは提携していません。各製品名はローカル互換性を説明するためにのみ使用しています。
