# memo.md — Inception 知識・手法メモ

## 1. Docker vs 仮想マシン(README比較セクション用の観点)
- VM: ハイパーバイザ上でゲストOSカーネルごと起動。分離度は高いがリソース消費・起動時間が大きい。
- Docker: ホストカーネルを共有し、名前空間(namespace)とcgroupsでプロセスを隔離する「軽量な仮想化」。起動が速く、イメージレイヤーで差分管理できる。
- この課題は「VMの中でDockerを動かす」= 二重構造。VM自体はまるごとの隔離環境として、Dockerはその中でのサービス分離として使う。

## 2. PID1問題とDockerfileのベストプラクティス
- コンテナ内でPID1になったプロセスはシグナル(SIGTERM等)を自分で正しく処理しないと、`docker stop`が効かずタイムアウト後にSIGKILLされる。
- `CMD`/`ENTRYPOINT`は**exec形式**(`["nginx", "-g", "daemon off;"]`)で書く。シェル形式(`CMD nginx -g daemon off;`)だとシェルがPID1になり、シグナルが子プロセスに正しく届かないことがある。
- `tail -f /dev/null`, `sleep infinity`, `while true; do ...; done`, ただの`bash`常駐は「コンテナを生かしておくためのハック」であり禁止。**サービス自体をフォアグラウンドで動かす**のが正しい(例: `nginx -g "daemon off;"`, `php-fpm -F`, `mysqld_safe` ではなく `mariadbd` を直接フォアグラウンド起動)。
- 参考キーワード: 「Docker and PID 1 zombie reaping problem」「tini init system」。

## 3. NGINXのTLS設定例
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
- 自己署名証明書生成コマンド例:
  `openssl req -x509 -nodes -newkey rsa:2048 -keyout login.42.fr.key -out login.42.fr.crt -days 365 -subj "/CN=login.42.fr"`
  これをDockerfileのビルド時、またはentrypointスクリプトで生成する(パスワードは書かない)。

## 4. php-fpmとNGINXの連携
- php-fpmは9000番ポート(TCP)またはUnixソケットでFastCGIプロトコルを喋る。NGINX側は自分ではPHPを解釈できないので `fastcgi_pass` で丸投げする。
- WordPressコンテナ内でphp-fpmを`daemon off`相当のフォアグラウンドモード(`php-fpm -F`)で起動。

## 5. WordPressの非対話インストール(wp-cli)
- `wp-cli` は公式のWordPress管理CLI。よく使うコマンド:
  - `wp core download`
  - `wp config create --dbname=... --dbuser=... --dbpass=... --dbhost=mariadb`
  - `wp core install --url=login.42.fr --title=... --admin_user=<非adminな名前> --admin_password=... --admin_email=...`
  - `wp user create <second_user> ...` で2人目のユーザーを追加
- パスワードは環境変数かDocker secrets(`/run/secrets/xxx`のファイルから読む)経由で渡し、スクリプト内でハードコードしない。

## 6. MariaDBの初期化
- 公式`mariadb`/`mysql`イメージのentrypoint挙動を参考にする(自作はするが挙動の再発明の参考として)。
- 起動時に `mysql_install_db` 相当の初期化 → 一時的にmysqldをローカルソケットのみで起動 → `CREATE DATABASE`, `CREATE USER`, `GRANT` を流す → 通常起動、という流れが定石。
- rootパスワード・WordPress用パスワードは `secrets/db_password.txt` 等から読む設計にする。

## 7. Docker Secrets vs 環境変数(README比較セクション用の観点)
- 環境変数(`.env`経由): `docker inspect` や `/proc/<pid>/environ` から比較的読めてしまう。ログに漏れるリスクもある。
- Docker Secrets: `docker-compose.yml`の`secrets:`セクションで定義し、コンテナ内には `/run/secrets/<name>` という一時ファイルとしてのみマウントされる(環境変数には出ない)。**機密情報はsecrets、非機密設定(ドメイン名等)は`.env`**という使い分けが推奨。

## 8. Docker Network vs Host Network(README比較セクション用の観点)
- `network: host`はコンテナがホストのネットワーク名前空間をそのまま使う = 隔離が失われる。この課題では禁止。
- 自作の`docker-compose.yml`の`networks:`でブリッジネットワークを定義し、コンテナ名でDNS解決させる(例: `wordpress`コンテナから`mariadb`という名前でMariaDBに到達できる)のが正しいやり方。

## 9. Docker Volumes vs Bind Mounts(README比較セクション用の観点)
- Bind mount: ホストの特定パスをそのままコンテナにマウント。パスがホスト依存になりポータビリティが落ちる。この課題では**禁止**(WordPress DB/filesの永続化には使えない)。
- Named volume: Dockerが管理する独立したストレージ領域。`docker volume create`相当で作られ、`docker-compose.yml`の`volumes:`トップレベルキーで定義。この課題では「名前付きボリュームだが実体は`/home/login/data`配下に置く」という指定があるので、ボリュームドライバのオプション(`driver: local`, `driver_opts: {type: none, o: bind, device: /home/login/data/wordpress}`)で紐付けるのが定番のテクニック。

## 10. デバッグの定石
- `docker compose logs -f <service>` でログ監視
- `docker compose exec <service> sh` でコンテナ内に入って確認
- `docker compose config` でcompose定義の展開結果を確認(環境変数の展開ミスを見つけやすい)
- `docker network inspect <network>` でコンテナ間疎通を確認
