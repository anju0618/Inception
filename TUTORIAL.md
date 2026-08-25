# はじめてのInception操作ガイド

このドキュメントは、Docker・サーバーの知識がゼロの状態から、今回作ったInceptionの
インフラを実際に自分の手を動かして触り、「何が」「なぜ」動いているのかを理解するための
取扱説明書です。`README.md`/`USER_DOC.md`/`DEV_DOC.md`は提出用(評価者向け・英語)ですが、
このファイルはあなた自身が操作を覚えるための日本語の学習用資料です。

上から順番に読んで、実際にコマンドを打ちながら進めてください。コピペで良いので、
**打つ前に「これは何をするコマンドか」を1行の説明と一緒に読む**ようにすると身につきます。

---

## 0. 全体像をつかむ(超基礎知識)

いきなりコマンドを打つ前に、最低限の言葉の意味だけ押さえておきます。

### VM(仮想マシン)とは

あなたのPC(ホスト)の中に、まるごと別の「PC」をソフトウェアで作る技術です。
今回は`VirtualBox`というソフトで`Inception-VM`という名前のDebian Linuxマシンを
1台作ってあります。42の課題ルールで「この課題はVMの中でやること」と決まっているため、
実際のDocker関連の作業は全部この**VMの中**で行います。あなたが今見ているホスト側の
ターミナルとVMの中は別のコンピュータだと思ってください。

### コンテナ・Dockerとは

「コンテナ」は、VMよりもっと軽量な隔離環境です。VMがPCまるごとのコピーだとすると、
コンテナは「1つのアプリだけを動かすための小さな箱」のイメージです。今回は

- NGINX(Webサーバー)
- WordPress + php-fpm(ブログのCMS本体)
- MariaDB(データベース)
- Redis / FTPサーバー / 静的サイト / Adminer / バックアップ(ボーナス)

という8つのコンテナが、VMの中で同時に動いています。この「複数のコンテナをまとめて
定義・起動する」ための設定ファイルが`srcs/docker-compose.yml`です。

### なぜVMの中にDockerがあるという二重構造なのか

VMは「この課題全体」を外の世界から隔離するための箱、Dockerは「VMの中のサービス同士」を
隔離するための箱、と役割が違います。README.mdの「Virtual Machine vs Docker」の節にも
同じ説明を書いてあるので、余裕があれば読んでみてください。

### イメージ・コンテナ・Dockerfileの関係

- **Dockerfile** = 「このアプリが動く環境をどう組み立てるか」のレシピ(テキストファイル)
- **イメージ(image)** = Dockerfileを実行(ビルド)して出来上がった、実行可能な「完成品」
- **コンテナ(container)** = イメージを実際に起動した、動いているインスタンス

料理に例えると、Dockerfile=レシピ、image=作り置きの冷凍食品、container=それをレンジで
温めて今まさに食卓に出ている状態、というイメージです。

---

## 1. VMに接続する

すべての作業はVMの中で行います。まずSSH(Secure Shell、離れたマシンに安全に
コマンドを送る仕組み)で接続します。

```sh
ssh -i /goinfre/amakino/Inception/vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1
```

- `-i <ファイル>` … 「鍵ファイル」を指定するオプション。パスワードの代わりに、
  この専用の鍵ファイルを持っている人だけがログインできる仕組みです。
- `-p 2222` … 接続先のポート番号。VMのSSH(本来22番)を、ホストの2222番に
  転送する設定にしてあります。
- `amakino@127.0.0.1` … 「amakinoユーザーとして、自分自身(127.0.0.1 = ホスト)の
  2222番ポートへ」接続する、という意味です(実体はVMに転送されます)。

接続できたら、プロンプトが変わって`inception-vm`というホスト名が見えるはずです。
以降、このガイドの中で断りなく出てくるコマンドは**すべてVMの中(SSH接続後)**で
実行するものです。

```sh
# 接続後、プロジェクトのディレクトリに移動
cd /home/amakino/Inception
ls
```

### VM内で`sudo`を使うときのパスワード

SSHは鍵で入れますが、VMの中で`sudo`(管理者権限でコマンドを実行する)を使うとき
(例: `make fclean`が内部で`sudo rm -rf ...`を叩く)は、**別に**`amakino`ユーザー
自身のログインパスワードを聞かれます。これはホスト側の

```
/goinfre/amakino/Inception/vm/vm-password.txt
```

というファイルに保存してあります(VM作成時に自動生成したもの)。ホストのターミナルで

```sh
cat /goinfre/amakino/Inception/vm/vm-password.txt
```

を打てば値が見られるので、`sudo`のプロンプトが出たらそれを入力してください
(SSH接続に使う鍵ファイルとは別物なので混同しないように)。

VMを終了・再起動したい場合は(ホスト側で):

```sh
VBoxManage list runningvms                          # 起動中のVM一覧
VBoxManage startvm Inception-VM --type headless      # 起動(画面なしで裏で起動)
VBoxManage controlvm Inception-VM acpipowerbutton    # 正常にシャットダウン
```

---

## 2. プロジェクトの地図

```
Inception/
├── Makefile              ← すべての操作の入口。「make」が合言葉。
├── secrets/               ← パスワード置き場(gitには入れない)
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── credentials.txt        (WordPress管理者パスワード)
│   ├── wp_users_password.txt  (WordPress一般ユーザーパスワード)
│   └── ftp_password.txt
└── srcs/
    ├── .env                ← パスワード以外の設定(ドメイン名、ユーザー名など)
    ├── docker-compose.yml  ← 8つのコンテナの設計図(超重要ファイル)
    └── requirements/
        ├── nginx/          ← NGINXコンテナのレシピ(Dockerfile)一式
        ├── wordpress/      ← WordPressコンテナのレシピ一式
        ├── mariadb/        ← MariaDBコンテナのレシピ一式
        └── bonus/          ← ボーナスサービス(redis/ftp/adminer/static-site/backup)
```

最初に眺めるべきファイルは`srcs/docker-compose.yml`です。全コンテナがどんな設定で
動いているか、ここに全部書いてあります。エディタで一度開いて眺めてみてください
(`cat srcs/docker-compose.yml`でも見られます)。

---

## 3. 起動してみる

### 3-1. `make`を実行する

```sh
make
```

これだけで、8個全部のコンテナがビルド(まだ無ければ)されて起動します。
`Makefile`の中身を見ると、実際にはこう書いてあります:

```makefile
up: prepare
	docker compose -f srcs/docker-compose.yml --env-file srcs/.env up --build -d
```

- `docker compose up` … `docker-compose.yml`に書かれた通りに全コンテナを起動する。
- `--build` … 起動前に、各コンテナのイメージを(必要なら)ビルドし直す。
- `-d` … "detached"の略。ターミナルを占有せず、バックグラウンドで動かす。

初回はビルドに数十秒〜数分かかります。「〇〇 Started」という行が全サービス分
(nginx, wordpress, mariadb, redis, ftp, adminer, static-site, backup)出れば成功です。

### 3-2. 動いているか確認する

```sh
make ps
```

`STATUS`列が全部`Up ...`になっていればOKです。もし`Restarting`が続いていたら
どこかで失敗しています(→ 8章のトラブルシューティング参照)。

個別のログを見たいときは:

```sh
docker compose -f srcs/docker-compose.yml logs -f wordpress
# Ctrl + C で見るのをやめる(コンテナは止まりません)
```

---

## 4. ブラウザで実際に見てみる

### 4-1. なぜ普通にブラウザで開けないのか

`https://amakino.42.fr/`というURLをブラウザに打っても、`amakino.42.fr`という名前が
どのIPアドレスなのか、ブラウザ(正確にはOS)は知りません。普通のサイトなら世界中の
DNSサーバーに聞きに行きますが、`amakino.42.fr`は42の課題用に自分で作った架空の
ドメイン名なので、どこのDNSサーバーにも登録されていません。

本来は「`/etc/hosts`というファイルに`amakino.42.fr`はこのIP、と手動で1行書く」ことで
解決します(subjectが要求しているのもまさにこれです)。ただし`/etc/hosts`は
システム全体の設定ファイルなので、書き換えには管理者権限(`sudo`)が必要です。

今回のようにVMがNAT接続(ホストのネットワークを間借りする方式)の場合、話がさらに
1段ややこしくなります。

- **VM側の`/etc/hosts`** … `amakino.42.fr → 127.0.0.1`をすでに追加済み。VMの中から
  見れば、これはVM自身(=NGINXが動いている本人)を指すので正しく解決できる。
- **ホスト(あなたのPC)側の`/etc/hosts`** … まだ何も書いていない。しかも今回のように
  42の端末では`sudo`が使えないため、あなたのアカウントからは書き換えられない。

これが`DNS_PROBE_FINISHED_NXDOMAIN`(=「その名前、存在しません」というブラウザのエラー)
が出た理由です。ホストのOSが`amakino.42.fr`というIPアドレスを知らないだけです。

### 4-2. 「IPで直接アクセス」だけでは足りない理由

VMの443番ポートは、ホストの8443番に転送してあります(`VBoxManage ... natpf1
"https,tcp,127.0.0.1,8443,,443"`)。そのため、名前解決を経由せず

```
https://127.0.0.1:8443/
```

と直接IPを打てばトップページ自体は表示できます(試してみると`HTTP 200`が返ります)。
ですが、WordPressは「自分のサイトのURLはhttps://amakino.42.fr」だと**データベースに
記憶している**ため、管理画面(`/wp-admin`)を開こうとすると内部で
`https://amakino.42.fr/wp-login.php`へ強制的にリダイレクトされてしまい、結局同じ
DNSエラーに戻ってきてしまいます。つまりIP直打ちは「トップページだけ見る」なら
使えますが、ログインなど実用上はほぼ使えません。

### 4-3. 解決策: VMの中でブラウザを起動し、画面だけホストに転送する

一番確実なのは、**ブラウザ自体をVMの中で動かす**ことです。VMの中では
`amakino.42.fr`は正しく`127.0.0.1`(=自分自身)に解決され、しかもポートも
標準の443番のままなので、上記の問題が両方とも起きません。これはまさに実際の
評価者が採点時にやることとも一致します(評価者のマシンの`/etc/hosts`にVMのIPを
登録して、標準の443番でアクセスする)。

とはいえ今のVMは画面(GUI)なしの「headless」モードで動いていて、デスクトップ環境も
入っていません。そこで**X11フォワーディング**という仕組みを使います。これは
「アプリケーションの処理(計算)はVMの中で行うが、画面の描画結果だけをSSH経由で
ホストの画面に転送して表示する」という、SSHの機能の1つです。VM側にフルのデスクトップ
環境(GUI一式)を入れる必要がないので、インストールが軽くて済みます。

一度だけ、VMに軽量ブラウザ(Chromium)を入れておきます(実施済みならスキップ可):

```sh
# ホスト側で(guestcontrol = VMに直接コマンドを送る仕組み、SSH不要)
VBoxManage guestcontrol Inception-VM run --username root --password "$(cat vm/vm-password.txt)" \
  --exe /usr/bin/apt-get -- -y install chromium xauth
```

あとは、`ssh`に`-X`オプション(X11フォワーディングを有効にするオプション)を付けて、
VMの中でChromiumを起動するだけです。

```sh
ssh -X -i /goinfre/amakino/Inception/vm/inception_vm_ed25519 -p 2222 amakino@127.0.0.1 \
  "chromium --no-sandbox --user-data-dir=/tmp/chrome-profile --new-window https://amakino.42.fr/"
```

- `-X` … X11フォワーディングを有効にする(=描画結果をホストの画面に転送する)。
- `--no-sandbox` … Chromiumのサンドボックス機能を無効化するオプション。通常はセキュリティ
  上オンにすべきですが、root寄りの検証専用VM環境なのでここでは問題ありません。
- `--user-data-dir=/tmp/chrome-profile` … プロフィール(履歴やCookie)の保存場所を
  一時ディレクトリに指定(root権限で動かす際の警告を避けるため)。

数秒待つと、ホストの画面に「Inception - Chromium」というタイトルの**普通のブラウザ
ウィンドウ**が開き、その中で`https://amakino.42.fr/`が正しく表示されます。中身の実体は
VMの中で動いていますが、見た目・操作感は普通のブラウザと同じです。自己署名証明書の
警告が出たら「詳細設定」→「amakino.42.fr にアクセスする(安全ではありません)」で
進めます。このウィンドウの中でなら、`/wp-admin`のリンクも問題なく開けます。

- サイト本体: `https://amakino.42.fr/`
- 管理画面: `https://amakino.42.fr/wp-admin`
  - ユーザー名: `.env`の`WORDPRESS_ADMIN_USER`(= `wp_owner`)
  - パスワード: `secrets/credentials.txt`の中身

```sh
# VMの中で(パスワードを確認)
cat /home/amakino/Inception/secrets/credentials.txt
```

このブラウザ経由でのアクセスがまさに「NGINXコンテナが443番だけを唯一の入口として
公開している」という要件そのものを体験している状態です。他のポート(WordPressの
9000番やMariaDBの3306番)はホストから一切開かれていないので、直接アクセスできません。

- Adminer(DB管理画面): `http://amakino.42.fr:8080/`
  - サーバー: `mariadb` / ユーザー名: `wp_user` / パスワード: `secrets/db_password.txt`
    / データベース: `wordpress`
- 静的サイト(PHPを使わないおまけサイト): `http://amakino.42.fr:8081/`

### 4-4. (参考)ホストの普通のブラウザで開きたい場合

`sudo`が使えるマシンでこの課題をやる場合は、ホスト側の`/etc/hosts`に

```
127.0.0.1 amakino.42.fr
```

の1行を追加すれば、ホストの普通のブラウザから`https://amakino.42.fr:8443/`
(NGINXの443番をホストの8443番に転送してある)で開けます。ただし前述の通り
`/wp-admin`のリンクは`:8443`が付かない`https://amakino.42.fr/wp-login.php`へ
リダイレクトされるため、この方法だとやはりログイン周りは崩れます。今回のような
「ホストに`sudo`が無い/NATで完結させたい」環境では、4-3のVM内ブラウザ方式が
一番トラブルが少ないです。

---

## 5. コンテナの中に入ってみる

コンテナは「小さな独立したLinux」のようなものなので、中に入ってファイルを見たり
コマンドを打ったりできます。

```sh
docker compose -f srcs/docker-compose.yml exec wordpress sh
```

これで「wordpressコンテナの中のシェル」に入ります。プロンプトが変わります。
中で試してみてください:

```sh
ls /var/www/html            # WordPress本体のファイル一覧
cat /run/secrets/credentials  # secretsがファイルとしてどう見えるか(実際の値が読める)
env | grep WORDPRESS         # 環境変数(パスワードの値そのものは無いはず)
exit                          # コンテナから抜けてVM側のシェルに戻る
```

同じように他のコンテナにも入れます:

```sh
docker compose -f srcs/docker-compose.yml exec mariadb sh
docker compose -f srcs/docker-compose.yml exec nginx sh
```

### 5-1. ブラウザで書いた内容が本当にMariaDBに届いているか確認する

評価でよく聞かれる/自分で確認しておくべき定番の実演です。「サイトは表示されているが、
中身はただの静的なファイルで、DBには何もつながっていないのでは?」という疑いを、
実際にコメントを投稿してDBの中を直接覗くことで晴らします。

**手順1: ブラウザ側でコメントを投稿する**

4章の方法(X11転送のChromium、または`https://amakino.42.fr/`)でサイトを開き、
WordPressインストール直後にデフォルトで存在する「Hello world!」という投稿を開いて、
一番下のコメント欄から適当な名前・メールアドレス・コメント本文(例:
`これはMariaDBへの到達確認テストです`)を入力して投稿します。

管理画面から新しい投稿を作る場合は、`https://amakino.42.fr/wp-admin`にログインし、
「投稿」→「新規追加」でも構いません。

**手順2: MariaDBコンテナに入って、直接SQLで確認する**

```sh
# VMの中で
cd /home/amakino/Inception

# mariadbコンテナのシェルに入る
docker compose -f srcs/docker-compose.yml exec mariadb sh

# コンテナの中で、wp_user(アプリ用ユーザー)としてMySQLクライアントに接続する
# パスワードはプロンプトで聞かれるので secrets/db_password.txt の中身を入力する
mysql -u wp_user -p wordpress
```

> **もし`ERROR 1045 (28000): Access denied for user 'wp_user'@'localhost'`が
> 出たら**: パスワードのタイプミスではなく、MariaDBがデフォルトで作る「匿名ユーザー」が
> `wp_user`より先にマッチしてしまう既知の罠です(`memo.md`の12.4に詳しい原因を書いて
> あります)。今回のプロジェクトの`mariadb`entrypointでは匿名ユーザーを削除する処理を
> 入れて対応済みなので、一度`make re`(または`make fclean && make`)でDBを作り直せば
> 再発しません。作り直したくない場合は、次のコマンドでも直せます(VMの中で実行):
> ```sh
> docker compose -f srcs/docker-compose.yml exec mariadb sh -c \
>   "mysql -uroot -p\$(cat /run/secrets/db_root_password) -e \"DELETE FROM mysql.user WHERE User='';FLUSH PRIVILEGES;\""
> ```

パスワードを事前に見ておきたい場合は、別のターミナル(またはVM側のシェル)で:

```sh
cat /home/amakino/Inception/secrets/db_password.txt
```

MySQLクライアントに入ったら(プロンプトが`MariaDB [wordpress]>`になります)、
以下のSQLを打ちます:

```sql
-- 直近のコメントを新しい順に5件表示
SELECT comment_ID, comment_author, comment_content, comment_post_ID, comment_date
FROM wp_comments
ORDER BY comment_ID DESC
LIMIT 5;

-- 直近の投稿タイトルも同様に確認できる
SELECT ID, post_title, post_status, post_date
FROM wp_posts
WHERE post_type = 'post'
ORDER BY ID DESC
LIMIT 5;
```

さっきブラウザで打ち込んだコメント本文が`comment_content`列にそのまま出てくれば、
「ブラウザ → NGINX → php-fpm → WordPress → MariaDB」という一連の経路が
実際に機能していることの動かぬ証拠になります。確認できたら、SQLの`exit;`でMySQL
クライアントを抜け、続けてシェルの`exit`でコンテナから抜けます(2段階です)。

ワンライナーで済ませたい場合(毎回パスワードを打つのが面倒なとき)は、コンテナの中で
secretsファイルを直接読ませる形でも実行できます:

```sh
docker compose -f srcs/docker-compose.yml exec mariadb sh -c \
  'mysql -u wp_user -p"$(cat /run/secrets/db_password)" wordpress -e \
  "SELECT comment_ID, comment_author, comment_content FROM wp_comments ORDER BY comment_ID DESC LIMIT 5;"'
```

### 5-2. 管理画面での変更が実際のサイトに反映されるか確認する

これも評価でそのまま試される定番の操作です。「管理画面(裏側)で行った変更が、
本当に公開側(表側)のサイトに反映されるか」を確認します。

1. `https://amakino.42.fr/wp-admin`に管理者(`wp_owner`)でログインする。
2. 左メニューの「固定ページ」→「Sample Page」(インストール直後にデフォルトで
   存在する固定ページ)を開き、本文を適当に書き換えて「更新」を押す。
3. ブラウザの別タブで`https://amakino.42.fr/sample-page/`(または「表示」ボタン)を
   開き、さっき書いた内容が実際に反映されていることを確認する。

これで「管理画面での操作 → DBへの保存 → 公開ページへの反映」という一連の流れが
本当に機能していることが確認できます。

### 5-3. MariaDBのrootが「パスワード無し」でログインできないことを確認する

これは評価者が必ずと言っていいほど試す、代表的なセキュリティチェックです。
「パスワードを設定したつもり」でも、設定漏れがあると痛い目に遭う実例が
実際にこのプロジェクトでも見つかりました(`memo.md`の12.5参照)。

```sh
# mariadbコンテナの中で、パスワード無しでrootログインを試す
docker compose -f srcs/docker-compose.yml exec mariadb sh -c "mysql -u root -e 'SELECT 1;'"

# コンテナ名(ホスト名)経由でも試す
docker compose -f srcs/docker-compose.yml exec mariadb sh -c \
  "mysql -h \$(hostname) -u root -e 'SELECT 1;'"
```

どちらも`ERROR 1045 (28000): Access denied for user 'root'@'...' (using password: NO)`
というエラーで**拒否されるのが正解**です。もし片方でも成功してしまったら、
`mysql.user`テーブルにパスワード未設定のrootアカウントが残っている証拠なので、
`memo.md`の12.5にある対策(`DELETE FROM mysql.user WHERE User = 'root' AND Host !=
'localhost';`)が正しく効いているか確認してください。

---

## 6. 止める・作り直すの違い

ここを混同すると事故るので、違いを整理します。

| コマンド | 何をする | データは消える? |
|---|---|---|
| `make stop` | コンテナを一時停止 | 消えない |
| `make start` | 止まっていたコンテナを再開 | - |
| `make down` | コンテナを停止して削除(volumeは残す) | 消えない |
| `make` (再実行) | down相当のあと、また作って起動 | 消えない(volumeは名前付きボリュームとして残るため) |
| `make clean` | down + 自分がビルドしたimageやvolume参照も削除 | volume参照は消えるが実データはホストに残る(下記参照) |
| `make fclean` | cleanに加えて`/home/amakino/data`配下の実データも削除 | **完全に消える** |
| `make re` | fclean + make | **完全に作り直す(ゼロから)** |

ポイントは、WordPressのファイルやDBの中身は`/home/amakino/data/`という
**VM側の普通のディレクトリ**に実体があるということです。`docker compose down`や
`docker volume rm`をしても、この実体データまでは消えません。本当にまっさらに
したいときは`make fclean`(内部で`rm -rf /home/amakino/data/...`している)を
使う必要があります。これは実装中に私(Claude)も一度ハマった落とし穴で、
`memo.md`の12.2に詳しく書いてあります。

試しに、データが本当に残ることを確認してみましょう:

```sh
# WordPressコンテナの中に適当なファイルを作る
docker compose -f srcs/docker-compose.yml exec wordpress touch /var/www/html/wp-content/uploads/test.txt

# 一度コンテナを全部消して作り直す
make down
make

# ファイルが残っているか確認
docker compose -f srcs/docker-compose.yml exec wordpress ls /var/www/html/wp-content/uploads/
# → test.txt が見えれば「名前付きボリュームによる永続化」が体感できたことになります
```

---

## 7. わざと壊してみる(クラッシュ復旧の体験)

subjectの要件「コンテナはクラッシュしたら自動で再起動する」を、実際に壊して確認します。

```sh
docker compose -f srcs/docker-compose.yml ps mariadb   # 起動中であることを確認
docker kill mariadb                                      # 強制的にプロセスを殺す(=クラッシュを模擬)
sleep 5
docker compose -f srcs/docker-compose.yml ps mariadb   # もう一度確認
```

`docker kill`直後は落ちますが、数秒後には`STATUS`が`Up ...`に戻っているはずです。
これは`docker-compose.yml`の各サービスに書いてある`restart: on-failure`のおかげです。
なぜ落ちても復活するのか気になったら、次のコマンドで設定を確認できます:

```sh
docker inspect mariadb --format '{{.HostConfig.RestartPolicy.Name}}'
# → on-failure と表示される
```

---

## 8. TLS(暗号化通信)の制限を体験する

「NGINXはTLSv1.2かTLSv1.3でしか喋らない」という要件も、実際に試すと分かりやすいです。

```sh
# 古い(禁止された)プロトコルで接続を試みる → 失敗するはず
openssl s_client -connect amakino.42.fr:443 -tls1 </dev/null
# エラーで接続が切れる(protocol version alert)のが正しい挙動

# 許可されているプロトコルで接続 → 成功するはず
openssl s_client -connect amakino.42.fr:443 -tls1_2 </dev/null | grep Protocol
openssl s_client -connect amakino.42.fr:443 -tls1_3 </dev/null | grep Protocol
```

これは`srcs/requirements/nginx/conf/nginx.conf`の

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

という1行が効いています。この行を消してビルドし直すと、古いプロトコルでも
繋がってしまう(=要件違反)ことも体験できます(余裕があれば試して、また戻してください)。

---

## 9. secrets(パスワード管理)の仕組みを体験する

「パスワードは環境変数ではなくDocker secretsで渡す」という要件を、実際に目で確認します。

```sh
# 環境変数を見ても、パスワードの値そのものは出てこない(ファイルパスだけ)
docker inspect mariadb --format '{{json .Config.Env}}'
# → "MYSQL_PASSWORD_FILE=/run/secrets/db_password" のような「場所」しか書いていない

# コンテナの中に入って、実際のファイルを見るとそこにだけ値がある
docker compose -f srcs/docker-compose.yml exec mariadb cat /run/secrets/db_password
```

もし「パスワードを環境変数にそのまま書いたらどうなるか」を体験したければ、
`srcs/docker-compose.yml`のどこかの`environment:`に`TEST_PASS: hogehoge`のような行を
足して`docker inspect <container> --format '{{json .Config.Env}}'`を見てみてください。
今度は値そのものが見えてしまうはずです。これがsecretsを使う理由です
(README.mdの「Secrets vs Environment Variables」にも解説があります)。

---

## 10. よく使うコマンドまとめ(チートシート)

```sh
# --- 状態確認 ---
make ps                                                    # 一覧・起動状態
docker compose -f srcs/docker-compose.yml logs -f <service>  # 特定サービスのログ
docker compose -f srcs/docker-compose.yml config            # .env展開後の最終設定を見る

# --- コンテナに入る ---
docker compose -f srcs/docker-compose.yml exec <service> sh

# --- 起動・停止 ---
make            # ビルド + 起動
make down       # 停止 + 削除(データは残る)
make stop       # 一時停止
make start      # 再開
make re         # 完全リセットして作り直す(データも消える、注意)

# --- 個別サービスだけ再ビルド ---
docker compose -f srcs/docker-compose.yml up -d --build wordpress

# --- ネットワーク確認 ---
docker network ls
docker network inspect srcs_inception

# --- ボリューム確認 ---
docker volume ls
docker volume inspect srcs_wordpress_data
```

より defense(評価)向けの実演コマンド集は`memo.md`の11章・12章にさらに詳しくまとめて
あります。慣れてきたらそちらも読んでみてください。

---

## 11. よくあるつまずきポイント

- **`make`がPermission deniedで失敗する**
  → `/home/amakino/data`配下の所有者がずれている可能性があります。
  `ls -la /home/amakino/data`で確認し、必要なら`sudo chown -R amakino:amakino /home/amakino/data`。

- **ブラウザで「ERR_CONNECTION_REFUSED」**
  → VMが起動していない、またはVM内で`make`していない可能性。まず`make ps`で確認。

- **ブラウザで「DNS_PROBE_FINISHED_NXDOMAIN」(このサイトにアクセスできません)**
  → ホスト側が`amakino.42.fr`という名前を知らないのが原因です。`sudo`が使えない環境
  では`/etc/hosts`を直接書き換えられないので、4-3節のX11フォワーディング方式
  (VMの中でChromiumを起動し、画面だけホストに転送する)を使ってください。

- **証明書の警告が出る**
  → 正常です。自己署名証明書(自分で発行した証明書)を使っているので、
  ブラウザは「本当に信頼していい証明書か分からない」と警告を出します。実際の運用では
  信頼された機関の証明書を使いますが、今回は課題の要件的に自己署名でOKです。

- **`docker compose`か`docker-compose`かで迷う**
  → 今回インストールしたのは新しい方の`docker compose`(スペースあり、pluginとして
  統合された形式)です。古い`docker-compose`(ハイフン、単独コマンド)は入れていません。

- **VMが再起動すると全部消えている**
  → `/goinfre`はセッションでクリアされる領域なので、VM自体が消えている可能性があります。
  `vm/README.md`に再構築のヒントがあります(最悪、この会話のログを元に作り直せます)。

---

## 12. 次にやってみるといい練習

1. `srcs/requirements/wordpress/tools/entrypoint.sh`を開いて、WordPressが
   「MariaDBの起動を待つ→ダウンロード→インストール→2人目のユーザー作成」という
   流れを実際にコードで追ってみる。
2. `srcs/requirements/mariadb/tools/entrypoint.sh`を読んで、MariaDBが
   「初回だけ初期化して、2回目以降はスキップする」という判定
   (`[ ! -d /var/lib/mysql/mysql ]`)をどうやっているか理解する。
3. `.env`の値(例えば`WORDPRESS_TITLE`)を書き換えて、`make`をもう一度実行し、
   サイトのタイトルが変わることを確認する(設定変更→再起動の流れを体験)。
4. `memo.md`の11章のコマンドを一通り自分の手で打ってみて、「これは何を証明する
   コマンドなのか」を自分の言葉で説明できるようにする(これがdefense対策になります)。
