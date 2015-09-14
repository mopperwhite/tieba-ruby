#!/usr/bin/env ruby
#encoding=UTF-8
require 'net/http'
require 'cgi'
require 'json'
require 'yaml'
require 'nokogiri'
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

class TiebaException<Exception;end
class Logger<MozillaCookieJarLogger
        def initialize cookies_file,pause_time=0
                super cookies_file,"wapp.baidu.com",pause_time
                @webhttp=Net::HTTP.new "tieba.baidu.com"
        end
        def webget path,&block
                sleep(@pause_time)
                @webhttp.get path,@header,&block
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
        def favorite_bas
                favorite_bas! if @favorite_bas==nil
        end
        def favorite_bas!
                doc=self.parse '/m?tn=bdFBW'
                table=doc.css"table.tb"
                @favorite_bas=table.children.map do |tr|
                        a=tr.at("a")
                        {
                                :name=>a.text,
                                :url=>a[:href],
                        }
                end
        end
        def inspect
                "#<#{self.class.name}:'#{username}' at '#{@cookies_file}'>"
        end
        def signba url
                signlink=parse(url)
                        .at("//table/tr/td[@style='text-align:right;']/a")
                raise RuntimeError.new("无签到标记，未关注或已签到") if signlink.nil?
                raise RuntimeError.new("未成功") if parse(signlink[:href]).at("span.light").nil?
        end
        def signall
                favorite_bas.map do |ba|
                        begin
                                signba ba[:url]
                                puts "- #{ba[:name]}: Done"
                        rescue =>e
                                warn "#{username}@#{ba[:name]}: #{e}"
                                sleep 2
                                next
                        end
                        sleep Random.rand 3..9
                end
        end
end
$config=File.join Dir.home,".tieba","usernames.yaml"

config=YAML.load_file($config)
config["usernames"].each do |name|
        logger=Logger.new File.join(Dir.home,".tieba","cookies","#{name}.cookies")
        puts "for #{name}"
        logger.signall
end
