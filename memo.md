# memo.md — Inception 技術メモ

## 1. VM vs Docker

- VM: ハイパーバイザ上でゲストOSカーネルごと起動する。分離度は高いが、リソース消費・起動時間が大きい。
- Docker: ホストカーネルを共有し、namespaceとcgroupsでプロセスを隔離する。起動が速く、イメージレイヤーで差分管理できる。
- この課題の構造: VM = 課題全体をホストから隔離する箱。Docker = VMの中でサービス同士を隔離する箱。役割が異なる。

## 2. PID1とDockerfileの書き方

- コンテナ内でPID1になったプロセスは、シグナル(SIGTERM等)を正しく処理しないと`docker stop`が効かず、タイムアウト後にSIGKILLされる。
- `CMD`/`ENTRYPOINT`はexec形式(`["nginx", "-g", "daemon off;"]`)で書く。シェル形式(`CMD nginx -g daemon off;`)だとシェルがPID1になり、シグナルが子プロセスに正しく届かない場合がある。
- `tail -f /dev/null`、`sleep infinity`、`while true; do ...; done`、ただの`bash`常駐は禁止パターン。サービス本体をフォアグラウンドで実行する(`nginx -g "daemon off;"`、`php-fpm -F`、`mariadbd`、`cron -f`など)。
- 参考キーワード: "Docker and PID 1 zombie reaping problem"、"tini init system"。

## 3. NGINXのTLS設定

```nginx
server {
    listen 443 ssl;
    server_name login.42.fr;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_certificate     /etc/nginx/ssl/login.42.fr.crt;
    ssl_certificate_key /etc/nginx/ssl/login.42.fr.key;

    root /var/www/html;
    index index.php;

    location ~ \.php$ {
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

- `ssl_protocols`に列挙したバージョン以外のTLSはハンドシェイクの時点で拒否される。
- 自己署名証明書生成コマンド:
  ```sh
  openssl req -x509 -nodes -newkey rsa:2048 -keyout login.42.fr.key -out login.42.fr.crt -days 365 -subj "/CN=login.42.fr"
  ```
  - `-x509`: CAに署名を依頼せず、自分で署名済みの証明書を直接作るオプション。
  - `-nodes`: 秘密鍵を暗号化しない(パスフレーズ無しでNGINXが起動時に読める)。
  - `-newkey rsa:2048`: 2048bitのRSA鍵を新規生成する。
  - `-days 365`: 証明書の有効期限。
- 証明書の「署名」とは、認証局(CA)が「このドメインの持ち主だと確認した」という保証を暗号技術で証明書に付与すること。自己署名証明書はCAを介さず自分で署名するため、ブラウザは信頼できるCA一覧に無いと判断し警告を出す。暗号化通信自体は機能する。

## 4. php-fpmとNGINXの連携

- php-fpmは9000番ポート(TCP)またはUnixソケットでFastCGIプロトコルを話す。NGINXはPHPを直接解釈できないため`fastcgi_pass`で転送する。
- php-fpmは`daemon off`に相当するフォアグラウンドモード(`php-fpm -F`)で起動する。

## 5. WordPressの非対話インストール(wp-cli)

- `wp-cli`はWordPress公式の管理CLI。
- 主なコマンド:
  ```sh
  wp core download
  wp config create --dbname=... --dbuser=... --dbpass=... --dbhost=mariadb
  wp core install --url=login.42.fr --title=... --admin_user=<非admin文字列> --admin_password=... --admin_email=...
  wp user create <second_user> <email> --role=author --user_pass=...
  ```
- パスワードは環境変数かDocker secrets(`/run/secrets/xxx`)経由でスクリプトに渡し、ハードコードしない。

## 6. MariaDBの初期化とアカウント管理

### 初期化の流れ

1. `mariadb-install-db --datadir=/var/lib/mysql --auth-root-authentication-method=normal` でシステムテーブルを作成する。
2. `--skip-networking`付きで一時的にmariadbdを起動する(ソケットのみ、外部から到達不可)。
3. `CREATE DATABASE` / `CREATE USER` / `GRANT` / `ALTER USER`をSQLで実行する。
4. 一時起動していたmariadbdを`mysqladmin shutdown`で止める。
5. 通常モード(`--skip-networking`無し)で`exec mariadbd`する。

### 匿名アカウント

`mariadb-install-db`は`root`以外に、ユーザー名が空文字列の**匿名アカウント**
(`''@'localhost'`、`''@'<ホスト名>'`)も作成する。MySQL/MariaDBの接続マッチングは
ユーザー名より先に「接続元Hostの具体性」で優先順位を決めるため、`localhost`(完全一致)は
`%`(ワイルドカード)より優先され、ユーザー名が空欄の匿名アカウント(空欄はどんな
ユーザー名にもマッチする)が、本来使いたいアプリ用アカウント(例: `wp_user`@`%`)より
先にマッチしてしまう。ソケット経由のローカル接続で「正しいパスワードのはずなのに
Access denied」になる場合、この匿名アカウントが原因であることが多い。
`mysql_secure_installation`が本来削除する対象であり、自前のentrypointでは
```sql
DELETE FROM mysql.user WHERE User = '';
```
で明示的に削除する。

### rootアカウントは複数存在する

`mariadb-install-db`は`root@localhost`だけでなく、`root@127.0.0.1`、`root@::1`、
`root@<ホスト名>`という複数の行を作成する。`ALTER USER 'root'@'localhost' IDENTIFIED
BY ...`は該当する1行(Host='localhost')にしか効かないため、他のHost向けrootアカウントに
別途パスワードを設定するか、不要な行を削除する必要がある。放置すると
`mysql -h <ホスト名> -u root`のようなTCP経由のパスワード無しログインが成立してしまう。
対応:
```sql
DELETE FROM mysql.user WHERE User = 'root' AND Host != 'localhost';
```

## 7. Docker Secrets vs 環境変数

- 環境変数(`.env`経由): `docker inspect`や`/proc/<pid>/environ`から比較的読める。ログに漏れるリスクもある。
- Docker Secrets: `docker-compose.yml`の`secrets:`セクションで定義し、コンテナ内には`/run/secrets/<name>`という一時ファイルとしてのみマウントされる。環境変数には出ない。
- 使い分け: 機密情報はsecrets、非機密設定(ドメイン名等)は`.env`。

## 8. Docker Network vs Host Network

- `network: host`はコンテナがホストのネットワーク名前空間をそのまま使う。隔離が失われるためこの課題では禁止。
- `docker-compose.yml`の`networks:`でブリッジネットワークを定義すると、コンテナ名でDNS解決できる(例: `wordpress`コンテナから`mariadb`という名前でMariaDBに到達できる)。

## 9. Docker Volumes vs Bind Mounts

- Bind mount: ホストの特定パスをそのままコンテナにマウントする。ホスト依存になりポータビリティが下がる。この課題では禁止。
- Named volume: Dockerが管理するストレージ領域。この課題では「名前付きボリュームだが実体は`/home/login/data`配下に置く」という指定があるため、`driver_opts`(`type: none, o: bind, device: /home/login/data/xxx`)で紐付ける。
- Mount種別の確認:
  ```sh
  docker inspect <container> --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
  ```
  named volume経由なら`Type`は`volume`、bind mountなら`bind`と表示される。
- 名前付きボリュームの自動コピー挙動: マウント先のパスにイメージ側の既存ファイルがあり、かつボリュームが空の場合、初回起動時にイメージ側の内容がボリュームへ自動的にコピーされる(Docker本体の仕様)。イメージのビルド時にそのパスへ何かを書き込んでいると、コンテナ初回起動時にその内容がそのままボリュームに引き継がれる。
- `docker volume rm`は、Dockerが管理するボリューム参照(メタデータ)を削除するだけで、`driver_opts`で固定したホストパスの実体データまでは削除しない。ホスト側データを完全に消すには、ホストディレクトリを直接`rm -rf`する必要がある。

## 10. FTP(vsftpd)とPAM

- vsftpdはPAM(Pluggable Authentication Modules)経由でローカルユーザー認証を行う。設定ファイルは`/etc/pam.d/vsftpd`。
- `auth required pam_shells.so`という行がある場合、接続ユーザーのログインシェルが`/etc/shells`に登録されていないと認証が拒否される(パスワードが合っていても)。
- FTP専用ユーザーのシェルを`/usr/sbin/nologin`(SSH等の対話ログインを禁止するための慣用シェル)にする場合、`/etc/shells`にも`/usr/sbin/nologin`を追記しておく必要がある。

## 11. コマンドリファレンス(運用・デバッグ)

```sh
docker compose logs -f <service>          # ログ監視
docker compose exec <service> sh          # コンテナ内シェルに入る
docker compose config                      # 環境変数展開後の最終設定を表示
docker network inspect <network>           # コンテナ間の接続・DNSを確認
docker volume inspect <volume>             # ボリュームの実体パス(Mountpoint)を確認
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'  # 再起動ポリシー確認
docker inspect <container> --format '{{json .Config.Env}}'                # コンテナの環境変数一覧
```

## 12. 評価(defense)実演コマンド集

### 12.1 起動・全体確認

```sh
make                                                    # docker compose up --build -d 相当
docker compose -f srcs/docker-compose.yml ps            # 起動状態一覧
docker compose -f srcs/docker-compose.yml config         # 変数展開後の最終定義
```

### 12.2 「唯一の入口が443だけ」であることの確認

```sh
docker port <nginx_container>         # 公開ポート一覧(443/tcpのみのはず)
curl -vk https://login.42.fr          # 443で応答すること
curl http://login.42.fr               # 80番は繋がらないこと
```

### 12.3 TLSバージョン制限の確認

```sh
openssl s_client -connect login.42.fr:443 -tls1   </dev/null   # 拒否されるべき
openssl s_client -connect login.42.fr:443 -tls1_1 </dev/null   # 拒否されるべき
openssl s_client -connect login.42.fr:443 -tls1_2 </dev/null | grep Protocol   # 成功するべき
openssl s_client -connect login.42.fr:443 -tls1_3 </dev/null | grep Protocol   # 成功するべき
```

### 12.4 自動再起動(クラッシュ時)の確認

```sh
docker kill <container_name>
sleep 3
docker compose ps                       # STATUSがUpに戻ること
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'
```

### 12.5 ボリュームの永続化・実体パスの確認

```sh
docker volume ls
docker volume inspect <wordpress_volume_name>   # Mountpointが /home/<login>/data/... であること

docker compose exec wordpress touch /var/www/html/wp-content/uploads/test.txt
docker compose down
docker compose up -d
docker compose exec wordpress ls /var/www/html/wp-content/uploads/   # test.txtが残っていること
```

### 12.6 Bind mountでないことの確認

```sh
docker inspect <container> --format '{{json .Mounts}}'
# "Type": "volume" であること("Type": "bind"ならNG)
```

### 12.7 Dockerネットワークの確認

```sh
docker network ls
docker network inspect <network_name>              # ブリッジネットワーク、コンテナ間のIP割当を確認
docker compose exec nginx getent hosts wordpress    # コンテナ名でDNS解決できること
grep -n "network_mode\|--link" srcs/docker-compose.yml   # 何もヒットしないのが正
```

### 12.8 Secretsが環境変数に漏れていないことの確認

```sh
docker compose exec mariadb env | grep -i pass       # 何も出ないのが正
docker compose exec mariadb cat /run/secrets/db_password   # ここにだけ値がある
docker inspect <container> --format '{{json .Config.Env}}'   # パスワード文字列が含まれないこと
```

### 12.9 PID1・フォアグラウンド起動の確認

```sh
docker compose exec nginx ps aux        # PID1がnginx本体(masterプロセス)であること
docker inspect <container> --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
```

### 12.10 Dockerfile制約の確認

```sh
grep -n "^FROM" srcs/requirements/*/Dockerfile        # タグ固定、latest不使用であること
docker images                                           # 自作ビルドイメージのみであること
```

### 12.11 WordPressユーザーの確認

```sh
docker compose exec wordpress wp user list --allow-root
# 管理者ユーザー名に "admin"/"administrator" を含まないこと、一般ユーザーが1人以上いること
```

### 12.12 MariaDB rootのパスワード無しログインが拒否されることの確認

```sh
docker compose exec mariadb sh -c "mysql -u root -e 'SELECT 1;'"                 # 拒否されるべき
docker compose exec mariadb sh -c "mysql -h \$(hostname) -u root -e 'SELECT 1;'" # 拒否されるべき
```

### 12.13 WordPressコメントとDB反映の確認

ブラウザ側でWordPressの投稿にコメントを追加したあと、MariaDBに直接入って確認する。

```sh
docker compose exec mariadb sh -c \
  'mysql -u wp_user -p"$(cat /run/secrets/db_password)" wordpress -e \
  "SELECT comment_ID, comment_author, comment_content FROM wp_comments ORDER BY comment_ID DESC LIMIT 5;"'
```

## 13. 42公式評価チェックリストの要点

出典: [inception correction (wormav.github.io/42_eval)](https://wormav.github.io/42_eval/Cursus/Inception/index.html)
(2023年11月更新版、`docker compose`表記・現行subjectのpenultimate stable表記に対応済み)。
旧版(2022年、`docker-compose`表記・`debian:buster`固定表記): 
[school21-checklists (GitHub)](https://github.com/mharriso/school21-checklists/blob/master/ng_3_inception.pdf)。

### 13.1 前提ルール

- 認証情報(credentials/APIキー等)は評価時に作成する`.env`の中だけにあること。
  `.env`の外(gitリポジトリ内)に存在した場合、その時点で評価終了・0点。
- 学生本人が評価の場に同席していること。

### 13.2 評価開始前(採点者が実行するコマンド)

```sh
docker stop $(docker ps -qa); docker rm $(docker ps -qa); \
docker rmi -f $(docker images -qa); docker volume rm $(docker volume ls -q); \
docker network rm $(docker network ls -q) 2>/dev/null
```
コンテナ・イメージ・ボリューム・ネットワークを全て削除したあと、`docker-compose.yml`に
`network: host`/`links:`が無いこと、Makefile・スクリプトに`--link`が無いこと、
Dockerfileの`ENTRYPOINT`にバックグラウンド実行やハック(`tail -f`、`sleep infinity`等)が
無いことを確認し、Makefileを実行してゼロから起動できるかを見る。

### 13.3 口頭説明を求められる項目

- Dockerとdocker composeの仕組み
- docker composeを使う場合と使わない場合でのDockerイメージの違い
- VMと比べたDockerの利点
- このディレクトリ構成の妥当性・理由

### 13.4 実演確認項目

- 80番ではNGINXに繋がらないこと、443番でTLSv1.2/1.3が使われていること
- WordPressがインストール画面ではなく本番サイトとして表示されること
- 各Dockerfileが1サービス1つ、自作、空でないこと。ベースイメージがpenultimate stableの
  Alpine/Debianであること(バージョン番号の固定は必須だが、コードネームの指定は無い)
- イメージ名がサービス名と一致していること
- `docker compose ps`で全コンテナが正常起動していること
- `docker network ls`でネットワークが見えること、docker-networkの説明ができること
- `docker volume inspect`でMountpointに`/home/<login>/data/`が含まれること
- WordPressの一般ユーザーでコメントを投稿できること
- 管理者アカウント名に`admin`/`Admin`を含まないこと
- 管理画面から固定ページを編集し、公開ページ側に反映されることを確認する
- MariaDBのログイン方法を説明できること。DBが空でないことを確認する
  (rootのパスワード無しログイン拒否は新版では明文化されていないが、旧版の必須項目であり
  かつ12.5で見つかった通り実際に穴になり得るため、対策は維持する)
- VMを再起動して`docker compose`を立ち上げ直しても、WordPress/MariaDBの設定や
  以前の変更が残っていること

### 13.5 ボーナス

必須部分が完璧な場合のみ評価対象。ボーナス1つにつき1点。「自由選択」のサービスは、
仕組みと有用性を自分の言葉で説明できる必要がある。

### 13.6 評価結果のフラグ

`Ok`・`Outstanding project`(高評価)の他に、`Empty work`・`Incomplete work`・`Cheat`・
`Crash`・`Concerning situation`、そして**`Can't support / explain code`**
(自分のコードを説明できない)という不合格フラグがある。AIを使って書いたコードでも、
中身を自分の言葉で説明できることが前提になっている。
