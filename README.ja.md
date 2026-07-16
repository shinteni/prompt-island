# Vibelsland Free

<p align="center">
  <img src="docs/assets/readme/app-icon.png" alt="Vibelsland Free app icon" width="128">
</p>

<p align="center">
  <a href="README.md">中文</a> | <a href="README.en.md">English</a> | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <strong>macOS 向けのローカルファースト AI コーディングステータスアイランド。</strong>
</p>

<p align="center">
  <a href="https://shinteni.github.io/prompt-island/ja/">公式サイト</a>
  ·
  <a href="https://github.com/shinteni/prompt-island/releases/download/v0.2.1/Vibelsland-Free-0.2.1-macos.zip">v0.2.1 をダウンロード</a>
  ·
  <a href="https://shinteni.github.io/prompt-island/ja/install.html">インストールガイド</a>
  ·
  <a href="PRIVACY.md">プライバシー</a>
  ·
  <a href="LICENSE">MIT License</a>
</p>

<p align="center">
  <img src="docs/assets/readme/hero-island-light.jpg" alt="Vibelsland Free floating island interface" width="960">
</p>

`macOS 14+` `Claude Code` `Codex CLI` `Codex Desktop` `Local-first` `No telemetry`

Vibelsland Free は、Claude Code、Codex CLI、Codex Desktop のタスク状態、ツール実行、トークン概要、承認リクエストを画面上部のアイランドにまとめて表示します。待機中は静かに隠れ、タスクの実行中や対応が必要なときに自動で表示されます。

## 主な機能

- 実行中、完了、失敗、承認待ちの状態を画面上部で確認できます。
- タスク名、ツール実行、AI 応答の概要、トークン使用量、最近の活動を表示します。
- 許可、拒否、継続、キャンセルなどの操作をアイランドから処理できます。
- Claude Code、Codex CLI、Codex Desktop を 1 つの画面にまとめます。
- 日本語、英語、中国語に対応し、サウンド、ショートカット、集中モード、表示位置を設定できます。
- アカウント不要、テレメトリ送信なしで、主要データは Mac 内に保存されます。

## ダウンロードとインストール

[Vibelsland Free v0.2.1 をダウンロード](https://github.com/shinteni/prompt-island/releases/download/v0.2.1/Vibelsland-Free-0.2.1-macos.zip)し、解凍後に `>_ - island.app` を「アプリケーション」フォルダへ移動してください。

現在のリリースは ad-hoc 署名です。初回起動時に macOS にブロックされた場合は、[インストールと信頼の説明](https://shinteni.github.io/prompt-island/ja/install.html)に従ってください。

Homebrew でもインストールできます。

```sh
brew tap shinteni/island https://github.com/shinteni/prompt-island.git
brew install --cask shinteni/island/vibelsland-free
```

## 使い方

1. `>_ - island.app` を開きます。アプリはメニューバーに常駐し、タスク開始時に画面上部へアイランドが表示されます。
2. メニューバーの `>_` アイコンから「設定」を開き、「受信元」で Claude Code、Codex CLI、Codex Desktop を必要に応じて有効にします。
3. Claude Code または Codex CLI を使う場合は、メニューバーから「Hooks をインストール」を選びます。Codex Desktop は Hook 不要で、現在のユーザーのローカル状態を読み取ります。
4. 通常どおり AI コーディングタスクを開始します。アイランドをクリックすると詳細を確認でき、承認リクエストにも対応できます。
5. 設定画面に接続エラーが表示された場合は、「メンテナンス」の「接続を修復」を実行してから再チェックします。

言語、アイランド位置、ログイン時起動、サウンド、集中モード、グローバルショートカットは設定画面で変更できます。

## プライバシーとライセンス

Vibelsland Free はアカウントを作成せず、テレメトリを送信せず、セッションをリモートサーバーへ同期しません。詳細は [PRIVACY.md](PRIVACY.md) を確認してください。

このプロジェクトは [MIT License](LICENSE) の下で公開されています。

Vibelsland Free は独立したユーティリティであり、Anthropic、OpenAI、Claude、Codex とは提携していません。各製品名はローカル互換性を説明するためにのみ使用しています。
