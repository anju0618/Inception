# Inception — 課題説明とタスク

## この課題は何か
Dockerを使ったシステム管理の課題。**仮想マシン(VM)の中で**、Docker Composeを使って
小さなインフラ(NGINX + WordPress/php-fpm + MariaDB)を構築する。個人課題。

必須構成:
- NGINXコンテナ: TLSv1.2 or TLSv1.3のみ。インフラへの**唯一の入口**(ポート443のみ)。
- WordPress + php-fpmコンテナ(NGINXなし、それ単体)
- MariaDBコンテナ(NGINXなし、それ単体)
- WordPress DB用の名前付きボリューム、WordPressファイル用の名前付きボリューム(**bind mountは不可**、どちらもホストの`/home/login/data`配下)
- 上記コンテナを繋ぐDockerネットワーク
- クラッシュ時は自動再起動
- ドメイン名 `login.42.fr` を自分のIPに向ける
- WordPress DBに管理者含む2ユーザー(管理者名に admin/administrator 等の文字列を含めてはいけない)

## タスクリスト

### 0. 環境準備
- [ ] VM(VirtualBox/UTM/自前ハイパーバイザ)を用意し、その中で作業する
- [ ] Docker / Docker Composeをインストール

### 1. ディレクトリ構成(公式の例に準拠)
```
.
├── Makefile
├── secrets/
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── docker-compose.yml
    ├── .env
    └── requirements/
        ├── nginx/{Dockerfile, .dockerignore, conf/, tools/}
        ├── wordpress/{Dockerfile, .dockerignore, conf/, tools/}
        ├── mariadb/{Dockerfile, .dockerignore, conf/, tools/}
        ├── bonus/ (bonus用)
        └── tools/
```
- [ ] 上記の骨組みを作る
- [ ] `.env` に `DOMAIN_NAME=<login>.42.fr` 等の非機密設定をまとめる
- [ ] `secrets/` にパスワード類を置き、**Docker secrets** で読ませる(推奨)。`.gitignore`で除外必須

### 2. 各Dockerfile
- [ ] ベースイメージはAlpineかDebianの**penultimate stable版**(最新の1つ前の安定版)を選び、**タグ固定**(`latest`禁止)
- [ ] 3サービス(nginx/wordpress/mariadb)それぞれ自作Dockerfileを書く(既製イメージのpull・DockerHub利用は禁止。Alpine/Debianベースイメージ自体は例外)
- [ ] docker-compose.ymlからMakefile経由でこれらDockerfileをビルドする
- [ ] コンテナは**PID1問題**を意識し、フォアグラウンドプロセスとして正しく起動する(`tail -f`, `sleep infinity`, `while true`, ただの`bash`などのハック禁止。デーモン化せずexec形式で前面起動する)

### 3. NGINX
- [ ] `ssl_protocols TLSv1.2 TLSv1.3;` のみを許可する設定
- [ ] 自己署名証明書を生成(`openssl req -x509 ...`)しDockerfile内でCOPYまたはビルド時生成
- [ ] php-fpmへのfastcgi_pass設定(WordPressコンテナの9000番へ)
- [ ] 443番のみを公開し、インフラへの唯一の入口にする

### 4. WordPress + php-fpm
- [ ] php-fpmをインストール・設定(nginxは同居させない)
- [ ] `wp-cli` 等でWordPressを非対話的にインストール・設定するスクリプトを書く
- [ ] MariaDBへの接続情報は環境変数/secrets経由
- [ ] DBに管理者ユーザー1人(名前にadmin系文字列を含めない)+一般ユーザー1人を作成

### 5. MariaDB
- [ ] 初回起動時にDB・テーブル・ユーザーを初期化するentrypointスクリプト
- [ ] root/WordPress用パスワードはsecrets経由、Dockerfileにパスワードを書かない

### 6. Compose / ネットワーク / ボリューム
- [ ] `docker-compose.yml` に3サービス + `networks:` を明示的に定義(`network: host` や `--link` は禁止)
- [ ] 名前付きボリューム2つ(wordpress DB用・files用)を定義し、`/home/<login>/data` にマウント
- [ ] 各サービスに `restart: on-failure` 等クラッシュ時再起動設定

### 7. ドメイン
- [ ] ホスト(採点者マシン想定)の `/etc/hosts` に `<login>.42.fr` を自分のIPにマッピングする手順を確認・文書化

### 8. Makefile
- [ ] `make` (または `make up`)で `docker compose up --build -d` 相当を実行
- [ ] `make down` / `make clean` / `make re` などの補助ターゲット

### 9. ドキュメント
- [ ] `README.md`(1行目イタリックの規定文言、Description/Instructions/Resources必須セクション、加えて **VM vs Docker**、**Secrets vs 環境変数**、**Docker Network vs Host Network**、**Docker Volumes vs Bind Mounts** の比較説明)
- [ ] `USER_DOC.md`(サービス一覧、起動/停止方法、サイト/管理画面へのアクセス方法、認証情報の場所、正常稼働確認方法)
- [ ] `DEV_DOC.md`(環境構築手順、Makefile/Composeでのビルド・起動方法、コンテナ/ボリューム管理コマンド、データ永続化の仕組み)
- [ ] すべて英語で記述

### 10. ボーナス(必須部分が完璧な場合のみ評価対象)
- [ ] Redis(WordPressキャッシュ用)
- [ ] FTPサーバー(WordPressボリュームを指す)
- [ ] 静的サイト(PHP以外の言語、例: 自己紹介サイト)
- [ ] Adminer
- [ ] 任意の追加サービス(defenseで選定理由を説明できるもの)

## 評価上の注意
- 評価中に軽微な仕様変更を即興で求められることがある(理解度確認のため)。数分で対応できるようにコードベースを把握しておく。
