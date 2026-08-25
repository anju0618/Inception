# マンド集
`<login>` = `amakino`、ドメイン = `amakino.42.fr`

## VMをSSH接続

```sh
# VM起動
VBoxManage list runningvms
VBoxManage startvm Inception-VM --type headless

# SSH接続
ssh -i /goinfre/amakino/Inception/vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1
# PW
cat /goinfre/amakino/Inception/vm/vm-password.txt

# ｸﾛﾐｳﾑ
ssh -X -i /goinfre/amakino/Inception/vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1 \
  "chromium --no-sandbox --user-data-dir=/tmp/chrome-profile --new-window https://amakino.42.fr/"

# VMシャットダウン
VBoxManage controlvm Inception-VM acpipowerbutton
```

## 0. 評価直前の全消し

```sh
docker stop $(docker ps -qa); docker rm $(docker ps -qa)
docker rmi -f $(docker images -qa)
docker volume rm $(docker volume ls -q)
docker network rm $(docker network ls -q) 2>/dev/null

cd /home/amakino/Inception
make
```

## 1. 禁止パターンが無いことの確認

```sh
grep -n "network: host\|links:" srcs/docker-compose.yml   # 何もヒットしないこと
grep -rn -- "--link" Makefile srcs/                         # 何もヒットしないこと
grep -rn "tail -f\|sleep infinity\|while true" srcs/requirements/  # 何もヒットしないこと
grep -rn "^FROM" srcs/requirements/*/Dockerfile srcs/requirements/bonus/*/Dockerfile  # latest不使用、タグ固定
```

## 2. 起動状態・イメージ名の確認

```sh
docker compose -f srcs/docker-compose.yml ps       # 全サービスがUp
docker images                                        # イメージ名がサービス名と一致していること
docker network ls                                    # ネットワークが見えること
docker network inspect srcs_inception                # コンテナ間のIP割当
```

## 3. NGINX / TLS / 443のみ

```sh
curl -m 3 http://amakino.42.fr/                      # 繋がらないこと
curl -vk https://amakino.42.fr/                      # 200が返ること
docker port nginx                                     # 443/tcpのみ

openssl s_client -connect amakino.42.fr:443 -tls1   </dev/null 2>&1 | tail -3   # 拒否
openssl s_client -connect amakino.42.fr:443 -tls1_2 </dev/null 2>&1 | grep Protocol  # 成功
openssl s_client -connect amakino.42.fr:443 -tls1_3 </dev/null 2>&1 | grep Protocol  # 成功
```

## 4. WordPressとそのボリューム

```sh
docker volume ls
docker volume inspect srcs_wordpress_data | grep Mountpoint   # /home/amakino/data/ を含むこと

# 一般ユーザーでコメント投稿できること → ブラウザで操作(TUTORIAL.md 4章/5-1章)
# 投稿後、MariaDBに直接入って反映されているか確認する
docker compose -f srcs/docker-compose.yml exec mariadb sh -c \
  'mysql -u wp_user -p"$(cat /run/secrets/db_password)" wordpress -e \
  "SELECT comment_ID, comment_author, comment_content FROM wp_comments ORDER BY comment_ID DESC LIMIT 5;"'

# 管理者アカウント名にadmin/administratorを含まないこと
docker compose -f srcs/docker-compose.yml exec wordpress wp user list --allow-root
```

## 5. MariaDBとそのボリューム

```sh
docker volume inspect srcs_mariadb_data | grep Mountpoint     # /home/amakino/data/ を含むこと

# rootのパスワード無しログインが拒否されること
docker compose -f srcs/docker-compose.yml exec mariadb sh -c "mysql -u root -e 'SELECT 1;'"
docker compose -f srcs/docker-compose.yml exec mariadb sh -c "mysql -h \$(hostname) -u root -e 'SELECT 1;'"

# アプリ用ユーザーでログインでき、DBが空でないこと
docker compose -f srcs/docker-compose.yml exec mariadb sh -c \
  'mysql -u wp_user -p"$(cat /run/secrets/db_password)" wordpress -e "SHOW TABLES;"'
```

## 6. Secretsが環境変数に漏れていないこと

```sh
docker inspect mariadb --format '{{json .Config.Env}}'      # パスワード文字列が含まれないこと
docker inspect wordpress --format '{{json .Config.Env}}'
```

## 7. PID1・自作Dockerfileの確認

```sh
docker inspect nginx --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
docker top nginx        # PID1がnginx本体であること(psが無い場合はこちら)
docker top wordpress    # PID1がphp-fpm masterであること
docker top mariadb      # PID1がmariadbdであること
```

## 8. クラッシュ時の自動再起動

```sh
docker compose -f srcs/docker-compose.yml ps mariadb
docker kill mariadb
sleep 5
docker compose -f srcs/docker-compose.yml ps mariadb   # Upに戻ること
```

## 9. 永続化(down/up、VM再起動)

```sh
docker compose -f srcs/docker-compose.yml exec wordpress touch /var/www/html/wp-content/uploads/persist_test.txt
docker compose -f srcs/docker-compose.yml down
docker compose -f srcs/docker-compose.yml up -d
docker compose -f srcs/docker-compose.yml exec wordpress ls /var/www/html/wp-content/uploads/   # 残っていること
```

VM自体を再起動して確認する場合(ホスト側で):

```sh
VBoxManage controlvm Inception-VM acpipowerbutton
VBoxManage startvm Inception-VM --type headless
# 起動後、VMにSSHして
cd /home/amakino/Inception && make
```

## 10. ボーナス

```sh
# Redis: WordPressのキャッシュが実際に使われているか
docker compose -f srcs/docker-compose.yml exec redis redis-cli monitor
# ↑ 動かしたまま別ターミナルでブラウザからページを再読み込みし、コマンドが流れることを確認

# FTP
FTPPASS=$(docker compose -f srcs/docker-compose.yml exec ftp cat /run/secrets/ftp_password | tr -d '\r')
curl --user "ftpuser:${FTPPASS}" ftp://amakino.42.fr/

curl -s -o /dev/null -w "static-site:%{http_code}\n" http://amakino.42.fr:8081/ # http://127.0.0.1:8081/
curl -s -o /dev/null -w "adminer:%{http_code}\n"     http://amakino.42.fr:8080/ # http://127.0.0.1:8080/
# system: MySQL, Server: mariadb, Username: wp_user, Password: secrets/db_password.txt, Database: wordpress

# コード
200: 成功.正常返答
404: ページが見つからない
500: サーバー内部でエラー
502/504: 裏側のアプリに繋がらなかった(NGINXがphp-fpmに転送失敗、等)
000: 接続不可(ポートが開いていない、コンテナが落ちている等)
# backup
docker compose -f srcs/docker-compose.yml exec backup ls -la /backups
```

## 11. 口頭説明を求められる項目(コマンド無し、自分の言葉で)

- Dockerとdocker composeの仕組み
- docker composeを使う場合と使わない場合でのDockerイメージの違い
- VMと比べたDockerの利点
- ディレクトリ構成(`srcs/`, `secrets/`)の妥当性
- docker-networkの仕組み
- MariaDBへのログイン方法
- ボーナス(backup)の仕組みと有用性
