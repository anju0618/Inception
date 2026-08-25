*This project has been created as part of the 42 curriculum by amakino.*

## Description

Inception is a system administration project that builds a small, self-contained web
infrastructure using Docker and Docker Compose, entirely inside a personal virtual
machine. The goal is to understand how to containerize and orchestrate a realistic
multi-service stack from scratch, without relying on any pre-built service images.

The mandatory infrastructure is made of three custom-built Docker images, each running
in its own container:

- **NGINX** — the single entry point of the infrastructure, exposing port 443 and
  accepting only TLSv1.2/TLSv1.3 connections. It forwards PHP requests to WordPress
  over FastCGI.
- **WordPress + php-fpm** — the CMS itself, installed and configured non-interactively
  with `wp-cli`, without NGINX bundled in the same container.
- **MariaDB** — the database backend for WordPress, without NGINX bundled in the same
  container.

All three containers are connected through a dedicated Docker bridge network, and the
WordPress database and website files are persisted through two named Docker volumes
backed by `/home/amakino/data` on the host.

On top of the mandatory part, the following bonus services were added, each in its own
container/image:

- **Redis** — object cache for WordPress (via the `redis-cache` plugin).
- **FTP server** (vsftpd) — exposes the WordPress volume for file transfer.
- **Static website** — a small Python 3 (`http.server`) site, independent from PHP.
- **Adminer** — a lightweight web UI to inspect/manage the MariaDB database.
- **Backup service** — a `cron`-driven container that periodically dumps the WordPress
  database to a dedicated volume and prunes old backups (service of choice).

## Instructions

### Prerequisites

- A virtual machine (this project must be built and run inside one) with Docker and
  Docker Compose installed.
- `secrets/*.txt` files present (see [DEV_DOC.md](./DEV_DOC.md) for how to generate
  them) — these are intentionally excluded from Git.
- The host's `/etc/hosts` (or the evaluator's) must map `amakino.42.fr` to the VM's IP
  address.

### Build & run

```sh
make            # builds every image and starts the stack in the background
make down       # stops and removes the containers
make re         # full clean + rebuild
```

See [USER_DOC.md](./USER_DOC.md) for day-to-day usage and [DEV_DOC.md](./DEV_DOC.md)
for the full developer setup, build, and data-management workflow.

## Project design choices

Every service is built from `debian:bookworm-slim` (the penultimate stable Debian
release at the time of writing), with an explicit tag (never `latest`), and its own
hand-written Dockerfile — no ready-made service image is pulled from any registry.
Each container runs a single foreground process as PID 1 (e.g. `nginx -g "daemon
off;"`, `php-fpm -F`, `mariadbd`, `cron -f`), so it receives and handles signals
correctly and can be stopped/restarted cleanly by Docker; no `tail -f`, `sleep
infinity`, or busy `while true` loops are used to keep a container alive.

### Virtual Machine vs Docker

A VM virtualizes a whole machine, including its own kernel, on top of a hypervisor:
strong isolation, but heavier to boot and to run. Docker containers share the host
kernel and use Linux namespaces/cgroups to isolate processes: much lighter and faster
to start, with image layers enabling efficient reuse and distribution. In this project
both are used together: the VM provides one fully isolated environment for the whole
exercise (as required by the subject), while Docker is used inside it to isolate and
orchestrate each individual service.

### Secrets vs Environment Variables

Environment variables (e.g. from a `.env` file) are convenient for non-sensitive
configuration (domain name, database name, usernames...), but they are easy to leak:
they show up in `docker inspect`, in `/proc/<pid>/environ`, and often end up in logs.
Docker secrets are mounted as files under `/run/secrets/<name>` inside the container
and never appear in `docker inspect` or in the container's declared environment. This
project keeps non-sensitive settings in `srcs/.env` and stores every password
(database root/user passwords, WordPress admin/user passwords, FTP password) as a
Docker secret, read from `secrets/*.txt` files that are excluded from Git.

### Docker Network vs Host Network

`network: host` (or `--link`) makes a container share the host's network namespace
directly, which breaks the isolation between services and is forbidden by the
subject. This project instead declares a dedicated bridge network (`inception`) in
`docker-compose.yml`; containers reach each other by service name (e.g. `wordpress`
resolves `mariadb`'s IP through Docker's embedded DNS) while staying isolated from the
host's network stack, with only NGINX's port 443 published to the host.

### Docker Volumes vs Bind Mounts

A bind mount maps an arbitrary host path directly into a container: simple, but tightly
coupled to the host's filesystem layout and less portable. A named volume is managed by
Docker itself and can still be pinned to a specific host path through `driver_opts`
without behaving like a raw bind mount. The subject requires named volumes for the
WordPress database and website files, both physically stored under
`/home/amakino/data` on the host: `docker-compose.yml` declares `wordpress_data` and
`mariadb_data` as named volumes with `driver: local` and `driver_opts: {type: none, o:
bind, device: /home/amakino/data/...}`.

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- ["Docker and the PID 1 zombie reaping problem"](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WP-CLI documentation](https://wp-cli.org/)
- [MariaDB documentation](https://mariadb.com/kb/en/)
- [vsftpd documentation](https://security.appspot.com/vsftpd.html)
- [Adminer](https://www.adminer.org/)
- [Redis Object Cache plugin](https://wordpress.org/plugins/redis-cache/)

### Japanese-language resources

- [Docker ドキュメント日本語化プロジェクト (docs.docker.jp)](https://docs.docker.jp/) — community translation of the official Docker docs
- [Docker Compose ファイル v3 リファレンス（日本語）](https://docs.docker.jp/compose/compose-file/compose-file-v3.html)
- [「Unix プロセスと Docker の罠」（PID 1 問題の解説）](https://kechako.dev/posts/2015/05/27/210459/)
- [Nginx — WordPress Codex 日本語版](https://wpdocs.osdn.jp/Nginx)
- [WP-CLI 公式サイト（日本語）](https://wp-cli.org/ja/)
- [MariaDB Knowledge Base（日本語）](https://mariadb.com/kb/ja/mariadb/)
- [vsftpd.conf マニュアルページ（日本語, Ubuntu）](https://manpages.ubuntu.com/manpages/jammy/ja/man5/vsftpd.conf.5.html)
- [Adminer 公式サイト（日本語）](https://www.adminer.org/ja/)
- [Redis Object Cache – WordPress プラグインページ（日本語）](https://ja.wordpress.org/plugins/redis-cache/)

### AI usage

Claude (Anthropic, running as the Claude Code CLI) was used throughout this project as
a hands-on pair-programming assistant: setting up the VirtualBox VM (unattended Debian
install, Docker/Docker Compose installation), drafting the whole `srcs/` tree
(Dockerfiles, NGINX/PHP-FPM/MariaDB configuration, entrypoint scripts, the
`docker-compose.yml` and `Makefile`), writing this documentation, and building a
defense-oriented command cheat-sheet (kept in `memo.md`) to verify each subject
requirement (single 443 entry point, enforced TLS versions, crash auto-restart, volume
persistence, secrets isolation, PID 1 correctness, etc.). Every generated file was
reviewed, tested by actually building and running the stack, and adjusted where the
result didn't match the subject's constraints, so that the reasoning behind each choice
could be explained during the defense.

---

# 日本語版

## 概要

InceptionはDockerとDocker Composeを使い、個人用の仮想マシンの中だけで完結する
小規模なWebインフラを構築するシステム管理課題です。既製のサービスイメージに頼らず、
現実的な複数サービス構成のコンテナ化・オーケストレーションをゼロから理解することが目的です。

必須部分は、それぞれ専用コンテナで動く3つの自作Dockerイメージで構成されています。

- **NGINX** — インフラへの唯一の入口。443番ポートのみを公開し、TLSv1.2/TLSv1.3の
  接続のみを受け付ける。PHPへのリクエストはFastCGI経由でWordPressへ転送する。
- **WordPress + php-fpm** — CMS本体。`wp-cli`で非対話的にインストール・設定される。
  同じコンテナにNGINXは同居しない。
- **MariaDB** — WordPress用のデータベース。同じコンテナにNGINXは同居しない。

3つのコンテナは専用のDockerブリッジネットワークで接続され、WordPressのデータベースと
サイトファイルは、ホストの`/home/amakino/data`配下に実体を持つ2つの名前付きDocker
ボリュームで永続化されています。

必須部分に加えて、以下のボーナスサービスをそれぞれ専用コンテナ/イメージとして追加しました。

- **Redis** — WordPress用のオブジェクトキャッシュ(`redis-cache`プラグイン経由)。
- **FTPサーバー**(vsftpd) — WordPressのボリュームをファイル転送用に公開。
- **静的サイト** — PHPを使わない、Python 3(`http.server`)による小さなサイト。
- **Adminer** — MariaDBを閲覧・操作できる軽量なWeb UI。
- **バックアップサービス** — `cron`駆動で定期的にWordPressのDBを専用ボリュームへ
  ダンプし、古いバックアップを削除するコンテナ(自由選択項目)。

## 使い方

### 前提条件

- 仮想マシン(本プロジェクトは必ずこの中でビルド・実行する)にDockerと
  Docker Composeがインストールされていること。
- `secrets/*.txt`ファイルが用意されていること(生成方法は[DEV_DOC.md](./DEV_DOC.md)参照)。
  これらは意図的にGitの管理対象外にしている。
- ホスト(または採点者のマシン)の`/etc/hosts`で`amakino.42.fr`をVMのIPアドレスに
  マッピングしてあること。

### ビルドと起動

```sh
make            # 全イメージをビルドし、バックグラウンドでスタックを起動
make down       # コンテナを停止・削除
make re         # フルクリーン後に再ビルド
```

日常的な使い方は[USER_DOC.md](./USER_DOC.md)、開発者向けのセットアップ・ビルド・
データ管理の詳細は[DEV_DOC.md](./DEV_DOC.md)を参照してください。

## 設計上の選択

全サービスは`debian:bookworm-slim`(執筆時点のpenultimate stableなDebian)をベースに、
タグを明示的に固定(`latest`は使用しない)し、自前で書いたDockerfileからビルドしています。
既製のサービスイメージをレジストリからpullすることはしていません。各コンテナはPID1として
単一のフォアグラウンドプロセスを実行するため(例: `nginx -g "daemon off;"`、`php-fpm -F`、
`mariadbd`、`cron -f`)、シグナルを正しく受け取り・処理でき、Dockerによってクリーンに
停止・再起動できます。`tail -f`や`sleep infinity`、ビジーな`while true`ループでコンテナを
延命させるようなハックは使用していません。

### 仮想マシン vs Docker

VMはハイパーバイザ上でカーネルごとマシン全体を仮想化するため、強い隔離が得られる一方で
起動・実行のコストは重くなります。Dockerコンテナはホストのカーネルを共有し、Linuxの
namespace/cgroupsでプロセスを隔離するため、起動が非常に軽量・高速で、イメージレイヤーに
よる効率的な再利用・配布が可能です。本プロジェクトでは両方を組み合わせています。
VMはこの課題全体を隔離する1つの環境を提供し(subjectの要求通り)、その中でDockerを使って
各サービスを個別に隔離・オーケストレーションしています。

### Secrets vs 環境変数

環境変数(`.env`ファイルなど)はドメイン名・DB名・ユーザー名といった非機密設定には便利
ですが、`docker inspect`や`/proc/<pid>/environ`から見えてしまったり、ログに残ってしまう
など漏洩しやすいという弱点があります。Docker secretsはコンテナ内の`/run/secrets/<name>`
というファイルとしてのみマウントされ、`docker inspect`やコンテナの環境変数には一切
現れません。本プロジェクトでは非機密設定を`srcs/.env`に、すべてのパスワード
(DBのroot/アプリ用パスワード、WordPressの管理者/一般ユーザーパスワード、FTPパスワード)
はGitの管理対象外である`secrets/*.txt`から読み込むDocker secretsとして扱っています。

### Dockerネットワーク vs ホストネットワーク

`network: host`(や`--link`)はコンテナにホストのネットワーク名前空間をそのまま
使わせてしまい、サービス間の隔離が失われるためsubjectで禁止されています。本プロジェクトでは
代わりに`docker-compose.yml`で専用のブリッジネットワーク(`inception`)を定義しており、
コンテナ同士はサービス名で到達できます(例: `wordpress`はDockerの組み込みDNSを通じて
`mariadb`のIPを解決する)。ホストのネットワークスタックからは隔離されたままで、
ホストに公開されるのはNGINXの443番ポートのみです。

### Dockerボリューム vs バインドマウント

バインドマウントはホストの任意のパスをそのままコンテナにマッピングするもので、
シンプルですがホストのファイルシステム構成に強く依存しポータビリティが下がります。
名前付きボリュームはDocker自身が管理するストレージで、`driver_opts`を使えば生の
バインドマウントのように振る舞うことなく特定のホストパスに固定できます。subjectでは
WordPressのデータベースとサイトファイルについて、`/home/amakino/data`配下に物理的に
保存される名前付きボリュームの使用が求められています。`docker-compose.yml`では
`wordpress_data`と`mariadb_data`を、`driver: local`と`driver_opts: {type: none, o:
bind, device: /home/amakino/data/...}`を指定した名前付きボリュームとして定義しています。

## 参考資料

日本語の資料:

- [Docker ドキュメント日本語化プロジェクト (docs.docker.jp)](https://docs.docker.jp/) — Docker公式ドキュメントの有志翻訳
- [Docker Compose ファイル v3 リファレンス（日本語）](https://docs.docker.jp/compose/compose-file/compose-file-v3.html)
- [「Unix プロセスと Docker の罠」（PID 1 問題の解説）](https://kechako.dev/posts/2015/05/27/210459/)
- [Nginx — WordPress Codex 日本語版](https://wpdocs.osdn.jp/Nginx)
- [WP-CLI 公式サイト（日本語）](https://wp-cli.org/ja/)
- [MariaDB Knowledge Base（日本語）](https://mariadb.com/kb/ja/mariadb/)
- [vsftpd.conf マニュアルページ（日本語, Ubuntu）](https://manpages.ubuntu.com/manpages/jammy/ja/man5/vsftpd.conf.5.html)
- [Adminer 公式サイト（日本語）](https://www.adminer.org/ja/)
- [Redis Object Cache – WordPress プラグインページ（日本語）](https://ja.wordpress.org/plugins/redis-cache/)

英語の一次資料:

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- ["Docker and the PID 1 zombie reaping problem"](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WP-CLI documentation](https://wp-cli.org/)
- [MariaDB documentation](https://mariadb.com/kb/en/)
- [vsftpd documentation](https://security.appspot.com/vsftpd.html)
- [Adminer](https://www.adminer.org/)
- [Redis Object Cache plugin](https://wordpress.org/plugins/redis-cache/)

### AIの利用について

本プロジェクトを通じて、Claude(Anthropic、Claude Code CLIとして実行)を実践的な
ペアプログラミングの相棒として活用しました。具体的には、VirtualBox VMの構築
(Debianの無人インストール、Docker/Docker Composeの導入)、`srcs/`以下一式の作成
(各Dockerfile、NGINX/PHP-FPM/MariaDBの設定、entrypointスクリプト、
`docker-compose.yml`と`Makefile`)、このドキュメント一式の執筆、そしてsubjectの各要件
(443番のみの入口、TLSバージョン強制、クラッシュ時自動再起動、ボリューム永続化、
secretsの隔離、PID1の正しさ等)を確認するための、defense向けコマンド集
(`memo.md`にまとめている)の作成に使用しています。生成された各ファイルは、実際に
ビルド・起動して動作確認したうえでレビューし、subjectの制約に合わない箇所は都度
修正しました。また、readmeを英訳する際に使用しました。また、不明な概念などについての解説をさせました
