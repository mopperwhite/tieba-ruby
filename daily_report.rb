#!/usr/bin/env ruby
require 'nokogiri'
require 'net/http'
require 'cgi'
require 'json'

class MozillaCookieJarLogger
        attr_reader :http,:header
        attr_accessor :pause_time
        def initialize cookies_file,host,pause_time=0
                @host=host
                @http=Net::HTTP.new @host
                @cookies_file=cookies_file
                @pause_time=pause_time
                load_file
                @header={
                        "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                        "Accept-Encoding"=>"deflate,sdch",
                        "Accept-Language"=>"zh-CN,zh;q=0.8",
                        "Connection"=>"keep-alive",
                        "User-Agent"=>"Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.153 Safari/537.36",
                        "Cookie"=>@cookies_data,
                }
        end
        def get path,&block
                sleep(@pause_time)
                @http.get path,@header,&block
        end
        def post path,data,&block
                sleep(@pause_time)
                @http.post path,URI.encode_www_form(data),@header,&block
        end
        def parse path,&block
                res=self.get path
                doc=Nokogiri::HTML res.body
                return block.call(doc) if block_given?
                doc
        end
        def parse_file! jar_file_name
                @cookies=open jar_file_name do|file|
                        lines=file.reject{|line| line.start_with?"#" or (values=line.split).empty?}
                        @cookies_list=lines.map do |line|
                                keys=[:domain,:initial_dot,:path,:secure,:expires,:name,:value]
                                h=keys.zip(line.split).to_h
                        end
                end
        end
        def cookies
                @cookies=parse_file! @cookies_file if @cookies==nil
                @cookies
        end
        def load_file
                @cookies_data=cookies.map {|h|
                                "#{h[:name]}=#{h[:value]}" }.join "; "
        end
        def regmatch reg,str
                reg.match(str)[1]
        end
end
class Logger<MozillaCookieJarLogger
        def initialize cookies_file,pause_time=0
                super cookies_file,"wapp.baidu.com",pause_time
                @webhttp=Net::HTTP.new "tieba.baidu.com"
                @post_header={
                        "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                        "Accept-Encoding"=>"gzip, deflate",
                        "Accept-Language"=>"zh-CN,zh;q=0.8",
                        "Cache-Control"=>"max-age=0",
                        "Connection"=>"keep-alive",
                        "Content-Length"=>"247",
                        "Content-Type"=>"application/x-www-form-urlencoded",
                        "Host"=>"tieba.baidu.com",
                        "Origin"=>"http://tieba.baidu.com",
                        "Referer"=>"http://tieba.baidu.com/mo/q-acaa53997b818983564575223b77cd3e.3.1432903969.1.Njk9fkAOVEl5--168763E130C368EF6605F40B38588634%3AFG%3D1--1-3-0----wapp_1432903956769_477/submit",
                        "User-Agent"=>"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/41.0.2272.89 Safari/537.36",
                        "Cookie"=>@cookies_data,
                }
        end
        def webget path,&block
                sleep(@pause_time)
                @webhttp.get path,@header,&block
        end
        def webpost path,data,referer=nil,&block
                @webhttp.post path,URI.encode_www_form(data),@post_header,&block
        end
        def webparse path,&block
                res=self.webget path
                doc=Nokogiri::HTML res.body
                return block.call(doc) if block_given?
                doc
        end
        def login?
                /的i贴吧<\/a><\/div>/===self.get("/").body.force_encoding("UTF-8")
        end
        def username
                @username=(/>([^>]+?)的i贴吧<\/a><\/div>/.match self.get("/").body.force_encoding("UTF-8") )[1] if @username==nil
                @username
        end
        def inspect
                "#<#{self.class.name}:'#{username}' at '#{@cookies_file}'>"
        end
        def get_ba_link ba
                parse("/m?tn=bdFBW&tab=favorite")
                .at("//div[@class='d']/table[@class='tb']/tr/td/a[text()='#{ba}']")
                .get_attribute("href")
        end
        def post_thread ba,title,content
                ba_link=get_ba_link ba
                /baidu\.com(\/.*)$/===ba_link
                form=webparse($1).at("//div[@class='d h']/form[@method='post']")
                data={}
                form.xpath("//input[@type='hidden']").each do |h|
                        data[h.get_attribute("name").to_sym]=h.get_attribute("value")
                end
                data[:ti]=title
                data[:co]=content
                data[:sub1]="发贴"
                /baidu\.com(\/.*\/)m\?/===ba_link
                path=$1+"submit"
                pp data
                res=webpost path,data,ba_link
                File.open("233.html",'w'){|f| f.write res.body}
        end
end

$home=File.join Dir.home,".tieba","daily_report"
$cookies_dir=File.join Dir.home,".tieba","cookies"
$contents=[]

def login_as name
        $cookies_file=File.join $cookies_dir,name+".cookies"
        $logger=Logger.new($cookies_file,0.5)
end
def update_content
        def append_content content
                $contents.push(content)
        end
        Dir[File.join($home,"conf.d","*.rb")].map{|f|
                instance_eval File.open(f).read
        }
end

require 'pry'
require 'pp'
def main
        login_as "KUChanBot"
        puts $logger.login?
        $logger.post_thread("转基因","23333","test4")
        pry
        return
        update_content
        login_as "转盟联合水军01"
        $logger.post_thread("无神论者",
        "[KUChan每日简报] #{Time.now.strftime "%Y-%m-%d"}",
        $contents.map{|c| "[#{c[:source]}] #{c[:title]}\nSummary:#{c[:content].force_encoding"UTF-8"}"}.join("\n----\n"))
end

main if __FILE__==$0
