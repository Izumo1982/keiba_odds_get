# keiba_odds_get
# コード詳細  
2010年9月に退職し、2010年12月に再就職するまでの  
求職中に完全独学で作った  
yahoo!様のサイトより競馬のオッズデータを取得するコードです。  
  
仕事を探しながら昼夜問わずコード作成に没頭していました。  
とても楽しくコードを書いていましたが、  
今考えれば恐ろしいニート期間です・・・。  
  
Rubyでスクレイピングして、データをPostgreSQLへ保存しています。  
  
当時のyahoo!様が9時30分過ぎと正午にデータ更新していたので、  
それに合わせて下記のようにオッズ取得していました。  
  
また、出先でも分かるように、携帯へメール送信する  
プログラムも組んでいました。  
  
# 大まかな流れ  
  
時間になるまで「sleep60」で待機  
↓  
8時に前売りのオッズ取得  
↓  
12時10分に取得  
↓  
正午にオッズ取得  
↓  
18時に結果取得  
  
  
別プログラムで必勝法の導き出した買い目と結果を照合するプログラムも  
作っていました。  
  
改良したら前回のkeibaget以下の数字を一つ大きくして保存していました。  
ファイル名が示す通り、これは189個目のファイルです。  
バージョン管理という概念が当時、自分の中に全くありませんでした・・・。  
  
  
# 今の時点で気付いている問題点  
・データベースがカード型。データ重複しまくり。  
 
・メソッドは理解できていたが、  
当時クラスは理解できなかったので使っていなかった。  
  
・無駄に同じコードが何回も出てくる。  
  
・当時の入門書の鵜呑みにして、SJIS表記。  
  
・自分で説明出来ないコードを多々使っている。  

・データ取得後にsleepメソッドを使っておらず、サーバーに負担を掛けていた（と思われる）  

・ほとんどの変数が日本語のローマ字表記  

等、ひどいコードです。  
  
# 今後について  
当時ほどに競馬に興味がなくなってしまいましたので、  
もう日常的にこのコードを動かす事はありませんが、  
勉強の為、このコードを学んだ技術で改善してみようと考えています。  
  
まずは現時点でのコードをアップロードしました。  
  
※マークダウン方式について、少しですが記載方法を学びました。  

