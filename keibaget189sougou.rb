# encoding: sjis
#! ruby -Ks
# -*- coding: windows-31j -*-

require "rubygems"
require "open-uri"
require "kconv"
require "nkf"
require "dbi"
require "date"
require "net/smtp"
require "tmail"

dbh = DBI.connect("DBI:Pg:gamble:localhost","gam","111456")
#データベース名:、ユーザー名:、パスワード:
dbh.execute("SET client_encoding TO SJIS")

$SENDER_MAIL = "baseball_keiba_0_2@yahoo.co.jp"
$SMTP_SERVER = "smtp.mail.yahoo.co.jp"

#先月～前日以降の結果取得
#前売りのオッズ取得
#9時半のオッズ取得
#12時半のオッズ取得
#最終的にはそれぞれ買い目を出す
#それぞれメール送る
#明日のレースの有無確認
#今日のレースが無ければメール送らない
###全レース終わった時点で結果を取って明日のレース確認

# 01 = 札幌 02 = 函館 03 = 福島 04 = 新潟 05 = 東京
# 06 = 中山 07 = 中京 08 = 京都 09 = 阪神 10 = 小倉

# kekka_d 馬券種類
# 0 = 単勝, 1 = 複勝, 2 = 枠連, 3 = 馬連
# 4 = ワイド, 5 = 馬単, 6 = ３連複, 7 = ３連単


#in  本文、題名
#out メール内容
def sendmail(body,header)
	er = 0
	begin
		m = TMail::Mail.new
		{
		 "mime-version" => "1.0",
		 "date" => Time.now,
		 "from" => $SENDER_MAIL,
		}.merge(header).each_pair do |name,value|
			m[name] = value.to_s.tosjis
		end

		m.set_content_type("text","plain","charset" => "ISO-2022-JP")
		m.body = body.tosjis
		yield m if block_given?
		Net::SMTP.start($SMTP_SERVER) do |smtp|
		 smtp.sendmail m.encoded,$SENDER_MAIL, header["to"]
		end

	rescue
$err.puts "#{__LINE__}行目：エラー：#{er}回目：#{Time.now}"
		if er <= 20
			er += 1
			retry
		end
	end

end

def mail_send(kai,keitai,massage)
	er = 0
	begin

	if keitai != ""
			sendmail NKF.nkf("-Sj","今日#{kai}回目-#{Time.now.strftime("%H%M%S")}終了\n#{keitai}"),
			 "to" => "xxxx@ezweb.ne.jp",
			 "x-mailer" => "Ruby net/smtp",
			 "subject" => NKF.nkf("-Sj","競馬確認")
	end

		sendmail NKF.nkf("-Sj","今日#{kai}回目-#{Time.now.strftime("%H%M%S")}終了\n#{keitai}\n#{massage}"),
		 "to" => "yyyy@yahoo.co.jp",
		 "x-mailer" => "Ruby net/smtp",
		 "subject" => NKF.nkf("-Sj","競馬確認")


	rescue
$err.puts "再接続#{__LINE__}行目：エラー：#{er}回目：#{Time.now}"
		if er <= 20
			er += 1
			retry
		end
	end

return "メール送信終了"
end

def get_url_sosu(komoku,url)
er = 1
	begin
		sosu = ""
		sosu = NKF.nkf("-sW",(URI("#{url}")).read)
	rescue
$err.puts "再接続#{__LINE__}行目：#{komoku}：sosuエラー：#{url}：#{er}回目：#{Time.now}"
		puts "再接続：sosuエラー：#{er}"
		er += 1
		retry
	end

end

def PostgerSQL_ctrl(komoku,command,e_command)
	er = 0
	dbh = DBI.connect("DBI:Pg:gamble:localhost","gam","111456")
	dbh.execute("SET client_encoding TO SJIS")

	begin
		out = (dbh.execute("#{command}")).fetch
	rescue
$err.puts "再接続#{__LINE__}行目：PSQLエラー#{komoku}：#{er}回目：#{Time.now}"
		puts "#{__LINE__}行目再接続#{er}"
		dbh.disconnect
		dbh = DBI.connect("DBI:Pg:gamble:localhost","gam","111456")
		dbh.execute("SET client_encoding TO SJIS")

		if e_command != ""
			dbh.execute("#{e_command}")
		end
		er += 1
		retry
	end

	return out
end

def PostgerSQL_ctrl_no_fetch(komoku,command,e_command)
	er = 0
	dbh = DBI.connect("DBI:Pg:gamble:localhost","gam","111456")
	dbh.execute("SET client_encoding TO SJIS")

	begin
		out = dbh.execute("#{command}")
	rescue
$err.puts "再接続#{__LINE__}行目：PSQLエラー#{komoku}：#{er}回目：#{Time.now}"
		puts "#{__LINE__}行目再接続#{er}"
		dbh.disconnect
		dbh = DBI.connect("DBI:Pg:gamble:localhost","gam","111456")
		dbh.execute("SET client_encoding TO SJIS")

		if e_command != ""
			dbh.execute("#{e_command}")
		end
		er += 1
		retry
	end

	return out
end



def kaisai_to_racecode(kaisai_cd)
	race_code = []

	kaisai_cd.each do |kaisai_code|
		r_c = []
		sosu2 = ""
		if kaisai_code =~ /[0-9.]/
			puts kaisai_code
			until sosu2 != ""
				sosu2 = ""
				sosu2 = get_url_sosu("会場別ソース","http://keiba.yahoo.co.jp/race/list/#{kaisai_code}/")
			end
		else
			sosu2 = ""
			#URLが存在しない時の一時しのぎ(未来のレース)
		end

		en2 = 0
		until sosu2.index(%!<a href="/race/result/!,en2) == nil
			st2 = sosu2.index(%!<a href="/race/result/!,en2) + 22
			r_c.push sosu2.slice(st2..st2 + 9)
			en2 = st2 + 13
			st2 = sosu2.rindex(%!:!,en2) - 1
		end#レース単位

		race_code.push [kaisai_code,r_c]
	end

	return race_code
end

def kaisai_code_get(check_day)
	#↓レースコード、日付、時間
	check_mon =[]
	check_mon.push Date.new((check_day - 10).year,(check_day - 10).month,1)
	check_mon.push Date.new(check_day.year,check_day.month,1)
	check_mon.push Date.new((check_day + 10).year,(check_day + 10).month,1)
	check_mon.uniq!

	check_code = []

	check_mon.each do |che|
		er = 0
		sosu = ""
		until sosu != ""
			sosu = ""
			sosu = get_url_sosu("月別ソース","http://keiba.yahoo.co.jp/schedule/list/#{che.year}/?month=#{che.month}")
		end

		en1 = 0
		until sosu.index(/回.{3,4}日/,en1) == nil
			st1 = sosu.index(/回.{3,4}日/,en1) - 12
			kaisai_code = sosu.slice(st1..st1+7)
			en1 = st1 + 13
			en1 = sosu.rindex(%!日（!,st1) - 1
			st1 = sosu.rindex(%!<td>!,en1) + 4
			kaisai_day = sosu.slice(st1..en1)
			en1 = st1 + 51

			er = 0

		check_code.push [kaisai_code,Date.new(che.year,che.month,kaisai_day.to_i)]

		end#開催単位
	puts "#{che.year}年#{che.month}月　終了"
	end#月単位

	today_code = []
	kekka_code = []
	n_day = check_day >> 1

	check_code.each do |code,c_day|
		if check_day <= c_day && c_day < n_day
			n_day = c_day
		end

		if check_day == c_day
			today_code.push code
		elsif check_day > c_day && check_day - 10 < c_day
			kekka_code.push code
		end

	end
return today_code,kekka_code,n_day

end

def kekka_get(r_code,henkou,tuika)
	er = 0
	re_text = ""

		start_a			 = PostgerSQL_ctrl("keibadataの最終番号","select max(t_no) from keibadata_kekka;","")
		daburi_check = PostgerSQL_ctrl("keibadataの重複チェック","select count(*) from keibadata_kekka where race_code = '#{r_code}';","")

	sosu3 = ""
	er = 0
	until sosu3 != "" && ( sosu3.index(%!払戻!,0) != nil || sosu3.index(%! fntSS">!,0) != nil)
			sosu3 = ""
			sosu3 = get_url_sosu("レース結果1件","http://keiba.yahoo.co.jp/race/result/#{r_code}/").gsub(/'/,"''")
	end

	temp_file = File.open("C\:\\ruby\_ex2\\keiba_last_sosu\\keiba_last_sosu-#{Date.today.to_date}.txt","w")
	temp_file.puts "http://keiba.yahoo.co.jp/race/result/#{r_code}/"
	temp_file.puts sosu3
	temp_file.close

	if start_a[0] == nil
		ban = 1
	else
		ban = start_a[0] + 1
	end

	kekka_d,r_date,jun,name,memo1,waku_ct = kekka_kakou(sosu3,r_code)

	PostgerSQL_ctrl("結果をセット","update keibadata set kekka = '#{kekka_d}',race_date = '#{r_date}' where race_code = '#{r_code}';","")

	if daburi_check[0] == 0
		PostgerSQL_ctrl("結果をセット","insert into keibadata_kekka values (#{ban},'#{r_code}','#{r_date.to_date}','#{sosu3}','#{kekka_d}','#{jun.flatten}','#{name.flatten}','#{memo1}','#{waku_ct}');","delete from keibadata_kekka where t_no = #{ban};")
		re_text = "追加"
		tuika += 1
	else
		PostgerSQL_ctrl("結果を変更","update keibadata_kekka set race_date = '#{r_date.to_date}',sosu = '#{sosu3}',kekka = '#{kekka_d}', jun = '#{jun.flatten}',name = '#{name.flatten}',memo = '#{memo1}', waku = '#{waku_ct}' where race_code = '#{r_code}';","")
		re_text = "変更"
		henkou += 1
	end

	return "#{r_code}終了",re_text,henkou,tuika
end


def odds_data_get(today_code,ct,timing)
			$load_no = 1
			$today_basyo_kaisuu = 1
			ken = 0
			mail_text = ""
			td = Date.today

			today_code.each do |today_kaisai,today_cd|
				file_name =  "keiba\_#{Time.now.strftime("%Y%m%d-%H%M%S-")}#{today_kaisai}.txt"
				file = File.open("C\\\backup\\競馬データ　2010年10月から\\#{file_name}","w")
				today_cd.each do |oc|
					out_text,ken = keibadataget(oc,td.to_date,file,file_name,ken,ct)
					mail_text = "#{mail_text}\n#{out_text}"
				end
				file.close

			end

			puts mail_send(ct,"#{timing}：オッズ取得\n#{ken}件終了","#{mail_text}")
end



def kekka_data_get(kekka_code,ct,timing)
	kekka_cd = kaisai_to_racecode(kekka_code)

	hen = 0
	tui = 0
	mail_text = ""
	kekka_cd.each do |dam,k_c|
		k_c.each do |kc|
			hyoji,out_text,hen,tui = kekka_get(kc,hen,tui)
			puts "#{hyoji} #{hen + tui}"
			mail_text = "#{mail_text}\n#{hyoji}#{out_text}"
		end
	end
	puts mail_send(ct,"#{timing}：結果終了\n変更#{hen}件-追加#{tui}件","#{mail_text}")

end

def kekka_kakou(sosu,r_code)

	kekka_d = Array.new(22){Array.new(5,"")}
	kekka_jun = Array.new(30,"")
	kekka_name = Array.new(30,"")
	kekka_waku = Array.new(10){Array.new(0,"")}

	#レース日付
	st = sosu.index(%!<p id="raceTitDay" class="fntSS">!) + 33
	en = sosu.index(%!年!,st) -1
	r_nen = sosu.slice(st..en)

	st = sosu.index(%!年!,en) + 1
	en = sosu.index(%!月!,st) -1
	r_gatu = sosu.slice(st..en)

	st = sosu.index(%!月!,en) + 1
	en = sosu.index(%!日!,st) -1
	r_niti = sosu.slice(st..en)
	r_day  = sosu.slice(st..en)

	r_date = Date.new(r_nen.to_i,r_gatu.to_i,r_day.to_i)

	en = 0
	until sosu.index(%!</td>\n<td class="txC"><span class="wk!,en) == nil
		st = sosu.index(%!</td>\n<td class="txC"><span class="wk!,en) + 37
		en = sosu.index(%!">!,st) - 1
		wk_n = sosu.slice(st..en).to_i

		en = sosu.rindex(%!</td>\n<td class="txC"><span class="wk!,en) - 1
		st = sosu.rindex(%!C">!,en) + 4
		kekka_uma = sosu.slice(st..en).gsub(%!<small>!,"").gsub(%!</small>!,"").gsub(%!<span>!,"").gsub(%!</span>!,"")

		st = sosu.index(%!<td class="txC">!,en + 8) + 16
		en = sosu.index(%!</td>!,st) - 1
		umaban = sosu.slice(st..en).to_i - 1

		en = sosu.index(%!</a>!,en) - 1
		st = sosu.rindex(%!/">!,en) + 3
		kekka_na = sosu.slice(st..en)

		kekka_waku[wk_n].push kekka_uma
		kekka_jun[umaban] = kekka_uma
		kekka_name[umaban] = kekka_na
		en += 29
	end

	#メモ(特記事項)
	enmemo = 0
	stmemo = sosu.index(%! fntSS">!,enmemo) + 8
	enmemo = sosu.index(%!</div>!,stmemo) -1

	if sosu.slice(stmemo..stmemo + 3).gsub(/,/,"")  == "通過順位"
		memo = ""
	else
		memo = sosu.slice(stmemo..enmemo).gsub(/,/,"")
	end

	if sosu.index(%!resultNo">!) == nil || memo.index(%!中止!,0) !=  nil
		flg = 1
	else
		kekka_d = Array.new(8){Array.new(0)}
		

		#単勝
		en = sosu.index("単勝")
		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en)

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[0].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end
		end

		#複勝
		en = sosu.index("複勝")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en)

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[1].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end

		end

		#枠連
		en = sosu.index("枠連")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en)

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			if sosu.slice(st..en) == " "
				kekka_one[2] = 0
			else
				kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 
			end

			kekka_d[2].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end


		end

		#馬連
		en = sosu.index("馬連")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en) 

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[3].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end

		end

		#ワイド
		en = sosu.index("ワイド")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en) 

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[4].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end

		end



		#馬単
		en = sosu.index("馬単")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en) 

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[5].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end
		end

		#3連複
		en = sosu.index("3連複")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en) 

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[6].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end

		end

		#3連単
		en = sosu.index("3連単")

		flg = ""
		until flg == 1
			kekka_one = Array.new(3,"")

			st = sosu.index(%!resultNo">!,en) + 10
			en = sosu.index(%!</td>!,st) -1
			kekka_one[0] = sosu.slice(st..en)

			st = sosu.index(%!<td>!,en) + 4
			en = sosu.index(%!円!,st) -1
			kekka_one[1] = sosu.slice(st..en).gsub(/,/,"").to_i 

			st = sosu.index(%!<span>!,en) + 6
			en = sosu.index(%!番!,st) -1
			kekka_one[2] = sosu.slice(st..en).gsub(/,/,"").to_i 

			kekka_d[7].push kekka_one

			tugi_k = sosu.index(%!rowspan!,en)
			if tugi_k == nil
				tugi_k = 999998
			end

			ima_k = sosu.index(%!resultNo">!,en)
			if ima_k == nil
				ima_k = 999999
			end

			if tugi_k < ima_k
				flg = 1
			end

		end#3連単終わり


	end#空白時のNG

	return kekka_d , r_date , kekka_jun ,kekka_name ,memo.gsub("\n",""),kekka_waku
end

def oddsdata_get(rcode,race_date,file,syu)

		if syu == 1 then
			rsyu = "odds/tfw/"
			rsyuf = "単複馬オッズ"
			en_s = "/"
		elsif syu == 2 then
			rsyu = "odds/ur/"
			rsyuf = "馬連オッズ"
			en_s = "/"
		elsif syu == 3 then
			rsyu = "odds/wide/"
			rsyuf = "ワイドオッズ"
			en_s = "/"
		elsif syu == 4 then
			rsyu = "odds/ut/"
			rsyuf = "馬単オッズ"
			en_s = "/"
		elsif syu == 5 then
			rsyu = "odds/sf/"
			rsyuf = "３連複オッズ"
			en_s = "/"
		elsif syu >= 6 then
			rsyu = "odds/st/"
			en_s = "/?rf=0&umaBan=#{(syu - 5).to_s}&position=1"
			rsyuf = "３連単オッズ#{(syu - 5).to_s}頭目"
		end

		puts "#{$today_basyo_kaisuu}レース目・#{$load_no}件目・keibafile_#{rsyuf.to_s}#{rcode.to_s}"  
		$load_no +=1
		file.puts "keibafile_#{rsyuf.to_s}#{rcode.to_s}"

		er = 0
		ded = ""
		until ded != ""

			begin
				ded = ""
				ded = get_url_sosu("オッズ取得","http://keiba.yahoo.co.jp/#{rsyu}#{rcode}#{en_s}")

			rescue
	$err.puts "再接続#{__LINE__}行目：オッズ取得エラー：#{er}回目：#{Time.now}"
					er += 1
					retry
			end
		end

		#.txt出力(1ソース分)
		file.puts ded
		return ded
end

def keibadataget(rcode,race_date,file,file_name,ken,ct)

	odds = Array.new(7,"")
	sosu = Array.new(23,"")
	odds_ti = Array.new(24,"")
	hassou_d = Array.new(24,"")
	hassou_t = Array.new(24,"")
	jo1 = Array.new(24,"")
	jo2 = Array.new(24,"")
	jo3 = Array.new(24,"")
	ten = Array.new(24,"")
	baba = Array.new(24,"")
	odds[6] = Array.new(5832,"")

	for syu in 1..23

		ded = oddsdata_get(rcode,race_date,file,syu)

		#ソースデータ加工：オッズ以外
		odds_igai = athorodds(ded)
		if odds_igai != ""
			odds_igai = odds_igai.split(',')
		else
			odds_igai = Array.new(8,"")
		end

		sosu[syu-1] = ded.gsub(/'/,"''")
		odds_ti[syu] = odds_igai[0]
		hassou_d[syu] = odds_igai[1]
		hassou_t[syu] = odds_igai[2]
		jo1[syu] = odds_igai[3]
		jo2[syu] = odds_igai[4]
		jo3[syu] = odds_igai[5]
		ten[syu] = odds_igai[6]
		baba[syu] = odds_igai[7]

		#ソースデータ加工：オッズ
		if syu == 1 then
			odds[0] = tf(ded)
			odds[1] = waku(ded)
		elsif syu == 2 then
			odds[2] = ur(ded)
		elsif syu == 3 then
			odds[3] = wide(ded)
		elsif syu == 4 then
			odds[4] = ut(ded)
		elsif syu == 5 then
			odds[5] = srf(ded)
		elsif syu >= 6 then
			odds[6] = srt(ded,odds[6],rcode,file_name)
		end

	end#←全ソース取得終了

	mukasi_day = PostgerSQL_ctrl("結果から最終開催日取得","select max(race_date) from keibadata_kekka where race_code like e'__#{rcode.slice(2..3)}______' and race_date < '#{race_date}';","")

	mukasi = Date.parse("#{mukasi_day[0]}").to_date
	#週判定
	syu_hantei = "#{ct},#{ct},#{ct},#{ct},#{ct},#{ct},#{ct},*,,,,,,,"

	#場判定
	case rcode.slice(2..3).to_s
	when "01"
		kaijo = "札幌"
		jo_hantei = 1
	when "02"
		kaijo = "函館"
		jo_hantei = 1
	when "03"
		kaijo = "福島"
		jo_hantei = 1
	when "04"
		kaijo = "新潟"
		jo_hantei = 1
	when "05"
		kaijo = "東京"
		jo_hantei = 0
	when "06"
		kaijo = "中山"
		jo_hantei = 0
	when "07"
		kaijo = "中京"
		jo_hantei = 1
	when "08"
		kaijo = "京都"
		jo_hantei = 0
	when "09"
		kaijo = "阪神"
		jo_hantei = 0
	when "10"
		kaijo = "小倉"
		jo_hantei = 1
	end


	flg = ""
	for check in odds_ti
		if check != odds_ti[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		odds_ti[0] = odds_ti[1]
	end

	flg = ""
	for check in hassou_d
		if check != hassou_d[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		hassou_d[0] = hassou_d[1]
	end

	flg = ""
	for check in hassou_t
		if check != hassou_t[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		hassou_t[0] = hassou_t[1]
	end


	for check in jo1
		if check != jo1[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		jo1[0] = jo1[1]
	end

	flg = ""
	for check in jo2
		if check != jo2[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		jo2[0] = jo2[1]
	end

	flg = ""
	for check in jo3
		if check != jo3[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		jo3[0] = jo3[1]
	end

	flg = ""
	for check in ten
		if check != ten[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		ten[0] = ten[1]
	end


	flg = ""
	for check in baba
		if check != baba[1] && check != ""
			flg = 1
		end
	end

	if flg == ""
		baba[0] = baba[1]
	end


	if (odds[6].join",").length <= 5832
		odds[6] = ""
	else
		odds[6] = odds[6].join","
	end

	bango = PostgerSQL_ctrl("競馬オッズテキストの最終番号取得","select max(odds_no) from keibaoddstext;","") 

	bango[0] += 1
	okuri = "insert into keibaoddstext values (#{bango[0]},'#{file_name}','#{rcode}'"
	for i in 0..23
		okuri = "#{okuri},'#{sosu[i]}'"
	end

	PostgerSQL_ctrl("競馬オッズテキスト入力","#{okuri});","")

	t_no_min = PostgerSQL_ctrl("競馬データの最終番号取得","select max(t_no) from keibadata;","")

	t_no_min[0] += 1
	PostgerSQL_ctrl("競馬データの入力","insert into keibadata values (#{t_no_min[0]},'#{rcode}','#{file_name}','#{kaijo}','#{syu_hantei}',#{jo_hantei},'#{odds_ti.join","}','#{hassou_d.join","}','#{hassou_t.join","}','#{jo1.join","}','#{jo2.join","}','#{jo3.join","}','#{ten.join","}','#{baba.join","}','#{odds[0]}','#{odds[1]}','#{odds[2]}','#{odds[3]}','#{odds[4]}','#{odds[5]}','#{odds[6]}');","")

	$today_basyo_kaisuu += 1
	$load_no = 1
	file.puts "データ終了"
	ken += 1
	return "#{rcode} - keibadata No.#{bango[0]}",ken
end



def athorodds(sosu)
	st = sosu.index(%!<p class="fntS" id="oddsNaviAtt">\n<strong>!) 

	if st == nil
		st = sosu.index(%!<p id="oddsNaviAtt" class="fntS">\n<strong>!) 
		if st == nil
			sosu = ""
		else

			st +=  42
			en = sosu.index("</p>",st) -1
			odds_ti = sosu.slice(st..en).gsub(/<\/strong>/,"")

			st = sosu.index(%!<p id="raceTitDay" class="fntSS">!) + 33
			en = sosu.index("（",st) -1
			hassou_d = sosu.slice(st..en)

			st = sosu.index("日 <span>|</span> ") + 17
			en = sosu.index("発走</p>",st) -1
			hassou_t = sosu.slice(st..en)

			st = sosu.index("日 <span>|</span> ") + 17
			en = sosu.index("発走</p>",st) -1
			hassou_t = sosu.slice(st..en)

			st = sosu.index(%!<h1 class="fntB">\n!) +18
			en = sosu.index("</h1>",st) -1
			jo1 = sosu.slice(st..en)

			st = sosu.index(%!<p id="raceTitMeta" class="fntSS gryB">!) + 39
			en = sosu.index(%! [<a href="/!,st) -1
			jo2 = sosu.slice(st..en)

			en = sosu.index(%!天気! ) + 1
			st = sosu.index(%! alt="! , en) + 6
			en = sosu.index(%!"! , st) -1
			ten = sosu.slice(st..en)

			st = sosu.index(%! alt="! , en) + 6
			en = sosu.index(%!"! , st) -1
			baba = sosu.slice(st..en)


			st = sosu.index(%!/> <span>|</span> ! , en ) + 18
			en = sosu.index(%! <span>|</span> 本賞金! ,st ) -1
			jo3 = sosu.slice(st..en).gsub(" <span>|</span> ", " ")
			sosu = "#{odds_ti},#{hassou_d},#{hassou_t},#{jo1},#{jo2},#{jo3},#{ten},#{baba}"
		end

	else st != nil		  
		st +=  42
		en = sosu.index("</p>",st) -1
		odds_ti = sosu.slice(st..en).gsub(/<\/strong>/,"")


		st = sosu.index(%!<p class="fntSS" id="raceTitDay">!) + 33
		en = sosu.index("（",st) -1
		hassou_d = sosu.slice(st..en)

		st = sosu.index("日 <span>|</span> ") + 17
		en = sosu.index("発走</p>",st) -1
		hassou_t = sosu.slice(st..en)

		st = sosu.index(%!<h1 class="fntB">\n!) +18
		en = sosu.index("</h1>",st) -1
		jo1 = sosu.slice(st..en)

		st = sosu.index(%!<p class="fntSS gryB" id="raceTitMeta">!) + 39
		en = sosu.index(%! [<a href="/!,st) -1
		jo2 = sosu.slice(st..en)

		en = sosu.index(%!天気! ) + 1
		st = sosu.index(%! alt="! , en) + 6
		en = sosu.index(%!"! , st) -1
		ten = sosu.slice(st..en)

		st = sosu.index(%! alt="! , en) + 6
		en = sosu.index(%!"! , st) -1
		baba = sosu.slice(st..en)


		st = sosu.index(%!/> <span>|</span> ! , en ) + 18
		en = sosu.index(%! <span>|</span> 本賞金! ,st ) -1
		jo3 = sosu.slice(st..en).gsub(" <span>|</span> ", " ")
		sosu = "#{odds_ti},#{hassou_d},#{hassou_t},#{jo1},#{jo2},#{jo3},#{ten},#{baba}"
	end
end

def tf(sosu)
	tf = Array.new(108,"")
	if sosu.index("<!--- 単勝・複勝 -->") == nil
		return tf.join","
	elsif sosu.index("<!--- 単勝・複勝 -->",sosu.index("<!--- 単勝・複勝 -->")+ 1 ) == nil
		return tf.join","
	else
		en = sosu.index("<!--- 単勝・複勝 -->") + 1
		until sosu.index(%!txR">!,en) == nil || sosu.index("<!--- 単勝・複勝 -->",en) < sosu.index(%!txR">!,en)
			st = sosu.index(%!<td class="txC"><span class="wk!,en) + 34
			en = sosu.index("</span>",st) -1
			waku = sosu.slice(st..en).to_i
			
			st = sosu.index(%!</td>\n<td class="txC">!,en) + 22
			en = sosu.index("</td>",st) -1
			uma = sosu.slice(st..en).to_i
			tf[(uma - 1) * 6 + 0] = waku
			tf[(uma - 1) * 6 + 1] = uma

			st = sosu.index(%!<td class="txL"><a href="/directory/horse/!,en) + 55
			en = sosu.index("</a>",st) -1
			tf[(uma - 1) * 6 + 2] = sosu.slice(st..en)
			
			st = sosu.index(%!txR">!,en) + 5
			en = sosu.index("</td>",st) -1

			tf[(uma - 1) * 6 + 3] =  str_check(sosu.slice(st..en))

			st = sosu.index(%!txR">!,en) + 5
			en = sosu.index("</td>",st) -1
			tf[(uma - 1) * 6 + 4] =  str_check(sosu.slice(st..en))


			st = sosu.index(%!txR">!,en) + 5
			en = sosu.index("</td>",st) -1
			tf[(uma - 1) * 6 + 5] =  str_check(sosu.slice(st..en))

		end
	return tf.join","
	end
end

def waku(sosu)
	if sosu.index("<!--- /枠連 -->") != nil
		wk = Array.new(64,"")
		en = sosu.index("<!--- 枠連 -->") + 1
		until sosu.index("<!--- /枠連 -->",en) < sosu.index(%!class!,en)
		
			jiku_s = sosu.index(%!oddsWaku!,en)
			if jiku_s == nil
				jiku_s = 999999
			end

			aite_s = sosu.index(%!txR">!,en)
			if aite_s == nil
				aite_s = 999998
			end

			if jiku_s < aite_s
				st = sosu.index(%!<div class="oddsWaku!,en) + 23
				en = sosu.index("</div>",st) - 1
				jiku = sosu.slice(st..en).to_i - 1

			else
				st = sosu.index(%!><th>!,en) + 5
				en = sosu.index("</th>",st) -1
				aite = sosu.slice(st..en).to_i - 1

				st = sosu.index(%!txR">!,en) + 5
				en = sosu.index("</td>",st) -1

				wk[jiku * 8 + aite] = str_check(sosu.slice(st..en))

			end

		end

		return wk.join","
	else
		return ""
	end
end

def ur(sosu)
	od = Array.new(306,"")
	en = sosu.index(%!<table class="oddsLs">!)

	if en != nil
		jiku_str1 = %!<tr><th class="oddsJk" colspan="2">!
		jiku_str2 = %!<tr><th colspan="2" class="oddsJk">!
		if sosu.index(jiku_str1,en) == nil
			jiku_check = jiku_str2
		else
			jiku_check = jiku_str1
		end

		until sosu.index(%!</table>!,en) == nil

			tab_sosu = sosu.slice(sosu.index(%!<table!,en)..sosu.index(%!</table>!,en))
			en = sosu.index(%!</table>!,en) + 1
			tab_st = tab_sosu.index(jiku_check) + 35
			tab_en = tab_sosu.index(%!</th>! , tab_st) - 1
			jiku   = tab_sosu.slice(tab_st..tab_en).to_i - 1

			until tab_sosu.index(%!txR">!,tab_en) == nil

				tab_st = tab_sosu.index(%!<th>!,tab_en) + 4
				tab_en = tab_sosu.index(%!</th><td!,tab_st) -1
				aite   = tab_sosu.slice(tab_st..tab_en).to_i - 1

				tab_st = tab_sosu.index(%!txR">!,tab_en) + 5
				tab_en = tab_sosu.index(%!</td></tr>!,tab_st) -1

				od[jiku * 18 + aite] = str_check(tab_sosu.slice(tab_st..tab_en))

			end
		end

		return od.join","
	else
		return ""
	end
end

def wide(sosu)
	od = Array.new(612,"")
	en = sosu.index(%!<table class="oddsWLs">!)
	if en != nil
		jiku_str1 = %!<tr><th class="oddsWJk" colspan="4">!
		jiku_str2 = %!<tr><th colspan="4" class="oddsWJk">!
		if sosu.index(jiku_str1,en) == nil
			jiku_check = jiku_str2
		else
			jiku_check = jiku_str1
		end

		until sosu.index(%!</table>!,en) == nil

			tab_sosu = sosu.slice(sosu.index(%!<table!,en)..sosu.index(%!</table>!,en))
			en = sosu.index(%!</table>!,en) + 1
			tab_st = tab_sosu.index(jiku_check) + 36
			tab_en = tab_sosu.index(%!</th>! , tab_st) - 1
			jiku   = tab_sosu.slice(tab_st..tab_en).to_i - 1

			until tab_sosu.index(%!txR">!,tab_en) == nil

				tab_st = tab_sosu.index(%!><th>!,tab_en) + 5
				tab_en = tab_sosu.index(%!</th><td!,tab_st) -1
				aite   = tab_sosu.slice(tab_st..tab_en).to_i - 1

				tab_st = tab_sosu.index(%!txR">!,tab_en) + 5
				tab_en = tab_sosu.index(%!</td><td!,tab_st) -1
				od[(jiku * 18 + aite) * 2] = str_check(tab_sosu.slice(tab_st..tab_en))

				tab_st = tab_sosu.index(%!txR">!,tab_en) + 5
				tab_en = tab_sosu.index(%!</td></tr>!,tab_st) -1
				od[(jiku * 18 + aite) * 2 + 1] = str_check(tab_sosu.slice(tab_st..tab_en))
			end
		end

		return od.join","
	else
		return ""
	end
end

def ut(sosu)
	od = Array.new(306,"")
	en = sosu.index(%!<table class="oddsLs">!)

	if en != nil
		jiku_str1 = %!<tr><th class="oddsJk" colspan="2">!
		jiku_str2 = %!<tr><th colspan="2" class="oddsJk">!
		if sosu.index(jiku_str1,en) == nil
			jiku_check = jiku_str2
		else
			jiku_check = jiku_str1
		end

		until sosu.index(%!</table>!,en) == nil

			tab_sosu = sosu.slice(sosu.index(%!<table!,en)..sosu.index(%!</table>!,en))
			en = sosu.index(%!</table>!,en) + 1
			tab_st = tab_sosu.index(jiku_check) + 35
			tab_en = tab_sosu.index(%!</th>! , tab_st) - 1
			jiku   = tab_sosu.slice(tab_st..tab_en).to_i - 1

			until tab_sosu.index(%!txR">!,tab_en) == nil

				tab_st = tab_sosu.index(%!<th>!,tab_en) + 4
				tab_en = tab_sosu.index(%!</th><td!,tab_st) -1
				aite   = tab_sosu.slice(tab_st..tab_en).to_i - 1

				tab_st = tab_sosu.index(%!txR">!,tab_en) + 5
				tab_en = tab_sosu.index(%!</td></tr>!,tab_st) -1

				od[jiku * 18 + aite] = str_check(tab_sosu.slice(tab_st..tab_en))

			end
		end

		return od.join","
	else
		return ""
	end
end

def srf(sosu)
	od = Array.new(5832,"")
	en = sosu.index(%!<table class="oddsLs">!)

	if en != nil
		jiku_str1 = %!<tr><th class="oddsJk" colspan="2">!
		jiku_str2 = %!<tr><th colspan="2" class="oddsJk">!
		if sosu.index(jiku_str1,en) == nil
			jiku_check = jiku_str2
		else
			jiku_check = jiku_str1
		end

		until sosu.index(%!</table>!,en) == nil

			tab_sosu = sosu.slice(sosu.index(%!<table!,en)..sosu.index(%!</table>!,en))
			en = sosu.index(%!</table>!,en) + 1
			tab_st = tab_sosu.index(jiku_check) + 35
			tab_en = tab_sosu.index(%!－! , tab_st) - 1
			jiku   = tab_sosu.slice(tab_st..tab_en).to_i - 1

			tab_st = tab_sosu.index(%!－!) + 1
			tab_en = tab_sosu.index(%!</th>! , tab_st) - 1
			aite   = tab_sosu.slice(tab_st..tab_en).to_i - 1

			until tab_sosu.index(%!txR">!,tab_en) == nil

				tab_st = tab_sosu.index(%!><th>!,tab_en) + 5
				tab_en = tab_sosu.index(%!</th><td!,tab_st) -1
				himo   = tab_sosu.slice(tab_st..tab_en).to_i - 1

				tab_st = tab_sosu.index(%!txR">!,tab_en) + 5
				tab_en = tab_sosu.index(%!</td></tr>!,tab_st) -1

				od[jiku * 18 * 18 + aite * 18 + himo] = str_check(tab_sosu.slice(tab_st..tab_en))

			end
		end

		return od.join","
	else
		return ""
	end
end

def srt(sosu,od,rcode,file_name)
en = sosu.index(%!<table class="odds3TLs">!)
	if en != nil
		until sosu.index(%!txR">!,en) == nil

				en = sosu.index(%!－! , en) - 1
				st = sosu.rindex(%!<th>!,en) + 4
				jiku = sosu.slice(st..en).to_i - 1

				st = sosu.index(%!－! ,en) + 1 
				en = sosu.index(%!－! ,st) - 1
				aite = sosu.slice(st..en).to_i - 1

				st = sosu.index(%!－! ,st) + 1 
				en = sosu.index(%!</th>! , st) - 1
				himo = sosu.slice(st..en).to_i - 1

				st = sosu.index(%!txR">!,en) + 5
				en = sosu.index(%!</td></tr>!,st) -1

				if od[jiku * 18 * 18 + aite * 18 + himo] != ""
					$err.puts "#{rcode},#{file_name},#{jiku + 1}-#{aite + 1 }-#{himo + 1}　すでにデータ有"
				end

				od[jiku * 18 * 18 + aite * 18 + himo]  = str_check(sosu.slice(st..en))

		end
	end

return od
end


def str_check(so)
	if so == "票数なし" || so == "****"
		return  so.to_s
	else
	 	so.split(//).each do |d| 
			if d =~ /[0-9.]/
			else
				$err.puts "#{so}は数字ではない"
				return  so.to_s
#				exit
			end
		end
		return  so.to_f
	end
end

#文字列→多重配列
def array_split(a_r)

	if a_r.index(%!]!) != nil || a_r.index(",") != nil 
		a_r = a_r.chars.to_a
		ct = 0
		st = ""
		a_r.each do |arr|
		case arr
			when "["
				ct += 1
				if ct == 1
					st = "#{st}-[-"
				else
					st = "#{st}["
				end
			when "]"
				if ct == 1
					st = "#{st}-]-"
				else
					st = "#{st}]"
				end
				ct -= 1

			when ","
				if ct == 1
					st = "#{st}-,-"
				else
					st = "#{st},"
				end
			else
				st = "#{st}#{arr}"
			end

		end

		st = st.gsub("-]-","").gsub("-[-","").split"-,- "
		out = []
		if st.class == Array
			st.each do |one|
				out.push array_split(one)
			end
		else
			out.push st
		end

	else
		out = a_r
	end

	return out
end


def tf_check(race_code,arr,get_t)

	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "単複データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	uma = PostgerSQL_ctrl("結果取得","select name from keibadata_kekka where race_code = '#{race_code}';","")

	if uma == nil
		return "レースコードに対応した結果なし　エラー"
	end

	uma = array_split(NKF.nkf("-sS",uma[0]).gsub("\"",""))

	if arr.length % 6 != 0
		return "単複#{arr.length}だからエラー"
	else
		arr.each_index do |ind|
			if ind % 6 == 1
				if arr[ind].to_i != (ind / 6).to_i + 1
					return "単複 馬番エラー#{ind / 6 + 1}頭目-#{arr[ind]}-#{ind / 6 + 1}"
				end
			end

			if ind % 6 == 2
				if arr[ind] != uma[ind / 6]
					return "単複 馬名エラー　オッズ:#{arr[ind]}-結果:#{uma[ind / 6]}"
				end
			end

			if ind % 6 > 2
				if arr[ind] == "" || arr[ind] == nil
					return "#{ind / 6 + 1}頭目　単複データなし"
				end
			end
		end
	end

	return get_t_check(get_t[1])
end


def wk_check(arr,get_t)
	err_msg = "枠連"
	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "#{err_msg}データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	for a in 0..7
		for b in 0..7
			if a > b 
				if arr[a * 8 + b] != "" && arr[a * 8 + b] != nil
					return "#{err_msg}データエラー 正しくはnil #{a}-#{b} '#{arr[a * 8 + b]}'"
				end
			elsif a < b
				if arr[a * 8 + b] == "" || arr[a * 8 + b] == nil
					return "#{err_msg}データエラー 正しくはnil以外 #{a}-#{b} '#{arr[a * 8 + b]}'"
				end
			end

		end
	end
	return get_t_check(get_t[1])
end

def ur_check(arr,tou,get_t)
	err_msg = "馬連"
	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "#{err_msg}データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	for a in 0..17
		for b in 0..17
			if a >= b || a > tou || b > tou
				if arr[a * 18 + b] != "" && arr[a * 18 + b] != nil
					return "#{err_msg}データエラー 正しくはnil #{a}-#{b} '#{arr[a * 18 + b]}'"
				end
			else#if a < b 
				if arr[a * 18 + b] == "" || arr[a * 18 + b] == nil
					return "#{err_msg}データエラー 正しくはnil以外 #{a}-#{b} '#{arr[a * 18 + b]}'"
				end
			end

		end
	end
	return get_t_check(get_t[2])
end

def wide_check(arr,tou,get_t)
	err_msg = "ワイド"
	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "#{err_msg}データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	for a in 0..17
		for b in 0..17
			for c in 0..1
				if a >= b || a > tou || b > tou
					if arr[(a * 18 + b) * 2 + c] != "" && arr[(a * 18 + b) * 2 + c] != nil
						return "#{err_msg}データエラー 正しくはnil#{a}-#{b}-#{c} '#{arr[(a * 18 + b) * 2 + c]}'"
					end
				else#if a < b 
					if arr[(a * 18 + b) * 2 + c] == "" || arr[(a * 18 + b) * 2 + c] == nil
						return "#{err_msg}データエラー 正しくはnil以外#{a}-#{b}-#{c} '#{arr[(a * 18 + b) * 2 + c]}'"
					end
				end
			end
		end
	end
	return get_t_check(get_t[3])
end

def ut_check(arr,tou,get_t)
	err_msg = "馬単"
	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "#{err_msg}データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	for a in 0..17
		for b in 0..17
			if a == b || a > tou || b > tou
				if arr[a * 18 + b] != "" && arr[a * 18 + b] != nil
					return "#{err_msg}データエラー 正しくはnil#{a}-#{b} '#{arr[a * 18 + b]}'"
				end
			else
				if arr[a * 18 + b] == "" || arr[a * 18 + b] == nil
					return "#{err_msg}データエラー 正しくはnil以外#{a}-#{b} '#{arr[a * 18 + b]}'"
				end
			end

		end
	end
	return get_t_check(get_t[4])
end

def srf_check(arr,tou,get_t)
	err_msg = "三連複"
	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "#{err_msg}データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	for a in 0..17
		for b in 0..17
			for c in 0..17
				if a >= b || b >= c || a >= c || a > tou || b > tou || c > tou
					if arr[a * 18 * 18 + b * 18 + c] != "" && arr[a * 18 * 18 + b * 18 + c] != nil
						return "#{err_msg}データエラー 正しくはnil #{a}-#{b}-#{c} '#{arr[a * 18 * 18 + b * 18 + c]}'"
					end
				else#if a < b 
					if arr[a * 18 * 18 + b * 18 + c] == "" || arr[a * 18 * 18 + b * 18 + c] == nil
						return "#{err_msg}データエラー 正しくはnil以外 #{a}-#{b}-#{c} '#{arr[a * 18 * 18 + b * 18 + c]}'"
					end
				end
			end
		end
	end
	return get_t_check(get_t[5])
end


def srt_check(arr,tou,get_t)
	err_msg = "三連単"
	if arr == "" || arr == nil || arr.gsub(/,/,"") == ""
		return "#{err_msg}データなし"
	end

	arr = NKF.nkf("-sS",arr).split ","

	for a in 0..17
		for b in 0..17
			for c in 0..17
				if a == b || b == c  || a == c || a > tou || b > tou || c > tou
					if arr[a * 18 * 18 + b * 18 + c] != "" && arr[a * 18 * 18 + b * 18 + c] != nil
						return "#{err_msg}データエラー 正しくはnil #{a}-#{b}-#{c} '#{arr[a * 18 * 18 + b * 18 + c]}'"
					end
				else#if a < b 
					if arr[a * 18 * 18 + b * 18 + c] == "" || arr[a * 18 * 18 + b * 18 + c] == nil
						return "#{err_msg}データエラー 正しくはnil以外 #{a}-#{b}-#{c} '#{arr[a * 18 * 18 + b * 18 + c]}'"
					end
				end
			end
		end
	end

	get_timing = get_t_check(get_t[6])

	for i in 2..tou
		if get_timing != get_t_check(get_t[tou + 5])
			return "3連単　ソースによってオッズ取得時間が違う　エラー"
		end
	end

	return get_t_check(get_t[6])
end

def get_t_check(get_t)
	if get_t =~ /確定オッズ/
		return "確定オッズ"
	elsif get_t =~ /09時30分/ && get_t =~ /オッズ/
		return "朝一オッズ"
	elsif get_t =~ /年/ && get_t =~ /月/ && get_t =~ /日/
		st1 = get_t.index(%!日!) + 1
		en1 = get_t.index(%!時!) - 1 

		st2 = get_t.index(%!時!) + 1
		en2 = get_t.index(%!分!) - 1 

		get_time = "#{get_t.slice(st1..en1)}".to_i * 100 + "#{get_t.slice(st2..en2)}".to_i

		if get_time < 1100
			return "朝一オッズ"
		elsif get_time >= 1100 && get_time < 1700
			return "正午オッズ"
		elsif get_time >= 1700
			return "前売オッズ"
		else
			return "取得時間エラー1"
		end
	else
		return "取得時間エラー2"
	end
end

def dub_chk(t_no,race_code,err_flg)
	kako = PostgerSQL_ctrl("ダブリチェック","select syu_hantei from keibadata where t_no < #{t_no} and race_code = '#{race_code}';","")

	if kako != nil
		kako.each do |kako2|
			kako2 = NKF.nkf("-sS",kako2).split","
			for i in 0..6
				if err_flg[i] =~ /オッズ/ && kako2[i+8] == err_flg[i]
					err_flg[i] = "ダブリ：#{err_flg[i]}"
				end
			end
		end
	end

	return err_flg
end

def kigou(err_flg)
	err_kigou = Array.new(7,"")

	for i in 0..6
		if err_flg[i] == nil || err_flg[i] == ""
			err_kigou[i] = "Y"
		elsif err_flg[i] =~ /データなし/
			err_kigou[i] = "-"
		elsif err_flg[i] =~ /エラー/
			err_kigou[i] = "E"
		elsif err_flg[i] =~ /ダブリ：/
			err_kigou[i] = "D"
		elsif err_flg[i] == "確定オッズ"
			err_kigou[i] = "K"
		elsif err_flg[i] == "朝一オッズ"
			err_kigou[i] = "A"
		elsif err_flg[i] == "正午オッズ"
			err_kigou[i] = "P"
		elsif err_flg[i] == "前売オッズ"
			err_kigou[i] = "M"
		else
			err_kigou[i] = "Z"
		end
	end
  return "#{err_kigou.join","},*,#{err_flg.join","}"
end

def data_get_timing_check
	ct = 0
	all_data = PostgerSQL_ctrl_no_fetch("データ全取得","select t_no,race_code,file_name,get_t,tf,wk,ur,wide,ut,srf,srt,memo from keibadata where syu_hantei like '%*,,,,,,,' order by t_no;","")
	if all_data != nil
		all_data.fetch do |t_no,race_code,file_name,get_t,tf,wk,ur,wide,ut,srf,srt,memo|

			err_flg = Array.new(7,"")

			get_t = NKF.nkf("-sS",get_t).split","

			if memo != nil
				memo = NKF.nkf("-sS",memo)
			end

			err_flg[0] = tf_check(race_code,tf,get_t)
			if err_flg[0] =~ /エラー/
				tou = - 1
			else
				tou = (NKF.nkf("-sS",tf).split ",").length / 6 - 1
				err_flg[1] = wk_check(wk,get_t)
				err_flg[2] = ur_check(ur,tou,get_t)
				err_flg[3] = wide_check(wide,tou,get_t)
				err_flg[4] = ut_check(ut,tou,get_t)
				err_flg[5] = srf_check(srf,tou,get_t)
				err_flg[6] = srt_check(srt,tou,get_t)
				err_flg = dub_chk(t_no,race_code,err_flg)
			end

			err_flg = kigou(err_flg)

			PostgerSQL_ctrl("更新","update keibadata set syu_hantei = '#{err_flg.gsub(/'/,"''")}' where t_no = #{t_no};","")
			ct += 1
			puts "#{t_no}終了 #{race_code}"
		end
	end
	return ct
end



def backup_tabledata(fol)
	fi = File.open("#{fol}backup\_tabledata#{Date.today.strftime("%Y%m%d")}.txt","w")
	tab = ["keibadata","keibadata_kekka","keiba_bet","keibaoddstext"]
	tab.each do |table|
	command = "SELECT   pg_class.relname,   pg_attribute.attname,   pg_attribute.atttypmod,   pg_attribute.attnum,   pg_attribute.attalign,   pg_attribute.attnotnull,   pg_type.typname  FROM   pg_class,   pg_attribute,   pg_type  WHERE   pg_class.oid = pg_attribute.attrelid and   pg_attribute.atttypid = pg_type.oid and   pg_class.relname='#{table}' and   pg_attribute.attnum > 0  ORDER BY   pg_attribute.attnum; "
	fi.puts "table_name:#{table}"
	dat  = PostgerSQL_ctrl_no_fetch("列名、条件出力",command,"")
	dat.fetch do |a|
	fi.puts "#{a[3]}列目:#{a[1]},#{a[6]}"
	end
	fi.puts "\n"
	end
	fi.close
end


def backup_database(fol,table,ken,kou)
	ct = PostgerSQL_ctrl("レコードの最後取得","select count(*) from #{table};","")

	if table == "keibaoddstext"
		fi = File.open("#{fol}backup\_#{table}#{Date.today.strftime("%Y%m%d")}-1-.txt","w")
		tno = "odds_no"
	else
		fi = File.open("#{fol}backup\_#{table}#{Date.today.strftime("%Y%m%d")}.txt","w")
		tno = "t_no"
	end

	for no in 1..ct[0]

		if table == "keibaoddstext" && no % 2000 == 0
			fi.close
			fi = File.open("#{fol}backup\_#{table}#{Date.today.strftime("%Y%m%d")}-#{no}-.txt","w")
		elsif no != 1 then 
			fi.puts ken
		end

		arr = PostgerSQL_ctrl("#{table}一行取得","select * from #{table} where #{tno} = #{no};","")
		fi.puts arr.join"#{kou}\n"
		puts "#{table}-#{ct[0]}中-#{no}終了"
	end

	fi.close
end



#↓　競馬は関係ないが、プログラムのバックアップ
def ruby_backup(fol)

	file = File.open("#{fol}rubyfile-ruby_ex2-backup\_#{Time.now.strftime("%Y%m%d")}.txt","w")
	ct = 0
	Dir["c:/ruby_ex2/*.rb"].each do |fil|
		file.puts "---#{fil}開始---"
		file.puts open(fil).read
		file.puts "---#{fil}終了---"
		ct += 1
		puts ct
	end
	file.close

	file = File.open("#{fol}rubyfile-keiba-backup\_#{Time.now.strftime("%Y%m%d")}.txt","w")
	ct = 0
	Dir["C:/keiba/ruby/*.rb"].each do |fil|
		file.puts "---#{fil}開始---"
		file.puts open(fil).read
		file.puts "---#{fil}終了---"
		ct += 1
		puts ct
	end
	file.close

end

#↓　実作業
def run_pro
	end_flg = ""#←ダミー
	until end_flg == 1#←ダミーの条件
		$err = File.open("C\:\\ruby\_ex2\\keiba_error\\keiba_#{Date.today.to_date}.txt","a")

		jikkou = Date.today
		today_code,kekka_code,next_day = kaisai_code_get(jikkou)

		if today_code.length >= 1
			puts "本日のレース#{today_code.length}会場"
		elsif jikkou == next_day - 1
			msg = "本日のレースなしだが、\n明日レース開催\nプログラム実行継続"
			puts msg
			puts mail_send("0",msg,msg)
		else
			puts "本日のレースなし\n次回は#{next_day.strftime("%Y年%m月%d日")}開催"
			puts mail_send("0","","本日のレースなし\n次回は#{next_day.strftime("%Y年%m月%d日")}開催")
			break#この行を消すと無限ループのはず
		end

		#結果取得
		until Time.now.strftime("%H%M").to_i >= 800
			puts Time.now.strftime("%H%M%S")
			sleep 60
		end

		if Time.now.strftime("%H%M").to_i >= 930
			puts mail_send("1","","時間が無いので、朝の結果取得無し")
		else
			kekka_data_get(kekka_code,1,"朝")
		end

		if today_code.length >= 1
			today_code = kaisai_to_racecode(today_code)
			#オッズ取得1
			odds_data_get(today_code,2,"前売り")

			until Time.now.strftime("%H%M").to_i >= 940
				puts Time.now.strftime("%H%M%S")
				sleep 60
			end

			#オッズ取得2
			odds_data_get(today_code,3,"9時半")

			until Time.now.strftime("%H%M").to_i >= 1210
				puts Time.now.strftime("%H%M%S")
				sleep 60
			end

			#オッズ取得3
			odds_data_get(today_code,4,"正午")
		end

		until Time.now.strftime("%H%M").to_i >= 1800#←最終レース終了後1時間程度後に開始
			puts Time.now.strftime("%H%M%S")
			sleep 60
		end

		#明日のレースのチェックと今日の結果取得
		today_code,kekka_code,next_day = kaisai_code_get(jikkou + 1)

		kekka_data_get(kekka_code,5,"夕方")
		dgtc_msg = "結果更新に伴い、データ取得タイミング更新終了\n#{data_get_timing_check}件"
		puts mail_send("6","#{dgtc_msg}","#{dgtc_msg}")

		if jikkou.month != next_day.month
			puts mail_send("7","データベースバックアップ開始\n約2時間は電源切らない事！","データベースバックアップ開始\n約2時間は電源切らない事！")
			bc = "C\:\\backup\\keiba\_database\_backup\\"
			["keibadata","keibaoddstext","keibadata_kekka"].each do |tab|
				backup_database(bc,tab,"ken-end","kou-end")
			end
			ruby_backup(bc)
			backup_tabledata(bc)
			puts mail_send("8","データベースバックアップ終了","データベースバックアップ終了")
		end

		if today_code.length == 0
			puts mail_send("9","データ取得終了\n次回は#{next_day.strftime("%Y年%m月%d日")}開催","データ取得終了\n次回は#{next_day.strftime("%Y年%m月%d日")}開催")
			break#この行を消すと無限ループのはず
		end

		until jikkou != Date.today || end_flg == 1
			puts "#{jikkou.to_date}-#{Time.now.strftime("%H%M%S")}一時間待ち"
			sleep 3600
		end
	$err.close
	end
end
#↑　実作業

ruby_backup("C\:\\ruby\_ex2\\ruby\_file\_backup\\")
run_pro
