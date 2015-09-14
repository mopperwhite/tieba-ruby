#!/usr/bin/env ruby
#encoding=utf-8
require "net/http"
require "nokogiri"
require "yaml"
require "uri"
$home=File.join Dir.home,".tieba","monitor"
$config=File.join $home,"config.rb"
$bawu_record=File.join $home,"bawu-record.yaml"
$personal_record=File.join $home,"visitor-record.yaml"
$header={
        "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Encoding"=>"deflate,sdch",
        "Accept-Language"=>"zh-CN,zh;q=0.8",
        "Connection"=>"keep-alive",
        "User-Agent"=>"Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.153 Safari/537.36",
}

$ba_list=[]
$personal_list=[]
$ba_data={}
$personal_data={}
FileUtils.mkpath $home unless File.exists? $home
$http=Net::HTTP.new "tieba.baidu.com"

def parse_judgement_page ba_name
        res=$http.get "/bawu2/platform/listBawuTeamInfo?word=#{URI::encode ba_name}&ie=UTF-8",$header
        doc=Nokogiri::HTML.parse res.body
        doc.xpath("//a[@class='user_name']").map{|a| a.text}
end
def parse_personal_page id
        res=$http.get "/home/main?un=#{URI::encode id}&from=live&ie=utf-8",$header
        doc=Nokogiri::HTML.parse res.body
        doc.xpath("//li[@class='visitor_card']/a[@target='_blank']").map{|a|
                /\/home\/main\?un=(.+?)&fr=home/===a["href"]
                $1
        }
end

def monitor_ba ba_name
        $ba_list.push(ba_name)
end
def monitor_id ba_name
        $personal_list.push(ba_name)
end
instance_eval File.read $config

$ba_list.each do|ba_name|
        $ba_data[ba_name]=parse_judgement_page ba_name
        sleep 3
end
$personal_list.each do|id|
        $personal_data[id]=parse_personal_page id
        sleep 3
end

status=0
if File.exists? $bawu_record
        rdata=YAML.load_file $bawu_record
        ($ba_data.keys&rdata.keys).select{|k| $ba_data[k]!=rdata[k]}.each do |k|
                puts "【#{k}吧 发生吧务变动】"
                puts "上任:",$ba_data[k]-rdata[k] unless ($ba_data[k]-rdata[k]).empty?
                puts "离任:",rdata[k]-$ba_data[k] unless (rdata[k]-$ba_data[k]).empty?
                status=233
        end
end
File.write $bawu_record,$ba_data.to_yaml

if File.exists? $personal_record
        rdata=YAML.load_file $personal_record
        ($personal_data.keys&rdata.keys).select{|k| $personal_data[k]!=rdata[k]}.each do |k|
                puts "【#{k} 的个人页面 有新访问者】"
                puts $personal_data[k]-rdata[k]
                status=233
        end
end
File.write $personal_record,$personal_data.to_yaml


exit status
