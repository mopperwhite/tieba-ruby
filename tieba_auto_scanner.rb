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
        def [] name #选择吧
                Ba.new self,name
                #~ favorite_bas.detect{|ba| name===ba.name}
        end
end
class Ba
        attr_reader :name,:path
        def initialize logger,name
                #~ unless logger.login?
                        #~ puts logger.get("/").body.force_encoding("UTF-8")
                        #~ raise TiebaException.new"Anonymous user."
                #~ end
                @name=name
                @logger=logger
                @path="/m?kw=#{URI::encode @name}"
                @max_post_number=nil
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
        def webpage index
                doc=@logger.webparse "/f?kw=#{URI::encode @name}&ie=utf-8&pn=#{index*50}"
                doc=Nokogiri::HTML.parse doc.at("//code[@id='pagelet_html_frs-list/pagelet/thread_list']/comment()").text
                doc.xpath(".//li[contains(@class,'j_thread_list') and @data-field]").map do |li|
                        data=JSON.load li["data-field"].gsub('&quot;','"')
                        username=data["author_name"]
                        kz=data["id"]
                        top= data["is_top"]==1
                        fine= data["is_good"]==1
                        live= data["is_portal"]==1
                        reply_num=data["reply_num"]
                        /^\s*(.+?)\s*$/===li.at(".//div[contains(@class,'threadlist_title')]").text
                        title=$1
                        sn=li.at(".//div[contains(@class,'threadlist_abs')]")
                        if sn and /^\s+(.+?)\s+$/===sn.text
                                summary=$1
                        else
                                summary=""
                        end
                        ThreadPost.new(@logger,kz,username,title,summary,reply_num,fine,top,live)
                end
        end
        def scan filters,&block
                bf=filters.reject{|f| f.white?}
                wf=filters.select{|f| f.white?}
                wpdata=webpage(0)
                blist=wpdata.select{|t| bf===t}
                wlist=wpdata.select{|t| wf===t}
                rlist=(blist-wlist)
                return rlist.map{|t| block.call(t)} if block_given?
                return rlist
        end
end
class ThreadPost
        @@keys=[:title,:username,:summary,:fine,:top,:live,:kz,:reply_num]
        class Filter
                @@keys=ThreadPost.class_variable_get:"@@keys"
                def initialize type=:black,&b
                        init_funcs
                        set &b if block_given?
                        @type=type;
                end
                def set &b
                        instance_eval &b
                end
                def white?
                        @type==:white
                end
                def init_funcs
                        @@keys.each do |name|
                                define_singleton_method(name) do |value=nil|
                                        unless value==nil then instance_variable_set :"@#{name}",value
                                        else instance_variable_get :"@#{name}"
                                        end
                                end
                        end
                end
                def advanced &b
                        @advanced=b
                end
                def === thread
                        ( @advanced==nil or @advanced.call(thread)) and
                        @@keys.all?{ |n|
                                send(n)==nil or
                                send(n)===thread.send(n)
                        }
                end
                alias :"=~" ===
        end
        attr_reader :kz,:title,:username,:logger,:fine,:top,:live,:path,:reply_num,:summary
        def initialize logger,kz,username,title=nil,summary=nil,reply_num=0,fine=false,top=false,live=false
                @logger=logger
                @kz=kz.to_s
                @title=title
                @summary=summary
                @username=username
                @path="/m?kz=#{@kz}&pinf=1_2_0"#后面这个打开管理模式
                @fine=fine
                @top=top
                @live=live
                @reply_num=reply_num
                #~ [:username,:content,].each do |n|
                        #~ define_singleton_method(n)do
                                #~ update_info! if instance_variable_get(:"@#{n}")==nil
                                #~ instance_variable_get(:"@#{n}")
                        #~ end
                #~ end
        end
        def update_info!
                doc=@logger.parse @path
                @title=doc.at(".//div[@class='bc p']/strong").text
                @content=doc.at(".//div[@class='i']").text
                @username=doc.at(".//span[@class='g']/a").text
        end
        def remove
                doc=@logger.parse @path
                remove_link=doc.at(".//a[text()='删主题']")
                raise TiebaException,"No permission to remove." unless remove_link
                /(\/m\?.*)$/===remove_link["href"]
                check_page=@logger.parse $1
                check_link=check_page.at(".//a[text()='确认删除']")
                /(\/m\?.*)$/===check_link["href"]
                @logger.get $1
                self
        end
end
class Array
        def === x#方便起见
                super x or self.any?{|i| i===x;}
        end
        def to_h#应付树莓派的低版本(1.9)ruby
                h=Hash.new
                each{ |pair|
                        h[pair[0]]=pair[1]
                }
                h
        end
end


$home=File.join Dir.home,".tieba","auto_scanner"
$cookies_dir=File.join Dir.home,".tieba","cookies"
$logging_file=File.join $home,"loggings",Time.now.to_s+".yaml"
$config=File.join $home,"config.rb"

$filters_list=[]
$loggings=[]

def add_filter type=:black,&b
        filter=ThreadPost::Filter.new type,&b
        $filters_list.push filter
end
def login_as name
        $cookies_file=File.join $cookies_dir,name+".cookies"
        $logger=Logger.new($cookies_file,0.5)
end
def scan_threads_at name,&block
        ba=$logger[name]
        threads=ba.scan($filters_list).each{|t| block.call t}
        $loggings.push({:ba=>name,:threads=>threads}) unless threads.empty?
end
def clear_filters
        $filters_list.clear
end

if __FILE__==$0
        instance_eval File.read($config)
        open($logging_file,'w'){|f|f.write $loggings.to_yaml}unless $loggings.empty?
end
