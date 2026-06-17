# `.pbxproj` 競合解消手順

このリポジトリでは `Feedman.xcodeproj/project.pbxproj` を commit 対象として扱う。
`.pbxproj` には Xcode project の target membership、build phase、group 構造、build settings が含まれるため、`.gitignore` しない。

Tuist や XcodeGen などで `.xcodeproj` を生成する運用へ移行した場合だけ、生成元の設定ファイルを正本にして `.xcodeproj` を ignore する選択肢を検討する。

## 起きやすい原因

複数の branch が同時に新規 Swift ファイルを追加すると、`.pbxproj` の同じセクションで競合しやすい。
特に、次のオブジェクトを同じ数値 ID で追加している場合は、単純に両方を貼り合わせるだけでは project graph が壊れる。

- `PBXBuildFile`: build phase へ入るファイル参照
- `PBXFileReference`: Xcode project 上のファイル参照
- `PBXGroup`: Xcode navigator の group 構造
- `PBXSourcesBuildPhase`: app target / test target の compile sources

## 解消方針

1. 作業前に状態を確認する。

```bash
git status --short --branch
git fetch origin develop
```

2. 対象 branch に `origin/develop` を取り込む。

```bash
git merge origin/develop
```

3. 競合箇所を確認する。

```bash
rg -n '<<<<<<<|=======|>>>>>>>' Feedman.xcodeproj/project.pbxproj
```

4. 片側を捨てず、両 branch の新規ファイルを残す。

新規 feature / test file が両側にある場合は、基本的に両方必要。片側採用にすると、Swift ファイルは存在するのに Xcode target に入っていない状態になりやすい。

5. ID 重複を避ける。

`PBXBuildFile` と `PBXFileReference` と `PBXGroup` の ID は project 内で一意にする。
片側の追加分が同じ ID を使っている場合は、片側の ID を未使用 ID へずらし、参照先もすべて同じ ID へ揃える。

例:

- `PBXBuildFile` の `fileRef` は対応する `PBXFileReference` を指す
- `PBXGroup.children` は対応する `PBXFileReference` または `PBXGroup` を指す
- `PBXSourcesBuildPhase.files` は対応する `PBXBuildFile` を指す

6. target membership を確認する。

- app 用 Swift file は `Feedman` target の `PBXSourcesBuildPhase` に入れる
- test 用 Swift file は `FeedmanTests` target の `PBXSourcesBuildPhase` に入れる
- feature group は `Feedman/Features/<FeatureName>` の group 配下に入れる
- test file は `FeedmanTests` group 配下に入れる

## 検証

競合解消後は、少なくとも次を確認する。

```bash
rg -n '<<<<<<<|=======|>>>>>>>' Feedman.xcodeproj/project.pbxproj
plutil -lint Feedman.xcodeproj/project.pbxproj
git diff --check
```

オブジェクト宣言 ID の重複も確認する。

```bash
ruby -e 'ids=Hash.new(0); File.readlines("Feedman.xcodeproj/project.pbxproj").each { |line| ids[$1] += 1 if line =~ /^\s*([A-Z0-9]{24}) \/\*.*\*\/ = / }; dup=ids.select { |_, v| v > 1 }; abort(dup.map { |k, v| "#{k} #{v}" }.join("\n")) unless dup.empty?; puts "no duplicate object declarations"'
```

macOS / Xcode 環境では、最後に project の標準テストを実行する。

```bash
xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`xcode-select -p` が `/Library/Developer/CommandLineTools` を指している場合は、一時的に `DEVELOPER_DIR` を指定して実行する。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Feedman.xcodeproj -scheme Feedman -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## よくある失敗

- conflict marker を消しただけで、片側の build phase 参照を落としている
- `PBXBuildFile` の ID だけ変えて、`PBXSourcesBuildPhase.files` 側の参照を変えていない
- `PBXFileReference` の ID だけ変えて、`PBXBuildFile.fileRef` や `PBXGroup.children` 側の参照を変えていない
- app file を test target に入れている、または test file を app target に入れている
- `plutil -lint` は通るが、target membership が欠けていて `xcodebuild test` で失敗する

## 関連 Issue

- https://github.com/hitoshiichikawa/feedman-ios/issues/92
