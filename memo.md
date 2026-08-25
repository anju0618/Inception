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

## 11. 評価(defense)でよく求められる操作・コマンド集

評価者はその場で「これを見せて」「これを試して」と要求してくることが多い。以下を手元でさっと打てるようにしておく。

### 11.1 VMの起動・接続
```sh
VBoxManage list runningvms                          # 起動中VM確認
VBoxManage startvm Inception-VM --type headless      # 起動
ssh -i vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1   # 接続
VBoxManage controlvm Inception-VM acpipowerbutton     # 正常停止
```

### 11.2 起動・全体確認(Makefile)
```sh
make            # docker compose up --build -d 相当
make down        # 停止
make clean       # コンテナ・イメージ等を削除
make re          # clean → up
docker compose -f srcs/docker-compose.yml ps          # 起動状態一覧
docker compose -f srcs/docker-compose.yml config       # 変数展開後の最終定義を確認(評価者に見せやすい)
```

### 11.3 「唯一の入口が443だけ」であることの証明
```sh
docker compose ps                     # nginxのPORTS欄が 443/tcp のみであることを見せる
docker port <nginx_container>         # 公開ポート一覧
curl -vk https://login.42.fr          # 443で応答することを確認(/etc/hostsにマッピング済み前提)
curl http://login.42.fr               # 80番は繋がらないことを見せる(接続拒否 or timeout)
```

### 11.4 TLSがv1.2/1.3限定であることの証明
```sh
# 弱いプロトコルが拒否されることを見せる(いずれもハンドシケ失敗になるはず)
openssl s_client -connect login.42.fr:443 -tls1   2>&1 | tail -5
openssl s_client -connect login.42.fr:443 -tls1_1 2>&1 | tail -5
# 許可されたプロトコルは繋がることを見せる
openssl s_client -connect login.42.fr:443 -tls1_2 2>&1 | grep "Protocol"
openssl s_client -connect login.42.fr:443 -tls1_3 2>&1 | grep "Protocol"
```

### 11.5 自動再起動(クラッシュ時)の証明
```sh
docker compose ps                       # 事前にコンテナIDを確認
docker kill <mariadb_container_name>    # プロセスを強制終了させてクラッシュを模擬
sleep 3
docker compose ps                       # STATUSがUp(再起動済み)に戻っていることを見せる
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'  # restart: on-failure等の設定確認
```

### 11.6 ボリュームが「名前付き」かつ「ホストの/home/login/data配下」であることの証明
```sh
docker volume ls                                        # 名前付きボリューム一覧
docker volume inspect <wordpress_volume_name>            # Mountpointが /home/<login>/data/... を指すことを見せる
ls -la /home/<login>/data/wordpress /home/<login>/data/mariadb   # ホスト側の実体を見せる
```
永続化の証明(評価者がよくやる操作):
```sh
docker compose exec wordpress touch /var/www/html/wp-content/uploads/test_persist.txt
docker compose down
docker compose up -d
docker compose exec wordpress ls /var/www/html/wp-content/uploads/   # test_persist.txtが残っていることを見せる
```

### 11.7 Bind mountではなく名前付きボリュームであることの証明
```sh
docker inspect <wordpress_container> --format '{{json .Mounts}}' | python3 -m json.tool
# "Type": "volume" になっていること(Bind mountなら "Type": "bind")を見せる
```

### 11.8 Docker networkの確認(host networkでない・--linkを使っていないこと)
```sh
docker network ls
docker network inspect srcs_inception              # ブリッジネットワーク、コンテナ間にIP/DNSが振られていることを見せる
docker compose exec nginx getent hosts wordpress    # コンテナ名でDNS解決できることを見せる
grep -n "network_mode\|--link" srcs/docker-compose.yml   # 使っていないことをソースで見せる(何もヒットしないのが正)
```

### 11.9 Secretsが環境変数に漏れていないことの証明
```sh
docker compose exec mariadb env | grep -i pass       # 何も出ない(secretsはファイル経由)のが正
docker compose exec mariadb cat /run/secrets/db_password   # ここにだけ値がある
docker inspect <mariadb_container> --format '{{json .Config.Env}}'   # パスワード文字列が含まれないことを見せる
```

### 11.10 PID1・フォアグラウンド起動の証明
```sh
docker compose exec nginx ps aux        # PID1がnginx本体(masterプロセス)自身であることを見せる。shやtail -fがPID1になっていないこと
docker inspect <container> --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'   # exec形式で書かれていることを確認
```

### 11.11 各Dockerfileがベースイメージ以外pull禁止・タグ固定であることの証明
```sh
grep -n "^FROM" srcs/requirements/*/Dockerfile        # 全て alpine:x.y や debian:bookworm-slim 等タグ固定、latestが無いことを見せる
docker images                                           # 使用イメージが自作ビルドのみであることを見せる(pull済みの既製サービスイメージが無いこと)
```

### 11.12 WordPress側の確認(管理者名にadmin文字列を含まない・2ユーザー)
```sh
docker compose exec wordpress wp user list --allow-root
# 管理者ユーザー名に "admin"/"administrator" が含まれていないこと、一般ユーザーが1人以上いることを見せる
```

### 11.13 その場での軽微な仕様変更に備えて
- `docker compose up -d --build <service>` で1サービスだけ再ビルド・再起動できることを覚えておく
- `.env` や `secrets/*.txt` を書き換えたら `docker compose up -d` の再実行が必要(再ビルド不要な場合が多い)ことを説明できるようにしておく
- 設定変更のたびに `docker compose config` で反映結果を確認する癖をつける

## 12. 実装中に実際にハマった落とし穴(defenseで聞かれても即答できるように)

### 12.1 「名前付きボリュームなのに初期化スクリプトが走らない」問題
Debianの`mariadb-server`パッケージは`apt-get install`した時点(=Dockerイメージのビルド時)で
`postinst`が自動的に`mysql_install_db`相当を実行し、`/var/lib/mysql`に初期データを作ってしまう。
一方Dockerの名前付きボリュームには「マウント先のパスにイメージ側の既存ファイルがあり、かつ
ボリュームが空の場合、初回起動時にイメージ側の内容をボリューム側へ自動コピーする」という仕様がある。
この2つが組み合わさると、entrypointスクリプトの「初期化済みか?」判定
(`[ ! -d /var/lib/mysql/mysql ]`)が「初期化済み」と誤判定し、自前の
`CREATE DATABASE`/`CREATE USER`が一度も実行されないままmariadbdが起動してしまう。
→ 対策: Dockerfileで`apt-get install`直後に`rm -rf /var/lib/mysql/*`しておき、
イメージ内は必ず空の状態でボリュームに渡す。

### 12.2 「`docker volume rm`してもデータが消えない」問題
`driver_opts: {type: none, o: bind, device: /home/login/data/xxx}`で固定ホストパスに
紐付けた名前付きボリュームは、`docker volume rm`してもホスト側のディレクトリの中身までは
削除されない(Dockerが管理しているのは「その固定パスを使う」というメタデータだけで、
実体は普通のホストディレクトリのため)。作り直したつもりでも古いデータが残り、上記12.1のような
問題の切り分けを混乱させる。
→ データを本当にまっさらにしたい時は`docker volume rm`ではなく、
`rm -rf /home/login/data/<service>/*`のようにホスト側のディレクトリを直接消す
(`make fclean`はこれをやっている)。

### 12.3 vsftpdでローカルユーザーログインが`530 Login incorrect`になる
FTP専用ユーザーのシェルを`/usr/sbin/nologin`にしていると、vsftpdのPAM設定
(`/etc/pam.d/vsftpd`)にある`auth required pam_shells.so`が「`/etc/shells`に
登録されていないシェルは拒否」するため、パスワードが合っていてもログインに失敗する。
→ 対策: Dockerfileで`echo /usr/sbin/nologin >> /etc/shells`しておく
(SSHログインは`nologin`のままなので問題なく防げる)。

### 12.4 mariadbコンテナ内から`wp_user`でsocket接続すると`Access denied`になる
正しいパスワード(`secrets/db_password.txt`の中身そのもの)を渡しても、コンテナ内で
`mysql -u wp_user -p wordpress`(`-h`無し=ローカルUnixソケット経由)すると
`ERROR 1045 (28000): Access denied for user 'wp_user'@'localhost' (using password: YES)`
になる。原因はタイプミスではなく、`mariadb-install-db`がデフォルトで作る**匿名ユーザー**
(`''@'localhost'`, `''@'<コンテナのホスト名>'`)。MySQL/MariaDBの接続マッチングは
「ユーザー名」より先に「接続元Hostがどれだけ具体的か」で優先順位を決めるため、
`localhost`(完全一致)は`%`(ワイルドカード)より優先され、ユーザー名が空欄の匿名アカウント
(空欄はどんなユーザー名にもマッチする)が`wp_user`@`%`より先にマッチしてしまい、
匿名アカウント側のパスワードと照合されて弾かれる。
→ 対策: entrypointの初期化SQLに`DELETE FROM mysql.user WHERE User = '';`を追加し、
`mysql_secure_installation`が本来やる「匿名ユーザー削除」を自前でやっておく。
(ちなみにWordPressコンテナからのTCP接続(`mariadb`というコンテナ名経由)は接続元が
コンテナのIPアドレスになり匿名アカウントの`localhost`/ホスト名とは一致しないため、
この問題とは無関係に最初から成功していた。あくまで「コンテナ内から`-h`無しでsocket接続
した場合」特有の罠。)

## 13. 作業ログ(実施した手順・コマンドと解説)

このセッションで実際に行ったことを、実行した順番にコマンド付きでまとめる。

### 13.1 環境確認

VMを作る前に、今いるホスト(42東京の端末)の状況を確認した。

```sh
uname -a                                  # ホストOSの確認(Ubuntu 22.04)
which VBoxManage virt-manager qemu-system-x86_64   # 使えるハイパーバイザの確認
systemd-detect-virt                       # 自分自身がVM内かどうか(→ none = ホスト直)
grep -Eo 'vmx|svm' /proc/cpuinfo | sort -u  # CPU仮想化支援(vmx)があるか
df -h /goinfre                            # VM置き場の空き容量確認
VBoxManage list vms                       # 既存VM登録の確認
```

`/goinfre`はセッションでクリアされる領域で、以前作っていた`born2beroot`VMとISOが
消えていたため、VirtualBoxへの古い登録(`<inaccessible!>`状態)を
`VBoxManage unregistervm <uuid>`で掃除してから作り直した。

### 13.2 Debian 12 (bookworm) netinst ISOの取得

VMのゲストOSに、subjectが要求する「penultimate stable」に合わせてDebian 12を選択。
最新のポイントリリースをcdimageのarchiveから確認して取得した。

```sh
curl -s https://cdimage.debian.org/cdimage/archive/ | grep -oE 'href="12\.[0-9.]+/"'
# → 12.15.0 が最新と判明

curl -L -o debian-12.15.0-amd64-netinst.iso \
  https://cdimage.debian.org/cdimage/archive/12.15.0/amd64/iso-cd/debian-12.15.0-amd64-netinst.iso
# 最初 -L を付け忘れて302リダイレクトのHTMLしか落ちてこなかった失敗あり(要 -L)

sha512sum -c <(grep "debian-12.15.0-amd64-netinst.iso$" SHA512SUMS)  # 改ざん/破損チェック
```

### 13.3 VirtualBoxでVM作成(無人インストール)

RAM6GB/CPU4/ディスク40GB可変というボーナスも見据えたサイズで、`VBoxManage`のCLIだけで
VM作成からOSインストールまで完結させた(GUIクリック不要)。

```sh
VBoxManage createvm --name Inception-VM --ostype Debian12_64 --register \
  --basefolder /goinfre/amakino

VBoxManage modifyvm Inception-VM \
  --memory 6144 --cpus 4 \
  --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2222,,22" \
  --graphicscontroller vmsvga --vram 16 --audio-driver none \
  --boot1 dvd --boot2 disk --firmware bios

VBoxManage createmedium disk \
  --filename /goinfre/amakino/Inception-VM/Inception-VM.vdi \
  --size 40960 --format VDI

VBoxManage storagectl Inception-VM --name SATA --add sata --controller IntelAHCI
VBoxManage storageattach Inception-VM --storagectl SATA --port 0 --device 0 \
  --type hdd --medium /goinfre/amakino/Inception-VM/Inception-VM.vdi

VBoxManage storagectl Inception-VM --name IDE --add ide
VBoxManage storageattach Inception-VM --storagectl IDE --port 0 --device 0 \
  --type dvddrive --medium /goinfre/amakino/iso/debian-12.15.0-amd64-netinst.iso
```

SSH接続用に、鍵とパスワードを`vm/`配下(`.gitignore`済み)に生成:

```sh
openssl rand -base64 18 > vm/vm-password.txt
ssh-keygen -t ed25519 -N "" -f vm/inception_vm_ed25519
```

`VBoxManage unattended install`でDebianの無人インストール(preseed)を実行し、
headlessで起動:

```sh
VBoxManage unattended install Inception-VM \
  --iso=/goinfre/amakino/iso/debian-12.15.0-amd64-netinst.iso \
  --user=amakino --password="$(cat vm/vm-password.txt)" \
  --hostname=inception-vm.local --locale=en_US --time-zone=Asia/Tokyo \
  --install-additions --start-vm=headless
```

インストール完了(初回起動後、Guest Additionsが立ち上がるタイミング)を
バックグラウンドでポーリングして検知した:

```sh
while true; do
  val=$(VBoxManage guestproperty get Inception-VM "/VirtualBox/GuestAdd/Version")
  [[ "$val" != *"No value set"* ]] && break
  sleep 20
done
```

### 13.4 SSHサーバー・Docker導入

VirtualBoxの`guestcontrol`はGuest Additions経由でホストからゲストへ直接コマンドを
実行できる(SSH不要)。これを使ってsshdとDockerを入れた。

```sh
# guestcontrol run の書式に注意: "--" の後は実引数そのもの(argv0を勝手に補完しない)
VBoxManage guestcontrol Inception-VM run --username root --password "$VMPASS" \
  --exe /usr/bin/apt-get -- -y install openssh-server sudo

# 公開鍵配置
VBoxManage guestcontrol Inception-VM run --username amakino --password "$VMPASS" \
  --exe /bin/sh -- -c "mkdir -p ~/.ssh && echo '<pubkey>' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

VBoxManage guestcontrol Inception-VM run --username root --password "$VMPASS" \
  --exe /usr/sbin/usermod -- -aG sudo amakino
VBoxManage guestcontrol Inception-VM run --username root --password "$VMPASS" \
  --exe /bin/systemctl -- enable --now ssh
```

以後はSSHで接続できることを確認した上で作業:

```sh
ssh -i vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1
```

Dockerは公式APTリポジトリから導入(Debian同梱の`docker.io`ではなくDocker CE本体):

```sh
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker amakino
systemctl enable --now docker
```

### 13.5 subjectの正確な要件確認

思い込みで実装しないよう、`en.subject.pdf`をテキスト抽出して該当箇所を実際に読んだ。

```sh
pdftotext -layout en.subject.pdf subject.txt
grep -n -i "README\|Mandatory\|Bonus part\|penultimate\|TLS\|/home/login" subject.txt
```

これで以下を確認: READMEの1行目の正確な規定文言、イメージ名=サービス名の縛り、
ボーナスは5項目(自由選択1つ含む)必要なこと、README/USER_DOC/DEV_DOCの必須項目。

### 13.6 プロジェクト一式の実装

`Makefile` / `secrets/*.txt`(ランダムパスワード) / `srcs/.env` / `srcs/docker-compose.yml` /
`srcs/requirements/{nginx,wordpress,mariadb,bonus/*}` を作成。詳細は各ファイル参照。
ポイントだけ挙げると:

- 全サービスのベースは`debian:bookworm-slim`固定(`latest`不使用)
- nginx: ビルド時に`openssl req -x509`で自己署名証明書を生成、`ssl_protocols TLSv1.2 TLSv1.3;`のみ
- wordpress: `wp-cli`をDL、entrypointで`mysqladmin ping`待ち→`wp core download/config create/core install`→
  2人目ユーザー作成→`redis-cache`プラグイン導入、という非対話インストール
- mariadb: entrypointで`mariadb-install-db`→一時起動→`CREATE DATABASE/USER`→シャットダウン→
  `exec mariadbd`(foreground)
- 全entrypointは最後に`exec <daemon> ...`でPID1を明け渡す(`tail -f`等のハック無し)

### 13.7 VMへの転送とビルド

ホスト(Claude Code実行環境)側でファイルを書き、VM内のDockerでビルド・実行する構成のため、
毎回tar経由でVMへ同期した(`rsync`がVMに入っていなかったため):

```sh
tar --exclude=.git --exclude=vm --exclude='*.pdf' --exclude='*.iso' -czf /tmp/src.tar.gz .
cat /tmp/src.tar.gz | ssh -i vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1 \
  "tar -xzf - -C /home/amakino/Inception"

ssh -i vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1 \
  "cd /home/amakino/Inception && make"
```

### 13.8 デバッグ(詳細は12章)

1回目の`make`では起動はしたがMariaDBの初期化(`CREATE DATABASE`/`CREATE USER`)が
実行されておらず、WordPressが`mysqladmin ping`待ちのまま止まっていた。

```sh
docker logs mariadb --tail 60      # "ready for connections" が1回しか出ていないのを確認
docker exec mariadb mysql -uroot -p"$ROOTPASS" -e "SELECT User,Host FROM mysql.user;"
# → wp_user が存在しない = 初期化ブロックが走っていないと判明(12.1の原因)
```

Dockerfileに`rm -rf /var/lib/mysql/*`を追加して再テストしたが、まだ再現した。
`docker volume rm`しただけではホスト側`/home/amakino/data/mariadb`の実データが
消えていなかったのが原因(12.2)。ホストディレクトリを直接`rm -rf`してから再testして解決:

```sh
docker compose down
rm -rf /home/amakino/data/mariadb/* /home/amakino/data/wordpress/* /home/amakino/data/backups/*
make
docker logs mariadb | grep "initialization complete"   # 出るようになった
```

FTPは`vsftpd`導入後`500 OOPS: secure_chroot_dir`エラー→ディレクトリ作成で解消、
続けて`530 Login incorrect`→PAMの`pam_shells.so`が原因と特定し`/etc/shells`に
`/usr/sbin/nologin`を追加して解消(12.3)。

### 13.9 最終検証

クリーンな状態から`make`一発で全8コンテナが立ち上がることを確認した上で、
defense想定の項目を実機で一通りチェックした(コマンドは11章参照)。代表的なもの:

```sh
curl -vk https://amakino.42.fr/                          # TLS1.3で200
openssl s_client -connect amakino.42.fr:443 -tls1        # 拒否されることを確認
docker kill mariadb; sleep 5; docker compose ps mariadb   # 自動再起動を確認
docker exec wordpress touch .../uploads/persist_test.txt
docker compose down && docker compose up -d
docker exec wordpress ls .../uploads/                     # ファイルが残っている=永続化OK
docker inspect wordpress --format '{{range .Mounts}}{{.Type}} ...{{end}}'  # "volume"であってbindでない
docker inspect mariadb --format '{{json .Config.Env}}'    # パスワード文字列が含まれない
FTPPASS=$(docker exec ftp cat /run/secrets/ftp_password)
curl --user "ftpuser:$FTPPASS" ftp://amakino.42.fr/       # FTPログイン成功
```

最後に、ホストのブラウザからも見た目確認できるよう443のポートフォワードを追加:

```sh
VBoxManage controlvm Inception-VM natpf1 "https,tcp,127.0.0.1,8443,,443"
curl -sk --resolve amakino.42.fr:8443:127.0.0.1 https://amakino.42.fr:8443/
```
