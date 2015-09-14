#!/usr/bin/env ruby
#encoding=UTF-8
require 'net/http'
require 'cgi'
require 'yaml'
require 'nokogiri'
require 'json'
class MozillaCookieJarLogger
        attr_reader :http,:header
        def initialize cookies_file,host
                @host=host
                @http=Net::HTTP.new @host
                @cookies_file=cookies_file
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
                @http.get path,@header,&block
        end
        def post path,data,&block
                res=@http.post path,URI.encode_www_form(data),@header,&block
        end
        def parse path,&block
                res=self.get path
                doc=Nokogiri::HTML res.body
                return block.call(doc) unless block==nil
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
module Tieba
        class Logger<MozillaCookieJarLogger
                def initialize cookies_file
                        super cookies_file,"tieba.baidu.com"
                end
                def update_tokens!
                        res=Net::HTTP.get_response("http://tieba.baidu.com/mo/",URI::encode_www_form(@header))
                        @waptoken=regmatch /http:\/\/tieba.baidu.com\/mo\/([\%w-]*)\/m\?/,res.body
                end
                def waptoken
                        @waptoken=update_tokens! if @waptoken==nil
                        @waptoken
                end
                def get path,&block
                        super "/mo/#{waptoken}path",&block
                end
                def post path,data,&block
                        super "/mo/#{waptoken}path",data,&block
                end
                def login?
                        /的i贴吧<\/a><\/div>/===self.get("/").body.force_encoding("UTF-8")
                end
                def username
                        @username=(/>([^>]+?)的i贴吧<\/a><\/div>/.match self.get("/").body.force_encoding("UTF-8") )[1] if @username==nil
                        @username
                end
                def favorite_bas
                        @favorite_bas=favorite_bas! if @favorite_bas==nil
                        @favorite_bas
                end
                def favorite_bas!
                        doc=self.parse '/m?tn=bdFBW'
                        table=doc.css"table.tb"
                        table.children.map{ |tr| Ba.new self,tr.at("a").text }
                end
                def inspect
                        "#<#{self.class.name}:'#{username}' at '#{@cookies_file}'>"
                end
                def update_reading_setting!
                        doc=self.parse "/mo/dont_no_why_but_worked/urs?src=3"
                        def get_selected_value doc,name
                                return doc.xpath(".//select[@name='#{name}']")
                                .children.detect{|option| option["selected"]}["value"].to_i
                        end
                        @threads_number_in_ba_page=get_selected_value(doc,"frsrn")
                        @posts_number_in_thread_page=get_selected_value(doc,"pbrn")
                end
                def threads_number_in_ba_page
                        update_reading_setting! if @threads_number_in_ba_page==nil
                        @threads_number_in_ba_page
                end
                def posts_number_in_thread_page
                        update_reading_setting! if @posts_number_in_thread_page==nil
                        @posts_number_in_thread_page
                end
                def ban baname,username
                        
                end
                def [] name #选择吧
                        favorite_bas.detect{|ba| name===ba.name}
                end
        end

        
        module Content
                #内容
                #存有数据
                #Thread,Post和SubPost
                #有poster
                #支持删封操作
                #check_act:删封 除了post_act外还要确认一下
                #有编号
                #可以被搜索
                #inspect的时候把内容展示出来
                attr_reader :data,:poster,:index
                def remove
                end
                def ban
                end
        end
        module Container
                #容器
                #吧、楼和层都属于容器
                #可以发贴(post)
                #post_act:发贴 在一个地址向一个位置POST
                #一页一页更新
                #通过each方法访问，访问到页尾时换到下一页
                #each无block时返回一个Enumator用来访问
                #用create_enumator创建
                #可以搜索内容
                #最大搜索页面数 :max_page_number
                attr_reader :members
                attr_accessor :max_page_number
                def each
                end
        end

        
        class Ba
                include Container
                attr_reader :name,:path
                def initialize logger,name
                        raise TiebaException.new"Anonymous user." unless logger.login?
                        @name=name
                        @logger=logger
                        @path="/m?kw=#{URI::encode @name}"
                        @max_post_number=nil
                        StopIteration
                end
                def update_ba_info!
                        doc=@logger.parse @path
                        doc.at(".//table/tr") do |tr|
                                @level=/\(等级(\d*)\)/.match(tr[0].text)[1].to_i
                                if tr[1].at("a")
                                        @sign_link=tr[1].at("a")["href"]
                                else
                                        @sign_link=""
                                end
                        end
                end
                def level
                        update_ba_info! if @level==nil
                        @level
                end
                def sign_link
                        update_ba_info! if @level==nil
                        @sign_link
                end
                def sign
                        unless sign_link==""
                                get sign_link
                        else
                                raise SignedException.new @name
                        end
                end
                def page index #start from 0
                        doc=@logger.parse "/m?kw=#{URI::encode @name}&pn=#{index*@logger.threads_number_in_ba_page}"
                        doc.css("div.i").map do |div|
                                kz= /kz=(\d*)/.match(div.at("a")["href"])[1]
                                title= /^\d*\.&#160;(.*)$/.match(div.at("a").text)[1]
                                fine=div.xpath(".//span[@class='light' and text()='精']").empty?
                                top=div.xpath(".//span[@class='light' and text()='顶']").empty?
                                Thread.new @logger,kz,title,fine,top
                        end
                end
        end
        class Thread
                include Container,Content
                attr_reader :kz,:title,:logger,:fine,:top,:path
                def initialize logger,kz,title=nil,fine=false,top=false
                        @logger=logger
                        @kz=kz
                        @title=title
                        @path="/m?kz=#{@kz}"
                        @fine=fine
                        @top=top
                end
                def page index
                        doc=@logger.parse"/m?kz=#{@kz}&pn=#{index*@logger.posts_number_in_thread_page}"
                        doc.css("div.d").children.map do |li|
                                code=li.display
                                text=li.text
                                poster=li.at("span.g").text
                                date=li.at("span.b").text
                                #http://wapp.baidu.com/m?tn=bdPBC&pid=30646475865&templeType=2 #delete link
                                #http://wapp.baidu.com/m?tn=bdFIL&word=无神论者&un=爱七情RYYO&act=2  #ban
                                li.at("a.reply_to")
                                li.at("a.banned")["href"]
                                li.at("a.delete")
                        end
                end
        end
        class Post
                include Container,Content
        end
        class SubPost
                include Content
        end
        
        class TiebaException<Exception;end
        class SignedException<TiebaException;end
        module_function
        def load_users_from usernames_file
                d=YAML.load(open(usernames_file))
                d["usernames"].map do |un|
                        fp=File.join(d["dir"],un+".cookies")
                        Logger.new fp
                end
        end
end
ul=Tieba.load_users_from "usernames.yaml"
u=ul[0]
require 'pry'
pry
