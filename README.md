# くま避けメーター

散歩・サイクリング・低山に行く前に、札幌市のヒグマ出没情報から「今日は行くべきか」を短時間で判断するための SwiftUI MVP です。

## MVPの範囲

- 札幌市ヒグマ出没情報CSVをJSONに変換
- 札幌市公式ヒグマ出没情報ページも補助ソースとして取り込み
- GitHub Actionsで毎朝JSONを作り直し、GitHub Pagesで配信
- iOSアプリ起動時にGitHub PagesのJSONを取得
- 取得失敗時はキャッシュ、それもなければアプリ内の同梱JSONを表示
- 目的地または現在地から、半径1km / 3km / 5km以内の件数を表示
- 直近7日 / 30日の条件で危険度を判定
- MapKitで出没地点をピン表示
- 出発前チェックリストを表示

ログイン、投稿、通知、独自DB、常時稼働サーバー、AI判定は入れていません。まず「自分が出発前に本当に使うか」を見るための小さい形です。

## 判定ロジック

| 条件 | 表示 |
| --- | --- |
| 7日以内・1km以内 | 中止推奨 |
| 7日以内・3km以内 | 高リスク |
| 30日以内・3km以内 | 注意 |
| 30日以内・5km以内 | 通常注意 |
| 情報なし | 通常警戒 |

重要な方針として、アプリ内では「安全」とは表示しません。情報がない場合も「安全保証なし」として扱います。

## 開き方

1. Xcodeで `KumaYokeMeter.xcodeproj` を開きます。
2. 実行先に iPhone シミュレータまたは実機を選びます。
3. Run します。

現在地判定を使う場合は、アプリ起動後に位置情報の許可が必要です。目的地判定だけなら位置情報なしでも確認できます。

## データ更新の仕組み

データの流れは次の順番です。

1. GitHub Actionsが毎朝5時ごろ、札幌市CKAN APIを確認します。
2. CKANのCSVリソース一覧から、最新年のCSVを選びます。
3. 札幌市公式ヒグマ出没情報ページも取得します。
4. CKAN CSVと公式ページHTMLを同じ形式に正規化します。
5. `date + place + detail` と近い緯度経度を使って重複を除去します。
6. メタデータ付きの `bear_sightings.json` を生成します。
7. `bear_sightings.json` と `bear_sightings_metadata.json` をGitHub Pagesに公開します。
8. iOSアプリは起動時にGitHub PagesのJSONを取得します。
9. 取得できたらキャッシュに保存します。
10. 取得できない場合は、前回キャッシュを使います。
11. キャッシュもない場合は、アプリ内に同梱したJSONを使います。

公式ページのHTML構造が変わってパースに失敗した場合でも、workflow全体は止めません。その場合はCKANデータだけでJSONを生成し、メタデータ上で公式ページソースを `failed` として記録します。

## GitHub Pagesの設定

最初に一度だけ、GitHub側で設定が必要です。

1. このリポジトリをGitHubへpushします。
2. GitHubのリポジトリ画面で `Settings` を開きます。
3. `Pages` を開きます。
4. `Build and deployment` の `Source` を `GitHub Actions` にします。
5. `Actions` タブで `Update bear sightings data` を選び、`Run workflow` を押します。

成功すると、次のURLでJSONが見られるようになります。

```text
https://<GitHubユーザー名>.github.io/<リポジトリ名>/bear_sightings.json
https://<GitHubユーザー名>.github.io/<リポジトリ名>/bear_sightings_metadata.json
```

このリポジトリでは、アプリが読むURLは次です。

```text
https://catgptv5.github.io/kuma-yoke-meter/bear_sightings.json
```

## iOSアプリにJSON URLを設定する

Xcodeで `KumaYokeMeter.xcodeproj` を開いたあと、プロジェクトファイル内の次のプレースホルダを、自分のGitHub Pages URLに置き換えます。

```text
https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPOSITORY/bear_sightings.json
```

置き換え先の例です。

```text
https://taro.github.io/kuma-yoke-meter/bear_sightings.json
```

このURLはInfo.plistの `KumaSightingsJSONURL` としてアプリに入ります。プレースホルダのままだと、アプリは通信せず、キャッシュまたは同梱JSONだけを表示します。

## 手元でJSONを作り直す

CKAN CSVと公式ページからアプリ同梱JSONを作り直すには、プロジェクト直下で次を実行します。通常はCKAN APIから最新CSVを自動選択し、公式ページも補助ソースとして取り込みます。

```bash
python3 Tools/convert_sapporo_bear_csv.py
```

出力先は `KumaYokeMeter/Resources/bear_sightings.json` です。

GitHub Pages配信用JSONを手元で確認したい場合は、次を実行します。

```bash
python3 Tools/convert_sapporo_bear_csv.py \
  --output public/bear_sightings.json \
  --metadata-output public/bear_sightings_metadata.json
```

特定のCSV URLを使いたい場合は、次のようにURLを指定できます。

```bash
python3 Tools/convert_sapporo_bear_csv.py --url "CSVのURL"
```

公式ページの取り込みを一時的に止め、CKANだけで作る場合は次を使います。

```bash
python3 Tools/convert_sapporo_bear_csv.py --skip-official-page
```

## 注意

このアプリは、公開データを見やすくするための個人用MVPです。ヒグマの行動範囲は広く、出没情報がない場所でも遭遇する可能性があります。山道・農道・川沿いへ行く前は、札幌市や北海道の公式情報も必ず確認してください。

## データ出典

出典とライセンスは `DATA_ATTRIBUTION.md` にまとめています。
